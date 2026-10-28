#' Level-2 ATC classes except L01/L02 (oncology drugs/therapy). An
#' ingredient is included if it has ANY non-oncology ATC code, even if it
#' also has an oncology one elsewhere.
atc_non_oncologic_classes <- function() {
  res <- http_get_json("https://rxnav.nlm.nih.gov/REST/rxclass/allClasses.json",
                        list(classTypes = "ATC1-4"))
  classes <- res$rxclassMinConceptList$rxclassMinConcept
  ids <- purrr::map_chr(classes, "classId")
  lvl2 <- ids[nchar(ids) == 3]
  setdiff(unique(lvl2), c("L01", "L02"))
}

#' Ingredients (name + RxCUI) belonging to an ATC class.
atc_class_members <- function(class_id) {
  res <- tryCatch(
    http_get_json("https://rxnav.nlm.nih.gov/REST/rxclass/classMembers.json",
                  list(classId = class_id, relaSource = "ATC")),
    error = function(e) NULL
  )
  items <- res$drugMemberGroup$drugMember
  if (is.null(items) || length(items) == 0) return(tibble::tibble())
  purrr::map_dfr(items, function(x) {
    tibble::tibble(
      drug_id = x$minConcept$rxcui,
      preferred_name = x$minConcept$name,
      atc_class = class_id
    )
  })
}

#' TRUE if the ingredient has at least one SCD/SBD in RxNorm's Current
#' Prescribable Content (API `Prescribe`) — currently marketed and
#' prescribable in the US, not just a historical/discontinued concept.
rxnorm_is_prescribable <- function(rxcui) {
  res <- tryCatch(
    http_get_json(paste0("https://rxnav.nlm.nih.gov/REST/Prescribe/rxcui/", rxcui, "/related.json"), list(tty = "SCD SBD")),
    error = function(e) NULL
  )
  cg <- res$relatedGroup$conceptGroup
  if (is.null(cg)) return(FALSE)
  any(vapply(cg, function(g) length(g$conceptProperties %||% list()) > 0, logical(1)))
}

#' Builds the non-oncology drug catalog: (1) collect every non-oncology ATC
#' class and its members, (2) filter to ingredients with a currently
#' prescribable form. The two steps stay separate so a repurposed drug that
#' also has an approved oncology indication isn't excluded for that reason.
build_drug_catalog <- function(cfg) {
  raw_dir <- fs::path(cfg$paths$raw, "..", "05_catalogo_farmacos") |> fs::path_norm()
  fs::dir_create(raw_dir)

  classes <- atc_non_oncologic_classes()
  log_step_count("atc_classes_no_oncologicas", length(classes))

  rows <- purrr::map(classes, function(cid) {
    members <- atc_class_members(cid)
    Sys.sleep(0.1)
    members
  })
  archive_raw_response(list(classes = classes, n_members_total = sum(purrr::map_int(rows, nrow))),
                        raw_dir, "atc_enumeration_summary")

  catalog <- dplyr::bind_rows(rows) |>
    dplyr::mutate(preferred_name = tolower(preferred_name)) |>
    dplyr::group_by(drug_id, preferred_name) |>
    dplyr::summarise(atc_classes = list(unique(atc_class)), .groups = "drop")
  log_step_count("catalogo_ingredientes_no_oncologicos_atc", nrow(catalog))

  is_marketed <- purrr::map_lgl(catalog$drug_id, function(id) {
    ok <- rxnorm_is_prescribable(id)
    Sys.sleep(0.1)
    ok
  })
  archive_raw_response(
    list(n_total = nrow(catalog), n_con_forma_comercializada_vigente = sum(is_marketed)),
    raw_dir, "fda_marketed_filter_summary"
  )
  catalog <- catalog[is_marketed, ]

  log_step_count("catalogo_ingredientes_unicos", nrow(catalog))
  catalog
}

#' Manual exceptions: ingredients the automatic ATC match flags as
#' non-oncology but are actually oncology drugs with a secondary indication.
#'   - bevacizumab: oncology drug (VEGF inhibitor) repurposed toward
#'     ophthalmology — opposite direction from this review's scope.
CATALOG_MANUAL_EXCLUDE <- c("bevacizumab")

#' Generic biochemical terms that match by ATC code but mostly add noise
#' (reactive oxygen species, cell metabolism) instead of signaling an
#' administered intervention.
CATALOG_GENERIC_NOISE_EXCLUDE <- c("oxygen", "glucose", "hydrogen peroxide")

#' Splits catalog names into single-word (set intersection, fast) and
#' multi-word (fixed substring match — a regex alternation across ~2,800
#' names was too slow against full-text articles).
prepare_match_names <- function(catalog, min_chars = 4) {
  names <- unique(catalog$preferred_name)
  names <- names[nchar(names) >= min_chars]
  names <- setdiff(names, c(CATALOG_MANUAL_EXCLUDE, CATALOG_GENERIC_NOISE_EXCLUDE))
  list(single = names[!grepl(" ", names)], multi = names[grepl(" ", names)])
}

#' Catalog drugs mentioned in a text: token intersection for single-word
#' names, fixed substring match for multi-word names.
find_drug_mentions <- function(text, names_single, names_multi) {
  tokens <- unique(stringi::stri_extract_all_words(text)[[1]])
  hits_single <- intersect(tokens, names_single)
  hits_multi <- names_multi[stringi::stri_detect_fixed(text, names_multi)]
  c(hits_single, hits_multi)
}

#' Matches the catalog against article text (title+abstract, or later full
#' text) and flags matches. Not called in the current pipeline: drug name is
#' already required in the search query, so re-filtering by text presence
#' before Rayyan would be redundant. Kept for later use on full text of
#' already-included studies.
match_drugs_to_articles <- function(articles, catalog) {
  names <- prepare_match_names(catalog)
  match_text <- tolower(paste(articles$title, articles$abstract))
  hits <- purrr::map(match_text, find_drug_mentions, names_single = names$single, names_multi = names$multi)

  articles$drug_matches <- hits
  articles$n_drug_matches <- lengths(hits)
  articles$eligibility_status <- dplyr::case_when(
    articles$n_drug_matches > 0 ~ "match_farmaco",
    !is.na(articles$abstract) ~ "excluible_sin_farmaco",
    TRUE ~ "no_verificable_sin_resumen"
  )

  log_step_count("con_match_de_farmaco", sum(articles$eligibility_status == "match_farmaco"))
  log_step_count("excluibles_sin_farmaco", sum(articles$eligibility_status == "excluible_sin_farmaco"))
  log_step_count("no_verificable_sin_resumen", sum(articles$eligibility_status == "no_verificable_sin_resumen"))
  articles
}
