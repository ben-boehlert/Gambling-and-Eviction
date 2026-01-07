#!/usr/bin/env Rscript
################################################################################
# test_seasonality.R
# Test whether correcting for seasonality fixes parallel trends violations
################################################################################

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(fixest)
  library(glue)
})

set.seed(123)

cat("=== Testing Seasonality Effects on Parallel Trends ===\n\n")

# Source the main simulation to get data loading functions
source("power_simulation_cs.R")

# Load panel data (pre-COVID monthly)
panel_df <- load_panel(cfg)
treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)

# Build baseline (untreated sample)
baseline_raw <- build_untreated_sample(panel_df, treat_schedule_std)

# Restrict to pre-COVID period
baseline_precovid <- baseline_raw %>%
  filter(month_date < as.Date("2020-03-01"))

cat(glue("Baseline period: {min(baseline_precovid$month_date)} to {max(baseline_precovid$month_date)}\n"))
cat(glue("Total observations: {nrow(baseline_precovid)}\n"))
cat(glue("Units: {n_distinct(baseline_precovid$unit_id)}\n"))
cat(glue("Time periods: {n_distinct(baseline_precovid$time_id)}\n\n"))

# Save treatment indicators before they get removed later
treat_indicators <- baseline_precovid %>%
  distinct(unit_id, g_id, ever_treated)

# Add month for seasonality
baseline_with_treat <- baseline_precovid %>%
  mutate(
    month = month(month_date),
    year = year(month_date)
  )

cat("=== TEST 1: Baseline Outcomes (No Residualization) ===\n")
baseline_means <- baseline_with_treat %>%
  group_by(ever_treated) %>%
  summarise(
    mean_outcome = mean(outcome, na.rm = TRUE),
    sd_outcome = sd(outcome, na.rm = TRUE),
    n = n()
  )
print(baseline_means)

t_test_raw <- t.test(outcome ~ ever_treated, data = baseline_with_treat)
cat(glue("\nT-test: t = {round(t_test_raw$statistic, 3)}, p = {round(t_test_raw$p.value, 4)}\n\n"))

cat("=== TEST 2: Differential Time Trends (No Seasonality Controls) ===\n")
model_no_season <- feols(outcome ~ time_id * ever_treated | unit_id,
                         data = baseline_with_treat)
print(summary(model_no_season))

cat("\n=== TEST 3: Differential Time Trends (WITH Month FE) ===\n")
model_with_season <- feols(outcome ~ time_id * ever_treated | unit_id + month,
                           data = baseline_with_treat)
print(summary(model_with_season))

cat("\n=== TEST 4: Residualization WITHOUT Seasonality ===\n")
# Standard residualization (unit + time FE only)
m1 <- feols(outcome ~ 1 | unit_id + time_id, data = baseline_with_treat)
outcome_mean <- mean(baseline_with_treat$outcome, na.rm = TRUE)
baseline_resid_no_season <- baseline_with_treat %>%
  mutate(outcome_resid = resid(m1) + outcome_mean)

# Test differential trends on residualized data
baseline_resid_no_season_test <- baseline_resid_no_season %>%
  select(-any_of(c("g_id", "ever_treated"))) %>%
  left_join(treat_indicators, by = "unit_id")

model_resid_no_season <- feols(outcome_resid ~ time_id * ever_treated | unit_id,
                               data = baseline_resid_no_season_test)
cat("After residualization (unit + time FE):\n")
print(summary(model_resid_no_season))

cat("\n=== TEST 5: Residualization WITH Seasonality (unit + time + month FE) ===\n")
# Residualization with month FE
m2 <- feols(outcome ~ 1 | unit_id + time_id + month, data = baseline_with_treat)
baseline_resid_with_season <- baseline_with_treat %>%
  mutate(outcome_resid = resid(m2) + outcome_mean)

# Test differential trends on seasonally-adjusted residualized data
baseline_resid_with_season_test <- baseline_resid_with_season %>%
  select(-any_of(c("g_id", "ever_treated"))) %>%
  left_join(treat_indicators, by = "unit_id")

model_resid_with_season <- feols(outcome_resid ~ time_id * ever_treated | unit_id,
                                 data = baseline_resid_with_season_test)
cat("After residualization (unit + time + month FE):\n")
print(summary(model_resid_with_season))

cat("\n=== TEST 6: Type I Error Calibration (No Seasonality) ===\n")

# Function to test a single simulation
test_type_i <- function(baseline_data, n_sims = 50) {
  cluster_var <- if ("state_abb" %in% names(baseline_data)) "state_abb" else "unit_id"

  unit_state_map <- if ("state_abb" %in% names(baseline_data)) {
    baseline_data %>% distinct(unit_id, state_abb) %>% filter(!is.na(state_abb))
  } else {
    NULL
  }

  p_values <- map_dbl(1:n_sims, function(i) {
    if (i %% 10 == 0) cat(".")

    tryCatch({
      placebo <- draw_placebo_schedule(treat_schedule_std, cfg,
                                       baseline_df = baseline_data,
                                       n_switchers = NULL,
                                       unit_state_map = unit_state_map)
      df_sim <- impose_effect(baseline_data, placebo, effect_size = 0, cfg)
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

# Test without seasonality correction
baseline_no_season <- baseline_resid_no_season %>%
  select(-any_of(c("g_id", "ever_treated", "outcome_resid", "month", "year")))

cat("Running 50 simulations without seasonality correction...\n")
result_no_season <- test_type_i(baseline_no_season, n_sims = 50)
cat(glue("Rejection rate: {round(result_no_season$rejection_rate * 100, 1)}%\n"))
cat(glue("NA rate: {round(result_no_season$na_rate * 100, 1)}%\n\n"))

cat("=== TEST 7: Type I Error Calibration (WITH Seasonality) ===\n")

# Test with seasonality correction
baseline_with_season_final <- baseline_resid_with_season %>%
  select(-any_of(c("g_id", "ever_treated", "outcome_resid", "month", "year")))

cat("Running 50 simulations with seasonality correction...\n")
result_with_season <- test_type_i(baseline_with_season_final, n_sims = 50)
cat(glue("Rejection rate: {round(result_with_season$rejection_rate * 100, 1)}%\n"))
cat(glue("NA rate: {round(result_with_season$na_rate * 100, 1)}%\n\n"))

cat("=== SUMMARY ===\n")
cat(glue("Without seasonality correction: {round(result_no_season$rejection_rate * 100, 1)}% rejection (target: 5%)\n"))
cat(glue("With seasonality correction:    {round(result_with_season$rejection_rate * 100, 1)}% rejection (target: 5%)\n"))
cat(glue("Improvement: {round((result_no_season$rejection_rate - result_with_season$rejection_rate) * 100, 1)} percentage points\n"))

# Save results
results_df <- tibble(
  method = c("No seasonality", "With month FE"),
  rejection_rate = c(result_no_season$rejection_rate, result_with_season$rejection_rate),
  na_rate = c(result_no_season$na_rate, result_with_season$na_rate)
)

write_csv(results_df, "seasonality_test_results.csv")
cat("\nResults saved to seasonality_test_results.csv\n")
