# Quick grid test: tiny states/switchers grid, minimal sims/effects, no bootstrap
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

cfg <- list(
  data_dir = ".",
  panel_choice = "states_from_counties",
  outcome_preference = c("filings_count_per_1k_renters", "filings_count"),
  weights_var = NULL,
  treat_date_col = "online_start_date",
  n_sims = 2,
  effect_grid = c(0, 1),
  alpha = 0.05,
  power_target = 0.80,
  run_state_switcher_grid = TRUE,
  n_states_grid = c(10, 12),
  n_switchers_grid = c(3, 5),
  estimand = "overall_att",
  target_h = 12,
  pre_len = 12,
  post_len = 12,
  effect_shape = "step",
  delay_h = 6,
  did_bstrap = FALSE,
  did_biters = 50,
  did_cband = FALSE,
  cluster_level = "state",
  use_parallel = FALSE,
  workers = 1
)

cat("Quick grid test: 2 sims × 2 effects × small states/switchers grid\n")
cat("This should complete quickly and write grid CSV outputs.\n\n")

source("power_simulation_cs.R", echo = FALSE)
