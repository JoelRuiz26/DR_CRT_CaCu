# Search pipeline — Drug repurposing and chemoradiation in cervical cancer

Literature search pipeline for a scoping review (PRISMA-ScR) on
non-oncological drugs combined with cisplatin or carboplatin, with or
without radiation, in cervical cancer.

This repository does only this: builds the drug catalog, searches PubMed
and ClinicalTrials.gov, applies structural exclusions, and generates the
file imported into Rayyan for screening.

---

## Pipeline

```
config.yml (search strings, parameters)
            │
            ▼
RxClass — non-oncology ATC classes (excludes L01/L02)
            │   2,826 ingredients
            ▼
RxNorm Prescribable Content — currently marketed filter
            │
            ▼
Non-oncological, currently marketed drug catalog
            │   1,626 ingredients
            │
     ┌──────┴──────┐
     ▼             ▼
  PubMed       ClinicalTrials.gov
     │             │
     └──────┬──────┘
            ▼
articles_raw.csv — 460 combined records, not deduplicated
            │
            ▼
classify_metadata_exclusions() — 32 excluded
            │
            ▼
para_rayyan.ris — 428 records ← output of this repository
            │
            ▼
   (outside this repo) Rayyan: dedup on import,
   blind screening by 2 reviewers, Cohen's kappa
```

---

## Scripts (`R/`)

1. **`01_catalogo_farmacos.R`** — non-oncological, currently marketed drug
   catalog (RxClass + RxNorm). 2,826 → 1,626 ingredients.
2. **`02_fetch_pubmed.R`** / **`02_fetch_clinicaltrials.R`** — search both
   sources with the same criteria: population AND drug AND treatment.
   243 + 217 = 460 records.
3. **`03_export_rayyan.R`** — structural exclusions (trials with no
   possible data, reviews) and export to `para_rayyan.ris`. 460 → 428.

`utils_http.R`, `utils_io.R`, `utils_logging.R` — shared utilities.

---

## Running it

```r
renv::restore()          # once, to install the pinned versions
targets::tar_make()      # run the pipeline
targets::tar_visnetwork()  # view the dependency graph
```

Each run's log is written to `logs/pipeline.log`.
