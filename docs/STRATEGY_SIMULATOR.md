# Strategy Simulator

The simulator (`%simula`, program 03) compares one- and two-stop dry-race strategies with a transparent cost model. It is a **separate component**: its degradation inputs come from the 2024 GLM of program 02, not from the V3c regression. Its outputs are **relative costs under its own cost function**, not predicted race times or real time savings.

## Cost function

For a race of `L` laps, circuit degradation `b` (s per lap of tyre age), pit loss `P` (s per stop), and compounds `c ∈ {HARD, MEDIUM, SOFT}` with wear multiplier `m_c` and pace offset `o_c`:

```
cost(strategy) = Σ_stints [ b · m_c · t(t−1)/2  +  o_c · t ]  +  n_stops · P
```

- `t` is the stint length. Tyre age restarts at 0 each stint, so the sum of ages over a stint is `t(t−1)/2`.
- Base pace, fuel and track evolution are the same for every strategy with the same `L`, so they cancel. Results are relative seconds.

## Inputs

| Input | Definition | Source |
|---|---|---|
| `b`, **input A** | `circuito*tyre_age` slope of the 2024 fixed-effects GLM (0.026–0.120 s/lap²) | program 02 |
| `b`, **input B** | `a + c · practice slope`, calibrated on 2024, floor 0.005 (0.016–0.107) | program 08, 2025 free practice |
| `b`, **input C** | average of A and B | program 08 |
| `P` | per-circuit median of (in-lap + out-lap − 2 × typical lap), 2024, excluding SC/VSC and red flag (18.0–30.3 s) | program 02 |
| Compounds | HARD = reference. MEDIUM: `o = +0.01594` s/lap (GLM 2024), `m = 1`. SOFT: 4 fixed scenarios, `m ∈ {1.0, 1.7} × o ∈ {−0.13, 0}` | program 03 (SOFT values are assumptions, not estimates) |

The model is linear in tyre age, with no degradation cliff.

## Exhaustive search

- **1 stop:** first stop at `k1 ∈ [5, L−5]`.
- **2 stops:** `k1 ∈ [5, L−10]`, `k2 ∈ [k1+5, L−5]`.
- All compound sequences with **at least two different dry compounds** are evaluated. The minimum stint is 5 laps, and there are at most 2 stops.
- **Recommendation.** Take the lowest-cost plan in each SOFT scenario, then vote: two stops only if 3 or more of the 4 scenarios agree. The window is the set of laps within 1 s of the optimum, and the predicted lap is the median of the 4 optima.

## Audit (program 20): approved with caveats

| Test | Result |
|---|---|
| Synthetic races (L = 20, b ∈ {0, 0.1, 1.0}, P = 20): 204 rows recomputed lap by lap | max difference 0.000000000 s |
| Stint sums = L; stints ≥ 5; ≥ 2 compounds; duplicates | 0 violations (also on real `sim24` 6,816 rows and `sim25` 5,416 rows) |
| Optimum vs independent exhaustive search | identical (≤ 4e-14) |
| Symmetry, hand calculations (29.0 s and 45.7 s) | match |
| `L` vs scheduled laps (18 circuits 2024, 14 in 2025) | 0 differences |

## 2024 simulation (in-sample)

- `CASUSER.F1_SIMULADOR_ROTULADO`: 18 circuits × 4 SOFT scenarios = 72 rows.
- Scope label: "2024 in-sample". Unit: "relative cost (s), not absolute time". Source: "program 02 GLM, not integrated with V3c".
- It is **descriptive**: the degradation was estimated on the same races it is applied to.

## 2025 historical evaluation (retrospective)

- **14 circuits** have both `b` and `P` from 2024. Catalunya, Interlagos, Spielberg and Lusail are not simulated.
- **Selection leakage.** Input B was chosen over A and C using real results from the **1st half of 2025**. Only the **2nd half** is a later historical evaluation for B. The full 2025 season is not an independent test.

| Input | 1st half (used for selection): stop-count accuracy; first-stop MAE (laps) | 2nd half (later evaluation) |
|---|---|---|
| A: 2024 race degradation | 86%; 9.47 | 29%; 10.57 |
| **B: 2025 practice degradation** | 86%; 8.40 | **43%; 9.87** |
| C: average | 86%; 9.46 | 43%; 9.97 |

**Monaco 2025.** The mandatory two-stop rule is not modelled. With input A the simulator recommends one stop, so that case is flagged **INVALID** (13 of 14 circuits valid for A). Input B happens to predict two stops.

### Baselines under the same cost function

Mean over the 4 scenarios and 14 circuits, in seconds above the simulator optimum:

| Strategy | Input A | Input B |
|---|---|---|
| Simulator optimum | 0.00 | 0.00 |
| Best observed strategy (hindsight) | 3.17 | 2.86 |
| Fixed 1-stop M-H at half distance | 3.42 | 2.89 |
| Fixed 2-stop M-H-H at 1/3 and 2/3 | 8.33 | 7.89 |
| Median observed strategy (237 valid of 288 drivers) | 9.40 | 8.46 |

The optimum is, by construction, the minimum of the model's own function, so this table shows how much the *model* thinks is at stake, not real accuracy. Real strategies look costly here because the model ignores the factors listed below.

## Limitations and rules not modelled

- Traffic, track position, undercut and overcut.
- Safety Car, VSC and red flags (no cheap stops under neutralisation); a constant `P`.
- Tyre-set allocation, used tyres, C1–C6 compound identities, degradation cliffs and weather.
- Three or more stops.
- Circuit-specific rules: Monaco 2025 two-stop (flagged), Lusail 2025 stint cap (Lusail not simulated).
- Fixed SOFT scenarios; HARD and MEDIUM share the same wear, which produces symmetric stints.
- `%simula` relies on the global macro variable `&offM` created outside the macro; it must be recomputed in a new session.
- `L` is read from observed laps, which matched the schedule in all cases.

The simulator **does not predict real F1 team strategies** and makes no claim of proven accuracy.
