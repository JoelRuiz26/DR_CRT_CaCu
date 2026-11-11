#' Heatmap: pharmacological group (WHO ATC Level 1) x evidence level. Cell
#' value is the number of DISTINCT articles contributing to that group at
#' that evidence level (an article matching two drugs in the same group
#' counts once, not twice; an article with both in vitro and in vivo data
#' counts in both columns).

source("R/figures/utils_figures.R")

build_heatmap <- function() {
  long <- utils::read.csv("data/04_texto_completo/figure_dataset_long.csv", stringsAsFactors = FALSE)

  cell_counts <- long |>
    tidyr::pivot_longer(
      cols = c(evidence_in_vitro, evidence_in_vivo, evidence_clinical),
      names_to = "evidence_level", values_to = "present"
    ) |>
    dplyr::filter(present) |>
    dplyr::mutate(evidence_level = c(
      evidence_in_vitro = "In vitro", evidence_in_vivo = "In vivo", evidence_clinical = "Clinical"
    )[evidence_level]) |>
    dplyr::distinct(atc_level1_name, evidence_level, source_id) |>
    dplyr::count(atc_level1_name, evidence_level, name = "n_studies")

  group_order <- cell_counts |>
    dplyr::group_by(atc_level1_name) |>
    dplyr::summarise(total = sum(n_studies), .groups = "drop") |>
    dplyr::arrange(total) |>
    dplyr::pull(atc_level1_name)

  cell_counts$atc_level1_name <- factor(cell_counts$atc_level1_name, levels = group_order)
  cell_counts$evidence_level <- factor(cell_counts$evidence_level, levels = c("In vitro", "In vivo", "Clinical"))
  cell_counts$label_color <- ifelse(
    cell_counts$n_studies > max(cell_counts$n_studies) * 0.6, "white", "black"
  )

  ggplot2::ggplot(cell_counts, ggplot2::aes(x = evidence_level, y = atc_level1_name, fill = n_studies)) +
    ggplot2::geom_tile(color = NA) +
    ggplot2::geom_text(
      ggplot2::aes(label = n_studies, color = label_color),
      size = 2.7, family = FONT_FAMILY, show.legend = FALSE
    ) +
    ggplot2::scale_color_identity() +
    ggplot2::scale_fill_gradient(
      name = "Studies\n(n)", low = PALETTE$sequential_low, high = PALETTE$sequential_high,
      guide = ggplot2::guide_colorbar(barwidth = 0.5, barheight = 5, ticks = FALSE)
    ) +
    ggplot2::scale_x_discrete(position = "top", expand = c(0, 0)) +
    ggplot2::scale_y_discrete(expand = c(0, 0)) +
    ggplot2::labs(x = NULL, y = NULL) +
    theme_journal() +
    ggplot2::theme(
      axis.line = ggplot2::element_blank(),
      axis.ticks = ggplot2::element_blank(),
      axis.text.y = ggplot2::element_text(size = ggplot2::rel(0.95), hjust = 1),
      axis.text.x = ggplot2::element_text(size = ggplot2::rel(1), face = "bold"),
      legend.position = "right"
    )
}

if (sys.nframe() == 0) {
  save_figure(build_heatmap(), "fig02_heatmap_class_evidence", width = 4.6, height = 5.8)
}
