#' Flattens list columns to "; "-separated text for a readable CSV export.
flatten_list_cols <- function(df) {
  dplyr::mutate(df, dplyr::across(
    dplyr::where(is.list),
    \(col) purrr::map_chr(col, \(x) paste(x, collapse = "; "))
  ))
}

#' Saves a table as RDS (exact, list columns intact) and as a flattened
#' CSV (for human inspection) inside a stage directory.
write_stage <- function(df, dir, name) {
  fs::dir_create(dir)
  saveRDS(df, fs::path(dir, paste0(name, ".rds")))
  utils::write.csv(flatten_list_cols(df), fs::path(dir, paste0(name, ".csv")),
                    row.names = FALSE, na = "")
  invisible(df)
}

#' Saves the outputs of stage 1 (search).
save_stage1_outputs <- function(search_log, articles_combined, pubmed_chunk_log, ctgov_chunk_log, cfg) {
  dir <- cfg$paths$stage1
  write_stage(search_log, dir, "search_log")
  write_stage(articles_combined, dir, "articles_raw")
  write_stage(pubmed_chunk_log, dir, "pubmed_chunk_log")
  write_stage(ctgov_chunk_log, dir, "ctgov_chunk_log")
  logger::log_info("Stage 1 outputs saved to {dir}")
  TRUE
}

