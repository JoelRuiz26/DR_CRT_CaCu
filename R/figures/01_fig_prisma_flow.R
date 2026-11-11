#' PRISMA 2020 flow diagram. The identification/automated-exclusion numbers
#' come straight from the pipeline's own logs. The three numbers below this
#' comment are NOT in any pipeline output — they only exist once screening
#' and full-text review are done by hand in Rayyan. Fill them in, then
#' re-run this script; everything else recomputes on its own.

N_DUPLICATES_RAYYAN <- NA # Rayyan's own duplicate count after import
N_EXCLUDED_SCREENING <- NA # title/abstract exclusions decided in Rayyan
N_REPORTS_NOT_RETRIEVED <- NA # full text not obtainable
N_EXCLUDED_FULLTEXT <- NA # full-text exclusions, with reasons
N_INCLUDED_FINAL <- NA # studies in the final synthesis

source("R/figures/utils_figures.R")

fmt_n <- function(x) if (is.na(x)) "n = pendiente" else sprintf("n = %d", x)

build_prisma_flow <- function() {
  search_log <- utils::read.csv("data/01_busqueda/search_log.csv", stringsAsFactors = FALSE)
  classified <- utils::read.csv("data/03_cribado/clasificacion_pre_rayyan.csv", stringsAsFactors = FALSE)

  n_pubmed <- search_log$n_results[search_log$source == "pubmed"]
  n_ctgov <- search_log$n_results[search_log$source == "clinicaltrials"]
  n_identified <- n_pubmed + n_ctgov

  n_automation <- sum(classified$exclusion_reason %in%
    c("sin_farmaco_confirmado_en_texto", "ensayo_sin_datos_posibles", "retractado"), na.rm = TRUE)
  n_other_reasons <- sum(classified$exclusion_reason %in%
    c("revision_evidencia_secundaria", "secundario_o_sin_resultados"), na.rm = TRUE)
  n_screened <- sum(is.na(classified$exclusion_reason) | classified$exclusion_reason == "")

  boxes <- tibble::tribble(
    ~id, ~x, ~y, ~w, ~h, ~label,
    "ident", 1.0, 9.0, 3.6, 1.6,
    sprintf("Records identified from:\nPubMed (n = %d)\nClinicalTrials.gov registers (n = %d)\nTotal (n = %d)", n_pubmed, n_ctgov, n_identified),
    "removed", 5.2, 9.0, 3.6, 1.8,
    sprintf("Records removed before screening:\nDuplicate records removed (%s)\nIneligible by automation tools (n = %d)\nRemoved for other reasons (n = %d)", fmt_n(N_DUPLICATES_RAYYAN), n_automation, n_other_reasons),
    "screened", 1.0, 6.6, 3.6, 1.0,
    sprintf("Records screened\n(n = %d)", n_screened),
    "excl_screen", 5.2, 6.6, 3.6, 1.0,
    sprintf("Records excluded\n(%s)", fmt_n(N_EXCLUDED_SCREENING)),
    "sought", 1.0, 4.6, 3.6, 1.0,
    sprintf("Reports sought for retrieval\n(%s)", fmt_n(ifelse(is.na(N_EXCLUDED_SCREENING), NA, n_screened - N_EXCLUDED_SCREENING))),
    "not_retrieved", 5.2, 4.6, 3.6, 1.0,
    sprintf("Reports not retrieved\n(%s)", fmt_n(N_REPORTS_NOT_RETRIEVED)),
    "eligibility", 1.0, 2.6, 3.6, 1.0,
    "Reports assessed for eligibility",
    "excl_fulltext", 5.2, 2.6, 3.6, 1.2,
    sprintf("Reports excluded, with reasons\n(%s)", fmt_n(N_EXCLUDED_FULLTEXT)),
    "included", 1.0, 0.4, 3.6, 1.2,
    sprintf("Studies included in review\n(%s)", fmt_n(N_INCLUDED_FINAL))
  )

  arrows <- tibble::tribble(
    ~x, ~y, ~xend, ~yend,
    1.0 + 3.6, 9.0 + 0.8, 5.2, 9.0 + 0.9,
    1.0 + 1.8, 9.0, 1.0 + 1.8, 7.6,
    1.0 + 3.6, 6.6 + 0.5, 5.2, 6.6 + 0.5,
    1.0 + 1.8, 6.6, 1.0 + 1.8, 5.6,
    1.0 + 3.6, 4.6 + 0.5, 5.2, 4.6 + 0.5,
    1.0 + 1.8, 4.6, 1.0 + 1.8, 3.6,
    1.0 + 3.6, 2.6 + 0.5, 5.2, 2.6 + 0.5,
    1.0 + 1.8, 2.6, 1.0 + 1.8, 1.6
  )

  ggplot2::ggplot() +
    ggplot2::geom_rect(
      data = boxes,
      ggplot2::aes(xmin = x, xmax = x + w, ymin = y, ymax = y + h),
      fill = "white", color = "grey25", linewidth = 0.4
    ) +
    ggplot2::geom_text(
      data = boxes,
      ggplot2::aes(x = x + w / 2, y = y + h / 2, label = label),
      size = 3.1, lineheight = 1.05
    ) +
    ggplot2::geom_segment(
      data = arrows,
      ggplot2::aes(x = x, y = y, xend = xend, yend = yend),
      arrow = grid::arrow(length = ggplot2::unit(0.1, "inches"), type = "closed"),
      color = "grey25", linewidth = 0.4
    ) +
    ggplot2::coord_fixed(xlim = c(0.5, 9.3), ylim = c(0, 11), clip = "off") +
    ggplot2::theme_void() +
    ggplot2::labs(title = "Identification of studies via databases and registers")
}

if (sys.nframe() == 0) {
  save_figure(build_prisma_flow(), "fig01_prisma_flow", width = 7.5, height = 9)
}
