# Data Pipeline

## Sources

| Source | Endpoints used | Notes |
|---|---|---|
| [OpenF1 API](https://openf1.org) (`https://api.openf1.org/v1`) | `sessions`, `weather`, `laps`, `pit`, `stints`, `race_control`, plus practice sessions | Unofficial community API, CC BY-NC-SA 4.0, non-commercial/educational use. The collector retries on HTTP 429 with increasing waits and pauses 2 s between calls. |

No other data source is used. Raw data is not committed (see [data/README.md](../data/README.md)).

## Season scope

| Season | Dry races | Laps in frozen base (V3c) | Role |
|---|---|---|---|
| 2023 | 17 (Imola cancelled; OpenF1 returns 404) | 14,863 | Training (E1, E2) |
| 2024 | 19 | 18,048 | Evaluation in E1, training in E2; simulator calibration |
| 2025 | 18 | 17,669 | Evaluation in E2; simulator retrospective |
| **Total** | **54** | **50,580** | |

- A race is **dry** when OpenF1 weather data records no rainfall for the session.
- Main races only; sprint races are excluded.
- Sprint weekends have a single free-practice session.

## Lap cleaning

Implemented in the collector (`00_coleta_openf1*.py`). The flag `usar2` marks a lap as usable when all of these hold:

| Rule | Excluded laps |
|---|---|
| Start | lap 1 |
| Timing | laps without a valid `lap_duration` |
| Pit | pit-in laps (`is_in_lap`) and pit-out laps (`is_pit_out_lap`) |
| Neutralisation | laps under Safety Car or VSC (from `race_control`) |
| Restart | the first lap after each SC/VSC period |
| Red flag | **v1 (original):** every lap up to the *last* red flag + 2. **Corrected:** only the red-flag lap and the 2 following laps (`regras_limpeza.py`, tested in `test_bandeira_vermelha.py`). |

The v1 red-flag rule removed the whole race up to a mid-race stoppage. The corrected rule was used for the 2023 collection (program 15), where it kept 110 more laps at Melbourne. For 2024 and 2025 the pit-in correction below was applied downstream in SAS.

2023 funnel: 18,255 laps → 14,991 usable before the pit-in correction (SC/VSC 1,964; red flag 164).

## Pit-in identification and correction (V3c, program 19)

The 2023 audit (program 17) found that OpenF1 has **no pit records** for Sakhir, Jeddah, Melbourne, Baku, Miami and Montreal 2023. In-laps there were being treated as clean laps, about 3.4% slower than normal laps.

The final rule, applied identically to all three seasons, treats a lap as a pit-in when **any** of these holds:

- **B.** OpenF1 records a pit stop on that lap (`is_in_lap`).
- **C.** The driver's next lap is a pit-out lap (`is_pit_out_lap`, from the laps endpoint, independent of the pit endpoint).
- **A.** It is the last lap of a stint that is not the driver's final stint.

Exceptions:

- tyre changes under a red flag (within ±1 lap of the flag);
- retirements.

| Season | Stint boundaries | Pit records | Before a pit-out | Boundary only | Red-flag change | Final pit-in laps | Clean laps reclassified |
|---|---|---|---|---|---|---|---|
| 2023 | 601 | 425 | 610 | 73 | 70 | 651 | **128** |
| 2024 | 600 | 616 | 616 | 43 | 18 | 659 | **43** |
| 2025 | 551 | 555 | 555 | 36 | 0 | 591 | **34** |

The 2023 reclassifications break down as Sakhir 44, Montreal 30, Miami 20, Baku 14, Jeddah 11 and Melbourne 9.

The correction changed E1 MAE from 1.327 to 1.325 and left E2 unchanged. No conclusion changed.

## Practice long-run reference

Target: `y = race lap time − reference`, where the reference is the driver's long-run pace in free practice of the same weekend.

- Program 13 compared three constructions:
  - **A:** median of race-simulation laps;
  - **B:** robust per-driver model;
  - **C:** a combination.
- **CA reference (program 14, V2).**
  - Compute `q = reference / driver's best practice lap`.
  - **Observed:** use the long-run median when `q ∈ [Q1 − 3·IQR, Q3 + 3·IQR]`. The bounds are learned only from training seasons (E1: 1.0084–1.1241, n = 271; E2: 1.0056–1.1247, n = 591).
  - **Estimated:** otherwise, `best lap × q_weekend`, the median `q` of drivers with a valid observed reference that weekend.
- Model training uses laps with an **observed** reference only (variant "B", frozen as V3c). Evaluation covers all laps.

Coverage of observed reference A: 2023 **77.0%**, 2024 **83.9%**, 2025 **80.5%**. Share of laps using the estimated reference: 2023 24%, 2024 16%, 2025 18%.

### Reference audit (program 16, 2024 masked validation, n = 306)

| Check | Result |
|---|---|
| Race pace explained by the reference, normal weekends | observed: slope 0.50 (R² 0.10); estimated: slope 1.08 (R² 0.29) |
| Race pace explained by the reference, sprint weekends | observed 0.08 (R² 0.01); estimated 0.23 (R² 0.02) |
| Compression of driver differences | none detected (slope ≈ 1 for the estimated reference) |
| Team bias of the estimated reference | Alpine +0.62 s, Ferrari +0.24, Williams +0.21, Haas −0.31, Red Bull −0.29 |

The team bias is systematic, probably reflecting each team's fuel programme in practice. It is documented as a limitation, not corrected.

## Coverage and limitations

- 2025 includes circuits with no history in the training seasons (Interlagos, Spielberg). Catalunya has history only from 2023.
- Baku 2023 has only 2 practice references, and sprint weekends give a weak reference.
- Circuit × compound combinations unseen in training: 25 laps in E1, none in E2. These were not evaluable.
- The collector reads race length from observed laps; it matched the scheduled distance in every race checked.
