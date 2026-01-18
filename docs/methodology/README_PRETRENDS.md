# Pre-Trends Event-Study Diagnostics

Comprehensive pre-trends testing pipeline combining Callaway-Sant'Anna (CS-DiD) and TWFE event-study methods.

## Quick Start

### Local Execution (Fast Test)

```bash
cd /Users/bb1806/Documents/GitHub/Gambling-and-Eviction

# Fast diagnostic (no bootstrap, ~30 sec)
export OUT_DIR="pretrends_test"
export DID_BSTRAP="FALSE"
export DID_BITERS="0"
export RUN_TWFE_ES="TRUE"
export EXCLUDE_STATES="ME"
export MAX_DATE="2024-12-31"

Rscript analysis/pretrends_eventstudy_diagnostics.R
```

### Local Execution (Full Run)

```bash
cd /Users/bb1806/Documents/GitHub/Gambling-and-Eviction

# Full inference with bootstrap (~5 min)
export OUT_DIR="pretrends_out_full"
export DID_BSTRAP="TRUE"
export DID_BITERS="199"
export RUN_TWFE_ES="TRUE"
export EXCLUDE_STATES="ME"
export MAX_DATE="2024-12-31"

Rscript analysis/pretrends_eventstudy_diagnostics.R
```

### Della Execution

```bash
cd /scratch/gpfs/DESMOND/ben/eviction_gambling
sbatch scripts/run_pretrends_della.sh

# Check job status
squeue -u $USER

# View output when complete
tail pretrends_della_*.out
ls -lh pretrends_out_*/
```

## What It Does

### 1. Panel Summary
- **File**: `panel_summary.csv`
- Number of states, months, observations
- Never-treated vs. switcher states
- Date range

### 2. Support Diagnostics
- **Files**: `untreated_support_by_month.csv`, `support_by_event_time.csv`
- Control unit availability by calendar time
- Treatment/control overlap by event time

### 3. CS-DiD Event Study
- **Files**: `cs_event_study.csv`, `cs_event_study.png`, `cs_pretrends_joint_test.csv`
- Robust staggered DiD estimates (Callaway-Sant'Anna 2021)
- Dynamic ATT by event time
- Joint Wald test for pre-trends (all leads)

### 4. TWFE Event Study (Optional)
- **Files**: `twfe_event_study.csv`, `twfe_event_study.png`, `twfe_pretrends_joint_test.csv`
- Classic two-way fixed effects specification
- Event-time coefficients with -1 as reference
- F-test for joint significance of pre-treatment coefficients

## Environment Variables

### Required Files
- `DATA_FILE`: Combined monthly panel (default: `combined_monthly_panel.csv`)
- `TREAT_FILE`: Treatment assignment (default: `state_month_panel_with_treatment.csv`)
- `OUT_DIR`: Output directory (default: `pretrends_out`)

### Outcome Specification
- `OUTCOME`: `log1p_filings_count` or `log1p_rate` (default: `log1p_filings_count`)
- `RATE_EPS`: Epsilon for log rate (default: `0.01`)

### Filtering
- `EXCLUDE_STATES`: Comma-separated state abbrevations (e.g., `"ME,VT"`)
- `MAX_DATE`: Maximum date to include (e.g., `"2024-12-31"`)
- `DROP_START`, `DROP_END`: Remove date range from analysis panel
- `EXCLUDE_START`, `EXCLUDE_END`: Documented but unused (TWFE resid pool only)

### CS-DiD Settings
- `DID_EST_METHOD`: `reg`, `dr`, or `ipw` (default: `reg`)
- `DID_CONTROL_GROUP`: `notyettreated` or `nevertreated` (default: `notyettreated`)
- `DID_ALLOW_UNBALANCED`: `TRUE` or `FALSE` (default: `TRUE`)
- `DID_BSTRAP`: Bootstrap SEs? `TRUE` or `FALSE` (default: `TRUE`)
- `DID_BITERS`: Bootstrap iterations (default: `999`)

### Event Window
- `MIN_E`: Minimum event time (default: `-24`)
- `MAX_E`: Maximum event time (default: `24`)
- `BALANCE_E`: Balance event time (optional, no default)

### TWFE Toggle
- `RUN_TWFE_ES`: Run TWFE event study? `TRUE` or `FALSE` (default: `FALSE`)

### Other
- `ALPHA`: Significance level (default: `0.05`)
- `SEED`: Random seed (default: `123`)
- `MIN_STATES_PER_MONTH`: Support diagnostic threshold (default: `5`)

## Outputs

All outputs go to `$OUT_DIR/`:

```
pretrends_out/
├── run_pretrends.log                  # Execution log with detailed diagnostics
├── diagnostic_summary.csv             # High-level summary of what ran
├── panel_summary.csv                  # Panel dimensions and structure
├── cohort_sizes.csv                   # Treatment cohort diagnostics
├── control_availability.csv           # Control units available by time period
├── untreated_support_by_month.csv     # Control support by calendar time
├── support_by_event_time.csv          # Support by event time
├── cs_event_study.csv                 # CS-DiD estimates (e, att, se, z, p, lo, hi)
├── cs_event_study.png                 # CS-DiD plot
├── cs_pretrends_joint_test.csv        # Joint Wald test for pre-trends
├── twfe_event_study.csv               # TWFE estimates (if RUN_TWFE_ES=TRUE)
├── twfe_event_study.png               # TWFE plot (if RUN_TWFE_ES=TRUE)
└── twfe_pretrends_joint_test.csv      # TWFE joint F-test (if RUN_TWFE_ES=TRUE)
```

## Performance

- **No bootstrap** (`DID_BSTRAP=FALSE`): ~30 seconds, no SEs for CS-DiD
- **Low bootstrap** (`DID_BITERS=199`): ~2-5 minutes, adequate inference
- **High bootstrap** (`DID_BITERS=999`): ~10-15 minutes, precise inference
- **TWFE event study**: Adds ~5 seconds

## Pre-Trends Testing Interpretation

### CS-DiD Joint Test
- **Null hypothesis**: All pre-treatment ATTs are zero
- **Test statistic**: Wald chi-square
- **Rejection**: Evidence against parallel trends

### TWFE Joint F-Test
- **Null hypothesis**: All pre-treatment coefficients are zero
- **Test statistic**: F-statistic
- **Rejection**: Evidence against parallel trends

### Visual Inspection
- Look for systematic pre-trends (e.g., upward/downward slope)
- Check confidence intervals crossing zero
- Compare CS-DiD vs. TWFE for robustness

## Comparison: CS-DiD vs. TWFE

### CS-DiD (Recommended)
- ✅ Robust to treatment effect heterogeneity
- ✅ Explicitly controls for never-treated or not-yet-treated
- ✅ Accounts for staggered adoption timing
- ⚠️ Slower (requires bootstrap)

### TWFE (Supplement)
- ✅ Fast (~5 seconds)
- ✅ Familiar to reviewers
- ⚠️ Biased under heterogeneous treatment effects
- ⚠️ "Forbidden comparisons" problem

**Best practice**: Report both, but rely on CS-DiD for inference.

## Troubleshooting

### Error: "DATA_FILE not found"
- Verify `DATA_FILE` and `TREAT_FILE` paths
- Check working directory with `pwd`

### Error: "DID_EST_METHOD must be reg/dr/ipw"
- Set `DID_EST_METHOD` to valid value
- Use `reg` (regression) as safe default

### Warning: "Small groups in your dataset"
- **Cause**: Some treatment cohorts have very few units (1-2 states)
- **Impact**: May cause singular matrix errors for those cohorts
- **Solution**: Check `cohort_sizes.csv` to identify problem cohorts
- **Options**:
  1. Exclude small cohorts from analysis (filter by `g`)
  2. Use TWFE instead (less sensitive to small cohorts)
  3. Accept that some (g,t) pairs will fail (they'll be excluded automatically)

### Warning: "Singular matrix" for specific (g,t) pairs
- **Cause**: Not enough pre-treatment periods for early-treated cohorts
- **Impact**: Those specific (g,t) ATTs will be NA (excluded from aggregation)
- **Solution**: This is expected behavior - `aggte()` handles it with `na.rm=TRUE`
- **Check**: Review `cohort_sizes.csv` for cohorts with `n_pre_periods < 2`

### CS-DiD fails with IPW estimator
- **Cause**: IPW requires covariates, but we use `xformla=~1` (no covariates)
- **Solution**: Use `DID_EST_METHOD="reg"` (default) or `"dr"` instead
- **Note**: For pre-trends testing, "reg" is sufficient

### Warning: "faster_mode" error
- **Full message**: "An unexpected error occurred... Try changing faster_mode=FALSE"
- **Cause**: Numerical issues with default optimization
- **Current solution**: Script uses `suppressWarnings()` to continue
- **If persistent**: This is a sign of fundamental identification issues
  - Check if you have enough never-treated or not-yet-treated units
  - Review `untreated_support_by_month.csv` for control availability
  - Consider alternative control group (`nevertreated` vs `notyettreated`)

### Memory issues on Della
- Script requests 16GB (conservative)
- Force single-threaded (already set in script)
- If still failing, try reducing `DID_BITERS` (e.g., 199 instead of 999)

### Wrong event window
- Check `MIN_E` and `MAX_E` values
- Ensure sufficient pre-treatment periods (recommend ≥12)
- Symmetric windows often work best (e.g., -24 to +24)

### TWFE gives different results than CS-DiD
- **This is expected!** TWFE is biased under heterogeneous treatment effects
- Differences indicate treatment effect heterogeneity
- **Trust CS-DiD** for inference, use TWFE only for comparison
- See Goodman-Bacon (2021) for decomposition of the differences

## References

1. Callaway, B., & Sant'Anna, P. H. (2021). Difference-in-differences with multiple time periods. *Journal of Econometrics*, 225(2), 200-230.

2. Roth, J. (2022). Pretest with caution: Event-study estimates after testing for parallel trends. *American Economic Review: Insights*, 4(3), 305-322.

3. Sun, L., & Abraham, S. (2021). Estimating dynamic treatment effects in event studies with heterogeneous treatment effects. *Journal of Econometrics*, 225(2), 175-199.

4. Goodman-Bacon, A. (2021). Difference-in-differences with variation in treatment timing. *Journal of Econometrics*, 225(2), 254-277.

## Design Rationale

### Why two runs in bash script?
1. **Fast iteration**: No-bootstrap run for quick checks (~30 sec)
2. **Full inference**: Bootstrap run for publication-ready SEs
3. **Cost efficiency**: Skip expensive bootstrap for exploratory work

### Why single-threaded?
1. **Stability**: `did` + `fixest` + BLAS can conflict with multi-threading
2. **Della compatibility**: Prevents over-subscription
3. **Reproducibility**: Eliminates race conditions in bootstrap

### Why optional TWFE?
1. **Comparison**: Shows difference between CS-DiD and TWFE
2. **Literature**: Both methods commonly reported
3. **Flexibility**: Can disable for faster runs
4. **Simplicity**: TWFE is instant, CS-DiD is slow

## Success Criteria

✅ Script runs on both local machine and Della
✅ Outputs match TWFE simulation conventions
✅ All required CSVs and plots generated
✅ Panel construction matches TWFE simulation
✅ Environment variables work as documented
✅ Fail-fast on missing files
✅ Log file records settings and status
✅ Bootstrap can be toggled
✅ TWFE event study can be toggled
✅ Single command execution (no RStudio required)
