# Ultra-minimal test: 5 sims, 2 effect sizes, no bootstrap, no parallel
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

# Override config for minimal test
cfg <- list(
  data_dir = ".",
  panel_choice = "counties",
  outcome_preference = c("filings_count_per_1k_renters", "filings_count"),
  weights_var = NULL,  # Disable weights for speed
  treat_date_col = "online_start_date",
  n_sims = 5,  # Minimal
  effect_grid = c(0, 1.5),  # Just 2 points
  alpha = 0.05,
  power_target = 0.80,
  estimand = "overall_att",
  target_h = 12,
  pre_len = 12,
  post_len = 12,
  effect_shape = "step",
  delay_h = 6,
  did_bstrap = FALSE,  # No bootstrap for speed
  did_biters = 50,
  did_cband = FALSE,
  cluster_level = "unit",
  use_parallel = FALSE,  # Sequential for testing
  workers = 1
)

cat("Quick test: 5 sims × 2 effect sizes, no bootstrap\n")
cat("This should complete in < 2 minutes...\n\n")

# Source just the functions we need (not the full script)
source("power_simulation_cs.R", echo = FALSE)
