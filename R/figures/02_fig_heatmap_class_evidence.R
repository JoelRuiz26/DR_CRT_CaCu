#' Heatmap: pharmacological group (WHO ATC Level 1) x evidence category
#' (Preclinical / Clinical). Cell value is the number of DISTINCT articles
#' — each article falls into exactly ONE column (`evidence_category`, from
#' 00_prepare_figure_data.R), so a study with both an in-vitro and an
#' in-vivo arm is not counted twice.

source("R/figures/utils_figures.R")

EVIDENCE_LEVELS <- c("Preclinical", "Clinical")

build_heatmap <- function() {
  long <- utils::read.csv("data/04_texto_completo/figure_dataset_long.csv", stringsAsFactors = FALSE)

  cell_counts <- long |>
    dplyr::filter(!is.na(evidence_category) & nzchar(evidence_category)) |>
    dplyr::distinct(atc_level1_name, evidence_category, source_id) |>
    dplyr::count(atc_level1_name, evidence_category, name = "n_studies")

  group_order <- cell_counts |>
    dplyr::group_by(atc_level1_name) |>
    dplyr::summarise(total = sum(n_studies), .groups = "drop") |>
    dplyr::arrange(total) |>
    dplyr::pull(atc_level1_name)

  # Every (group, category) pair gets a tile, including the ones with zero
  # studies — an absent row would otherwise leave blank panel background
  # there, indistinguishable from "no data" rather than "zero".
  cell_counts <- cell_counts |>
    tidyr::complete(atc_level1_name = group_order, evidence_category = EVIDENCE_LEVELS, fill = list(n_studies = 0))

  cell_counts$atc_level1_name <- factor(cell_counts$atc_level1_name, levels = group_order)
  cell_counts$evidence_category <- factor(cell_counts$evidence_category, levels = EVIDENCE_LEVELS)
  cell_counts$label_color <- ifelse(
    cell_counts$n_studies > max(cell_counts$n_studies) * 0.6, "white", "black"
  )
  cell_counts$label <- ifelse(cell_counts$n_studies == 0, "", as.character(cell_counts$n_studies))

  ggplot2::ggplot(cell_counts, ggplot2::aes(x = evidence_category, y = atc_level1_name, fill = n_studies)) +
    ggplot2::geom_tile(color = NA) +
    ggplot2::geom_text(
      ggplot2::aes(label = label, color = label_color),
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
      axis.text.x = ggplot2::element_text(size = ggplot2::rel(0.9), face = "bold", lineheight = 0.95),
      legend.position = "right"
    )
}

if (sys.nframe() == 0) {
  save_figure(build_heatmap(), "fig02_heatmap_class_evidence", width = 4, height = 5.8)
}
