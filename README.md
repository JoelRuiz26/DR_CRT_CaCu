# Pipeline de búsqueda — Reposicionamiento farmacológico y quimiorradiación en cáncer cervicouterino

Búsqueda bibliográfica para una revisión de alcance (PRISMA-ScR) sobre
fármacos no oncológicos combinados con cisplatino o carboplatino, con o sin
radiación, en cáncer cervicouterino.

Este repositorio hace solo esto: arma el catálogo de fármacos, busca en
PubMed y ClinicalTrials.gov, aplica exclusiones estructurales, y genera el
archivo que se importa a Rayyan para el cribado. El detalle completo de
cada decisión metodológica está en `DECISIONS.md`.

---

## Esquema del pipeline

```
config.yml (cadena de búsqueda, parámetros)
            │
            ▼
RxClass — clases ATC no oncológicas (excluye L01/L02)
            │   2,826 ingredientes
            ▼
RxNorm Prescribable Content — filtro de vigencia
            │
            ▼
Catálogo de fármacos no oncológicos y vigentes
            │   1,626 ingredientes
            │
     ┌──────┴──────┐
     ▼             ▼
  PubMed       ClinicalTrials.gov
     │             │
     └──────┬──────┘
            ▼
articles_raw.csv — 460 registros combinados, sin deduplicar
            │
            ▼
classify_metadata_exclusions() — 32 excluidos
            │
            ▼
para_rayyan.ris — 428 registros ← salida de este repositorio
            │
            ▼
   (fuera de este repo) Rayyan: deduplicación al importar,
   cribado ciego por 2 revisores, kappa de Cohen
```

---

## Scripts (`R/`)

1. **`01_catalogo_farmacos.R`** — catálogo de fármacos no oncológicos y
   vigentes (RxClass + RxNorm). 2,826 → 1,626 ingredientes.
2. **`02_fetch_pubmed.R`** / **`02_fetch_clinicaltrials.R`** — búsqueda en
   cada fuente, mismo criterio: población AND fármaco AND tratamiento.
   243 + 217 = 460 registros.
3. **`03_export_rayyan.R`** — exclusiones estructurales (ensayos sin datos,
   revisiones) y exporta a `para_rayyan.ris`. 460 → 428.

`utils_http.R`, `utils_io.R`, `utils_logging.R` — utilidades compartidas.

---

## Cómo correr

```r
renv::restore()          # una vez, para instalar las versiones fijadas
targets::tar_make()      # corre el pipeline
targets::tar_visnetwork()  # ver el grafo
```

El log de cada corrida queda en `logs/pipeline.log`.
