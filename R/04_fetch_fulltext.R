#' Descarga el XML JATS de texto completo de un articulo via NCBI efetch
#' (db=pmc), archivando la respuesta cruda sin modificar. Devuelve NA si no
#' esta disponible (no todos los PMCID tienen texto completo servible, aun
#' marcados como acceso abierto — no se reintenta agresivamente, un 404 es
#' una respuesta valida de "no disponible").
fetch_fulltext_pmc <- function(pmcid, cfg) {
  raw_dir <- fs::path(cfg$paths$stage4, "raw")
  fs::dir_create(raw_dir)
  numeric_id <- gsub("^PMC", "", pmcid, ignore.case = TRUE)
  api_key <- Sys.getenv(cfg$apis$ncbi_api_key_env, unset = NA)
  has_key <- !is.na(api_key) && nzchar(api_key)

  resp <- tryCatch(
    httr2::request("https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi") |>
      httr2::req_url_query(db = "pmc", id = numeric_id, rettype = "full", retmode = "xml",
                            api_key = if (has_key) api_key else NULL) |>
      httr2::req_retry(max_tries = 3, is_transient = \(r) httr2::resp_status(r) %in% c(429, 500, 502, 503, 504)) |>
      httr2::req_perform(),
    error = function(e) NULL
  )
  if (is.null(resp) || httr2::resp_status(resp) != 200) return(NA_character_)
  xml_text <- httr2::resp_body_string(resp)

  ts <- format(Sys.time(), "%Y%m%dT%H%M%OS3Z", tz = "UTC")
  writeLines(xml_text, fs::path(raw_dir, sprintf("%s_%s.xml", pmcid, ts)))
  xml_text
}

#' Extrae abstract+body de un XML JATS, excluyendo <back> por completo (ahi
#' vive la lista de referencias, agradecimientos, financiamiento y notas de
#' revisores — un farmaco mencionado solo ahi es una cita de otro trabajo,
#' no evidencia de que el estudio lo haya usado). Ver DECISIONS.md.
extract_body_text <- function(xml_text) {
  if (is.na(xml_text)) return(NA_character_)
  doc <- tryCatch(xml2::read_xml(xml_text), error = function(e) NULL)
  if (is.null(doc)) return(NA_character_)
  useful <- xml2::xml_find_all(doc, ".//abstract | .//body")
  if (length(useful) == 0) return(NA_character_)
  paste(xml2::xml_text(useful), collapse = " ")
}

#' Para cada articulo con PMCID, intenta bajar y segmentar el texto
#' completo. Los que no tienen PMCID (u obtienen 404) quedan con
#' fulltext_status = "abstract_only" y su texto disponible es el que ya
#' tenian (title+abstract) — NUNCA se excluyen por falta de texto completo,
#' solo se marcan para que la exclusion automatica de la etapa 5 no los toque.
fetch_all_fulltext <- function(articles, cfg) {
  has_pmcid <- !is.na(articles$pmcid) & nzchar(articles$pmcid)
  logger::log_info("Articulos con PMCID (candidatos a texto completo): {sum(has_pmcid)} de {nrow(articles)}")

  body_text <- rep(NA_character_, nrow(articles))
  status <- ifelse(has_pmcid, "pending", "abstract_only")

  idx <- which(has_pmcid)
  for (k in seq_along(idx)) {
    i <- idx[k]
    xml_text <- fetch_fulltext_pmc(articles$pmcid[i], cfg)
    txt <- extract_body_text(xml_text)
    if (!is.na(txt)) {
      body_text[i] <- txt
      status[i] <- "fulltext_oa"
    } else {
      status[i] <- "abstract_only"
    }
    if (k %% 50 == 0) logger::log_info("Texto completo: {k}/{length(idx)} procesados")
    Sys.sleep(0.34)
  }

  n_ok <- sum(status == "fulltext_oa")
  log_step_count("fulltext_descargado", n_ok, detail = paste0("cobertura = ", round(100 * n_ok / nrow(articles), 1), "%"))

  articles$fulltext_status <- status
  articles$fulltext_body <- body_text
  # texto a usar para el emparejamiento: completo cuando se logro, si no lo
  # que ya habia (title+abstract) — nunca texto vacio.
  articles$match_text <- ifelse(
    !is.na(articles$fulltext_body), articles$fulltext_body,
    paste(articles$title, articles$abstract)
  )
  articles
}
