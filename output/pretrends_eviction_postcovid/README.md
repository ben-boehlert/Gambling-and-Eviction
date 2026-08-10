# Pre-trends Diagnostics Output

Generated: 2026-02-13 12:06:47.148547

## Configuration
- Panel: `data/raw/state_month_panel_with_treatment.csv`
- Excluded states: ME
- Date range: 2021-08-01 to 2024-12-31
- Dropped window: <none> to <none>
- Coverage threshold: 41
- Balance common months: TRUE
- Outcome: log1p_filings_count
- Control group: notyettreated, est_method: reg
- Allow unbalanced panel: TRUE
- Pre-window: -12 to -1
- Alpha: 0.05

## Panel Summary
- 27 states (15 treated, 12 never-treated)
- 14 treatment cohorts
- 41 months, 1107 observations

## Headline CS Inference Method
**ANALYTIC**

## TWFE / Sun-Abraham Pretrends
- Joint test (Holm): min_p = 0, reject = TRUE

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

