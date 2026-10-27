#' Parsea un bloque de PubmedArticle XML al esquema normalizado.
parse_pubmed_xml <- function(xml_text) {
  doc <- xml2::read_xml(xml_text)
  articles <- xml2::xml_find_all(doc, ".//PubmedArticle")
  if (length(articles) == 0) return(tibble::tibble())

  purrr::map_dfr(articles, function(a) {
    pmid <- xml2::xml_text(xml2::xml_find_first(a, ".//PMID"))
    title <- xml2::xml_text(xml2::xml_find_first(a, ".//ArticleTitle"))
    abstract_nodes <- xml2::xml_find_all(a, ".//Abstract/AbstractText")
    abstract <- paste(xml2::xml_text(abstract_nodes), collapse = " ")
    journal <- xml2::xml_text(xml2::xml_find_first(a, ".//Journal/Title"))
    year <- xml2::xml_text(xml2::xml_find_first(a, ".//JournalIssue/PubDate/Year"))
    if (is.na(year) || year == "") {
      medline_date <- xml2::xml_text(xml2::xml_find_first(a, ".//JournalIssue/PubDate/MedlineDate"))
      year <- stringr::str_extract(medline_date, "\\d{4}")
    }
    doi <- xml2::xml_text(xml2::xml_find_first(a, ".//ArticleId[@IdType='doi']"))
    pmcid <- xml2::xml_text(xml2::xml_find_first(a, ".//ArticleId[@IdType='pmc']"))
    author_nodes <- xml2::xml_find_all(a, ".//AuthorList/Author")
    author_names <- purrr::map_chr(author_nodes, function(au) {
      ln <- xml2::xml_text(xml2::xml_find_first(au, ".//LastName"))
      fn <- xml2::xml_text(xml2::xml_find_first(au, ".//ForeName"))
      trimws(paste(fn, ln))
    })
    pub_types <- xml2::xml_text(xml2::xml_find_all(a, ".//PublicationTypeList/PublicationType"))
    mesh <- xml2::xml_text(xml2::xml_find_all(a, ".//MeshHeadingList/MeshHeading/DescriptorName"))
    keywords <- xml2::xml_text(xml2::xml_find_all(a, ".//KeywordList/Keyword"))

    tibble::tibble(
      source = "pubmed", source_id = pmid,
      doi = na_if_empty(doi), pmid = na_if_empty(pmid), pmcid = na_if_empty(pmcid),
      title = na_if_empty(title), abstract = na_if_empty(abstract),
      journal = na_if_empty(journal), year = suppressWarnings(as.integer(year)),
      authors = list(author_names),
      publication_type = if (length(pub_types) == 0) NA_character_ else paste(pub_types, collapse = "; "),
      mesh_terms = list(mesh), keywords = list(keywords),
      url = if (!is.na(na_if_empty(pmid))) sprintf("https://pubmed.ncbi.nlm.nih.gov/%s/", pmid) else NA_character_,
      retrieved_at = Sys.time()
    )
  })
}

#' esearch de un lote de nombres de farmaco contra PubMed, con biseccion
#' automatica si el lote es rechazado por ser la URL demasiado larga (HTTP
#' 414). El tamano de lote (`chunk_size`) se valido contra una muestra de
#' nombres cortos (los primeros alfabeticamente) y parecia seguro hasta
#' ~95-99 nombres, pero un lote real puede incluir varios nombres largos
#' (combinaciones de dos farmacos, ej. "dutasteride / tamsulosin") que
#' hacen que ESE lote en particular sea mas largo de lo esperado — por eso
#' no basta con fijar un tamano de lote validado con una muestra, hace
#' falta recuperarse automaticamente del caso real. Mismo patron que
#' `ctgov_query_batch()` en R/01_fetch_clinicaltrials.R. Ver DECISIONS.md
#' (2026-10-04).
pubmed_esearch_batch <- function(pop, drug_batch, treat, date_filter, api_key, retmax = 3000) {
  terms <- paste0('"', drug_batch, '"[tiab]')
  q <- paste0(pop, " AND ", treat, " AND (", paste(terms, collapse = " OR "), ") AND ", date_filter)
  res <- tryCatch(
    rentrez::entrez_search(db = "pubmed", term = q, retmax = retmax, api_key = api_key),
    error = function(e) e
  )
  if (inherits(res, "error")) {
    if (length(drug_batch) <= 1) stop(res)
    mid <- length(drug_batch) %/% 2
    left <- pubmed_esearch_batch(pop, drug_batch[1:mid], treat, date_filter, api_key, retmax)
    right <- pubmed_esearch_batch(pop, drug_batch[(mid + 1):length(drug_batch)], treat, date_filter, api_key, retmax)
    return(list(count = left$count + right$count, ids = union(left$ids, right$ids)))
  }
  list(count = as.integer(res$count), ids = res$ids)
}

#' Busqueda en PubMed: poblacion AND tratamiento estandar AND
#' nombre_de_farmaco (el bloque de farmaco va al final), en lotes porque el
#' catalogo completo no cabe en una sola consulta. Lote de tamano
#' `drug_branch$chunk_size`, el MISMO numero que ClinicalTrials.gov
#' (homogenizacion explicita para metodos, 2026-10-04) — "de partida",
#' porque `pubmed_esearch_batch()` puede bisectar un lote hacia abajo si la
#' URL resulta demasiado larga. Antes de esto existio una rama de
#' sensibilizacion (poblacion AND tratamiento AND vocabulario de mecanismo,
#' sin nombrar farmaco) que se retiro — ver DECISIONS.md para el historial
#' completo.
fetch_pubmed <- function(cfg, drug_catalog) {
  raw_dir <- fs::path(cfg$paths$raw, "pubmed")
  fs::dir_create(raw_dir)
  api_key_env <- Sys.getenv(cfg$apis$ncbi_api_key_env, unset = NA)
  has_key <- !is.na(api_key_env) && nzchar(api_key_env)
  api_key <- if (has_key) api_key_env else NULL
  sleep_sec <- if (has_key) 1 / cfg$apis$rate_limit_with_key else 1 / cfg$apis$rate_limit_no_key

  pop <- cfg$search_string$pubmed_population
  treat <- cfg$search_string$pubmed_treatment
  # Limite superior = anio real de la corrida (cfg$retrieval$date_to_year,
  # calculado en _targets.R), NO un numero inventado como "3000" — ver
  # DECISIONS.md 2026-10-16.
  date_filter <- sprintf("%d:%d[dp]", cfg$retrieval$date_from_year, cfg$retrieval$date_to_year)
  chunk_size <- cfg$drug_branch$chunk_size %||% 80
  min_chars <- cfg$drug_branch$min_name_chars %||% 4

  # prepare_match_names() (R/05_catalogo_farmacos.R), no
  # drug_catalog$preferred_name directo — asi la busqueda excluye los MISMOS
  # nombres de ruido (glucose/oxygen/hydrogen peroxide/bevacizumab) que ya
  # excluye match_drugs_to_articles(). Ver DECISIONS.md (bug 2026-09-30).
  match_names <- prepare_match_names(drug_catalog, min_chars = min_chars)
  drug_names <- tolower(c(match_names$single, match_names$multi))
  chunks <- split(drug_names, ceiling(seq_along(drug_names) / chunk_size))

  all_ids <- character(0)
  chunk_log <- vector("list", length(chunks))
  for (i in seq_along(chunks)) {
    res <- pubmed_esearch_batch(pop, chunks[[i]], treat, date_filter, api_key)
    archive_raw_response(res, fs::path(raw_dir, "rama_farmaco_esearch"), sprintf("lote_%03d", i))
    chunk_log[[i]] <- tibble::tibble(chunk = i, n_drugs = length(chunks[[i]]), n_hits = res$count)
    all_ids <- union(all_ids, res$ids)
    Sys.sleep(sleep_sec)
  }

  id_batches <- split(all_ids, ceiling(seq_along(all_ids) / 200))
  records <- list()
  for (i in seq_along(id_batches)) {
    xml_txt <- rentrez::entrez_fetch(
      db = "pubmed", id = id_batches[[i]], rettype = "abstract", retmode = "xml",
      api_key = api_key
    )
    ts <- format(Sys.time(), "%Y%m%dT%H%M%OS3Z", tz = "UTC")
    writeLines(xml_txt, fs::path(raw_dir, sprintf("pubmed_drugbranch_%s.xml", ts)))
    records[[length(records) + 1]] <- parse_pubmed_xml(xml_txt)
    Sys.sleep(sleep_sec)
  }
  articles <- dplyr::bind_rows(records)
  log_step_count("pubmed_total_articulos", nrow(articles))

  list(
    articles = articles,
    log = tibble::tibble(
      source = "pubmed",
      query_string = sprintf(
        "%d lotes de %d farmacos: POBLACION AND TRATAMIENTO AND (lote) AND %s; catalogo=%d farmacos no oncologicos",
        length(chunks), chunk_size, date_filter, nrow(drug_catalog)
      ),
      n_results = length(all_ids), retrieved_at = Sys.time()
    ),
    chunk_log = dplyr::bind_rows(chunk_log)
  )
}
