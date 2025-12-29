# Test manual aggregation with influence functions
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(did)
})

set.seed(789)

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
  cluster_level = "state",
  estimand = "overall_att",
  alpha = 0.05
)

source("power_simulation_cs.R", echo = FALSE, verbose = FALSE)

panel_df <- load_panel(cfg)
treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)
baseline <- build_untreated_sample(panel_df, treat_schedule_std)
placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline)
df_sim <- impose_effect(baseline, placebo, effect_size = 3.0, cfg)

cat("=== RUNNING ESTIMATOR ===\n")
result <- run_estimator_and_extract_p(df_sim, cfg, cluster_var = "state_abb")

cat("\n=== RESULT ===\n")
cat("Estimate:", result$est, "\n")
cat("SE:", result$se, "\n")
cat("P-value:", result$p, "\n")

if (!is.na(result$p) && result$p < 0.05) {
  cat("✓ Reject null at alpha=0.05\n")
} else if (is.na(result$p)) {
  cat("❌ Could not compute p-value\n")
} else {
  cat("✗ Fail to reject null\n")
}
