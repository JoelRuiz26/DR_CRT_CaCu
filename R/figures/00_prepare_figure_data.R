#' Builds the two datasets every figure script reads from. Re-run this one
#' script after finishing full-text review and re-exporting from Rayyan —
#' point SCREENING_FILE at the final file and every figure updates with it.
#'
#' Evidence level (in vitro / in vivo / clinical) is NOT something the
#' search or the catalog match can determine — it's set here by a keyword
#' heuristic on title+abstract (`classify_evidence_level()`), same spirit as
#' every other automated step in this pipeline: a transparent draft, meant
#' to be corrected by hand against the full text, not trusted as final.
#' After full-text review, edit `evidence_in_vitro`/`evidence_in_vivo`/
#' `evidence_clinical` directly in figure_dataset_articles.csv — the other
#' scripts read whatever is in that file, auto or corrected alike.

source("R/figures/utils_figures.R")

SCREENING_FILE <- "data/03_cribado/clasificacion_pre_rayyan.csv"
CATALOG_FILE <- "data/05_catalogo_farmacos/drug_catalog.csv"
OUT_DIR <- "data/04_texto_completo"

#' Keyword heuristic for evidence level, run on title + abstract (+
#' intervention text, for ClinicalTrials.gov). A ClinicalTrials.gov record is
#' always clinical by construction (it's a trial registry entry). A study
#' can be flagged TRUE on more than one level (e.g. a paper with both a
#' cell-line and a mouse-xenograft experiment).
classify_evidence_level <- function(source, text) {
  text <- tolower(text)
  in_vitro <- stringr::str_detect(
    text,
    "\\bin vitro\\b|cell line|cultured cells|\\bhela\\b|\\bsiha\\b|\\bcaski\\b|\\bc-?33a\\b|mtt assay|cytotoxicity assay"
  )
  in_vivo <- stringr::str_detect(
    text,
    "\\bin vivo\\b|xenograft|\\bmice\\b|\\bmouse\\b|murine|\\brats?\\b|animal model|nude mice"
  )
  clinical <- source == "clinicaltrials" | stringr::str_detect(
    text,
    "\\bpatients?\\b|clinical trial|\\bphase (i|ii|iii|1|2|3)\\b|randomi[sz]ed|\\bcohort\\b|retrospective|prospective study|case series"
  )
  tibble::tibble(evidence_in_vitro = in_vitro, evidence_in_vivo = in_vivo, evidence_clinical = clinical)
}

prepare_figure_data <- function() {
  classified <- utils::read.csv(SCREENING_FILE, stringsAsFactors = FALSE)
  included <- dplyr::filter(classified, is.na(exclusion_reason) | exclusion_reason == "")
  logger::log_info("Articulos incluidos para figuras: {nrow(included)}")

  catalog <- utils::read.csv(CATALOG_FILE, stringsAsFactors = FALSE)

  interventions <- if ("interventions_text" %in% names(included)) included$interventions_text else ""
  full_text <- paste(included$title, included$abstract, dplyr::coalesce(interventions, ""))
  evidence <- classify_evidence_level(included$source, full_text)
  articles <- dplyr::bind_cols(included, evidence)

  fs::dir_create(OUT_DIR)
  utils::write.csv(articles, fs::path(OUT_DIR, "figure_dataset_articles.csv"), row.names = FALSE, na = "")

  # Long format: one row per (article, matched drug, ATC code) — what the
  # class x evidence heatmap and the ATC-breadth figure read from.
  long <- articles |>
    dplyr::mutate(drug = stringr::str_split(drug_matches, ";\\s*")) |>
    tidyr::unnest(drug) |>
    dplyr::mutate(drug = trimws(drug)) |>
    dplyr::filter(nzchar(drug)) |>
    dplyr::left_join(
      dplyr::select(catalog, preferred_name, atc_classes),
      by = dplyr::join_by(drug == preferred_name)
    ) |>
    dplyr::mutate(atc_code = stringr::str_split(atc_classes, ";\\s*")) |>
    tidyr::unnest(atc_code) |>
    dplyr::mutate(
      atc_code = trimws(atc_code),
      atc_level1 = substr(atc_code, 1, 1),
      atc_level1_name = ATC_LEVEL1_NAMES[atc_level1]
    ) |>
    dplyr::filter(!is.na(atc_code), nzchar(atc_code))

  utils::write.csv(long, fs::path(OUT_DIR, "figure_dataset_long.csv"), row.names = FALSE, na = "")
  logger::log_info("figure_dataset_articles.csv: {nrow(articles)} filas; figure_dataset_long.csv: {nrow(long)} filas")

  list(articles = articles, long = long)
}

if (sys.nframe() == 0) invisible(prepare_figure_data())
