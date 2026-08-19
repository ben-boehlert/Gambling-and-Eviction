# Post-COVID Maturation-Market Power: BJS + did2s (+ twfe, lpdid)

**Date:** 2026-08-19. **Run:** `output_blinded_power/postcovid_maturation/`
(config `config/power_postcovid_maturation.yml`; state / S2 / covid: post
[2021-08..2025-11, 52 months, 17 states, no splice] / D1 panel-template /
count_nb / step; 300 reps × 12-point grid to 0.60; base_seed 20260723; two
paired blocks: maturation50 treatment vs legalization dates).
**New infrastructure:** `bjs` (didimputation) estimator arm in
`R/power/run_estimators.R`; maturation50 schedule
(`analysis/data_prep/make_maturation50_schedule.R` → handle50 = first month a
state's handle reaches 50% of its own peak; blindness cutoffs remain at
`first_start_date`, strictly conservative; handle dates are design info per
BLINDNESS_PROTOCOL §2).

## Bottom line

**Restricting to markets that matured post-COVID neither costs nor buys
power: gate-passing MDEs are ~28–31%, the same as the legalization-date
post-COVID design. The imputation-family hope is only half-realized: did2s is
size-valid on the clean window (its spliced-window failure stays resolved),
but BJS/didimputation FAILS the size gate badly in both blocks (27–29% null
rejection, SE/SD ≈ 0.55) — its nominally best-in-class 21–22% MDE is an
artifact of an invalid test and must not be used.**

## Size gate (δ = 0, 300 reps, 0 failures; gate = reject@.05 ∈ [2.5%, 10%])

| Block (design) | twfe | did2s | bjs | lpdid |
|---|---|---|---|---|
| maturation50 (5 treated / 12 control) | 6.0% PASS | 9.3% PASS* | **29.0% FAIL** | 6.3% PASS |
| legalization (7 treated / 10 control) | 0.7% FAIL (conserv.) | 5.0% PASS | **27.0% FAIL** | 6.3% PASS |

SE/SD: bjs ≈ 0.55 in both blocks (SEs ~45% too small — the classic
few-treated-cluster analytic-SE failure; global PT tolerance does not fix an
inference problem); did2s 0.86–0.87; twfe 0.93–0.95; lpdid 0.76–0.91. Null
bias ≤ 0.02 everywhere (no CS-style location bias).
\* did2s at 9.3% sits at the top of the gate (Wilson ≈ [6.5%, 13.2%]) — its
MDE is understated relative to nominal 5%; treat as borderline.

## MDE-80 (raw, α = .05; gate-passing arms only)

| Block | Estimator | MDE-80 | bootstrap CI | MDE-90 |
|---|---|---|---|---|
| maturation50 | lpdid | **0.280** | [0.263, 0.297] | 0.360 |
| maturation50 | twfe | 0.308 | [0.292, 0.330] | 0.369 |
| maturation50 | did2s* | 0.313 | [0.291, 0.342] | 0.390 |
| legalization | did2s | 0.310 | [0.291, 0.330] | 0.370 |
| legalization | lpdid | 0.326 | [0.239, 0.354] | 0.419 |
| legalization | twfe (failed gate, conservative side) | (0.262) | [0.248, 0.275] | (0.297) |

Disqualified (size): bjs 0.224 / 0.206 — reported only to show what the
invalid test would have claimed.

## Interpretation

1. **Maturation vs legalization treatment barely moves power** (did2s 31.3%
   vs 31.0%): later treatment dates shrink treated clusters 7 → 5 but
   lengthen usable pre-periods and add controls (12 vs 10); the effects
   offset. The binding constraint is the 52-month window with ≤7 switchers,
   not the treatment definition.
2. **The clean-window logic works for did2s** (global PT defensible, size
   valid at 5.0% on legalization dates) — but did2s post-COVID buys no
   power over TWFE. **It does not work for BJS**: didimputation's analytic
   SEs undercover with this few treated clusters regardless of window.
   If BJS is wanted, it needs a different inference arm (e.g., wild/cluster
   bootstrap over its influence representation) — not prespecified, not run.
3. **Cost of going post-COVID stands:** best gate-passing post-COVID MDE
   (lpdid, maturation, 28%) is ~3× the spliced-window LP-DiD MDE (8.1% raw /
   8.9% size-adjusted, 2026-08-17). Real-world: post-COVID median state
   ~24,000 filings/yr → a 28% MDE ≈ 6,700 additional filings/yr; only
   crisis-size effects are detectable.
4. Scope: state level, one mechanism (count_nb), one shape (step), single
   sample (S2) — §14 fragility criterion unmet by construction. County
   post-COVID (the headline unit) remains unrun for these estimators.

## Files

- `output_blinded_power/postcovid_maturation/{oc_summary,mde_table,results_raw.csv.gz,run_metadata.json}`
- Paired seeds with all other framework runs (base_seed 20260723); the two
  blocks share draws rep-for-rep with each other via the common window.

---

# COUNTY addendum (2026-08-19, later same day)

**Runs:** `output_blinded_power/postcovid_maturation_county/` (did2s + lpdid,
analytic) and `output_blinded_power/postcovid_maturation_county_wild/` (lpdid
with the newly plumbed `lpdid_wild` wild-cluster-bootstrap arm; config key →
grid → spec, conditionally hashed — commit 1b5a2aa). County post-COVID panel:
509 counties, 14 states, 50 months; maturation block 4 treated / 10 control
states, legalization block 5 / 9. 300 reps × same 12-δ grid.

## Size gate at county (δ = 0, 300 reps, failures ≤ 1%)

| Arm | maturation50 | legalization | Verdict |
|---|---|---|---|
| did2s analytic | 23.9% | 21.5% | **FAIL both** (SE/SD 0.62) |
| lpdid analytic | 11.7% | 14.0% | FAIL both (SE/SD 0.70–0.72) |
| **lpdid wild** | **5.0%** | **4.7%** | **PASS — exactly nominal** |

The county reversal vs state level (where did2s/lpdid analytic passed) is the
classic few-treated-clusters problem: 4–5 treated state clusters over 509
counties makes cluster-robust analytic SEs badly downward-biased; the wild
cluster bootstrap restores exact size. did2s has no wild arm in the framework,
so **did2s is disqualified at county post-COVID as it stands**.

## Valid county post-COVID MDEs (lpdid wild, α = .05)

| Block | MDE-80 | bootstrap CI | MDE-90 |
|---|---|---|---|
| legalization (5 treated) | **0.239** | [0.230, 0.249] | 0.281 |
| maturation50 (4 treated) | **0.317** | [0.287, 0.353] | 0.436 |

(Analytic lpdid's apparent ~19% MDEs are artifacts of the invalid test.)

## Updated interpretation

1. **County data does NOT rescue post-COVID power the way it rescued the
   spliced window.** Spliced-window county did2s reached MDE ≈ 4–5%; the best
   valid county post-COVID MDE is 23.9% — because the binding constraint is
   4–5 treated state clusters, which counties cannot fix.
2. **Maturation-only costs real power at county** (31.7% vs 23.9%): dropping
   from 5 to 4 treated clusters matters when clusters are this scarce —
   unlike at state level, where the composition change was power-neutral.
3. Best available post-COVID design overall: **county lpdid with wild
   inference, legalization dates — MDE-80 ≈ 24%** (~5,700 extra filings/yr at
   the post-COVID median state), still crisis-size-only detection.
4. Same single-cell scope caveats (S2, count_nb, step) as the state runs.
