#' Shared theme, color assignments, and ATC Level-1 lookup for every script
#' in R/figures/. Colors are the Okabe-Ito colorblind-safe set, assigned once
#' per entity here and reused as-is everywhere else — never re-picked or
#' re-cycled per figure.

PALETTE <- list(
  source = c("PubMed" = "#0072B2", "ClinicalTrials.gov" = "#D55E00"),
  evidence = c("In vitro" = "#009E73", "In vivo" = "#E69F00", "Clinical" = "#CC79A7"),
  sequential = "viridis"
)

#' WHO ATC Level 1 (anatomical main group) code -> name, for the subset of
#' letters that can appear in this catalog (L01/L02, oncology, are excluded
#' upstream — see R/01_catalogo_farmacos.R).
ATC_LEVEL1_NAMES <- c(
  A = "Alimentary tract & metabolism",
  B = "Blood & blood forming organs",
  C = "Cardiovascular system",
  D = "Dermatologicals",
  G = "Genito-urinary system & sex hormones",
  H = "Systemic hormonal preparations",
  J = "Antiinfectives for systemic use",
  L = "Immunomodulating agents",
  M = "Musculo-skeletal system",
  N = "Nervous system",
  P = "Antiparasitic products & insecticides",
  R = "Respiratory system",
  S = "Sensory organs",
  V = "Various"
)

#' Minimal, print-ready ggplot2 theme shared by every figure.
theme_journal <- function(base_size = 11) {
  ggplot2::theme_minimal(base_size = base_size, base_family = "sans") +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(color = "grey88", linewidth = 0.3),
      axis.line = ggplot2::element_line(color = "grey40", linewidth = 0.3),
      axis.ticks = ggplot2::element_line(color = "grey40", linewidth = 0.3),
      plot.title = ggplot2::element_text(face = "bold", size = ggplot2::rel(1.05)),
      plot.subtitle = ggplot2::element_text(color = "grey30", size = ggplot2::rel(0.9)),
      plot.caption = ggplot2::element_text(color = "grey45", size = ggplot2::rel(0.75), hjust = 0),
      legend.position = "bottom",
      legend.title = ggplot2::element_text(size = ggplot2::rel(0.85)),
      strip.background = ggplot2::element_rect(fill = "grey95", color = NA),
      strip.text = ggplot2::element_text(face = "bold")
    )
}

#' Saves a figure as both a print-resolution PNG and a vector PDF.
save_figure <- function(plot, name, width = 7, height = 5, dir = "outputs/figures") {
  fs::dir_create(dir)
  ggplot2::ggsave(fs::path(dir, paste0(name, ".png")), plot, width = width, height = height, dpi = 320, bg = "white")
  ggplot2::ggsave(fs::path(dir, paste0(name, ".pdf")), plot, width = width, height = height, device = "pdf")
  logger::log_info("Figura guardada: {dir}/{name}.png (.pdf)")
  invisible(plot)
}
