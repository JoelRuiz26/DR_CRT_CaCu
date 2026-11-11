#' Grouped horizontal bars: pharmacological group (WHO ATC Level 1) by
#' evidence category (Preclinical / Clinical). Bars anchor to zero, so
#' magnitude comparisons across groups and between the two categories are
#' honest at a glance — the standard form for this, and the same
#' language (bars, direct labels, one accent per series) as every other
#' figure in this set.

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
  counts$label <- ifelse(counts$n_studies == 0, "", as.character(counts$n_studies))

  ggplot2::ggplot(counts, ggplot2::aes(x = n_studies, y = atc_level1_name, fill = evidence_category)) +
    ggplot2::geom_col(
      position = ggplot2::position_dodge(width = 0.75), width = 0.65
    ) +
    ggplot2::geom_text(
      ggplot2::aes(label = label),
      position = ggplot2::position_dodge(width = 0.75),
      hjust = -0.4, size = 2.7, family = FONT_FAMILY, color = "black"
    ) +
    ggplot2::scale_fill_manual(values = PALETTE$evidence, name = "Evidence level") +
    ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0, 0.12))) +
    ggplot2::labs(x = "Studies (n)", y = NULL) +
    theme_journal()
}

if (sys.nframe() == 0) {
  save_figure(build_heatmap(), "fig02_heatmap_class_evidence", width = 6, height = 5.5)
}
