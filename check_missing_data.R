# Check why did package is dropping so much data
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
})

set.seed(1111)

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
  did_bstrap = FALSE,
  did_biters = 50,
  did_cband = FALSE,
  cluster_level = "state",
  estimand = "overall_att",
  target_h = 12,
  alpha = 0.05
)

source("power_simulation_cs.R", echo = FALSE, verbose = FALSE)

panel_df <- load_panel(cfg)
cluster_var <- "state_abb"
treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)
baseline <- build_untreated_sample(panel_df, treat_schedule_std)
placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline)
df_sim <- impose_effect(baseline, placebo, effect_size = 0, cfg)

cat("=== DATA QUALITY CHECK ===\n\n")

cat("df_sim dimensions:", nrow(df_sim), "rows x", ncol(df_sim), "cols\n\n")

# Check for missing values in key columns
key_cols <- c("unit_id", "time_id", "outcome_sim", "g_placebo", cluster_var, cfg$weights_var)
cat("Missing values in key columns:\n")
for (col in key_cols) {
  if (col %in% names(df_sim)) {
    n_missing <- sum(is.na(df_sim[[col]]))
    pct_missing <- 100 * n_missing / nrow(df_sim)
    cat(sprintf("  %-35s: %6d (%.1f%%)\n", col, n_missing, pct_missing))
  }
}

cat("\nRows with ANY missing values in key columns:\n")
complete_rows <- df_sim %>%
  select(any_of(key_cols)) %>%
  complete.cases()
cat("  Complete rows:", sum(complete_rows), "\n")
cat("  Incomplete rows:", sum(!complete_rows), "\n")

# Check for panel balance
cat("\nPanel balance:\n")
units_per_time <- df_sim %>%
  group_by(time_id) %>%
  summarise(n_units = n_distinct(unit_id), .groups = "drop")

cat("  Min units per time:", min(units_per_time$n_units), "\n")
cat("  Max units per time:", max(units_per_time$n_units), "\n")
cat("  Mean units per time:", mean(units_per_time$n_units), "\n")

times_per_unit <- df_sim %>%
  group_by(unit_id) %>%
  summarise(n_times = n(), .groups = "drop")

cat("  Min times per unit:", min(times_per_unit$n_times), "\n")
cat("  Max times per unit:", max(times_per_unit$n_times), "\n")
cat("  Mean times per unit:", mean(times_per_unit$n_times), "\n")

imbalanced_units <- times_per_unit %>%
  filter(n_times != max(times_per_unit$n_times))

cat("  Imbalanced units:", nrow(imbalanced_units), "\n")

# Check outcome distribution
cat("\nOutcome (outcome_sim) distribution:\n")
cat("  Min:", min(df_sim$outcome_sim, na.rm = TRUE), "\n")
cat("  Max:", max(df_sim$outcome_sim, na.rm = TRUE), "\n")
cat("  Mean:", mean(df_sim$outcome_sim, na.rm = TRUE), "\n")
cat("  Median:", median(df_sim$outcome_sim, na.rm = TRUE), "\n")
cat("  NAs:", sum(is.na(df_sim$outcome_sim)), "\n")
