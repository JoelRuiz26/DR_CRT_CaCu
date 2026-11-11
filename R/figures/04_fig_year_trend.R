#' Stacked bar: included studies per publication year, split by evidence
#' level, showing how the field has grown and shifted over time.

source("R/figures/utils_figures.R")

build_year_trend <- function() {
  articles <- utils::read.csv("data/04_texto_completo/figure_dataset_articles.csv", stringsAsFactors = FALSE)

  by_year <- articles |>
    tidyr::pivot_longer(
      cols = c(evidence_in_vitro, evidence_in_vivo, evidence_clinical),
      names_to = "evidence_level", values_to = "present"
    ) |>
    dplyr::filter(present) |>
    dplyr::mutate(evidence_level = c(
      evidence_in_vitro = "In vitro", evidence_in_vivo = "In vivo", evidence_clinical = "Clinical"
    )[evidence_level]) |>
    dplyr::count(year, evidence_level, name = "n_studies") |>
    dplyr::filter(!is.na(year))

  by_year$evidence_level <- factor(by_year$evidence_level, levels = c("In vitro", "In vivo", "Clinical"))

  ggplot2::ggplot(by_year, ggplot2::aes(x = year, y = n_studies, fill = evidence_level)) +
    ggplot2::geom_col(width = 0.75, color = "white", linewidth = 0.2) +
    ggplot2::scale_fill_manual(values = PALETTE$evidence, name = "Evidence level") +
    ggplot2::scale_x_continuous(breaks = scales::breaks_pretty(n = 8)) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.08))) +
    ggplot2::labs(
      title = "Publication trend by evidence level",
      subtitle = "Included studies per year, stacked by type of evidence",
      x = NULL, y = "Studies (n)"
    ) +
    theme_journal()
}

if (sys.nframe() == 0) {
  save_figure(build_year_trend(), "fig04_year_trend", width = 7.5, height = 5)
}
