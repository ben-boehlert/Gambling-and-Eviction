# Strategy Review: strategy_memo_did2s_lpdid_covid.md
**Date:** 2026-08-20  
**Reviewer:** strategist-critic

## Phase 1: Claim Identification
- **Paper type:** Reduced-form causal strategy memo
- **Designs:** (1) clean-control LP-DiD with comparisons restricted to one COVID regime; (2) did2s estimated separately by regime
- **Estimand or target:** Dynamic state-level ATTs and a support-limited average over post-legalization horizons
- **Treatment:** First month of legal online sports betting
- **Control or comparison:** Never-treated and not-yet-treated states that remain untreated through the LP-DiD horizon; untreated observations in the did2s first stage
- **Outcome:** State-month log eviction filings, conditional on resolving the outcome-panel measurement failures

## Phase 2: Core Design Validity

### Design Check: LP-DiD
**Assessment:** CONCERNS

#### Issues Found: 3

##### Issue 2.1: “Local” is accurate, but “meaningful improvement” is not yet established
- **Location:** Memo lines 39, 92–100, 110–115, 219–223
- **Severity:** MAJOR
- **Problem:** The memo correctly distinguishes did2s's additive untreated-outcome model from LP-DiD's cohort/date/horizon-specific parallel-changes restrictions. But “local” does not mean weak or validated. For every supported \((t,h)\), LP-DiD still assumes the switcher-control long difference identifies the untreated change. At long horizons this can be a demanding collection of restrictions, and the control group changes with \(t\) and \(h\). Removing cross-gap contrasts therefore changes the location of the identifying assumptions; it does not by itself show they are more plausible in these data.
- **Suggested fix:** Replace “meaningful improvement” and the unconditional 3.5/5 rating with “more localized and potentially more credible, conditional on within-regime path diagnostics, support, and measurement validity.” Describe the rating as an ex ante design ranking, not an empirical validation.

##### Issue 2.2: Non-straddling LP-DiD avoids the omitted interval, not COVID contamination
- **Location:** Memo lines 39, 88, 99, 110–115, 213–214
- **Severity:** MAJOR
- **Problem:** The memo acknowledges persistent recovery confounding at line 99, but “COVID remedy” and the headline comparison still invite the stronger reading that dropping straddling long differences solves the pandemic problem. It only guarantees that neither endpoint nor baseline lies inside, or on opposite sides of, the declared gap. State-specific moratorium expiry, court reopening, backlog unwinding, migration, and reporting changes can continue within the post regime and can be correlated with legalization timing. Trying two gap endpoints is sensitivity analysis, not identification.
- **Suggested fix:** Rename this section “cross-gap exclusion.” State explicitly: “This removes mechanical interpolation across omitted months but does not purge COVID-related state-specific recovery paths.” Treat boundary-adjacent exclusions and within-regime untreated-path evidence as necessary diagnostics, while acknowledging that they cannot establish the counterfactual assumption.

##### Issue 2.3: The pooled and dynamic estimands remain underdefined when support changes
- **Location:** Memo lines 70–81, 106–108, 112, 128, 138, 150, 160–161, 195, 221–223
- **Severity:** MAJOR
- **Problem:** Excluding gap-treated and already-treated-at-regime-entry states changes the target population. A pre-COVID estimate pertains to early adopters; a post-COVID estimate pertains to later adopters. Their weighted average is not the ATT for all legalizing states without an external transportability restriction. The proposed “equal-weighted average over horizons and eligible treated states” is ambiguous when eligibility changes with \(h\): equal state-horizon cells, equal horizons, and equal states produce different parameters. A fixed-cohort event study holds treated composition constant but may select a very small set of states, and its clean-control composition can still change by horizon.
- **Suggested fix:** Define the target with an explicit finite-sample weight formula. Name the eligible-state set separately for each regime and for fixed versus maximal support. Report state and control contributors at every horizon. Do not call a cross-regime average an overall legalization ATT; call it a declared mixture of two regime- and cohort-specific parameters.

### Design Check: did2s
**Assessment:** CONCERNS

#### Issues Found: 1

##### Issue 2.4: The early-treated-state identification warning is correct and must be a hard support rule
- **Location:** Memo lines 120–138, 197–204
- **Severity:** MINOR
- **Problem:** The memo is technically right: with first-stage estimation restricted to untreated observations, a state-by-post-COVID effect is not identified for a state already treated when the post regime begins. A pooled state-by-post adjustment cannot recover that counterfactual by algebra. The same applies to states treated inside the omitted gap. The remaining risk is presentational: “algebraically similar to allowing separate regimes” could be read as a pooled fix before the support qualification is noticed.
- **Suggested fix:** State the rank condition first: each retained state-regime effect must be identified from untreated observations in that regime. Make exclusion of states already treated at regime entry a non-negotiable first-stage support rule, not a robustness choice. Keep pre- and post-regime parameters separate.

### Sanity Check
- **Sign:** Not assessable; the memo correctly endorses no current treatment-effect estimate.
- **Magnitude:** Not assessable. The 0.05-log-point benchmark is a target effect, not an estimate.
- **Dynamics:** Not assessable on the proposed non-straddling, rebuilt-panel specification because it has not been rerun.
- **Consistency:** The qualitative ranking of regime-specific LP-DiD above pooled did2s is defensible in principle, but the 2/5 and 3.5/5 scores are not yet data-validated.

## Phase 3: Inference

### Issues Found: 2

These inference issues matter after the identification and measurement gates above.

##### Issue 3.1: The existing LP-DiD joint pretrend p-value is invalid
- **Location:** Memo lines 108, 151, 168, 195; current implementation `analysis/main/lpdid_statepanel.R:273-278`
- **Severity:** MAJOR
- **Problem:** The current code computes \(\sum_h (\hat\tau_h/SE_h)^2\) and compares it with a chi-square distribution, implicitly treating horizon estimates as independent. They reuse states, baselines, and outcomes, so cross-horizon covariance is material. The memo correctly says not to do this, but it should explicitly invalidate the existing saved joint p-value rather than merely prescribe future covariance-aware inference.
- **Suggested fix:** Add a release statement that no existing LP-DiD joint-pretrend p-value may be cited. Require a joint Wald statistic using the full state-clustered covariance matrix, or a joint null-imposed state-cluster bootstrap that re-estimates all horizons in each draw. Preserve the exact horizon-specific samples in that procedure.

##### Issue 3.2: Wild-cluster bootstrap is not an automatic cure for few treated clusters
- **Location:** Memo lines 50, 146–152, 216
- **Severity:** MAJOR
- **Problem:** There are about 24–26 total state clusters but fewer switchers within each regime and at longer horizons. Null-imposed wild-cluster bootstrap is preferable to an uncorrected large-cluster approximation, yet its reliability can still be poor with highly unbalanced treatment leverage or only a handful of treated clusters. “Use Webb weights” alone does not establish size control. The current standalone LP script also uses Rademacher weights, not the memo's proposed Webb-weight specification.
- **Suggested fix:** Make inference credibility conditional on same-design null calibration by regime and horizon/support pattern. Report total, treated, and control cluster counts and leverage by coefficient; suppress or label inferential claims where treated support collapses. Distinguish the proposed inference from all saved outputs generated under other bootstrap settings or COVID endpoints.

## Phase 4: Polish & Completeness

### Issues Found: 1

##### Issue 4.1: The descriptive COVID evidence is correctly labeled noncausal but is overinterpreted
- **Location:** Memo lines 62–64 and credibility table at lines 43–50
- **Severity:** MAJOR
- **Problem:** The 0.44–0.54 log-point statistic is across-state dispersion in pre/post mean shifts among never-treated states. It is not the bias in did2s: bias depends on how those shifts align with treatment timing and estimator weights. It also does not isolate COVID. The local handoff reports a pre-COVID placebo split SD of 0.416, close to the across-gap dispersion, suggesting substantial generic instability; and the current data audit documents changing reporting geography in never-treated controls. Thus the statistic is a valid warning against a stable global state effect, but not evidence that COVID uniquely caused the failure or that LP-DiD earns a 3.5/5 rating.
- **Suggested fix:** Report the across-gap statistic beside the pre-COVID placebo and within-post dispersion. Say that the evidence is consistent with additive-model misspecification from COVID, generic drift, and/or measurement changes. Remove the comparison “much larger than a 0.05 target effect” or clarify that it is scale context, not an implied bias calculation. Mark all ratings provisional until fixed-geography outcomes and exact non-straddling support are audited.

## Summary
- **Overall assessment:** MAJOR ISSUES
- **Critical issues (must fix):** 0
- **Major issues (should fix):** 6
- **Minor issues (consider):** 1

## Priority Recommendations
1. **[MAJOR]** Recast non-straddling LP-DiD as removing cross-gap comparisons, not removing COVID confounding, and make its credibility explicitly conditional.
2. **[MAJOR]** Define the exact regime-, cohort-, horizon-, and weight-specific estimands; do not present a cross-regime mixture as the ATT for all adopters.
3. **[MAJOR]** Formally invalidate the current sum-of-squared-z LP-DiD pretrend test and require full cross-horizon covariance.
4. **[MAJOR]** Condition small-cluster inference on support-specific size calibration rather than treating wild bootstrap as sufficient by itself.
5. **[MAJOR]** Temper the descriptive COVID claim with the pre-period placebo dispersion and reporting-composition caveat.

## Positive Findings
- The memo correctly identifies pooled did2s's additive untreated-outcome restriction and correctly explains why deleting COVID rows alone does not relax the pre/post state-effect restriction.
- It correctly recognizes that state-by-post adjustments are unidentified for early-treated states when the first stage uses untreated observations only.
- It correctly flags changing horizon composition, requires clean controls, uses calendar rather than row lags, and calls for covariance-aware joint inference and a measurement release gate.
