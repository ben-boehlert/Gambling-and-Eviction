# Post-COVID Maturation-Treatment Power (BJS + did2s) Plan

**Status:** APPROVED (user request 2026-08-19: "power using only markets that
matured post-COVID; look at BJS, did2s — global parallel trends may be more
tolerable there")
**Baseline it extends (2026-08-17):** post-COVID window (covid: post,
2021-08..2025-11) with LEGALIZATION dates — size: twfe 2.0%, did2s 7.3% (its
spliced-window failure was a COVID-splice artifact), lpdid 6.0%; MDE-80
(size-adj): twfe 24.5%, did2s 33.2%, lpdid 37.6% on 7 treated / 10 control.

## What's new here

1. **Treatment at market MATURATION, not legal launch:** the handle50 date
   (first month state handle reaches 50% of its peak month;
   `data/processed/activity_treatment_dates.csv` col `treat_start`,
   infrastructure documented in docs/methodology/ACTIVITY_BASED_TREATMENT.md).
   Blindness stays anchored at `first_start_date` (first legal betting of any
   kind) — earlier than maturation, so the blinded panel is strictly
   conservative. Handle dates are design information (never merged to eviction
   outcomes), allowed under BLINDNESS_PROTOCOL §2 (same as ramp75 precedent).
2. **BJS (didimputation, Borusyak–Jaravel–Spiess) added to the framework's
   estimator registry** (`bjs` in R/power/run_estimators.R), alongside did2s —
   both imputation-family estimators whose "global parallel trends over the
   estimation window" assumption is most defensible on the clean post-COVID
   window (no structural break inside).

## Files

- Create `analysis/data_prep/make_maturation50_schedule.R` →
  `data/processed/maturation50_schedule.csv` with columns: state (full name),
  first_start_date (from data/raw/sports_gambling_legalization_dates.csv),
  online_start_date (reference), maturation50_start_date (activity treat_start).
- Modify `R/power/load_blinded_panel.R`: add "maturation50_start_date" to the
  treat_def whitelist (cutoffs unchanged — always first_start_date).
- Modify `R/power/run_estimators.R`: add estimator "bjs" via
  didimputation::did_imputation (yname y_sim-analysis outcome, gname pseudo-g,
  cluster state), analytic arm, p from t(df = treated clusters − 1) matching
  the did2s convention; failures logged never thrown.
- Tests: extend tests/testthat/test-estimators.R (bjs recovers a known effect
  on the toy panel; contract columns; error capture).
- Create `config/power_postcovid_maturation.yml`: state / S2 / covid: post /
  D1 / template panel / count_nb / step / y_log1p; schedule →
  data/processed/maturation50_schedule.csv; TWO scenario blocks:
  treat_def maturation50_start_date vs online_start_date (same seeds/window →
  paired comparison); estimators [twfe, did2s, bjs, lpdid]; effect_grid
  [0,.02,.05,.08,.10,.15,.20,.25,.30,.40,.50,.60]; n_reps 300;
  base_seed 20260723; alpha [0.10, 0.05, 0.01]; mde_boot 200.
- Run via run_scenario_grid (brute force; state-level, cheap; full curves for
  all arms). Output: output_blinded_power/postcovid_maturation/.

## Decision rules (prespecified, same as framework §14 size criterion)

- Size gate per estimator×arm: δ=0 rejection at α=.05 in [2.5%, 10%] AND
  failure rate ≤5%; MDEs reported only for gate-passing arms (others shown,
  flagged disqualified).
- Report raw MDE-80 with bootstrap CI; note achieved treated/control counts
  per treat_def (maturation shifts dates later → different cohort feasibility).
- Single-cell scope caveat (one sample, one mechanism) as in the CS report.
