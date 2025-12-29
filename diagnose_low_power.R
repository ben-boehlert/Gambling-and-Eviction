# Diagnose why power is so low
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(did)
})

set.seed(123)

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

cat("=== BASELINE CHARACTERISTICS ===\n")
cat("Total observations:", nrow(baseline), "\n")
cat("Counties:", n_distinct(baseline$unit_id), "\n")
cat("States:", n_distinct(baseline$state_abb), "\n")
cat("Time periods:", n_distinct(baseline$time_id), "\n")

cat("\nOutcome statistics:\n")
cat("Mean:", mean(baseline$outcome, na.rm = TRUE), "\n")
cat("SD:", sd(baseline$outcome, na.rm = TRUE), "\n")
cat("Min:", min(baseline$outcome, na.rm = TRUE), "\n")
cat("Max:", max(baseline$outcome, na.rm = TRUE), "\n")

# Draw placebo and impose large effect
placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline)

cat("\n=== PLACEBO TREATMENT ===\n")
cat("Total treated counties:", sum(placebo$g_placebo > 0), "\n")
cat("Placebo cohorts:", n_distinct(placebo$g_placebo[placebo$g_placebo > 0]), "\n")

placebo_by_state <- baseline %>%
  distinct(unit_id, state_abb) %>%
  left_join(placebo, by = "unit_id") %>%
  filter(g_placebo > 0) %>%
  group_by(state_abb) %>%
  summarise(n_counties = n(), .groups = "drop")

cat("Treated states:", nrow(placebo_by_state), "\n")
print(placebo_by_state)

# Impose LARGE effect
effect_size <- 3.0
df_sim <- impose_effect(baseline, placebo, effect_size = effect_size, cfg)

cat("\n=== AFTER IMPOSING EFFECT (size =", effect_size, ") ===\n")

# Check if effect was actually imposed
treated_post <- df_sim %>%
  filter(!is.na(g_placebo) & g_placebo > 0 & time_id >= g_placebo)

if (nrow(treated_post) > 0) {
  cat("Treated post-period observations:", nrow(treated_post), "\n")
  cat("Mean outcome in treated post:", mean(treated_post$outcome_sim, na.rm = TRUE), "\n")

  control <- df_sim %>%
    filter(is.na(g_placebo) | g_placebo == 0)

  cat("Control observations:", nrow(control), "\n")
  cat("Mean outcome in control:", mean(control$outcome_sim, na.rm = TRUE), "\n")

  naive_diff <- mean(treated_post$outcome_sim, na.rm = TRUE) - mean(control$outcome_sim, na.rm = TRUE)
  cat("Naive difference:", naive_diff, "\n")
  cat("Expected effect:", effect_size, "\n")
  cat("Ratio (should be ~1.0):", naive_diff / effect_size, "\n")
} else {
  cat("ERROR: No treated post-period observations!\n")
}

# Run estimator
cat("\n=== RUNNING CS ESTIMATOR ===\n")
result <- run_estimator_and_extract_p(df_sim, cfg, cluster_var = "state_abb")

cat("\nEstimate:", result$est, "(true effect:", effect_size, ")\n")
cat("SE:", result$se, "\n")
cat("P-value:", result$p, "\n")

if (is.finite(result$est) && is.finite(result$se) && result$se > 0) {
  t_stat <- result$est / result$se
  cat("t-statistic:", t_stat, "\n")

  if (result$p < 0.05) {
    cat("✓ Correctly reject null\n")
  } else {
    cat("✗ FAILED to reject - this is the power problem!\n")
    cat("\nPossible issues:\n")
    cat("- SE too large (", result$se, " vs estimate ", result$est, ")\n")
    cat("- SE/Est ratio:", result$se / result$est, "(should be < 2 for power)\n")
  }
}

# Check the impose_effect function
cat("\n=== CHECKING IMPOSE_EFFECT LOGIC ===\n")
test_sample <- df_sim %>%
  filter(!is.na(g_placebo) & g_placebo > 0) %>%
  arrange(unit_id, time_id) %>%
  group_by(unit_id) %>%
  slice(1:3) %>%
  ungroup() %>%
  select(unit_id, time_id, g_placebo, outcome, outcome_sim)

cat("Sample of treated units (first 3 periods each):\n")
print(test_sample %>% head(15), n = 15)
