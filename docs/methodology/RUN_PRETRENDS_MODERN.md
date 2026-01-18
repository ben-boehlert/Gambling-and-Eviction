# Running Modern Pre-Trends Analysis

## Quick Start

```bash
cd /Users/bb1806/Documents/GitHub/Gambling-and-Eviction
Rscript analysis/pretrends_modern.R
```

**Runtime**: ~4-5 minutes
**Output directory**: `pretrends_modern_out/`

## Prerequisites

### Required R Packages

Install the modern pre-trends packages (one-time setup):

```bash
Rscript install_modern_packages.R
```

This installs:
- `HonestDiD` (Rambachan & Roth 2023)
- `pretrends` (Roth 2022)

### Already Installed Packages

The script also requires (should already be installed):
- dplyr, readr, glue, tibble, ggplot2
- fixest (TWFE estimation)
- patchwork (plot layout)
- MASS (mvrnorm for equivalence tests)

## What the Script Does

### Treatment Definition
- **Treatment**: Online gambling legalization only (not retail)
- **Data source**: `data/raw/sports_gambling_legalization_dates.csv`
- **Treatment variable**: `online_start_date`
- **States without online gambling**: Treated as never-treated controls

### Specifications Analyzed

1. **Baseline**: Full period (2012-2024), exclude ME, event window -24 to +24
2. **No COVID**: Exclude March 2020 - July 2021, otherwise same as baseline
3. **Narrow Window**: Event window -12 to +12, full period
4. **Pre-2020**: Data through 2019-12-31, event window -24 to +12

### Modern Methods Applied

For each specification, the script runs:

1. **TWFE Event Study**
   - Event-time regression with state + month fixed effects
   - Joint F-test on pre-treatment coefficients
   - Event study plot with confidence intervals

2. **HonestDiD Sensitivity Analysis**
   - Relative Magnitudes approach (Mbar = 0, 0.5, 1, 1.5, 2)
   - Robust confidence intervals accounting for violations
   - Tests whether identification survives bounded violations

3. **Power Analysis (Roth 2022)**
   - Minimal Detectable Effect (MDE) for 50% and 80% power
   - Calculates: "What pre-trend slope can we detect with X% probability?"
   - Assesses whether pre-trends test is informative

4. **Equivalence Testing (Hartman & Hidalgo 2018)**
   - Maximum test: Can rule out max|β_pre| ≥ δ*?
   - Average test: Can rule out |mean(β_pre)| ≥ δ*?
   - RMS test: Can rule out sqrt(mean(β_pre²)) ≥ δ*?
   - Provides evidence FOR parallel trends

## Output Structure

```
pretrends_modern_out/
├── consolidated_report.md              # START HERE - Overall summary
├── comparison/
│   └── robustness_matrix_assessed.csv  # Cross-spec comparison with traffic lights
└── specifications/
    ├── baseline/
    ├── no_covid/
    ├── narrow_window/
    └── pre2020/
        ├── twfe_event_study.csv        # Event-time coefficients
        ├── twfe_event_study.png        # Event study plot
        ├── power_analysis_mde.csv      # MDEs for 50% and 80% power
        └── equivalence_tests.csv       # δ* thresholds
```

## Interpreting Results

### Traffic Light Assessment

Each specification receives a color code:

- **GREEN**: Strong evidence for parallel trends
  - F-test p > 0.10
  - Good power (MDE₈₀ < 0.10)
  - Small δ* (can rule out violations > δ*)

- **YELLOW**: Moderate concerns
  - 0.05 < p < 0.10
  - Moderate power (0.10 ≤ MDE₈₀ < 0.15)
  - Moderate δ*

- **RED**: Significant concerns
  - F-test p < 0.05
  - Weak power (MDE₈₀ ≥ 0.15)
  - Large or NA δ*

### Key Questions to Ask

1. **Do pre-trends tests reject parallel trends?**
   - Check F-test p-value in `twfe_pretrends_joint_test.csv`
   - p < 0.05 suggests violations

2. **Does the test have good power?**
   - Check `power_analysis_mde.csv`
   - MDE₈₀ < 0.10 is good power
   - MDE₈₀ > 0.15 is weak power (passing test uninformative)

3. **Can we rule out economically meaningful violations?**
   - Check δ* in `equivalence_tests.csv`
   - Compare δ* to treatment effect magnitude
   - If δ* < 50% of treatment effect → violations unlikely to explain results

4. **Are results robust across specifications?**
   - Check `comparison/robustness_matrix_assessed.csv`
   - Consistent GREEN across specs → robust
   - Multiple RED → concerning

## Customization

### Environment Variables

You can customize the analysis via environment variables:

```bash
# Use different data file
export DATA_FILE="alternative_panel.csv"

# Different output directory
export OUT_DIR="custom_output"

# Different outcome variable
export OUTCOME="log1p_rate"

# Then run
Rscript analysis/pretrends_modern.R
```

### Modifying Specifications

Edit the `SPECIFICATIONS` list in `pretrends_modern.R` (lines 85-135):

```r
SPECIFICATIONS <- list(
  my_spec = list(
    name = "My Custom Spec",
    exclude_states = "ME,CA",  # Exclude multiple states
    max_date = as.Date("2023-12-31"),
    drop_start = as.Date("2020-03-01"),
    drop_end = as.Date("2020-08-31"),
    min_e = -18,
    max_e = 18
  )
)
```

## Troubleshooting

### Package Installation Fails

If HonestDiD or pretrends installation fails:

```r
# Try installing dependencies manually
install.packages(c("CVXR", "Matrix", "lpSolveAPI"))
remotes::install_github("asheshrambachan/HonestDiD")
remotes::install_github("jonathandroth/pretrends")
```

### "select" Function Conflicts

The script handles MASS::select vs dplyr::select conflicts. If you see errors, ensure MASS is loaded last in the library() calls.

### Low Power Warnings

If power analysis shows very low power (MDE₈₀ > 0.20):
- This means pre-trends test cannot detect moderate violations
- Consider: longer pre-period, more treated units, or higher-frequency data
- Do NOT simply drop the power analysis - report it honestly

### Equivalence Tests Return NA

If δ* = NA for Maximum or Average tests:
- Means we cannot rule out any violations on the grid (DELTA_GRID)
- Suggests large pre-treatment differences
- Consider expanding DELTA_GRID or investigating specific pre-trends

## Following Best Practices

This script implements Roth (2022) recommendations:

✅ **DO**:
- Report power of pre-trends tests
- Conduct sensitivity analysis (HonestDiD)
- Report all specifications regardless of results
- Quantify assumptions needed to defend estimates

❌ **DON'T**:
- Use pre-tests as screening devices
- Condition analysis on passing pre-tests
- Rely solely on p-values without power analysis
- Hide specifications that fail pre-tests

## References

- Rambachan, A., & Roth, J. (2023). A more credible approach to parallel trends. *Review of Economic Studies*, 90(5), 2555-2591.
- Roth, J. (2022). Pretest with caution: Event-study estimates after testing for parallel trends. *American Economic Review: Insights*, 4(3), 305-322.
- Hartman, E., & Hidalgo, F. D. (2018). An equivalence approach to balance and placebo tests. *American Journal of Political Science*, 62(4), 1000-1013.

## Support

For questions or issues:
1. Check `pretrends_modern_out/run_log.txt` for execution details
2. Review warnings in R output
3. Consult the original papers for methodology details
4. Check HonestDiD and pretrends package documentation

---

Last updated: 2026-01-16
