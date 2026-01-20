#!/usr/bin/env Rscript
################################################################################
# verify_test_size.R
#
# Verify that our test has correct size (Type I error rate)
# Under the null hypothesis (no treatment effect), we should reject ~5% of the time
#
# If we reject < 5%, the test is too conservative (SEs too large)
# If we reject > 5%, the test is too liberal (SEs too small)
################################################################################

library(dplyr)
library(readr)
library(fixest)

set.seed(42)

cat("\n")
cat("================================================================================\n")
cat("TEST SIZE VERIFICATION: Should reject H0 5% of time when H0 is true\n")
cat("================================================================================\n\n")

# Load real data structure
panel_data <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                       show_col_types = FALSE)

# Prepare data
panel_data <- panel_data %>%
  mutate(
    month_date_parsed = as.Date(month_date),
    first_treat_date = treat_start,
    event_time = as.numeric(difftime(month_date_parsed, first_treat_date, units = "days")) / 30.44,
    event_time = round(event_time),
    log_evictions = log(filings_count + 1),
    treated_ever = ifelse(!is.na(first_treat_date), 1, 0),
    state_id = as.integer(factor(state_abb)),
    year_month = as.integer(format(month_date_parsed, "%Y%m"))
  ) %>%
  filter(!is.na(log_evictions))

# Create event bins
panel_data <- panel_data %>%
  mutate(
    event_bin = case_when(
      is.na(event_time) ~ "Never treated",
      event_time < -12 ~ "Exclude",
      event_time >= -12 & event_time <= 24 ~ as.character(event_time),
      event_time > 24 ~ "Exclude"
    )
  ) %>%
  filter(event_bin != "Exclude")

cat(sprintf("Data structure:\n"))
cat(sprintf("  N observations: %d\n", nrow(panel_data)))
cat(sprintf("  N states: %d\n", n_distinct(panel_data$state_id)))
cat(sprintf("  N treated: %d\n", sum(panel_data$treated_ever == 1 & !duplicated(panel_data$state_id))))
cat(sprintf("  N control: %d\n\n", sum(panel_data$treated_ever == 0 & !duplicated(panel_data$state_id))))

# ========================================================================
# Simulation 1: Permutation Test (Null is true by design)
# ========================================================================

cat("Simulation 1: Permutation test (randomly reassign treatment)\n")
cat("========================================================================\n")
cat("If test has correct size, should reject ~5% of 1000 permutations\n\n")

n_sims <- 1000
reject_count <- 0
p_values <- numeric(n_sims)

cat("Running permutations")

for (i in 1:n_sims) {
  if (i %% 100 == 0) cat(".")

  # Randomly reassign treatment status (keeping same N treated)
  treated_states <- sample(unique(panel_data$state_id),
                          sum(panel_data$treated_ever == 1 & !duplicated(panel_data$state_id)))

  sim_data <- panel_data %>%
    mutate(
      sim_treated = state_id %in% treated_states,
      sim_post = event_time >= 0 & sim_treated
    )

  # Estimate treatment effect
  tryCatch({
    model <- feols(log_evictions ~ sim_post | state_id + year_month,
                   data = sim_data,
                   cluster = ~state_id)

    # Get p-value for treatment effect
    p_val <- summary(model)$coeftable["sim_postTRUE", "Pr(>|t|)"]
    p_values[i] <- p_val

    if (p_val < 0.05) {
      reject_count <- reject_count + 1
    }
  }, error = function(e) {
    p_values[i] <<- NA
  })
}

cat("\n\n")
reject_rate <- reject_count / n_sims
cat(sprintf("Results:\n"))
cat(sprintf("  Rejections: %d / %d\n", reject_count, n_sims))
cat(sprintf("  Rejection rate: %.1f%%\n", 100 * reject_rate))
cat(sprintf("  Expected (if correct): 5.0%%\n\n"))

if (reject_rate < 0.03) {
  cat("  ⚠ Test is TOO CONSERVATIVE (rejecting < 3%)\n")
  cat("     → Standard errors are too large\n")
  cat("     → Likely cause: High autocorrelation not accounted for\n\n")
} else if (reject_rate > 0.07) {
  cat("  ⚠ Test is TOO LIBERAL (rejecting > 7%)\n")
  cat("     → Standard errors are too small\n\n")
} else {
  cat("  ✓ Test has approximately correct size\n\n")
}

# ========================================================================
# Simulation 2: Placebo Treatment Dates
# ========================================================================

cat("Simulation 2: Placebo treatment dates (shift actual treatment)\n")
cat("========================================================================\n")
cat("Shift treatment dates by random amounts - should reject ~5%\n\n")

n_sims2 <- 500
reject_count2 <- 0
p_values2 <- numeric(n_sims2)

cat("Running placebo simulations")

for (i in 1:n_sims2) {
  if (i %% 50 == 0) cat(".")

  # Shift treatment dates by random amount (-6 to +6 months)
  sim_data <- panel_data %>%
    group_by(state_id) %>%
    mutate(
      shift = ifelse(treated_ever == 1, sample(-6:6, 1), 0),
      sim_event_time = event_time - shift,
      sim_post = sim_event_time >= 0 & treated_ever == 1
    ) %>%
    ungroup()

  tryCatch({
    model <- feols(log_evictions ~ sim_post | state_id + year_month,
                   data = sim_data,
                   cluster = ~state_id)

    p_val <- summary(model)$coeftable["sim_postTRUE", "Pr(>|t|)"]
    p_values2[i] <- p_val

    if (p_val < 0.05) {
      reject_count2 <- reject_count2 + 1
    }
  }, error = function(e) {
    p_values2[i] <<- NA
  })
}

cat("\n\n")
reject_rate2 <- reject_count2 / n_sims2
cat(sprintf("Results:\n"))
cat(sprintf("  Rejections: %d / %d\n", reject_count2, n_sims2))
cat(sprintf("  Rejection rate: %.1f%%\n", 100 * reject_rate2))
cat(sprintf("  Expected (if correct): 5.0%%\n\n"))

# ========================================================================
# Simulation 3: Generate Data Under Null (DGP with no effect)
# ========================================================================

cat("Simulation 3: Simulated data with known null (no treatment effect)\n")
cat("========================================================================\n")
cat("Generate data matching real structure but with zero treatment effect\n\n")

# Estimate baseline model to get residual structure
baseline <- feols(log_evictions ~ 1 | state_id + year_month,
                  data = panel_data,
                  cluster = ~state_id)

# Get state and time fixed effects
state_fe <- fixef(baseline)$state_id
time_fe <- fixef(baseline)$year_month

n_sims3 <- 500
reject_count3 <- 0
p_values3 <- numeric(n_sims3)

cat("Running DGP simulations")

for (i in 1:n_sims3) {
  if (i %% 50 == 0) cat(".")

  # Generate outcome under null (no treatment effect)
  sim_data <- panel_data %>%
    mutate(
      # Add state FE + time FE + random error
      sim_y = state_fe[as.character(state_id)] +
              time_fe[as.character(year_month)] +
              rnorm(n(), 0, sd(baseline$residuals, na.rm = TRUE)),
      post_treat = event_time >= 0 & treated_ever == 1
    )

  tryCatch({
    model <- feols(sim_y ~ post_treat | state_id + year_month,
                   data = sim_data,
                   cluster = ~state_id)

    p_val <- summary(model)$coeftable["post_treatTRUE", "Pr(>|t|)"]
    p_values3[i] <- p_val

    if (p_val < 0.05) {
      reject_count3 <- reject_count3 + 1
    }
  }, error = function(e) {
    p_values3[i] <<- NA
  })
}

cat("\n\n")
reject_rate3 <- reject_count3 / n_sims3
cat(sprintf("Results:\n"))
cat(sprintf("  Rejections: %d / %d\n", reject_count3, n_sims3))
cat(sprintf("  Rejection rate: %.1f%%\n", 100 * reject_rate3))
cat(sprintf("  Expected (if correct): 5.0%%\n\n"))

# ========================================================================
# Analysis of p-value distribution
# ========================================================================

cat("Analysis of p-value distributions:\n")
cat("========================================================================\n\n")

# Under null, p-values should be uniform [0,1]
# Check if they're shifted toward 1 (too conservative)

cat(sprintf("Permutation test p-values:\n"))
cat(sprintf("  Mean: %.3f (should be ~0.5)\n", mean(p_values, na.rm = TRUE)))
cat(sprintf("  Median: %.3f (should be ~0.5)\n", median(p_values, na.rm = TRUE)))
cat(sprintf("  % < 0.05: %.1f%% (should be ~5%%)\n", 100 * mean(p_values < 0.05, na.rm = TRUE)))
cat(sprintf("  % < 0.10: %.1f%% (should be ~10%%)\n\n", 100 * mean(p_values < 0.10, na.rm = TRUE)))

cat(sprintf("Placebo dates p-values:\n"))
cat(sprintf("  Mean: %.3f (should be ~0.5)\n", mean(p_values2, na.rm = TRUE)))
cat(sprintf("  Median: %.3f (should be ~0.5)\n", median(p_values2, na.rm = TRUE)))
cat(sprintf("  % < 0.05: %.1f%% (should be ~5%%)\n", 100 * mean(p_values2 < 0.05, na.rm = TRUE)))
cat(sprintf("  % < 0.10: %.1f%% (should be ~10%%)\n\n", 100 * mean(p_values2 < 0.10, na.rm = TRUE)))

cat(sprintf("Simulated DGP p-values:\n"))
cat(sprintf("  Mean: %.3f (should be ~0.5)\n", mean(p_values3, na.rm = TRUE)))
cat(sprintf("  Median: %.3f (should be ~0.5)\n", median(p_values3, na.rm = TRUE)))
cat(sprintf("  % < 0.05: %.1f%% (should be ~5%%)\n", 100 * mean(p_values3 < 0.05, na.rm = TRUE)))
cat(sprintf("  % < 0.10: %.1f%% (should be ~10%%)\n\n", 100 * mean(p_values3 < 0.10, na.rm = TRUE)))

# ========================================================================
# Summary
# ========================================================================

cat("================================================================================\n")
cat("SUMMARY\n")
cat("================================================================================\n\n")

avg_reject <- mean(c(reject_rate, reject_rate2, reject_rate3))

cat(sprintf("Average rejection rate across all tests: %.1f%%\n\n", 100 * avg_reject))

if (avg_reject < 0.03) {
  cat("DIAGNOSIS: Test is TOO CONSERVATIVE\n")
  cat("  → You're rejecting the null < 3% of the time when it's true\n")
  cat("  → Standard errors are INFLATED (too large)\n\n")
  cat("LIKELY CAUSES:\n")
  cat("  1. High autocorrelation (AR=0.82) makes cluster SEs too large\n")
  cat("  2. Small number of clusters (G=32) increases conservative bias\n")
  cat("  3. Cluster SE formula may be over-correcting\n\n")
  cat("SOLUTIONS:\n")
  cat("  1. Use HAC (Newey-West) standard errors\n")
  cat("  2. Aggregate to quarters to reduce autocorrelation\n")
  cat("  3. Use wild cluster bootstrap (already showing p=0.90)\n")
  cat("  4. Use degrees-of-freedom correction (t-distribution)\n\n")
} else if (avg_reject > 0.07) {
  cat("DIAGNOSIS: Test is TOO LIBERAL\n")
  cat("  → You're rejecting the null > 7% of the time when it's true\n")
  cat("  → Standard errors are too small\n\n")
} else {
  cat("DIAGNOSIS: Test size is approximately correct\n")
  cat("  → Rejecting ~5% when null is true\n")
  cat("  → Standard errors appear correctly calibrated\n\n")
}

cat("This explains your simulation results:\n")
cat("  • If test is too conservative, you won't detect real effects\n")
cat("  • CIs will include zero too often, even when true effect ≠ 0\n")
cat("  • This matches your finding of \"always finding zero effect\"\n\n")

cat("================================================================================\n\n")

# Save results
dir.create("output/csdid_pretrends/diagnostics", showWarnings = FALSE, recursive = TRUE)

results_df <- data.frame(
  Test = c("Permutation", "Placebo dates", "Simulated DGP", "Average"),
  N_sims = c(n_sims, n_sims2, n_sims3, NA),
  Rejection_rate = c(reject_rate, reject_rate2, reject_rate3, avg_reject),
  Expected = c(0.05, 0.05, 0.05, 0.05)
)

write.csv(results_df, "output/csdid_pretrends/diagnostics/test_size_verification.csv",
          row.names = FALSE)

cat("Results saved to: output/csdid_pretrends/diagnostics/test_size_verification.csv\n\n")
