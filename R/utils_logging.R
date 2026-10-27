#' Configura {logger} con salida a consola y a archivo.
#' @param log_file ruta del archivo de log (se crea el directorio si falta).
#' @param level nivel minimo, ej. "INFO", "DEBUG".
setup_logging <- function(log_file = "logs/pipeline.log", level = "INFO") {
  fs::dir_create(fs::path_dir(log_file))
  logger::log_threshold(logger::as.loglevel(level))
  logger::log_appender(logger::appender_tee(log_file), namespace = "global")
  logger::log_layout(logger::layout_glue_generator(
    format = "{time} [{level}] {msg}"
  ), namespace = "global")
  invisible(TRUE)
}

#' Registra un conteo de un paso del pipeline con un mensaje uniforme.
#' @param step nombre corto del paso, ej. "rxnorm_fetch".
#' @param n numero de registros.
#' @param detail texto adicional opcional.
log_step_count <- function(step, n, detail = NULL) {
  msg <- sprintf("%s: n = %d", step, n)
  if (!is.null(detail)) msg <- paste0(msg, " (", detail, ")")
  logger::log_info(msg)
  invisible(n)
}
