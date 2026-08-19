# CS Calibration under Time Aggregation × COVID Handling

**Date:** 2026-08-19 (state panel). **Status:** 6 of 13 scenarios complete;
run in progress — see "Resuming" below.
**Question (user, 2026-08-19):** what do CS calibration and power look like
using quarter- or year-of-legalization instead of month, examined across
several ways of handling the COVID break?
**Run:** `output_blinded_power/time_agg_covid_gates/` (config
`config/power_time_agg_covid_gates.yml`; state / S2 / D1 panel-template /
count_nb / step / y_log1p / notyettreated; δ = 0 only — this is the SIZE GATE;
300 reps; base_seed 20260723; `cs_safe_patches: true`, `cs_faster_mode: false`,
`lpdid_wild: true`).

---

## Bottom line (from the 6 completed scenarios)

**Coarser time aggregation does NOT fix CS calibration, and annual makes it
worse. The COVID splice — not the singleton-cohort structure — is what breaks
CS on this design: on the clean post-COVID monthly window CS passes the size
gate for the first time in this project (5.0% / 6.0% / 3.3%, SE/SD ≈ 1.06–1.14),
while every spliced-window cell fails at every aggregation.**

This is a **negative result for the mechanism CLAUDE.md hypothesises.**
Aggregation collapses singleton cohorts exactly as expected — 21 cohorts
(max 2 states) at month → 17 (max 3) at quarter → **7 cohorts (max 6 states)**
at year — and CS's size does not follow.

## 1. Cohort collapse and cost (measured, D1 panel template, rep 1)

| Aggregation | Periods | Treated | Cohorts | Max cohort | CS sec/cell |
|---|---|---|---|---|---|
| month (keep) | 119 | 23 | 21 | 2 | 27.7 |
| quarter (keep) | 39 | 23 | 17 | 3 | 3.4 |
| year (keep) | 9 | 21 | **7** | **6** | 0.2 |

Aggregation is an 8×–140× speedup for CS. That is real and reusable even
though it does not fix calibration.

## 2. Size gate, δ = 0, 300 reps (gate: reject@.05 ∈ [2.5%, 10%])

Spliced window (`covid: drop`, partial periods kept):

| Cell | Cohorts | CS analytic | CS boot | CS boot_t | SE/SD | Null bias |
|---|---|---|---|---|---|---|
| month_drop | 21 | 18.3% | 20.7% | 17.7% | 0.64–0.67 | +0.161 |
| quarter_drop | 17 | 16.7% | 18.7% | 14.7% | 0.66–0.69 | +0.081 |
| year_drop | 7 | **24.7%** | 28.0% | 21.3% | 0.73–0.76 | **−0.476** |

Post-COVID window (`covid: post`, no splice):

| Cell | CS analytic | CS boot | CS boot_t | SE/SD | Null bias |
|---|---|---|---|---|---|
| month_post | **5.0% PASS** | **6.0% PASS** | **3.3% PASS** | 1.06–1.14 | −0.204 |
| quarter_post | 0.7% fail (conserv.) | 3.7% PASS | 0.3% fail | 1.16–1.24 | −0.212 |
| year_post | 8.0% PASS | 14.7% fail | 7.7% PASS | 1.29–1.35 | −0.578 |

Reference arms on the same draws:

| Cell | twfe analytic | twfe wild | did2s | lpdid analytic | lpdid wild |
|---|---|---|---|---|---|
| month_drop | 2.0% | 0.7% | 27.3% FAIL | 6.3% PASS | 6.0% PASS |
| quarter_drop | 2.3% | 1.7% | 26.7% FAIL | **0/300 converged** | — |
| year_drop | 5.3% PASS | 7.3% PASS | 41.7% FAIL | **0/300 converged** | — |
| month_post | 3.7% PASS | 4.3% PASS | 6.0% PASS | 6.3% PASS | 4.3% PASS |
| quarter_post | 4.0% PASS | 6.0% PASS | 5.0% PASS | **0/300** | — |
| year_post | 0.7% | 7.0% PASS | 6.3% PASS | **0/300** | — |

## 3. Findings

1. **Aggregation does not calibrate CS.** Quarterly buys a marginal
   improvement on the spliced window (18.3% → 16.7% analytic); annual is
   *worse* (24.7%) despite having only 7 cohorts. Whatever drives CS's
   over-rejection here, it is not cohort singleton-ness alone.
2. **The COVID splice is the dominant factor.** Every spliced cell fails for
   CS *and* did2s (26–42%); every post-COVID monthly/quarterly cell passes or
   nearly passes for both. This corroborates and generalises the 2026-08-17
   finding that did2s's failure was a splice artifact — it is now shown to be
   a splice artifact for **CS** as well.
3. **Annual aggregation carries a large null bias** (−0.476 spliced, −0.578
   post) — consistent with the partial-period artifact: the loader filters
   COVID months *before* aggregating, so annual 2020 holds 2 months of filings
   and 2021 holds 5. The `complete_periods_only` scenarios (still running)
   isolate this.
4. **CS's null bias is large and negative on every post-COVID cell**
   (−0.20 to −0.58) even where size passes. Size-valid ≠ unbiased; any CS
   point estimate from a post-COVID design needs this reported alongside.
5. **LP-DiD is incompatible with coarse aggregation: 0 of 300 reps converged**
   at quarterly and annual, in every COVID window. Its lag construction runs
   on calendar months by design (`run_estimators.R` comment: lags "must run on
   calendar months so they cannot bridge a covid: drop gap"), so quarter/year
   period dates find no matching lags. Anyone speccing LP-DiD on quarterly
   data must fix this first. It is *not* a data problem — LP-DiD converges
   300/300 on monthly.
6. **TWFE remains the most robust arm** across the whole grid (0.7%–7.3%),
   as in every prior calibration in this project.

## 4. Structural infeasibility finding (no compute needed)

On the **spliced** window, `complete_periods_only = TRUE` makes coarse
aggregation **D1-infeasible**: probing 5 seeds per cell, quarterly placed 1/5
and annual 0/5, versus 5/5 with the rule off. Dropping partial periods
shortens per-state coverage below what the 55-month cohort template needs;
annual loses 5 states outright (38 → 33) and its span shrinks to
2016-01..2024-01. So on a spliced window you must choose between
a partial-period level artifact and an infeasible design — which is itself an
argument against combining coarse aggregation with the splice.

## 5. What is still running (7 of 13)

`month_keep`, `quarter_keep`, `year_keep`, and the four
`complete_periods_only` variants (`{quarter, year}` × `{post, keep}`). These
add the no-COVID-handling baseline and isolate the partial-period artifact.

## 6. Resuming after the laptop closes

The run is checkpointed **per 25-rep batch**; closing the lid suspends it and
at most one batch is lost. To resume (skips every completed scenario):

```bash
cd "/Users/bb1806/Documents/GitHub Doc/Gambling-and-Eviction" && Rscript -e 'source("R/power/config.R"); source("R/power/blindness_checks.R"); source("R/power/load_blinded_panel.R"); source("R/power/make_pseudo_schedules.R"); source("R/power/impose_effects.R"); source("R/power/run_estimators.R"); source("R/power/summarize_operating_characteristics.R"); source("R/power/run_scenario_grid.R"); run_scenario_grid("config/power_time_agg_covid_gates.yml", workers = 5, resume = TRUE)' > output_blinded_power/time_agg_covid_gates_run3.log 2>&1
```

Two furrr worker crashes occurred today (county CS run; this run at
`month_post` batch 9). Both resumed cleanly; concurrency was reduced 6 → 5.

## 7. Power (NOT yet run — deliberately)

No power/MDE numbers exist for this grid yet. Per the framework's decision
rule, power is only computed for arms that pass the size gate; the passing
cells are the post-COVID ones. Shift mode is **barred** for CS MDEs
(2026-08-18 review), so power must use `R/power/adaptive_mde.R` — cheap here,
since coarse CS cells cost 0.1–3.4 s.

## 8. Infrastructure added (committed, tested, full suite green)

- `time_agg` axis ("month"/"quarter"/"year") in `load_blinded_panel()` and the
  scenario grid, superseding the legacy boolean `quarterly`, which is kept in
  sync so **existing quarterly and monthly scenario ids do not move** (year is
  hashed conditionally). Tests: `test-loader.R`, `test-grid.R`.
- `complete_periods_only` rule: drops any unit-period not holding its full
  complement of months (3 / 12), applied **per unit-period** so a state whose
  coverage starts mid-quarter loses only its own partial period. Hashed only
  when TRUE. Attributes `time_agg`, `complete_periods_only`,
  `n_periods_dropped_incomplete` recorded on the panel.
- Commit `79498b1`.
