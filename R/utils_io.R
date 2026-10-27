#' Aplana columnas de lista a texto separado por "; " para exportar a CSV legible.
flatten_list_cols <- function(df) {
  dplyr::mutate(df, dplyr::across(
    dplyr::where(is.list),
    \(col) purrr::map_chr(col, \(x) paste(x, collapse = "; "))
  ))
}

#' Guarda una tabla en RDS (fiel, con columnas de lista intactas) y CSV
#' aplanado (inspeccion humana) dentro del directorio de una etapa.
write_stage <- function(df, dir, name) {
  fs::dir_create(dir)
  saveRDS(df, fs::path(dir, paste0(name, ".rds")))
  utils::write.csv(flatten_list_cols(df), fs::path(dir, paste0(name, ".csv")),
                    row.names = FALSE, na = "")
  invisible(df)
}

#' Guarda las salidas de la etapa 1 (busqueda).
save_stage1_outputs <- function(search_log, articles_combined, pubmed_chunk_log, ctgov_chunk_log, cfg) {
  dir <- cfg$paths$stage1
  write_stage(search_log, dir, "search_log")
  write_stage(articles_combined, dir, "articles_raw")
  write_stage(pubmed_chunk_log, dir, "pubmed_chunk_log")
  write_stage(ctgov_chunk_log, dir, "ctgov_chunk_log")
  logger::log_info("Outputs de etapa 1 guardados en {dir}")
  TRUE
}

