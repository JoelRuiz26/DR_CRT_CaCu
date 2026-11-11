#' Horizontal bar: breadth of candidates per pharmacological group — how
#' many DISTINCT drugs from each WHO ATC Level 1 group appear in the
#' included corpus (a map of the field's breadth, not its study volume —
#' that is fig02's job).

source("R/figures/utils_figures.R")

build_atc_breadth <- function() {
  long <- utils::read.csv("data/04_texto_completo/figure_dataset_long.csv", stringsAsFactors = FALSE)

  counts <- long |>
    dplyr::distinct(atc_level1_name, drug) |>
    dplyr::count(atc_level1_name, name = "n_drugs") |>
    dplyr::arrange(n_drugs)

  counts$atc_level1_name <- factor(counts$atc_level1_name, levels = counts$atc_level1_name)

  ggplot2::ggplot(counts, ggplot2::aes(x = n_drugs, y = atc_level1_name)) +
    ggplot2::geom_col(fill = "#009E73", width = 0.7) +
    ggplot2::geom_text(ggplot2::aes(label = n_drugs), hjust = -0.3, size = 3.2, color = "grey20") +
    ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0, 0.15))) +
    ggplot2::labs(
      title = "Breadth of repurposing candidates by pharmacological group",
      subtitle = "Number of distinct non-oncological drugs identified per WHO ATC group",
      x = "Distinct drugs (n)", y = NULL
    ) +
    theme_journal() +
    ggplot2::theme(panel.grid.major.y = ggplot2::element_blank())
}

if (sys.nframe() == 0) {
  save_figure(build_atc_breadth(), "fig05_atc_breadth", width = 7, height = 5.5)
}
