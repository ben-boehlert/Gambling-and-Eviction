# Power-Simulation Code Audit (Blinded)

**Date:** 2026-07-23
**Purpose:** Phase-1 audit for the blinded, pre-analysis-plan power-simulation framework.
**Blindness:** This audit was conducted without opening `output/`, `figures/`, HANDOFF documents,
generated result files, or result sections of project guides. Where scripts print real-data
estimates as "sanity checks," the values were not recorded. No actual estimated gambling→eviction
treatment effect appears in this document. See `POWER_SIMULATION_BLINDNESS_PROTOCOL.md` for the
full protocol, including a disclosure about orchestrator context exposure.

---

## 1. Executive summary

The repo contains substantial, partially reusable power-simulation infrastructure, but it is
fragmented across ~15 scripts with **two incompatible DGP philosophies**, **three inconsistent
effect-injection scales**, **two different COVID drop windows**, **one high-severity mislabeling**
(two "CS-DiD power simulation" scripts that actually estimate TWFE), and **no automated tests**.
The local "patched" `did`/`DRDID` package copies are not actually installed or loaded by the
active pipeline. No existing simulation uses an anticipation buffer. Existing simulations do
**not** leak treated outcomes into their baselines (verified; see §5), but none of them was built
under an explicit blindness protocol, and several sit in files that also print real-data
estimates.

Verdict: **consolidate, don't replace.** The best pieces (the residual-pool DGP, the genuine CS
one-sim from the mortgage script, the TWFE engine, the treatment-schedule loader, the Type-S/M
metric block, the self-test calibration pattern) should be factored into a modular `R/power/`
framework; the mislabeled and broken scripts should be deprecated in place.

---

## 2. The two existing DGP families

**Family P — placebo-shift on real untreated outcomes.**
`power_simulation_cs.R` (root, 1,358 lines) and `analysis/main/cs_state_count_sweep.R`.
Keeps actual untreated outcome values, draws placebo adoption dates shifted into the untreated
window, imposes an effect, re-estimates. Preserves real serial correlation and variance because
it never resamples residuals.

**Family R — residual-resampling on the real treatment schedule.**
`analysis/main/power_simulation_twfe_statepanel_staggered_parallel_fixed.R`,
`power_simulation_mortgage_delinquency.R`, the three `did2s_power_*.R` scripts, and the two
`power_simulation_cs_reg_*` scripts. Fits unit+time FE on untreated observations only, predicts
`yhat` for all observations, adds month-stratified resampled residuals plus a deterministic
effect on the **real** cohort schedule, re-estimates.

These are not interchangeable: Family P preserves real autocorrelation but randomizes the cohort
structure (matching only the treatment *rate*, not per-cohort counts — `power_simulation_cs.R:786-792`);
Family R preserves the exact cohort structure but, under its default `iid_month` error mode,
destroys within-state autocorrelation (an AR(1) mode exists but is not the default). The new
framework should support both as distinct pseudo-schedule/DGP options and make the tradeoff
explicit.

---

## 3. File-by-file status

### Canonical / reusable

| File | Role | Status |
|---|---|---|
| `power_simulation_cs.R` (root) | Family-P library: `cfg`, `load_panel()`, `build_untreated_sample()`, `draw_placebo_schedule()`, `impose_effect()`, `att_gt_safe()` wrapper, Type-S/M metrics, `compute_mde()` | Active library (`POWER_SIM_LIBRARY_MODE` guard at line 1257). Reuse utilities; rewrite `draw_placebo_schedule()` |
| `analysis/main/power_simulation_twfe_statepanel_staggered_parallel_fixed.R` | Family-R TWFE power sim | Canonical TWFE engine. Cleanest harness in repo (batching, checkpoints, null Type-I diagnostic at lines 783–808) |
| `analysis/main/power_simulation_mortgage_delinquency.R` | Family-R dual TWFE + genuine CS | The reference genuine-CS one-sim (`att_gt` call at lines 532–575) |
| `analysis/main/did2s_power_augmentation.R` | Family-R did2s + synthetic-cluster augmentation | `augment_panel()` (lines 165–208) is the repo's only add-clusters design; reuse |
| `analysis/main/did2s_power_panel_specs.R`, `did2s_power_cleaned_and_annual.R` | Family-R did2s spec sweeps | Active; duplicate the same `one_sim` block — consolidate |
| `analysis/main/cs_state_count_sweep.R` | Family-P CS sweep over coverage thresholds | Active; inherits Family-P DGP; threshold/cluster-count utilities reusable |
| `analysis/diagnostics/cs_calibration_multi_estimator.R` / `_county.R` / `_mortgage.R` | Null-DGP multi-estimator calibration | Active, the definitive size tests. County version clusters at `state_abb` correctly (L23–25) |
| `analysis/diagnostics/cs_calibration_unified.R` | Env-var-driven CS calibration harness | Active ("source of truth" per header); has the best AR(1) residual model (L124–165, 355–423), dynamic `true_effect_fn` (L92–122), multi-estimand extractor (L167–187) |
| `analysis/diagnostics/validate_csdid_dynamic_sim.R` | Dynamic-effect recovery + Type-I validation | Active template; per-event-time bias vs known truth (L549–564) |
| `analysis/diagnostics/power_sim_shared.R` + `power_sim_{all_county,border_county,border_state_agg,state_baseline}.R` | Shared TWFE power engine + 4 panel callers | Cleanest modular pattern already in the repo (`prep_pool` / `one_sim_twfe` / `run_power_grid`) |
| `utils/eviction_treatment_schedule.R` | Treatment-schedule loader + name↔abb crosswalk | Keep verbatim; already shared by pretrends and calibration scripts |
| `patches/att_gt_safe.R`, `preflight_support_check.R`, `reg_did_rc_safe.R` | Safe wrappers around `did`/DRDID | Real runtime helpers, but only wired into `scripts/prepare_and_run_csdid.R` / `run_csdid_pretrends.R` — **not** used by the calibration/pretrends pipeline (see F4) |

### Deprecated / broken (recommend deprecation, do not delete)

| File | Problem |
|---|---|
| `analysis/main/power_simulation_cs_reg_statepanel_staggered_parallel_REVISED.R` | **Mislabeled: estimates TWFE, not CS** (lines 636–641: `fixest::feols(y ~ post_treat \| id + t)`). All `did_*` config options are dead code. A comment at 609–613 documents the silent estimator swap |
| `analysis/main/power_simulation_cs_statepanel_staggered_parallel_merged.R` | Same TWFE-in-CS-clothing (lines 616–621); header self-flags "WORK IN PROGRESS — NOT RECOMMENDED" |
| `analysis/main/power_simulation_cs_INSTRUMENTED.R` | Errors at line 157 (undefined `%R%` operator); `source()`s `_merged.R` at line 10, which executes a full 2000-sim run as a side effect |
| `analysis/main/power_simulation_cs_reg_statepanel_staggered_parallel.R` | Genuine CS (`att_gt` at 477–493) but header says superseded by REVISED — which then silently dropped CS. If a state-panel CS sim is resurrected, start here, not from REVISED |
| `analysis/diagnostics/cs_calibration_test.R` | Superseded by multi-estimator versions; line 61 comment falsely claims its COVID window matches the pretrends runner (see F3) |
| ~25 `debug_*` / `diagnose_*` / `test_*` scripts in `analysis/diagnostics/` | One-off forensics from the CS SE-inflation investigation; candidates for `analysis/diagnostics/deprecated/` |
| `scripts/run_mortgage_pretrends_full.sh`, `run_pretrends_della.sh`, threshold-sweep runners | Invoke stale paths (e.g. `analysis/create_*` instead of `analysis/data_prep/create_*`; `backup_cleanup_20260112_094739/...` data paths) |

---

## 4. Findings

**F1 — Mislabeled CS power simulations (high severity).**
`power_simulation_cs_reg_..._REVISED.R` and `..._merged.R` carry full CS configuration surfaces,
`library(did)`, and `cs_*` output-directory names, but their `one_sim` estimates plain TWFE via
`fixest::feols` (REVISED:636–641; merged:616–621). Any consumer trusting filenames would
attribute TWFE operating characteristics to CS-DiD. The genuinely-CS ancestor
(`..._parallel.R:477–493`) is marked superseded by the file that dropped CS.

**F2 — The "bootstrap" arm is a t-test on a bootstrap SE, not bootstrap inference.**
Everywhere `bstrap=TRUE, biters=199` appears (`cs_calibration_test.R:268–270`, the pretrends
self-test, `cs_calibration_unified.R:549`), the decision rule is `2*pt(-|att/se|, df)` using the
bootstrap SE — the multiplier bootstrap's own critical values/p-values are discarded. Internally
consistent, but it should not be described as bootstrap inference, and the new framework should
implement (and label) both options distinctly.

**F3 — COVID drop windows disagree between the calibration tests and the recommended pipeline.**
Recommended pipeline (`scripts/run_pretrends_statepanel.sh:11–20`) drops 2020-03-01→**2021-07-31**;
`cs_calibration_test.R:61` and both `cs_calibration_multi_estimator*.R` (L64–68) drop
2020-03-01→**2022-03-31**; `cs_calibration_unified.R:199` and `validate_csdid_dynamic_sim.R`
default to 2021-07-31. The definitive calibration numbers were therefore computed on an
8-months-shorter sample than the headline pipeline. Root cause: per-script hardcoding — the
new framework must take this from a single shared config.

**F4 — The "patched" local packages are not installed or loaded.**
`library(did)` resolves to stock CRAN did 2.3.0. The `.patch` files in `patches/` are diffs
against an *old project harness script*, not the `did` package (their headers target
`analysis/power_simulation_cs_reg_statepanel_staggered_parallel_REVISED.R`). The p-value fix
("never trust `agg$overall.pval`; compute `2*pt(-|att/se|, df=n_clusters-1)`") is live only
because every current script reimplements it inline. The safe wrappers (`att_gt_safe.R`,
`reg_did_rc_safe.R`) are needed only if `est_method` ∈ {"dr","ipw"}; the active pipeline uses
`est_method="reg"`, which never enters the DRDID/fastglm path. Note `att_gt_safe.R` defaults to
`est_method="dr"` — adopting it without overriding would silently change the estimator.

**F5 — Effect-injection scales are inconsistent across scripts.**
`power_simulation_cs.R:840–860` injects **additively on the raw outcome scale**
(`effect_grid` 0–3 in per-1k-renter units); the TWFE and mortgage-log scripts use `log(1+pct)`;
the did2s scripts add raw log points (`0.05` instead of `log(1.05)`); the mortgage-levels branch
adds percentage points. Results are not comparable across scripts without a conversion layer.
The new framework needs one injection module with an explicit scale argument.

**F6 — No anticipation handling anywhere.**
No script excludes a pre-treatment buffer from its untreated baseline
(`build_untreated_sample()` keeps the month before `g`: `power_simulation_cs.R:671`), and no
`att_gt` call passes `anticipation=`. If anticipation effects exist, they contaminate both the
calibration baselines and the estimators' identifying assumptions untested.

**F7 — CS specification drift between the two genuine implementations.**
`power_simulation_cs.R` uses `est_method="ipw"` (line 902, chosen to dodge a fastglm segfault)
with `base_period` default `"varying"`; the mortgage script uses `est_method="reg"` with
`base_period="universal"` and does not pass `clustervars`; the pretrends template
(`pretrends_statepanel_template.R:624–723`) uses `est_method="reg"`, default `"varying"`,
`clustervars="id"`, `cband=TRUE`. The simulation must match the intended analysis spec exactly —
today no single simulation does.

**F8 — Degrees-of-freedom inconsistency.**
State-level scripts use `df = n_states − 1`; the county calibration script uses
`df = n_treated_states − 1` (`cs_calibration_multi_estimator_county.R:324,342,364`). Standardize
(convention: number of clusters − 1).

**F9 — Serial correlation is destroyed by the default error mode.**
Family-R scripts default to `ERR_MODE="iid_month"`; the AR(1)-state mode exists
(`cs_calibration_unified.R:124–165`) but is opt-in. Burlig–Preonas–Woerman-style logic implies
iid resampling can materially overstate power/understate Type-I error in long panels. The new
framework should treat error structure as a first-class scenario dimension, defaulting to the
autocorrelation-preserving options.

**F10 — No automated tests.**
No `tests/` or testthat suite exists for analysis code (checked repo-wide). The only structured
regression test is `patches/test_att_gt_safe_regression.R`. `INSTALL_PACKAGES.R` omits `did`,
`did2s`, `didimputation`, `DRDID`, `fastglm` — a reproducibility gap.

**F11 — Output hygiene.**
`power_simulation_cs.R`'s run block writes results CSVs and a PNG into `cfg$data_dir`
(= `data/raw/`), mixing outputs into the raw-data directory.

**F12 — Data constraints that shape the simulation design** (from the blinded data audit):
- Universally untreated window: **2016-01 through 2018-05** (first launch: Delaware retail
  2018-06; first online: NJ/WV 2018-08) — 28–29 monthly periods.
- County panel (`monthly_county_data_download.csv`): 120,357 rows, 32 states + PR/USVI
  territories (80 FIPS, 3,822 rows — should be excluded), 1,384 counties, 2016-01→2025-09.
  **Strongly unbalanced**: only 12% of counties span the full window; per-month county counts
  range 565–1,202.
- Counts are integer, near-zero zero-share pre-2018-05 (0.22%), moderately overdispersed
  (median within-county var/mean ≈ 1.43) → negative-binomial/quasi-Poisson calibration, no
  zero-inflation needed.
- State panel: 39 states, 24 with treatment dates, 15 never-treated.
- Pre-own-treatment coverage in the county panel varies from 6 months (NY) to 84 (OH) —
  risk-set pseudo-designs must respect per-state support.
- Cohorts by `online_start_date`: 18 cohorts, max size 2 (mostly singletons). By
  `first_start_date`: 21 cohorts, largest size 4. Pseudo-schedules must preserve this
  singleton-heavy structure, not a common-date design.
- The 7 "expansion" states: only MI has real pre-treatment coverage (annual 2006+); MD, OR, NH,
  IL source files in-repo are post-treatment-only; NJ/IA have no processed flat file. The
  expansion panel is therefore **not usable for calibration** of those states' pre-periods.
- Handle/revenue intensity data exists only post-legalization by construction (34 states,
  earliest April 2019).

**F13 — Two divergent panel merge targets.**
`data_prep/monthly_panel_expansion/05_merge_expanded_panel.R` writes
`data/processed/state_month_panel_expanded.csv`, but scripts 06/07 (NH repair, MD merge) edit
`data/raw/state_month_panel_with_treatment.csv` directly. The canonical panel path must be
pinned in config.

---

## 5. Blindness assessment of existing simulations

- **Family P:** `build_untreated_sample()` keeps `(!ever_treated) | (t < g)`
  (`power_simulation_cs.R:671`) — treated post-period outcomes are correctly excluded from the
  baseline. No anticipation buffer (F6).
- **Family R:** unit/time FEs are fit on untreated observations only (e.g.
  `power_simulation_twfe_...fixed.R:382–419`); residual pools draw from untreated rows.
  Simulated outcomes are `yhat + resampled residual (+ imposed effect)` — real treated outcomes
  do not enter. The real *schedule* (treatment dates) is used, which is permitted design
  information.
- **However:** several simulation scripts also print real-data ATT "sanity check" lines, and no
  script has an automated guard preventing treated outcomes from entering a calibration sample.
  The new framework adds these guards (`R/power/blindness_checks.R`) and a dedicated blinded
  loader; see `POWER_SIMULATION_BLINDNESS_PROTOCOL.md`.

---

## 6. Consolidation plan (what the new framework reuses)

Lift with attribution into `R/power/`:

1. `utils/eviction_treatment_schedule.R` — used as-is (sourced, not copied).
2. Residual-pool DGP (FE on untreated → `yhat` → month-stratified resample), consolidating the
   four near-identical copies; AR(1) variant from `cs_calibration_unified.R:124–165`.
3. Genuine CS one-sim structure from `power_simulation_mortgage_delinquency.R:532–575`, with
   the spec surface aligned to `pretrends_statepanel_template.R:624–723`.
4. TWFE engine and batching/progress/null-diagnostic harness from
   `power_simulation_twfe_statepanel_staggered_parallel_fixed.R`.
5. `augment_panel()` synthetic-cluster generator from `did2s_power_augmentation.R:165–208`
   (as a clearly-labeled sensitivity, per the design doc).
6. `true_effect_fn` dynamic-effect shapes and `extract_agg_target` estimand extractor from
   `cs_calibration_unified.R`.
7. Type-S/Type-M/exaggeration metrics and `compute_mde()` from `power_simulation_cs.R:1034–1046,
   1214–1219`.
8. The self-test decision-rule pattern (null sims through the identical estimator call, gate on
   measured Type-I) from `pretrends_statepanel_template.R:363–616` — promoted to a first-class
   pipeline stage.
9. `prep_pool`/`run_power_grid` modular pattern from `power_sim_shared.R`.

Rewritten from scratch: pseudo-schedule assignment (cohort-preserving, shifted-actual,
risk-set, never-treated-placebo — none exists today in the required form), count-based
stochastic effect injection (nothing count-based exists today), operating-characteristics
summarizer (coverage, CI width, sign/magnitude errors per spec), blindness layer, config-file
driven scenario grid, tests.

---

## 7. Recommended deprecations (recommendation only — nothing deleted)

Move to `analysis/main/deprecated/` (or annotate headers): the two mislabeled CS scripts (F1),
`power_simulation_cs_INSTRUMENTED.R`, and `cs_calibration_test.R`. Move the ~25 forensic
`debug_*`/`diagnose_*`/`test_*` diagnostics to `analysis/diagnostics/deprecated/`. Fix or retire
the stale shell runners (§3). These are recommendations for Ben to approve; this project's
convention is deprecate-don't-delete.
