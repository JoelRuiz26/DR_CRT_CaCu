#' Horizontal bar chart: most-studied individual drugs across the included
#' corpus (one count per distinct article, not per mention).

source("R/figures/utils_figures.R")

build_top_drugs <- function(top_n = 15) {
  long <- utils::read.csv("data/04_texto_completo/figure_dataset_long.csv", stringsAsFactors = FALSE)

  counts <- long |>
    dplyr::distinct(drug, source_id) |>
    dplyr::count(drug, name = "n_studies") |>
    dplyr::arrange(dplyr::desc(n_studies)) |>
    dplyr::slice_head(n = top_n) |>
    dplyr::mutate(drug = stringr::str_to_sentence(drug))

  counts$drug <- factor(counts$drug, levels = rev(counts$drug))

  ggplot2::ggplot(counts, ggplot2::aes(x = n_studies, y = drug)) +
    ggplot2::geom_col(fill = "#0072B2", width = 0.7) +
    ggplot2::geom_text(ggplot2::aes(label = n_studies), hjust = -0.3, size = 3.2, color = "grey20") +
    ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0, 0.15))) +
    ggplot2::labs(
      title = paste("The", top_n, "most-studied repurposing candidates"),
      subtitle = "Number of included studies per non-oncological drug",
      x = "Studies (n)", y = NULL
    ) +
    theme_journal() +
    ggplot2::theme(panel.grid.major.y = ggplot2::element_blank(), legend.position = "none")
}

if (sys.nframe() == 0) {
  save_figure(build_top_drugs(), "fig03_top_drugs", width = 7, height = 5.5)
}
