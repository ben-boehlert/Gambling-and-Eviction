# Pre-trends Diagnostics: Mortgage Delinquency

Generated: 2026-02-13 01:43:54.841467

## Research Question
Does online sports gambling legalization affect mortgage delinquency rates?
Outcome: % of mortgages 90+ days delinquent (delinq_pct)
Treatment: online_start_date (online sports gambling legalization)

## Configuration
- Mortgage data: `data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv`
- Treatment file: `data/raw/sports_gambling_legalization_dates.csv`
- Treatment column: online_start_date
- Excluded states: <none>
- Date range: 2016-01-01 to 2024-12-31
- Dropped window: 2020-03-01 to 2021-07-31
- Coverage threshold: 91
- Balance common months: TRUE
- Outcome: delinq_pct
- Control group: notyettreated, est_method: reg
- Allow unbalanced panel: TRUE
- Pre-window: -12 to -1
- Alpha: 0.05

## Panel Summary
- 51 states (24 treated, 27 never-treated)
- 18 treatment cohorts
- 91 months, 4641 observations

## CS-DiD Pretrends (Analytic)
- Pre-periods tested: 12
- Joint test (Holm): min_p = 1, reject = FALSE
- Overall ATT: 0.0298 (SE = 0.0429)

## CS-DiD Pretrends (Bootstrap)
- Pre-periods tested: 12
- Joint test (Holm): min_p = 1, reject = FALSE
- Overall ATT: 0.0298 (SE = 0.0489)
- Bootstrap iterations: 199

## TWFE / Sun-Abraham Pretrends
- Joint Wald F = 34451923784.811, p = 0, reject = TRUE

## Inference Notes
- CS p-values: pointwise t-test with df = n_states - 1, Holm step-down for joint test
- SunAb p-values: cluster-robust SEs (state level), Wald F-test for joint pre-trend

## How to Run
```bash
# Default (excludes COVID period)
bash scripts/run_pretrends_mortgage.sh

# Include COVID period
NO_COVID=FALSE bash scripts/run_pretrends_mortgage.sh

# Use retail legalization dates instead of online
TREAT_DATE_COL=retail_start_date bash scripts/run_pretrends_mortgage.sh
```

