# Code Audit — Handle/Legalization Cohort Support
**Date:** 2026-08-14  
**Reviewer:** coder-critic  
**Paper type:** Reduced-form  
**Score:** 88/100  
**Mode:** Full diagnostic review

## Code-Strategy Alignment: MATCH FOR SUPPORT / PRODUCTION DEVIATION

The diagnostic implements the stated task: it compares updated online dates with Handle-50 timing across the all-39, balanced-26, and legacy-24 samples and computes descriptive CS and SA support. It does **not** estimate CS or SA, and the summary says so explicitly (`results_summary.md:79`).

The production post-COVID runner is not aligned with the Handle estimand. `scripts/run_pretrends_pre_post_covid.sh:46-52` passes the Handle panel but does not set `TREAT_SOURCE=panel`; `scripts/run_pretrends_statepanel.sh:23-25` therefore defaults to the legalization file and `online_start_date`. The data profile correctly flags this at `quality_reports/handle_cohort_support_data_profile.md:107-116`. Consequently, the Handle update currently changes the support audit but **does not change the default CS/SA run**. This is a release blocker for re-estimation, but it is outside the reviewed diagnostic script's ownership and is not scored as a defect in that script.

## Paper-to-Code Map: PRESENT

The map is present at `analysis/diagnostics/handle_legalization_cohort_support.R:40-49` and in the generated summary at `results_summary.md:81-89`.

## Sanity Checks: PASS WITH CONCERNS

- Rerun completed successfully and regenerated fresh outputs.
- Verified sample counts: 39 raw-window states; 26 states x 91 common observed months = 2,366 observations; legacy 24 states = 2,184 observations.
- Verified balanced-26 monthly cohorts: online 17 treated / 16 cohorts / 15 singletons; Handle-50 16 treated / 13 cohorts / 11 singletons / largest cohort 3.
- Verified all-39 monthly cohorts: online 23 treated / 21 cohorts; Handle-50 22 treated / 18 cohorts.
- Verified CS support: 521/521 online and 376/376 Handle-50 post-treatment cells have a treated observation and at least one not-yet/never control. This is existence support, not an inference calibration result.
- Verified SA tails: fewer than five contributing treated states first occurs at e=48 online and e=39 Handle-50; last horizons with at least five are e=47 and e=38.
- Verified Florida: online date 2023-12, no LSR rows, Handle-50 missing. The summary correctly warns that Florida is not a clean never-treated control (`results_summary.md:42`).
- Verified the deleted COVID gap: online cohorts TN 2020-11 and VA 2021-01 fall in it; Handle-50 cohorts WV 2020-08, PA 2020-10, and IN 2020-12 fall in it.

## Numerical Discipline: CONCERNS

The numerical calculations are guarded appropriately for this deterministic descriptive task: integer indexing uses `seq_len()`, the availability matrix is preallocated, no float equality is used, and CDF/inverse-link guards are not applicable. However, six result lists are initialized empty and grown inside nested loops at `analysis/diagnostics/handle_legalization_cohort_support.R:578-617`, violating **INV-17**.

## Robustness: COMPLETE FOR THE REQUESTED SUPPORT AUDIT

The requested 39/26/24 samples, monthly/annual grain, alternative dates, both CS control definitions, and SA event-time counts are present. These are support diagnostics only; they do not establish estimator bias, standard-error calibration, or coverage. The reports maintain that distinction.

## Code Quality (12 categories)

| Category | Status | Issues |
|----------|--------|--------|
| Project layout | OK | Diagnostic is placed under `analysis/diagnostics/`; outputs are under `output/handle_cohort_support/`, satisfying **INV-18**. |
| Script headers | OK | Purpose, inputs, outputs, and paper context are documented at lines 1-8. |
| Console output | OK | Clean `message()` completion output; linter reported zero issues. |
| Reproducibility | WARN | Script reruns successfully and creates output directories. Paths are relative, but they are raw strings rather than `here()` paths at lines 21-29, a strict **INV-16** portability shortfall. The single seed at lines 16-17 satisfies **INV-14**, although no stochastic operation is present. Packages are loaded first, satisfying **INV-15**. |
| Numerical discipline | WARN | Empty lists are grown in loops, violating **INV-17**. No unsafe float, CDF, inverse-link, NaN/Inf, or `1:n` pattern was found. |
| Function design | WARN | Functions are sensibly named and return named tibbles, but non-trivial helpers lack Roxygen documentation and input preconditions. `period_table()` and `panel_availability()` silently treat any non-`"monthly"` grain as annual (`lines 86-116`). |
| Figure quality | N/A | No figures are produced; **INV-12** is not applicable. |
| Table quality | N/A | Markdown diagnostic tables only; no LaTeX table export, so **INV-13** is not applicable. |
| RDS/checkpoint | OK | All 12 CSV objects have paired RDS files; panels, schedules, activity checks, and the combined diagnostic are also saved. |
| Comment quality | OK | Comments explain sample construction and estimator support logic; no dead blocks found. |
| Error handling | WARN | Required-file, duplicate-key, schedule-duplicate, activity-date agreement, and exact-sample checks are present. Helper-level column/type/grain preconditions are missing. |
| Prohibited patterns | OK | No `setwd()`, `rm(list=ls())`, `install.packages()`, `attach()`/`detach()`, or global assignment; satisfies **INV-19**. |

## Data Cleaning / Support Construction

- The all-39 panel is explicitly described as unbalanced; the balanced-26 and legacy-24 claims are not conflated with it.
- CS control logic at `analysis/diagnostics/handle_legalization_cohort_support.R:315-344` correctly defines never-treated controls and not-yet-treated-plus-never controls at calendar t, conditional on observed baseline and outcome periods.
- SA support at lines 375-413 correctly counts distinct contributing treated states and cohorts by event time. These counts are descriptive availability, not proof that every interaction survives regression collinearity or that clustered inference is calibrated.
- The data profile's post-COVID 30-state counts are correct, but they are an independent profile rather than outputs from this script. Preserve that scope distinction when citing them.

## Score Breakdown

- Starting: 100
- Growing result lists in nested loops; violates **INV-17**: -5
- Missing preconditions on non-trivial helper functions: -5
- Relative paths are not constructed via `here()`; strict **INV-16** shortfall: -2
- **Final: 88/100**

## Recommendation

**Accept the support diagnostic and its headline conclusion:** updated Handle timing provides modest pooling but does not solve the small-cohort problem. Before any Handle-based CS/SA re-estimation, fix or explicitly override the production treatment-source routing and prevent missing Handle measurement (especially Florida, and Nevada in the post-COVID sample) from being silently interpreted as never treated. Continue to describe 521/521 and 376/376 as formal cell existence—not estimator performance.

## Escalation Status: None
