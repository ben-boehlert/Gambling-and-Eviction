# Plan: Cheap Staged Simulation Framework (Sims 0–4)

**Status:** APPROVED (user provided full spec; autonomous session)
**Date:** 2026-08-12
**Spec:** user message of 2026-08-12 (staged cheap power/size simulation for the C&S design)

## Goal

Cheaply determine (1) test size under a true zero effect, (2) power under plausible
gambling-ramp effects, (3) whether identification comes from COVID-crossing vs clean
comparisons, before investing in an expensive simulation suite.

## Key design decisions (from repo audit)

- **Reuse `R/power/` modules** (load_blinded_panel, impose_effects, run_estimators,
  make_pseudo_schedules internals). The user's Black-et-al-style design (perturb real
  *untreated* data) coincides with the blindness protocol.
- **Panel:** state-month, `y_log1p`, panel floor 2016-01, S2-style anticipation
  censoring (6 mo before `first_start_date`), COVID window **2020-03-01..2021-07-31
  dropped** (framework protocol default; env-configurable). **ME included** (repaired
  2026-07-23; now treated Nov 2023). **NV hard-excluded** — absent from schedule CSV,
  would otherwise be silently miscoded never-treated.
- **Treatment:** `online_start_date` from repaired
  `data/raw/sports_gambling_legalization_dates.csv`. Never the stale panel `treat_start`.
- **Placebo:** NEW calendar-preserving generator — real online cohort dates of panel
  states kept FIXED on the calendar (no D1 anchor shift, which would break COVID
  alignment); eligible untreated states assigned scarcest-cohort-first without
  replacement; unfillable cohorts dropped and recorded (expected: late 2022–24 cohorts
  compete for ~9 never-treated hosts).
- **Estimator:** did::att_gt, control_group=notyettreated, est_method=reg,
  base_period=varying, anticipation=0, faster_mode=FALSE (TRUE errors on this design),
  cluster=state(=id). Analytic IF inference, t(n_states-1). One fit per rep×DGP.
- **COVID decomposition from ONE fit:** classify each post ATT(g,t) cell by its
  comparison window (base month g-1 vs t): clean-pre / clean-post / cross-COVID.
  Aggregate subsets with cohort-size weights and influence-function SEs. Designs:
  full / covid_clean(pre+post) / pre_covid / post_covid / cross_covid. This yields
  Sims 1A/1B/1C AND 3A–3D from the same fits (cells are numerically identical to
  sample-restricted fits under varying base period + notyettreated).
- **Ramp DGP (Sim 2):** exposure_s(e) = Handle/peak-handle-excl-COVID (settled
  quintile-timing definition), capped at 1, event time from online date, actual monthly
  values (keeps seasonality). Pseudo-states get seeded donor profiles from the ~30 real
  online states; tails extended at donor trailing-6-month mean. Population cancels in
  the normalization (no per-capita data needed for the ramp itself).
  Injection: count_nb (theta=1.4) with delta_ist = delta_mature × exposure(e − lag).
- **Grid:** ramp lag0 δ∈{0,.01,.025,.05}; ramp lag6 δ∈{.01,.025,.05}; step lag0
  δ∈{.01,.025,.05} (ramp-vs-step diagnostic). δ=0 is the shared null (pure
  pass-through of real data). Smoke 24 reps → 250 reps. Seeds:
  `base_seed 20260723 + 10007*rep + 101*scenario` (framework convention).
- **Sim 4:** REUSE existing 200-rep null CV3 result
  (`data/output/cs_cv3_calibration/state/`): analytic 21.5% rejection, CV3 0.5%
  (over-corrects), SE/SD 1.24. New work = estimand-integrity diagnostics only:
  per-LOSO-replicate ATT(g,t) cell disappearance / weight shifts (small add-on run)
  + real-data leave-one-state-out influence plot (unblinded, clearly marked).

## Files

- `analysis/cheap_sims/00_common.R` — shared functions (panel builder, ramps, placebo,
  cell classifier, subset aggregator, one_sim)
- `analysis/cheap_sims/01_stage0_audit.R` — design object + audit tables + ramp plots
- `analysis/cheap_sims/02_run_cheap_grid.R` — checkpointed MC driver (env: N_REPS, N_CORES)
- `analysis/cheap_sims/03_summarize.R` — cheap_power_sim_summary.csv, power curves,
  null-size table, MDE interpolation, runtime report
- `analysis/cheap_sims/04_jackknife_diag.R` — Sim 4 add-on diagnostics
- `analysis/cheap_sims/CHEAP_POWER_SIM_NOTES.md` — methodology notes
- Output → `output/cheap_power_sim/`

## Verification

- Stage 0 audit gates: NV absent; treated-without-post states (NC, MO) coded untreated;
  placebo attrition reported; IF-aggregation validated against aggte(simple) in smoke.
- Runtime: ~4.5 s/fit (measured, prior CV3 run) → ~10 fits/rep ≈ 45 s → 250 reps ≈ 3 h
  serial, ~25–35 min on 7 cores. **Local is sufficient; Della not needed for Sims 1–3.**
- Stop after decision memo; no second-stage suite.
