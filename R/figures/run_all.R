#' Regenerates every figure from scratch, in order. Run this one file after
#' finishing full-text review (and after filling in the manual counts at
#' the top of 01_fig_prisma_flow.R) — it rebuilds the datasets and every
#' figure from whatever is currently in data/03_cribado/clasificacion_pre_rayyan.csv.
#'
#' Each step below just sources that script's function definitions, then
#' calls the same build + save it would run on its own via
#' `Rscript R/figures/0N_....R` — this file is only the orchestrator.

source("R/figures/00_prepare_figure_data.R")
invisible(prepare_figure_data())

source("R/figures/01_fig_prisma_flow.R")
save_figure(build_prisma_flow(), "fig01_prisma_flow", width = 7.5, height = 9)

source("R/figures/02_fig_heatmap_class_evidence.R")
save_figure(build_heatmap(), "fig02_heatmap_class_evidence", width = 7, height = 6)

source("R/figures/03_fig_top_drugs.R")
save_figure(build_top_drugs(), "fig03_top_drugs", width = 7, height = 5.5)

source("R/figures/04_fig_year_trend.R")
save_figure(build_year_trend(), "fig04_year_trend", width = 7.5, height = 5)

source("R/figures/05_fig_atc_breadth.R")
save_figure(build_atc_breadth(), "fig05_atc_breadth", width = 7, height = 5.5)

source("R/figures/06_fig_source_evidence.R")
save_figure(build_source_evidence(), "fig06_source_evidence", width = 7, height = 3.5)

cat("Listo. Figuras en outputs/figures/\n")
