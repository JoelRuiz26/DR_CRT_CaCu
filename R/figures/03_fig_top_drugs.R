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
    ggplot2::geom_col(fill = PALETTE$sequential_high, width = 0.65) +
    ggplot2::geom_text(ggplot2::aes(label = n_studies), hjust = -0.4, size = 2.7, family = FONT_FAMILY, color = "black") +
    ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0, 0.12))) +
    ggplot2::labs(x = "Studies (n)", y = NULL) +
    theme_journal() +
    ggplot2::theme(legend.position = "none")
}

if (sys.nframe() == 0) {
  save_figure(build_top_drugs(), "fig03_top_drugs", width = 7, height = 5.5)
}
