# Review — Handle Maturity Results Summary

**Date:** 2026-08-20  
**Reviewer:** coder-critic  
**Paper type:** Reduced-form  
**Score:** 98/100  
**Verdict:** VERIFIED. The revision resolves all substantive factual and causal-interpretation findings. The only remaining deduction is the producer script's pre-existing INV-16 path-style violation.

## Revision verification

- **Peak denominator resolved:** lines 39–45 now correctly state that the frozen December-2024 peak excludes March 2020–July 2021, while threshold crossings search the full sequence.
- **West Virginia sensitivity resolved:** lines 19–23 disclose that the broader COVID exclusion moves West Virginia's 50% crossing from August 2020 to January 2020 and condition the headline claim on the default calibration.
- **Attenuation claim resolved:** lines 25–35 distinguish the legal-access ITT from a mature-market estimand and state the additional assumptions needed to predict the direction of the difference.
- **Threshold contamination resolved:** lines 102–110 explicitly identify realized Handle as endogenous and explain why legally treated, sub-threshold observations are contaminated controls.
- **Roster, dates, lags, cutoff, and right-censoring:** remain verified against both supplied CSVs.

## Findings

### 1. Major — The report misstates the denominator used for the 50%/75% dates

Lines 27–28 say the denominator is each state's maximum nominal monthly Handle observed through December 2024. The producer script instead computes the peak after excluding March 2020 through July 2021 (`create_activity_treatment_dates.R`, lines 155–156), while allowing threshold crossings to occur in those excluded months (line 202 passes the full calibration data). The report must describe this as a **December-2024-frozen, COVID-window-excluded peak**, not the unrestricted observed maximum.

This is substantively important for the user's exact concern. Under the project-default exclusion, West Virginia reaches 50% in August 2020 (lag 24), as reported. Under the supporting profile's broader March 2020–March 2022 exclusion, its peak falls from $88.19m to $72.95m and its first 50% crossing moves to January 2020 (lag 17). Thus “only Rhode Island reached 50% before March 2020” is true under the primary/default calibration, but not robust to the alternative peak definition already present in the supporting CSV. The other reported early-state 50%/75% dates are unchanged across those two profile definitions.

**Resolution status:** Resolved in revised lines 11–23 and 39–45. No deduction.

### 2. State roster and arithmetic — Verified

The table's 22 states, online-launch dates, first 50%/75% dates, and launch-to-threshold calendar-month lags exactly match `activity_treatment_dates.csv` for analysis-eligible states with observed Handle. Florida is correctly identified as online-treated with missing Handle; Missouri's December 2025 launch is correctly outside the cutoff. Iowa, Illinois, Michigan, New Jersey, Oregon, Wyoming, and DC appear in the broader supporting profile but are correctly omitted because they are outside the estimator-ready eviction frame.

The right-censoring warning is also correct: the frozen denominator is not a lifetime peak, and late-launch states have short support. First crossing is additionally a weak proxy for “maturity” because nominal monthly Handle is seasonal and can fall back below the threshold. A sustained or rolling-average threshold is more descriptively informative, though still not an exogenous treatment date.

### 3. Causal interpretation — Mostly correct, with one necessary qualification

The strongest sentence in the report is lines 21–23: a smaller launch-date estimate is **not attenuation bias relative to the legal-access ITT**. It is an estimand mismatch if the scientific target is a mature/high-volume market effect. Regime-specific LP-DiD can identify:

- pre-COVID launch responses for the five early cohorts, over horizons that remain pre-COVID; and
- post-COVID launch responses for later switchers.

It cannot identify the mature post-COVID effect for the early cohorts without reintroducing a cross-COVID counterfactual. Nor can the later-launch estimates automatically stand in for early adopters' mature effects, because cohort composition, regulation, and market structure differ.

The revision now states the additional conditions and correctly avoids predicting attenuation without them. **Resolution status:** Resolved. No deduction.

### 4. Realized Handle thresholds are not a causal fix

Lines 87–98 correctly call 50%/75% analyses exploratory and flag endogeneity. The problem is even stronger than the report states: states below their own realized threshold are already legally treated and have positive betting. Reclassifying them as untreated until crossing therefore changes treatment to a post-treatment mediator and makes “not-yet-threshold” observations contaminated controls unless one assumes exactly zero effect below the cutoff. Crossing time also responds to state demand, regulation, competition, and macroeconomic conditions that may directly predict evictions.

Accordingly, threshold-timed LP-DiD should not be presented as identifying a mature-market causal effect. A pre-specified lag or leave-one-state-out prediction is safer as an exploratory timing rule, but it still answers a different cohort-weighted estimand and needs its own support table and pretrend assessment. **Resolution status:** Resolved in revised lines 102–118. No deduction.

### 5. Content invariants INV-13–INV-19

- INV-13, INV-14, INV-17, INV-18, and INV-19: no applicable violation in the reviewed markdown/CSV deliverable; no stochastic computation or LaTeX table export is part of this report.
- INV-15: the producer script loads packages before data work.
- The producer script uses raw project-relative strings and `file.path()` rather than `here()` (`create_activity_treatment_dates.R`, lines 27–49 and 58), which violates the project's strict **INV-16** path rule even though the paths are not absolute. Deduction: **−2**.

## Score breakdown

- Starting: 100
- Peak denominator and West Virginia sensitivity: resolved, 0
- Conditions for attenuation interpretation: resolved, 0
- Threshold-control contamination: resolved, 0
- Producer-path noncompliance (INV-16): −2
- **Final: 98/100**

## Bottom line for the user

The concern is real, but the precise conclusion is: **pre-COVID LP-DiD estimates the early legal-access ramp, not mature exposure; it is not statistically attenuated relative to its own ITT estimand.** Separate regimes solve cross-COVID comparisons, not maturation. Keep launch-date LP-DiD primary, report cohort/horizon Handle exposure alongside it, and treat any realized-Handle threshold design as descriptive or exploratory rather than a causal repair.
