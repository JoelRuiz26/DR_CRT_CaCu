#' Parsea un objeto "study" de la API v2 de ClinicalTrials.gov al esquema normalizado.
parse_ctgov_study <- function(s) {
  ident <- s$protocolSection$identificationModule
  status <- s$protocolSection$statusModule
  desc <- s$protocolSection$descriptionModule
  nct <- ident$nctId %||% NA_character_

  tibble::tibble(
    source = "clinicaltrials", source_id = nct,
    doi = NA_character_, pmid = NA_character_, pmcid = NA_character_,
    title = ident$briefTitle %||% NA_character_,
    abstract = desc$briefSummary %||% NA_character_,
    journal = NA_character_,
    year = suppressWarnings(as.integer(
      stringr::str_extract(status$startDateStruct$date %||% "", "^\\d{4}")
    )),
    authors = list(character(0)),
    publication_type = status$overallStatus %||% NA_character_,
    mesh_terms = list(character(0)), keywords = list(character(0)),
    url = if (!is.na(nct)) sprintf("https://clinicaltrials.gov/study/%s", nct) else NA_character_,
    retrieved_at = Sys.time()
  )
}

#' Consulta un lote de nombres de farmaco contra la API v2 de
#' ClinicalTrials.gov, paginando con pageToken, y archiva cada pagina cruda.
#' `date_filter` es la sintaxis Essie `AREA[StartDate]RANGE[...]`, probada
#' empiricamente contra la API real antes de usarla (ver DECISIONS.md).
#'
#' El motor de busqueda (Essie) a veces rechaza un lote con HTTP 400, sin
#' que se haya podido caracterizar una causa unica y confiable: se probo la
#' hipotesis de que fuera por mandar muchas peticiones seguidas (no lo
#' era — el mismo lote fallido, reintentado solo con pausas mas largas,
#' siguio fallando) y la hipotesis de que fuera solo numero de terminos
#' (tampoco explica todos los casos: un lote de 80 farmacos + poblacion +
#' tratamiento completos, 94 terminos en total, puede fallar, aunque antes
#' se habian probado lotes de hasta ~123 terminos sin fallar). Ante un
#' limite que no se puede caracterizar con precision, la solucion robusta
#' es bisectar: si un lote es rechazado, se reintenta partido a la mitad,
#' cuantas veces haga falta, hasta que cada sublote funcione. No depende de
#' entender la causa exacta. Ver DECISIONS.md (2026-10-04) para el historial
#' de intentos de simplificacion que no resultaron suficientes.
ctgov_query_batch <- function(pop, drug_batch, treat, date_filter, raw_dir, max_total, chunk_idx, depth = 0) {
  terms <- paste0('"', drug_batch, '"')
  q <- paste0(pop, " AND ", treat, " AND (", paste(terms, collapse = " OR "), ") AND ", date_filter)

  studies <- list()
  next_token <- NULL
  page <- 0L
  repeat {
    query <- list("query.term" = q, pageSize = 100)
    if (!is.null(next_token)) query$pageToken <- next_token
    resp <- tryCatch(http_get_json("https://clinicaltrials.gov/api/v2/studies", query), httr2_http_400 = function(e) e)
    if (inherits(resp, "condition")) {
      if (length(drug_batch) <= 1) stop(resp)
      logger::log_info(
        "ClinicalTrials.gov: lote {chunk_idx} rechazado (400) con {length(drug_batch)} farmacos, bisectando"
      )
      mid <- length(drug_batch) %/% 2
      left <- ctgov_query_batch(pop, drug_batch[1:mid], treat, date_filter, raw_dir, max_total, chunk_idx, depth + 1)
      right <- ctgov_query_batch(pop, drug_batch[(mid + 1):length(drug_batch)], treat, date_filter, raw_dir, max_total, chunk_idx, depth + 1)
      return(c(left, right))
    }
    ts <- format(Sys.time(), "%Y%m%dT%H%M%OS3Z", tz = "UTC")
    archive_raw_response(resp, raw_dir, sprintf("lote_%03d_d%d_p%d_%s", chunk_idx, depth, page, ts))
    studies <- c(studies, resp$studies)
    next_token <- resp$nextPageToken
    page <- page + 1L
    if (is.null(next_token) || length(studies) >= max_total || length(resp$studies) == 0) break
  }
  studies
}

#' Busqueda en ClinicalTrials.gov API v2: poblacion AND nombre_de_farmaco AND
#' tratamiento estandar, en lotes del mismo tamano de partida que PubMed
#' (homogenizacion explicita para metodos, ver R/01_fetch_pubmed.R y
#' DECISIONS.md) — "de partida" porque `ctgov_query_batch()` puede bisectar
#' un lote hacia abajo si el motor de busqueda lo rechaza.
fetch_clinicaltrials <- function(cfg, drug_catalog) {
  raw_dir <- fs::path(cfg$paths$raw, "clinicaltrials")
  fs::dir_create(raw_dir)
  max_total <- cfg$retrieval$max_records
  # Antes no habia pausa entre lotes (pocas llamadas, parecia innecesario).
  # Se agrego junto con el reintento de arriba: mandar muchas peticiones
  # seguidas sin pausa es la sospecha mas probable del 400 intermitente.
  sleep_sec <- 1

  pop <- cfg$search_string$ctgov_population
  treat <- cfg$search_string$ctgov_treatment
  date_filter <- sprintf("AREA[StartDate]RANGE[%d-01-01,MAX]", cfg$retrieval$date_from_year)
  chunk_size <- cfg$drug_branch$chunk_size %||% 80
  min_chars <- cfg$drug_branch$min_name_chars %||% 4

  # Ver R/01_fetch_pubmed.R para por que se usa prepare_match_names() en vez
  # de drug_catalog$preferred_name directo (excluye glucose/oxygen/hydrogen
  # peroxide/bevacizumab, el mismo bug de ruido de busqueda). Ver DECISIONS.md.
  match_names <- prepare_match_names(drug_catalog, min_chars = min_chars)
  drug_names <- tolower(c(match_names$single, match_names$multi))
  chunks <- split(drug_names, ceiling(seq_along(drug_names) / chunk_size))

  all_studies <- list()
  chunk_log <- vector("list", length(chunks))
  for (i in seq_along(chunks)) {
    chunk_studies <- ctgov_query_batch(pop, chunks[[i]], treat, date_filter, fs::path(raw_dir, "rama_farmaco"), max_total, i)
    chunk_log[[i]] <- tibble::tibble(chunk = i, n_drugs = length(chunks[[i]]), n_hits = length(chunk_studies))
    all_studies <- c(all_studies, chunk_studies)
    Sys.sleep(sleep_sec)
  }

  nct_ids <- purrr::map_chr(all_studies, ~ .x$protocolSection$identificationModule$nctId %||% NA_character_)
  all_studies <- all_studies[!duplicated(nct_ids)]
  logger::log_info("ClinicalTrials.gov: n_studies = {length(all_studies)}")

  articles <- if (length(all_studies) == 0) tibble::tibble() else dplyr::bind_rows(purrr::map(all_studies, parse_ctgov_study))
  log_step_count("clinicaltrials_total_estudios", nrow(articles))
  list(
    articles = articles,
    log = tibble::tibble(
      source = "clinicaltrials",
      query_string = sprintf(
        "%d lotes de %d farmacos: POBLACION AND TRATAMIENTO AND (lote) AND %s; catalogo=%d farmacos no oncologicos",
        length(chunks), chunk_size, date_filter, nrow(drug_catalog)
      ),
      n_results = length(all_studies), retrieved_at = Sys.time()
    ),
    chunk_log = dplyr::bind_rows(chunk_log)
  )
}
