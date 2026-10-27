# Decisiones metodológicas

Este archivo es la fuente de verdad para la sección de métodos del manuscrito.
Cada decisión lleva fecha, motivo y consecuencia sobre los conteos PRISMA.

**2026-09-30 — Reorganización mayor: filtro de aprobación FDA en el
catálogo, se retira el filtro de texto post-búsqueda, deduplicación por
mención de NCT.** Tres cambios explícitos del usuario en una sola pasada.

1. **Filtro de aprobación FDA, separado del filtro ATC (no combinado).**
   El catálogo automático (ATC no oncológico) puede incluir compuestos
   clasificados por la OMS pero sin ningún producto aprobado en EE. UU.
   Se agregó `rxcui_has_marketed_form()` (`R/05_catalogo_farmacos.R`): un
   ingrediente (RXCUI tipo IN) se conserva solo si tiene al menos un
   descendiente SCD/SBD (droga clínica o de marca formulada) en RxNorm —
   proxy de "tiene producto comercializado en EE. UU.", sin cruzar nombres
   de texto contra openFDA (eso se probó antes en la sesión con recorte de
   sal y se abandonó por complejo). Validado con muestra real antes de
   aplicarlo (n=15): 4/15 sin SCD/SBD resultaron ser fármacos aprobados
   solo fuera de EE. UU. (dipropylacetamide, glycyrrhetinic acid,
   benzoxonium chloride, idrocilamide) — exactamente el ruido que debía
   quitar. **Orden explícitamente separado, no un solo criterio conjunto**:
   primero se enumera todo lo no oncológico por ATC (regla ya existente:
   se incluye si tiene CUALQUIER clase no oncológica, sin importar si
   también tiene una oncológica), y DESPUÉS, como paso aparte, se filtra
   por aprobación — así un fármaco ya reposicionado hacia oncología que
   conserve su indicación no oncológica original no se excluye por error.
   Resultado: catálogo baja de 2,824 a **2,008** ingredientes (816
   removidos, 29%, consistente con la muestra de validación).
2. **Se retira el filtro de texto post-búsqueda (`match_drugs_to_articles()`)
   de la ruta hacia Rayyan.** Decisión explícita del usuario, en contra de
   la recomendación inicial de mantenerlo: el nombre de fármaco ya es
   obligatorio en la búsqueda (etapa 1) — filtrar otra vez por su
   presencia en el texto es redundante para PubMed y, para
   ClinicalTrials.gov, incorrectamente estricto (su buscador confirma el
   fármaco en campos del registro que no siempre están en el resumen
   descargado — ver el hallazgo del 2026-09-29 sobre esto). `_targets.R`
   ya no tiene los targets `articles_classified`/`stage5_outputs`;
   `export_screening_set()` exporta directamente `articles_deduped`
   completo. `match_drugs_to_articles()` queda escrita en
   `R/05_catalogo_farmacos.R`, sin llamarse en el grafo actual — se
   reserva para la etapa 5 (emparejamiento fino para Tabla 1, sobre texto
   completo de los ya incluidos tras Rayyan), donde el objetivo es extraer
   CON QUÉ evidencia se menciona cada fármaco, no decidir exclusión.
3. **Deduplicación por mención de NCT, criterio adicional de identificador
   exacto (no difuso).** El usuario notó, correctamente, que 1 solo
   duplicado entre 977 registros era sospechoso dado que los ensayos
   clínicos suelen tener su artículo de resultados en PubMed. Se confirmó
   con datos reales: 11 resúmenes de PubMed mencionaban un número NCT, 9
   de esos NCT estaban en el propio set de ClinicalTrials.gov de esta
   corrida — duplicados genuinos invisibles para DOI/PMID/título+año
   porque PubMed y ClinicalTrials.gov usan sistemas de identificadores
   disjuntos por diseño (ya documentado en la etapa 2, pero ahora con una
   forma real de resolverlo). Se agregó `merge_by_nct_mention()`
   (`R/02_deduplicate.R`): fusiona un registro de PubMed con el de
   ClinicalTrials.gov cuyo NCT mencione explícitamente en el resumen. Es
   un identificador exacto (mismo rigor que DOI/PMID), no similitud
   difusa. **Bug encontrado y corregido antes de correr en producción**:
   la búsqueda del NCT en un lookup usaba `[[` sobre un vector con nombres
   (no una lista), lo que lanza error en vez de `NULL` cuando el NCT
   mencionado no está en el set — se cambió a `[` con chequeo de `NA`.
   Cubierto con 2 pruebas nuevas (`tests/testthat/test-deduplicate.R`):
   fusiona cuando el NCT sí está en el set, no fusiona nada cuando el NCT
   mencionado no está.
- **Resultado de la corrida con los tres cambios:** PubMed 561 (baja de
  662 porque el catálogo tiene menos fármacos) + ClinicalTrials.gov 294
  (baja de 315) = 855 brutos → **845 únicos** (10 duplicados fusionados,
  8 de ellos cruzados PubMed↔ClinicalTrials.gov vía NCT, 1 PubMed↔PubMed
  estándar, más un cluster de 3 registros). **845 van a Rayyan — el 100%
  del corpus deduplicado, sin ningún filtro de texto posterior.**

**2026-10-06 — Exclusiones estructurales antes de Rayyan: metadatos, no
texto de título/resumen.** El usuario preguntó si, dado que "sensaban
similar" las diferenciaciones frente a Capistrano et al. 2022 (ver abajo),
se podía filtrar el corpus de otra forma antes de Rayyan — pidió
específicamente criterios que NO dependieran del contenido de
título/resumen. Se revisaron los metadatos ya descargados (no se hizo
ninguna búsqueda nueva):
- **ClinicalTrials.gov, estado del ensayo (`overallStatus`):** `WITHDRAWN`
  (11, retirado antes de inscribir a un solo paciente) y
  `NOT_YET_RECRUITING` (18, registrado pero sin reclutar a nadie todavía)
  — ninguno de los dos puede tener datos que aportar; no es una exclusión
  de "probablemente irrelevante", es que el estudio no ha ocurrido. Cero
  riesgo de perder evidencia real.
- **PubMed, `publication_type`:** `Review`/`Systematic Review` (45) —
  evidencia secundaria, no primaria (el protocolo pide diseños primarios).
  Se separan para minería manual de referencias (ya planeada para
  Capistrano/Candelaria/Low/Julian; aquí se extiende a TODAS las
  revisiones que la propia búsqueda encontró) — no se descartan sin más,
  se guardan en `data/03_cribado/revisiones_para_mineria_referencias.rds`.
- **PubMed, hallazgos adicionales menores tras revisar más a fondo:** 1
  `Retracted Publication` (retirado formalmente por la revista, no cuenta
  como evidencia bajo ningún criterio) y 4 más entre `Editorial`,
  `Clinical Trial Protocol` (publica el diseño de un ensayo sin resultados
  todavía — mismo argumento que `NOT_YET_RECRUITING`).
- **Implementación:** `classify_metadata_exclusions()`
  (`R/03_export_screening.R`), llamada dentro de `export_screening_set()`.
  Guarda la clasificación completa (incluidos los excluidos, con su razón)
  en `data/03_cribado/clasificacion_pre_rayyan.rds` — nada se descarta sin
  dejar rastro.
- **Resultado:** 848 → **769 a Rayyan** (29 + 45 + 1 + 4 = 79 excluidos
  por razones estructurales, 9.3%). Quedó pendiente de decisión del equipo
  una cuarta categoría explorada pero NO aplicada: 81 `Case Reports` en
  PubMed — el protocolo no dice explícitamente si cuentan como "diseño
  observacional" o se excluyen, es una zona gris real, no una decisión
  técnica.
- **Nota de corrección:** en la conversación se mencionó primero "693"
  como resultado esperado — ese número sumaba las tres categorías
  originales (79+45+**81 case reports incluidos**). Al aplicar solo las
  dos sin zona gris (más los 5 hallazgos menores de la revisión posterior),
  el número real es 769, no 693. Los 81 reportes de caso siguen en el
  corpus hasta que el equipo decida.

**2026-10-04 — Homogenización del tamaño de lote entre fuentes: simplificación
real, pero el intento inicial de quitar TODA la lógica de reintento no
aguantó la corrida de producción — quedó documentado el proceso completo
porque es justo el tipo de decisión que un revisor de PRISMA puede
cuestionar.** Decisión explícita del usuario: usar el mismo `chunk_size` en
PubMed y ClinicalTrials.gov (antes 120 y 100 respectivamente, cada uno con
su propio mecanismo), para que la sección de métodos describa un solo
procedimiento de lotes en vez de dos.

1. **Primer intento (fallido): quitar `POST` y la bisección, confiar en un
   tamaño de lote validado como "seguro".** Se probó contra el catálogo
   completo con cadenas de población/tratamiento *simplificadas* (solo 2-3
   términos cada una, no las 7 reales): 80 nombres por lote dio 26/26
   lotes limpios en ClinicalTrials.gov y sin error hasta ~95-99 nombres en
   PubMed. Con esa evidencia se quitaron `eutils_esearch_post()`/
   `eutils_efetch_post()` (ya no hacía falta `POST`, bastaba `rentrez`
   normal) y la biseccion recursiva de `ctgov_query_batch()`.
2. **Falló en la corrida real de producción**, con las cadenas de
   población/tratamiento COMPLETAS (7 términos cada una): ClinicalTrials.gov
   rechazó un lote con HTTP 400; PubMed rechazó otro con HTTP 414. La
   validación había sido optimista en dos sentidos distintos:
   - **ClinicalTrials.gov**: se probó primero la hipótesis de que el 400
     fuera por mandar muchas peticiones seguidas sin pausa (se agregó
     pausa de 1s entre lotes y reintento con retroceso de hasta 15s) —
     **no era eso**: el mismo lote rechazado, probado de nuevo aislado y
     con cadenas completas, volvió a fallar de forma reproducible. Con las
     cadenas completas (94 términos totales: 7 población + 7 tratamiento +
     80 fármacos), ese lote específico sí excede algún límite del parser
     Essie que no se pudo caracterizar con precisión (no es solo conteo de
     términos: lotes de hasta 123 términos totales habían funcionado antes
     en otra combinación).
   - **PubMed**: la muestra de validación usó `all_names[1:n]`, es decir,
     los primeros nombres en orden alfabético — que tienden a ser más
     cortos. Un lote real tomado de otra parte del catálogo puede incluir
     varios nombres largos (combinaciones de dos fármacos, ej.
     `"dutasteride / tamsulosin"`), empujando la URL de ESE lote particular
     por encima del límite aunque el tamaño de lote en sí sea razonable.
3. **Solución final: biseccion automática en las DOS fuentes, no un tamaño
   "seguro" fijo.** Se restauró la bisección recursiva en
   `ctgov_query_batch()` (ClinicalTrials.gov) y se agregó la misma lógica,
   nueva, en `pubmed_esearch_batch()` (PubMed, `R/01_fetch_pubmed.R`): si
   un lote es rechazado (400 o 414), se reintenta partido a la mitad,
   recursivamente, hasta que cada sublote funcione. No depende de entender
   la causa exacta del rechazo — se recupera igual sin importar cuál sea.
   `chunk_size: 80` queda como el tamaño de partida (más alto que el
   mínimo necesario en la mayoría de los lotes, bajo lo suficiente para
   que la bisección rara vez tenga que actuar), igual en las dos fuentes.
   Verificado contra el catálogo completo real: en ClinicalTrials.gov 2 de
   26 lotes necesitaron bisección (igual que la tasa de fallo ya conocida
   de la version anterior con lotes de 100); en PubMed, ninguno en esta
   corrida.
- **Resultado de la corrida con el código corregido:** PubMed 564 + ClinicalTrials.gov
  294 = 858 brutos → 848 únicos (10 duplicados, misma composición que antes:
  8 cruces PubMed↔ClinicalTrials.gov vía NCT, 1 PubMed↔PubMed, un cluster
  de 3). **848 van a Rayyan.** La pequeña diferencia en PubMed (564 vs. 561
  de la corrida anterior) es esperable: el catálogo se reconstruye en cada
  corrida consultando RxNorm en vivo, y esa fuente externa puede cambiar
  ligeramente de un día a otro — no es un error, es una característica ya
  conocida de depender de una API externa no versionada.

**2026-09-30 — Bug real encontrado y corregido: la búsqueda usaba nombres de
"ruido" que ya estaban excluidos del filtro local, pero nunca de la
búsqueda misma.** El usuario cuestionó por qué, si el nombre de fármaco ya
es obligatorio en la cadena de búsqueda, seguía habiendo tantos registros
clasificados como `excluible_sin_farmaco` (484 de 1,127 en PubMed, 43%).
Se investigó con una muestra real: los títulos/resúmenes no mencionaban
ningún fármaco reconocible ("Significance of hypoxia...", "Hedgehog
pathway signaling...", "Gynecologic cancer in pregnancy..."). Se confirmó
la causa exacta: `CATALOG_GENERIC_NOISE_EXCLUDE` (`oxygen`, `glucose`,
`hydrogen peroxide`) y `CATALOG_MANUAL_EXCLUDE` (`bevacizumab`) —
definidos en `R/05_catalogo_farmacos.R` para excluir ruido bioquímico
genérico del **filtro local** (`match_drugs_to_articles()`, vía
`prepare_match_names()`) — nunca se aplicaban a la **búsqueda**
(`fetch_pubmed()`/`fetch_clinicaltrials()`), que construía su lista de
nombres directamente desde `drug_catalog$preferred_name` sin pasar por
`prepare_match_names()`. Resultado: la búsqueda traía artículos solo
porque mencionaban "glucose transporter" o "oxygen" en un sentido
bioquímico genérico sin relación con ningún fármaco, y el filtro local
los rechazaba correctamente — **461 de los 484 `excluible_sin_farmaco` de
PubMed (95%) eran exactamente este ruido de búsqueda**, no candidatos
genuinos evaluados y descartados.
- **Corrección:** `fetch_pubmed()` y `fetch_clinicaltrials()`
  (`R/01_fetch_pubmed.R`, `R/01_fetch_clinicaltrials.R`) ahora usan
  `prepare_match_names(drug_catalog, min_chars)` — la misma función que ya
  usa el filtro local — en vez de leer `drug_catalog$preferred_name`
  directo. Una sola fuente de verdad para "qué cuenta como nombre de
  fármaco buscable", sin posibilidad de que búsqueda y filtro posterior
  vuelvan a divergir en el futuro.
- **Resultado de la corrida corregida:** PubMed 662 (antes 1,127) +
  ClinicalTrials.gov 315 (antes 340) = 977 brutos → 976 únicos (1
  duplicado) → 683 `match_farmaco` + 0 `no_verificable_sin_resumen` =
  **683 a Rayyan** (293 `excluible_sin_farmaco`). El número exportado a
  Rayyan prácticamente no cambia (683 vs. 685 antes del fix) — la
  corrección no pierde ningún candidato real, solo deja de traer y
  después descartar 754 registros que nunca debieron entrar al pool
  bruto. `excluible_sin_farmaco` en PubMed baja de 484 a 21 (de esos 21,
  solo 4 aún mencionan alguno de los términos de ruido, coincidencia con
  otra causa de inclusión). El de ClinicalTrials.gov queda en 272 (antes
  297) — ese residual sí es el fenómeno ya documentado de `query.term`
  buscando en campos más allá del resumen, no este bug.

**2026-09-29 — Restricción temporal: últimos 20 años (ventana móvil), cambia
el criterio "sin límite de fecha" del protocolo original.** Decisión
explícita del usuario. Se evaluaron varias anclas históricas posibles antes
de elegir esta:
- **1999-2000** (NCI Clinical Announcement + cinco ensayos aleatorizados —
  Keys et al., Morris et al., Rose et al. *N Engl J Med* 1999; Whitney et
  al. *J Clin Oncol* 1999; Peters et al. *J Clin Oncol* 2000 — que
  establecieron la quimiorradiación concurrente con cisplatino como
  estándar): justifica el *tratamiento* que se sensibiliza, no el concepto
  de reposicionamiento en sí.
- **FIGO 2018** (revisión que permitió estadificación por imagen/patología,
  no solo clínica): descartada — dejaría solo 387 de 1,088 (704 fuera), y
  la mayoría de la literatura mecanística/preclínica no depende de la
  edición de FIGO usada.
- **Duración típica de un reposicionamiento** (~3-12 años según Pushpakom
  et al. 2019, *Nat Rev Drug Discov*, "Drug repurposing: progress,
  challenges and recommendations"): descartada — describe cuánto tarda
  reposicionar UN fármaco ya identificado, no desde cuándo debería existir
  la literatura buscada; no se traduce en un año de corte razonable.
- **Elegida: Ashburn TT, Thor KB. "Drug repositioning: identifying and
  developing new uses for existing drugs." Nat Rev Drug Discov.
  2004;3(8):673-83** — el artículo fundacional más citado que formalizó
  "drug repositioning/repurposing" como estrategia de investigación con
  ese nombre. Justifica el concepto central de la revisión (reposicionamiento),
  no solo el contexto de tratamiento.
- **Implementación: ventana móvil de N años (`retrieval$years_back: 20`),
  no un año fijo.** En vez de fijar "2004" como constante, se calcula
  `año_actual - 20` una sola vez en el target `cfg` de `_targets.R` (mismo
  valor para las dos fuentes, documentado en el log de cada corrida). Esto
  prioriza reproducibilidad y facilidad de mantenimiento sobre pegar el
  corte exacto a la cita de 2004; el usuario aceptó explícitamente esta
  diferencia. Con la corrida de hoy (2026-09-29), la ventana calculada es
  **desde 2006**.
- **Sintaxis de filtro por fuente, ambas probadas empíricamente antes de
  usarse:** PubMed usa `AAAA:3000[dp]` (rango de fecha de publicación).
  ClinicalTrials.gov usa sintaxis Essie `AREA[StartDate]RANGE[AAAA-01-01,MAX]`
  dentro de `query.term` — se confirmó que sí filtra de verdad (fechas de
  inicio de estudio devueltas antes del filtro incluían 1996-2005; después
  del filtro, todas ≥2006).
- **Resultado de la corrida con la ventana de 20 años (desde 2006):**
  PubMed 1,127 + ClinicalTrials.gov 340 = 1,467 brutos → 1,466 únicos (1
  duplicado) → 683 `match_farmaco` + 2 `no_verificable_sin_resumen` =
  **685 a Rayyan** (781 `excluible_sin_farmaco`). Baja de 1,088 a 685 —
  una reducción del 37%, mayor a la estimada (725) porque el efecto no es
  lineal: al restringir la fecha en la búsqueda misma (no solo como filtro
  posterior), también cambia qué lotes de fármacos encuentran cada
  registro.

**2026-09-29 — Corrección sobre la corrección: bloque de tratamiento
reducido de vuelta a solo cisplatino+carboplatino.** La auditoría de alto
impacto (entrada de abajo) agregó 6 citostáticos al bloque de tratamiento
(carboplatin, paclitaxel, gemcitabine, topotecan, mitomycin, fluorouracil)
razonando que eran "citostáticos estándar de cáncer cervicouterino". El
usuario pidió verificar esto contra la guía clínica vigente antes de
aceptarlo, y la verificación mostró que el razonamiento original estaba
incompleto: según NCCN/ESGO-ESTRO-ESP, **cisplatino y carboplatino son los
únicos citostáticos que se dan CONCURRENTES con radiación** (carboplatino
como sustituto reconocido cuando cisplatino está contraindicado — mismo rol
radiosensibilizador). Paclitaxel, gemcitabina, topotecán, mitomicina y
fluorouracilo se usan en cáncer cervicouterino, pero SOLO en contextos sin
radiación concurrente: enfermedad recurrente/metastásica (manejo sistémico
paliativo) o como inducción neoadyuvante ANTES de la quimiorradiación
estándar (protocolo INTERLACE 2024: carboplatino+paclitaxel x6 semanas,
después sí la quimiorradiación con cisplatino) — nunca simultáneos con la
radiación. Esto además coincide con el criterio de inclusión literal del
protocolo original (`Propuesta_art_revision.docx`, §6): "Combinación con
cisplatino, con radiación ionizante o con ambos" — no dice "con cualquier
citostático de cáncer cervicouterino". Se retiraron los 5 términos que no
correspondían a uso concurrente; se conserva carboplatino. Bloque final:
`cisplatin, carboplatin, radiotherapy, "radiation therapy", chemoradiation,
chemoradiotherapy, brachytherapy` (7 términos). Resultado de la corrida con
este bloque corregido: PubMed 1,590 + ClinicalTrials.gov 403 = 1,993 brutos
→ 1,991 únicos (2 duplicados) → 1,026 `match_farmaco` + 62
`no_verificable_sin_resumen` = **1,088 a Rayyan** (903
`excluible_sin_farmaco`).
- **Orden de los bloques en la cadena: población AND tratamiento AND
  fármaco (fármaco al final), decisión explícita del usuario.** No cambia
  el resultado (AND es conmutativo — el orden es booleanamente
  irrelevante), pero se actualizó el orden en que `fetch_pubmed()` y
  `ctgov_query_batch()` construyen el string, para que la cadena
  documentada en métodos coincida exactamente con la que se ejecuta.

**2026-09-29 — Auditoría de alto impacto: bloque de tratamiento ampliado,
catálogo/idioma revisados.** A petición explícita del usuario ("audita y
juzga si el flujo no es digno de una publicación de alto impacto"), se
revisaron tres puntos:
1. **`[tiab]` no reduce recall de texto, solo acota el campo.** Restringe
   la coincidencia a título+resumen (evita que la búsqueda encuentre el
   término en un campo — MeSH, sustancias químicas indexadas, afiliaciones
   — que después no se puede verificar, el mismo problema ya documentado
   para ClinicalTrials.gov más abajo). No afecta qué tan literal es el
   match de la frase entre comillas. **Confirmado empíricamente:** se
   corrió la misma consulta (población AND tratamiento AND "metformin")
   con y sin `[tiab]`. Con `[tiab]`: 11 resultados. Sin `[tiab]`: 12 — el
   registro extra es PMID 28498475 ("Targeting hexokinase 2 inhibition
   promotes radiosensitization in HPV16 E7-induced cervical cancer..."),
   cuyo resumen nunca dice "radiotherapy" ni "radiation therapy" (dice
   "irradiation therapy"/"sensitivity to irradiation") — sin `[tiab]`,
   PubMed lo encontró probablemente por un término MeSH indexado
   (mapeo automático de términos sobre la palabra suelta `radiotherapy`),
   no por coincidencia literal de texto. Es exactamente el mismo mecanismo
   que infla el conteo de ClinicalTrials.gov: la búsqueda "encuentra" algo
   que el filtro posterior (que solo revisa texto literal) no podría
   confirmar.
2. **Dependencia del catálogo RxNorm/ATC para la búsqueda misma —
   evaluada, no es un defecto.** Con el fármaco como requisito obligatorio
   de búsqueda (no solo de clasificación posterior), cualquier fármaco no
   oncológico ausente del catálogo es ahora invisible desde el inicio, no
   solo mal clasificado. Se probaron 7 candidatos frecuentes en esta
   literatura — curcumina, resveratrol, quercetina, genisteína,
   sulforafano, EGCG, berberina — ninguno está en el catálogo, y existen
   al menos 41 artículos reales en PubMed (población + estos 7 nombres +
   bloque de tratamiento) que el pipeline actual nunca recupera. Sin
   embargo, el criterio de inclusión del protocolo original
   (`Propuesta_art_revision.docx`, §6) exige explícitamente "fármaco con
   indicación aprobada previa" — ninguno de los 7 es un fármaco aprobado
   (son suplementos/nutracéuticos), así que quedarían excluidos de todas
   formas por el propio criterio de la revisión. **Conclusión: no es un
   error, el catálogo está operacionalizando correctamente el criterio de
   "aprobado previamente".** Limitación real que sí queda declarada:
   RxNorm es una base de nomenclatura de EE.UU.; un fármaco con aprobación
   solo en otro país podría faltar del catálogo aunque cumpla el criterio
   de inclusión en sentido estricto.
3. **Filtro de idioma: nunca fue un parámetro real de ninguna API,
   corregido el comentario que lo daba a entender.** Ni PubMed ni
   ClinicalTrials.gov reciben un parámetro de idioma en esta cadena — la
   restricción a inglés es un efecto secundario de que los términos de
   búsqueda están escritos en inglés (un resumen exclusivamente en español
   no calza con ninguna frase de la cadena), no un filtro explícito. El
   campo `retrieval$language_filter` en `config.yml` no se leía en ningún
   lado del código — se eliminó por ser documentación muerta que podía
   inducir a error a un revisor que leyera `config.yml` y asumiera que
   estaba aplicado.
- **Bloque de tratamiento ampliado (hallazgo con corrección aplicada).**
  El bloque original solo tenía 6 términos (`cisplatin`, `radiotherapy`,
  `"radiation therapy"`, `chemoradiation`, `chemoradiotherapy`,
  `brachytherapy`) — le faltaban otros citostáticos de uso estándar en
  cáncer cervicouterino. Caso real confirmado perdido: Tang ZY et al. 2018
  (10.26355/eurrev_201812_16501, PMID 30556847), "Metformin enhances
  inhibitive effects of **carboplatin** on HeLa cell proliferation" —
  ausente del pool bruto porque ni carboplatino ni ningún otro término del
  bloque aparecía en su resumen. Se agregaron `carboplatin`, `paclitaxel`,
  `gemcitabine`, `topotecan`, `mitomycin`, `fluorouracil` (citostáticos
  estándar en protocolos de cáncer cervicouterino además de cisplatino,
  ver referencias de `Propuesta_art_revision.docx`). Impacto medido antes
  de aplicar: población AND tratamiento pasa de 17,777 a 18,656 (+4.9%) —
  bajo riesgo de ruido porque el nombre de fármaco sigue siendo obligatorio
  en la misma consulta. Verificado tras la corrida real: el PMID 30556847
  ya aparece en `data/01_busqueda/articles_raw.rds`.
- **Resultado de la corrida con el bloque de tratamiento ampliado:**
  PubMed 1,774 + ClinicalTrials.gov 424 = 2,198 brutos → 2,194 únicos (4
  duplicados) → 1,175 `match_farmaco` + 67 `no_verificable_sin_resumen` =
  **1,242 a Rayyan** (952 `excluible_sin_farmaco`).
- **Pendientes para publicación de alto impacto, no resueltos en esta
  auditoría (requieren decisión o trabajo fuera del alcance de este
  pipeline):**
  - Registrar el protocolo en OSF (`project.registration` sigue
    "pendiente de DOI de registro") — idealmente antes de que el equipo
    empiece a cribar en Rayyan, no después.
  - Búsqueda manual en las referencias de Capistrano 2022, Candelaria
    2006, Low 2024 y Julian 2026, requerida por el protocolo original
    (§6) y nunca ejecutada — es trabajo manual barato (leer las
    referencias de 4 artículos), no automatizable con lo que ya existe.
  - Limitación de idioma (declarada arriba): la revisión enmarca su
    aporte en equidad de acceso en países de ingreso bajo y medio, pero
    excluye literatura en español sin resumen en inglés — vale la pena
    que el equipo decida si esto merece una búsqueda complementaria en
    español antes de cerrar la etapa de búsqueda, no solo una limitación
    declarada al final.

**2026-09-29 — Reorganización final: una sola cadena, se retira la rama de
sensibilización.** Decisión explícita del usuario, tras revisar los
números de la corrida con dos ramas (2026-09-28, más abajo): en vez de
mantener dos ramas complementarias en PubMed (sensibilización +
por fármaco) con lógicas distintas, el pipeline queda con **una sola
lógica de búsqueda, igual en las dos fuentes**: población AND nombre de
fármaco (del catálogo, en lotes) AND tratamiento estándar. Se retira por
completo el bloque de vocabulario de mecanismo (`synergy`, `resistance`,
`drug repurposing`, etc.) — ya no se exige en ninguna búsqueda. Consecuencia
aceptada conscientemente: se pierde la capacidad de encontrar artículos que
discuten sensibilización/reposicionamiento en términos generales sin citar
un nombre de fármaco que calce exactamente con el catálogo (por ejemplo, si
el resumen usa una marca comercial o una grafía distinta a
`preferred_name`). A cambio, el diseño es más simple de defender en
métodos (una sola pregunta: ¿hay un fármaco no oncológico del catálogo,
usado con el tratamiento estándar? — no dos preguntas con lógicas
distintas) y evita el riesgo, ya detectado, de que el comparador local de
texto y la búsqueda indexada de PubMed no siempre estén de acuerdo sobre
qué cuenta como "mención de mecanismo".
- **`R/01_fetch_pubmed.R`** — se retira la función vieja `fetch_pubmed(cfg)`
  (rama de sensibilización); la función que hacía la rama por fármaco se
  renombra de `fetch_pubmed_drug_branch()` a `fetch_pubmed()`, ahora la
  única.
- **ClinicalTrials.gov recibe la misma reorganización**, no solo PubMed
  (decisión explícita del usuario, para no dejar las dos fuentes con
  lógicas distintas). Se agregó `fetch_clinicaltrials(cfg, drug_catalog)`
  con el mismo patrón de lotes.
- **Límite de lote distinto y más frágil en ClinicalTrials.gov.** Se probó
  primero cuántos nombres de fármaco caben en un lote: 123 funciona, 125
  falla con HTTP 400 "Search error" (motor de búsqueda Essie). Pero al
  correr los 29 lotes reales de 100 nombres, 2 de 29 fallaron igual con
  HTTP 400, aunque tienen el mismo tamaño que los otros 27 que sí
  funcionaron — y cada mitad (50) de un lote rechazado funciona sola. Es
  decir, el límite no es un número fijo de términos ni de caracteres, sino
  algo más opaco del lado del servidor (posible límite de complejidad
  interna del parser). En vez de perseguir el tamaño "seguro" exacto,
  `ctgov_query_batch()` (`R/01_fetch_clinicaltrials.R`) reintenta
  bisectando a la mitad cualquier lote que reciba HTTP 400, recursivamente,
  hasta que cada sublote funcione — robusto sin depender de encontrar el
  límite exacto.
- **Resultado de la corrida con la cadena única: PubMed 1,539, ClinicalTrials.gov
  388 → 1,927 brutos → 1,925 únicos (2 duplicados) → 999 `match_farmaco` +
  62 `no_verificable_sin_resumen` = 1,061 a Rayyan (864 `excluible_sin_farmaco`).**
  El total exportado a Rayyan (1,061) coincide, por coincidencia numérica,
  con el de la corrida anterior de dos ramas — pero la composición es
  distinta (999+62 aquí vs. 989+72 antes).
- **Hallazgo: ClinicalTrials.gov "identifica" muchos más registros de los
  que su propio resumen puede confirmar, mucho más que PubMed.** De los 388
  registros de ClinicalTrials.gov, solo 50 (12.9%) quedan como
  `match_farmaco`; de los 1,539 de PubMed, 949 (61.7%). Revisando una
  muestra de los 338 de ClinicalTrials.gov clasificados
  `excluible_sin_farmaco`, se confirmó la causa: `query.term` de la API v2
  de ClinicalTrials.gov busca por defecto en un conjunto amplio de campos
  del registro completo del ensayo (brazos/intervenciones, criterios de
  elegibilidad, etc.), no solo en título + resumen breve — a diferencia de
  PubMed, donde `[tiab]` restringe la coincidencia exactamente a los campos
  que después se descargan y verifican. Ejemplo encontrado: NCT00046969
  ("Epoetin Beta in Treating Anemia...") aparece porque el lote de búsqueda
  incluía `"methoxy polyethylene glycol-epoetin beta"` (nombre distinto en
  el catálogo, variante pegilada) y el motor de búsqueda de
  ClinicalTrials.gov (Essie) hizo una coincidencia laxa por palabras, no
  una frase exacta como hace PubMed. Otros ejemplos (NCT06426056,
  NCT05179239) mencionan en título/resumen solo fármacos oncológicos
  (nab-paclitaxel, SHR-1701, bevacizumab) — el fármaco no oncológico real
  que disparó la coincidencia está en otro campo del registro, no en lo que
  se descarga como `abstract`. **Esto no invalida los números finales**: el
  comparador local (`match_drugs_to_articles()`) solo confirma una
  coincidencia si el nombre aparece en título+resumen, igual que para
  PubMed, así que estos casos se excluyen correctamente aguas abajo. El
  efecto real es que el número "identificado" de ClinicalTrials.gov (388)
  no es comparable uno a uno con el de PubMed (1,539) en términos de tasa
  de acierto — vale la pena declararlo en limitaciones si se reporta el
  diagrama PRISMA desglosado por fuente.
- **`config.yml`:** se eliminan `search_string.pubmed` y
  `search_string.clinicaltrials` (las cadenas de 3 bloques con vocabulario
  de mecanismo) — quedan solo `pubmed_population`, `pubmed_treatment`,
  `ctgov_population`, `ctgov_treatment`, subcadenas exactas de las cadenas
  auditadas anteriormente. El texto completo de las cadenas retiradas
  queda preservado en el historial de git y en las entradas de abajo
  fechadas 2026-09-27.

**2026-09-28 — Corrección: se reinstala la "rama por fármaco" del protocolo
original, retirada por error durante el rediseño del 2026-09-27.** Al
releer `Propuesta_art_revision.docx` (§6, "Estrategia de búsqueda y
criterios") se confirmó que el protocolo original define **tres** ramas de
búsqueda, no una: (1) cadena base de reposicionamiento, para dimensionar el
campo; (2) rama de sensibilización (población + vocabulario de mecanismo +
tratamiento); (3) rama por fármaco ("Búsqueda nominal para cada candidato").
Durante el rediseño del 2026-09-27 se retiró la rama 3 y se documentó más
abajo (sección "Por qué el contexto de tratamiento y no el nombre del
fármaco") con el razonamiento de que no hacía falta porque el criterio de
tratamiento ya la volvía redundante — **ese razonamiento resultó
incorrecto**. Se probó primero como script temporal, exploratorio, fuera
del pipeline (población AND nombre de fármaco del catálogo, filtro de
tratamiento aplicado después sobre el texto ya descargado): de 1,501
artículos encontrados así, solo 365 coincidían con el universo de la rama
de sensibilización (1,833), y de esos 365, 136 eran artículos que la rama
de sensibilización sí había traído pero que el comparador local de
fármacos había clasificado como `excluible_sin_farmaco` — es decir, sí
mencionaban un fármaco del catálogo y el comparador local no lo había
detectado. Los otros 1,136 eran estudios que la rama de sensibilización
nunca encontró: combinan un fármaco del catálogo con el tratamiento
estándar, pero no usan ninguna palabra de mecanismo (`synergy`,
`resistance`, `drug repurposing`, etc.) en el resumen. Esto confirma
exactamente la razón por la que el protocolo original pedía una rama
nominal aparte. Se reinstaló como rama permanente de producción
(`fetch_pubmed_drug_branch()`, `R/01_fetch_pubmed.R`): población AND
(lote de hasta 120 nombres del catálogo, por límite de longitud de URL)
AND tratamiento, usando `POST` a `esearch.fcgi`/`efetch.fcgi` en vez de
`GET` (con 120+ términos en un solo query, `GET` devuelve HTTP 414). Los
bloques de población y tratamiento son subcadenas exactas de
`search_string.pubmed` (`search_string.pubmed_population` y
`search_string.pubmed_treatment` en `config.yml`), no una redacción nueva.
Resultado de la corrida completa: PubMed rama de sensibilización 1,833 +
rama por fármaco 1,538 + ClinicalTrials.gov 212 = 3,583 registros brutos;
tras deduplicar, 3,213 únicos (370 fusionados — el primer traslape real
entre fuentes de esta revisión, porque ahora dos búsquedas distintas
pueden apuntar al mismo artículo de PubMed); filtro de fármaco: 989
`match_farmaco`, 2,152 `excluible_sin_farmaco`, 72
`no_verificable_sin_resumen`; exportados a Rayyan: 1,061 (antes 282). El
salto es real, no un error: la rama nueva está diseñada para encontrar
precisamente lo que la anterior no podía ver por construcción.

**2026-09-27 — Rediseño.** Después de una primera implementación (búsqueda en
tres fuentes con tres cadenas por fármaco, deduplicación difusa propia), se
simplificó todo el pipeline. Motivo explícito: exceso de preprocesamiento
propio (normalización de sales, cruce RxNorm↔openFDA, deduplicación con
similitud de texto inventada) que ni la práctica estándar de revisiones
PRISMA hechas por no programadores usa, ni es fácil de defender en una
sección de métodos ("¿por qué ese umbral y no otro?"). La sección
**"Arquitectura vigente"** de abajo describe el diseño actual. La sección
**"Historial de diseño"** conserva el razonamiento de las decisiones
descartadas — no se borra, porque documenta por qué se evaluaron y
rechazaron alternativas (Europe PMC, ASySD/synthesisr, cadenas por fármaco,
Jaro-Winkler vs coseno), que es justo el tipo de trazabilidad que un
revisor de la revista puede pedir.

---

## Arquitectura vigente

### Etapa 1 — Búsqueda

- **Fuentes:** PubMed y ClinicalTrials.gov únicamente. Sin Scopus/Web of
  Science (sin acceso institucional). Sin Europe PMC (ver historial).
- **Una sola cadena, sin nombres de fármaco, agrupada en dos bloques
  lógicos (población AND (tratamiento OR reposicionamiento)):**
  ```
  ("cervical cancer" OR "Uterine Cervical Neoplasms"[MeSH] OR "cervix cancer"
  OR "cervical carcinoma" OR "carcinoma of the cervix" OR "cancer of the cervix"
  OR "uterine cervical cancer")
  AND (
    (cisplatin OR radiotherapy OR "radiation therapy" OR chemoradiation
    OR chemoradiotherapy OR brachytherapy OR radiosensiti* OR chemosensiti*
    OR synerg* OR potentiat*)
    OR
    ("drug repurposing" OR "drug repositioning" OR "repurposed drug"
    OR "repositioned drug" OR "drug rediscovery" OR "drug reprofiling"
    OR "drug redirecting" OR "new indication" OR "combination therapy" OR "off-label")
  )
  ```
  Para ClinicalTrials.gov, la misma cadena sin la sintaxis `[MeSH]` (no
  soportada por su motor de búsqueda).
- **Por qué dos bloques y no facetas AND estrictas.** Se probó primero una
  estructura de facetas limpias (población AND tratamiento AND mecanismo,
  cada una obligatoria) — y **falló empíricamente**: recuperó 0-1 de los 5
  ensayos clave, porque exigir coincidencia simultánea en cada faceta
  multiplica las formas en que un estudio real puede quedar fuera (ej. un
  ensayo dice "synergize" como verbo y no "synergy"/"synergistic"; otro dice
  "radiation treatment" y nunca "cisplatin"/"radiotherapy"/"chemoradiation";
  otro enmarca el mecanismo como "hypoxia-modifying" sin ningún término de
  sensibilización). Un solo bloque OR amplio solo necesita **una**
  coincidencia en cualquier parte del texto, y sí recuperó los 5 de 5. El
  agrupamiento en dos bloques con nombre (tratamiento vs. reposicionamiento)
  es cosmético para la redacción de métodos — booleanamente equivalente a
  un bloque plano — y se verificó que da resultados idénticos.
- **Auditoría de sinónimos de población (2026-09-27).** Se consultó la API
  de MeSH de la NLM (descriptor `D002583`, concepto `M0003943`) y se
  confirmaron como sinónimos oficiales: *Cervical Cancer, Cervix Cancer,
  Cancer of the Cervix, Cancer of Cervix, Uterine Cervical Cancer, Cancer
  of the Uterine Cervix*. "Cervix cancer" faltaba en la versión anterior.
  En ClinicalTrials.gov el aporte marginal de estos sinónimos fue nulo
  (921→921, porque el campo de condición ya normaliza cualquier fraseo),
  pero se conservan para PubMed, donde un artículo muy reciente puede no
  estar indexado aún con el MeSH y depender del texto libre.
- **Auditoría de los bloques de tratamiento y reposicionamiento
  (2026-09-27).** Probando cada término dentro del contexto completo de la
  cadena (nunca aislado — un término aislado en ClinicalTrials.gov puede
  dar un conteo que no refleja su aporte real dentro del AND), se
  encontraron términos genuinamente faltantes: `chemoradiotherapy`,
  `"radiation therapy"` y `brachytherapy` en el bloque de tratamiento
  (921→931); `"repurposed drug"`, `"repositioned drug"`, `"drug
  rediscovery"`, `"drug reprofiling"`, `"drug redirecting"` y `"off-label"`
  en el de reposicionamiento (921→922). Cadena final combinada: 933
  estudios en ClinicalTrials.gov, los 5 ensayos clave siguen encontrándose
  los 5 de 5.
- **Bug encontrado en la API de ClinicalTrials.gov: comodines de
  truncamiento poco confiables.** `radiosensiti*`, `synerg*` o `repurpos*`
  aislados (sin ningún otro término en el mismo grupo) devuelven 0 de forma
  errática, aunque esos mismos comodines sí funcionan correctamente dentro
  de la cadena completa ya validada. Por eso las adiciones nuevas de esta
  auditoría se escribieron con palabras completas, no con comodines nuevos
  — el riesgo de que uno falle en silencio no vale la ganancia marginal de
  recall de truncar una palabra más.
- **2026-09-27. Tratamiento como requisito obligatorio (AND), no solo una
  opción dentro del OR — decisión final tras correr la etapa 1 real.**
  Con el bloque único (tratamiento O reposicionamiento como alternativas),
  la corrida real en PubMed identificó 23,959 artículos — y el tope de
  seguridad `max_records: 5000` se activó de verdad, truncando la descarga
  a una muestra parcial y sesgada hacia lo más reciente (no un tope
  "que nunca se alcanza" como se pensó al definirlo). Para evitar tanto el
  volumen inmanejable como la descarga incompleta, se exige ahora
  `cisplatin/radiotherapy/...` como AND obligatorio, no como una opción más
  del OR. Costo medido: de los 5 ensayos clave, se recuperan 3 de 5
  (NCT03256916 nelfinavir, NCT00532818 y NCT00404326 hidralazina-valproato).
  Se pierden los 2 de metformina (NCT02394652, NCT04275713): ninguno usa
  lenguaje de sensibilización/sinergia/reposicionamiento — describen el
  mecanismo como "mejora de la oxigenación tumoral"/"hipoxia", un framing
  metabólico que ningún término de la cadena cubre. Se acepta esta pérdida
  conscientemente, documentada como limitación, a cambio de un volumen
  manejable: **1475 en PubMed (antes 23,959) y 94 en ClinicalTrials.gov
  (antes 933)**.
- **Dos cadenas distintas por fuente, no una traducción mecánica.** Al
  volver a probar la estructura de 3 grupos AND anidados (población,
  tratamiento, mecanismo/reposicionamiento) con el bug de comodines de
  ClinicalTrials.gov ya conocido, reapareció (0/5 ensayos, 73 resultados).
  Se resolvió escribiendo `search_string.pubmed` y
  `search_string.clinicaltrials` como dos cadenas separadas en
  `config.yml`: PubMed conserva los comodines (`radiosensiti*`, `synerg*`,
  etc., que ahí sí funcionan bien anidados), ClinicalTrials.gov usa las
  formas completas deletreadas (`radiosensitizing`, `synergize`, etc.). Ya
  no hay una función de traducción automática entre las dos — cada fuente
  tiene su propia cadena, redactada a mano pero derivada de la misma.
- **2026-09-27. Recuperación de los 5/5 ensayos con términos generales, no
  con mecanismos específicos.** Se revisó el protocolo completo de los 2
  ensayos de metformina perdidos (campos de brazos/intervenciones de
  ClinicalTrials.gov, no solo el resumen): ambos SÍ combinan metformina
  concurrentemente con cisplatino/radioterapia estándar — no son
  irrelevantes, es un hueco real de vocabulario. Se evaluó agregar
  "hypoxia"/"oxygenation" (rescata los 2, pero es un mecanismo específico
  más de una lista que nunca converge — el usuario objetó esto
  correctamente). Se probó en su lugar **`resistance`** y **`"in
  combination with"`**, ambos conceptos generales (aplican a cualquier
  sensibilizador, no a un mecanismo particular): `"in combination with"`
  recupera NCT02394652 (lo tiene textualmente en el resumen);
  `resistance` recupera NCT04275713 (su título dice "Overcoming
  Radiotherapy Resistance"). Con ambos, 5/5 ensayos, sin nombrar hipoxia,
  autofagia, ni ningún mecanismo específico.
- **2026-09-27. Por qué el bloque de tratamiento y el de mecanismo NO se
  fusionan en uno solo, aunque compartan campo semántico (radio-/quimio-).**
  Se probó fusionarlos: el volumen vuelve a dispararse (PubMed 26,441,
  ClinicalTrials.gov 1,116 — casi el mismo problema del principio). Motivo:
  `cisplatin`/`radiotherapy` son tan universales en la literatura de cáncer
  cervicouterino que, dentro de un OR, satisfacen la condición por sí
  solos sin que el bloque de mecanismo aporte nada. Mantenerlos como dos
  requisitos AND separados fuerza dos condiciones independientes
  (¿es sobre el tratamiento estándar? Y, por separado, ¿señala algo
  combinado/potenciado/reposicionado?) — la segunda es la que de verdad
  discrimina. El agrupamiento en la cadena refleja el rol lógico de cada
  bloque, no la similitud temática de las palabras.
- **2026-09-27. Términos evaluados y rechazados para el bloque de
  mecanismo/reposicionamiento**, cada uno probado empíricamente contra el
  contexto completo de la cadena (nunca aislado) y con muestra de
  resultados revisada a mano:
  - `adjuvant`: ruido (+88 registros, casi todos de imagenología,
    toxicidad o quimioterapia neoadyuvante prequirúrgica con fármacos
    oncológicos — "adjuvante" en su sentido oncológico genérico de
    secuencia de tratamiento, no de modificación farmacológica).
  - `neoadjuvant`: mismo problema (+54 registros, quimioterapia
    neoadyuvante antes de cirugía con fármacos oncológicos estándar).
  - `enhancement`/`enhancing`: ruido (dilatadores vaginales, programas de
    adherencia, biomarcadores — nada de combinación farmacológica).
  - `augment*`: ruido (resonancia magnética, hipofraccionamiento,
    radioterapia adyuvante en cáncer de **endometrio** — población
    equivocada).
  - `"added to"`: **sí aceptado** — trae al menos un hallazgo genuino
    ("Radiotherapy + Metronidazole vs Radiotherapy Alone", metronidazol es
    justo el tipo de fármaco no oncológico que se busca) más algunas
    combinaciones con fármacos oncológicos que el cribado excluirá
    correctamente después (no es ruido de búsqueda, es precisión normal
    de cribado).
- **2026-09-27. Consistencia entre fuentes: palabras completas en las dos,
  pero con `[tiab]` en PubMed.** Copiar las palabras deletreadas de
  ClinicalTrials.gov directamente a PubMed sin más disparó el volumen a
  7,319 (de 2,782 con comodines) — no por más cobertura real, sino porque
  una palabra suelta sin comodín activa el "mapeo automático de términos"
  de PubMed, que expande de forma poco predecible (se encontró en la
  muestra un resultado sobre un brote alimentario y vacunación, sin
  ninguna relación). Restringir cada término a título/resumen con
  `[tiab]` da la misma redacción exacta que ClinicalTrials.gov, sin la
  expansión errática: **1,834** en PubMed, más controlado y predecible que
  tanto la versión con comodines como la versión sin restringir.
- **Números finales de la etapa 1: PubMed 1,834, ClinicalTrials.gov 212.**
  Los 5 ensayos clave de la propuesta original se recuperan los 5 de 5.
- **Por qué el contexto de tratamiento y no el nombre del fármaco — ⚠
  SUPERADO el 2026-09-28, ver la nota al inicio del documento.** El
  razonamiento de este párrafo (que el criterio de tratamiento ya volvía
  redundante buscar por nombre) se probó empíricamente y resultó
  incorrecto: 1,136 artículos que sí combinan un fármaco del catálogo con
  el tratamiento estándar nunca aparecen en la rama de solo-contexto,
  porque no usan vocabulario de mecanismo en el resumen. La objeción sobre
  el ruido de nombres comunes (`metformin AND cervical cancer`) seguía
  siendo válida — por eso la rama nominal reinstalada exige tratamiento
  como AND, no solo el nombre del fármaco solo. Se conserva este párrafo
  como registro de por qué se tomó la decisión original, no porque siga
  vigente.
- **Validación empírica (2026-09-27):** se probó la cadena de solo-contexto
  contra ClinicalTrials.gov y se confirmó que recupera los 5 ensayos clave
  de la propuesta original sin necesidad de nombrar ningún fármaco:
  NCT03256916 (nelfinavir, NELCER), NCT00532818 y NCT00404326 (hidralazina-
  valproato), NCT02394652 y NCT04275713 (metformina). Volumen total de la
  cadena en ClinicalTrials.gov: ~857 estudios — manejable en una sola
  consulta, sin loop por fármaco.
- **Precedente citable:** Low, Rodriguez-Berriguete & Higgins (2024,
  `10.1136/bmjonc-2023-000192`, ya en la lista de referencias) usan
  exactamente este patrón — búsqueda por concepto de tratamiento para la
  literatura general, búsqueda nominal por fármaco reservada solo para
  registros de ensayos clínicos — con la diferencia de que en nuestro caso
  ni siquiera hace falta la parte nominal, porque el criterio de inclusión
  ya exige combinación con cisplatino/radioterapia (ver validación arriba).
- **Reporte PRISMA-S:** el diagrama de flujo reporta un número por fuente
  (identificados en PubMed: N; en ClinicalTrials.gov: N). La cadena
  completa y la fecha exacta de búsqueda van en `search_log.csv`
  (`data/01_busqueda/`), y las respuestas crudas de API quedan archivadas
  sin modificar con timestamp en `data/01_busqueda/raw/`.
- **Sin tope artificial de resultados** (`max_records` en `config.yml` es
  un techo de seguridad de 5000, no un muestreo): a diferencia del piloto
  anterior, esta es la corrida real, así que se recupera todo.

### Etapa 2 — Deduplicación

- **DOI normalizado + PMID exactos + título exacto normalizado con mismo
  año** (`R/02_deduplicate.R`), los tres criterios estándar que usan
  Rayyan/EndNote al importar. Nada de similitud difusa de texto — eso se
  le deja a Rayyan en la etapa 3, que ya trae un algoritmo de
  deduplicación publicado y citable. Ver historial para por qué se
  descartó la deduplicación difusa que sí se llegó a implementar.
- **Título exacto exige también el mismo año** (no título solo): se
  encontraron en el corpus real dos pares de artículos con título idéntico
  pero genuinamente distintos — "Chemotherapy for recurrent cervical
  cancer" (2007 y 2008) y "Adenocarcinoma of the uterine cervix" (1981 y
  1986). Fusionarlos solo por título habría sido un error real (perder dos
  estudios distintos), no una limpieza.
- **2026-09-27. Resultado de la corrida real: 0 duplicados fusionados
  (2045 → 2045), incluso con el criterio de título+año agregado.** Se
  verificó que no es un bug: cero IDs repetidos dentro de PubMed y cero
  dentro de ClinicalTrials.gov (el fetch es limpio), y los únicos títulos
  idénticos del corpus son los dos pares genuinos de arriba (años
  distintos, correctamente no fusionados). Es el resultado esperado para
  esta combinación de fuentes: PubMed indexa artículos publicados,
  ClinicalTrials.gov indexa registros de ensayos — son sistemas de
  identificadores disjuntos por diseño, a diferencia de combinar bases que
  indexan el mismo tipo de contenido (ej. PubMed+Scopus+Embase, donde sí se
  esperaría traslape real).
- Representante de cada cluster: se prefiere el registro con `abstract` no
  vacío, y entre esos, PubMed sobre ClinicalTrials.gov.

### Filtro de fármaco no oncológico — ANTES del cribado en Rayyan

- **2026-09-27. Orden invertido respecto al diseño original, decisión
  explícita del usuario.** El nombre del fármaco es un criterio de
  inclusión obligatorio: si el artículo no prueba ningún fármaco no
  oncológico, no puede pasar la revisión sin importar lo que diga el
  cribado de tema. Por eso este filtro corre automáticamente antes de
  Rayyan, no después como en el diseño original — con la salvaguarda de
  que nunca se excluye un artículo sin haber podido revisar su resumen.
- **Catálogo automático:** RxNorm/RxClass, enumerando las 92 clases ATC de
  segundo nivel que no son L01/L02 (antineoplásicos/terapia endocrina
  oncológica) y uniendo sus miembros — 2,824 ingredientes únicos, sin
  curación manual. Implementa la misma regla de siempre (excluir solo si
  *todos* los códigos ATC de un ingrediente son L01/L02) porque un
  ingrediente que aparezca en cualquier clase no oncológica queda incluido
  automáticamente, sin importar si también tiene clasificación oncológica
  en otro lado.
- **Excepción manual encontrada con evidencia: `bevacizumab`.** ATC real
  L01FG (oncológico, inhibidor VEGF) + S01LA (antineovascularización
  oftalmológica) — el algoritmo lo incluía por tener un código no
  oncológico, pero es un fármaco oncológico reposicionado *hacia*
  oftalmología, dirección opuesta a la que busca esta revisión. Confirmado
  con muestra: sus menciones en el corpus son de inmunoterapia oncológica
  combinada (serplulimab, ivonescimab + bevacizumab).
- **Exclusiones de ruido bioquímico genérico:** `oxygen`, `glucose`,
  `hydrogen peroxide` — tienen código ATC real pero en el corpus aparecen
  casi siempre como vocabulario bioquímico general (especies reactivas de
  oxígeno, metabolismo celular), no como intervención administrada.
- **2026-09-27. Se intentó primero contra TEXTO COMPLETO (JATS vía NCBI
  efetch db=pmc, excluyendo `<back>` — bibliografía, agradecimientos,
  financiamiento) y se descartó.** Cobertura real: de 1,833 artículos de
  PubMed, solo 773 tenían PMCID candidato a texto abierto (42%); de esos,
  una fracción further fallaba con 404 al pedir el XML (tener PMCID no
  garantiza que el texto completo este servible, ni siquiera para
  artículos marcados `isOpenAccess: Y`). Más grave: la sección de métodos
  del texto completo está llena de reactivos de laboratorio con ATC real
  (tripsina, penicilina/estreptomicina de medio de cultivo, DMSO como
  solvente, urea/nitrógeno de buffers) que el resumen nunca menciona —
  confirmado con muestra real, ej. un artículo sobre HIF2A y resistencia a
  cisplatino salió con "match" de `chloroquine, streptomycin, nitrogen,
  penicillin g`, donde solo chloroquine es real señal, el resto es ruido
  de protocolo de cultivo celular. Revertido a título+resumen solamente.
- **Problema técnico encontrado y corregido en el camino:** la primera
  implementación del emparejamiento (una sola expresión regular con ~2,800
  alternativas) tardaba más de 20 minutos contra texto completo (~90 mil
  caracteres por artículo) sin terminar — el motor de retroceso de regex
  no escala con alternancias tan grandes contra texto largo. Se reemplazó
  por tokenización + intersección de conjuntos para nombres de una palabra
  (2,178) y búsqueda de subcadena fija para nombres de varias palabras
  (645) — de minutos sin terminar a segundos. Relevante también si se
  retoma el emparejamiento contra texto completo más adelante.
- **Resultado final (título+resumen, `R/05_catalogo_farmacos.R`):** de
  2,045 artículos deduplicados, **271 con coincidencia de fármaco
  candidato**, **1,763 revisados sin ninguna coincidencia (excluidos con
  seguridad — sí tenían resumen que revisar)**, **11 sin resumen
  disponible (no se excluyen, pasan a cribado marcados como no
  verificados)**. Total a cribado en Rayyan: **282**. Muestra de calidad
  revisada a mano: 8 de 10 candidatos son plausibles o claramente
  correctos (metformina, cidofovir, selenito/selenato de sodio,
  glutatión), sin el contamine de reactivos de laboratorio que sí
  apareció con texto completo.
- **2026-09-27. Validación formal de los excluidos (n = 25, muestra
  aleatoria) — la que el documento original pedía ("al menos 20").**
  Motivo: al ver la caja "excluidos por herramienta automatizada (n =
  1763)" en el diagrama PRISMA formal, el volumen (86% del corpus) generó
  la duda razonable de si el filtro estaba perdiendo información real.
  Se revisaron 25 títulos al azar del bucket `excluible_sin_farmaco`:
  **25/25 correctamente excluidos**. Composición: 22/25 son justo lo
  esperado (mecanismos moleculares — lncRNA/miRNA, resistencia
  mitocondrial; combinaciones entre dos fármacos oncológicos; técnicas de
  radioterapia; biomarcadores/imagenología; sin ningún fármaco no
  oncológico involucrado). 2/25 (ácido gálico, fenólicos de aceite de
  oliva) son compuestos dietéticos sin indicación aprobada por la FDA —
  quedarían fuera de todos modos por el propio criterio de inclusión
  ("indicación aprobada previa"), no es un fallo del catálogo. 1/25
  (interferón mencionado de forma genérica, sin formulación específica)
  reveló una limitación real y menor: el catálogo indexa nombres de
  ingrediente específicos (ej. "interferon alfa-2a"), no nombres de clase
  genéricos — documentado, no corregido todavía.
- **Conclusión sobre el volumen (86% excluido):** no es evidencia de sesgo
  del filtro — es consistente con la premisa central de la revisión (que
  el espacio de fármacos no oncológicos en este contexto está poco
  explorado). Si la mayoría de la literatura de "quimiorradiación +
  modificación" ya fuera sobre fármacos no oncológicos, el argumento de
  vacío de literatura de la propia revisión se debilitaría.
- `R/04_fetch_fulltext.R` queda escrito (funciona, probado) pero no se
  ejecuta en el pipeline activo — se retoma si hace falta texto completo
  para otro propósito (ej. extracción fina de Tabla 1 sobre los ya
  incluidos tras el cribado, donde el riesgo de ruido de reactivos importa
  menos porque ya se sabe que el artículo es relevante).

---

## Historial de diseño (decisiones descartadas o superadas)

Se conserva por trazabilidad metodológica, no refleja el pipeline actual.

**Búsqueda con tres cadenas y fuentes (versión original).**
Se partió de tres cadenas — A: reposicionamiento explícito, B:
sensibilización, C: nominal por fármaco iterada sobre un catálogo — contra
PubMed, Europe PMC y ClinicalTrials.gov. Se descartó por, en orden:
- Europe PMC generaba complejidad desproporcionada: preprints cuyo título
  se reescribe en la versión publicada (ver caso PRDM1 más abajo), una
  llamada de detalle adicional por artículo para obtener resumen/MeSH, y
  conteos brutos enormes (hasta 10930 para la cadena C) sin aportar
  cobertura que PubMed no tuviera ya.
- La cadena C (nominal por fármaco) requería resolver, para volverla
  automática de verdad: qué nombre usar por fármaco (bug real: RxNorm
  puede resolver "metformin" a la variante con sal "metformin
  hydrochloride", que da 0 resultados en PubMed — corregido prefiriendo
  TTY=IN sobre PIN), si incluir marcas comerciales, y qué tan amplio hacer
  el catálogo de origen (la pregunta de "qué grupos ATC conservar" que
  nunca se resolvió). Analizado con evidencia real (los 5 NCT de la
  propuesta), se confirmó que la cadena de contexto sola ya cubre lo que la
  cadena C pretendía rescatar, así que se eliminó por completo.
- Fusionar A+B en una sola cadena de concepto (intermedio, ya superado
  también) — la versión final integró además los términos de sinergia
  (`synerg*`, `potentiat*`) que la propuesta original excluía confiando en
  que la cadena C los rescataría; al eliminar la cadena C, esos términos
  volvieron a hacer falta en la cadena de concepto.

**Deduplicación por similitud de texto (implementada y luego retirada).**
Se llegó a implementar una cascada DOI → PMID → vínculo NCT → similitud de
título (Jaro-Winkler, luego coseno de bigramas tras encontrar que
Jaro-Winkler pierde pares cuando el texto agregado es un *prefijo*, ej.
"Preprint: ..." — caso real: el preprint de Europe PMC PPR1227056 vs. su
versión publicada, con título reescrito de "Drives" a "Is Associated
with", daba 0.805 con Jaro-Winkler —invisible— y 0.929 con coseno
—correctamente en banda de revisión—). Se retiró completa porque: (1) es
la clase de decisión (¿por qué ese umbral, por qué esa métrica?) más
difícil de defender en métodos frente a "usamos la deduplicación estándar
de Rayyan"; (2) Rayyan hace esto mismo con un algoritmo ya publicado, así
que reimplementarlo no añade rigor, solo superficie de error.

**Catálogo de fármacos: RxNorm + openFDA con recorte de sal y marcas
comerciales.** Se construyó un catálogo con normalización de sal
(`strip_salt_suffix()`), cruce de aprobación FDA vía NDC, expansión con
marcas comerciales para la búsqueda nominal, y exclusión de oncológicos por
regla ATC "todos los códigos son L01/L02". Todo esto queda archivado en
`R/` de versiones anteriores (recuperable del historial de git si hace
falta) y se retomará, simplificado, en la etapa 5 — ya no necesita resolver
qué nombre usar para *buscar* (no hay búsqueda por fármaco), solo qué
nombres usar para *emparejar* texto, que es un problema más simple.

**Paquetes de deduplicación descartados:** `{ASySD}` (arrastra Shiny +
shinyjs + shinythemes + bibliometrix + igraph + RecordLinkage) y
`{synthesisr}` (instala `vroom`/`readr` con compilación C++ lenta). Ya
irrelevante tras retirar la deduplicación difusa por completo.

**Filtro de idioma:** solo inglés (diverge de la propuesta original en
`Propuesta_art_revision.docx`, que incluía español). Riesgo declarado:
podría excluir literatura latinoamericana en español (ej. los ensayos
mexicanos de hidralazina-valproato) — se menciona en limitaciones.

## 2026-10-13. Bloque de tratamiento angostado a solo cisplatino/carboplatino

**Decisión explícita del usuario, objetivo declarado: reducir el universo
de artículos.** El bloque de tratamiento pasó de `(cisplatin[tiab] OR
carboplatin[tiab] OR radiotherapy[tiab] OR "radiation therapy"[tiab] OR
chemoradiation[tiab] OR chemoradiotherapy[tiab] OR brachytherapy[tiab])` a
solo `(cisplatin[tiab] OR carboplatin[tiab])` — se quitan los cinco
términos relacionados con radioterapia/quimiorradiación, igual en las dos
fuentes (`ctgov_treatment` en espejo, sin `[tiab]`).

**Validación empírica antes de aplicar el cambio (no se aplicó a ciegas).**
Se corrió un script ad-hoc fuera de `_targets.R` contra la API real de
PubMed, con los mismos 2,004 nombres de fármaco en lotes de 80, la misma
población y el mismo filtro de fecha, cambiando únicamente el bloque de
tratamiento:
- Cadena amplia (la de antes): 566 PMIDs únicos.
- Cadena angosta (cisplatino/carboplatino solo): 256 PMIDs únicos.
- Los 256 son subconjunto exacto de los 566 (0 PMIDs nuevos que la cadena
  amplia no tuviera ya) — se pierden 310, no se gana nada.

**Riesgo declarado, explícito, no oculto.** Angostar así excluye cualquier
artículo que mencione el tratamiento como "chemoradiation"/
"chemoradiotherapy"/"brachytherapy" en el resumen indexado sin nombrar
"cisplatin"/"carboplatin" explícitamente en ese mismo texto — por ejemplo,
un ensayo centrado en la técnica de radioterapia que solo menciona el
citostático en la sección de métodos no indexada en el resumen. Esto es
justo el tipo de registro que el criterio de inclusión original
(Propuesta_art_revision.docx, S6: "combinación con cisplatino, con
radiación ionizante o con ambos") sí contempla, así que el riesgo de perder
evidencia relevante es real, no cosmético — se documenta aquí por
transparencia metodológica, siguiendo la misma norma del resto de este
archivo.

**Resultado de la corrida completa de `tar_make()` tras el cambio (no solo
el conteo de PMIDs — con metadatos completos, deduplicación y exclusiones
estructurales ya aplicadas):**
- PubMed: 256 artículos (confirma el número de la validación).
- ClinicalTrials.gov: 216 estudios (antes 294 — mismo efecto del bloque
  angostado, aplicado igual en `ctgov_treatment`).
- Identificados en total: 472 (antes 858).
- Deduplicados: 469 únicos (3 fusionados — antes 10; menos duplicados
  cruzados PubMed↔ClinicalTrials.gov porque hay menos registros de cada
  lado que puedan coincidir).
- Excluidos antes del cribado (`classify_metadata_exclusions()`, sin
  cambios en su lógica): 21 ensayos de ClinicalTrials.gov sin datos
  posibles (`WITHDRAWN`/`NOT_YET_RECRUITING`) + 12 revisiones de PubMed
  (separadas para minería de referencias, no descartadas) + 0 retractados +
  0 editorial/protocolo sin resultados = 33 excluidos en total.
- **A Rayyan: 436 registros** (antes 769).

El catálogo de fármacos (2,826 → 2,008 ingredientes) no cambió — se
reconstruyó en la misma corrida por estar corriente arriba de la
búsqueda en el grafo de `targets`, y dio el mismo número que antes, como
se esperaba (el catálogo es independiente del bloque de tratamiento).

## 2026-10-15. Se retira la deduplicación propia en R — queda solo en Rayyan

**Decisión explícita del usuario:** la deduplicación por DOI/PMID/título+año
y mención de NCT cruzada (`R/02_deduplicate.R`, `deduplicate_articles()`,
`merge_by_nct_mention()`) se consideró "casera" frente a lo que Rayyan ya
hace de forma nativa al importar (coincidencia por DOI, título, autores,
año, con un algoritmo publicado y mantenido). El usuario pidió no duplicar
ese trabajo. Se retiró el archivo completo, su función de guardado
(`save_stage2_outputs()` en `R/utils_io.R`), el target `articles_deduped`/
`stage2_outputs` en `_targets.R`, la ruta `paths$stage2` en `config.yml`, y
su archivo de pruebas (`tests/testthat/test-deduplicate.R`) — nada se dejó
a medias ni como código muerto comentado.

**Lo que SÍ se queda en R, y por qué no es lo mismo que deduplicar:**
`classify_metadata_exclusions()` (en `R/03_export_screening.R`) no se tocó.
Es una regla sobre un campo de metadato que ya trae cada registro (estado
de ClinicalTrials.gov, tipo de publicación de PubMed) — Rayyan no tiene
forma de evaluar eso, no es una comparación entre registros para encontrar
duplicados. Confundir las dos cosas habría sido un error real: una es
identificar que dos registros son el mismo estudio, la otra es decidir que
un registro no puede aportar evidencia aunque sea único.

**Consecuencia para el diagrama PRISMA:** la caja "Duplicados eliminados"
ya no se llena en esta etapa — se llenará con lo que Rayyan reporte después
de que el equipo importe `para_rayyan.ris` y confirme las fusiones que
Rayyan proponga. Mientras tanto queda pendiente (`n = —`), igual que el
resto de las cajas de cribado y elegibilidad.

**Consecuencia para `ris_record()`:** el campo `N1` del RIS, que antes
llevaba el `cluster_id` del clúster de deduplicación, ahora lleva
`source`+`source_id` (ej. `pubmed 37851143`) — sigue sirviendo como
identificador interno de trazabilidad, solo que ya no depende de un
concepto (clúster) que dejó de existir.

**Consecuencia para las pruebas automatizadas:** `tests/testthat/` quedó
vacío — los únicos 17 tests que existían en el proyecto eran exactamente
los de `deduplicate_articles()`/`merge_by_nct_mention()`. Ninguna otra
función del pipeline (búsqueda, catálogo, exclusiones estructurales) tenía
tests propios. Esto no se resolvió aquí por no ser lo que se pidió — se
deja registrado para que quede explícito que "0 tests" es el estado real
actual, no un error de esta sesión.

**Números de la corrida real tras el cambio** (sin deduplicación en R,
mismo bloque de tratamiento angosto del 2026-10-13):
- PubMed 256 + ClinicalTrials.gov 217 = 473 identificados (217, no 216,
  por una diferencia natural de un día entre corridas — ClinicalTrials.gov
  cambia su índice entre consultas).
- Sin deduplicación en R: los 473 pasan completos a
  `classify_metadata_exclusions()` (antes pasaban los 469 ya deduplicados
  de la corrida con dedup en R).
- Exclusiones estructurales: 21 ensayos de ClinicalTrials.gov sin datos
  posibles (9 `WITHDRAWN` + 12 `NOT_YET_RECRUITING`) + 12 revisiones de
  PubMed (separadas para minería de referencias) + 0 retractados + 0
  editorial/protocolo sin resultados = 33 excluidos.
- **473 → 440 registros exportados a `data/03_cribado/para_rayyan.ris`.**
  Este 440 es el archivo que se importa a Rayyan, NO el número final de
  "registros cribados" del diagrama PRISMA — ese número solo se conoce
  después de que el equipo revise y confirme los duplicados que Rayyan
  detecte al importar. Mientras tanto, en el diagrama PRISMA, la caja de
  "Duplicados eliminados" y la de "Registros cribados" quedan en
  `n = —` (pendiente), igual que el resto de las etapas posteriores.

## 2026-10-16. Filtro de fecha de PubMed: se quita el "3000" inventado

**Pregunta del usuario:** el filtro de fecha de PubMed decía
`AAAA:3000[dp]` — ¿por qué el año 3000, no hay otra forma de poner la
fecha actual?

**Respuesta y corrección.** `AAAA:3000[dp]` es un modismo común en cadenas
de búsqueda bibliográfica para decir "desde AAAA, sin límite superior" —
PubMed exige un rango con los dos extremos en el campo `[dp]`, no acepta
un operador de "mayor o igual que" solo, así que históricamente se usa un
año lejano como sustituto de "infinito". El problema: es confuso para
cualquier lector que no conozca la convención (parece un error, no una
decisión), y es impreciso — ningún artículo puede estar publicado en el
año 3000. Como el límite inferior (`date_from_year`) YA se calcula
dinámicamente en cada corrida (`_targets.R`, target `cfg`), no había
ninguna razón real para no calcular el límite superior de la misma forma:
se agregó `cfg$retrieval$date_to_year <- as.integer(format(Sys.Date(),
"%Y"))` junto al cálculo de `date_from_year`, y `fetch_pubmed()` ahora arma
`date_filter` como `"%d:%d[dp]"` con los dos años reales de la corrida, no
un número inventado.

**ClinicalTrials.gov no necesitaba este cambio.** Su filtro
(`AREA[StartDate]RANGE[AAAA-01-01,MAX]`, en `R/01_fetch_clinicaltrials.R`)
ya usa `MAX`, que es una palabra clave real de la sintaxis Essie de
ClinicalTrials.gov (significa "sin límite", documentado por la propia
API) — no es un número inventado, así que no había nada que corregir ahí.

**Verificación antes de aplicar:** se probó un lote pequeño (cisplatin,
temozolomide, metformin) contra la API real de PubMed con
`2006:3000[dp]` y con `2006:2026[dp]` (el año real de hoy) — mismo
conteo (2,641) y mismo conjunto exacto de PMIDs en los dos casos, como se
esperaba (ningún artículo real puede tener fecha futura, así que el
límite superior nunca cambia el resultado en la práctica). El cambio es
puramente de claridad para la sección de métodos, no afecta ningún número
ya reportado — no hizo falta volver a correr el pipeline completo.

## 2026-10-22. Filtro de aprobación FDA: de proxy de RxNorm a verificación directa

**Pregunta del usuario:** el filtro de "aprobado por la FDA" usaba RxNorm
(`rxcui_has_marketed_form()`) como indicador indirecto — el usuario pidió
en su lugar descargar los no oncológicos y filtrar directamente contra una
base de datos de la FDA.

**Validación empírica antes de decidir (muestra de 150 ingredientes del
catálogo pre-filtro, 2,826 en total).** Se comparó el proxy de RxNorm
contra una consulta directa a openFDA (directorio NDC de la FDA) para los
mismos 150 fármacos. Resultado: **77% de acuerdo (116/150)**. De los 34
desacuerdos: 8 eran artefactos de la prueba (nombres de combinación con
"/", que openFDA no indexa así); de los 26 restantes (ingrediente simple),
el patrón fue consistente: el proxy de RxNorm decía "comercializado" para
fármacos genuinamente **descontinuados hace años** en EE. UU. — cephradine
(antibiótico retirado), danaparoid (Orgaran, retirado ~2002),
secobarbital/hexobarbital/butobarbital (barbitúricos de uso hoy muy
restringido), retapamulin, inamrinone, entre otros. La causa: RxNorm
conserva el concepto SCD/SBD de un producto aunque ya no se venda — el
proxy nunca revisaba vigencia, solo "¿existió alguna vez?".

**Decisión: reemplazar el proxy por una verificación directa contra
openFDA, cruzando por RXCUI (no por nombre).** Se consideró y se descartó
un cruce por nombre de texto contra el directorio NDC de la FDA — ya se
había intentado antes en este proyecto (`strip_salt_suffix()`, retirado el
2026-09-27 por complejo) porque la FDA indexa los productos con la forma
de sal incluida (ej. "metoprolol tartrate"), mientras que RxNorm usa el
ingrediente puro ("metoprolol"); además existe el problema, independiente
de las sales, de nomenclatura INN vs. USAN (ej. "alendronic acid" en
RxNorm/INN es el MISMO fármaco que "alendronate" en nomenclatura de EE.
UU., pero un cruce de texto los trataría como distintos). La solución: cada
registro del directorio NDC de openFDA trae un campo `openfda.rxcui` que
lo vincula de vuelta al RXCUI de RxNorm — cruzar por ese número evita los
dos problemas de raíz, sin necesitar ningún diccionario de sales ni de
sinónimos.

**Implementación** (`R/05_catalogo_farmacos.R`):
1. `rxnorm_scd_sbd_ids(rxcui)` — ya existía como parte de la lógica
   anterior, ahora expone la lista completa de RXCUIs de SCD/SBD en vez de
   solo un booleano.
2. `fda_has_active_marketed_form(rxcui)` — NUEVA, reemplaza
   `rxcui_has_marketed_form()` (retirada). Arma una sola consulta a
   `api.fda.gov/drug/ndc.json` con `openfda.rxcui:(id1 id2 id3 ...)` (todos
   los SCD/SBD del ingrediente en una sola llamada, no una por cada uno —
   importante para ingredientes con muchos descendientes, ej. metformin
   tiene 134), y revisa si al menos un resultado tiene
   `listing_expiration_date` igual o posterior a hoy. "Vigente", no solo
   "alguna vez existió".
3. Verificado contra los casos reales de la validación antes de aplicarlo
   al catálogo completo: cephradine, danaparoid y secobarbital —
   confirmado que con el nuevo método NO aparecen vigentes en openFDA
   (0 resultados), corrigiendo el error del proxy anterior. metformin,
   cisplatin y alendronic acid — confirmado que SÍ aparecen vigentes
   (cruzando por RXCUI, "alendronic acid" ya no falla por el problema
   INN/USAN que sí afectaba a un cruce de texto).

**Actualización, mismo día: se reemplazó otra vez, por algo más simple Y
más preciso.** El usuario pidió explícitamente simplificar ("¿no hay una
manera más fácil?"). Se probó `rxcui/{id}/property...` — no, se probó algo
más prometedor: la API separada **`Prescribe`** de RxNorm
(`REST/Prescribe/rxcui/{id}/related.json`), que expone el subconjunto
"RxNorm Current Prescribable Content" — mantenido y depurado por la propia
NLM para reflejar solo lo que está REALMENTE prescribible hoy (excluye
conceptos históricos/retirados). Todo dentro de RxNorm, sin necesitar la
FDA como fuente aparte — una sola llamada por ingrediente, no dos.

**Validación empírica antes de aplicarlo** (misma muestra de 150, mismo
`seed(42)`, los tres métodos comparados a la vez): 91% de acuerdo entre
Prescribable Content y la consulta directa a openFDA (136/150) — mejor que
el 74% del proxy original (111/150 en esta repetición; 77% en la muestra
anterior, consistente). De los 14 desacuerdos, 13 fueron casos donde
Prescribable decía "sí vigente" y openFDA directo decía "no" — pero los 13
fármacos en disputa (evinacumab/Evkeeza, pramlintide/Symlin, obeticholic
acid/Ocaliva, deutetrabenazine/Austedo, factor VIIa, además de varios
suplementos OTC comunes como hierro, calcio citrato e inositol) son casos
reales y conocidos de fármacos vigentes en EE. UU. — es decir, el patrón
indica que la consulta directa a openFDA (implementada por mí sobre el
directorio NDC) tiene sus propios puntos ciegos para biológicos y
suplementos OTC, no que Prescribable Content esté mal.

**Decisión final: `rxnorm_is_prescribable()` (R/05_catalogo_farmacos.R),
usando la API `Prescribe` de RxNorm, reemplaza tanto al proxy original
como al cruce con openFDA.** Es la opción más simple (vuelve a 1 llamada
por ingrediente, igual que el proxy original) y la más precisa de las tres
probadas en este mismo día. `fda_has_active_marketed_form()` y
`rxnorm_scd_sbd_ids()` se retiraron del código — el cruce con openFDA por
RXCUI que se diseñó sigue siendo válido como técnica (y documentado arriba
por si hace falta retomarlo), pero no es lo que corre en producción.

**Números de la corrida real con `rxnorm_is_prescribable()`:**
- Catálogo: **2,826 → 1,626 ingredientes** (42% removidos — notablemente
  más estricto que el proxy original, que removía solo 29%. Consistente
  con lo encontrado en la validación: el proxy original era demasiado
  permisivo, contaba como "comercializados" fármacos descontinuados hace
  años que Prescribable Content sí excluye correctamente).
- PubMed: 243 + ClinicalTrials.gov: 217 = **460 identificados** (antes,
  con el catálogo de 2,008 del proxy original: 256 + 217 = 473 — menos
  fármacos en el catálogo da menos lotes de búsqueda y, en este caso,
  menos resultados).
- Excluidos antes del cribado: 21 ensayos sin datos posibles (9
  `WITHDRAWN` + 12 `NOT_YET_RECRUITING`, sin cambio — no dependen del
  catálogo de fármacos) + 11 revisiones de PubMed (antes 12, variación
  natural del corpus más chico) + 0 retractados + 0 secundario/sin
  resultados = 32 excluidos en total.
- **460 → 428 registros exportados a `data/03_cribado/para_rayyan.ris`**
  (antes 440 con el catálogo del proxy original). Sigue siendo el archivo
  que se importa a Rayyan, no el número final de "registros cribados" —
  ese sigue pendiente de que el equipo confirme los duplicados que Rayyan
  detecte al importar (ver entrada del 2026-10-15).

**Causa raíz confirmada del 9% de desacuerdo (14/150) entre Prescribable
Content y mi cruce directo con openFDA — el usuario preguntó explícitamente
si un desacuerdo menor al 100% no era señal de que la consulta estaba mal
hecha, y tenía razón en pedir que se investigara en vez de solo
argumentarlo.** Caso investigado a fondo: **evinacumab** (Evkeeza).
Confirmado que el registro NDC de evinacumab en la FDA SÍ existe y SÍ está
vigente (`listing_expiration_date: 2026-12-31`), pero su campo
`openfda.rxcui` — el que usaba `fda_has_active_marketed_form()` para
cruzar — viene **vacío** en ese registro. RxNorm, mientras tanto, modela
este fármaco bajo el nombre **"evinacumab-dgnb"** (el sufijo de 4 letras
que la FDA exige desde 2017 para biológicos, para distinguir el producto
de referencia de sus biosimilares), con RXCUIs de producto que nunca
coinciden con el campo vacío de ese registro NDC. Dos problemas
concretos, no uno genérico: (1) el campo `openfda.rxcui` no está poblado
de forma confiable para productos biológicos en los datos de origen de la
FDA — no es arreglable cambiando la consulta; (2) un desajuste de nombre
(evinacumab vs. evinacumab-dgnb) análogo al problema de sales/INN-USAN ya
documentado, pero específico de biológicos. Conclusión: el 9% de
desacuerdo no era ruido aleatorio ni una limitación vaga de "biológicos y
suplementos" — era un defecto identificable y verificado en el método que
ya se reemplazó (`fda_has_active_marketed_form()`, retirado), no en
`rxnorm_is_prescribable()`, que sigue siendo el método en producción.
