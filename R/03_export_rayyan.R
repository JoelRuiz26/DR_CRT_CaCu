#' Writes a single record in RIS format (the standard format Rayyan,
#' EndNote and Zotero import). TY=JOUR for everything, for simple import
#' compatibility across both sources.
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

#' Writes the full RIS file for import into Rayyan.
write_ris <- function(articles, path) {
  all_lines <- unlist(purrr::map(seq_len(nrow(articles)), function(i) ris_record(articles[i, ])))
  writeLines(all_lines, path)
  invisible(path)
}

#' Excludes records before Rayyan for STRUCTURAL reasons only (metadata
#' already assigned by NLM/ClinicalTrials.gov, not title/abstract text):
#' - ClinicalTrials.gov WITHDRAWN or NOT_YET_RECRUITING: no participant was
#'   ever enrolled, so there is no data to extract.
#' - PubMed reviews/systematic reviews: secondary evidence, not primary;
#'   kept aside for manual reference mining, not discarded.
#' - PubMed retracted publications: formally withdrawn by the journal.
#' - PubMed editorials/comments/letters/news: secondary evidence.
#' - PubMed clinical trial protocols: design-only, no results yet.
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

#' Exports the combined corpus to Rayyan (RIS), without deduplicating in R
#' (Rayyan deduplicates on import by DOI/title/authors/year) and without
#' filtering by drug-name presence in the text (already required by the
#' search query). Only the structural exclusions from
#' `classify_metadata_exclusions()` are applied here.
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
