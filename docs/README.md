# Documentation Index

This directory contains comprehensive documentation for the Sports Gambling and Eviction Rates research project.

## Quick Start

**New to this project? Start here:**

- **[Quick Start Guide](QUICK_START_GUIDE.md)** - Get up and running quickly with basic setup and execution
- **[Replication Guide](README_REPLICATION.md)** - Complete instructions for reproducing all analyses
- **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues and their solutions

## Methodology

**Understanding the research approach:**

- **[Pre-trends Methods](methodology/PRETRENDS_METHODS.md)** - Modern pre-trends evaluation using Roth (2022) and Rambachan & Roth (2023) methods
- **[Activity-Based Treatment](methodology/ACTIVITY_BASED_TREATMENT.md)** - Alternative treatment timing using gambling handle data (66% improvement in pre-trends F-statistic)
- **[CS-DiD P-Value Fix](methodology/CS_DID_PVALUE_FIX.md)** - Critical bug fix documentation for Callaway-Sant'Anna estimator
- **[Interpreting Pre-trends](methodology/INTERPRETING_PRETRENDS.md)** - Guide to understanding pre-trends diagnostics
- **[Pre-trends Overview](methodology/README_PRETRENDS.md)** - General pre-trends analysis documentation
- **[TWFE Pre-trends](methodology/README_PRETRENDS_TWFE.md)** - Two-way fixed effects specific pre-trends methods
- **[CS-DiD Simulation](methodology/README_CS_DID_SIMULATION.md)** - Callaway-Sant'Anna simulation methodology
- **[Running Modern Pre-trends](methodology/RUN_PRETRENDS_MODERN.md)** - Execution guide for modern methods
- **[Plots Guide](methodology/PLOTS_GUIDE.md)** - Visualization and plotting guide
- **[Pre-trends Quick Start](methodology/PRETRENDS_QUICKSTART.md)** - Quick start for pre-trends analysis

## Results

- **[Power Analysis Summary](POWER_ANALYSIS_SUMMARY.md)** - Overview of main power simulation results
- **[Grant-Ready Summary](grant_ready_paragraph.txt)** - Concise summary for grant applications

## Research Archive

The repository preserves detailed documentation of the research process:

- **`archive/diagnostics/cs_did/`** - CS-DiD package debugging process (12 diagnostic files)
- **`archive/diagnostics/se_spike/`** - Standard error spike investigation (4 analysis files)
- **`archive/diagnostics/implementation_notes/`** - Implementation insights

These archived materials demonstrate the rigorous methodological investigation conducted during the research. While not required for replication, they provide valuable context for understanding the analytical choices made.

See also: **[patches/README.md](../patches/README.md)** for CS-DiD package fixes

## Directory Structure

```
docs/
├── README.md (this file)
├── QUICK_START_GUIDE.md
├── README_REPLICATION.md
├── POWER_ANALYSIS_SUMMARY.md
├── TROUBLESHOOTING.md
├── grant_ready_paragraph.txt
└── methodology/
    ├── CS_DID_PVALUE_FIX.md
    ├── PRETRENDS_METHODS.md
    ├── ACTIVITY_BASED_TREATMENT.md
    ├── INTERPRETING_PRETRENDS.md
    ├── README_PRETRENDS.md
    ├── README_PRETRENDS_TWFE.md
    ├── README_CS_DID_SIMULATION.md
    ├── RUN_PRETRENDS_MODERN.md
    ├── PLOTS_GUIDE.md
    └── PRETRENDS_QUICKSTART.md
```

## Getting Help

1. **Common Issues**: Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. **Methodological Questions**: See relevant file in `methodology/`
3. **Replication Issues**: Follow [README_REPLICATION.md](README_REPLICATION.md) step-by-step
4. **Package Issues**: See [../patches/README.md](../patches/README.md) for known CS-DiD bugs

## Contributing

This is a research replication package. For questions about methodology or data, please open an issue in the repository.
