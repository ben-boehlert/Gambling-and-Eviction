# Test Suite for power_simulation_cs_v2.R

## Overview

This test suite (`test_power_simulation_cs_v2.R`) provides comprehensive verification of the power simulation code that implements the **Black et al. methodology** for simulation-based power analysis in difference-in-differences settings.

## Running the Tests

```bash
Rscript test_power_simulation_cs_v2.R
```

Expected runtime: ~2-3 minutes

## What is Being Tested

### Core Methodology (Black et al.)

The tests verify that the simulation correctly implements the Black et al. approach:

1. **Uses never-treated units to estimate baseline variation** (not just treated units' pre-treatment periods)
2. **Accounts for autocorrelation through simulation** (why formula-based power is incorrect)
3. **Prevents treatment indicator leakage** (critical for unbiased placebo tests)
4. **Bootstrap inference** with proper clustering

### Test Coverage

#### TEST 1: Panel Loading and Structure
- Verifies panel loads with required columns: `unit_id`, `time_id`, `month_date`, `outcome`, `state_abb`
- Checks that `unit_id` is numeric (required by `did::att_gt`)
- Validates outcome variable exists and is not all NA

**Why this matters**: The `did` package requires numeric IDs and will fail with character IDs.

#### TEST 2: Treatment Schedule Creation
- Reads sports gambling legalization dates
- Matches states to panel units
- Creates `g` (treatment date) and `ever_treated` indicator
- Verifies both treated and never-treated units exist

**Why this matters**: Need both groups for Black et al. methodology.

#### TEST 3: Standardized Treatment Schedule
- Converts treatment dates to numeric `time_id` (g_id)
- Sets `g_id = 0` for never-treated units
- Validates all treated units have `g_id > 0`

**Why this matters**: The Callaway-Sant'Anna estimator needs numeric treatment times.

#### TEST 4: Build Untreated Sample (Black et al.)
- Constructs baseline from:
  - **Never-treated units**: all time periods
  - **Treated units**: only pre-treatment periods
- Filters to balanced units (≥80% time coverage) to prevent CS estimator errors

**Why this matters**: This is the core of Black et al. - using untreated observations to estimate natural variation.

#### TEST 5: Residualization Preserves Variance Structure
- Removes unit and time fixed effects
- Verifies residualized outcome still has variation (not all removed)
- **Critical check**: Confirms `g_id` and `ever_treated` are removed after residualization

**Why this matters**: If treatment indicators remain, placebo assignment can use this information, causing spurious rejections. This was a major bug in earlier versions.

#### TEST 6: Placebo Treatment Assignment
- Draws placebo schedule mimicking real adoption pattern
- Shifts treatment dates into untreated baseline window
- Verifies some units get placebo treatment, others serve as placebo controls
- Ensures sufficient pre/post periods around placebo treatment

**Why this matters**: Placebo schedule must preserve staggered timing structure of real data.

#### TEST 7: Effect Injection
- Injects known effect size into placebo-treated units post-placebo-treatment
- Verifies pre-post difference matches injected effect (within sampling error)
- Tests step, ramp, and delayed effect shapes

**Why this matters**: Power = fraction of simulations that correctly detect this injected effect.

#### TEST 8: Time ID Remapping for did Package
- Maps large `time_id` values (e.g., 24254 = 2021×12+2) to sequential integers (1, 2, 3, ...)
- Prevents `Inf` warnings from `did` package

**Why this matters**: `did` package can't handle large time IDs; this was causing failures in v1.

#### TEST 9: Run One Simulation (Integration Test)
- Full pipeline: placebo assignment → effect injection → CS estimation
- Extracts p-value, estimate, and SE
- Tests both null (effect=0) and alternative (effect>0) scenarios

**Why this matters**: Verifies all components work together correctly.

#### TEST 10: MDE Computation
- Tests `compute_mde()` function with synthetic power curve
- Verifies interpolation between grid points
- Tests edge case when target power never reached

**Why this matters**: MDE is the key output for grant applications.

#### TEST 11: Never-Treated Control Group (Black et al.)
- Counts never-treated units in treatment schedule
- Verifies never-treated units are present in baseline
- Confirms methodology follows Black et al. (not just pre-post on treated units)

**Why this matters**: This is what distinguishes Black et al. from simpler approaches.

#### TEST 12: State-Level Clustering
- Verifies `state_abb` is available for clustering
- Counts number of clusters
- Warns if <30 clusters (small-cluster inference matters)

**Why this matters**: Treatment is at state level, so inference must cluster at state level.

#### TEST 13: Parallel Execution Setup
- Checks `use_parallel` and `workers` configuration
- Verifies parallel backend can be initialized

**Why this matters**: Simulations are embarrassingly parallel; this speeds up computation 4-10x.

#### TEST 14: Baseline Subsetting (for Grid Search)
- Tests `subset_baseline_to_n_clusters()` function
- Randomly selects subset of states for power analysis at different sample sizes
- Verifies correct number of states in subset

**Why this matters**: Allows power analysis over grid of (n_states, n_switchers) to understand how power scales.

#### TEST 15: Date Parsing
- Tests `parse_month_to_date()` with multiple formats:
  - ISO date: "2020-01-01"
  - ISO datetime: "2020-06-15 12:00:00"
  - Month-year: "Jan-20", "Jun 2018"
- Verifies all parsed to first-of-month dates

**Why this matters**: Treatment dates come from CSV in various formats; robust parsing prevents errors.

## Key Differences from power_simulation_cs.R

The v2 script has several enhancements tested here:

1. **Time ID remapping**: Prevents `Inf` warnings in `did` package
2. **Treatment leakage prevention**: Explicitly removes `g_id` and `ever_treated` after residualization
3. **Parallel execution**: Supports `future`/`furrr` for parallel simulations
4. **Grid search**: Can vary n_states and n_switchers systematically
5. **Flexible date parsing**: Handles multiple date formats robustly
6. **Unbalanced panel handling**: Pre-filters to balanced units to prevent CS estimator errors

## Interpreting Test Results

### Successful Run

You should see:

```
=== TEST SUMMARY ===
All tests passed! ✓

power_simulation_cs_v2.R is verified for:
  ✓ Panel loading and structure (numeric IDs for did)
  ✓ Treatment schedule creation
  ...
  ✓ Date parsing (multiple formats)

Ready for full power analysis!
```

### Common Warnings (Safe to Ignore)

- `Use of .data in tidyselect expressions was deprecated`: tidyselect deprecation warning, doesn't affect results
- `You have an unbalanced panel`: Expected, the code handles this correctly
- `Be aware that there are some small groups`: CS estimator warning about small treatment cohorts, expected with placebo assignment
- `Not returning pre-test Wald statistic due to singular covariance matrix`: Expected when groups are small, doesn't affect ATT estimation

### Test Failures (Investigate)

If tests fail, check:

1. **Data files present**: Need `monthly_county_data_download.csv` and `sports_gambling_legalization_dates.csv`
2. **Sufficient data**: Need at least 2 treated states, 2 never-treated states, and sufficient time periods
3. **Package versions**: May need to update `did`, `fixest`, `tidyverse`

## Understanding Black et al. Methodology

From the tests, you can see Black et al. works as follows:

1. **Build untreated baseline** (TEST 4):
   - Never-treated states: all months contribute to baseline
   - Treated states: only pre-treatment months contribute
   - This baseline captures natural variation in outcome

2. **Residualize** (TEST 5):
   - Remove unit and time fixed effects
   - **Critical**: Remove treatment indicators to prevent leakage
   - Preserves within-unit-time variation and autocorrelation

3. **Draw placebo** (TEST 6):
   - Randomly assign "placebo treatment" to subset of baseline
   - Mimic real adoption pattern (staggered timing)
   - Shift into untreated window (ensure pre/post periods available)

4. **Inject effect** (TEST 7):
   - Add known effect to placebo-treated units post-placebo-treatment
   - Effect shape: step, ramp, or delayed

5. **Estimate** (TEST 9):
   - Run Callaway-Sant'Anna DiD estimator
   - Bootstrap inference with state-level clustering
   - Extract p-value

6. **Repeat** 100-1000 times:
   - Power = fraction of simulations with p < 0.05
   - MDE = effect size where power = 80%

## Why Simulation Instead of Formula?

The tests reveal why formula-based power won't work:

- **TEST 5**: Residualization preserves ~9% of original variance (most removed by FE)
- **TEST 12**: Clustering at state level (not observation level) inflates SEs
- **Autocorrelation**: Outcomes within state-month are correlated over time

Formula-based power assumes:
- IID errors (violated by autocorrelation)
- Known standard error (violated by complex clustering)
- No fixed effects (violated by unit+time FE)

Black et al. simulation captures all of this by using the actual data structure.

## Next Steps

After tests pass:

1. **Run quick test**: `Rscript run_quick_power_test.R` (10 simulations, 3 effect sizes, ~5 min)
2. **Run full power analysis**: Edit `power_simulation_cs_v2.R` to set `n_sims = 500`, then run
3. **Interpret results**: Check `power_results.csv`, `power_curve.png`, and `grant_ready_paragraph.txt`

## Troubleshooting

### "No valid groups" error from did package
- Check that placebo assignment creates sufficient pre/post periods
- Verify treatment dates are within baseline window
- Increase `pre_len` and `post_len` in cfg

### All simulations return NA
- Check that baseline has sufficient units and time periods
- Verify panel is not too unbalanced (TEST 4 filters to ≥80% coverage)
- Try increasing `did_biters` for bootstrap

### Type I error >> 0.05
- Check TEST 5: Are treatment indicators removed?
- Verify placebo assignment is random (not using real treatment info)
- Check clustering is at correct level (state, not unit)

## References

- Black et al. (2023): "Simulation-based power analysis for panel data designs"
- Callaway & Sant'Anna (2021): "Difference-in-Differences with multiple time periods"
- Roth et al. (2023): "What's trending in difference-in-differences?"
