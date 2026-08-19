# Strategy Review: strategy_memo_quarterly_handle_rampup.md
**Date:** 2026-08-14
**Reviewer:** strategist-critic

## Phase 1: Claim Identification
- **Paper type:** Reduced-form causal paper, with a secondary descriptive/measurement component.
- **Design(s) or approach:** Legal-access Gardner two-stage DiD (`did2s`) as the proposed headline; legal-access Callaway–Sant'Anna (CS) and Sun–Abraham (SA) as secondary estimators; naive TWFE as a diagnostic comparison; Handle-threshold designs as exploratory measurement sensitivities only.
- **Estimand or target:** Intended state-equal ATT of operational legal online access, plus event-quarter ATTs over early and mature windows. The memo does not yet fully specify whether the headline observation is a county-quarter or state-quarter, whether the overall ATT weights states or state-post-periods equally, or the exact early/mature windows.
- **Treatment or variation:** Operational online-access date. In quarterly specifications, the launch quarter is omitted and treatment begins in the first complete following quarter.
- **Control or comparison:** Stable never-online states are described as primary; not-yet-online states are described as secondary. This does not yet align unambiguously with the stated `did2s` first-stage sample.
- **Outcome(s):** Quarterly eviction filings, considered as log counts/log rates and filings per 1,000 renter households. The headline outcome and scale are not fixed.

## Phase 2: Core Design Validity
### Design Check: Legal-access staggered DiD (`did2s`, then CS and SA)
**Assessment:** CONCERNS

#### Issues Found: 5

##### Issue 2.1: The headline estimand and estimation sample are not pinned down
- **Location:** `quality_reports/strategy_memo_quarterly_handle_rampup.md:154-168, 208-214, 252-280`
- **Severity:** MAJOR
- **Problem:** “County-quarters/state-quarters,” “state-weighted overall ATT,” monthly versus quarterly data, and several outcome scales remain alternatives inside the proposed headline. With changing event-time support, equal weighting of treated states, treated state-quarters, and counties are different estimands. A referee cannot tell which parameter the headline coefficient estimates.
- **Suggested fix:** Before implementation, state one primary sample, grain, outcome, cutoff, transition-quarter rule, event window, and weighting formula. Label every alternative as robustness. Define whether the ATT weights each treated state equally and then averages within state over a fixed supported horizon.

##### Issue 2.2: The COVID gap must be an identification rule, not eighth-ranked robustness
- **Location:** `quality_reports/strategy_memo_quarterly_handle_rampup.md:81-84, 104-110, 168, 305, 320, 359-361`; `output/handle_cohort_support/state_cohorts.csv:538,541,733,744-745,748,750`
- **Severity:** MAJOR
- **Problem:** Requiring complete quarters leaves 2016Q1–2019Q4 and 2021Q4–2024Q4, with no observations between them. Under legal timing, TN and VA adopt inside the gap; under Handle timing, WV, PA, and IN cross inside it. With the memo's first-full-quarter rule, TN and VA have no observed treatment or reference-adjacent quarter. Their post-period contrasts necessarily span COVID closure/reopening and cannot supply local pretrend evidence. Existing repository evidence also shows cross-COVID CS cells are 3–6 times noisier and receive 42% of the state-level estimand's weight. Calendar indexing prevents a coding error but does not restore the identifying counterfactual.
- **Suggested fix:** Make a COVID-clean estimand/sample the primary eligibility rule, or explicitly exclude gap-treated cohorts from the headline. Quantify clean-pre, clean-post, and cross-gap weights for the exact county `did2s` estimator before calling it calibrated or referee-defensible. Keep cross-gap estimates labeled separately.

##### Issue 2.3: The proposed `did2s` comparison group is internally ambiguous
- **Location:** `quality_reports/strategy_memo_quarterly_handle_rampup.md:162, 210, 275-280, 317`
- **Severity:** MAJOR
- **Problem:** The memo calls never-online states the primary comparison group, but defines the first stage on all observations with `D=0`, which includes pre-treatment observations of later-treated states. It then calls “not-yet” a secondary specification without explaining what changes in the two stages. These statements do not identify one executable estimator or one comparison population.
- **Suggested fix:** Write the two estimating equations and list exactly which observations enter each stage under the primary and sensitivity variants. Explain how unit and time effects are identified, how later-treated pre-periods enter, and how state weights are carried into stage two.

##### Issue 2.4: The cohort counts are right, but the post-COVID Handle sample label is not
- **Location:** `quality_reports/strategy_memo_quarterly_handle_rampup.md:66-75, 83-84`; `output/handle_cohort_support/state_cohorts.csv:518-543,726-750`
- **Severity:** MAJOR
- **Problem:** Direct mapping of the CSV dates confirms the balanced legal counts (17 states, 14 quarter cohorts, 11 singletons, three doubletons) and Handle counts (16 states, nine cohorts, four singletons, four doubletons, one four-state cohort). The post-COVID treated-cohort arithmetic is also correct: legal sizes are `1,1,1,1,2,2`; Handle sizes are `1,1,2,2,2`. But “Post-COVID 30, 50%-Handle” is not an estimator-ready 30-state Handle sample: Florida lacks Handle and Nevada is pre-sample treated, so the Handle-eligible analysis excludes both. The treated count remains eight, but the control pool and cluster count do not.
- **Suggested fix:** Relabel this row as the Handle-eligible sample with its actual number of states, and regenerate all support tables from the exact estimation frame after full-quarter and treatment-source restrictions.

##### Issue 2.5: The memo does not predeclare a signed hypothesis or plausible effect range
- **Location:** `quality_reports/strategy_memo_quarterly_handle_rampup.md:58, 158, 178, 292-296, 367-370`
- **Severity:** MINOR
- **Problem:** The calibration gate refers to an “economically relevant” MDE without stating the benchmark. Sign and magnitude therefore remain movable after results are seen.
- **Suggested fix:** State the expected sign, the substantive mechanism, and fixed effect-size benchmarks used for power and interpretation.

### Sanity Check
- **Sign:** Not assessable from this strategy memo. The hypothesized household-finance mechanism appears to imply higher eviction filings after market maturation, but the direction is not stated.
- **Magnitude:** No new estimate is presented. Existing state-panel calibration implies an oracle mature-effect MDE around 0.40–0.54 log points in design-preserving simulations, far above a roughly 2.5% benchmark; quartering does not add treated clusters and should not be presumed to close that gap.
- **Dynamics:** A delayed response is economically coherent with Handle ramp-up. However, mature-horizon legal SA coefficients rapidly become two-state contrasts, and gap-treated cohorts have no observed near-treatment quarters.
- **Consistency:** Not assessable before estimation. The memo appropriately requires estimator triangulation and prohibits selecting an estimator ex post based on favorable results.

## Phase 3: Inference
Design issues above should be resolved before inferential comparisons become decisive.

### Issues Found: 2

##### Issue 3.1: Small-cluster inference is named but not operationally specified
- **Location:** `quality_reports/strategy_memo_quarterly_handle_rampup.md:214, 280, 292-296`
- **Severity:** MAJOR
- **Problem:** “State cluster + restricted wild bootstrap” does not say whether the full two-stage estimator is re-estimated in each draw, what null is imposed, how few treated states at each horizon are handled, or how simultaneous event-study bands are formed. Bootstrapping only the second-stage regression would not automatically propagate first-stage estimation and custom weighting uncertainty.
- **Suggested fix:** Specify the complete resampling algorithm, cluster weights, restricted null, replication count, finite-sample reference distribution, and simultaneous-band construction. Calibrate that exact procedure by horizon on the final sample.

##### Issue 3.2: Custom CS aggregation requires a matching variance estimator
- **Location:** `quality_reports/strategy_memo_quarterly_handle_rampup.md:218-222`
- **Severity:** MAJOR
- **Problem:** “Aggregate first by treated state and event quarter” is not a complete CS estimand or inference rule. Custom equal-state/cell weights can differ from standard `aggte` weights, and uncertainty must account for the chosen fixed weights and common controls. Otherwise the reported point estimate and standard error may refer to different aggregation logic.
- **Suggested fix:** Give the aggregation formula, support rule, fixed weighting population, and influence-function/bootstrap calculation for that exact aggregate.

## Phase 4: Polish & Completeness
These points are lower priority than the sample, COVID, and inference issues above.

### Issues Found: 2

##### Issue 4.1: Handle-based maturity windows remain underdefined
- **Location:** `quality_reports/strategy_memo_quarterly_handle_rampup.md:140-150, 268-273, 325`
- **Severity:** MINOR
- **Problem:** Average total Handle is not comparable across states and is affected by population, seasonality, reporting, and a future-capped peak. “Early/developing/mature” has no fixed thresholds. This does not invalidate legal-access DiD, but it weakens the claimed pre-specification role for Handle.
- **Suggested fix:** Lock a normalized descriptive measure and fixed window thresholds before inspecting eviction outcomes; clearly distinguish within-state ramp normalization from cross-state intensity.

##### Issue 4.2: Methodological citations are not submission-ready
- **Location:** Throughout; especially `quality_reports/strategy_memo_quarterly_handle_rampup.md:15-18,154-184,231-233`
- **Severity:** MINOR
- **Problem:** Gardner, Callaway–Sant'Anna, Sun–Abraham, BJS, and the small-cluster/calibration claims are named without formal references. No `Bibliography_base.bib` was found in the repository for the requested cross-check.
- **Suggested fix:** Add full citations and a bibliography source before manuscript drafting.

## Summary
- **Overall assessment:** MAJOR ISSUES
- **Critical issues (must fix):** 0
- **Major issues (should fix):** 6
- **Minor issues (consider):** 3

## Priority Recommendations
1. **[MAJOR]** Define one exact legal-access `did2s` headline estimand, sample, comparison set, outcome, horizon, and state-weighting formula.
2. **[MAJOR]** Resolve the COVID gap at the design stage: make COVID-clean comparisons primary and quantify the exact `did2s` weight carried by cross-gap contrasts before trusting the headline.
3. **[MAJOR]** Specify and calibrate full-estimator state-level inference; do not infer that quarterly aggregation repairs CS/SA merely because dates pool into fewer cohorts.
4. **[MAJOR]** Correct the post-COVID Handle sample denominator and derive all cohort/support claims from the final estimator-ready frame.
5. **[MINOR]** Predeclare the signed hypothesis, plausible effect-size range, and normalized Handle-based maturity windows.

## Positive Findings
- The memo gets the central causal distinction right: legal access can define an intention-to-treat policy effect, whereas realized Handle is a post-treatment variable and cannot cure sparse legal cohorts without changing the estimand and adding strong selection assumptions.
- The exact balanced-sample quarter arithmetic is correct, and the memo correctly emphasizes that quartering does not create new independently treated states.
- The proposed ordering—legal-access `did2s` first, legal CS/SA only as calibrated short-horizon triangulation, naive TWFE as a diagnostic—is potentially referee-defensible after the primary estimand, COVID-clean sample, and inference procedure are made exact.

## Bottom-Line Disposition

**Revise before implementation.** Quarterly outcomes plus Handle ramp-up do **not** make Handle-timed CS/SA suitable for headline causal inference. Quarterly legal-access CS/SA may be shown as secondary point-estimate triangulation, but existing support and power evidence makes headline eligibility unlikely. A legal-access `did2s` headline is a defensible response to the TWFE concern only after the memo fixes the estimand/control ambiguity, makes COVID-clean identification primary, and passes exact-sample full-procedure calibration. `did2s` is still a fixed-effects-based estimator, but it avoids the contaminated first stage and forbidden-comparison problem of naive staggered TWFE; the remaining referee risk is identification and inference, not the label “TWFE.”
