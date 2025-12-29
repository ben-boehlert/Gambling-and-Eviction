################################################################################
# test_power_sim.R
# Quick test to verify power_simulation_cs.R runs with minimal settings
################################################################################

# Source the main script with modified config for quick testing
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(stringr)
  library(zoo)
  library(did)
  library(fixest)
  library(glue)
  library(future)
  library(furrr)
})

set.seed(20251224)

# Test configuration - minimal settings for quick validation
cfg <- list(
  data_dir = ".",
  panel_choice = "counties",
  outcome_preference = c(
    "filings_per_1k_renters",
    "filings_count_per_1k_renters",
    "filings_count"
  ),
  weights_var = "renter_occupied_housing_units",
  treat_date_col = "online_start_date",

  # Minimal simulation grid for testing
  n_sims = 10,  # Just 10 sims to test
  effect_grid = c(0, 1.0, 2.0),  # 3 effect sizes
  alpha = 0.05,
  power_target = 0.80,

  estimand = "overall_att",
  target_h = 12,

  pre_len = 12,
  post_len = 12,

  effect_shape = "step",
  delay_h = 6,

  did_bstrap = FALSE,  # Turn off bootstrap for speed
  did_biters = 50,
  did_cband = FALSE,

  cluster_level = "state",

  use_parallel = FALSE,  # No parallel for testing
  workers = 1
)

cat("Testing power_simulation_cs.R with minimal config...\n")
cat("Config summary:\n")
cat("  - Panel:", cfg$panel_choice, "\n")
cat("  - Simulations:", cfg$n_sims, "\n")
cat("  - Effect grid:", paste(cfg$effect_grid, collapse=", "), "\n")
cat("  - Bootstrap:", cfg$did_bstrap, "\n")
cat("  - Parallel:", cfg$use_parallel, "\n\n")

# Test if all required files exist
required_files <- c(
  "monthly_county_data_download.csv",
  "sports_gambling_legalization_dates.csv"
)

all_exist <- all(file.exists(file.path(cfg$data_dir, required_files)))

if (!all_exist) {
  stop("Missing required data files. Check: ", paste(required_files, collapse=", "))
}

cat("✓ All required data files found\n\n")

# Try to source the main script functions
cat("Testing main script execution...\n")
tryCatch({
  source("power_simulation_cs.R")
  cat("\n✓ Script completed successfully!\n")
  cat("\nOutput files generated:\n")
  if (file.exists("power_results.csv")) cat("  ✓ power_results.csv\n")
  if (file.exists("power_curve.png")) cat("  ✓ power_curve.png\n")
  if (file.exists("grant_ready_paragraph.txt")) cat("  ✓ grant_ready_paragraph.txt\n")
}, error = function(e) {
  cat("\n✗ Error occurred:\n")
  cat(conditionMessage(e), "\n")
  stop(e)
})
