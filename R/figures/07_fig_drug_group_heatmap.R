#' Evidence map: every distinct drug (one row each, no drug double-counted
#' across groups — see the primary-ATC-class fix in
#' 00_prepare_figure_data.R) by evidence category, grouped and faceted by
#' WHO ATC Level 1 pharmacological group. The detailed, full-corpus
#' companion to fig02's group-level summary — the kind of dense evidence
#' map a scoping review's supplementary material typically carries.

source("R/figures/utils_figures.R")

EVIDENCE_LEVELS <- c("Preclinical", "Clinical")

build_drug_group_heatmap <- function() {
  long <- utils::read.csv("data/04_texto_completo/figure_dataset_long.csv", stringsAsFactors = FALSE)

  counts <- long |>
    dplyr::filter(!is.na(evidence_category) & nzchar(evidence_category)) |>
    dplyr::distinct(atc_level1_name, drug, evidence_category, source_id) |>
    dplyr::count(atc_level1_name, drug, evidence_category, name = "n_studies") |>
    tidyr::complete(
      tidyr::nesting(atc_level1_name, drug), evidence_category = EVIDENCE_LEVELS,
      fill = list(n_studies = 0)
    )

  group_order <- counts |>
    dplyr::group_by(atc_level1_name) |>
    dplyr::summarise(total = sum(n_studies), .groups = "drop") |>
    dplyr::arrange(dplyr::desc(total)) |>
    dplyr::pull(atc_level1_name)

  drug_order <- counts |>
    dplyr::group_by(drug) |>
    dplyr::mutate(total = sum(n_studies)) |>
    dplyr::ungroup() |>
    dplyr::distinct(atc_level1_name, drug, total) |>
    dplyr::arrange(factor(atc_level1_name, levels = group_order), dplyr::desc(total), drug) |>
    dplyr::pull(drug)

  # facet_grid(space = "free_y") sizes each group's panel strictly by its
  # own number of drugs — a group with only 1-2 drugs gets a sliver too
  # short to hold its (wrapped, multi-line) group-name label, which then
  # overflows into the next panel. Pad any such group with blank rows (no
  # tile, no label) so every panel has enough vertical room.
  MIN_ROWS <- 3
  group_sizes <- table(dplyr::distinct(counts, atc_level1_name, drug)$atc_level1_name)
  padding <- do.call(rbind, lapply(names(group_sizes)[group_sizes < MIN_ROWS], function(g) {
    n_pad <- MIN_ROWS - group_sizes[[g]]
    tidyr::expand_grid(
      atc_level1_name = g, drug = strrep(" ", seq_len(n_pad)),
      evidence_category = EVIDENCE_LEVELS, n_studies = NA_real_
    )
  }))
  if (!is.null(padding)) {
    drug_order <- c(drug_order, unique(padding$drug))
    counts <- dplyr::bind_rows(counts, padding)
  }

  counts$atc_level1_name <- factor(counts$atc_level1_name, levels = group_order)
  display_drug <- ifelse(trimws(counts$drug) == "", counts$drug, stringr::str_to_sentence(counts$drug))
  display_levels <- ifelse(trimws(drug_order) == "", drug_order, stringr::str_to_sentence(drug_order))
  counts$drug <- factor(display_drug, levels = display_levels)
  counts$evidence_category <- factor(counts$evidence_category, levels = EVIDENCE_LEVELS)
  counts$label <- ifelse(is.na(counts$n_studies) | counts$n_studies == 0, "", as.character(counts$n_studies))
  counts$label_color <- ifelse(!is.na(counts$n_studies) & counts$n_studies > max(counts$n_studies, na.rm = TRUE) * 0.6, "white", "black")

  n_drugs <- length(unique(counts$drug))
  n_groups <- length(group_order)

  p <- ggplot2::ggplot(counts, ggplot2::aes(x = evidence_category, y = drug, fill = n_studies)) +
    ggplot2::geom_tile(color = "white", linewidth = 0.4) +
    ggplot2::geom_text(
      ggplot2::aes(label = label, color = label_color),
      size = 2.5, family = FONT_FAMILY, show.legend = FALSE
    ) +
    ggplot2::scale_color_identity() +
    ggplot2::scale_fill_gradient(
      name = "Studies\n(n)", low = PALETTE$sequential_low, high = PALETTE$sequential_high,
      na.value = "white",
      guide = ggplot2::guide_colorbar(barwidth = 0.5, barheight = 6, ticks = FALSE)
    ) +
    ggplot2::scale_x_discrete(position = "top", expand = c(0, 0)) +
    ggplot2::scale_y_discrete(expand = c(0, 0)) +
    ggplot2::facet_grid(
      rows = ggplot2::vars(atc_level1_name), scales = "free_y", space = "free_y",
      labeller = ggplot2::labeller(atc_level1_name = ggplot2::label_wrap_gen(14))
    ) +
    ggplot2::labs(x = NULL, y = NULL) +
    theme_journal() +
    ggplot2::theme(
      axis.line = ggplot2::element_blank(),
      axis.ticks = ggplot2::element_blank(),
      axis.text.y = ggplot2::element_text(size = ggplot2::rel(0.85), hjust = 1),
      axis.text.x = ggplot2::element_text(size = ggplot2::rel(1), face = "bold"),
      strip.background = ggplot2::element_rect(fill = "grey92", color = NA),
      strip.text.y = ggplot2::element_text(
        angle = 0, hjust = 0.5, size = ggplot2::rel(0.78), face = "bold", color = PALETTE$sequential_high
      ),
      panel.border = ggplot2::element_rect(color = "grey80", fill = NA, linewidth = 0.4),
      panel.spacing = ggplot2::unit(9, "pt"),
      legend.position = "right"
    )

  list(plot = p, n_drugs = n_drugs, n_groups = n_groups)
}

if (sys.nframe() == 0) {
  res <- build_drug_group_heatmap()
  fig_height <- max(10, res$n_drugs * 0.155 + res$n_groups * 0.22)
  save_figure(res$plot, "fig07_drug_group_heatmap", width = 6.5, height = fig_height)
}
