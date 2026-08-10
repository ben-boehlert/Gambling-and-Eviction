# Code Audit — Cohort-Specific Long Differences
**Date:** 2026-08-03
**Reviewer:** coder-critic
**Paper type:** Reduced-form
**Score:** 82/100
**Mode:** Full
**Disposition:** PASS — no Critical or Major issues remain

## Resolution history

1. **Critical treatment-timing error — RESOLVED.** The first version read stale panel-embedded `treat_start` dates and labeled first/retail-access cohorts as online cohorts. The current script reads `sports_gambling_legalization_dates.csv::online_start_date` at lines 562–618. The resulting regime audit correctly dates WV 2018-08, PA 2019-05, IN 2019-10, CO 2020-05, TN 2020-11, VA 2021-01, CT 2021-10, NY 2022-01, and AR 2022-03.
2. **Major retail-history estimand problem — RESOLVED WITH AN EXPLICIT CLEAN SENSITIVITY.** The broad primary estimate still mixes retail histories, but the summary now labels that assumption. The new `online_first_clean` specification separately identifies first sports-betting access delivered online using online-first/simultaneous treated states and controls with no first betting launch through the cohort-window endpoint.
3. **Calendar-coverage ambiguity — RESOLVED.** The summary states that the primary 50% rule need not average identical observed months, and a 100% complete-coverage sensitivity is reported.
4. **COVID aggregate flag bug — RESOLVED.** `covid_any` is computed from every included cohort cell, including placebo cells.
5. **Percent-effect overstatement — RESOLVED.** Outputs now call `100 * expm1(ATT)` a transformed long-difference contrast rather than an arithmetic causal percent effect.

## Code-Strategy Alignment: MATCH

The code implements the approved cohort-calendar design:

- exact online-launch cohorts;
- 24-month baseline `g-30:g-7`, preserving a six-month anticipation gap;
- fixed post windows `g:g+11`, `g+12:g+23`, and `g+24:g+35`;
- cohort-specific calendar transformation of comparison states;
- same-county pre/post coverage requirements;
- county-to-state collapse followed by equal-treated-state aggregation;
- never-online primary controls, endpoint-clean not-yet-online robustness, and a clean retail-history specification;
- state-level leave-one-out inference and explicit singleton-cohort caveats.

### Clean retail-history verification

The clean design is correctly parameterized at lines 82–101 and implemented at lines 228–271:

- treated states must have `online_regime == "online_first_or_simultaneous"`;
- controls must satisfy `first_start_date` missing or later than that cohort-window endpoint;
- current-cohort treated states cannot also be controls.

Direct checks on `state_cell_changes.rds` found zero treated-regime violations, zero control endpoint violations, and zero treated/control overlaps. Supported clean treated states are WV, TN, VA, and CT. CO is correctly regime-eligible but excluded for insufficient clean-pre coverage. PA, IN, NY, and AR are correctly classified retail-first and excluded from the clean treated group.

For all three clean post horizons, the reported aggregate uses four treated states. Point estimates are +8.7%, +19.0%, and +29.0%, with wide intervals that all include zero. The clean placebo is −29.4% and also includes zero. The summary appropriately says the four-state design is especially fragile.

## Paper-to-Code Map: PRESENT

The script and `results_summary.md` trace `Y_it`, `G_i`, `DeltaY_i(g,h)`, `ATT(g,h)`, and `ATT(h)` to code objects. `analysis_parameters.rds` records the treatment source, online-date definition, regime definition, and clean-control rule at lines 1013–1033.

## Sanity Checks: PASS WITH CAUTIONS

- Reported summary values match `aggregate_estimates.csv` and `aggregate_estimates.rds`.
- The primary available and common-post estimates coincide because all eight supported primary treated states appear at every post horizon.
- The clean available and common-post estimates also coincide because WV, TN, VA, and CT have all three horizons.
- CO is consistently marked unsupported. The regime audit contains nine online-treated states and correct support flags.
- The panel has no duplicate state/county/month rows. Aggregate estimates, standard errors, intervals, and p-values are finite; all p-values are in `[0,1]`.
- The placebo and clean estimates remain sensitive to CT, and the clean design has only four treated states. These are substantive precision limitations, not implementation errors, and are disclosed.
- The complete-coverage sensitivity can represent NY with one county and CT with four. Cell-level outputs make this visible, though any paper table should report county support.

## Numerical Discipline: PASS WITH MINOR WARNINGS

- P-values are clamped to `[0,1]`; `log1p`/`expm1` are used appropriately; loops use `seq_len`/`seq_along`; and nonfinite estimates are guarded.
- The interval transformation is monotone and numerically correct for the transformed log1p contrast.
- `aggregate_list` and `replicate_list` are still grown inside loops at lines 900–933. This violates **INV-17** but does not affect current numerical results.

## Robustness: COMPLETE FOR THIS EXPLORATORY DESIGN

Implemented checks now include:

- never-online and endpoint-clean not-yet-online controls;
- online-first/simultaneous treated states with endpoint-clean no-any-betting controls;
- log filing-rate outcome;
- renter-weighted within-state aggregation;
- 75% and 100% county-month coverage;
- common post-horizon treated composition;
- cohort/cell COVID flags;
- full leave-one-state-out influence output;
- treated-state retail-regime and support audit.

A COVID-clean aggregate is not credibly supported by these cohorts, so explicit overlap flags and caveats are an appropriate diagnostic treatment.

## Inference assessment

The delete-one-state implementation correctly recomputes the estimator after dropping every relevant state and applies the standard jackknife variance formula. It respects the state assignment level. Because all cohorts are singleton treated states—and the clean sensitivity has only four treated states—the t intervals and p-values are approximate rather than demonstrated size-correct inference. The summary repeatedly states this limitation, so these values are suitable as exploratory uncertainty diagnostics but not as definitive publication inference without simulation or design-based validation.

## Data Cleaning (Stage 0): PASS WITH CAVEATS

- The drop audit records 120,725 raw rows, 114,389 after the crosswalk plus ME/NH exclusion, and 112,678 after the five-county rule: 93.3% retained.
- Same counties must contribute to both comparison periods.
- The primary partial-coverage rule and complete-coverage alternative are both clearly documented.
- No duplicate panel rows or nonfinite state changes were detected.
- Minor hardening remains desirable: assert one treatment row per state, consistency of `has_online` with `online_start_date`, and uniqueness of `(state_abb, fips, month_date)` inside the script.

## Code Quality (12 categories)

| Category | Status | Issues |
|----------|--------|--------|
| Project layout | WARN | Appropriate standalone diagnostic, but not yet integrated into a numbered production master. |
| Script headers | OK | Purpose, inputs, outputs, and distinction from the formal Lee–Wooldridge estimator are documented. |
| Console output | WARN | `print(sessionInfo())` at line 1498 should be saved or emitted through the project logging convention. |
| Reproducibility | OK | Libraries load at top; paths are project-relative; the seed occurs once; outputs are current. |
| Numerical discipline | WARN | Correct numerical guards; growing result lists violate INV-17. |
| Function design | OK | Documented functions, snake-case names, named returns, and core preconditions. |
| Figure quality | WARN | Axis and table labels now correctly say “contrast,” but the ggplot retains an internal title/subtitle at lines 1086–1094, violating **INV-12**. PNG is produced, not a publication PDF. |
| Table quality | WARN | Readable Markdown table; a publication version should add treated/control state and county counts. No TeX table is exported, so INV-13 is not triggered. |
| RDS/checkpoint | OK | All central data, schedule, regime audit, state cells, estimates, support, LOO replicates, parameters, summary, and plot objects are serialized. |
| Comment quality | OK | Comments explain estimator and support logic. |
| Error handling | WARN | Add explicit source-data uniqueness/consistency assertions. |
| Prohibited patterns | OK | No `setwd`, absolute path, `rm(list=ls())`, `attach`, `detach`, `install.packages`, or `<<-`. |

## Content invariants (INV-13 through INV-19)

- **INV-13:** Not applicable; no LaTeX table environment is exported.
- **INV-14:** Pass; `set.seed()` appears once at the top.
- **INV-15:** Pass; libraries load before computation.
- **INV-16:** Pass; paths are relative through `here()`/`file.path()`.
- **INV-17:** Minor fail; aggregate and replicate lists grow in loops.
- **INV-18:** Pass; outputs are in the declared analysis directory.
- **INV-19:** Pass; no prohibited functions.

## Artifact verification

- 21 output artifacts, none zero-byte.
- `aggregate_estimates.csv` and RDS each contain 49 rows.
- `online_treated_regime.csv` and RDS each contain nine rows.
- Main, clean, support, regime, COVID, LOO, and parameter outputs are mutually consistent and newer than the analysis script.

## Score Breakdown

- Starting: 100
- Growing result lists, violating INV-17: −5
- Figure title/subtitle inside ggplot, violating INV-12: −5
- Missing source-data uniqueness/consistency guards: −5
- Console output pollution from `print(sessionInfo())`: −3
- **Final: 82/100**

## Escalation Status: None

The critical cohort-date error and major retail-history estimand issue were resolved within the review cycle. Remaining findings are minor implementation and presentation improvements.
