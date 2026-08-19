# Code review: sufficient-statistics / shift-mode power simulation

Date: 2026-08-18  
Scope: commit `0e8fb34` plus the current `config/power_county_cs.yml` production configuration  
Disposition: **CRITICAL ERRORS — do not use shift-mode output for the headline CS MDE yet**

## Bottom line

The deterministic, transformed-scale, constant-step benchmark supports an exact shift shortcut under its narrow conditions. The primary `count_nb` simulations do not satisfy those conditions: the injection adds effect-dependent random noise, the standard error need not remain fixed, and the learned loading is an approximation rather than a sufficient statistic. More importantly, the empirical validator does not run the production algorithm on held-out replications, does not test standard-error invariance, and does not reach an 80% power crossing. The work therefore does not validate the decision-relevant MDE.

The implementation also is not accurately described as “run only the zero-effect simulation.” In the production county configuration, the first 25 of 250 replications run the full 11-point effect grid; the remaining replications are synthesized from their zero-effect fit using a loading learned from those 25 calibration replications.

## Findings

### 1. Critical: the validator does not validate the production algorithm

The validator fits one loading on all usable paired rows, pooling deltas, estimands, and event times (`analysis/diagnostics/validate_shift_sufficiency.R:422-435`), and evaluates that same fitted loading on the same rows (`:503-538`). Its per-delta loading is only written as a diagnostic (`:458-475`). Production instead learns loadings from the calibration subset, separately by estimator, inference arm, estimand, and delta (`R/power/run_scenario_grid.R:742-770`), then applies them to non-calibration replications.

This is both an algorithm mismatch and an in-sample validation. It cannot establish out-of-sample rejection-rate or MDE accuracy.

Required fix: validate by calling the actual synthesis function on repeated train/holdout splits with the production calibration fraction, effect grid, and grouping keys. Report held-out power error at each effect and held-out MDE error.

### 2. Critical: standard-error invariance is assumed, not tested, and is false for relevant arms

The probe calls SE invariance a primary question (`config/power_cs_probe.yml:11-23`), but the validator drops the nonzero-effect SE when constructing pairs (`analysis/diagnostics/validate_shift_sufficiency.R:350-354`). It always calculates shifted inference using `se0` (`:503-538`). Production likewise sets `se_new = se0` (`R/power/run_scenario_grid.R:788-797`).

Point-estimator linearity does not imply this variance result. Under `count_nb`, nonzero effects add delta-dependent negative-binomial randomness (`R/power/impose_effects.R:245-252`), changing residual and bootstrap variation. In the raw probe, CS bootstrap-t simple SEs show material changes across effects; dynamic analytic SE changes are larger still.

Required fix: restrict exact shift mode to deterministic effects for which both the point-estimate and inference transformations are proven. For stochastic mechanisms, validate an explicit SE model on held-out replications or re-estimate the effect cells. Do not synthesize bootstrap-t or wild inference until this passes.

### 3. Major: the simulated “truth” does not match the CS aggregation weights

The design requires the CS simple truth to use group-size weights over identifiable `(g,t)` cells (`docs/methodology/POWER_SIMULATION_DESIGN.md:32-39`). The code instead computes one equal-weighted mean over treated rows (`R/power/run_scenario_grid.R:475-490`) and assigns it to every estimator (`:499-509`). With unequal cohorts, unequal follow-up, unbalanced support, and `aggte(..., na.rm=TRUE)`, these quantities differ.

The learned loading is therefore partly correcting an estimand mismatch, not merely exploiting estimator linearity.

Required fix: compute estimator-specific truth from the actual identifiable CS cells and the same aggregation weights used by `aggte`. Add tests with unequal cohort sizes, unequal post periods, and unsupported cells.

### 4. Major: dynamic event times incorrectly share a loading

The baseline key includes `event_time` (`R/power/run_scenario_grid.R:718-727`), but loading estimation and the loading join omit it (`:754-770`). All dynamic horizons consequently share one loading. That is not defensible for ramp, delayed, anticipation, or heterogeneous-support designs.

Required fix: include `event_time` in the loading group and join, or exclude dynamic rows from shift synthesis. Test two horizons with deliberately different loadings.

### 5. Major: the validation establishes neither an MDE nor a production-eligible CS inference arm

Every CS-probe entry in `output/shift_validation_cs/mde_comparison.csv` is `never_crosses_target`; the probe stops at `delta = 0.10`. It therefore never tests the 80% power crossing that motivates the shortcut.

Null calibration also remains badly broken. In the completed state probe, CS simple rejection at nominal 5% is roughly 20-28% for the analytic arm and 16-24% for bootstrap-t, outside the design’s permitted 2.5-10% interval. In the current county partial inspected through 125 replications, rejection is 59.2% for analytic inference and 1.6% for both genuine bootstrap and bootstrap-t. Shift mode leaves the zero-effect results unchanged; it cannot repair this problem.

Required fix: first obtain a CS inference specification that passes the null-size gate. Only then validate a grid and replication count that bracket the 80% crossing.

### 6. Major: genuine bootstrap/jackknife power silently falls back to the small calibration sample

Genuine CS bootstrap and jackknife rows are deliberately not synthesized (`R/power/run_scenario_grid.R:664-669`). Downstream summaries and MDE calculations drop the nonconverged placeholder rows (`R/power/summarize_operating_characteristics.R:203-217`, `:381-408`). The pipeline can therefore report power and an MDE based only on the first 25 calibration replications even though the scenario nominally requests 250.

This is especially consequential because analytic CS inference currently fails the null-size gate; the inference arm that might otherwise be considered is precisely the one shift mode cannot reconstruct. The MDE bootstrap also resamples the already-synthesized rows without refitting the shared loading, omitting loading uncertainty and induced dependence.

Required fix: suppress decision metrics for an inference arm unless it has the required effective replication count, or brute-force that arm. If learned loadings remain, use nested resampling that refits the loading.

## What is solid

- Shift mode is off by default and separated through scenario hashing.
- The deterministic constant-step benchmark is exact to floating-point tolerance.
- Resume handling, atomic partial replacement, explicit unreconstructable-arm tags, and denominator diagnostics are carefully implemented.
- The full 11-file `tests/testthat` suite passed on 2026-08-18.

The tests mainly establish software arithmetic and lifecycle behavior. They do not cover production-faithful held-out validity, nonzero-effect SE invariance, CS-specific truth weights, event-time-specific loading, or MDE accuracy at a crossing.

## Recommended decision

Keep the machinery behind an experimental flag. Permit it only for a deterministic additive benchmark until the required held-out validation passes. For the primary stochastic `count_nb` CS analysis, use brute-force estimation or an adaptive/sequential grid that concentrates full simulations near the power crossing. Do not report a shift-mode CS MDE from the current run.
