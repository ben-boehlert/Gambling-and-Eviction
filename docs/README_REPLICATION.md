# Sports Gambling and Eviction Rates: Replication Package

This repository contains replication code for the power analysis of sports gambling legalization effects on eviction rates.

## Repository Structure

```
analysis/          # Main analysis scripts
data_prep/         # Data preparation and merging
plots/             # Visualization scripts
utils/             # Diagnostic and utility scripts
scripts/           # Shell scripts for running analyses
data/              # Data files (CSV)
```

## Main Analysis Files

### Power Simulation (TWFE)
**File**: `analysis/power_simulation_twfe_statepanel_staggered_parallel_fixed.R`

This is the primary power simulation script using traditional two-way fixed effects (TWFE) with proper cluster-robust standard errors.

**Key features:**
- Uses `fixest::feols()` for TWFE estimation
- Cluster-robust SEs at state level (no bootstrap needed)
- Correct type-I error control (~5% at null)
- Supports parallel processing
- Configurable via environment variables

**Alternative**: `analysis/power_simulation_cs_statepanel_staggered_parallel_merged.R`
- Uses Callaway-Sant'Anna DiD estimator
- Note: Has SE issues when `bstrap=FALSE` (documented in conversation history)
- Included for comparison purposes

## Replication Instructions

### Main Results (Table X): Power Analysis without COVID

Excludes Maine and COVID period (March 2020 - June 2021) from residual pool.

```bash
cd scripts
./run_twfe_power_no_maine_2024.sh
```

**Configuration:**
- Effect sizes tested: 0%, 3%, 4%, 5%, 6%
- Simulations: 2,000
- States: 37 (excluding Maine)
- Period: 2016-2024
- COVID exclusion: Yes (from residual pool only)
- Minimum states per month: 15
- Output: `twfe_power_out_no_maine_2024/`

**Results:**
- **MDE at 80% power: ~5 log points** (83.45% power at 5%)
- Type-I error: 4.65% (correct!)
- State-months: 2,867 (1,959 untreated)

### Robustness: Including COVID Period

Same as above but includes COVID period in residual pool.

```bash
cd scripts
./run_twfe_power_no_maine_2024_with_covid.sh
```

**Configuration:**
- Effect sizes tested: 0%, 6%, 7%, 8%, 9%, 10%
- COVID exclusion: No
- Minimum states per month: 5
- Output: `twfe_power_out_no_maine_2024_with_covid/`

**Results:**
- **MDE at 80% power: ~8 log points** (85.4% power at 8%)
- Type-I error: 4.8% (correct!)
- State-months: 3,397 (2,311 untreated)

### Additional Variant: Minimum 5 States

Lowers the minimum state threshold to capture late-period variation.

```bash
cd scripts
./run_twfe_power_no_maine_2024_min5.sh
```

## Environment Variables

All scripts can be customized via environment variables:

```bash
# Number of simulations
N_SIMS=2000

# Effect sizes to test (comma-separated percentages)
EFFECT_PCTS="0,0.03,0.04,0.05,0.06"

# Parallel workers
N_WORKERS=20

# Batch size for parallel processing
BATCH_SIZE=50

# State exclusions (comma-separated abbreviations)
EXCLUDE_STATES="ME"

# Maximum date to include
MAX_DATE="2024-12-31"

# COVID period exclusion from residual pool
EXCLUDE_START="2020-03-01"
EXCLUDE_END="2021-06-01"

# Minimum states per month for residual pool
MIN_STATES_PER_MONTH=5

# Output directory
OUT_DIR="twfe_power_out"

# Run with custom settings
N_SIMS=500 N_WORKERS=10 ./run_twfe_power_no_maine_2024.sh
```

## Hardware Requirements

- **RAM**: ~8GB minimum
- **CPUs**: Script defaults to 20 workers, respects SLURM_CPUS_PER_TASK
- **Runtime**: ~2-4 hours for 2,000 simulations with 20 workers

## Output Files

Each simulation creates an output directory with:

- `power_by_effect.csv` - Power at each effect size
- `diagnostics_sanity.csv` - Type-I error checks
- `treatment_schedule.csv` - Treatment timing by state
- `panel_summary.csv` - Panel dimensions
- `run.log` - Detailed execution log
- `power_curve.png` - Visualization

## Data Files

Required data files (in repository root or specify via `DATA_FILE`/`TREAT_FILE`):

- `combined_monthly_panel.csv` - State-month eviction data
- `state_month_panel_with_treatment.csv` - Treatment schedule

## Diagnostic Scripts

### Verify Data Merge
```bash
cd utils
Rscript verify_merge.R
```

Checks that state panels merge correctly between data sources.

### Check Panel Size
```bash
cd utils
Rscript check_panel_size.R
```

Shows state-month counts with/without COVID exclusion.

## Software Dependencies

Required R packages:
- `dplyr`
- `readr`
- `glue`
- `fixest`
- `tibble`
- `parallel`

Optional (for CS-DiD comparison):
- `did`

Install all dependencies:
```R
install.packages(c("dplyr", "readr", "glue", "fixest", "tibble", "did"))
```

## Notes

### Why TWFE Instead of CS-DiD for Power?

The Callaway-Sant'Anna estimator with `bstrap=FALSE` does not properly implement cluster-robust inference. From the `did` package warning:

> "clustering the standard errors requires using the bootstrap, resulting standard errors are NOT accounting for clustering"

This causes incorrect type-I error (0% instead of 5% at null), making power estimates unreliable. The TWFE approach with `fixest::feols()` provides proper cluster-robust SEs without bootstrap, giving correct inference for power calculations.

### Maine Exclusion

Maine was excluded due to data artifacts causing unusual variation in late 2023.

### Minimum States Per Month

The `MIN_STATES_PER_MONTH` parameter controls which months are included in the residual pool for resampling:
- **15 (default)**: Excludes all of 2023-2024 (only 12 untreated states)
- **5**: Includes all of 2023-2024 (12 > 5)

This affects baseline variance but not the analysis panel itself.

## Citation

[Add your paper citation here]

## Contact

[Add contact information]

## License

[Add license information]
