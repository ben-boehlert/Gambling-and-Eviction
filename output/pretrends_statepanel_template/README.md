# Pre-trends Diagnostics Output

Generated: 2026-02-13 01:57:32.411658

## Configuration
- Panel: `data/raw/state_month_panel_with_treatment.csv`
- Excluded states: ME
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
- 24 states (14 treated, 10 never-treated)
- 13 treatment cohorts
- 91 months, 2184 observations

## Headline CS Inference Method
**ANALYTIC**

## CS-DiD Pretrends (Analytic)
- Pre-periods tested: 12
- Joint test (Holm): min_p = 1, reject = FALSE
- Overall ATT: -0.225 (SE = 0.1466)

## CS-DiD Pretrends (Bootstrap)
- Pre-periods tested: 12
- Joint test (Holm): min_p = 1, reject = FALSE
- Overall ATT: -0.225 (SE = 0.146)
- Bootstrap iterations: 199

## TWFE / Sun-Abraham Pretrends
- Joint Wald F = 6639730695.609, p = 0, reject = TRUE

## Inference Notes
- CS p-values: pointwise t-test with df = n_states - 1, Holm step-down for joint test
- SunAb p-values: cluster-robust SEs (state level), Wald F-test for joint pre-trend
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

