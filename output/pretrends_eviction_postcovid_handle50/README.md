# Pre-trends Diagnostics Output

Generated: 2026-02-13 13:07:18.616038

## Configuration
- Panel: `data/processed/state_month_panel_handle50_treatment.csv`
- Excluded states: ME
- Date range: 2022-04-01 to 2024-12-31
- Dropped window: <none> to <none>
- Coverage threshold: 33
- Balance common months: TRUE
- Outcome: log1p_filings_count
- Control group: notyettreated, est_method: reg
- Allow unbalanced panel: TRUE
- Pre-window: -12 to -1
- Alpha: 0.05

## Panel Summary
- 27 states (16 treated, 11 never-treated)
- 12 treatment cohorts
- 33 months, 891 observations

## Headline CS Inference Method
**ANALYTIC**

## CS-DiD Pretrends (Analytic)
- Pre-periods tested: 12
- Joint test (Holm): min_p = 5e-04, reject = TRUE
- Overall ATT: 0.1477 (SE = 0.1246)

## CS-DiD Pretrends (Bootstrap)
- Pre-periods tested: 12
- Joint test (Holm): min_p = 7e-04, reject = TRUE
- Overall ATT: 0.1477 (SE = 0.1378)
- Bootstrap iterations: 199

## TWFE / Sun-Abraham Pretrends
- Joint test (Holm): min_p = 0.026, reject = TRUE

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

