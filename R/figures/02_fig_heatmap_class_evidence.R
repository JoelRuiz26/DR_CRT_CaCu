#' Paired-dot ("dumbbell") plot: pharmacological group (WHO ATC Level 1) by
#' evidence category (Preclinical / Clinical). A plain 2-column heatmap
#' doesn't earn its keep with only two categories — a heatmap's strength is
#' a wide matrix, not two columns of shaded squares. Two connected points
#' per row is the standard form for comparing exactly two series across
#' many categories, and reads at a glance which groups lean preclinical,
#' which lean clinical, and which are balanced.

source("R/figures/utils_figures.R")

EVIDENCE_LEVELS <- c("Preclinical", "Clinical")

build_heatmap <- function() {
  long <- utils::read.csv("data/04_texto_completo/figure_dataset_long.csv", stringsAsFactors = FALSE)

  counts <- long |>
    dplyr::filter(!is.na(evidence_category) & nzchar(evidence_category)) |>
    dplyr::distinct(atc_level1_name, evidence_category, source_id) |>
    dplyr::count(atc_level1_name, evidence_category, name = "n_studies") |>
    tidyr::complete(
      atc_level1_name = unique(long$atc_level1_name), evidence_category = EVIDENCE_LEVELS,
      fill = list(n_studies = 0)
    )

  group_order <- counts |>
    dplyr::group_by(atc_level1_name) |>
    dplyr::summarise(total = sum(n_studies), .groups = "drop") |>
    dplyr::arrange(total) |>
    dplyr::pull(atc_level1_name)

  counts$atc_level1_name <- factor(counts$atc_level1_name, levels = group_order)
  counts$evidence_category <- factor(counts$evidence_category, levels = EVIDENCE_LEVELS)

  wide <- tidyr::pivot_wider(counts, names_from = evidence_category, values_from = n_studies)

  # When the two values tie, the points (and their labels) land exactly on
  # top of each other and one fully hides the other. Nudge both slightly
  # apart vertically only in that case, so a tie still reads as two points.
  wide$tied <- wide$Preclinical == wide$Clinical
  counts <- dplyr::left_join(counts, dplyr::select(wide, atc_level1_name, tied), by = "atc_level1_name")
  counts$y_num <- as.numeric(counts$atc_level1_name) +
    ifelse(counts$tied, ifelse(counts$evidence_category == "Preclinical", 0.12, -0.12), 0)
  # Labels for a tie also need separating — same x and nearly the same y,
  # directly above each point, would otherwise print right on top of
  # each other.
  counts$label_x <- counts$n_studies +
    ifelse(counts$tied, ifelse(counts$evidence_category == "Preclinical", -0.7, 0.7), 0)

  ggplot2::ggplot() +
    ggplot2::geom_segment(
      data = wide,
      ggplot2::aes(
        x = Preclinical, xend = Clinical,
        y = as.numeric(atc_level1_name), yend = as.numeric(atc_level1_name)
      ),
      color = "grey80", linewidth = 0.7
    ) +
    ggplot2::geom_point(
      data = counts,
      ggplot2::aes(x = n_studies, y = y_num, color = evidence_category),
      size = 3.4
    ) +
    ggplot2::geom_text(
      data = counts,
      ggplot2::aes(x = label_x, y = y_num, label = n_studies, color = evidence_category),
      size = 2.7, family = FONT_FAMILY, show.legend = FALSE, vjust = -1.3
    ) +
    ggplot2::scale_color_manual(values = PALETTE$evidence, name = NULL) +
    ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0.04, 0.08))) +
    ggplot2::scale_y_continuous(breaks = seq_along(group_order), labels = group_order) +
    ggplot2::labs(x = "Studies (n)", y = NULL) +
    theme_journal() +
    ggplot2::theme(
      panel.grid.major.y = ggplot2::element_line(color = "grey93", linewidth = 0.3),
      legend.position = "top"
    )
}

if (sys.nframe() == 0) {
  save_figure(build_heatmap(), "fig02_heatmap_class_evidence", width = 5.5, height = 5.5)
}
