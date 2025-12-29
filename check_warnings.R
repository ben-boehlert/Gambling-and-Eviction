suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(did)
  library(fixest)
  library(glue)
})

set.seed(20251224)

# Load without running
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
  did_bstrap = TRUE,
  did_biters = 50,
  did_cband = FALSE,
  cluster_level = "state",
  estimand = "overall_att",
  target_h = 12,
  alpha = 0.05,
  use_parallel = FALSE,
  n_sims = 1,
  effect_grid = c(0),
  workers = 1
)

# Source functions only (parse without executing bottom)
lines <- readLines("power_simulation_cs.R")
# Find where the execution starts (after function definitions)
exec_start <- grep("^# Run A1 and A2", lines)[1]
if (is.na(exec_start)) exec_start <- grep("^power_A1 <-", lines)[1]

# Execute only function definitions
eval(parse(text = paste(lines[1:(exec_start-1)], collapse = "\n")))

# Load panel
panel_df <- load_panel(cfg)
cluster_var <- "state_abb"
treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)

# Capture warnings
warnings_list <- character()
result <- withCallingHandlers(
  simulate_power(panel_df, treat_schedule_std, option="A1", cfg=cfg, cluster_var=cluster_var),
  warning = function(w) {
    warnings_list <<- c(warnings_list, conditionMessage(w))
    invokeRestart("muffleWarning")
  }
)

cat("Total warnings:", length(warnings_list), "\n\n")
cat("First 20 unique warnings:\n")
cat(paste(head(unique(warnings_list), 20), collapse = "\n\n"))
cat("\n\nResult:\n")
print(result)
