# Pre-Analysis Plan — Power Simulation Language (Draft)

**Date:** 2026-07-23
**Status:** Draft language for the pre-analysis plan. Numeric operating characteristics marked
`[OC: …]` are to be transcribed from `output_blinded_power/` summary tables once the primary
simulation has run; nothing in this document reports actual treatment-effect estimates, and no
`[OC]` slot may be filled with anything other than blinded simulation output.

---

## 1. Design choices fixed before seeing results

The following were fixed in `docs/methodology/POWER_SIMULATION_DESIGN.md` (2026-07-23), before
any operating characteristic was computed and without inspecting the project's estimated
treatment effects (blindness procedure: `POWER_SIMULATION_BLINDNESS_PROTOCOL.md`):

- Estimand: overall ATT of sports-gambling legalization on eviction filings, proportional scale
  (log1p filings), with dynamic event-time effects as secondary.
- Treatment assignment at the state level; outcomes at the county-month level (state-month and
  quarterly as pre-specified variants); standard errors clustered by state throughout.
- Candidate estimator set (fixed and finite): Callaway–Sant'Anna (intended primary),
  TWFE (diagnostic benchmark), Gardner two-stage did2s (credible alternative), Sun–Abraham
  (calibration diagnostic only).
- Treatment definitions: online launch (primary), any-legal-betting (variant).
- Comparison groups: not-yet-treated (primary), never-treated (variant).
- Anticipation windows {0, 6} months; event windows and COVID handling as pre-specified.
- The effect-size grid, its external sources, the operating-characteristic metrics, the failure
  criteria, and the specification selection rule (design doc §§10, 12, 14, 15).

## 2. Simulation assumptions (stated, not hidden)

Power and size are estimated by Monte Carlo simulation in the style of Black, Hollingsworth,
Nunes & Simon (2022): real *untreated* outcome data, pseudo-treatment schedules that preserve
the actual staggered cohort structure, and imposed effects of known size, re-estimated with the
exact intended estimators. Key assumptions:

- Untreated eviction filings are representative of counterfactual treated-period filings up to
  the fitted seasonal/state structure. Because only 28 calendar months (2016-01–2018-04) are
  universally untreated, most calibration uses state-specific untreated risk sets and
  never-treated states; results are reported across all calibration samples, and differences
  across them are treated as genuine uncertainty about power, not noise to be averaged away.
- Imposed effects follow pre-specified shapes (immediate, delayed, ramp, temporary,
  anticipatory, heterogeneous); count-based negative-binomial augmentation (dispersion matched
  to untreated overdispersion) is the primary injection mechanism, with deterministic
  log-scale shifts as a transparent benchmark.
- Never-treated states may differ systematically from treated states; the never-treated-placebo
  design is therefore one calibration among several, not the headline.
- Synthetic/residual-based simulations are sensitivity analyses only; BHNS document that fully
  synthetic data can materially overstate MDEs, and our residual-based variants state their
  covariance assumptions (month-stratified iid vs state-AR(1)) explicitly.

## 3. Primary specification

The primary specification is the one selected by the pre-registered rule (design doc §15):
eliminate on size/coverage/failure/estimand-match first; then compare precision across
calibration samples and injection mechanisms using the worst reasonable case; prefer the
simplest adequate specification.

> The primary analysis will estimate `[SELECTED ESTIMATOR]` on `[SELECTED PANEL/AGGREGATION]`
> with `[SELECTED OUTCOME TRANSFORM]`, treatment defined as `[SELECTED DEFINITION]`, comparison
> group `[SELECTED]`, anticipation `[SELECTED]`, and inference by `[SELECTED PROCEDURE]`.
> In null simulations this specification rejected at `[OC: size at 5%]` against a nominal 5%
> level, with `[OC: coverage]`% coverage of known imposed effects; its minimum detectable
> effect at 80% power is `[OC: MDE-80 range across calibration samples]`.

## 4. Robustness set (limited, pre-specified)

Estimates will also be reported for: `[ROBUSTNESS 1..k — filled from the selection rule's
surviving variants]`, each of which passed the same size/coverage screens. Specifications that
failed calibration are reported in an appendix as diagnostics with an explicit warning, not as
robustness checks (this includes any estimator whose null rejection rate or coverage was
materially distorted in our design — see `[OC table reference]`).

## 5. Outcomes and treatment definitions

Primary outcome: county-month eviction filings (Eviction Tracking System), analyzed as
log1p(filings); rate and asinh transforms pre-specified as variants. Primary treatment: first
month of legal online sports betting in the state; any-legal-betting as a variant. No outcome
or treatment definition will be added, dropped, or redefined after unblinding.

## 6. Multiple testing

The paper reports one primary estimate (the primary specification's overall ATT) at α = 0.05,
two-sided. Pre-trend assessment uses the Holm-adjusted joint test over leads −12…−1 (as
calibrated in the simulation) plus Rambachan–Roth sensitivity; pre-testing is reported as
diagnostic information and the analysis is not conditioned on passing it (Roth 2022). Secondary
and robustness estimates are interpreted jointly, without independent hypothesis-level claims;
dynamic event-time profiles use uniform (sup-t) bands where available rather than pointwise
bands.

## 7. Interpretation of null findings

Detectable-effect language is fixed in advance:

> With minimum detectable effects of `[OC: MDE-80 range]` at 80% power, a null result should be
> read as ruling out proportional increases in eviction filings at or above `[OC: upper end of
> range]`, not as evidence of no effect. Effects below `[OC: lower end]` — including effects of
> the size found for consumer-credit outcomes scaled down by eviction's position as a more
> extreme downstream margin — would not be reliably detectable in this design, and we will say
> so explicitly. If the simulations show that no candidate specification detects
> policy-relevant effects (≤ 5%) with adequate probability, the study will be framed as
> providing bounds and design guidance rather than a decisive test.

## 8. What the power simulation does not do

It does not validate identification. Parallel-trends credibility is assessed separately
(pre-trends diagnostics, HonestDiD sensitivity), and no amount of simulated power substitutes
for it. The simulation also does not use, and its authors did not consult, the project's
estimated treatment effects; the blindness protocol, its automated checks, and its disclosure
log are in `POWER_SIMULATION_BLINDNESS_PROTOCOL.md`.
