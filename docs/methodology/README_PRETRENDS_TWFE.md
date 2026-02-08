# TWFE Pre-Trends Testing

Simple, reliable pre-trends testing using Two-Way Fixed Effects event-study regression. This is a focused alternative to the full CS-DiD pipeline when bootstrap standard errors prove problematic.

## Quick Start

### Local Execution

```bash
cd /Users/bb1806/Documents/GitHub/Gambling-and-Eviction

# Run with default settings
export OUT_DIR="pretrends_twfe_test"
export EXCLUDE_STATES="ME"
export MAX_DATE="2024-12-31"

Rscript analysis/pretrends_twfe.R
```

### Della Execution

```bash
cd /scratch/gpfs/DESMOND/ben/eviction_gambling
sbatch scripts/run_pretrends_twfe.sh

# Check job status
squeue -u $USER

# View output when complete
tail pretrends_twfe_*.out
ls -lh pretrends_twfe_out/
```

## What It Does

This script performs TWFE event-study regression to test for pre-trends:

1. **Panel Construction**: Identical to CS-DiD pipeline (same env vars, same filtering)
2. **Event-Time Dummies**: Creates indicators for each event time relative to treatment
3. **TWFE Regression**: Runs `y ~ event_dummies | state + month` with clustered SEs
4. **Pre-Trends Test**: Joint F-test that all pre-treatment coefficients are zero
5. **Event Study Plot**: Visualizes coefficients with confidence intervals

## Key Advantages

✅ **No bootstrap** - uses analytical standard errors
✅ **Fast** - runs in ~5-10 seconds
✅ **Stable** - no singular matrix issues with small cohorts
✅ **Interpretable** - familiar regression framework
✅ **Reliable inference** - well-understood asymptotic theory

## Key Limitations

⚠️ **Biased with heterogeneous treatment effects** - use CS-DiD for actual treatment effect estimation
⚠️ **Forbidden comparisons** - may compare treated units to each other
⚠️ **Not recommended for final estimates** - use only for pre-trends testing

## Environment Variables

### Required Files
- `DATA_FILE`: Combined monthly panel (default: `combined_monthly_panel.csv`)
- `TREAT_FILE`: Treatment assignment (default: `state_month_panel_with_treatment.csv`)
- `OUT_DIR`: Output directory (default: `pretrends_twfe_out`)

### Outcome Specification
- `OUTCOME`: `log1p_filings_count` or `log1p_rate` (default: `log1p_filings_count`)
- `RATE_EPS`: Epsilon for log rate (default: `0.01`)

### Filtering
- `EXCLUDE_STATES`: Comma-separated state abbreviations (e.g., `"ME,VT"`)
- `MAX_DATE`: Maximum date to include (e.g., `"2024-12-31"`)
- `DROP_START`, `DROP_END`: Remove date range from analysis panel

### Event Window
- `MIN_E`: Minimum event time (default: `-24`)
- `MAX_E`: Maximum event time (default: `24`)
- `BALANCE_E`: Balance event time (optional, no default)

### TWFE Settings
- `BINNED_ENDPOINTS`: Bin endpoints? `TRUE` or `FALSE` (default: `FALSE`)
  - `FALSE`: Saturated specification (recommended when you have never-treated units)
  - `TRUE`: Bin `e < MIN_E` and `e > MAX_E` into endpoint categories

### Other
- `ALPHA`: Significance level (default: `0.05`)
- `SEED`: Random seed (default: `123`)
- `MIN_STATES_PER_MONTH`: Support diagnostic threshold (default: `5`)

## Outputs

All outputs go to `$OUT_DIR/`:

```
pretrends_twfe_out/
├── run_pretrends_twfe.log              # Execution log
├── diagnostic_summary.csv              # High-level summary
├── panel_summary.csv                   # Panel dimensions and structure
├── cohort_sizes.csv                    # Treatment cohort diagnostics
├── untreated_support_by_month.csv      # Control support by calendar time
├── support_by_event_time.csv           # Support by event time
├── twfe_event_study.csv                # TWFE estimates (e, estimate, se, t_stat, p, lo, hi)
├── twfe_event_study.png                # TWFE event-study plot
└── twfe_pretrends_joint_test.csv       # Joint F-test for pre-trends
```

## Interpreting Results

### Joint F-Test (`twfe_pretrends_joint_test.csv`)

```csv
ok,method,n_leads,f_stat,df1,df2,p_value
TRUE,F-test on pre-treatment coefficients,24,0.89,24,3650,0.615
```

**Decision rule:**
- **p > 0.05**: ✅ **Fail to reject** → No evidence against parallel trends (GOOD)
- **p < 0.05**: ⚠️ **Reject** → Evidence of pre-trends (CONCERN)

### Event Study Plot (`twfe_event_study.png`)

**Visual inspection:**
- ✅ Pre-treatment coefficients should hover around zero
- ✅ Confidence intervals should cross zero
- ⚠️ Systematic upward/downward slope is concerning
- ✅ Post-treatment jump indicates treatment effect

### Event Study Estimates (`twfe_event_study.csv`)

```csv
e,estimate,se,t_stat,p_value,lo,hi
-24,0.0123,0.0456,0.27,0.787,-0.077,0.102
-23,-0.0089,0.0445,-0.20,0.842,-0.096,0.078
...
-1,0.0000,0.0000,NA,NA,0.0000,0.0000   # Reference period (omitted)
0,0.1456,0.0534,2.73,0.006,0.041,0.250  # Treatment begins
```

## Performance

- **Typical runtime**: ~5-10 seconds
- **Memory**: ~2-4 GB
- **Scaling**: Linear in panel size, no bootstrap overhead

## Binned vs. Saturated Specification

### Saturated (Default: `BINNED_ENDPOINTS=FALSE`)

**Use when you have never-treated units:**
- Estimates separate coefficient for every event time
- No binning at endpoints
- More flexible, no arbitrary aggregation
- **Recommended for this project** (you have 15 never-treated states)

### Binned Endpoints (`BINNED_ENDPOINTS=TRUE`)

**Use when all units are eventually treated:**
- Bins `e < MIN_E` into single "≤ MIN_E" category
- Bins `e > MAX_E` into single "≥ MAX_E" category
- Reduces collinearity issues when no never-treated group
- **Not necessary for this project** (you have never-treated states)

## Comparison to CS-DiD

| Feature | TWFE | CS-DiD |
|---------|------|--------|
| **Speed** | ✅ Fast (~5 sec) | ⚠️ Slow (~5 min with bootstrap) |
| **Stability** | ✅ Always works | ⚠️ Can fail with small cohorts |
| **Standard errors** | ✅ Analytical (reliable) | ⚠️ Bootstrap (can fail) |
| **Treatment effect heterogeneity** | ❌ Biased | ✅ Robust |
| **Pre-trends testing** | ✅ Reliable F-test | ⚠️ Wald test needs valid VCOV |
| **Final estimates** | ❌ Not recommended | ✅ Recommended |

## Best Practice Workflow

### Recommended Strategy

1. **Test pre-trends with TWFE** (this script)
   - Fast, reliable joint F-test
   - Stable standard errors
   - Visual inspection of event-study plot

2. **Estimate treatment effects with CS-DiD**
   - Use CS-DiD pipeline for actual ATT estimates
   - Robust to treatment effect heterogeneity
   - Report CS-DiD as primary results

3. **Report both methods**
   - Show TWFE and CS-DiD side-by-side
   - Note differences indicate heterogeneity
   - Rely on CS-DiD for inference

### If CS-DiD Standard Errors Fail

If CS-DiD produces unreliable SEs but TWFE pre-trends look good:

**Option A: Report TWFE with strong caveats**
- Acknowledge potential for bias under heterogeneity
- Emphasize pre-trends testing as primary contribution
- Treat treatment effect estimates as suggestive

**Option B: Use CS-DiD point estimates with TWFE SEs**
- Not theoretically justified, but pragmatic
- Report as sensitivity analysis
- Clearly document the approach

**Option C: Alternative estimators**
- Synthetic control method
- Stacked DiD (event-by-event estimation)
- Imputation estimators (e.g., `did2s`)

## Troubleshooting

### Error: "No treated observations in event window"
- **Cause**: Event window too restrictive or treatment timing outside range
- **Solution**: Check `MIN_E` and `MAX_E` values, verify treatment dates

### Warning: "No pre-treatment coefficients to test"
- **Cause**: No event times with `e < 0` in the data
- **Solution**: Ensure treatment doesn't start at beginning of panel, check event window

### Error: "Unknown OUTCOME"
- **Cause**: `OUTCOME` not set to valid value
- **Solution**: Use `log1p_filings_count` or `log1p_rate`

### Different results than CS-DiD
- **This is expected!** Indicates treatment effect heterogeneity
- TWFE is biased, CS-DiD is not (under parallel trends)
- See Goodman-Bacon (2021) for decomposition of differences

## Technical Details

### Reference Period

- Reference period: `e = -1` (one period before treatment)
- Coefficient for `e = -1` is normalized to zero (omitted from regression)
- All other coefficients are relative to `e = -1`

### Standard Errors

- Clustered at state level (unit of treatment assignment)
- Heteroskedasticity-robust
- Uses `fixest::feols()` with `cluster = ~id`

### Joint F-Test

- Tests null hypothesis: all pre-treatment coefficients are zero
- Uses `fixest::wald()` for joint test
- F-statistic with appropriate degrees of freedom
- P-value from F-distribution

### Event-Time Dummy Construction

- Uses `fastDummies::dummy_cols()` to create indicators
- One dummy per event time (except reference period)
- If `BINNED_ENDPOINTS=TRUE`, bins extreme event times

## References

1. **Callaway, B., & Sant'Anna, P. H. (2021).** Difference-in-differences with multiple time periods. *Journal of Econometrics*, 225(2), 200-230.

2. **Goodman-Bacon, A. (2021).** Difference-in-differences with variation in treatment timing. *Journal of Econometrics*, 225(2), 254-277.

3. **Sun, L., & Abraham, S. (2021).** Estimating dynamic treatment effects in event studies with heterogeneous treatment effects. *Journal of Econometrics*, 225(2), 175-199.

4. **Roth, J. (2022).** Pretest with caution: Event-study estimates after testing for parallel trends. *American Economic Review: Insights*, 4(3), 305-322.

## Success Criteria

✅ Script runs on both local machine and Della
✅ Outputs match CS-DiD pipeline conventions
✅ All required CSVs and plots generated
✅ Panel construction matches existing scripts
✅ Environment variables work as documented
✅ Fail-fast on missing files
✅ Log file records settings and status
✅ Single command execution (no RStudio required)
✅ Fast execution (<30 seconds)
✅ Stable with small cohorts
✅ Reliable standard errors (no bootstrap failures)
