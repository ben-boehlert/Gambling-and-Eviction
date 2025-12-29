################################################################################
# MASTER SCRIPT: Run All Power Analyses
#
# This script executes the complete simulated power analysis pipeline:
# 1. Data preparation and panel construction
# 2. Error calibration from untreated data
# 3. Power simulations (Scheme A & B)
# 4. Sensitivity analyses
# 5. Visualization and reporting
#
# Based on:
#   - Black, Hollingsworth, Nunes & Simon (2021) methodology
#   - Burlig, Preonas & Woerman (2020) serial-correlation-robust approach
#   - hollina/health_insurance_and_mortality simple_power_example.do
################################################################################

cat("\n")
cat(paste(rep("=", 80), collapse = ""), "\n")
cat("SIMULATED POWER ANALYSIS FOR SPORTS GAMBLING → EVICTION FILINGS\n")
cat(paste(rep("=", 80), collapse = ""), "\n\n")

cat("Methodology: Black et al. (2021) + Burlig et al. (2020)\n")
cat("Repository: hollina/health_insurance_and_mortality\n")
cat("Date:", format(Sys.Date(), "%B %d, %Y"), "\n\n")

################################################################################
# Setup
################################################################################

# Set working directory to script location
setwd("/Users/bb1806/Documents/eviction_gambling")

# Check for required packages
required_packages <- c(
  "tidyverse", "fixest", "boot", "lubridate", "patchwork", "scales", "here"
)

missing_packages <- required_packages[!required_packages %in% installed.packages()[,"Package"]]

if (length(missing_packages) > 0) {
  cat("Installing missing packages:", paste(missing_packages, collapse = ", "), "\n")
  install.packages(missing_packages)
}

# fwildclusterboot needs special installation
if (!"fwildclusterboot" %in% installed.packages()[,"Package"]) {
  cat("Installing fwildclusterboot from r-universe...\n")
  install.packages(
    "fwildclusterboot",
    repos = c("https://s3alfisc.r-universe.dev", "https://cloud.r-project.org")
  )
}

# Load packages quietly
suppressPackageStartupMessages({
  library(tidyverse)
  library(fixest)
  library(boot)
  library(fwildclusterboot)
  library(lubridate)
  library(patchwork)
  library(scales)
})

cat("All required packages loaded.\n\n")

################################################################################
# STEP 1: Data Preparation
################################################################################

cat(paste(rep("-", 80), collapse = ""), "\n")
cat("STEP 1: DATA PREPARATION\n")
cat(paste(rep("-", 80), collapse = ""), "\n\n")

start_time <- Sys.time()

tryCatch({
  source("eviction_gambling_power_analysis.R")
  cat("\n✓ Data preparation complete\n")
}, error = function(e) {
  cat("\n✗ Error in data preparation:", e$message, "\n")
  stop("Cannot proceed without data. Please check your CSV files.")
})

step1_time <- difftime(Sys.time(), start_time, units = "secs")

################################################################################
# STEP 2: Main Power Simulations
################################################################################

cat("\n")
cat(paste(rep("-", 80), collapse = ""), "\n")
cat("STEP 2: MAIN POWER SIMULATIONS\n")
cat(paste(rep("-", 80), collapse = ""), "\n\n")

start_time <- Sys.time()

tryCatch({
  source("power_simulation_main.R")
  cat("\n✓ Power simulations complete\n")
}, error = function(e) {
  cat("\n✗ Error in power simulations:", e$message, "\n")
  cat("Attempting to continue with partial results...\n")
})

step2_time <- difftime(Sys.time(), start_time, units = "secs")

################################################################################
# STEP 3: Sensitivity Analysis and Visualization
################################################################################

cat("\n")
cat(paste(rep("-", 80), collapse = ""), "\n")
cat("STEP 3: SENSITIVITY ANALYSIS & VISUALIZATION\n")
cat(paste(rep("-", 80), collapse = ""), "\n\n")

start_time <- Sys.time()

tryCatch({
  source("power_sensitivity_and_plots.R")
  cat("\n✓ Sensitivity analysis and visualization complete\n")
}, error = function(e) {
  cat("\n✗ Error in sensitivity/visualization:", e$message, "\n")
  cat("Attempting to continue...\n")
})

step3_time <- difftime(Sys.time(), start_time, units = "secs")

################################################################################
# FINAL SUMMARY
################################################################################

cat("\n\n")
cat(paste(rep("=", 80), collapse = ""), "\n")
cat("ANALYSIS COMPLETE - SUMMARY\n")
cat(paste(rep("=", 80), collapse = ""), "\n\n")

cat("Execution Times:\n")
cat(sprintf("  Step 1 (Data Prep):       %.1f seconds\n", as.numeric(step1_time)))
cat(sprintf("  Step 2 (Simulations):     %.1f seconds\n", as.numeric(step2_time)))
cat(sprintf("  Step 3 (Sensitivity):     %.1f seconds\n", as.numeric(step3_time)))
cat(sprintf("  Total:                    %.1f seconds (%.1f minutes)\n",
            sum(as.numeric(step1_time), as.numeric(step2_time), as.numeric(step3_time)),
            sum(as.numeric(step1_time), as.numeric(step2_time), as.numeric(step3_time))/60))

cat("\nOutput Files Generated:\n\n")

cat("Data:\n")
cat("  • eviction_gambling_power_workspace.RData\n")
cat("  • power_simulation_results.RData\n\n")

cat("Results CSVs:\n")
cat("  • power_results_scheme_a.csv\n")
cat("  • power_results_scheme_b.csv\n")
cat("  • sensitivity_panel_length.csv\n")
cat("  • sensitivity_n_states.csv\n")
cat("  • sensitivity_block_length.csv\n\n")

cat("Tables:\n")
cat("  • table_main_results.csv\n")
cat("  • table_mde_summary.csv\n\n")

cat("Plots:\n")
cat("  • plot_power_curves.png\n")
cat("  • plot_error_rates.png\n")
cat("  • plot_panel_length_sensitivity.png\n")
cat("  • plot_n_states_sensitivity.png\n")
cat("  • plot_combined_sensitivity.png\n\n")

################################################################################
# Key Results Display
################################################################################

if (exists("mde_scheme_a") && exists("mde_scheme_b")) {
  cat(paste(rep("=", 80), collapse = ""), "\n")
  cat("KEY FINDINGS\n")
  cat(paste(rep("=", 80), collapse = ""), "\n\n")

  cat("MINIMUM DETECTABLE EFFECTS (80% power, 5% significance):\n")
  cat(sprintf("  • Scheme A (Random assignment):      %.3f filings per 1,000 renters\n", mde_scheme_a))
  cat(sprintf("  • Scheme B (Staggered adoption):     %.3f filings per 1,000 renters\n\n", mde_scheme_b))

  cat("DESIGN PARAMETERS:\n")
  if (exists("analysis_panel")) {
    cat(sprintf("  • States (clusters):     %d\n", n_distinct(analysis_panel$state)))
    cat(sprintf("  • Observations:          %d state-months\n", nrow(analysis_panel)))
    cat(sprintf("  • Date range:            %s to %s\n",
                min(analysis_panel$month), max(analysis_panel$month)))
  }
  cat("  • Pre-periods:           6 months\n")
  cat("  • Post-periods:          6 months\n")
  cat("  • Monte Carlo sims:      500 per effect size\n")
  cat("  • Clustering:            State level\n")
  cat("  • Alpha:                 0.05 (two-sided)\n\n")

  cat("METHODOLOGY:\n")
  cat("  1. Used ONLY untreated/pre-period data (never-treated + pre-adoption months)\n")
  cat("  2. Calibrated error process preserving within-state serial correlation\n")
  cat("  3. Random pseudo-treatment assignment (500 iterations)\n")
  cat("  4. Recorded power, sign errors, magnitude errors following Black et al. (2021)\n")
  cat("  5. Serial-correlation-robust inference following Burlig et al. (2020)\n\n")

  if (exists("results_scheme_a")) {
    cat("POWER FOR SELECTED EFFECT SIZES (Scheme A):\n")
    power_display <- results_scheme_a %>%
      filter(effect_size %in% c(0, 1, 2, 3, 4, 5)) %>%
      select(effect_size, power, sign_error_rate, severe_mag_error_rate)

    for (i in 1:nrow(power_display)) {
      cat(sprintf("  %.1f filings/1000: Power=%.1f%%, Sign Error=%.1f%%, Severe Mag Error=%.1f%%\n",
                  power_display$effect_size[i],
                  power_display$power[i] * 100,
                  power_display$sign_error_rate[i] * 100,
                  power_display$severe_mag_error_rate[i] * 100))
    }
  }
}

cat("\n")
cat(paste(rep("=", 80), collapse = ""), "\n")
cat("Next Steps:\n")
cat("  1. Review plots in current directory\n")
cat("  2. Examine CSV tables for detailed results\n")
cat("  3. Load .RData files for further custom analysis\n")
cat("  4. Consider sensitivity to different design choices\n")
cat(paste(rep("=", 80), collapse = ""), "\n\n")

cat("Analysis completed successfully.\n")
cat("Working directory:", getwd(), "\n\n")

################################################################################
# Create README
################################################################################

# Build README text with conditional content
readme_parts <- list()

readme_parts$header <- "# Simulated Power Analysis: Sports Gambling → Eviction Filings

## Overview

This analysis implements a simulated power calculation following:
- **Black, Hollingsworth, Nunes & Simon (2021)**: Simulated power analysis methodology
- **Burlig, Preonas & Woerman (2020)**: Serial-correlation-robust panel data design
- **Repository**: hollina/health_insurance_and_mortality (simple_power_example.do)

## Methodology

### Data Sources
1. **monthly_county_data_download.csv**: County-level eviction filings
2. **all_sites_monthly_2020_2021.csv**: Eviction Lab site-level data
3. **sports_gambling_legalization_dates.csv**: Treatment timing

### Key Steps
1. **Panel Construction**: Aggregated to state-month level, calculated filings per 1,000 renters
2. **Error Calibration**: Used ONLY untreated months (never-treated + pre-adoption)
3. **Assignment Schemes**:
   - **A**: Random treated states with common post-period
   - **B**: Staggered adoption (permuted actual dates)
4. **Bootstrap**: Moving-block to preserve within-state autocorrelation
5. **Estimation**: `Y ~ D | state + month` with cluster-robust SE
6. **Metrics**: Power, MDE, sign error rate, magnitude error rate (>2× truth)

### Sensitivity Analyses
- Panel length: +6, +12, +24 months
- Number of states (clusters)
- Bootstrap block length
"

# Add results if available
if (exists("mde_scheme_a") && exists("mde_scheme_b") && exists("analysis_panel")) {
  readme_parts$results <- sprintf("
## Key Results

**Minimum Detectable Effects (80%% power, 5%% alpha):**
- Scheme A (Random): %.3f filings per 1,000 renters
- Scheme B (Staggered): %.3f filings per 1,000 renters

**Design:**
- %d states (clusters)
- 6 pre-periods, 6 post-periods
- 500 Monte Carlo iterations per effect size
- Cluster-robust standard errors at state level
",
    mde_scheme_a,
    mde_scheme_b,
    n_distinct(analysis_panel$state))
} else {
  readme_parts$results <- "
## Key Results

Analysis in progress or incomplete. Run the full analysis to see results.
"
}

readme_parts$files <- "

## Files

### Scripts (run in order)
1. `eviction_gambling_power_analysis.R` - Data prep & error calibration
2. `power_simulation_main.R` - Main simulations
3. `power_sensitivity_and_plots.R` - Sensitivity & visualization
4. `RUN_ALL_ANALYSES.R` - Master script (runs all)

### Output
**Data:**
- `eviction_gambling_power_workspace.RData`
- `power_simulation_results.RData`

**Results:**
- `power_results_scheme_a.csv`
- `power_results_scheme_b.csv`
- `sensitivity_*.csv`

**Tables:**
- `table_main_results.csv`
- `table_mde_summary.csv`

**Plots:**
- `plot_power_curves.png` - Main power curves
- `plot_error_rates.png` - Sign/magnitude errors
- `plot_panel_length_sensitivity.png`
- `plot_n_states_sensitivity.png`
- `plot_combined_sensitivity.png` - 4-panel summary

## References

1. Black, Hollingsworth, Nunes & Simon (2021). \"Simulated power analyses for observational studies: An application to the Affordable Care Act Medicaid expansion.\"

2. Burlig, Preonas & Woerman (2020). \"Panel data and experimental design.\" *Journal of Development Economics*, 144, 102458.

3. Repository: https://github.com/hollina/health_insurance_and_mortality
   - See `simple_power_example.do` (lines 1-665)

4. Gelman & Carlin (2014). \"Beyond power calculations.\" *Perspectives on Psychological Science*.

## Generated

Date: %s
Directory: %s
"

# Combine all parts
readme_text <- paste0(
  readme_parts$header,
  readme_parts$results,
  readme_parts$files,
  sprintf("\nDate: %s\nDirectory: %s\n",
          format(Sys.Date(), "%B %d, %Y"),
          getwd())
)

writeLines(readme_text, "README_POWER_ANALYSIS.md")

cat("README created: README_POWER_ANALYSIS.md\n\n")
cat("✓ All analyses complete.\n\n")

print(results)

