`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x))) y else x

#' Slug seguro para nombres de archivo a partir de un texto arbitrario.
slug <- function(x) gsub("[^A-Za-z0-9]+", "_", tolower(x))

#' NA si la cadena esta vacia o ausente.
na_if_empty <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_character_)
  x <- x[[1]]
  if (is.na(x) || x == "") NA_character_ else x
}

#' GET a una API JSON con reintentos y retroceso exponencial ({httr2}).
#' @param url endpoint base.
#' @param query lista de parametros de consulta.
#' @param max_tries reintentos maximos ante 429/5xx.
http_get_json <- function(url, query = list(), max_tries = 5) {
  resp <- httr2::request(url) |>
    httr2::req_url_query(!!!query) |>
    httr2::req_user_agent("DR_CRT_CaCu-review-pipeline (contacto: josejoelruizhernandez@gmail.com)") |>
    httr2::req_retry(
      max_tries = max_tries,
      is_transient = function(resp) httr2::resp_status(resp) %in% c(429, 500, 502, 503, 504)
    ) |>
    httr2::req_perform()
  httr2::resp_body_json(resp, simplifyVector = FALSE)
}

#' Archiva una respuesta cruda de API sin modificar, con marca de tiempo UTC.
#' Es un requisito de PRISMA: la fecha exacta de busqueda debe quedar registrada.
archive_raw_response <- function(content, dir, prefix) {
  fs::dir_create(dir)
  ts <- format(Sys.time(), "%Y%m%dT%H%M%OS3Z", tz = "UTC")
  path <- fs::path(dir, sprintf("%s_%s.json", prefix, ts))
  jsonlite::write_json(content, path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  path
}
