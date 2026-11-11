#' 100%-stacked bar: composition of evidence categories contributed by each
#' source (each study counts once — see evidence_category in
#' 00_prepare_figure_data.R). ClinicalTrials.gov entries are registry
#' records (clinical by definition); PubMed is where the preclinical
#' evidence comes from — this figure makes that split explicit.

source("R/figures/utils_figures.R")

EVIDENCE_LEVELS <- c("Preclinical", "Clinical")

build_source_evidence <- function() {
  articles <- utils::read.csv("data/04_texto_completo/figure_dataset_articles.csv", stringsAsFactors = FALSE)

  by_source <- articles |>
    dplyr::filter(!is.na(evidence_category) & nzchar(evidence_category)) |>
    dplyr::mutate(source = c(pubmed = "PubMed", clinicaltrials = "ClinicalTrials.gov")[source]) |>
    dplyr::count(source, evidence_category, name = "n_studies") |>
    dplyr::group_by(source) |>
    dplyr::mutate(share = n_studies / sum(n_studies)) |>
    dplyr::ungroup()

  by_source$evidence_category <- factor(by_source$evidence_category, levels = EVIDENCE_LEVELS)

  # geom_col with a categorical y and continuous x draws horizontal bars
  # directly — avoids coord_flip(), which on this ggplot2/Cairo combination
  # was duplicating the y axis tick labels as stray text inside the panel.
  ggplot2::ggplot(by_source, ggplot2::aes(y = source, x = share, fill = evidence_category)) +
    ggplot2::geom_col(width = 0.5, color = "white", linewidth = 0.3, orientation = "y") +
    ggplot2::geom_text(
      ggplot2::aes(label = n_studies),
      position = ggplot2::position_stack(vjust = 0.5),
      size = 2.7, family = FONT_FAMILY, color = "white"
    ) +
    ggplot2::scale_fill_manual(values = PALETTE$evidence, name = "Evidence level") +
    ggplot2::scale_x_continuous(labels = scales::percent_format(), expand = ggplot2::expansion(mult = c(0, 0.01))) +
    ggplot2::labs(x = "Share of studies", y = NULL) +
    theme_journal()
}

if (sys.nframe() == 0) {
  # height=3.5 made ggplot2's gtable layout miscompute space for the axis
  # text + legend together (only 2 categories), rendering the longer
  # category label a second time inside the panel. height=5 gives the
  # layout enough room and the glitch is gone — confirmed by bisection.
  save_figure(build_source_evidence(), "fig06_source_evidence", width = 7, height = 5)
}
