# Pre-trends Diagnostics Output

Generated: 2026-02-13 13:07:15.04079

## Configuration
- Panel: `data/raw/state_month_panel_with_treatment.csv`
- Excluded states: ME
- Date range: 2016-01-01 to 2020-02-29
- Dropped window: <none> to <none>
- Coverage threshold: 50
- Balance common months: TRUE
- Outcome: log1p_filings_count
- Control group: notyettreated, est_method: reg
- Allow unbalanced panel: TRUE
- Pre-window: -12 to -1
- Alpha: 0.05

## Panel Summary
- 26 states (16 treated, 10 never-treated)
- 14 treatment cohorts
- 50 months, 1300 observations

## Headline CS Inference Method
**ANALYTIC**

## CS-DiD Pretrends (Analytic)
- Pre-periods tested: 12
- Joint test (Holm): min_p = 0.8762, reject = FALSE
- Overall ATT: -0.0651 (SE = 0.0865)

## CS-DiD Pretrends (Bootstrap)
- Pre-periods tested: 12
- Joint test (Holm): min_p = 1, reject = FALSE
- Overall ATT: -0.0651 (SE = 0.0938)
- Bootstrap iterations: 199

## TWFE / Sun-Abraham Pretrends
- Joint test (Holm): min_p = 0.8658, reject = FALSE

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

