# Code Audit — Post-COVID Handle-Ramp Support

**Date:** 2026-08-14  
**Reviewer:** coder-critic  
**Paper type:** Reduced-form  
**Score:** 87/100  
**Mode:** Full  
**Recommendation:** ACCEPT. The corrected comparison language accurately distinguishes the samples and estimands. Remaining engineering issues are non-blocking for this diagnostic.

## Code-Strategy Alignment: MATCH

The diagnostic correctly analyzes a coherent market-maturation estimand on the common Handle-measurement sample. The script loads the Handle-eligible panel at `analysis/diagnostics/postcovid_handle_ramp_support.R:28-37` and explicitly requires Florida and Nevada to be absent at `analysis/diagnostics/postcovid_handle_ramp_support.R:101-113`. That produces the common-sample legal baseline of 7 treated states in 6 cohorts.

Independent reconstruction from `data/raw/state_month_panel_with_treatment.csv` finds 30 states with complete April 2022–December 2024 outcomes. Nevada is correctly removed as pre-sample treated, but Florida is balanced and legalized online in December 2023. The full legal-date ITT comparison therefore has **8 treated states in 7 cohorts**, including Florida. The Handle-25 design has 8 treated states in 6 cohorts after Florida is removed and Arkansas is moved into the treatment set. Relative to the full legal-date main design, Arkansas does not increase treated-state N; it swaps composition.

The correction now states all of this explicitly at `output/postcovid_handle_ramp_support/results_summary.md:7,13-23,47-53` and in the generating code at `analysis/diagnostics/postcovid_handle_ramp_support.R:520-527,540-557,590-604`. It labels the table's increment “vs common-sample legal,” identifies full legal ITT as 8/7 including Florida, identifies common-sample legal as 7/6, and identifies Handle-25 as 8/6 after Arkansas replaces Florida. It also correctly rejects a hybrid design retaining Florida at its legal date and assigning Arkansas a Handle threshold because that design would mix treatment clocks and estimands.

## Paper-to-Code Map: PRESENT

The map at `analysis/diagnostics/postcovid_handle_ramp_support.R:61-74` and `output/postcovid_handle_ramp_support/results_summary.md:61-71` is clear and consistent.

## Sanity Checks: CONCERNS

The following quantities were independently reproduced:

- The common Handle panel contains 28 balanced states with 33 observations each from April 2022 through December 2024.
- Florida is `legally_online_missing_handle` and Nevada is `pre_sample_treated`; both are correctly excluded from the Handle panel.
- On that common sample, online legalization yields 7 treated states, 6 cohorts, 5 singleton cohorts, 120 post-treatment CS group-time cells, a minimum of 10 eligible controls, 5 treated states at SA event month +12, and 2 at +24.
- Arkansas legalized online in March 2022. Its frozen peak is $66,058,203 in November 2024; April 2022 Handle is $8,598,226, or 13.016% of peak. Its first 25%, 50%, 75%, and sustained-50% dates are September 2022, March 2023, November 2023, and September 2023.
- Coherent activity-clock counts are correct: 25% = 8 states/6 cohorts/4 singleton cohorts; 50% = 8/7/6; 75% = 13/8/5; sustained 50% = 8/8/8.
- CS cells all retain controls and all attach to cohorts smaller than five. SA +12/+24 support is 6/3 at 25%, 6/2 at 50%, 11/1 at 75%, and 6/2 at sustained 50%.
- Candidate coverage statements are correct: DC, Oregon, Wyoming, and Illinois are unavailable in the eviction panel; North Carolina has no post-March-2024 outcome observations.
- Broadening the excluded COVID peak-calibration window through March 2022 leaves every candidate and candidate date unchanged. Only West Virginia's peak and early 25%/50% dates change, all before the analysis window.

The substantive concern is identification, not arithmetic. Arkansas already had positive legal betting throughout April–August 2022. Redating it to September treats exposed months as pre-treatment and requires no effect below an arbitrary, future-peak-normalized 25% threshold. September is also the football-season Handle jump, so the date is not independent of seasonality. The corrected summary now calls this only a “plausible exploratory sensitivity” and an “exploratory different-estimand sensitivity” at `output/postcovid_handle_ramp_support/results_summary.md:7`, and repeats that it is an endogenous market-maturation estimand rather than legal-ATT robustness at lines 47–59. The data profile makes the same distinction at `quality_reports/postcovid_ramp_candidate_data_profile.md:24-27,80-95,116-133`. This language is accepted. The remaining table label “B: useful sensitivity” and phrase “meaningful robustness range” in the profile should still be read subject to those explicit qualifications, but they no longer create a material ambiguity.

## Numerical Discipline: CONCERNS

Date arithmetic, finite-peak checks, consecutive-month guards, integer loop indices, and pre-allocation inside the support function are sound. There are no float-equality comparisons, inverse-link operations, CDF operations, or unguarded numerical estimators.

The main script initializes `diagnostics <- list()` and grows it inside nested loops at `analysis/diagnostics/postcovid_handle_ramp_support.R:246-266`. This violates **INV-17**. The final size is known (`length(sample_states) * length(design_columns)`), so the list must be pre-allocated.

## Robustness: Incomplete

The narrow-versus-broad COVID peak calibration is well documented and numerically supported in `output/postcovid_ramp_candidates/`, but no checked-in script generates those artifacts. The main diagnostic implements only the project-default March 2020–July 2021 exclusion at `analysis/diagnostics/postcovid_handle_ramp_support.R:22-23,160-163`. The profile's reproducibility section lists outputs rather than executable provenance at `quality_reports/postcovid_ramp_candidate_data_profile.md:134-147`. This prevents an independent clean rebuild of the broad-window result.

## Code Quality (12 categories)

| Category | Status | Issues |
|----------|--------|--------|
| Project layout | WARN | The main script and function are sensibly separated, but there is no numbered master-stage integration or test file. |
| Script headers | OK | Purpose, inputs, outputs, and paper role are documented. |
| Console output | OK | Uses `message()` and has no decorative banners or workspace clearing. |
| Reproducibility | WARN | Main diagnostic is reproducible; the separate candidate-profile and broad-COVID outputs lack a checked-in generator. |
| Numerical discipline | WARN | Core guards pass; the diagnostics result list grows in a loop, violating INV-17. |
| Function design | OK | Snake-case name, Roxygen documentation, preconditions, named return list, and no global assignment. |
| Figure quality | WARN | The diagnostic figure has a title and subtitle inside ggplot and is PNG-only at `analysis/diagnostics/postcovid_handle_ramp_support.R:433-455`; this is unsuitable as a paper figure and conflicts with INV-12, although it is acceptable as an internal diagnostic. |
| Table quality | OK | No LaTeX tables are emitted; **INV-13** is not implicated. Markdown tables are diagnostic outputs. |
| RDS/checkpoint | OK | Every exported diagnostic table has CSV and RDS forms; the full diagnostics list and figure object are checkpointed. |
| Comment quality | OK | Comments explain the diagnostic stages and the paper-to-code link. |
| Error handling | WARN | Input existence, dimensions, duplicate state-months, exclusions, finite peaks, and threshold ordering are checked. Balance is based on row presence only; the script does not assert nonmissing `filings_count`, although the current 28 states pass that check. |
| Prohibited patterns | OK | No `setwd()`, absolute paths, `rm(list=ls())`, `attach()`, `detach()`, `<<-`, `sapply()`, or `1:n`. **INV-16** and **INV-19** pass. |

## Content-Invariant Audit

- **INV-13:** Pass/not applicable; no LaTeX wrapper is generated.
- **INV-14:** Pass; `set.seed()` appears exactly once at the top of the main script. The analysis is deterministic, so the seed is harmless.
- **INV-15:** Pass; all packages are loaded before data work.
- **INV-16:** Pass; project paths use `here()` and function output paths derive from that root.
- **INV-17:** **Fail**; `diagnostics` is grown in a nested loop.
- **INV-18:** Pass; diagnostic outputs are written under `output/postcovid_handle_ramp_support/`.
- **INV-19:** Pass; no prohibited functions are present.

## Data Cleaning (Stage 0)

The 28-state common sample and exclusions are traceable and have no duplicate state-months. Current balanced states have complete `filings_count` observations. The data profile correctly distinguishes panel absence from incomplete post-treatment coverage. The corrected summary and profile now label the 28-state sample as **Handle-measurement common support** and separately state the full legal-date benchmark.

## Score Breakdown

- Starting: 100
- Broad-COVID/candidate-profile artifacts have no checked-in generator: −5
- Growing diagnostics list in loops, violating INV-17: −5
- Paper-incompatible title/subtitle and PNG-only figure: −3
- **Final: 87/100**

## Escalation Status: None

The main qualitative conclusion is supported: Handle redating does **not** solve small-cohort inference. On the coherent 25% design, every cohort still has fewer than five states, the largest cohort has two, SA support falls from six states at +12 to three at +24, and the treatment threshold is endogenous. The corrected language no longer presents Arkansas as an incremental-state gain relative to the full legal ITT. Remaining reproducibility and code-quality issues do not change that conclusion.
