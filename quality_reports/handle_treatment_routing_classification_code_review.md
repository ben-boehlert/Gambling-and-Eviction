# Code Audit — Handle Treatment Classification and Routing
**Date:** 2026-08-14  
**Reviewer:** coder-critic  
**Paper type:** Reduced-form  
**Score:** 88/100  
**Mode:** Full

## Code-Strategy Alignment: MATCH

The completed change implements the requested Handle-50 estimand consistently:

- Treatment is the first online-era month at which total reported Handle reaches
  50% of the state's non-COVID peak, with the peak and threshold search frozen at
  2024-12-31.
- Florida is treated online but has no observed LSR Handle and is excluded as
  `legally_online_missing_handle`, rather than interpreted as untreated.
- Nevada is excluded as `pre_sample_treated`.
- Missouri's online date is 2025-12-01, so it is a valid not-yet-treated control
  for the prespecified through-2024 analysis.
- The post-COVID runner explicitly requires `TREAT_SOURCE=panel`; both the shell
  and R entry points reject a conflicting source contract.
- The pre-COVID default continues to resolve `online_start_date` from the legal
  schedule file.

Excluding Florida is appropriate for the complete-case Handle-exposure estimand,
but it changes the target population and should not be described as estimating
Florida's effect. Excluding Nevada is necessary because it was already exposed
before the study window. Neither exclusion is appropriate for a separate legal-
access intent-to-treat estimand; that specification should continue to use the
legal schedule.

## Paper-to-Code Map: PRESENT

The diagnostic includes a formal notation map at
`analysis/diagnostics/handle_legalization_cohort_support.R:42-50`. The state
classification codebook provides the data-level map for status, eligibility,
threshold date, and estimator treatment date.

## Sanity Checks: PASS

Independent regeneration to a temporary directory produced the following exact
matches:

- Both builders' 39-row classifications agree on all values.
- The regenerated classification and estimator panel agree with the committed
  production CSVs.
- Source panel: 4,120 rows and 39 states.
- Estimator-ready Handle panel: 3,884 rows and 37 states.
- Treatment composition: 22 treated states and 15 eligible controls.
- Exact removals: Florida, 165 rows; Nevada, 71 rows.
- No duplicate state-month keys, infinite numeric values, or state-varying
  classification fields were found.
- All Handle threshold dates are on or after legal online launch.

State-specific assertions passed:

| State | Classification | Control eligible | Analysis eligible |
|---|---|---:|---:|
| FL | `legally_online_missing_handle` | false | false |
| NV | `pre_sample_treated` | false | false |
| MO | `not_yet_online_after_cutoff` | true | true |

The refreshed production post-COVID run is internally consistent and fresh:

- `panel_summary.csv`: 28 states, 18 treated, 10 controls, 15 cohorts,
  33 months, and 924 observations.
- Treatment source is `panel`; expected source is `panel`; required-panel flag
  is true; resolved date column is `treat_start`.
- `treatment_schedule_resolved.csv` and `.rds` contain the same 28-state
  schedule, 18 treatment dates, no Florida or Nevada, and
  `resolved_matches_panel = TRUE` for every state.

A separate pre-COVID smoke test resolved the treatment source to `file` and the
date column to `online_start_date`, confirming that the legal-date path remains
unchanged.

The refreshed support diagnostic also matches the requested numbers for the
balanced Handle-eligible subset: 25 states, 16 treated, 9 controls, 13 monthly
cohorts, 11 singleton cohorts, and a largest cohort of 3.

## Numerical Discipline: CONCERNS

The treatment calculation has appropriate finite-value and date-order guards,
uses `seq_len()` in the Handle-date print loop, and performs no unsafe floating-
point equality, CDF, or inverse-link operation. The formerly brittle
`2:length(...)` merges have been replaced by `Reduce()` at
`analysis/data_prep/create_activity_treatment_dates.R:206-209` and `:245-248`.
One quality issue remains:

- `analysis/diagnostics/handle_legalization_cohort_support.R:685-741` grows six
  result lists inside nested loops, violating **INV-17**.

## Robustness: COMPLETE FOR THE REQUESTED FIX

`scripts/test_pretrends_treatment_routing.sh` passed all three routing arms:

1. Static verification that the post-COVID Handle runner requests panel dates.
2. Negative shell and direct-R tests that reject file/panel source mismatches.
3. Positive end-to-end smoke test that exports an auditable resolved schedule.

The independent builder rerun, production-output audit, legal-date regression
test, and cohort-support checks cover the failure modes identified in the prior
review. No treatment-routing or control-classification release blocker remains.

## Code Quality (12 categories)

| Category | Status | Issues |
|---|---|---|
| Project layout | OK | Files are in the established `data_prep/`, `analysis/`, `scripts/`, `data/processed/`, `output/`, and `quality_reports/` locations. |
| Script headers | OK | The builders, runner, test, and diagnostic document purpose, inputs, outputs, and execution context. |
| Console output | WARN | The builders use extensive `cat()`/`print()` status output and decorative banners, e.g. `build_panel_handle50_treatment.R:89-91` and `create_activity_treatment_dates.R:68-71`, instead of `message()`. |
| Reproducibility | WARN | Regeneration is deterministic and tests pass. Raw relative path strings are used rather than `here()`, a strict **INV-16** shortfall. The optional self-test calls `set.seed()` at `pretrends_statepanel_template.R:684` and `:751`, rather than exactly once at main-script setup, violating strict **INV-14**, although its pre-generated per-replication seeds make the current simulation reproducible. Packages are loaded first, satisfying **INV-15**. |
| Numerical discipline | WARN | Growing lists in the cohort diagnostic violate **INV-17**. The data builders' list merges are now functional `Reduce()` calls. Current treatment outputs contain no Inf values or unsafe threshold comparisons. |
| Function design | OK | `classify_handle_states()` has clear inputs, preconditions, named columns, and business-logic guards. No global assignment is used. |
| Figure quality | WARN | Existing diagnostic figures use titles inside ggplot, a non-serif minimal theme, and PNG-only export at `pretrends_statepanel_template.R:1139-1255`. This is acceptable for diagnostics but not publication-ready. |
| Table quality | N/A | No LaTeX tables are generated, so **INV-13** is not applicable. |
| RDS/checkpoint | OK | Paired RDS checkpoints now exist for the activity table, state classification, codebook, and estimator panel (`build_panel_handle50_treatment.R:197-202,246-248`; `create_activity_treatment_dates.R:408-415`). Independent reads verify that every CSV/RDS pair has identical values. The estimator panel's all-missing `exclusion_reason` is inferred as logical by CSV import while the RDS correctly preserves its character type. |
| Comment quality | OK | Comments explain why Florida, Nevada, retail-era Handle, and the frozen peak cutoff require special handling. No dead treatment-routing block was found. |
| Error handling | WARN | Source contracts, state-constant dates, excluded states, invalid controls, duplicate keys, and builder disagreement are guarded. `create_activity_treatment_dates.R:405` creates the hard-coded `data/processed` directory rather than `dirname(OUTPUT_FILE)`, so a custom output path fails unless its directory already exists. |
| Prohibited patterns | OK | No `setwd()`, `rm(list = ls())`, `install.packages()`, `attach()`/`detach()`, or `<<-` occurs; satisfies **INV-19**. Outputs comply with **INV-18**. |

## Data Cleaning (Stage 0)

- State retention is 37/39 (94.9%); row retention is 3,884/4,120 (94.3%).
- Every dropped state and row count is documented.
- Missing Handle exposure is explicitly distinguished from untreated exposure.
- State classification and panel metadata agree exactly.
- The two independent treatment builders agree.
- `control_eligible` is true only for the 14 never-online states and Missouri's
  after-cutoff launch.

The activity builder's coverage row now reports `Legal online by cutoff` and
correctly limits the count to 23 states through 2024 at
`analysis/data_prep/create_activity_treatment_dates.R:375-389`.

The diagnostic now saves the 25-state current Handle-eligible panel as
`analysis_panel_current_exact_handle_eligible_25.rds` at
`analysis/diagnostics/handle_legalization_cohort_support.R:858-861`. The stale
`_24.rds` artifact is absent.

## Score Breakdown

- Starting: 100
- Growing lists in nested diagnostic loops; violates **INV-17**: -5
- Console output pollution: -3
- Multiple self-test seed calls rather than one main-script seed; strict
  **INV-14** violation: -2
- Paths are relative but not routed through `here()`; strict **INV-16**
  shortfall: -2
- **Final: 88/100**

## Recommendation

**ACCEPT the requested data and routing fix.** The estimator input is correctly
classified, the Handle runner uses the intended dates, both mismatch guards work,
production outputs are fresh, every requested data artifact has a paired RDS
checkpoint, and the stale support artifact has been removed. Remaining deductions
are limited to pre-existing/general code-quality debt in the broader diagnostic
pipeline: list preallocation, console output, seed placement, and strict `here()`
path discipline. None changes the verified treatment dates or control pool.

## Escalation Status: None
