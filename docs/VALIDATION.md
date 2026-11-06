# Validation

## Why a temporal design

Cross-validation within 2024 (leaving one race out) measures generalisation to a **new circuit**. In that setting the circuit effect is not estimable, and the regression falls back on an arbitrary base level (program 16). The practical question is different: *the same circuit, next season*. So all global parameters (q bounds, model coefficients, means) are fitted on training seasons only and evaluated on a later season, on circuits seen in training.

## Experiments

| | E1: development | E2: historical |
|---|---|---|
| Training | 2023 (17 races) | 2023 + 2024 (36 races) |
| Evaluation | 2024, seen circuits: **14 races, 12,867 laps** | 2025, seen circuits: **16 races, 15,659 laps** |
| q bounds (reference) | 1.0084–1.1241 (n = 271) | 1.0056–1.1247 (n = 591) |
| Status of the evaluation year | already used to choose between reference variants (V2/CA): **not an untouched test** | already examined during development: **historical evaluation, not an untouched test** |

## Metric

**MAE** (mean absolute error, seconds per lap) of `y` on all evaluation laps, including laps with an estimated reference. RMSE is stored in the frozen tables but not used for decisions.

## Results (V3c, frozen)

| Model | E1 MAE | E2 MAE |
|---|---|---|
| **V3c**: regression with tyre age, trained on observed refs | **1.325** | **1.134** |
| Without tyre age (same training) | 1.422 | 1.179 |
| **Zero baseline** (lap = practice reference) | 1.332 | 1.302 |

Program 18 benchmarks (before the final pit-in fix):

| Model | E1 MAE | E2 MAE |
|---|---|---|
| Random forest | 1.382 | 1.185 |
| Previous-season circuit × compound mean | 1.565 | 1.395 |

By reference type, E2 with tyre age (program 18): observed reference 1.097, estimated 1.383, atypical 1.70–1.96.

## Race-level bootstrap

- The unit is the **race**, because laps within a race are strongly correlated.
- For each pair of models, compute the per-race difference in MAE: `gain = MAE(second) − MAE(first)`. A positive gain means the first model is better.
- Resample races with replacement 1,000 times (`PROC SURVEYSELECT method=urs`, seed 2025). Each time, take the mean per-race gain, with every race weighted equally, and report the 2.5th–97.5th percentiles. The macro `%boot` is defined in program 14; its lap-weighted variant was used only in earlier comparisons.
- Leave-one-race-out (LORO) ranges are reported as a sensitivity check.

## Confidence intervals and verdicts

| Comparison | E1 gain (95% CI) | Races improved | E2 gain (95% CI) | Races improved |
|---|---|---|---|---|
| Tyre-age effect (with vs without) | **+0.107 [+0.028; +0.207]**: improvement | 11 / 14 | **+0.036 [−0.021; +0.101]**: inconclusive | 10 / 16 |
| V3c vs zero baseline | −0.011 [−0.422; +0.305]: inconclusive | 9 / 14 | +0.178 [−0.199; +0.514]: inconclusive | 12 / 16 |

Program 18 benchmarks, before the pit-in fix:

| Comparison | E1 | E2 |
|---|---|---|
| Regression vs forest | +0.004 [−0.049; +0.069] | +0.016 [−0.059; +0.079] (tie) |
| Regression vs previous-season mean | +0.189 [+0.118; +0.264] | +0.221 [+0.127; +0.315] |

LORO ranges for the tyre-age gain (training on observed references): E1 0.068–0.123; E2 0.020–0.047.

## Positive results

- Training on observed references only beats training on all references in both experiments.
- Tyre age improves predictions clearly in E1. The E2 point estimate is positive but its CI crosses zero.
- The regression clearly beats the previous-season circuit × compound mean.

## Negative results (kept in the dashboard)

- **No reliable advantage over the zero baseline.** In E1 V3c is almost identical to "lap = practice pace". In E2 it is better on average, but the CI crosses zero.
- **The tyre-age effect is unstable across seasons** (E1 vs E2).
- **Circuit levels do not transfer across years.** The previous-season circuit × compound mean is the worst option. The transferable value lies in the *shape* (race progress, tyre age), not the *level*.
- Regression and forest tie out of sample, so there is no basis for a more complex model.

## Limits of generalisation

- Neither 2024 nor 2025 is an untouched test set (see table above).
- Only circuits seen in training are evaluated. New circuits, and unseen circuit × compound combinations (25 laps in E1, none in E2), are not evaluable.
- The estimated reference carries a team-specific bias (see [DATA_PIPELINE.md](DATA_PIPELINE.md)).
- Sprint weekends give a weak reference.
- 2025 metrics are not evidence of future performance.
