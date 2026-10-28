#' Sets up logging with console and file output.
#' @param log_file path to the log file (directory created if missing).
#' @param level minimum level, e.g. "INFO", "DEBUG".
setup_logging <- function(log_file = "logs/pipeline.log", level = "INFO") {
  fs::dir_create(fs::path_dir(log_file))
  logger::log_threshold(logger::as.loglevel(level))
  logger::log_appender(logger::appender_tee(log_file), namespace = "global")
  logger::log_layout(logger::layout_glue_generator(
    format = "{time} [{level}] {msg}"
  ), namespace = "global")
  invisible(TRUE)
}

#' Logs a pipeline step's record count in a uniform message.
#' @param step short step name, e.g. "rxnorm_fetch".
#' @param n record count.
#' @param detail optional extra text.
log_step_count <- function(step, n, detail = NULL) {
  msg <- sprintf("%s: n = %d", step, n)
  if (!is.null(detail)) msg <- paste0(msg, " (", detail, ")")
  logger::log_info(msg)
  invisible(n)
}
