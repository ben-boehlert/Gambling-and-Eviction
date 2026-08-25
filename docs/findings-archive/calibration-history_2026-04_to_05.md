> Archived verbatim from CLAUDE.md on 2026-08-25 (repo cleanup). Historical record — numbers here may be superseded; current truth lives in FINDINGS.md, statuses in RUN_LEDGER.md.

### Heterogeneity-Robust Estimator Calibration (2026-04-09, SUPERSEDED 2026-05-21)

**Original state-panel calibration** (kept for chronology). Tested via `analysis/diagnostics/cs_calibration_multi_estimator.R` on the balanced 24-state panel (100 null simulations, effect=0, alpha=0.05):

| Estimator | Type | Rejection (target 5%) | SE/SD (target 1.0) | Noise vs TWFE |
|-----------|------|----------------------|---------------------|---------------|
| **TWFE** (fixest) | Pooled | 1% | 1.14 | 1x |
| **Sun-Abraham** (fixest) | Het.-robust | **21%** | **0.58** | **4x** |
| **CS Analytic** (did) | Het.-robust | **14%** | **0.67** | **5.1x** |
| didimputation (BJS) | Het.-robust | failed | — | — |
| did2s (Gardner) | Het.-robust | failed | — | — |

### Heterogeneity-Robust Estimator Calibration at COUNTY LEVEL (2026-05-21, NEW HEADLINE)

Ported the same calibration test to the all-county panel via `analysis/diagnostics/cs_calibration_multi_estimator_county.R`. 50 null simulations.

| Estimator | State-panel rej / SE-SD / noise | County-panel rej / SE-SD / noise | Status |
|-----------|---------------------------------|----------------------------------|--------|
| TWFE | 1% / 1.14 / 1× | **8% / 0.95 / 1×** | OK; wild bootstrap recommended for inference |
| Sun-Abraham | 21% / 0.58 / 4× | 30% / 0.51 / 4.5× | Still broken — skip |
| CS Analytic | 14% / 0.67 / 5.1× | 0% / 2.46 / 3.4× | Over-corrects — skip |
| didimputation (BJS) | failed | **14% / 0.73 / 1.1×** | Rescued; usable as robustness |
| **did2s (Gardner)** | **failed** | **4% / 0.97 / 1.1×** | **Rescued — NEW HEADLINE ESTIMATOR** |

**Key conclusions (updated):**
1. **County-level data rescues the modern imputation estimators.** did2s and didimputation, which failed entirely on the state panel, now run cleanly. did2s is well-calibrated and as efficient as TWFE.
2. **CS-DiD and Sun-Abraham remain broken even on county data.** The cohort heterogeneity problem isn't fixed by within-cohort disaggregation.
3. **TWFE at county level has Type I ≈ 7-8%** — mildly anti-conservative, within MC noise of nominal 5% but consistent enough to require wild cluster bootstrap for valid inference.
4. **Real-data SE is ~10× larger than null-DGP simulated SE.** The 2% MDE from the bootstrap simulation assumes homogeneous treatment effects. Real-data cohort heterogeneity widens the pooled SE substantially, putting the realistic MDE in the 8–10% range.

**Panel used for calibration** (matches pretrends pipeline exactly):
- Source: `state_month_panel_with_treatment.csv` + `sports_gambling_legalization_dates.csv`
- COVID drop: 2020-03-01 to 2022-03-31
- Exclude: ME
- Coverage threshold: auto (83 months) + BALANCE_COMMON_MONTHS=TRUE
- Result: 24 states (11 treated, 13 never-treated), 83 months, 1992 obs, perfectly balanced

**Cohort structure** (why het.-robust estimators struggle):
- 11 treated states, each with a unique online legalization date → 11 singleton cohorts
- No cohort has more than 1 state
- Compare to Hollenbeck et al. (2025): same treatment timing but 51 state clusters (24 treated), ~2x our design

### Previous CS threshold-sweep behavior (legacy, superseded by calibration test)

- Script: `analysis/diagnostics/cs_power_threshold_sweep_nocovid_small.R` (invoked by `scripts/run_cs_power_threshold_sweep_no_maine_2024_min5.sh`)
- For each threshold, the code estimates CS once per simulation at `effect=0` (`one_cs0`), storing `att0` and `se0`.
- For nonzero effects, it does **not** re-estimate `att_gt()`; it shifts the estimate as `att = att0 + log1p(effect_pct)` and keeps `se = se0`.
- P-values are then recomputed from the shifted t-statistic using `2 * pt(-abs(att/se), df = n_states - 1)`.
- Implication: within a threshold, `sd_att`, `mean_se`, and `se_over_sdatt` are expected to be nearly identical across effect sizes; only `mean_att` and rejection rates (power) should change.

