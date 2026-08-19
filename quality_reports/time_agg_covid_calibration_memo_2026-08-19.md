# CS Calibration under Time Aggregation × COVID Handling

**Date:** 2026-08-19 (state panel). **Status:** 6 of 13 scenarios complete,
1 in progress, 6 pending at handoff (16:40) — see §10 for the exact state and
§6 for the resume command.
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

---

## 9. WHY does CS pass post-COVID? (diagnostic, 2026-08-19)

**Short answer: it is the numerator, not the denominator — and the "pass" is a
coincidental balance, not clean calibration.**

### 9.1 CS's SEs barely move; its estimate dispersion halves

| Cell | sd_att | mean_se | SE/SD | bias | coverage | reject |
|---|---|---|---|---|---|---|
| month_drop | **0.537** | 0.346 | 0.64 | +0.161 | 0.82 | 18.3% |
| quarter_drop | 0.500 | 0.328 | 0.66 | +0.081 | 0.83 | 16.7% |
| year_drop | 0.534 | 0.388 | 0.73 | −0.476 | 0.75 | 24.7% |
| month_post | **0.274** | 0.289 | 1.06 | −0.204 | 0.95 | 5.0% |
| quarter_post | 0.240 | 0.278 | 1.16 | −0.212 | 0.99 | 0.7% |
| year_post | 0.463 | 0.598 | 1.29 | −0.578 | 0.92 | 8.0% |

Going month_drop → month_post, `mean_se` falls only 16% (0.346 → 0.289) while
`sd_att` falls 49% (0.537 → 0.274). CS's analytic SE is approximately right for
post-COVID sampling variability and far too small for the spliced window. The
question is therefore "what inflates CS's estimate dispersion on the spliced
window", not "why do the SEs improve".

### 9.2 The straddle mechanism, and a near-exact variance match

CS's ATT(g,t) compares period t to base period g−1 (`base_period = "varying"`).
On the spliced panel the calendar is non-contiguous, so a (g,t) pair can have
its **base period before the COVID gap and its outcome period after it**. The
never-treated diagnostic (`output/covid_global_pt/`) measured what such a
comparison imports: never-treated state effects shift across the gap with
**SD = 0.467 log points** (range −0.61 to +0.76). Which states straddle the gap
depends on the random pseudo-assignment, so this enters as cross-replication
dispersion that the analytic variance formula does not model — it is a real
feature of Y(0), not estimator sampling noise.

Back-of-envelope, treating the contamination as independent of the clean
component:

    sqrt(0.274^2 + 0.467^2) = sqrt(0.075 + 0.218) = 0.541   (predicted)
    observed sd_att on month_drop                  = 0.537

The independently-measured across-COVID shift SD reproduces the spliced
dispersion almost exactly. Suggestive rather than conclusive (it assumes
independence and one common contamination scale), but it is a strong match.

**Why TWFE survives the same splice:** its state-clustered SE mechanically
absorbs arbitrary within-state correlation — including a state-specific level
shift — so its SE grows to match its own dispersion (SE/SD 1.06 spliced). CS's
analytic/multiplier-bootstrap SE, built from (g,t)-cell influence functions,
does not propagate the straddle contamination.

### 9.3 The month_post "pass" is fragile: the null distribution is off-centre

Rejections decomposed by tail (CS analytic, δ = 0, 300 reps):

| Cell | reject (att<0) | reject (att>0) | total | median att |
|---|---|---|---|---|
| month_drop | 3.7% | 14.7% | 18.3% | **+0.133** |
| quarter_drop | 6.0% | 10.7% | 16.7% | +0.117 |
| year_drop | **24.0%** | 0.7% | 24.7% | −0.498 |
| month_post | **4.0%** | **1.0%** | 5.0% | **−0.184** |
| quarter_post | 0.7% | 0.0% | 0.7% | −0.207 |
| year_post | **8.0%** | **0.0%** | 8.0% | −0.565 |

Under a correctly-centred null each tail should carry ≈2.5%. `month_post`
splits 4.0/1.0: its two-sided 5.0% is the **net of a null distribution centred
at −0.18 against a slightly conservative SE**, not evidence that CS is
correctly calibrated there. Consequences: (i) one-sided or directional
inference at this cell is NOT 5%; (ii) the location shift would contaminate any
real ATT estimate; (iii) the pass is not robust — small changes in SE
conservativeness move it.

CS's null centre is non-zero in **every** cell and flips sign by window
(+0.13 spliced monthly, −0.18 to −0.57 post/annual). With δ = 0 the truth is
exactly 0, so this is a genuine estimator/design artifact — most plausibly the
not-yet-treated comparison on a strongly trending panel (post-COVID filings are
recovering), where later-assigned states sit at a systematically different
point on the trend than earlier-assigned ones.

### 9.4 Decisive follow-up (NOT yet run)

Re-run `month_post` with `control_group: nevertreated`. If the −0.18 centring
collapses, the not-yet-treated comparison is the cause; if it persists, the
cause is aggregation weights over identifiable (g,t) cells. Cost is trivial
(~1.4 s/cell → ~2 min for 300 reps). Until then, **CS should not be described
as "calibrated post-COVID"** — the defensible statement is "two-sided size is
nominal at one cell, with a null distribution centred −0.18 away from truth".

---

## 10. Handoff state (2026-08-19 16:40, laptop closing)

**Complete and on disk (6):** `month_drop`, `quarter_drop`, `year_drop`,
`month_post`, `quarter_post`, `year_post`. All results in §2 and §9 come from
these and are final.

**In progress (1):** `month_keep` — was at batch 11 of 12 (reps 251–275).

**Pending (6):** `quarter_keep`, `year_keep`, `quarter_post_completeperiods`,
`year_post_completeperiods`, `quarter_keep_completeperiods`,
`year_keep_completeperiods`. Estimated ~25 min of compute for all six.

**To resume:** run the §6 command. It rereads each partial's `.done_reps`
sidecar, discards any torn trailing batch, skips the 6 completed scenarios
outright, and continues. Verified working twice today (after a furrr worker
crash and after a deliberate stop). The run-level summaries
(`oc_summary.csv`, `mde_table.csv`, `run_metadata.json`) are only written once
all 13 scenarios finish — until then, read the partials directly, as §2 and §9
did.

**What the pending cells can and cannot change:** they add the
no-COVID-handling (`keep`) baseline and isolate the partial-period artifact
behind annual's −0.48/−0.58 null bias. They **cannot overturn** the headline
findings, which rest entirely on the 6 completed cells: aggregation does not
fix CS calibration; the COVID splice dominates; the single apparent pass
(`month_post`) is a fragile net of an off-centre null.

**Next actions, in priority order:**
1. Finish the 6 pending cells (resume command, ~25 min).
2. Run the §9.4 decisive test — `month_post` with
   `control_group: nevertreated`, ~2 min — to attribute CS's off-centre null.
3. Only then consider power/MDE, and only for cells that pass the gate, via
   `R/power/adaptive_mde.R` (shift mode is barred for CS MDEs).
4. Unrelated but flagged today: re-verify the "did2s is the calibrated county
   workhorse" claim at 300 reps (it failed the pooled county spliced gate at
   13.6% in `dose_tercile_gates`, vs 4.1% in a 50-rep smoke).

---

## 11. `month_keep` result (completed 16:42) — the splice mechanism confirmed

Monthly, **no COVID handling at all** (pandemic months left in, calendar
contiguous), 300 reps, δ = 0:

| Estimator / arm | reject@.05 | sd_att | mean_se | SE/SD | bias |
|---|---|---|---|---|---|
| cs analytic | **7.3% PASS** | 0.326 | 0.249 | 0.76 | −0.146 |
| cs boot | 9.3% PASS (top of gate) | 0.326 | 0.265 | 0.81 | −0.146 |
| cs boot_t | 6.3% PASS | 0.326 | 0.266 | 0.82 | −0.146 |
| did2s analytic | 19.3% FAIL | 0.158 | 0.112 | 0.71 | +0.001 |
| lpdid analytic / wild | 3.0% PASS | 0.080 | 0.085 | 1.07 | −0.018 |
| twfe analytic / wild | 1.0% / 0.7% | 0.089 | 0.108 | 1.22 | +0.001 |

### The decisive comparison: CS's dispersion by COVID handling (monthly)

| Window | Calendar | sd_att | CS analytic reject |
|---|---|---|---|
| `drop` (spliced) | **non-contiguous** | **0.537** | 18.3% FAIL |
| `keep` (pandemic left in) | contiguous | 0.326 | 7.3% PASS |
| `post` (post-COVID only) | contiguous | 0.274 | 5.0% PASS |

**This isolates the mechanism.** The `keep` window contains *more* pandemic
disruption than `drop` — it retains every volatile 2020–21 month — yet CS's
dispersion is 39% lower and its size passes. The damage therefore comes from
the **discontinuity in the calendar, not from the pandemic observations**:
only the spliced panel lets an ATT(g,t) pair its base period before the gap
with its outcome after it, importing the state-specific level shifts the
never-treated diagnostic measured at SD 0.467.

Quadrature check against both contiguous baselines (assuming independence):

    sqrt(0.274^2 + 0.467^2) = 0.541      (post as baseline)
    sqrt(0.326^2 + 0.467^2) = 0.569      (keep as baseline)
    observed month_drop sd_att = 0.537

Both bracket the observed value, the post-based estimate almost exactly.

### But the same fragility applies

`month_keep`'s CS tail split is **6.3% negative / 1.0% positive**, median att
**−0.112** — again a two-sided pass over an off-centre null, and SE/SD is still
0.76 (SEs too small; the pass survives only because the dispersion shrank).
So the §9.3 caveat stands for `keep` as well: two-sided size within gate,
directional inference not 5%, and a location shift that would contaminate a
real ATT.

**Revised practical implication:** if a CS design is wanted, avoid the SPLICE
specifically — either keep the full contiguous calendar (and model COVID
explicitly) or restrict to post-COVID. Do not drop a window out of the middle.
did2s still fails on `keep` (19.3%), so this is not a general fix for
imputation estimators.

---

## 12. Cells completed 16:48–17:15 (11 of 13 done)

CS analytic, δ = 0, 300 reps, all completed cells:

| Cell | reject@.05 | sd_att | mean_se | SE/SD | bias | treated |
|---|---|---|---|---|---|---|
| month_drop | 18.3% FAIL | 0.537 | 0.346 | 0.64 | +0.161 | 23 |
| quarter_drop | 16.7% FAIL | 0.500 | 0.328 | 0.66 | +0.081 | 23 |
| year_drop | 24.7% FAIL | 0.534 | 0.388 | 0.73 | −0.476 | 23 |
| month_keep | 7.3% PASS | 0.326 | 0.249 | 0.76 | −0.146 | 23 |
| quarter_keep | 16.3% FAIL | 0.375 | 0.297 | 0.79 | −0.278 | 23 |
| **year_keep** | **62.7% FAIL** | 0.625 | 0.423 | 0.68 | **−1.047** | 23 |
| month_post | 5.0% PASS | 0.274 | 0.289 | 1.06 | −0.204 | 7 |
| quarter_post | 0.7% fail (cons.) | 0.240 | 0.278 | 1.16 | −0.212 | 7 |
| year_post | 8.0% PASS | 0.463 | 0.598 | 1.29 | −0.578 | 7 |
| quarter_post_completeperiods | **5.3% PASS** | 0.281 | 0.319 | 1.13 | −0.164 | 7 |
| year_post_completeperiods | 0.0% fail (cons.) | 0.169 | 0.192 | 1.14 | **−0.042** | 4 |

### 12.1 Annual + pandemic-kept is catastrophic (`year_keep`)

62.7% null rejection and a **−1.047 log-point null bias** — the worst cell in
the grid by a wide margin. With only 9 annual periods, the 2020 moratorium
year is a single enormous negative outlier that no time effect can absorb into
a comparison across differently-timed cohorts. **Annual aggregation and
"leave COVID in" must never be combined.** Note this is the exact opposite of
the monthly recommendation in §11, where `keep` was the *best* window: at
monthly resolution the pandemic is ~17 unusual observations out of 119; at
annual resolution it is 1–2 catastrophic observations out of 9.

### 12.2 The partial-period artifact is CONFIRMED and quantified

`complete_periods_only` removes unit-periods lacking their full month
complement. Its effect on CS's null bias:

| Pair | bias without rule | bias with rule | reduction |
|---|---|---|---|
| year_post | −0.578 | **−0.042** | **93%** |
| quarter_post | −0.212 | −0.164 | 23% |

This confirms §3's hypothesis: the great majority of annual's null bias was a
mechanical aggregation artifact (the loader filters COVID months *before*
aggregating, so post-COVID 2021 held 5 months of filings summed as if a year),
not an estimator property. At quarterly the artifact is smaller because a
partial quarter loses at most 1 of 3 months.

**But the fix costs design size.** `year_post_completeperiods` drops from 7 to
**4 treated states** (states whose only post-window periods were partial
disappear), and the test becomes degenerate: 0% rejection, SE/SD 1.14.
`quarter_post_completeperiods` is the one cell that improves on both margins —
5.3% rejection (vs 0.7% without the rule), SE/SD 1.13, bias −0.164, 7 treated.

### 12.3 Updated practical ranking for a CS design

1. **`quarter_post` + complete periods** — 5.3%, 7 treated, smallest bias
   among passing cells. Best-calibrated CS cell found in this project.
2. **`month_post`** — 5.0%, 7 treated, bias −0.204.
3. **`month_keep`** — 7.3%, 23 treated (most clusters of any passing cell),
   bias −0.146, but SE/SD 0.76.
4. Everything spliced, and anything annual-with-COVID: disqualified.

All passing cells retain the §9.3 caveat: two-sided size within gate over an
off-centre null, so directional inference is not 5% and the location shift
would contaminate a real ATT.
