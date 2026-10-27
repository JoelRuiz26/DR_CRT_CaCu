#' Todas las clases ATC de segundo nivel (grupo terapeutico principal, ej
#' "A10"), excluyendo L01/L02 (antineoplasicos/terapia endocrina oncologica).
#' Con esto el catalogo automaticamente implementa la regla "se excluye solo
#' si TODOS los codigos ATC de un ingrediente son L01/L02" (ver DECISIONS.md
#' etapa 1A original): un ingrediente que aparezca en cualquier clase no
#' oncologica queda incluido, sin importar si tambien tiene clasificacion
#' oncologica en otro lado.
atc_non_oncologic_classes <- function() {
  res <- http_get_json("https://rxnav.nlm.nih.gov/REST/rxclass/allClasses.json",
                        list(classTypes = "ATC1-4"))
  classes <- res$rxclassMinConceptList$rxclassMinConcept
  ids <- purrr::map_chr(classes, "classId")
  lvl2 <- ids[nchar(ids) == 3]
  setdiff(unique(lvl2), c("L01", "L02"))
}

#' Ingredientes (nombre + RxCUI) miembros de una clase ATC.
atc_class_members <- function(class_id) {
  res <- tryCatch(
    http_get_json("https://rxnav.nlm.nih.gov/REST/rxclass/classMembers.json",
                  list(classId = class_id, relaSource = "ATC")),
    error = function(e) NULL
  )
  items <- res$drugMemberGroup$drugMember
  if (is.null(items) || length(items) == 0) return(tibble::tibble())
  purrr::map_dfr(items, function(x) {
    tibble::tibble(
      drug_id = x$minConcept$rxcui,
      preferred_name = x$minConcept$name,
      atc_class = class_id
    )
  })
}

#' Un ingrediente esta aprobado y VIGENTE en EE. UU. si tiene al menos un
#' descendiente SCD/SBD (droga clinica o de marca formulada) dentro del
#' "RxNorm Current Prescribable Content" — el subconjunto que la propia
#' NLM mantiene y depura para reflejar solo lo que esta REALMENTE
#' prescribible hoy (excluye conceptos historicos/retirados), vía la API
#' `Prescribe` (distinta del endpoint `rxcui/.../related.json` normal, que
#' sí incluye historico). Todo dentro de RxNorm — no hace falta consultar
#' la FDA por separado.
#'
#' 2026-10-22, REEMPLAZA dos versiones anteriores en el mismo día:
#' 1) `rxcui_has_marketed_form()` — solo revisaba "¿existe un SCD/SBD en
#'    RxNorm?" sin confirmar vigencia. Contaba como "comercializados"
#'    fármacos descontinuados hace años (cephradine, danaparoid,
#'    secobarbital...). Acuerdo con una consulta directa a la FDA: 74%
#'    (111/150 en la validación).
#' 2) `fda_has_active_marketed_form()` — cruzaba por RXCUI contra el
#'    directorio NDC de la FDA (openFDA) para confirmar vigencia. Mejoró
#'    el problema de (1), pero introdujo uno nuevo: falsos negativos en
#'    biológicos y suplementos OTC (evinacumab, pramlintide, calcio
#'    citrato, hierro...) que SÍ están vigentes pero mi consulta al
#'    directorio NDC no los capturaba bien.
#' Este metodo (Prescribable Content) se validó contra la MISMA consulta
#' directa a la FDA de (2) en la misma muestra de 150: **91% de acuerdo
#' (136/150)**, mejor que las dos versiones anteriores, y en los 14 casos
#' de desacuerdo el patrón indica que es la consulta a la FDA la que falla
#' (los 13 fármacos en disputa son casos reales conocidos de EE. UU.), no
#' Prescribable Content. Ademas es mas simple: una sola llamada por
#' ingrediente, sin necesitar la FDA como fuente aparte. Ver DECISIONS.md
#' para el detalle completo de las tres validaciones.
rxnorm_is_prescribable <- function(rxcui) {
  res <- tryCatch(
    http_get_json(paste0("https://rxnav.nlm.nih.gov/REST/Prescribe/rxcui/", rxcui, "/related.json"), list(tty = "SCD SBD")),
    error = function(e) NULL
  )
  cg <- res$relatedGroup$conceptGroup
  if (is.null(cg)) return(FALSE)
  any(vapply(cg, function(g) length(g$conceptProperties %||% list()) > 0, logical(1)))
}

#' Construye el catalogo automatico de fármacos no oncologicos: (1) enumera
#' todas las clases ATC de nivel 2 excepto L01/L02 y une sus miembros —
#' asi implementa la regla "se excluye solo si TODOS los codigos ATC de un
#' ingrediente son L01/L02", sin importar si ya esta aprobado en oncologia
#' en otro lado; (2) DESPUES, como paso separado, filtra a los que tienen
#' al menos una forma comercializada VIGENTE (`rxnorm_is_prescribable()`).
#' El orden importa: filtrar "no oncologico Y aprobado" como un solo
#' criterio conjunto sesgaria contra fármacos ya reposicionados que tengan
#' indicacion oncologica aprobada ademas de la no oncologica original —
#' separar los dos pasos evita ese sesgo. Ver DECISIONS.md.
build_drug_catalog <- function(cfg) {
  raw_dir <- fs::path(cfg$paths$raw, "..", "05_catalogo_farmacos") |> fs::path_norm()
  fs::dir_create(raw_dir)

  classes <- atc_non_oncologic_classes()
  log_step_count("atc_classes_no_oncologicas", length(classes))

  rows <- purrr::map(classes, function(cid) {
    members <- atc_class_members(cid)
    Sys.sleep(0.1)
    members
  })
  archive_raw_response(list(classes = classes, n_members_total = sum(purrr::map_int(rows, nrow))),
                        raw_dir, "atc_enumeration_summary")

  catalog <- dplyr::bind_rows(rows) |>
    dplyr::mutate(preferred_name = tolower(preferred_name)) |>
    dplyr::group_by(drug_id, preferred_name) |>
    dplyr::summarise(atc_classes = list(unique(atc_class)), .groups = "drop")
  log_step_count("catalogo_ingredientes_no_oncologicos_atc", nrow(catalog))

  is_marketed <- purrr::map_lgl(catalog$drug_id, function(id) {
    ok <- rxnorm_is_prescribable(id)
    Sys.sleep(0.1)
    ok
  })
  archive_raw_response(
    list(n_total = nrow(catalog), n_con_forma_comercializada_vigente = sum(is_marketed)),
    raw_dir, "fda_marketed_filter_summary"
  )
  catalog <- catalog[is_marketed, ]

  log_step_count("catalogo_ingredientes_unicos", nrow(catalog))
  catalog
}

#' Excepciones manuales al catalogo automatico: ingredientes que el
#' cruce automatico por clase ATC clasifica como "no oncologicos" (porque
#' tienen algun codigo ATC fuera de L01/L02) pero que en la practica son
#' farmacos oncologicos con una clasificacion secundaria no oncologica.
#' Cada uno con evidencia, nunca se excluye en silencio. Ver DECISIONS.md.
#'   - bevacizumab: ATC real L01FG (oncologico, inhibidor VEGF) + S01LA
#'     (antineovascularizacion oftalmologica) — es un farmaco oncologico
#'     reposicionado HACIA oftalmologia, direccion opuesta a la que busca
#'     esta revision. Confirmado con muestra: articulos de "bevacizumab"
#'     en el corpus son de inmunoterapia oncologica combinada.
CATALOG_MANUAL_EXCLUDE <- c("bevacizumab")

#' Terminos genericos bioquimicos que el catalogo automatico incluye por
#' tener un codigo ATC propio (ej. oxigeno medicinal, glucosa intravenosa)
#' pero que en la practica generan mayormente ruido de vocabulario general
#' (especies reactivas de oxigeno, metabolismo celular) en vez de senalar
#' que se administro como intervencion. Confirmado con muestra de texto.
CATALOG_GENERIC_NOISE_EXCLUDE <- c("oxygen", "glucose", "hydrogen peroxide")

#' Separa los nombres del catalogo (ya sin exclusiones manuales) en de una
#' sola palabra (se buscan por interseccion de conjuntos, rapido) y de
#' varias palabras (se buscan por subcadena fija, sin retroceso de regex —
#' una alternancia regex de ~2800 ramas contra texto completo de ~90 mil
#' caracteres por articulo resulto demasiado lenta, ver DECISIONS.md).
prepare_match_names <- function(catalog, min_chars = 4) {
  names <- unique(catalog$preferred_name)
  names <- names[nchar(names) >= min_chars]
  names <- setdiff(names, c(CATALOG_MANUAL_EXCLUDE, CATALOG_GENERIC_NOISE_EXCLUDE))
  list(single = names[!grepl(" ", names)], multi = names[grepl(" ", names)])
}

#' Fármacos del catalogo mencionados en un texto: interseccion de tokens
#' para nombres de una palabra, subcadena fija para los de varias.
find_drug_mentions <- function(text, names_single, names_multi) {
  tokens <- unique(stringi::stri_extract_all_words(text)[[1]])
  hits_single <- intersect(tokens, names_single)
  hits_multi <- names_multi[stringi::stri_detect_fixed(text, names_multi)]
  c(hits_single, hits_multi)
}

#' Empareja el catalogo de farmacos contra un texto (titulo+resumen, o mas
#' adelante texto completo) y clasifica. NO se llama en el grafo actual de
#' _targets.R — decision explicita del usuario (2026-09-30): el nombre de
#' farmaco ya es obligatorio en la busqueda (etapa 1), asi que filtrar otra
#' vez por su presencia en el texto antes de Rayyan quedaba mal (redundante
#' para PubMed, e incorrectamente estricto para ClinicalTrials.gov, cuyo
#' buscador confirma el farmaco en campos que no siempre estan en el
#' resumen). Se conserva para reusarse en la etapa 5 (emparejamiento fino
#' para Tabla 1, sobre texto completo de los articulos ya incluidos tras
#' Rayyan) — ahi si aplica extraer CON QUE evidencia se menciono cada
#' farmaco, no decidir si se excluye. Ver DECISIONS.md.
match_drugs_to_articles <- function(articles, catalog) {
  names <- prepare_match_names(catalog)
  match_text <- tolower(paste(articles$title, articles$abstract))
  hits <- purrr::map(match_text, find_drug_mentions, names_single = names$single, names_multi = names$multi)

  articles$drug_matches <- hits
  articles$n_drug_matches <- lengths(hits)
  articles$eligibility_status <- dplyr::case_when(
    articles$n_drug_matches > 0 ~ "match_farmaco",
    !is.na(articles$abstract) ~ "excluible_sin_farmaco",
    TRUE ~ "no_verificable_sin_resumen"
  )

  log_step_count("con_match_de_farmaco", sum(articles$eligibility_status == "match_farmaco"))
  log_step_count("excluibles_sin_farmaco", sum(articles$eligibility_status == "excluible_sin_farmaco"))
  log_step_count("no_verificable_sin_resumen", sum(articles$eligibility_status == "no_verificable_sin_resumen"))
  articles
}
