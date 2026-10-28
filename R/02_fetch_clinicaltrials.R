#' Parses a "study" object from the ClinicalTrials.gov API v2 into the
#' normalized schema.
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

#' Queries a batch of drug names against the ClinicalTrials.gov API v2,
#' paginating with pageToken, and archives every raw page. `date_filter`
#' uses the Essie syntax `AREA[StartDate]RANGE[...]`.
#'
#' The search engine (Essie) sometimes rejects a batch with HTTP 400 for no
#' single identifiable reason. Bisects the batch and retries each half,
#' recursively, until every sub-batch succeeds.
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
        "ClinicalTrials.gov: batch {chunk_idx} rejected (400) with {length(drug_batch)} drugs, bisecting"
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

#' ClinicalTrials.gov API v2 search: population AND drug name AND standard
#' treatment, batched the same starting size as PubMed (see
#' R/02_fetch_pubmed.R) — "starting" because `ctgov_query_batch()` can
#' bisect a batch further if rejected.
fetch_clinicaltrials <- function(cfg, drug_catalog) {
  raw_dir <- fs::path(cfg$paths$raw, "clinicaltrials")
  fs::dir_create(raw_dir)
  max_total <- cfg$retrieval$max_records
  sleep_sec <- 1

  pop <- cfg$search_string$ctgov_population
  treat <- cfg$search_string$ctgov_treatment
  date_filter <- sprintf("AREA[StartDate]RANGE[%d-01-01,MAX]", cfg$retrieval$date_from_year)
  chunk_size <- cfg$drug_branch$chunk_size %||% 80
  min_chars <- cfg$drug_branch$min_name_chars %||% 4

  # Reuses prepare_match_names() (same noise exclusions as PubMed's search).
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
