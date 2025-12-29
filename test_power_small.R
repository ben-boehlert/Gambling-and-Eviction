# Test power simulation with small grid
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(did)
})

cfg <- list(
  data_dir = ".",
  panel_choice = "counties",
  outcome_preference = c("filings_count_per_1k_renters"),
  weights_var = "renter_occupied_housing_units",
  treat_date_col = "online_start_date",
  pre_len = 12,
  post_len = 12,
  effect_shape = "step",
  delay_h = 6,
  did_bstrap = FALSE,  # Turn off bootstrap for speed
  cluster_level = "state",
  estimand = "overall_att",
  alpha = 0.05,
  power_target = 0.80,
  n_sims = 5,  # Small number for testing
  effect_grid = c(0, 1, 2, 3),  # Just 4 effect sizes
  use_parallel = FALSE,
  workers = 1
)

source("power_simulation_cs.R", echo = FALSE, verbose = FALSE)

panel_df <- load_panel(cfg)
treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)
cluster_var <- "state_abb"

cat("=== Running small power simulation ===\n")
cat("n_sims =", cfg$n_sims, "\n")
cat("effect_grid =", paste(cfg$effect_grid, collapse = ", "), "\n\n")

power_result <- simulate_power(panel_df, treat_schedule_std, option = "A1", cfg = cfg, cluster_var = cluster_var)

cat("\n=== Results ===\n")
print(power_result)

cat("\n=== Power by effect size ===\n")
power_summary <- power_result %>%
  select(effect_size, power, mean_est, mean_se) %>%
  mutate(across(where(is.numeric), ~round(., 3)))
print(power_summary)
