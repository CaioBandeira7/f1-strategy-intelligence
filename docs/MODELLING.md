# Modelling

## Problem formulation

> *Before the race, predict each race lap time relative to the driver's free-practice long-run pace of the same weekend.* (Program 10, task fixed before modelling.)

Only information available before the start enters as a feature: circuit, compound, tyre age, race progress and the practice reference. Driver and team identity are not features. They are absorbed by the reference.

## Target

`y = lap_duration − reference_CA` (seconds), on clean laps (see [DATA_PIPELINE.md](DATA_PIPELINE.md)).

## Features

| Feature | Type | Meaning |
|---|---|---|
| `circuito` | class | circuit |
| `compound` | class | SOFT / MEDIUM / HARD |
| `prog` | interval | race progress (lap / race laps), a proxy for fuel burn and track evolution |
| `tyre_age` | interval | laps on the current set |
| `circuito*compound` | interaction | circuit-specific compound offsets |

## V3c regression (frozen candidate)

```sas
proc regselect data=casuser.tall;
  partition role=papel_b(train='T' test='S');   /* T = training laps with observed reference; S = evaluation season */
  class circuito compound;
  model y = circuito compound prog tyre_age circuito*compound;
  selection method=stepwise(select=sbc choose=sbc);
run;
```

- **Selection.** Stepwise, entering and choosing by SBC (Schwarz Bayesian criterion), which penalises extra terms more heavily than AIC.
- **Training set.** Laps whose practice reference is observed (`papel_b`). Training on all laps, including estimated references, was worse in both experiments (E1 1.388 vs 1.327; E2 1.169 vs 1.134).
- **Version history.**
  - V1: Model Studio, first reference.
  - V2: CA reference.
  - V2-B: train on observed references only.
  - **V3c:** V2-B plus the final pit-in rule. It is frozen in `~/f1/candidata`.

### Comparison models (same split)

| Model | Definition |
|---|---|
| Without tyre age | same model without `tyre_age` |
| Random forest | `PROC FOREST`, 100 trees, seed 2025, same inputs |
| Previous-season mean | circuit × compound mean of `y` in the training years |
| **Zero baseline** | `ŷ = 0`, i.e. lap = practice reference |

Unseen circuits behave differently in each model (program 16):

- **REGSELECT:** the new circuit level enters with an empty training column, so its prediction rests on an arbitrary base. The mean difference against the reference-level prediction is 0.335 s.
- **Forest:** treats an unseen circuit exactly as missing.

The temporal design therefore evaluates only circuits seen in training ("same circuit, next season").

## Interactions between circuit and compound

`circuito*compound` lets each circuit have its own compound offsets, since tyre allocations and surfaces vary. A model without circuit terms was worse in leave-one-race-out CV on 2024: MAE 1.256 vs 1.219, better in only 7 of 19 folds. Circuit *levels*, however, do not transfer across seasons; see [VALIDATION.md](VALIDATION.md).

## Separate degradation model for the simulator

The strategy simulator does **not** use V3c. It uses a fixed-effects GLM fitted on 2024 race laps (program 02):

```sas
proc glm data=uso24;
  absorb rp;                                   /* driver × race fixed effect */
  class circuito compound;
  model lap_duration = circuito*lap_number     /* fuel + track evolution per circuit */
                       compound                /* compound pace offset */
                       circuito*tyre_age / solution;  /* degradation slope per circuit */
run;
```

- `b` (degradation) is the `circuito*tyre_age` slope: 0.026–0.120 s per lap of tyre age in 2024.
- The MEDIUM vs HARD offset is `offM = +0.01594` s/lap.
- Lusail is excluded because its effects are confounded.

## Exploratory models (documented, not in final results)

| Program | Model | Outcome |
|---|---|---|
| 05 | GLM / gradient boosting / forest on lap delta vs driver-race median | Early benchmark; superseded by the pre-race formulation |
| 09 | Quantile regression (`PROC QUANTREG`) of first-stop fraction | Explored learned stop windows |
| 10–11 | Pre-race regression, reproduction of Model Studio pipelines | Basis for V1; tyre-age ablation per race |
| 03b | Simulator v2 with compound-specific wear | Not used in the dashboard |
