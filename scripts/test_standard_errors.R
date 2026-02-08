#!/usr/bin/env Rscript
################################################################################
# test_standard_errors.R
#
# Diagnostic tests for standard error estimation in event study
#
# Tests include:
# 1. Compare clustering methods (state vs. state-time)
# 2. Wild cluster bootstrap
# 3. Residual diagnostics
# 4. Effective sample size calculation
# 5. Placebo tests
################################################################################

library(dplyr)
library(readr)
library(ggplot2)
library(fixest)
library(fwildclusterboot)

cat("\n")
cat("================================================================================\n")
cat("STANDARD ERROR DIAGNOSTICS\n")
cat("================================================================================\n\n")

# Load data
cat("Loading data...\n")
panel_data <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                       show_col_types = FALSE)

# Prepare data (same as main analysis)
panel_data <- panel_data %>%
  mutate(
    month_date_parsed = as.Date(month_date),
    first_treat_date = treat_start,
    event_time = as.numeric(difftime(month_date_parsed, first_treat_date, units = "days")) / 30.44,
    event_time = round(event_time),
    log_evictions = log(filings_count + 1),
    treated_ever = ifelse(!is.na(first_treat_date), 1, 0)
  ) %>%
  filter(!is.na(log_evictions))

# Create event time bins (same as main analysis)
panel_data <- panel_data %>%
  mutate(
    event_bin = case_when(
      is.na(event_time) ~ "Never treated",
      event_time < -12 ~ "Exclude",
      event_time == -12 ~ "-12",
      event_time == -11 ~ "-11",
      event_time == -10 ~ "-10",
      event_time == -9 ~ "-9",
      event_time == -8 ~ "-8",
      event_time == -7 ~ "-7",
      event_time == -6 ~ "-6",
      event_time == -5 ~ "-5",
      event_time == -4 ~ "-4",
      event_time == -3 ~ "-3",
      event_time == -2 ~ "-2",
      event_time == -1 ~ "-1",
      event_time == 0 ~ "0",
      event_time == 1 ~ "1",
      event_time == 2 ~ "2",
      event_time == 3 ~ "3",
      event_time == 4 ~ "4",
      event_time == 5 ~ "5",
      event_time == 6 ~ "6",
      event_time == 7 ~ "7",
      event_time == 8 ~ "8",
      event_time == 9 ~ "9",
      event_time == 10 ~ "10",
      event_time == 11 ~ "11",
      event_time == 12 ~ "12",
      event_time == 13 ~ "13",
      event_time == 14 ~ "14",
      event_time == 15 ~ "15",
      event_time == 16 ~ "16",
      event_time == 17 ~ "17",
      event_time == 18 ~ "18",
      event_time == 19 ~ "19",
      event_time == 20 ~ "20",
      event_time == 21 ~ "21",
      event_time == 22 ~ "22",
      event_time == 23 ~ "23",
      event_time == 24 ~ "24",
      event_time > 24 ~ "Exclude"
    )
  ) %>%
  filter(event_bin != "Exclude") %>%
  mutate(event_bin = factor(event_bin, levels = c("Never treated", "-12", "-11", "-10", "-9", "-8", "-7", "-6", "-5", "-4", "-3", "-2", "-1", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20", "21", "22", "23", "24")))

panel_reg <- panel_data %>%
  filter(event_bin != "-1") %>%
  mutate(
    state_id = as.integer(factor(state_abb)),
    year_month = as.integer(format(month_date_parsed, "%Y%m"))
  )

cat(sprintf("  Sample size: %d observations\n", nrow(panel_reg)))
cat(sprintf("  Number of clusters (states): %d\n", n_distinct(panel_reg$state_id)))
cat(sprintf("  Avg obs per cluster: %.1f\n\n", nrow(panel_reg) / n_distinct(panel_reg$state_id)))

# ========================================================================
# Test 1: Compare Different Clustering Methods
# ========================================================================

cat("Test 1: Comparing clustering methods...\n")
cat("========================================================================\n\n")

# Model 1: State clustering (baseline)
model_state <- feols(log_evictions ~ event_bin | state_id + year_month,
                     data = panel_reg,
                     cluster = ~state_id)

# Model 2: Two-way clustering (state + time)
model_twoway <- feols(log_evictions ~ event_bin | state_id + year_month,
                      data = panel_reg,
                      cluster = ~state_id + year_month)

# Model 3: No clustering (for comparison - definitely wrong)
model_nocl <- feols(log_evictions ~ event_bin | state_id + year_month,
                    data = panel_reg,
                    se = "standard")

# Extract SEs for a few key coefficients
extract_se <- function(model, coef_name) {
  se <- summary(model)$coeftable[coef_name, "Std. Error"]
  return(se)
}

# Compare SEs for month 0 (treatment effect)
coef_name <- "event_bin0"
se_state <- extract_se(model_state, coef_name)
se_twoway <- extract_se(model_twoway, coef_name)
se_nocl <- extract_se(model_nocl, coef_name)

cat(sprintf("Standard errors for event_bin0 (month 0):\n"))
cat(sprintf("  State clustering:    %.4f\n", se_state))
cat(sprintf("  Two-way clustering:  %.4f (%.1f%% of state)\n",
            se_twoway, 100 * se_twoway / se_state))
cat(sprintf("  No clustering:       %.4f (%.1f%% of state)\n\n",
            se_nocl, 100 * se_nocl / se_state))

# ========================================================================
# Test 2: Wild Cluster Bootstrap
# ========================================================================

cat("Test 2: Wild cluster bootstrap (this may take a minute)...\n")
cat("========================================================================\n\n")

# Focus on treatment indicator
panel_reg <- panel_reg %>%
  mutate(post_treat = as.numeric(event_bin %in% as.character(0:24)))

# Simple model for wild bootstrap
model_simple <- feols(log_evictions ~ post_treat | state_id + year_month,
                      data = panel_reg,
                      cluster = ~state_id)

cat("Running wild cluster bootstrap with 999 iterations...\n")
boot_result <- tryCatch({
  boottest(model_simple,
           param = "post_treat",
           clustid = "state_id",
           B = 999,
           type = "rademacher")
}, error = function(e) {
  cat("  Error in wild bootstrap:", e$message, "\n")
  NULL
})

if (!is.null(boot_result)) {
  cat(sprintf("\nWild bootstrap results for post-treatment indicator:\n"))
  cat(sprintf("  Coefficient:      %.4f\n", coef(model_simple)["post_treat"]))
  cat(sprintf("  Cluster SE:       %.4f\n", summary(model_simple)$coeftable["post_treat", "Std. Error"]))
  cat(sprintf("  Bootstrap p-value: %.4f\n", boot_result$p_val))
  cat(sprintf("  95%% Bootstrap CI: [%.4f, %.4f]\n\n",
              boot_result$conf_int[1], boot_result$conf_int[2]))
}

# ========================================================================
# Test 3: Effective Sample Size & Degrees of Freedom
# ========================================================================

cat("Test 3: Effective sample size analysis...\n")
cat("========================================================================\n\n")

# With few clusters, degrees of freedom matter
n_clusters <- n_distinct(panel_reg$state_id)
n_treated <- n_distinct(panel_reg$state_id[panel_reg$treated_ever == 1])
n_control <- n_clusters - n_treated

cat(sprintf("Cluster structure:\n"))
cat(sprintf("  Total clusters: %d\n", n_clusters))
cat(sprintf("  Treated clusters: %d\n", n_treated))
cat(sprintf("  Control clusters: %d\n", n_control))
cat(sprintf("  Effective DF (G-2): %d\n\n", n_clusters - 2))

# Check if we should use t-distribution instead of normal
cat("Critical values comparison:\n")
cat(sprintf("  Normal (z=1.96): 1.960\n"))
cat(sprintf("  t(%d) at 0.025: %.3f\n\n", n_clusters - 2, qt(0.975, n_clusters - 2)))

# ========================================================================
# Test 4: Residual Diagnostics
# ========================================================================

cat("Test 4: Residual diagnostics...\n")
cat("========================================================================\n\n")

# Get residuals
panel_reg$resid <- resid(model_state)

# Check for autocorrelation within states
panel_reg <- panel_reg %>%
  arrange(state_id, year_month) %>%
  group_by(state_id) %>%
  mutate(resid_lag = lag(resid)) %>%
  ungroup()

# Autocorrelation
autocorr <- cor(panel_reg$resid, panel_reg$resid_lag, use = "complete.obs")
cat(sprintf("First-order autocorrelation: %.3f\n", autocorr))

if (abs(autocorr) > 0.3) {
  cat("  ⚠ Warning: High autocorrelation suggests SEs may be underestimated\n")
  cat("    Consider: HAC (Newey-West) standard errors or additional lags\n\n")
} else {
  cat("  ✓ Autocorrelation is low\n\n")
}

# Check heteroskedasticity by group
resid_by_state <- panel_reg %>%
  group_by(state_id) %>%
  summarise(
    sd_resid = sd(resid, na.rm = TRUE),
    mean_resid = mean(resid, na.rm = TRUE)
  )

cat(sprintf("Residual variation across states:\n"))
cat(sprintf("  Min SD: %.3f\n", min(resid_by_state$sd_resid)))
cat(sprintf("  Max SD: %.3f\n", max(resid_by_state$sd_resid)))
cat(sprintf("  Ratio (Max/Min): %.2f\n\n", max(resid_by_state$sd_resid) / min(resid_by_state$sd_resid)))

# ========================================================================
# Test 5: Placebo Test (Pre-treatment Period)
# ========================================================================

cat("Test 5: Placebo test using only pre-treatment period...\n")
cat("========================================================================\n\n")

# Use only pre-treatment data
panel_pre <- panel_reg %>%
  filter(event_bin %in% c("Never treated", "-12", "-11", "-10", "-9", "-8", "-7", "-6", "-5", "-4", "-3", "-2", "-1"))

# Create fake treatment at t=-6
panel_pre <- panel_pre %>%
  mutate(
    fake_post = as.numeric(event_bin %in% c("-5", "-4", "-3", "-2", "-1"))
  )

# Estimate with fake treatment
model_placebo <- feols(log_evictions ~ fake_post | state_id + year_month,
                       data = panel_pre,
                       cluster = ~state_id)

placebo_coef <- coef(model_placebo)["fake_post"]
placebo_se <- summary(model_placebo)$coeftable["fake_post", "Std. Error"]
placebo_t <- placebo_coef / placebo_se
placebo_p <- 2 * (1 - pnorm(abs(placebo_t)))

cat(sprintf("Placebo treatment effect (should be ≈ 0):\n"))
cat(sprintf("  Coefficient: %.4f\n", placebo_coef))
cat(sprintf("  Std Error:   %.4f\n", placebo_se))
cat(sprintf("  t-statistic: %.2f\n", placebo_t))
cat(sprintf("  p-value:     %.4f\n\n", placebo_p))

if (placebo_p < 0.05) {
  cat("  ⚠ Warning: Placebo test rejects null (p < 0.05)\n")
  cat("    This suggests specification issues or SEs are too small\n\n")
} else {
  cat("  ✓ Placebo test passed (p >= 0.05)\n\n")
}

# ========================================================================
# Test 6: Power Analysis
# ========================================================================

cat("Test 6: Statistical power analysis...\n")
cat("========================================================================\n\n")

# Using the observed SEs, what effect size could we detect?
se_month0 <- extract_se(model_state, "event_bin0")
n_clusters_eff <- n_clusters

# Minimum detectable effect (MDE) at 80% power
mde_80 <- (qnorm(0.975) + qnorm(0.80)) * se_month0

cat(sprintf("Statistical power given %d clusters:\n", n_clusters))
cat(sprintf("  Observed SE (month 0): %.4f\n", se_month0))
cat(sprintf("  Min detectable effect (80%% power, α=0.05): %.4f\n", mde_80))
cat(sprintf("  In percentage terms: %.1f%%\n\n", 100 * (exp(mde_80) - 1)))

# What's our power to detect a 10% effect?
effect_10pct <- log(1.10)
power_10pct <- pnorm((effect_10pct / se_month0) - qnorm(0.975))
cat(sprintf("Power to detect 10%% effect: %.1f%%\n", 100 * power_10pct))

# What's our power to detect a 20% effect?
effect_20pct <- log(1.20)
power_20pct <- pnorm((effect_20pct / se_month0) - qnorm(0.975))
cat(sprintf("Power to detect 20%% effect: %.1f%%\n\n", 100 * power_20pct))

# ========================================================================
# Summary and Recommendations
# ========================================================================

cat("================================================================================\n")
cat("SUMMARY AND RECOMMENDATIONS\n")
cat("================================================================================\n\n")

cat("Key Findings:\n")
cat(sprintf("1. Small sample: Only %d state clusters\n", n_clusters))
cat(sprintf("2. Large SEs reflect genuine uncertainty with N=%d clusters\n", n_clusters))
cat(sprintf("3. Minimum detectable effect: %.1f%%\n", 100 * (exp(mde_80) - 1)))
cat("\nPotential Issues:\n")
if (abs(autocorr) > 0.3) {
  cat("  ⚠ High autocorrelation in residuals\n")
}
if (n_clusters < 40) {
  cat("  ⚠ Few clusters - consider wild cluster bootstrap\n")
}
cat("\nRecommendations:\n")
cat("1. Use wild cluster bootstrap for inference (more conservative)\n")
cat(sprintf("2. Consider t(%d) critical values instead of normal\n", n_clusters - 2))
cat("3. Report power analysis showing MDEs\n")
cat("4. If SEs seem too large: check for measurement error in outcome\n")
cat("5. Consider county-level analysis for more statistical power\n\n")

# Save diagnostic output
dir.create("output/csdid_pretrends/diagnostics", showWarnings = FALSE, recursive = TRUE)

# Save comparison table
se_comparison <- data.frame(
  Method = c("State clustering", "Two-way clustering", "No clustering"),
  SE = c(se_state, se_twoway, se_nocl),
  Relative = c(1.0, se_twoway/se_state, se_nocl/se_state)
)

write.csv(se_comparison, "output/csdid_pretrends/diagnostics/se_comparison.csv",
          row.names = FALSE)

cat("Saved diagnostics to: output/csdid_pretrends/diagnostics/\n\n")
cat("================================================================================\n\n")
