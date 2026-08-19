# Handle-50 treatment classification QA

Date: 2026-08-14

## Scope

The Handle-50 treatment data now distinguish missing exposure from valid
untreated controls. Classification uses a study start of 2016-01-01 and a
prespecified Handle calibration/study cutoff of 2024-12-31. The peak excludes
2020-03-01 through 2021-07-31; threshold search retains those months.

## State classification

The audit file contains all 39 states in the source eviction panel:

| Status | States | Control eligible | Analysis eligible |
|---|---:|---:|---:|
| Observed Handle threshold treated | 22 | 0 | 22 |
| Never online in window | 14 | 14 | 14 |
| Not yet online after cutoff | 1 | 1 | 1 |
| Legally online, Handle missing | 1 | 0 | 0 |
| Pre-sample treated | 1 | 0 | 0 |

Key cases:

- Florida: legal online start 2023-12-01, no LSR Handle threshold, classified
  `legally_online_missing_handle`, and excluded from the estimator panel.
- Nevada: classified `pre_sample_treated` and excluded from the estimator
  panel. It cannot enter the untreated comparison group.
- Missouri: legal online start 2025-12-01, classified
  `not_yet_online_after_cutoff`, and retained as an eligible control for the
  pre-2025 study window.

## Estimator-ready panel

- Source: 4,120 rows and 39 states.
- Removed: Florida (165 rows) and Nevada (71 rows).
- Output: 3,884 rows and 37 states.
- Treatment composition: 22 Handle-treated states and 15 eligible controls.
- No row has a missing treatment date while also being marked control
  ineligible.

The 15 controls are AK, GA, HI, ID, MN, MO, MS, MT, ND, NM, OK, SC, TX, UT,
and WI.

## Cross-builder agreement

Both treatment builders were run independently with the same defaults:

```bash
Rscript analysis/data_prep/create_activity_treatment_dates.R
Rscript data_prep/build_panel_handle50_treatment.R
```

Their 39-row state classifications agree on every field, and the Handle-50
threshold dates have zero state mismatches. Runtime assertions stop either
builder if a missing-exposure or pre-sample-treated state is made control
eligible, if a threshold predates legal online launch, or if Florida/Nevada
enter the estimator-ready panel.

## Outputs

- `data/processed/handle50_state_classification.csv`: state-level audit table.
- `data/processed/handle50_state_classification_codebook.csv`: field definitions.
- `data/processed/activity_treatment_dates.csv`: all 39 panel states with
  threshold dates and classification fields.
- `data/processed/state_month_panel_handle50_treatment.csv`: 37-state,
  estimator-ready panel with classification fields retained.
- Each CSV above has a same-named `.rds` checkpoint for downstream
  reproducibility.
