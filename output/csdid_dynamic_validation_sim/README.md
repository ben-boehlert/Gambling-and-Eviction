# CS-DiD Dynamic Validation (Simulation)

This folder is produced by:

- `analysis/diagnostics/validate_csdid_dynamic_sim.R`

Purpose:

- Validate (before using observed outcomes) that the CS workflow can recover a **known dynamic treatment effect** pattern and that **SEs are roughly calibrated** (Type I error near `alpha`) under a null.

Key outputs:

- `summary_overall.csv`: overall pass/fail counts and null-size diagnostics for a target event time.
- `summary_by_event_time.csv`: average estimated event-study (`att.egt`) vs the known simulated truth.
- `raw_target_h.csv`: per-simulation estimates/SEs/rejections for the target event time.

Notes:

- This uses your real adoption timing (state-month + `treat_start`) but simulates outcomes from a known DGP, so it does not estimate treatment effects on the observed outcome series.
- `ERR_MODE` now supports:
  - `iid` and `ar1_state` (Gaussian synthetic errors)
  - `resid_pool_iid_month` and `resid_pool_ar1_state` (errors drawn from untreated residual pools)
- For the "nearly-real DGP" check, use:
  - `ERR_MODE=resid_pool_ar1_state`
  - optional: `OUTCOME=log1p_filings_count` or `OUTCOME=log1p_rate`
  - optional: `RESID_POOL_MIN_STATES=5` (fallback threshold for month-specific pools)
