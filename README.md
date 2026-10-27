# Pipeline de revisión de alcance — Reposicionamiento farmacológico y quimiorradiación en cáncer cervicouterino

Repositorio del pipeline de recuperación, cribado y filtrado bibliográfico
para una revisión de alcance (PRISMA-ScR) sobre fármacos **no oncológicos**
reposicionados como sensibilizadores de la quimiorradiación en cáncer
cervicouterino.

Cada etapa se ejecuta y se revisa antes de pasar a la siguiente — no se
avanza a la etapa N+1 sin aprobación explícita.

Este repositorio cubre, por ahora, **solo la obtención de datos**: desde el
catálogo de fármacos hasta el archivo exportado a Rayyan. Todo lo posterior
(texto completo, extracción de datos, síntesis) todavía no se implementa.

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
            │   rxnorm_is_prescribable()
            ▼
Catálogo de fármacos no oncológicos y vigentes
            │   1,626 ingredientes
            │
     ┌──────┴──────┐
     ▼             ▼
  PubMed       ClinicalTrials.gov
(E-utilities/    (API v2)
  rentrez)
     │             │
     └──────┬──────┘
            ▼
articles_raw.csv — 460 registros combinados, sin deduplicar
            │
            ▼
classify_metadata_exclusions()
  — 32 excluidos: ensayos sin datos posibles, revisiones (secundarias)
            │
            ▼
para_rayyan.ris — 428 registros ← salida de este repositorio
            │
            ▼
   (fuera de este repo) Rayyan: deduplicación al importar,
   cribado ciego por 2 revisores, kappa de Cohen
```

---

## Principios de diseño

- **Fuentes:** PubMed y ClinicalTrials.gov únicamente. Sin Scopus ni Web of
  Science (sin acceso institucional). Sin Europe PMC (ver `DECISIONS.md`:
  añadía preprints con título reescrito y llamadas extra por artículo sin
  aportar cobertura que PubMed no tuviera ya).
- **Una sola cadena de búsqueda, igual en las dos fuentes: enfermedad AND
  nombre de fármaco AND tratamiento estándar.** Reorganizada el 2026-09-29,
  decisión explícita del usuario. El nombre de fármaco viene del catálogo
  (en lotes, porque no cabe en una sola consulta). Antes de esto hubo una
  rama adicional de "sensibilización" (vocabulario de mecanismo tipo
  synergy/resistance/drug repurposing, sin nombrar fármaco) que se probó,
  se validó, y finalmente se retiró para quedar con una sola lógica de
  búsqueda — ver `DECISIONS.md` para el historial completo de ambos
  cambios y sus números.
- **Bloque de tratamiento angostado a solo `cisplatin[tiab] OR
  carboplatin[tiab]`** (2026-10-13, decisión explícita del usuario para
  reducir el universo de artículos). Antes incluía también
  radiotherapy/"radiation therapy"/chemoradiation/chemoradiotherapy/
  brachytherapy. Validado empíricamente antes de aplicarse: la cadena
  angosta da 256 PMIDs, subconjunto exacto de los 566 de la cadena amplia
  (0 ganados, 310 perdidos) — riesgo declarado en `DECISIONS.md`: excluye
  artículos que mencionan el tratamiento como "chemoradiation" sin nombrar
  el citostático en el resumen.
- **El catálogo de fármacos se genera automáticamente en dos pasos
  separados: no oncológico por ATC, después aprobado y vigente.**
  (1) Desde RxClass: todas las clases ATC de nivel 2 excepto L01/L02
  (antineoplásicos), sin curación manual — un ingrediente entra si tiene
  CUALQUIER clase no oncológica, sin importar si también tiene una
  oncológica (para no excluir por error un fármaco ya reposicionado hacia
  oncología que conserve su indicación no oncológica original). (2) Sobre
  esa lista, un filtro de vigencia: se conserva solo si tiene al menos un
  producto formulado (SCD/SBD) dentro del **RxNorm Current Prescribable
  Content** (`rxnorm_is_prescribable()`, API `Prescribe` de RxNorm) — el
  subconjunto que la propia NLM depura para reflejar solo lo realmente
  prescribible hoy, excluyendo conceptos históricos o retirados.
  (2026-10-22: se evaluaron tres métodos en el mismo día — un proxy simple
  de RxNorm sin revisar vigencia, 74% de acuerdo con una consulta directa
  al directorio NDC de la FDA; un cruce directo por RXCUI contra esa misma
  base de la FDA, que corrigió ese problema pero introdujo puntos ciegos
  en biológicos y suplementos OTC; y este, RxNorm Prescribable Content,
  91% de acuerdo con la consulta directa a la FDA y la opción más simple
  de las tres — una sola llamada por ingrediente, todo dentro de RxNorm,
  sin necesitar la FDA como fuente aparte. Ver `DECISIONS.md` para las tres
  validaciones completas). El catálogo se usa como insumo directo de la
  búsqueda (el nombre de fármaco es parte obligatoria de la cadena, no un
  filtro posterior) — ver `DECISIONS.md` para la validación de cada paso.
- **Ningún filtro de texto después de la búsqueda.** Decisión explícita
  del usuario: como el nombre de fármaco ya es obligatorio en la cadena de
  búsqueda, no se vuelve a exigir su presencia en título/resumen antes de
  Rayyan — hacerlo sería redundante para PubMed e incorrectamente estricto
  para ClinicalTrials.gov (su buscador confirma el fármaco en campos que
  no siempre están en el resumen descargado). La función que hacía este
  cruce (`match_drugs_to_articles()`) sigue escrita para reusarse en la
  etapa 5, no para excluir antes de Rayyan. Ver `DECISIONS.md`.
- **Sin deduplicación propia en R — se deja por completo a Rayyan.**
  (2026-10-15, decisión explícita del usuario, se retira `R/02_deduplicate.R`
  por completo). Antes había una deduplicación en R por DOI, PMID,
  título+año exacto, y mención de NCT cruzada entre fuentes. Se retiró
  porque Rayyan ya deduplica al importar (DOI/título/autores/año) con un
  algoritmo publicado y mantenido — reimplementar esa misma lógica en R era
  trabajo duplicado, no aportaba rigor metodológico adicional. El conteo de
  "duplicados eliminados" del diagrama PRISMA ahora se llena con lo que
  reporte Rayyan después del import, no antes en R. Ver `DECISIONS.md`.
- **Scripts cortos, una función por tarea, estilo tidyverse.** `{targets}`
  orquesta, `{renv}` fija versiones.

---

## Estructura del repositorio

```
DR_CRT_CaCu/
├── README.md
├── DECISIONS.md              # bitácora de decisiones metodológicas (= métodos del manuscrito)
├── config.yml                # cadena de búsqueda, rutas, parámetros
├── _targets.R                # grafo del pipeline
├── R/
│   ├── utils_logging.R
│   ├── utils_http.R
│   ├── utils_io.R
│   ├── 01_fetch_pubmed.R
│   ├── 01_fetch_clinicaltrials.R
│   ├── 03_export_screening.R  # exclusiones estructurales + export a Rayyan (RIS)
│   └── 05_catalogo_farmacos.R # catálogo RxNorm + emparejamiento (título+resumen)
├── data/
│   ├── 01_busqueda/
│   │   ├── raw/               # respuestas crudas de API, sin modificar, con timestamp
│   │   │   ├── pubmed/
│   │   │   └── clinicaltrials/
│   │   ├── search_log.csv     # cadena efectiva y n de resultados por fuente
│   │   ├── pubmed_chunk_log.csv  # n de hits por lote de fármaco (PubMed)
│   │   ├── ctgov_chunk_log.csv   # n de hits por lote de fármaco (ClinicalTrials.gov)
│   │   └── articles_raw.csv   # artículos combinados, SIN deduplicar (eso lo hace Rayyan)
│   ├── 05_catalogo_farmacos/
│   │   └── drug_catalog.csv          # 1,626 ingredientes no oncológicos y vigentes
│   └── 03_cribado/             # export a Rayyan: todo lo combinado menos exclusiones estructurales
├── outputs/
│   ├── figures/
│   ├── tables/
│   └── prisma/
├── logs/
└── tests/testthat/            # vacío: los únicos tests eran de la deduplicación retirada
```

---

## Etapas

**Etapa 1 — Búsqueda.** `fetch_pubmed()` y `fetch_clinicaltrials()`, cada una
con la misma lógica: población AND tratamiento estándar AND nombre de
fármaco (en lotes del catálogo, al final de la cadena). Cadenas en
`config.yml: search_string` (`pubmed_population`, `pubmed_treatment`,
`ctgov_population`, `ctgov_treatment`) y **un solo `chunk_size` (80) para
las dos fuentes** en `config.yml: drug_branch` — homogenización explícita
para que la sección de métodos describa un solo procedimiento de lotes
(antes PubMed usaba 120 y ClinicalTrials.gov 100). El tamaño es el punto de
partida, no una garantía: si el motor de búsqueda de cualquiera de las dos
fuentes rechaza un lote (ClinicalTrials.gov con HTTP 400, PubMed con HTTP
414 por URL demasiado larga), se reintenta partido a la mitad,
recursivamente, hasta que cada sublote funcione (`ctgov_query_batch()` y
`pubmed_esearch_batch()`) — un intento de quitar esta lógica por completo
no resistió la corrida real con las cadenas completas de producción, ver
`DECISIONS.md` para el relato completo de por qué. Archiva cada respuesta
cruda de API sin modificar (requisito PRISMA: fecha exacta de búsqueda). El
bloque de tratamiento es solo `cisplatin[tiab] OR carboplatin[tiab]`
(cisplatino y carboplatino son los únicos citostáticos que la guía clínica
vigente usa concurrentes con radiación — ver auditoría 2026-09-29 en
`DECISIONS.md` — y desde el 2026-10-13 se quitaron además los términos de
radioterapia/quimiorradiación del bloque, para angostar el universo de
artículos — ver `DECISIONS.md`). La búsqueda también restringe a los
**últimos `retrieval$years_back` años** (ventana móvil calculada desde la
fecha de la corrida, no un año fijo — 20 años por defecto, justificado con
Ashburn & Thor 2004 sobre el origen del concepto de reposicionamiento
farmacológico; ver `DECISIONS.md` para las alternativas evaluadas). Esto
cambia el criterio original "sin límite de fecha" del protocolo, decisión
explícita del usuario. La lista de nombres de fármaco usada por la
búsqueda es exactamente `prepare_match_names(drug_catalog)`
(`R/05_catalogo_farmacos.R`) — la misma función que usa el emparejamiento
de texto de la etapa 5, para que las dos excluyan siempre los mismos
nombres de ruido genérico (`glucose`, `oxygen`, `hydrogen peroxide`) y
`bevacizumab` (ver bug corregido 2026-09-30 en `DECISIONS.md`).
`build_drug_catalog()` construye el catálogo en dos pasos separados (no
oncológico por ATC, después filtrado por vigencia con RxNorm Prescribable
Content — ver `DECISIONS.md`): 2,826 → **1,626** ingredientes. Resultado de
la corrida real (2026-10-22; ventana desde 2006, catálogo de 1,626, bloque
de tratamiento angosto del 2026-10-13): PubMed 243 + ClinicalTrials.gov
217 = **460** registros brutos (antes, con el catálogo del proxy anterior
de 2,008 ingredientes: 256 + 217 = 473; antes del angostamiento del bloque
de tratamiento: 564 + 294 = 858 — ver `DECISIONS.md`).

**Etapa 2 — Exclusiones estructurales y exportar a Rayyan.**
`export_screening_set()` exporta el corpus combinado a RIS — **sin
deduplicar en R** (2026-10-15, decisión explícita del usuario: Rayyan ya
deduplica al importar con un algoritmo publicado y mantenido, reimplementar
esa lógica en R era trabajo duplicado — ver `DECISIONS.md`; la antigua
etapa de deduplicación, `R/02_deduplicate.R`, se retiró por completo) y
sin ningún filtro por presencia de fármaco en el texto (ver "Ningún filtro
de texto después de la búsqueda" arriba), pero sí con exclusiones
**estructurales** basadas en metadatos ya asignados por
NLM/ClinicalTrials.gov (`classify_metadata_exclusions()`, sin cambios, ver
`DECISIONS.md`): ensayos `WITHDRAWN`/`NOT_YET_RECRUITING` (no pueden tener
datos), revisiones (secundarias, se separan para minería de referencias),
publicaciones retractadas, editoriales y protocolos de ensayo sin
resultados. **460 → 428 registros exportados a `para_rayyan.ris`** (32
excluidos: 21 ensayos sin datos posibles + 11 revisiones separadas para
minería de referencias + 0 retractados + 0 secundario/sin resultados).
Estos 428 son el archivo que se importa a Rayyan — **todavía no son "el
cribado"**: dentro de Rayyan, lo primero es revisar las coincidencias que
Rayyan detecte como posibles duplicados y confirmarlas, y *ese* número de
duplicados eliminados (y el total que efectivamente queda para cribar
título/resumen) es el que llena la siguiente caja del diagrama PRISMA,
pendiente hasta que el equipo lo haga. Después sigue el cribado ciego por
dos revisores y el kappa de Cohen.

`para_rayyan.ris` es, por ahora, la salida final de este repositorio. Las
etapas posteriores (texto completo, extracción de datos, síntesis) se
documentarán aquí cuando se implementen.

---

## Cómo correr

```r
renv::restore()          # una vez, para instalar las versiones fijadas
targets::tar_make()      # corre las etapas ya aprobadas
targets::tar_visnetwork()  # ver el grafo
```

El log de cada corrida queda en `logs/pipeline.log`.
