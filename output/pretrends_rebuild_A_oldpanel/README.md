# Pre-trends Diagnostics Output

Generated: 2026-08-20 00:33:59.787712

## Configuration
- Panel: `data/raw/deprecated/state_month_panel_with_treatment_double_counted_2026-08-20.csv`
- Treatment source: `file`
- Expected treatment source: `<none>`
- Require panel treatment: FALSE
- Resolved schedule: `treatment_schedule_resolved.csv` and `.rds`
- Treatment file: `data/raw/sports_gambling_legalization_dates.csv`
- Requested file-treatment date column: `online_start_date`
- Resolved treatment date column: `online_start_date`
- Excluded states: <none>
- Date range: 2016-01-01 to 2024-12-31
- Dropped window: 2020-03-01 to 2021-07-31
- Coverage threshold: 91
- Balance common months: TRUE
- Outcome: log1p_filings_count
- Control group: notyettreated, est_method: reg
- Allow unbalanced panel: TRUE
- Pre-window: -12 to -1
- Alpha: 0.05

## Panel Summary
- 26 states (17 treated, 9 never-treated)
- 16 treatment cohorts
- 91 months, 2366 observations

## Headline CS Inference Method
**ANALYTIC**

## CS-DiD Pretrends (Analytic)
- Pre-periods tested: 12
- Joint test (Holm): min_p = 0.7961, reject = FALSE
- Overall ATT: 0.0744 (SE = 0.1297)

## CS-DiD Pretrends (Bootstrap)
- Pre-periods tested: 12
- Joint test (Holm): min_p = 1, reject = FALSE
- Overall ATT: 0.0744 (SE = 0.1429)
- Bootstrap iterations: 199

## TWFE / Sun-Abraham Pretrends
- Joint test (Holm): min_p = 1, reject = FALSE

## Inference Notes
- CS p-values: pointwise t-test with df = n_states - 1, Holm step-down for joint test
- SunAb p-values: pointwise t-test with df = n_states - 1, Holm step-down for joint test
- CS p-values are NOT computed via TWFE Wald test (explicitly avoided)

## How to Run
```bash
# Quick (no self-test, no gambling)
bash scripts/run_pretrends_statepanel.sh

# With gambling intensity
GAMBLING_FILE=data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv \
  bash scripts/run_pretrends_statepanel.sh

# With self-test calibration (slow)
SELF_TEST=TRUE N_CORES=4 bash scripts/run_pretrends_statepanel.sh
```

