# Analysis Scripts

This directory contains all analysis code for the Sports Gambling and Eviction Rates research project.

## Directory Structure

### main/
**Primary analyses - START HERE**

Contains the main power simulation and dose-response analyses:
- `power_simulation_twfe_statepanel_staggered_parallel_fixed.R` - **PRIMARY TWFE ANALYSIS**
- `power_simulation_cs_statepanel_staggered_parallel_merged.R` - CS-DiD power simulation
- `power_simulation_cs_reg_statepanel_staggered_parallel.R` - CS-DiD regression estimator
- `power_simulation_cs_reg_statepanel_staggered_parallel_REVISED.R` - Revised CS-DiD version
- `power_simulation_cs_INSTRUMENTED.R` - Instrumented CS-DiD simulation
- `analyze_gambling_dose_response.R` - Dose-response analysis
- `analyze_gambling_dose_no_ny.R` - Dose-response excluding New York

### pretrends/
**Pre-trends evaluation and diagnostics**

Modern pre-trends testing and event study diagnostics:
- `evaluate_pretrends_modern_methods.R` - Modern methods (Roth 2022, Rambachan & Roth 2023)
- `pretrends_modern.R` - Comprehensive pre-trends with activity-based treatment
- `pretrends_twfe.R` - TWFE-specific pre-trends analysis
- `pretrends_pre_post_covid.R` - COVID period sensitivity analysis
- `pretrends_eventstudy_diagnostics.R` - Event study diagnostic tools
- `mortgage_delinquency_pretrends_simple.R` - Mortgage delinquency pre-trends
- `compare_pretrends_to_effects.R` - Compare pre-trend violations to effect estimates

### data_prep/
**Data preparation scripts**

Scripts for creating treatment timing and panel datasets:
- `create_activity_treatment_dates.R` - Activity-based treatment timing
- `create_mortgage_delinquency_panel.R` - Mortgage delinquency panel creation
- `create_mortgage_treatment_panel.R` - Treatment panel with mortgage data

### visualization/
**Plotting and visualization scripts**

Generate figures and diagnostic plots:
- `plot_pretreatment_coverage.R` - Pre-treatment period coverage visualization
- `plot_treated_untreated_trends.R` - Treated vs untreated trends comparison
- `visualize_pretrend_effect_comparison.R` - Pre-trend violations vs effects
- `compare_twfe_vs_cs_same_data.R` - TWFE and CS-DiD comparison plots

### diagnostics/
**Debugging and diagnostic scripts (for development)**

Tools used during development to diagnose methodological issues:
- CS-DiD null rejection diagnostics (`debug_cs_*.R`, `diagnose_cs_*.R`)
- Panel and data diagnostics (`diagnose_panel_issue.R`, `diagnose_e12_spike.R`)
- IPW estimator debugging (`debug_ipw_failure_detailed.R`)
- Test scripts for various fixes (`test_*.R`)
- Unit identification tools (`identify_problematic_units*.R`)

### exploratory/
**Exploratory analyses and utilities**

Additional analyses and job submission scripts:
- `analyze_parallel_trends.R` - Parallel trends assumption checks
- `FAILFAST_SAFEGUARD.R` - Utility safeguards
- Shell scripts for cluster job submission (`*.sh`)

## Main Analysis Workflow

### 1. Setup
```R
source("INSTALL_PACKAGES.R")
```

### 2. Primary Power Simulation
```bash
# From repository root
cd scripts
./run_twfe_power_no_maine_2024.sh
```

Or run directly in R:
```R
source("analysis/main/power_simulation_twfe_statepanel_staggered_parallel_fixed.R")
```

### 3. Pre-trends Evaluation
```R
source("analysis/pretrends/evaluate_pretrends_modern_methods.R")
```

### 4. Visualization
```R
source("analysis/visualization/plot_treated_untreated_trends.R")
```

## Key Analysis Files

**TWFE (Primary Method):**
- Main analysis: `main/power_simulation_twfe_statepanel_staggered_parallel_fixed.R`
- Pre-trends: `pretrends/pretrends_twfe.R`

**CS-DiD (Experimental):**
- See [patches/README.md](../patches/README.md) for known issues with CS-DiD estimator
- Main analysis: `main/power_simulation_cs_statepanel_staggered_parallel_merged.R`

**Activity-Based Treatment:**
- Treatment timing: `data_prep/create_activity_treatment_dates.R`
- Analysis: `pretrends/pretrends_modern.R`
- Results show 66% improvement in pre-trends F-statistic

## Documentation

For detailed documentation see:
- **[Complete Replication Guide](../docs/README_REPLICATION.md)** - Step-by-step instructions
- **[Methodology Documentation](../docs/methodology/)** - Detailed methods
- **[Pre-trends Guide](../docs/methodology/INTERPRETING_PRETRENDS.md)** - Understanding pre-trends

## Results

Analysis outputs are saved to:
- `data/output/` - Main simulation results (gitignored, reproducible)
- `data/output/pretrends/` - Pre-trends analysis results
- `figures/` - Generated plots and visualizations

## Notes

- **Primary method**: TWFE with cluster-robust standard errors (using `fixest` package)
- **CS-DiD status**: Experimental due to discovered package bugs (see `patches/` and `docs/methodology/CS_DID_PVALUE_FIX.md`)
- **Computation**: Large simulations benefit from parallel execution on HPC clusters
- **Shell scripts**: Located in `scripts/` directory at repository root

## Questions?

See [../docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md) for common issues or [../docs/README.md](../docs/README.md) for full documentation index.
