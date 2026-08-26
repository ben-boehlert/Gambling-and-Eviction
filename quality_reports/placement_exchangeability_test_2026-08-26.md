# Exchangeable-placement prototype: the null bias is NOT fixable by resampling

**Date:** 2026-08-26 · **Script:** `analysis/diagnostics/placement_exchangeability.R`
**Data:** `output/placement_exchangeability/` · **Log:** `output/placement_exchangeability_run.log`

## Question

`quality_reports/nullbias_decomposition_2026-08-25.md` attributed the +0.042 δ=0 null
bias to `.assign_cohorts()`'s deterministic scarcest-cohort-first fill. If that were the
cause, an exchangeable placement rule would remove it, and the honest fix would be to
repair the sampler rather than recenter the null. This tests that directly.

## Method

Added a `placement` knob to `make_pseudo_schedule()` / `.assign_cohorts()`:
`"scarcest"` (unchanged default), `"random_order"` (random cohort fill order with
restarts), `"uniform"` (strict rejection sampling — exactly uniform over feasible
assignments, i.e. exchangeable by construction). 300 draws per rule on the live gate
spec (state, S2, spliced, shift12, NV-free, min_pre 12 / min_post 6). Statistic:
`corr(pseudo-adoption date, that state's own outcome trend slope)`.

**Regression check: PASS — 25/25 draws under `"scarcest"` are identical to the
pre-2026-08-26 implementation.** Every existing run still reproduces.

## Results

| placement | infeasible | mean corr(date, trend) | share negative | mean corr(date, coverage) |
|---|---:|---:|---:|---:|
| scarcest (current) | 0/300 | **−0.196** | 98.7% | 0.590 |
| random_order | 0/300 | **−0.190** | 98.7% | 0.576 |
| uniform (exchangeable) | **300/300** | — | — | — |

**Structural cause.** Eligible-state counts per cohort date fall monotonically from 27
(2017-03) to 7 (2024-07): late cohorts need states whose data extends far enough forward,
and only a handful qualify. Common support — states eligible for *every* cohort date — is
**7 states against 21 treated slots**, so an exchangeable assignment does not exist at
this template and these support minima. It is not that the sampler picks badly; there is
nothing unskewed to pick.

## Conclusions (superseding the 2026-08-25 memo on this point)

1. **The scarcest-first heuristic is not the cause.** Randomizing the fill order moves the
   correlation by 0.006. The 2026-08-25 attribution was too specific.
2. **The cause is the eligibility structure itself.** Pseudo-adoption date is pinned to
   coverage (corr 0.58–0.59); coverage correlates with trend (−0.112 across the pool), so
   *any* eligibility-respecting assignment inherits a date/trend skew.
3. **Exchangeable placement is impossible here**, not merely expensive — 300/300 rejection
   failures and 7 < 21 on common support both say so.
4. **Therefore recentering is the correct handling, not a patch.** With no exchangeable
   design available, the feasible-placement distribution *is* the design's reference null;
   comparing against it (rather than assuming a zero-centred null) is standard
   randomization-inference logic.

## Residual caveat, to state in the PAP rather than fix

The real adoption process shows **no** such skew: corr(adoption month, own pre-trend) =
−0.078 (ETS, n=16) and +0.215 (annual, n=23), both n.s. and opposite in sign, against
−0.19 for every feasible pseudo-placement. So the simulation's reference distribution
still does not match the real assignment mechanism — the template-placement design
mechanically couples date to coverage in a way the real world does not. That is a
limitation of what the blinded framework can tell us about this design, and it should be
declared, not silently corrected.

## Untested options that would enlarge the feasible set

- Relax `min_pre` / `min_post` (directly widens per-cohort eligibility) — cheap to test.
- Coarsen the cohort template (quarters/years) so fewer, larger cohorts must be filled —
  but that changes the design under test.
