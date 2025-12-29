# Test state-level analysis
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(did)
  library(fixest)
})

set.seed(20251228)

cfg <- list(
  data_dir = ".",
  panel_choice = "states_from_counties",
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

cat("=== STATE-LEVEL POWER ANALYSIS TEST ===\n\n")

source("power_simulation_cs.R", echo = FALSE, verbose = FALSE)

cat("\n1. Loading state panel...\n")
panel_df <- load_panel(cfg)
cat("   Units:", n_distinct(panel_df$unit_id), "states\n")
cat("   Months:", n_distinct(panel_df$time_id), "\n")
cat("   Panel balance check:\n")
times_per_unit <- panel_df %>% count(unit_id)
cat("     Min months per state:", min(times_per_unit$n), "\n")
cat("     Max months per state:", max(times_per_unit$n), "\n")
cat("     Imbalanced states:", sum(times_per_unit$n != max(times_per_unit$n)), "\n\n")

cat("2. Creating treatment schedule...\n")
cluster_var <- "state_abb"
treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)
cat("   Total states:", nrow(treat_schedule_std), "\n")
cat("   Treated states:", sum(treat_schedule_std$ever_treated & treat_schedule_std$g_id > 0), "\n")
cat("   Never-treated states:", sum(!treat_schedule_std$ever_treated), "\n\n")

cat("3. Building baseline...\n")
baseline <- build_untreated_sample(panel_df, treat_schedule_std)
cat("   Baseline obs:", nrow(baseline), "\n")
cat("   Baseline states:", n_distinct(baseline$unit_id), "\n\n")

cat("4. Drawing placebo & imposing effect (size=2.0)...\n")
placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline)
df_sim <- impose_effect(baseline, placebo, effect_size = 2.0, cfg)
cat("   Sim data ready\n\n")

cat("5. Running CS estimator...\n")
result <- run_estimator_and_extract_p(df_sim, cfg, cluster_var)

cat("\n=== RESULT ===\n")
cat("p-value:", result$p, "\n")
cat("estimate:", result$est, "\n")
cat("SE:", result$se, "\n\n")

if (!is.na(result$p)) {
  cat("✓ SUCCESS! State-level analysis works!\n")
  if (result$p < 0.05) {
    cat("  Result is significant (p < 0.05)\n")
  }
  cat("\nEstimator detected effect of", round(result$est, 3),
      "with SE =", round(result$se, 3), "\n")
  cat("(True effect imposed was 2.0)\n")
} else {
  cat("❌ Still failing with state-level data\n")
}
