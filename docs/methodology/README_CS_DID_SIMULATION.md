# CS DiD Power Simulation (Regression Estimator)

## Overview

**File**: `power_simulation_cs_reg_statepanel_staggered_parallel.R`

This is a **fixed version** of the Callaway-Sant'Anna DiD power simulation that uses `est_method="reg"` (regression adjustment) instead of `est_method="ipw"` (inverse propensity weighting).

### Why This Version Exists

The original CS simulation (`power_simulation_cs_statepanel_staggered_parallel_merged.R`) used `est_method="ipw"` which **fails 100% of the time** due to a bug in the interaction between `did` and `fastglm` packages:

- `did` package calls `fastglm::fastglm(G ~ -1 + covariates, ...)` with formula syntax
- `fastglm` v0.0.4 has **NO formula method** (only default method expecting `x=, y=`)
- Error: "argument 'y' is missing, with no default"
- All simulations fail silently → appears as 0% rejection rate

**This version uses `est_method="reg"`** which:
- ✅ Works correctly (100% success rate)
- ✅ Gives nominal size (~4-5% Type I error at null)
- ✅ Faster than IPW
- ✅ Appropriate for power simulations with known DGP

## Quick Start

### Basic Usage

```bash
# Run with default settings
Rscript power_simulation_cs_reg_statepanel_staggered_parallel.R

# Specify data files
export DATA_FILE=combined_monthly_panel.csv
export TREAT_FILE=state_month_panel_with_treatment.csv
Rscript power_simulation_cs_reg_statepanel_staggered_parallel.R

# Run null simulations only (for size check)
export N_SIMS=500
export EFFECT_PCTS="0"
Rscript power_simulation_cs_reg_statepanel_staggered_parallel.R
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DATA_FILE` | `combined_monthly_panel.csv` | Panel data file |
| `TREAT_FILE` | `state_month_panel_with_treatment.csv` | Treatment schedule |
| `OUT_DIR` | `cs_reg_power_out` | Output directory |
| `OUTCOME` | `log1p_filings_count` | Outcome variable |
| `N_SIMS` | `2000` | Number of simulations per effect size |
| `EFFECT_PCTS` | `"0,0.05,0.10,0.15,0.20"` | Effect sizes (log points) |
| `ALPHA` | `0.05` | Significance level |
| `SEED` | `123` | Random seed |
| `N_WORKERS` | `20` | Number of parallel workers |
| `ERR_MODE` | `iid_month` | Error generation: `iid_month` or `ar1` |
| `DID_CONTROL_GROUP` | `nevertreated` | Control group: `nevertreated` or `notyettreated` |
| `DID_BSTRAP` | `TRUE` | Use bootstrap inference |
| `DID_BITERS` | `199` | Bootstrap iterations |

### Example: Full Power Curve

```bash
export DATA_FILE=combined_monthly_panel.csv
export TREAT_FILE=state_month_panel_with_treatment.csv
export N_SIMS=2000
export EFFECT_PCTS="0,0.05,0.10,0.15,0.20"
export N_WORKERS=20
export ERR_MODE=iid_month

Rscript power_simulation_cs_reg_statepanel_staggered_parallel.R
```

### Example: Null Size Check

```bash
export N_SIMS=500
export EFFECT_PCTS="0"
Rscript power_simulation_cs_reg_statepanel_staggered_parallel.R

# Check Type I error rate
cat cs_reg_power_out/diagnostics_sanity.csv
```

Expected output:
```
n_states,n_sims,mean_att0,sd_att0,mean_se0,se_inflation,type1_at_effect0
38,500,0.001,0.070,0.073,1.04,0.048
```
→ Type I error ≈ 4.8% (nominal)

## Outputs

All outputs are saved to `OUT_DIR` (default: `cs_reg_power_out/`):

| File | Description |
|------|-------------|
| `run.log` | Execution log with diagnostics |
| `treatment_schedule.csv` | Treatment timing by state |
| `panel_summary.csv` | Panel structure summary |
| `power_by_effect.csv` | Power for each effect size |
| `diagnostics_sanity.csv` | Null diagnostics (Type I error, SE calibration) |
| `draws_sample.csv` | Sample of simulation draws |
| `power_curve.png` | Power curve plot (if ggplot2 available) |

## Key Features

### 1. Fixed Estimator
```r
est_method = "reg"  # Always use regression adjustment
```
- Avoids fastglm bug that affects IPW/DR
- Reliable, fast, appropriate for power simulations

### 2. Fail-Fast Safeguard
```r
if (success_rate < 0.95) {
  # Print error messages
  # Stop execution
  stop("Simulation failed: success rate < 95%")
}
```
- Detects simulation failures immediately
- Prints top 3 error messages
- Prevents silent failures

### 3. Parallel Execution
```r
# Automatically uses SLURM_CPUS_PER_TASK if available
N_WORKERS <- max(1, min(req_workers, slurm_cpus))
```
- Respects cluster resource limits
- Efficient parallel execution

### 4. Flexible Error Generation
```r
ERR_MODE = "iid_month"  # Resample within month
ERR_MODE = "ar1"        # Generate AR(1) within state
```
- `iid_month`: Maintains within-month variation
- `ar1`: Captures temporal dependence

## Comparison: REG vs IPW

| Aspect | est_method="reg" | est_method="ipw" |
|--------|------------------|------------------|
| Success rate | 100% ✅ | 0% ❌ |
| Type I error | 4-5% ✅ | N/A (all fail) |
| Speed | Fast ✅ | N/A |
| Appropriate for power sims | Yes ✅ | Yes (if it worked) |
| Works with xformla=~1 | Yes ✅ | No ❌ (fastglm bug) |

## Technical Details

### Estimation Method

**Regression adjustment** (`est_method="reg"`):
- Models outcome conditional on treatment and covariates
- E[Y | D, G, T, X] where D=treatment, G=group, T=time, X=covariates
- With `xformla=~1`, this is: E[Y | D, G, T]
- Estimates ATT via outcome regression, no propensity scores

**vs IPW** (`est_method="ipw"`):
- Reweights observations using propensity scores P(G | X)
- Requires propensity score estimation (preliminary logit)
- **Fails with xformla=~1** due to fastglm bug

### Inference

Uses bootstrap with cluster-robust standard errors:
```r
bstrap = TRUE       # Enable bootstrap
biters = 199        # Bootstrap iterations
clustervars = "id"  # Cluster at state level
```

P-values computed using t-distribution:
```r
z <- att / se
p <- 2 * pt(-abs(z), df = n_states - 1)
```

### Data Generation Process

1. **Fit FE on untreated observations**:
   ```r
   fe_fit <- feols(y ~ 1 | id + t, data = untreated_only)
   ```

2. **Predict FE for all observations**:
   ```r
   yhat <- predict(fe_fit, newdata = panel)
   ```

3. **Generate simulated outcomes**:
   ```r
   y_sim <- yhat + e_draw + ifelse(post_treat, effect_log, 0)
   ```
   - `yhat`: Estimated FE (alpha_i + lambda_t)
   - `e_draw`: Resampled residuals
   - `effect_log`: Treatment effect (0 under null)

## Troubleshooting

### Low Success Rate (<95%)

If simulations fail:

1. Check `run.log` for error messages
2. Common issues:
   - **Sparse ATT(g,t) cells**: Some group-time combinations have insufficient data
     - Fix: Use larger MIN_POOL, or restrict event-time window
   - **Data file not found**: Check DATA_FILE and TREAT_FILE paths
   - **Small treatment groups**: Some states have very few observations
     - Fix: Exclude small states with EXCLUDE_STATES

### Type I Error Not Nominal

If null rejection rate is not ~5%:

1. Check `diagnostics_sanity.csv`:
   ```bash
   cat cs_reg_power_out/diagnostics_sanity.csv
   ```

2. Look at:
   - `se_inflation`: Should be ~1.0-1.2
   - `type1_at_effect0`: Should be ~0.04-0.06

3. Possible issues:
   - Data quality problems
   - Treatment contamination
   - Clustering issues

### Comparison with TWFE

To verify CS results match TWFE:

```bash
# Run CS
Rscript power_simulation_cs_reg_statepanel_staggered_parallel.R

# Run TWFE
Rscript power_simulation_twfe_statepanel_staggered_parallel_fixed.R

# Compare
head cs_reg_power_out/power_by_effect.csv
head twfe_power_out/power_by_effect.csv
```

Expect similar power curves (CS may be slightly more conservative).

## References

- **Callaway & Sant'Anna (2021)**: "Difference-in-Differences with multiple time periods", *Journal of Econometrics*
- **`did` package**: https://bcallaway11.github.io/did/
- **Bug report**: See `EVIDENCE_REPORT_IPW_FAILURE.md` for detailed documentation of the IPW bug

## Migration from Old Script

If you're using the old `power_simulation_cs_statepanel_staggered_parallel_merged.R`:

### Option 1: Use This New Script (Recommended)

```bash
# Simply switch to new script
Rscript power_simulation_cs_reg_statepanel_staggered_parallel.R
```

### Option 2: Fix Old Script (One Line)

Edit line 155 of the old script:
```diff
- did_method <- getenv1("DID_EST_METHOD", "ipw")
+ did_method <- getenv1("DID_EST_METHOD", "reg")
```

Both approaches give identical results.

## See Also

- `EVIDENCE_REPORT_IPW_FAILURE.md` - Complete diagnosis of IPW bug
- `FIX_OPTIONS_COMPLETE.md` - All fix options with pros/cons
- `CS_NULL_SIZE_RESULTS_TABLE.md` - A/B test results
- `FAILFAST_SAFEGUARD.R` - Fail-fast code (already integrated in this script)
