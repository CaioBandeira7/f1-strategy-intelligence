# Reproducibility

## Levels

| Level | Components | What you need |
|---|---|---|
| **Fully reproducible** | OpenF1 collection (`src/01_data_ingestion/*.py`); red-flag rule and its tests (`src/02_data_cleaning/regras_limpeza.py`, `test_bandeira_vermelha.py`) | Python 3.9+, pandas, pytest, internet access to `api.openf1.org` |
| **Partially reproducible** | SAS programs 01–22 | SAS Viya with SAS Studio and CAS; programs must run as chained sessions in the order below. OpenF1 data may change over time, so re-collected data can differ slightly from the frozen tables. |
| **Dependent on the original SAS environment** | Model Studio project(s); promoted CAS tables; the VA report; unsaved interactive steps (program "23" labels, program "17b" checks, the `F1_SIMULADOR` load step); `glm_prerace.sas` / `glm_score.sas` | Access to the original SAS Viya for Learners workspace, or a rebuild following the notes below |

## Environment

- **SAS:** SAS Viya (developed on SAS Viya for Learners). The code uses SAS Studio, `PROC PYTHON`, CAS (`cas` session, `CASUSER` caslib), `PROC REGSELECT`, `PROC FOREST`, `PROC GRADBOOST`, `PROC GLM`, `PROC QUANTREG`, `PROC SURVEYSELECT` and `PROC CASUTIL`.
- **Python** (inside SAS Studio or locally): `pandas`; standard library `urllib`, `json`, `time`.
- **Folder:** the code expects a project folder `~/f1` in the SAS Studio home directory (`%sysget(HOME)/f1`).
- **CAS libraries:** `CASUSER` only. Programs start sessions such as `cas s3 sessopts=(timeout=7200);` and `libname casuser cas caslib="casuser" sessref=s3;`.

## Execution order

Run in SAS Studio from `~/f1`, copying `src/**` files into that folder flat (the programs `%include` by bare file name).

| Step | Program(s) | Output |
|---|---|---|
| 1 | `00_coleta_openf1.py` for 2024 and 2025 (as Python, or via `PROC PYTHON`); `07_coleta_treinos.py` | `f1_<year>_*.csv` |
| 2 | `15_coleta_2023.sas` (2023 collection with the corrected red-flag rule) | `f1_2023_*.csv` |
| 3 | `01_importa.sas`, `02_degradacao.sas` (the server keeps these combined as `01_02_importa_degradacao.sas`) | WORK `v24 v25 …`, `deg24`, `box24` |
| 4 | `03_simulador_previsao.sas`, `04_avaliacao.sas` | `sim24`, `sim25`, evaluation tables |
| 5 | `08_degradacao_treinos.sas` (or wrapper `run08.sas`) | inputs A/B/C |
| 6 | `12_auditoria_dados.sas` → `13_referencia_alternativas.sas` (or `run_13.sas`) → `14_v2_referencia_ca.sas` | reference variants, V2, `%boot` macro |
| 7 | `16_auditoria_cv_ca.sas`, `17_auditoria_2023.sas` | audits, 2023 tables |
| 8 | `18_validacao_temporal.sas` → `19_pitin_candidata.sas` | `~/f1/temporal`, `~/f1/candidata` (V3c) |
| 9 | `20_auditoria_simulador.sas` → `21_ajustes_simulador.sas` | `~/f1/simulador_final`, `F1_SIMULADOR_ROTULADO` |
| 10 | `22_marts_va.sas` | `~/f1/va_marts`, `CASUSER.F1VA_*` |

Exploratory programs (05, 06, 09, 10, 11, 03b) are optional and not needed for the dashboard.

### Session notes

- WORK tables and macro variables persist only within a session. After a timeout, rerun the earlier steps or use the wrappers in `src/00_session_wrappers/`.
- `&offM` (MEDIUM vs HARD offset) is created in program 03 from the 2024 GLM estimates. Recompute it in a new session before calling `%simula`; the value obtained was 0.01594.
- The bootstrap uses seed 2025; forests use seed 2025.

## Recreating the tables not covered by saved code

| Table / step | How to recreate |
|---|---|
| `CASUSER.F1_SIMULADOR` | Summarise `sim24` to circuit × scenario (18 × 4 = 72 rows) and promote it to CAS. It was originally built interactively; program 20 documents its columns and checks. |
| English labels ("program 23") | Add label columns to the marts from program 22 (`season_label`, `stage_label`, `exp_label`, `model_short`, `signed_error_s`, `age_band`) and build `F1VA_SIM2024` from `F1_SIMULADOR_ROTULADO`. The exact code was not saved, so the label text should be checked against the exported report definition. |

## Opening or rebuilding the dashboard

1. Load the 13 `F1VA_*` marts into `CASUSER` and promote them.
2. Import the report definition `src/07_visual_analytics/report_definition/F1_Strategy_Intelligence_report_content.json` (once copied into the repo; see the checklist):
   - create an empty report in VA;
   - `PUT /reports/reports/{id}/content` with `Content-Type: application/vnd.sas.report.content+json`, the `If-Match` ETag and an `X-CSRF-TOKEN` header.
3. If table names or caslibs differ, edit the `dataSources[].casResource` entries first.
4. `report_builder/*.js` documents how the JSON was generated. It is not a stand-alone script.

## Not reproducible from this repository

- Model Studio pipelines (V1 history). Program 11 reproduces their regressions in code.
- The exact interactive refinements applied to the VA report; the exported definition contains their final state.
- Byte-identical OpenF1 extracts: the API is live and community-maintained.
