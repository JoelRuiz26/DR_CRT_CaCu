#' Escribe un solo registro en formato RIS (formato estandar que importa
#' Rayyan/EndNote/Zotero). TY=JOUR para todo (PubMed y ClinicalTrials.gov)
#' por compatibilidad simple de importacion.
ris_record <- function(row) {
  lines <- c("TY  - JOUR")
  if (!is.na(row$title)) lines <- c(lines, paste("TI  -", row$title))
  for (au in row$authors[[1]]) lines <- c(lines, paste("AU  -", au))
  if (!is.na(row$journal)) lines <- c(lines, paste("JO  -", row$journal))
  if (!is.na(row$year)) lines <- c(lines, paste("PY  -", row$year))
  if (!is.na(row$abstract)) lines <- c(lines, paste("AB  -", gsub("\\n", " ", row$abstract)))
  if (!is.na(row$doi)) lines <- c(lines, paste("DO  -", row$doi))
  if (!is.na(row$url)) lines <- c(lines, paste("UR  -", row$url))
  if (!is.na(row$pmid)) lines <- c(lines, paste("AN  -", row$pmid))
  if (!is.na(row$source_id) && row$source == "clinicaltrials") lines <- c(lines, paste("C1  -", row$source_id))
  lines <- c(lines, paste("N1  -", row$source, row$source_id), "ER  - ")
  lines
}

#' Escribe el archivo RIS completo para importar a Rayyan.
write_ris <- function(articles, path) {
  all_lines <- unlist(purrr::map(seq_len(nrow(articles)), function(i) ris_record(articles[i, ])))
  writeLines(all_lines, path)
  invisible(path)
}

#' Excluye antes de Rayyan por razones ESTRUCTURALES (metadatos ya
#' asignados por NLM/ClinicalTrials.gov, no texto de titulo/resumen):
#' decision explicita del usuario, 2026-10-06, ver DECISIONS.md.
#' - ClinicalTrials.gov con estado WITHDRAWN (retirado antes de inscribir a
#'   un solo paciente) o NOT_YET_RECRUITING (registrado pero aun no
#'   reclutando a nadie): no pueden tener ningun dato que aportar, no es
#'   una exclusion de "probablemente irrelevante", es que el estudio no
#'   ha ocurrido todavia. Sin riesgo de perder evidencia real.
#' - PubMed con publication_type "Review"/"Systematic Review": evidencia
#'   secundaria, no primaria (el protocolo pide diseños primarios: in
#'   vitro, in vivo, fase I-III, observacional). Se separan para mineria
#'   manual de referencias (ya planeada para Capistrano/Candelaria/Low/
#'   Julian, aqui se extiende a TODAS las revisiones que la propia
#'   busqueda encontro), no se descartan sin mas.
#' - PubMed con publication_type "Retracted Publication"/"Retraction of
#'   Publication": retirado formalmente por la revista, no cuenta como
#'   evidencia valida bajo ningun criterio.
#' - PubMed con publication_type "Editorial"/"Comment"/"Letter"/"News":
#'   mismo argumento que las revisiones, evidencia secundaria.
#' - PubMed con publication_type "Clinical Trial Protocol": publica el
#'   diseño de un ensayo que aun no reporta resultados — mismo caso que
#'   NOT_YET_RECRUITING, no hay efecto de combinacion que extraer todavia.
classify_metadata_exclusions <- function(articles) {
  ct_sin_datos <- articles$source == "clinicaltrials" &
    articles$publication_type %in% c("WITHDRAWN", "NOT_YET_RECRUITING")
  es_revision <- articles$source == "pubmed" &
    !is.na(articles$publication_type) &
    stringi::stri_detect_fixed(articles$publication_type, "Review")
  es_retractado <- articles$source == "pubmed" &
    !is.na(articles$publication_type) &
    stringi::stri_detect_fixed(articles$publication_type, "Retract")
  es_secundario_sin_datos <- articles$source == "pubmed" &
    !is.na(articles$publication_type) &
    (stringi::stri_detect_fixed(articles$publication_type, "Editorial") |
     stringi::stri_detect_fixed(articles$publication_type, "Comment") |
     stringi::stri_detect_fixed(articles$publication_type, "Letter") |
     stringi::stri_detect_fixed(articles$publication_type, "News") |
     stringi::stri_detect_fixed(articles$publication_type, "Clinical Trial Protocol"))

  articles$exclusion_reason <- dplyr::case_when(
    ct_sin_datos ~ "ensayo_sin_datos_posibles",
    es_retractado ~ "retractado",
    es_revision ~ "revision_evidencia_secundaria",
    es_secundario_sin_datos ~ "secundario_o_sin_resultados",
    TRUE ~ NA_character_
  )
  articles
}

#' Exporta a Rayyan (RIS) el corpus combinado (SIN deduplicar en R — ver
#' DECISIONS.md 2026-10-15: Rayyan ya deduplica al importar por
#' DOI/titulo/autores/anio, asi que reimplementar esa misma logica en R era
#' trabajo duplicado e innecesariamente "casero" frente a un algoritmo ya
#' publicado y mantenido. El conteo de "duplicados eliminados" del diagrama
#' PRISMA ahora se llena DESPUES, con lo que reporte Rayyan tras el import,
#' no antes en R), menos las exclusiones estructurales de
#' `classify_metadata_exclusions()` (eso si se queda en R: son reglas sobre
#' un campo de metadato que Rayyan no tiene forma de evaluar — el estado de
#' ClinicalTrials.gov o el tipo de publicacion de PubMed — no son
#' deduplicacion). Nada de filtro por presencia de fármaco en el texto — el
#' nombre de fármaco ya es un requisito obligatorio de la busqueda (etapa
#' 1), asi que exigirlo otra vez aqui seria redundante para PubMed y, para
#' ClinicalTrials.gov, incorrectamente estricto (su buscador confirma el
#' fármaco en campos del registro que no siempre estan en el resumen
#' descargado). Decision explicita del usuario, 2026-09-30. Ver
#' DECISIONS.md.
export_screening_set <- function(articles_combined, cfg) {
  dir <- cfg$paths$stage3
  fs::dir_create(dir)

  classified <- classify_metadata_exclusions(articles_combined)
  to_screen <- dplyr::filter(classified, is.na(exclusion_reason))
  revisiones <- dplyr::filter(classified, exclusion_reason == "revision_evidencia_secundaria")

  write_ris(to_screen, fs::path(dir, "para_rayyan.ris"))
  write_stage(classified, dir, "clasificacion_pre_rayyan")
  write_stage(revisiones, dir, "revisiones_para_mineria_referencias")

  tracking <- dplyr::select(to_screen, source, source_id, title, year)
  write_stage(tracking, dir, "seguimiento_cribado")

  log_step_count("articulos_exportados_a_rayyan", nrow(to_screen))
  log_step_count("excluidos_ensayo_sin_datos_posibles",
                  sum(classified$exclusion_reason == "ensayo_sin_datos_posibles", na.rm = TRUE))
  log_step_count("revisiones_para_mineria_referencias", nrow(revisiones))
  log_step_count("excluidos_retractados",
                  sum(classified$exclusion_reason == "retractado", na.rm = TRUE))
  log_step_count("excluidos_secundario_o_sin_resultados",
                  sum(classified$exclusion_reason == "secundario_o_sin_resultados", na.rm = TRUE))
  logger::log_info("RIS para Rayyan en {fs::path(dir, 'para_rayyan.ris')}")
  to_screen
}
