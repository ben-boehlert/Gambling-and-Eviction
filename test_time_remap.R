# Test if time_id remapping fixes the Inf warning
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(did)
  library(fixest)
  library(glue)
})

set.seed(456)

# Minimal config
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

cat("=== TESTING TIME REMAPPING FIX ===\n\n")

# Load functions
cat("1. Loading functions...\n")
source("power_simulation_cs.R", echo = FALSE, verbose = FALSE)

# Load data
cat("2. Loading panel...\n")
panel_df <- load_panel(cfg)
cat("   Units:", n_distinct(panel_df$unit_id), "\n")
cat("   time_id range:", min(panel_df$time_id), "to", max(panel_df$time_id), "\n\n")

# Treatment schedule
cat("3. Creating treatment schedule...\n")
cluster_var <- "state_abb"
treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)
cat("   Treated units:", sum(treat_schedule_std$ever_treated & treat_schedule_std$g_id > 0), "\n\n")

# Baseline
cat("4. Building baseline (A1)...\n")
baseline <- build_untreated_sample(panel_df, treat_schedule_std)
cat("   Baseline obs:", nrow(baseline), "\n\n")

# Placebo
cat("5. Drawing placebo schedule...\n")
placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline)
cat("   Placebo treated:", sum(placebo$g_placebo > 0), "\n\n")

# Impose effect
cat("6. Imposing effect (1.5)...\n")
df_sim <- impose_effect(baseline, placebo, effect_size = 1.5, cfg)
cat("   Sim data obs:", nrow(df_sim), "\n\n")

# Run estimator - this calls run_estimator_and_extract_p which now does remapping
cat("7. Running CS estimator (with time remapping)...\n")
cat("   Capturing warnings...\n\n")

warnings_list <- character()
result <- withCallingHandlers(
  run_estimator_and_extract_p(df_sim, cfg, cluster_var),
  warning = function(w) {
    msg <- conditionMessage(w)
    warnings_list <<- c(warnings_list, msg)
    invokeRestart("muffleWarning")
  }
)

cat("\n=== RESULTS ===\n")
cat("Warnings captured:", length(warnings_list), "\n")
if (length(warnings_list) > 0) {
  cat("\nUnique warnings:\n")
  for (w in unique(warnings_list)) {
    cat("  -", w, "\n")
  }
}

cat("\nEstimator result:\n")
cat("  p =", result$p, "\n")
cat("  est =", result$est, "\n")
cat("  se =", result$se, "\n")

if (!is.na(result$p)) {
  cat("\n✓ SUCCESS: Got valid p-value!\n")
} else {
  cat("\n✗ FAILED: p-value still NA\n")
}

# Check for Inf warning specifically
inf_warning <- any(grepl("inf.*double.*integer.*gname", warnings_list, ignore.case = TRUE))
if (inf_warning) {
  cat("\n⚠️  Inf warning still present\n")
} else {
  cat("\n✓ No Inf warning!\n")
}
