# Data

No data files are committed to this repository.

## Why

- **Licence.** The source is [OpenF1](https://openf1.org), an unofficial community API published under **CC BY-NC-SA 4.0** for non-commercial and educational use. Redistributing full extracts would carry those terms into this repository. Regenerating them from the API is simpler and keeps the source authoritative.
- **Size and need.** The raw lap, stint, race-control, weather and practice files for three seasons are large and fully regenerable. The analytical tables (`~/f1/candidata`, CAS marts) are derived from them.

## How to regenerate

Run the collectors in `src/01_data_ingestion/` (see [docs/REPRODUCIBILITY.md](../docs/REPRODUCIBILITY.md)). They write to `~/f1`:

| File | Content |
|---|---|
| `f1_<year>_voltas_para_sas.csv` | Lean lap table with cleaning flags (`usar2`, `is_in_lap`, `is_pit_out_lap`, `sc_t`) |
| `f1_<year>_secas_voltas_marcadas.csv` | All dry-race laps with every flag |
| `f1_<year>_secas_voltas_clima.csv` | Laps joined with weather |
| `f1_<year>_secas_race_control.csv` | Race-control messages (SC, VSC, red flag) |
| `f1_<year>_secas_clima.csv` | Weather |
| `f1_<year>_perda_box_por_pista.csv` | Pit-lane loss per circuit |
| `f1_<year>_stints.csv` | Raw stints |
| `f1_<year>_estrategia_real.csv` | Actual strategy per driver |
| `f1_<year>_treinos_voltas.csv` | Free-practice laps (from `07_coleta_treinos.py`) |

Data credit: OpenF1 (openf1.org). F1 and related marks belong to Formula One Licensing B.V.; this project is not affiliated with Formula 1.
