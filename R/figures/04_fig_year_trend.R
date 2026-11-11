#' Stacked bar: included studies per publication year, split by evidence
#' category, showing how the field has grown and shifted over time. Each
#' study counts exactly once (see evidence_category in
#' 00_prepare_figure_data.R) — a study with both an in-vitro and an
#' in-vivo arm is not double-counted across two segments.

source("R/figures/utils_figures.R")

EVIDENCE_LEVELS <- c("Preclinical", "Clinical")

build_year_trend <- function() {
  articles <- utils::read.csv("data/04_texto_completo/figure_dataset_articles.csv", stringsAsFactors = FALSE)

  by_year <- articles |>
    dplyr::filter(!is.na(evidence_category) & nzchar(evidence_category), !is.na(year)) |>
    dplyr::count(year, evidence_category, name = "n_studies")

  by_year$evidence_category <- factor(by_year$evidence_category, levels = EVIDENCE_LEVELS)

  ggplot2::ggplot(by_year, ggplot2::aes(x = year, y = n_studies, fill = evidence_category)) +
    ggplot2::geom_col(width = 0.7, color = "white", linewidth = 0.15) +
    ggplot2::scale_fill_manual(values = PALETTE$evidence, name = "Evidence level") +
    ggplot2::scale_x_continuous(breaks = scales::breaks_pretty(n = 8)) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.05))) +
    ggplot2::labs(x = NULL, y = "Studies (n)") +
    theme_journal()
}

if (sys.nframe() == 0) {
  save_figure(build_year_trend(), "fig04_year_trend", width = 7.5, height = 5)
}
