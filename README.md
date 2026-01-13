# Sports Gambling and Eviction Rates: Replication Package

This repository contains code and data for analyzing the effect of sports gambling legalization on eviction rates using staggered difference-in-differences methods.

## Quick Start

```bash
cd scripts
./run_twfe_power_no_maine_2024.sh
```

## Documentation

- **[Complete Replication Guide](docs/README_REPLICATION.md)** - Full instructions for reproducing all analyses
- **[Quick Start Guide](docs/QUICK_START_GUIDE.md)** - Get started quickly
- **[Power Analysis Summary](docs/POWER_ANALYSIS_SUMMARY.md)** - Overview of power simulation results
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions

## Repository Structure

```
analysis/       Main power simulation and analysis scripts
  ├─ power_simulation_twfe_statepanel_staggered_parallel_fixed.R  ← PRIMARY ANALYSIS
  └─ power_simulation_cs_statepanel_staggered_parallel_merged.R   ← CS-DiD (experimental, SE issues)
data_prep/      Data merging and preparation
plots/          Visualization scripts
utils/          Diagnostic and utility tools
scripts/        Shell scripts for replication (START HERE)
data/           Data files (raw inputs and outputs)
docs/           Documentation
figures/        Generated visualizations
```

## Main Results

Using TWFE with proper cluster-robust standard errors (2016-2024, excluding Maine):

- **Without COVID in residual pool**: 80% power to detect 5% effect (MDE = 5 log points)
- **With COVID in residual pool**: 80% power to detect 8% effect (MDE = 8 log points)

## Requirements

- R (≥ 4.0)
- Required packages: `dplyr`, `readr`, `glue`, `fixest`, `tibble`, `parallel`
- Optional: `did` (for Callaway-Sant'Anna comparison)

Install dependencies:
```R
source("INSTALL_PACKAGES.R")
```

## Citation

[Add citation here]

## License

[Add license here]
