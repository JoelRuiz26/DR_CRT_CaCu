`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x))) y else x

#' Safe filename slug from arbitrary text.
slug <- function(x) gsub("[^A-Za-z0-9]+", "_", tolower(x))

#' NA if the string is empty or missing.
na_if_empty <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_character_)
  x <- x[[1]]
  if (is.na(x) || x == "") NA_character_ else x
}

#' GET against a JSON API with retries and exponential backoff.
#' @param url base endpoint.
#' @param query list of query parameters.
#' @param max_tries max retries on 429/5xx.
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

#' Archives a raw API response unmodified, with a UTC timestamp — required
#' by PRISMA to record the exact search date.
archive_raw_response <- function(content, dir, prefix) {
  fs::dir_create(dir)
  ts <- format(Sys.time(), "%Y%m%dT%H%M%OS3Z", tz = "UTC")
  path <- fs::path(dir, sprintf("%s_%s.json", prefix, ts))
  jsonlite::write_json(content, path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  path
}
