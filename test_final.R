# Final test with all fixes
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(did)
  library(fixest)
})

set.seed(202512)

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

cat("=== FINAL TEST ===\n\n")

cat("Loading power_simulation_cs.R...\n")
source("power_simulation_cs.R", echo = FALSE, verbose = FALSE)

cat("\nRunning single simulation with effect = 2.0...\n")
cat("(This uses run_estimator_and_extract_p which includes time_id remapping)\n\n")

panel_df <- load_panel(cfg)
cluster_var <- "state_abb"
treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)
baseline <- build_untreated_sample(panel_df, treat_schedule_std)
placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline)
df_sim <- impose_effect(baseline, placebo, effect_size = 2.0, cfg)

cat("Calling run_estimator_and_extract_p...\n")
result <- run_estimator_and_extract_p(df_sim, cfg, cluster_var)

cat("\n=== RESULT ===\n")
cat("p =", result$p, "\n")
cat("est =", result$est, "\n")
cat("se =", result$se, "\n")

if (is.na(result$p)) {
  cat("\n❌ FAILED: p-value is NA\n")
} else {
  cat("\n✓ SUCCESS: Got valid result!\n")
  if (result$p < 0.05) {
    cat("Result is statistically significant (p < 0.05)\n")
  }
}
