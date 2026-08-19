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
