#' Shared theme, color assignments, and ATC Level-1 lookup for every script
#' in R/figures/. Colors are the Okabe-Ito colorblind-safe set, assigned once
#' per entity here and reused as-is everywhere else — never re-picked or
#' re-cycled per figure.

PALETTE <- list(
  # Categorical (identity): Okabe-Ito, colorblind-safe, fixed assignment.
  source = c("PubMed" = "#0072B2", "ClinicalTrials.gov" = "#D55E00"),
  evidence = c("In vitro" = "#009E73", "In vivo" = "#E69F00", "Clinical" = "#CC79A7"),
  # Sequential (magnitude, heatmap only): one hue, white -> dark navy. A
  # plainer, single-hue ramp reads as a clinical/biomedical figure; still
  # monotonic in lightness, so it degrades safely to greyscale.
  sequential_low = "#F7FBFF",
  sequential_high = "#08306B"
)

#' "Nimbus Sans" (Helvetica-equivalent) was tried first but its Cairo font
#' metrics are miscalculated at this size/dpi — ggplot2's gtable layout
#' under-reserves space for axis text and the legend, so long labels render
#' overlapping other elements (confirmed with a minimal reproduction, and
#' confirmed independent of ggplot2 version, 3.5.2 vs 4.0.3). Plain "sans"
#' (DejaVu Sans here) does not have this problem.
FONT_FAMILY <- "sans"

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

#' Restrained, Nature/Lancet-register ggplot2 theme: no in-image title (the
#' caption belongs in the manuscript text, not baked into the figure), thin
#' black axis lines, no gridlines, small print-size type.
theme_journal <- function(base_size = 8.5) {
  ggplot2::theme_minimal(base_size = base_size, base_family = FONT_FAMILY) +
    ggplot2::theme(
      panel.grid = ggplot2::element_blank(),
      axis.line = ggplot2::element_line(color = "black", linewidth = 0.3),
      axis.ticks = ggplot2::element_line(color = "black", linewidth = 0.3),
      axis.ticks.length = ggplot2::unit(2, "pt"),
      axis.text = ggplot2::element_text(color = "black", size = ggplot2::rel(1)),
      axis.title = ggplot2::element_text(color = "black", size = ggplot2::rel(1.05)),
      plot.title = ggplot2::element_blank(),
      plot.subtitle = ggplot2::element_blank(),
      plot.caption = ggplot2::element_blank(),
      legend.position = "right",
      legend.title = ggplot2::element_text(size = ggplot2::rel(0.95)),
      legend.text = ggplot2::element_text(size = ggplot2::rel(0.9)),
      legend.key.size = ggplot2::unit(10, "pt"),
      strip.background = ggplot2::element_blank(),
      strip.text = ggplot2::element_text(face = "bold", size = ggplot2::rel(1)),
      plot.margin = ggplot2::margin(6, 10, 6, 6)
    )
}

#' Saves a figure as both a print-resolution PNG and a vector PDF, same
#' Cairo backend for both so the embedded font matches exactly.
save_figure <- function(plot, name, width = 7, height = 5, dir = "outputs/figures") {
  fs::dir_create(dir)
  ggplot2::ggsave(fs::path(dir, paste0(name, ".png")), plot,
    width = width, height = height, dpi = 600, bg = "white", type = "cairo"
  )
  ggplot2::ggsave(fs::path(dir, paste0(name, ".pdf")), plot,
    width = width, height = height, device = grDevices::cairo_pdf
  )
  logger::log_info("Figura guardada: {dir}/{name}.png (.pdf)")
  invisible(plot)
}
