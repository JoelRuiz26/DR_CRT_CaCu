library(targets)

tar_option_set(
  packages = c(
    "dplyr", "purrr", "tibble", "tidyr", "stringr", "xml2", "jsonlite",
    "httr2", "rentrez", "yaml", "fs", "logger", "cli"
  )
)

tar_source("R")

list(
  tar_target(cfg_file, "config.yml", format = "file"),
  # setup_logging() corre como efecto lateral de leer la config, para que el
  # log a archivo quede activo antes que cualquier otro target.
  tar_target(cfg, {
    x <- yaml::read_yaml(cfg_file)
    setup_logging(x$logging$file, x$logging$level)
    # Ventana movil de N anios hacia atras (retrieval$years_back), calculada
    # una sola vez aqui para que las dos fuentes usen exactamente el mismo
    # anio de corte y quede documentado en el log de esta corrida. Ver
    # DECISIONS.md para la justificacion (Ashburn & Thor 2004).
    x$retrieval$date_from_year <- as.integer(format(Sys.Date(), "%Y")) - x$retrieval$years_back
    # 2026-10-16: antes el filtro de PubMed usaba "3000" como limite superior
    # (idioma comun en cadenas de busqueda bibliografica para decir "sin
    # limite", pero confuso para un lector que no conoce la convencion, y
    # tecnicamente impreciso: nada puede estar publicado en el anio 3000).
    # Como la fecha de corte YA se calcula aqui dinamicamente en cada
    # corrida, el limite superior tambien se calcula igual, con el anio real
    # de la corrida — no hay motivo para seguir usando un numero inventado.
    x$retrieval$date_to_year <- as.integer(format(Sys.Date(), "%Y"))
    logger::log_info("Ventana de busqueda: desde {x$retrieval$date_from_year} (ultimos {x$retrieval$years_back} anios)")
    x
  }),

  # Catalogo de farmacos no oncologicos (RxNorm/ATC). Se necesita ANTES de la
  # etapa 1 porque alimenta directamente la busqueda (nombre de farmaco es
  # parte de la cadena, no solo un filtro posterior). Ver DECISIONS.md.
  tar_target(drug_catalog, build_drug_catalog(cfg)),

  # --- Etapa 1: busqueda. Cadena unica reorganizada el 2026-09-29 (decision
  # explicita del usuario): poblacion AND nombre_de_farmaco AND tratamiento,
  # en lotes, igual en las dos fuentes (PubMed y ClinicalTrials.gov). Se
  # retiro la rama de sensibilizacion (vocabulario de mecanismo, sin nombrar
  # farmaco) que existio brevemente antes — ver DECISIONS.md para el
  # historial completo de por que existio y por que se retiro. ---
  tar_target(pubmed_raw, fetch_pubmed(cfg, drug_catalog)),
  tar_target(clinicaltrials_raw, fetch_clinicaltrials(cfg, drug_catalog)),
  tar_target(search_log, dplyr::bind_rows(pubmed_raw$log, clinicaltrials_raw$log)),
  tar_target(articles_combined, dplyr::bind_rows(pubmed_raw$articles, clinicaltrials_raw$articles)),
  tar_target(stage1_outputs, save_stage1_outputs(search_log, articles_combined, pubmed_raw$chunk_log, clinicaltrials_raw$chunk_log, cfg)),

  tar_target(drug_catalog_output, write_stage(drug_catalog, cfg$paths$stage5, "drug_catalog")),

  # --- Etapa 2: exportar TODO lo combinado a Rayyan (RIS), SIN deduplicar
  # en R. Decision explicita del usuario (2026-10-15): Rayyan ya deduplica
  # al importar (DOI/titulo/autores/anio) con un algoritmo publicado y
  # mantenido — reimplementar esa misma logica en R era trabajo duplicado,
  # no aportaba rigor. La antigua etapa 2 (`deduplicate_articles()`,
  # R/02_deduplicate.R) se retiro por completo; el conteo de "duplicados
  # eliminados" del diagrama PRISMA ahora se llena con lo que reporte
  # Rayyan tras el import, no antes en R. Lo que SI se queda en R son las
  # exclusiones estructurales de `classify_metadata_exclusions()` (estado
  # de ClinicalTrials.gov, tipo de publicacion de PubMed) porque son reglas
  # sobre metadatos que Rayyan no tiene forma de evaluar — no son
  # deduplicacion. Igual que antes: NINGUN registro se filtra ni excluye
  # por si el fármaco aparece o no en el texto — ver DECISIONS.md
  # 2026-09-30. El cribado real (leer y decidir, y ahora tambien
  # deduplicar) lo hacen dos revisores humanos en Rayyan, fuera de R. Ver
  # DECISIONS.md 2026-10-15 para el historial completo. ---
  tar_target(screening_set, export_screening_set(articles_combined, cfg))
)
