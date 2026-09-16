# Sun-Abraham / att_gt Encoding Bugs — Audit & Correction (2026-08-28)

**Trigger:** Ben asked for a code audit of the calibration sims ("these sims have
had a lot of coding errors"). The audit targeted
`analysis/diagnostics/cs_calibration_multi_estimator_county.R`, the script
behind the LIVE county estimator verdicts in FINDINGS §4, then swept the repo
for the same patterns.

Two silent sample-loss bugs were found and verified on synthetic known-truth
panels. Both drop **every never-treated unit** from estimation without any
visible error (the scripts suppress fixest notes and did warnings).

---

## Bug 1 — `sunab(first_treat, t)` with NA-coded never-treated cohorts

**Mechanism.** fixest removes observations with NA in any RHS variable.
`sunab()` does not special-case NA cohorts, so coding never-treated units as
`first_treat = NA` removes them from the regression entirely. The SA arm
therefore ran with **zero never-treated controls** — identification came only
from not-yet-treated cohorts, with heavy collinearity masking.

**Synthetic verification** (60 units, staggered, true ATT = 0.5):

| never-treated encoding | nobs kept | ATT | verdict |
|---|---|---|---|
| `NA` (county calib) | 1,200 / 2,400 | 0.044 | **wrong — half the panel dropped** |
| `0` (pretrends template) | 2,400 | 0.527 | correct |
| `Inf` (old test_sunab.R) | 2,400 | 0.527 | correct |
| `10000` (fixest docs) | 2,400 | 0.527 | correct |

**Real-data impact (county panel):** the NA encoding drops 30,024 of 91,384
obs (all 606 never-treated counties). Corrected encoding: nobs 60,446 →
90,465, SA SE 0.0513 → 0.0223 (ATT −0.019 → −0.019).

**Contaminated artifacts:**
- `output/border_diagnostic/cs_calibration_multi_county/` SA row — the LIVE
  FINDINGS §4 verdict "Sun-Abraham 30% size, SE/SD 0.51, broken — skip".
- `data/output/cs_calibration_multi/` SA row (state; 21%/0.58) — already
  SUPERSEDED, and also the "state-panel baseline" quoted in the county
  script's header.
- `output/cs_calibration_multi_mortgage/` SA row (status UNKNOWN/parked).
- `output/deprecated/permutation_placebo/` SA arm (already CONTAMINATED
  pre-rebuild).

**Fixed call sites** (all now `sunab(g, t)` with g = 0 for never-treated,
matching the pretrends template and `R/power/run_estimators.R .re_sunab`;
`first_treat` NA-encoding retained for didimputation only, which was verified
to handle NA/0/Inf identically):
`cs_calibration_multi_estimator_county.R`, `cs_calibration_multi_estimator.R`,
`cs_calibration_multi_estimator_mortgage.R`,
`permutation_placebo_real_data.R`.

## Bug 2 — integer `g` + `did::att_gt` under `faster_mode = TRUE`

**Mechanism.** `did/R/pre_process_did2.R:132` recodes never-treated `g == 0`
to `Inf` by in-place data.table assignment. In an INTEGER g column, Inf
truncates to NA (data.table warns, does not promote), and the "Dropped N
observations that had missing data" pass then removes **every never-treated
unit**. The classic path (`faster_mode = FALSE` → `pre_process_did.R`) keeps
g = 0 as its never-treated marker and is unaffected. The bundled patched `did`
defaults to `faster_mode = TRUE`, so any call site that omits the argument got
the dangerous path.

**Synthetic verification** (same panel, base data.frame input):

| faster_mode | g type | units kept | ATT (truth 0.5) |
|---|---|---|---|
| TRUE | integer | 30 / 60 | −0.034 |
| TRUE | numeric | 60 | 0.369 |
| FALSE | integer | 60 | 0.369 |
| FALSE | numeric | 60 | 0.369 |

**Exposure by script:** the county calibration passes `faster_mode = FALSE`
explicitly, so its CS rows do NOT suffer this bug. Exposed (integer g and/or
no faster_mode argument → default TRUE): `permutation_placebo_real_data.R`,
`cs_calibration_multi_estimator_mortgage.R`,
`power_simulation_mortgage_delinquency.R`,
`pretrends_mortgage_delinquency.R`, `power_simulation_cs.R` (legacy engine),
`cheap_sims/00_common.R` `fit_cs()` (integer g, though it pins FALSE).
The state calibration's g was already made double on 2026-08-20 (the
pretrends-template fix), but its April run predates that fix and omitted
faster_mode — its CS rows are suspect on top of being SUPERSEDED.

**Fix applied everywhere:** g columns converted to double at construction
("MUST stay double" comment), and `faster_mode = FALSE` pinned at every
previously-unpinned `att_gt` call site, including programmatically in
`power_simulation_cs.R::att_gt_safe()`.

*Prior art:* the same integer-g truncation was first diagnosed 2026-08-21 in
the pretrends template (see
[pretrends-lottery-conditioning_2026-08-21.md](pretrends-lottery-conditioning_2026-08-21.md),
the "+0.080 integer-g bug"); this audit found the surviving instances in
scripts that predate or missed that fix, and adds the faster_mode scoping
(the truncation lives in the `pre_process_did2` path only).

## Finding 3 — `clustervars` is inert without the bootstrap

`did::att_gt(..., clustervars = "state_abb", bstrap = FALSE)` warns
"clustering the standard errors requires using the bootstrap, resulting
standard errors are NOT accounting for clustering" — and the county script
suppressed that warning. Its header claim "all estimators cluster at STATE
level" is therefore false for the CS-analytic arm: those SEs are
county-level. State-clustered CS inference exists only in the bootstrap arms
(`output_blinded_power/county_cs_adaptive/`, via the clean R/power path).
Documented at the call site; the CS-analytic row should be read as
"id-clustered analytic".

## What is NOT affected

- **`R/power/` blinded framework** — `.re_cs` passes `as.numeric(g_int)` and
  `cs_faster_mode: FALSE`; `.re_sunab` uses `sunab(g_int, t)` with g = 0;
  didimputation's NA convention is correct for that package. All LP-DiD /
  TWFE / LDAM / CS-adaptive gate results stand.
- **Pretrends template** (`pretrends_statepanel_template.R`) — g kept double
  since 2026-08-20; `sunab(g, t)` encoding correct.
- **County did2s / didimputation / TWFE calibration rows** — none of these
  touch sunab-NA or the did2 path; per-seed reproduction in the paired re-run
  confirms the stored TWFE values.

## Corrected results

Paired 50-seed SA re-run (same stored seeds, same residual pools; TWFE
recomputed per seed as replication check):
`analysis/diagnostics/sunab_encoding_fix_rerun.R` →
`output/border_diagnostic/cs_calibration_multi_county_sunab_fix/`.

Paired result (50 sims, identical seeds and simulated panels within the run;
current data vintage):

| arm | rejection @5% | mean ATT | sd ATT | mean SE | SE/SD | noise vs TWFE |
|---|---:|---:|---:|---:|---:|---:|
| TWFE (stored 05-21 run, old vintage) | 8% | 0.0015 | 0.0046 | 0.0044 | 0.95 | 1.0× |
| SA, NA encoding (bug) | 42% | 0.0044 | 0.0195 | 0.0085 | 0.44 | 4.2× |
| SA, g=0 encoding (fixed) | **42%** | 0.0041 | 0.0163 | 0.0060 | **0.37** | 3.5× |

**Two conclusions:**

1. **The bug was real but the verdict survives the fix.** Restoring the
   never-treated sample shrinks SA's sampling noise (sd 0.0195 → 0.0163) and
   its SEs, but analytic SA inference on the county panel still rejects a
   true null ~42% of the time at the 5% level. "Sun-Abraham analytic —
   broken, skip" stands on corrected code; only the exact numbers change.
2. **The stored 2026-05-21 run is on a dead data vintage.** The per-seed
   replication check FAILED (max |TWFE − stored| = 0.013, not ~1e-15): the
   May 21 run predates both the 2026-08-10 schedule repair and the
   2026-08-20 state-panel rebuild (treatment dates flow through
   `state_month_panel_with_treatment.csv`). So ALL FIVE estimator rows of
   the LIVE county calibration — not just SA — were stale independently of
   the coding bug. The corrected full re-run on current data replaces the
   whole table.

> **[PENDING — full corrected county calibration (all 5 estimators, current
> vintage, fixed code) running 2026-08-28; its `calibration_summary.csv`
> becomes the new LIVE FINDINGS §4 county table.]**

## Ops note

First launch of the paired re-run OOM'd (6 PSOCK workers × saturated sunab
design matrices on 91k rows → worker killed → "error reading from connection"
in `parLapply`). The script is now batch-checkpointed (appends per batch to
`sim_results_sunab_fix_partial.csv`, skips completed seeds on relaunch) with
default `N_WORKERS = 3`.
