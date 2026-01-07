#!/usr/bin/env Rscript
################################################################################
# test_month_fe_full_period.R
# Test if calendar month FE fixes pre-trends in the FULL monthly period
################################################################################

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(fixest)
  library(glue)
})

set.seed(123)

cat("=== Testing Month FE on Full Monthly Period (2016-2025) ===\n\n")

# Source the main simulation to get data loading functions
source("power_simulation_cs.R")

# Load panel data (FULL period - no COVID restriction)
panel_df <- load_panel(cfg)
treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)

# Build baseline (untreated sample) - FULL PERIOD
baseline_full <- build_untreated_sample(panel_df, treat_schedule_std)

cat(glue("Full baseline period: {min(baseline_full$month_date)} to {max(baseline_full$month_date)}\n"))
cat(glue("Total observations: {nrow(baseline_full)}\n"))
cat(glue("Units: {n_distinct(baseline_full$unit_id)}\n"))
cat(glue("Time periods: {n_distinct(baseline_full$time_id)}\n\n"))

# Save treatment indicators
treat_indicators <- baseline_full %>%
  distinct(unit_id, g_id, ever_treated)

# Add calendar month variable
baseline_with_month <- baseline_full %>%
  mutate(month = month(month_date))

cat("=== TEST 1: Raw Pre-trends (No Controls) ===\n")
baseline_means <- baseline_with_month %>%
  group_by(ever_treated) %>%
  summarise(
    mean_outcome = mean(outcome, na.rm = TRUE),
    sd_outcome = sd(outcome, na.rm = TRUE),
    n = n()
  )
print(baseline_means)

t_test_raw <- t.test(outcome ~ ever_treated, data = baseline_with_month)
cat(glue("\nT-test: t = {round(t_test_raw$statistic, 3)}, p = {round(t_test_raw$p.value, 4)}\n\n"))

cat("=== TEST 2: Differential Trends WITHOUT Month FE ===\n")
model_no_month <- feols(outcome ~ time_id * ever_treated | unit_id,
                        data = baseline_with_month)
cat("Model: outcome ~ time_id * ever_treated | unit_id\n")
print(summary(model_no_month))

cat("\n=== TEST 3: Differential Trends WITH Calendar Month FE ===\n")
model_with_month <- feols(outcome ~ time_id * ever_treated | unit_id + month,
                          data = baseline_with_month)
cat("Model: outcome ~ time_id * ever_treated | unit_id + month\n")
print(summary(model_with_month))

# Extract key statistics
coef_no_month <- coef(model_no_month)["time_id:ever_treatedTRUE"]
se_no_month <- se(model_no_month)["time_id:ever_treatedTRUE"]
t_no_month <- coef_no_month / se_no_month
p_no_month <- 2 * pt(-abs(t_no_month), df = model_no_month$nobs - model_no_month$nparams)

coef_with_month <- coef(model_with_month)["time_id:ever_treatedTRUE"]
se_with_month <- se(model_with_month)["time_id:ever_treatedTRUE"]
t_with_month <- coef_with_month / se_with_month
p_with_month <- 2 * pt(-abs(t_with_month), df = model_with_month$nobs - model_with_month$nparams)

cat("\n=== COMPARISON ===\n")
cat(glue("WITHOUT month FE: coefficient = {round(coef_no_month, 5)}, t = {round(t_no_month, 3)}, p = {round(p_no_month, 4)}\n"))
cat(glue("WITH month FE:    coefficient = {round(coef_with_month, 5)}, t = {round(t_with_month, 3)}, p = {round(p_with_month, 4)}\n\n"))

if (p_no_month < 0.05 & p_with_month >= 0.05) {
  cat("✓ RESULT: Month FE FIXES the parallel trends violation!\n")
  cat("  Differential trends significant without month FE (p < 0.05)\n")
  cat("  Differential trends NOT significant with month FE (p >= 0.05)\n\n")
} else if (p_no_month < 0.05 & p_with_month < 0.05) {
  cat("✗ RESULT: Month FE does NOT fix the parallel trends violation.\n")
  cat("  Differential trends still significant even with month FE.\n\n")
} else {
  cat("? RESULT: Parallel trends hold in both models (p >= 0.05).\n")
  cat("  Month FE doesn't change the conclusion.\n\n")
}

cat("=== TEST 4: Type I Error with Full Period + Month FE ===\n")

# Test Type I error calibration with full period + month FE
test_type_i_month_fe <- function(n_sims = 50) {
  cluster_var <- if ("state_abb" %in% names(baseline_full)) "state_abb" else "unit_id"

  unit_state_map <- if ("state_abb" %in% names(baseline_full)) {
    baseline_full %>% distinct(unit_id, state_abb) %>% filter(!is.na(state_abb))
  } else {
    NULL
  }

  # Create residualized baseline with month FE
  m_month <- feols(outcome ~ 1 | unit_id + time_id + month, data = baseline_with_month)
  outcome_mean <- mean(baseline_with_month$outcome, na.rm = TRUE)
  baseline_resid <- baseline_with_month %>%
    mutate(outcome = resid(m_month) + outcome_mean) %>%
    select(-any_of(c("g_id", "ever_treated", "month")))

  p_values <- map_dbl(1:n_sims, function(i) {
    if (i %% 10 == 0) cat(".")

    tryCatch({
      placebo <- draw_placebo_schedule(treat_schedule_std, cfg,
                                       baseline_df = baseline_resid,
                                       n_switchers = NULL,
                                       unit_state_map = unit_state_map)
      df_sim <- impose_effect(baseline_resid, placebo, effect_size = 0, cfg)
      result <- run_estimator_and_extract_p(df_sim, cfg, cluster_var)
      if (is.list(result)) result$p else NA_real_
    }, error = function(e) NA_real_)
  })

  cat("\n")

  rejection_rate <- mean(p_values <= 0.05, na.rm = TRUE)
  na_rate <- mean(is.na(p_values))

  list(
    rejection_rate = rejection_rate,
    na_rate = na_rate,
    p_values = p_values
  )
}

cat("Running 50 simulations with full period + month FE...\n")
result_full_month <- test_type_i_month_fe(n_sims = 50)
cat(glue("Rejection rate: {round(result_full_month$rejection_rate * 100, 1)}%\n"))
cat(glue("NA rate: {round(result_full_month$na_rate * 100, 1)}%\n\n"))

cat("=== SUMMARY ===\n")
cat(glue("Full period (2016-2025) differential trends test:\n"))
cat(glue("  Without month FE: t = {round(t_no_month, 3)}, p = {round(p_no_month, 4)}\n"))
cat(glue("  With month FE:    t = {round(t_with_month, 3)}, p = {round(p_with_month, 4)}\n\n"))
cat(glue("Type I error with month FE: {round(result_full_month$rejection_rate * 100, 1)}% (target: 5%)\n\n"))

if (p_with_month >= 0.05 & result_full_month$rejection_rate <= 0.10) {
  cat("RECOMMENDATION: Use full period (2016-2025) with calendar month FE!\n")
  cat("  ✓ Parallel trends hold (p >= 0.05)\n")
  cat("  ✓ Type I error acceptable (<= 10%)\n")
  cat("  ✓ More data = more power\n")
} else {
  cat("RECOMMENDATION: Stick with pre-COVID period or investigate further.\n")
  if (p_with_month < 0.05) {
    cat("  ✗ Parallel trends still violated even with month FE\n")
  }
  if (result_full_month$rejection_rate > 0.10) {
    cat(glue("  ✗ Type I error too high ({round(result_full_month$rejection_rate * 100, 1)}%)\n"))
  }
}

# Save results
results_df <- tibble(
  period = "Full (2016-2025)",
  month_fe = c("No", "Yes"),
  diff_trend_coef = c(coef_no_month, coef_with_month),
  diff_trend_t = c(t_no_month, t_with_month),
  diff_trend_p = c(p_no_month, p_with_month),
  type_i_error = c(NA_real_, result_full_month$rejection_rate)
)

write_csv(results_df, "month_fe_full_period_results.csv")
cat("\nResults saved to month_fe_full_period_results.csv\n")
