#' 100%-stacked bar: composition of evidence levels contributed by each
#' source. ClinicalTrials.gov entries are registry records (clinical by
#' definition); PubMed is where the preclinical evidence comes from — this
#' figure makes that split explicit rather than leaving it implicit.

source("R/figures/utils_figures.R")

build_source_evidence <- function() {
  articles <- utils::read.csv("data/04_texto_completo/figure_dataset_articles.csv", stringsAsFactors = FALSE)

  by_source <- articles |>
    tidyr::pivot_longer(
      cols = c(evidence_in_vitro, evidence_in_vivo, evidence_clinical),
      names_to = "evidence_level", values_to = "present"
    ) |>
    dplyr::filter(present) |>
    dplyr::mutate(
      evidence_level = c(
        evidence_in_vitro = "In vitro", evidence_in_vivo = "In vivo", evidence_clinical = "Clinical"
      )[evidence_level],
      source = c(pubmed = "PubMed", clinicaltrials = "ClinicalTrials.gov")[source]
    ) |>
    dplyr::count(source, evidence_level, name = "n_studies") |>
    dplyr::group_by(source) |>
    dplyr::mutate(share = n_studies / sum(n_studies)) |>
    dplyr::ungroup()

  by_source$evidence_level <- factor(by_source$evidence_level, levels = c("In vitro", "In vivo", "Clinical"))

  ggplot2::ggplot(by_source, ggplot2::aes(x = source, y = share, fill = evidence_level)) +
    ggplot2::geom_col(width = 0.55, color = "white", linewidth = 0.3) +
    ggplot2::geom_text(
      ggplot2::aes(label = n_studies),
      position = ggplot2::position_stack(vjust = 0.5), size = 3.2, color = "white"
    ) +
    ggplot2::scale_fill_manual(values = PALETTE$evidence, name = "Evidence level") +
    ggplot2::scale_y_continuous(labels = scales::percent_format(), expand = ggplot2::expansion(mult = c(0, 0.02))) +
    ggplot2::coord_flip() +
    ggplot2::labs(
      title = "Evidence level by source",
      subtitle = "Share of included studies, by where they were identified",
      x = NULL, y = "Share of studies"
    ) +
    theme_journal() +
    ggplot2::theme(panel.grid.major.y = ggplot2::element_blank())
}

if (sys.nframe() == 0) {
  save_figure(build_source_evidence(), "fig06_source_evidence", width = 7, height = 3.5)
}
