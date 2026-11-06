# Project Inventory

This inventory lists every component of *F1 Strategy Intelligence | 2023–2025*: where it lives, what it does, what it depends on and whether it is in this repository. Nothing in the original SAS environment was deleted or overwritten during publication.

Key to the **Status** column:

- **In repo**: original file copied unchanged.
- **Server only**: exists in the SAS Viya environment but not exported here.
- **Not saved**: code was run interactively and only its outputs survive.

`~/f1` refers to the project folder in the SAS Studio home directory.

## 1. Dashboard

| Component | Location | Purpose | Status |
|---|---|---|---|
| VA report *F1 Strategy Intelligence \| 2023–2025* | SAS Visual Analytics, *My Folder* (report id `2451e3ab-…`) | 7-page dashboard | Server only (definition exported, see below) |
| Earlier VA report draft | *My Folder* (report id `3b1ade59-…`) | First build, kept as backup | Server only, preserved |
| Page images `assets/dashboard/01–07-*.png` | exported via VA report-images service | Portfolio gallery | Exported to the author's machine; copy step in [PUBLICATION_CHECKLIST](PUBLICATION_CHECKLIST.md) |
| `reports/F1_Strategy_Intelligence_2023_2025.pdf` | exported via VA PDF service (no cover page) | Full report | Exported to the author's machine; copy step in checklist |
| Report definition JSON (`F1_Strategy_Intelligence_report_content.json`) | VA REST API `/reports/reports/{id}/content` | Re-importable report definition | Exported to the author's machine; target `src/07_visual_analytics/report_definition/` |

## 2. Code

| File (repo path) | Original location / name | Purpose | Depends on | Status |
|---|---|---|---|---|
| `src/01_data_ingestion/00_coleta_openf1.py` | `~/f1/00_coleta_openf1.py` | OpenF1 race collection, v1 red-flag rule (used for the original 2024/2025 CSVs and the frozen V1 benchmark) | OpenF1 API, pandas | In repo |
| `src/01_data_ingestion/00_coleta_openf1_redflag_fix.py` | local working copy | Same collector with the corrected red-flag rule (imports `regras_limpeza.py`) | `regras_limpeza.py` | In repo |
| `src/01_data_ingestion/07_coleta_treinos.py` | `~/f1/07_coleta_treinos.py` | Free-practice (FP1–FP3) laps for dry-race weekends | `f1_<year>_estrategia_real.csv` | In repo |
| `src/01_data_ingestion/15_coleta_2023.sas` | `~/f1` | Runs the collectors for 2023 inside `PROC PYTHON`, patching in the corrected red-flag rule | 00, 07, `regras_limpeza.py` | In repo |
| `src/01_data_ingestion/01_importa.sas` | `~/f1` | Imports 2024/2025 CSVs into WORK | CSVs | In repo |
| `src/01_data_ingestion/legacy_jupyterlab/*.py` | JupyterLab (SAS Viya for Learners) | Earlier notebook versions of the collector | — | In repo (historical) |
| `src/02_data_cleaning/regras_limpeza.py` | `~/f1` | Corrected red-flag rule (flag lap + 2 following laps) | pandas | In repo |
| `src/02_data_cleaning/test_bandeira_vermelha.py` | local | Unit tests old vs new red-flag rule | pytest | In repo (4 tests pass) |
| `src/02_data_cleaning/12_auditoria_dados.sas` | `~/f1` | Data audit (A) and temporal-leakage audit (B) | 01, 02, 08 tables | In repo |
| `src/02_data_cleaning/17_auditoria_2023.sas` | `~/f1` | 2023 coverage and quality vs 2024/2025 | 15, 14 | In repo |
| `src/03_feature_engineering/13_referencia_alternativas.sas` | `~/f1` | Three practice-reference variants (A/B/C) | 12 | In repo |
| `src/03_feature_engineering/14_v2_referencia_ca.sas` | `~/f1` | V2: CA reference (observed or estimated) | 13 | In repo |
| `src/04_modelling/02_degradacao.sas` | `~/f1` (combined server copy: `01_02_importa_degradacao.sas`) | Fixed-effects GLM degradation per circuit (`deg24`), pit loss (`box24`) | 01 | In repo |
| `src/04_modelling/05_ml_degradacao.sas` | `~/f1` | Early ML degradation curves (GLM, gradient boosting, forest) | 01 | In repo (exploratory) |
| `src/04_modelling/10_ml_prerace.sas` | `~/f1` | Pre-race lap-time task definition (practice-relative target) | 07, 08 | In repo |
| `src/04_modelling/11_ablacao_por_corrida.sas` | `~/f1` | Code reproduction of the Model Studio regressions; tyre-age ablation per race | 10, CAS | In repo |
| `src/04_modelling/19_pitin_candidata.sas` | `~/f1` | Final pit-in rule, frozen candidate **V3c**, E1/E2 metrics and bootstrap | 18 session | In repo |
| `src/05_validation/16_auditoria_cv_ca.sas` | `~/f1` | Audits: CA compression; unseen circuits in CV | 14 | In repo |
| `src/05_validation/18_validacao_temporal.sas` | `~/f1` | Temporal validation E1/E2, baselines, race bootstrap, LORO | 14, 17 | In repo |
| `src/06_strategy_simulation/03_simulador_previsao.sas` | `~/f1` | `%simula` cost model and exhaustive search | 02 | In repo |
| `src/06_strategy_simulation/03b_modelo_v2.sas` | `~/f1` | Simulator variant with compound-specific wear (not used in dashboard) | 02, 03 | In repo (exploratory) |
| `src/06_strategy_simulation/04_avaliacao.sas` | `~/f1` | Compares simulator predictions with real 2025 strategies | 03 | In repo |
| `src/06_strategy_simulation/06_oraculo.sas` | `~/f1` | Oracle test: simulator with true 2025 degradation | 02–04 | In repo |
| `src/06_strategy_simulation/08_degradacao_treinos.sas` | `~/f1` | Practice-based degradation (inputs A/B/C) and input selection on 1st half 2025 | 01–04, 07 | In repo |
| `src/06_strategy_simulation/09_janela_ml.sas` | `~/f1` | Quantile regression for the first-stop window | 03, 04 | In repo |
| `src/06_strategy_simulation/20_auditoria_simulador.sas` | `~/f1` | Simulator audit T1–T5 (read-only) | 03, 04, 08 | In repo |
| `src/06_strategy_simulation/21_ajustes_simulador.sas` | `~/f1` | Authorised labelling fixes (Monaco validity, 2025 halves, labelled table) | 20 | In repo |
| `src/07_visual_analytics/22_marts_va.sas` | `~/f1` | Builds the CAS marts for VA from frozen results | 14–21 session | In repo |
| `src/07_visual_analytics/report_builder/*.js` | browser console on the VA host | Generates and PUTs the VA report JSON via REST | VA session, marts | In repo (partial; see note) |
| `src/00_session_wrappers/run08.sas`, `run12.sas`, `run_13.sas` | `~/f1` | Session rebuild wrappers (concatenate earlier programs, then run the next one) | listed programs | In repo |
| Program "23" (English labels for marts) | SAS Studio session | Added `season_label`, `stage_label`, `exp_label`, `model_short`, `signed_error_s`, `age_band`, and built `F1VA_SIM2024` from `F1_SIMULADOR_ROTULADO` with English scenario labels | 22 | **Not saved**; resulting tables exist in CAS |
| Load step for `CASUSER.F1_SIMULADOR` | SAS Studio session | Summarised `sim24` (18 circuits × 4 scenarios) and promoted it to CAS | 03 | **Not saved**; table exists in CAS and was audited in program 20 |
| Program "17b" (in-lap coverage check, `%cobref`) | SAS Studio session | Q14–Q16 checks of in-lap detection and reference coverage | 17 | **Not saved**; findings recorded in VALIDATION/DATA_PIPELINE docs |
| `glm_prerace.sas`, `glm_score.sas` | `~/f1` | Model Studio score code (pre-race GLM) | Model Studio | Server only |
| Model Studio project(s) | SAS Model Studio | Early regression pipelines (reproduced by program 11) | CAS | Server only, not exportable as code here |
| VA polish patches | browser console | Layout, colour map, filters and CI chart refinements applied to the report JSON | VA REST API | Not saved as files; effect is captured in the exported report definition |

Report-builder note: `gen_pages.js` and `assemble.js` show how the report was generated through the VA REST API. They read objects prepared earlier in the same browser session (`window.__n`, `window.__OUT`, …), so they are documentation of the method, not a stand-alone build script. The authoritative definition is the exported report JSON.

## 3. Data and tables (not committed)

| Table / folder | Location | Grain / rows | Produced by |
|---|---|---|---|
| `f1_<year>_*.csv` (laps, stints, race control, weather, practice, strategy) | `~/f1` | per season | 00, 07, 15 |
| `~/f1/candidata/base_candidata` | SAS library | 50,580 laps | 19 |
| `~/f1/candidata/pitin_2023/24/25`, `pred_E1c`, `pred_E2c`, `boot_*`, `manifesto` | SAS library | — | 19 |
| `~/f1/temporal` (`pred_E1`, `pred_E2`, `boot_E1`, `boot_E2`) | SAS library | — | 18 |
| `~/f1/benchmark_v1` | SAS library | frozen V1 benchmark | 11–13 |
| `~/f1/simulador_final` (`prev25_a_validade`, `entrada_b_metades`, …) | SAS library | — | 21 |
| `CASUSER.F1_SIMULADOR` / `F1_SIMULADOR_ROTULADO` | CAS (promoted, `.sashdat`) | 72 rows = 18 circuits × 4 scenarios | 03 / 21 |
| `~/f1/va_marts` and `CASUSER.F1VA_*` (13 marts) | SAS library + CAS | see below | 22, 23 |

VA marts: `F1VA_SEASON` (3), `F1VA_MODEL_METRICS` (6), `F1VA_MODEL_COMPARE` (4), `F1VA_LAP_ERROR` (85,578), `F1VA_RACE_ERROR` (90), `F1VA_DATA_FUNNEL` (12), `F1VA_PITIN_FIX` (11), `F1VA_REF_BIAS_TEAM` (10), `F1VA_TRACK` (18), `F1VA_SIM2024` (derived from `F1_SIMULADOR_ROTULADO`, 72 rows), `F1VA_SIM2025_HALVES` (6), `F1VA_SIM2025_BASELINES` (140), `F1VA_NOTES` (13).

## 4. Internal notes (not published)

The working audit notes (Portuguese) behind the docs were kept in the claude.ai project. Their figures are reproduced in the English docs: the 2023 audit and temporal validation, the simulator audit, the dashboard architecture, the VA marts and the dashboard build log.
