# Dose-Response IV Analysis: Gambling Handle on Evictions

**Generated**: 2026-02-16 18:31:11.445635

## Design

Continuous treatment: log(1 + handle per 1k renters), instrumented by binary legalization.
- Panel: 37 states (23 treated, 14 never-treated), 83 months, 2533 obs
- Date range: 2016-01-01 to 2024-12-01
- COVID gap: 2020-03-01 to 2022-03-31
- Outcome: log1p_filings_count
- States with handle data: 23

## Key Results

### Reduced form (binary TWFE)
- Coefficient: -0.0655 (SE = 0.13, p = 0.6172)

### First stage
- Coefficient: 8.4516 (SE = 1.2296)
- F-statistic: 2286

### IV/2SLS (main specification)
- Coefficient: -0.0078 (SE = 0.0154, p = 0.6174)
- 95% CI: [-0.0379, 0.0224]
- Interpretation: A 1-unit increase in log(1+handle_per_1k) is associated with a
  -0.0078 change in log(1+eviction_filings)

### Wald decomposition
- Wald ratio: -0.0078 (should equal IV coefficient)

## Files

| File | Description |
|------|-------------|
| `specifications_table.csv` | All specifications with coefficients, SEs, CIs |
| `first_stage_detail.csv` | First-stage diagnostics |
| `wald_decomposition.csv` | Reduced form / first stage decomposition |
| `event_study_reduced_form.csv` | Binary event study coefficients |
| `event_study_first_stage.csv` | Handle ramp-up by event time |
| `loo_sensitivity.csv` | Leave-one-out IV estimates |
| `subperiod_results.csv` | Post-COVID sub-period results |
| `run_log.txt` | Execution log |

