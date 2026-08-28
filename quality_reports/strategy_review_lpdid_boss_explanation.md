# Strategy Review: strategy_memo_lpdid_boss_explanation.md
**Date:** 2026-08-28
**Reviewer:** strategist-critic

## Phase 1: Claim Identification
- **Paper type:** Reduced-form policy evaluation, with an exposure-timing measurement component.
- **Design(s) or approach:** State-level stacked LP-DiD with clean, not-yet-launched controls and wild-cluster inference; compared with long differences, staggered TWFE, Callaway-Sant'Anna, `did2s`, Sun-Abraham, BJS, and LDAM.
- **Estimand or target:** A pooled contrast between outcomes 12--24 months after a state first reaches 75% of its frozen observed peak Handle and a shared pre-launch baseline, net of the same change among states unlaunched through the outcome month. The memo does not choose EWATT versus VWATT, so its exact pooled estimand remains unresolved.
- **Treatment or variation:** State-specific first crossing of 75% of a future-capped, post-legalization Handle peak, followed by a 12-month delay.
- **Control or comparison:** States not yet launched online betting by each treated cohort-horizon's outcome month; launched but not-yet-mature states are excluded.
- **Outcome(s):** State-month log-transformed eviction filing counts in the configured power design; the Ohio illustration describes the contrast in raw-filings language.

## Phase 2: Core Design Validity
### Design Check: Mature-period stacked LP-DiD
**Assessment:** CRITICAL ISSUES

#### Issues Found: 5

##### Issue 2.1: The 75%-maturity clock does not identify the legalization ATT
- **Location:** Memo lines 5, 24--32, 88; `data/processed/ramp75_schedule.csv`; prior accepted audit `quality_reports/handle_maturity_results_summary_code_review.md:44-48`
- **Severity:** CRITICAL
- **Problem:** The memo repeatedly calls the target a causal mature-period ATT, but the event date is determined by realized post-legalization Handle and a future-capped within-sample peak. Crossing time can respond to betting demand, operator entry, promotions, regulation, seasonality, income, and other state conditions that can also predict evictions. Waiting another 12 months does not remove that selection. The design therefore estimates an exposure-defined mature-market contrast under additional assumptions; it is not automatically the causal effect of legal access. This conflicts with the repository's prior accepted conclusion that threshold-timed LP-DiD must be labeled exploratory rather than a causal repair.
- **Suggested fix:** In the boss-facing explanation, call this an exposure-timed or mature-market comparison, not the legalization ATT. State that legal-launch LP-DiD remains the causal access design unless the Handle-timing assumptions are separately defended. Disclose that 75% is a first crossing of a frozen observed peak, not an exogenous or permanent maturity date.

##### Issue 2.2: The claimed automatic COVID cross-gap exclusion is false in the power implementation
- **Location:** Memo line 34 and CS comparison at line 64; `R/power/run_estimators.R:1145-1193`; standalone implementation `analysis/main/lpdid_statepanel.R:191,254-262`
- **Severity:** CRITICAL
- **Problem:** `event_clean` uses true calendar indices, but its power-stack difference is `Y[, far] - B[, launch]`. It checks that the pre-launch baseline months and terminal outcome exist; it does not check whether omitted COVID months fall between them. A baseline before March 2020 and an outcome after July 2021 therefore remains in the stack. The standalone real-data script computes a `straddles` flag and can drop such rows, but `DROP_STRADDLING` defaults to `FALSE`; the power framework has no corresponding exclusion in this code path. Thus the memo's statement that any comparison touching or crossing the omitted interval is dropped is not implemented and cannot support LP-DiD's claimed advantage over CS.
- **Suggested fix:** Remove the claim from the boss explanation unless the exact run explicitly activates and calibrates cross-gap exclusion. Distinguish correctly between calendar indexing, which prevents row-adjacency mistakes, and an explicit no-straddling eligibility rule, which is a separate restriction.

##### Issue 2.3: The exact pooled estimand is unspecified
- **Location:** Memo lines 24--36 and 82--88; `R/power/run_estimators.R:989-1019,1095-1107`; `ESTIMATOR_MATRIX.md:13-26`
- **Severity:** MAJOR
- **Problem:** LP-DiD is not one pooled parameter here. EWATT gives treated-state-cell weighting and, only with first-lag differencing, aligns with CS's point estimand; VWATT weights cells by treatment variance and delivers the tighter live shift12 MDE. The mature config uses a three-month pre-launch mean unless overridden, so its default EWATT is not CS-equivalent. The memo describes one preferred estimator without choosing or explaining the aggregation weights.
- **Suggested fix:** Name the exact primary weighting rule and finite-sample target. For a boss, one sentence is enough: either each supported treated state-horizon receives treated-unit weight (EWATT), or cells with more identifying variance receive more weight (VWATT). Do not borrow the CS-equivalence interpretation for PMD greater than one.

##### Issue 2.4: Parallel-change assumptions for the exact long horizons are omitted
- **Location:** Memo lines 24--36, 38--48, 82--90
- **Severity:** MAJOR
- **Problem:** Clean controls prevent forbidden comparisons, but they do not establish the counterfactual. For every maturity cohort and horizon, LP-DiD assumes that absent the exposure, the treated state's change from its pre-launch baseline to the mature outcome would match the changing clean-control pool. At horizons 12--24 months after maturity, these are long differences, often with changing treated and control composition. No pretrend, support, or placebo evidence exists for the exact `ramp75 + event_clean + h=12..24` design.
- **Suggested fix:** Add a concise qualification that LP-DiD makes the desired comparison transparently but still relies on cohort-horizon parallel changes. Require exact-design support tables and blinded placebo/pretrend diagnostics before causal interpretation.

##### Issue 2.5: The Ohio example is correct but narrower than the pooled design
- **Location:** Memo lines 40--48; `data/processed/ramp75_schedule.csv:34`; `data/processed/state_panel_coverage_qa.csv`; `data/raw/state_month_panel_with_treatment.csv`
- **Severity:** MINOR
- **Problem:** Ohio's January 2023 launch, November 2023 75% crossing, October--December 2022 baseline, and November 2024 first eligible outcome are correctly stated. Alaska, Georgia, Texas, and Utah are observed, stable-basket, unlaunched controls for those endpoints. But this is one supported h=12 cell; Ohio does not support the full h=12--24 window under a December 2024 analysis cutoff. The actual configured outcome is log-transformed filings, not a raw-count difference.
- **Suggested fix:** Label it explicitly as the first supported Ohio cell and say the regression compares changes in log filings. Do not imply that all listed controls or Ohio itself contribute at every pooled horizon.

### Sanity Check
- **Sign:** Not assessable without disclosing real-data estimates, consistent with the user's request.
- **Magnitude:** Not assessable for the unrun event-clean maturity design. Live MDEs belong to the earlier shift12/event specification and cannot be transferred.
- **Dynamics:** Not assessable for the exact design. First-crossing Handle dates are seasonal and may not mark a stable mature regime.
- **Consistency:** The clean-control logic is internally coherent, but the causal interpretation conflicts with the repository's accepted Handle-threshold guidance, and the COVID claim conflicts with the implemented stack.

## Phase 3: Inference
### Issues Found: 2

The Phase 2 issues must be resolved before these inference comparisons become decisive.

##### Issue 3.1: “Size-valid track record” omits the diagnosed null-centering problem
- **Location:** Memo lines 36, 60, 84--88; `FINDINGS.md:31`; `ESTIMATOR_MATRIX.md:28-38,117`
- **Severity:** MAJOR
- **Problem:** The live shift12 wild arms pass rejection-rate gates, but every state estimator has positive null bias. VWATT's mean null estimate is +0.042, 1.06 simulation SDs and roughly 48% of its reported MDE. Wild inference recenters under the null, so correct rejection frequency does not make the simulated point estimator centered. The open recentering decision is expected to change the MDE ranking and may reverse VWATT versus EWATT. Calling the evidence simply “promising, size-valid” is incomplete.
- **Suggested fix:** Say that wild inference controlled false positives in the earlier shift12 exercise, while point-estimate centering and MDE recalculation remain unresolved. Do not present the current sensitivity ranking as settled.

##### Issue 3.2: The exact event-clean wild procedure has not passed its own gate
- **Location:** Memo lines 36, 82--90; `RUN_LEDGER.md:41,122-133`; `config/power_lpdid_ramp75_mde.yml:62-66`
- **Severity:** MAJOR
- **Problem:** The live EWATT and VWATT shift12 runs used the legacy `event` anchor. Today's default is `event_clean`, with a pre-launch baseline, maturity-relative horizons, and different support. No completed, current, NV-free, correctly weighted size/power run validates that procedure. Wild bootstrap is appropriate to test, but its reliability is not inherited automatically when the stack, leverage, cohorts, and horizons change.
- **Suggested fix:** Make the recommendation explicitly provisional pending the exact `ramp75/event_clean/h=12..24` null gate, power run, contributor counts, and leverage diagnostics. Do not call it the final empirical specification before those checks pass.

## Phase 4: Robustness, Alternatives, Feasibility, and Power
### Issues Found: 3

These points are lower priority than the identification failures above.

##### Issue 4.1: “Why the alternatives do not work” should remain design-specific
- **Location:** Memo lines 50--80
- **Severity:** MINOR
- **Problem:** The memo mostly handles this well, but several calibration findings are estimator-by-sample-by-inference results, not universal estimator failures. TWFE is size-valid in the live state shift12 design; CS is calibrated on the clean post-COVID monthly state panel; `did2s` is calibrated in one county harness but fails the blinded state designs; LDAM with jackknife passes its state gates. A boss could otherwise hear that the methods themselves are broken.
- **Suggested fix:** Preserve the memo's opening qualification and use “not preferred for this estimand and sample” consistently. Separate wrong target, failed exact-sample calibration, and incomplete evaluation.

##### Issue 4.2: The long-difference evidence explains low power, not the realized zero estimate
- **Location:** Memo lines 54--56; `ESTIMATOR_MATRIX.md:104-107`
- **Severity:** MINOR
- **Problem:** The live annual 2x2 diagnostic supports an approximately 27% MDE and therefore weak sensitivity. It does not establish that heterogeneity cancellation caused the user's realized near-zero coefficient, and it uses a distinct annual county-court design. Cancellation is a plausible mechanism, not a demonstrated diagnosis.
- **Suggested fix:** Phrase cancellation and buildup mixing as reasons the estimands can differ, while citing the 27% diagnostic only as evidence of low power.

##### Issue 4.3: LDAM remains an unresolved competitor
- **Location:** Memo lines 78--80; `ESTIMATOR_MATRIX.md:23,111`
- **Severity:** MAJOR
- **Problem:** The memo correctly notes that LDAM jackknife passes size but lacks an MDE. Under the project's size-first rule, LP-DiD cannot be declared uniquely preferred on power until that gap is closed, especially because the current LP-DiD MDEs face recentering. LDAM also lacks the requested mature-period implementation, so neither method has completed the exact contest.
- **Suggested fix:** Describe LP-DiD as the leading design candidate because it directly encodes the desired comparison, not as the settled winner of a completed estimator tournament.

## Summary
- **Overall assessment:** CRITICAL ERRORS
- **Critical issues (must fix):** 2
- **Major issues (should fix):** 6
- **Minor issues (consider):** 3

## Priority Recommendations
1. **[CRITICAL]** Remove the claim that a realized 75%-of-peak clock identifies the legalization ATT; label it an exposure-timed exploratory contrast unless stronger assumptions are defended.
2. **[CRITICAL]** Correct the COVID-gap statement: current power code does not automatically drop long differences whose endpoints straddle the omitted interval.
3. **[MAJOR]** Present LP-DiD as a provisional leading candidate pending exact event-clean size/power calibration, null-bias handling, and the unresolved LDAM comparison.
4. **[MAJOR]** Choose and explain EWATT versus VWATT and state the cohort-horizon parallel-change assumption.
5. **[MINOR]** Keep the verified Ohio example, but label it an h=12 log-filings cell rather than the entire pooled design.

## Positive Findings
- The memo correctly separates the existing shift12 calibration from the not-yet-run event-clean maturity design; that is essential and should remain prominent.
- The clean-control implementation is accurately explained: launched buildup states are excluded rather than mislabeled as untreated, and treated and control units share the same pre-launch baseline and outcome endpoints.
- The Ohio dates and the Alaska, Georgia, Texas, and Utah control examples are verified against the current schedules, panel, and stable-basket coverage audit.
- The alternatives section is unusually careful not to call every competing estimator intrinsically invalid; it correctly distinguishes target mismatch, calibration failure, and incomplete evidence in most cases.
