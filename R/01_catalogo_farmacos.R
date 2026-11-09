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

#' Generic biochemical/elemental terms that match by ATC code but, in free
#' text, overwhelmingly signal a lab value, diagnostic tracer or chemistry
#' reagent rather than an administered intervention — verified against this
#' review's own corpus: every record matched SOLELY by one of these turned
#' out to be "blood urea nitrogen" (a lab marker), "99mTc sulfur colloid"
#' (an imaging tracer), a metal-coordination-chemistry paper (ligands
#' described as "sulfur-containing", "nitrogen-containing"), or similar.
CATALOG_GENERIC_NOISE_EXCLUDE <- c(
  "oxygen", "glucose", "hydrogen peroxide",
  "urea", "nitrogen", "sulfur", "nitric oxide", "methionine",
  "acetic acid", "protein c"
)

#' Splits catalog names into single-token (set intersection, fast) and
#' substring-matched (fixed substring match — a regex alternation across
#' ~2,800 names was too slow against full-text articles). A name goes to
#' substring matching whenever it has a space OR a hyphen: word-tokenizers
#' split on both (e.g. "sipuleucel-t" tokenizes as "sipuleucel", "t"), so
#' token intersection alone would silently miss every hyphenated name.
prepare_match_names <- function(catalog, min_chars = 4) {
  names <- unique(catalog$preferred_name)
  names <- names[nchar(names) >= min_chars]
  names <- setdiff(names, c(CATALOG_MANUAL_EXCLUDE, CATALOG_GENERIC_NOISE_EXCLUDE))
  needs_substring <- grepl("[^a-z0-9]", names)
  list(single = names[!needs_substring], multi = names[needs_substring])
}

#' Catalog drugs mentioned in a text: token intersection for single-word
#' names, fixed substring match for multi-word names.
find_drug_mentions <- function(text, names_single, names_multi) {
  tokens <- unique(stringi::stri_extract_all_words(text)[[1]])
  hits_single <- intersect(tokens, names_single)
  hits_multi <- names_multi[stringi::stri_detect_fixed(text, names_multi)]
  c(hits_single, hits_multi)
}

#' Matches the catalog against article text and flags matches. This is the
#' pipeline's real drug-name filter: the search query's own per-batch
#' drug-name clause isn't reliable enough to trust alone (verified against
#' the live PubMed/ClinicalTrials.gov APIs — a batch's "OR of 80 names" can
#' silently stop constraining results), so every record is re-checked here
#' against the full catalog before `classify_metadata_exclusions()`
#' (R/03_export_rayyan.R) drops the ones with no match. Uses title+abstract,
#' plus `interventions_text` when present (ClinicalTrials.gov: the brief
#' summary alone often doesn't name the studied drug).
match_drugs_to_articles <- function(articles, catalog) {
  names <- prepare_match_names(catalog)
  extra_text <- if ("interventions_text" %in% names(articles)) {
    dplyr::coalesce(articles$interventions_text, "")
  } else {
    ""
  }
  match_text <- tolower(paste(articles$title, articles$abstract, extra_text))
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
