# Sports Gambling and Eviction Rates: Replication Package

This repository contains code and data for analyzing the effect of sports gambling legalization on eviction rates using staggered difference-in-differences methods.

## Quick Start

```bash
cd scripts
./run_twfe_power_no_maine_2024.sh
```

## Documentation

- **[Documentation Index](docs/README.md)** - Complete documentation navigation
- **[Complete Replication Guide](docs/README_REPLICATION.md)** - Full instructions for reproducing all analyses
- **[Quick Start Guide](docs/QUICK_START_GUIDE.md)** - Get started quickly
- **[Power Analysis Summary](docs/POWER_ANALYSIS_SUMMARY.md)** - Overview of power simulation results
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions

## Repository Structure

```
analysis/       Main power simulation and analysis scripts (see analysis/README.md)
  ├─ main/          Primary analyses (TWFE and CS-DiD power simulations)
  ├─ pretrends/     Pre-trends diagnostics and evaluation
  ├─ data_prep/     Data preparation scripts
  ├─ visualization/ Plotting scripts
  ├─ diagnostics/   Debugging and diagnostic tools
  └─ exploratory/   Exploratory analyses
data_prep/      Original data merging and preparation scripts
plots/          Visualization utility scripts
utils/          Diagnostic and utility tools
scripts/        Shell scripts for replication (START HERE)
data/           Data files (raw inputs and outputs)
docs/           Documentation (see docs/README.md)
  └─ methodology/ Detailed methodology documentation
figures/        Generated visualizations
patches/        CS-DiD package bug fixes (see patches/README.md)
```

## Recent Updates

- **CS-DiD Issues Documented**: Critical bugs discovered in the `did` package during development. See [patches/](patches/) for fixes and [docs/methodology/CS_DID_PVALUE_FIX.md](docs/methodology/CS_DID_PVALUE_FIX.md) for detailed analysis
- **Modern Pre-trends Methods**: Implemented Roth (2022) and Rambachan & Roth (2023) diagnostics for robust pre-trends evaluation
- **Activity-Based Treatment**: Alternative treatment timing using gambling handle data shows 66% improvement in pre-trends F-statistic (see [docs/methodology/ACTIVITY_BASED_TREATMENT.md](docs/methodology/ACTIVITY_BASED_TREATMENT.md))

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

## Research Archive

The [archive/](archive/) directory (excluded from GitHub via .gitignore) contains diagnostic notes and research process documentation showing how methodological issues were identified and resolved. This material demonstrates the rigorous investigation conducted during development but is not required for replication.

## Contributing

This is a research replication package. For questions about methodology or data, please open an issue.

## Citation

[Add citation here]

## License

[Add license here]
