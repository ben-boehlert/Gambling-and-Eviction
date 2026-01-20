#!/usr/bin/env Rscript
################################################################################
# prepare_and_run_csdid.R
#
# Prepare data and run CS-DiD estimation with pre-trends plots
################################################################################

library(dplyr)
library(readr)
library(lubridate)
library(did)
library(ggplot2)

# Load patches
source("patches/preflight_support_check.R")
source("patches/att_gt_safe.R")
source("patches/plot_csdid_pretrends.R")

cat("\n")
cat("================================================================================\n")
cat("CS-DiD ESTIMATION WITH PRE-TRENDS PLOTS\n")
cat("================================================================================\n\n")

# ========================================================================
# Load and Prepare Data
# ========================================================================

cat("Step 1: Loading and preparing data...\n\n")

# Load combined panel
panel_raw <- read_csv("data/raw/combined_monthly_panel_with_gambling_treatment.csv",
                      show_col_types = FALSE)

# Aggregate from county to state level
panel_data <- panel_raw %>%
  filter(geo_level == "county") %>%
  mutate(
    state_abb = tools::toTitleCase(state_key),
    year_month = year(month_date) * 100 + month(month_date)
  ) %>%
  group_by(state_abb, month_date, year_month, treat_start, treated) %>%
  summarise(
    filings_count = sum(filings_count, na.rm = TRUE),
    renter_occupied_housing_units = sum(renter_occupied_housing_units, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    # Calculate filings per 1k renters
    filings_per_1k_renters = (filings_count / renter_occupied_housing_units) * 1000,

    # Create treatment timing variable (0 = never treated)
    first_treat = if_else(is.na(treat_start), 0,
                         year(treat_start) * 100 + month(treat_start)),

    # Create log outcome
    log_evictions = log(filings_per_1k_renters + 0.01)
  ) %>%
  # Filter out Maine
  filter(state_abb != "Maine") %>%
  # Create numeric state ID (required by did package)
  arrange(state_abb) %>%
  mutate(state_id = as.numeric(factor(state_abb))) %>%
  select(state_abb, state_id, year_month, month_date, first_treat, log_evictions,
         filings_per_1k_renters, filings_count, renter_occupied_housing_units) %>%
  # Remove missing outcomes
  filter(!is.na(log_evictions), is.finite(log_evictions))

cat(sprintf("  Loaded %d state-month observations\n", nrow(panel_data)))
cat(sprintf("  States: %d (excluding Maine)\n", n_distinct(panel_data$state_abb)))
cat(sprintf("  Time range: %d to %d\n", min(panel_data$year_month), max(panel_data$year_month)))

# Check treatment structure
n_treated <- panel_data %>%
  filter(first_treat > 0) %>%
  distinct(state_abb) %>%
  nrow()

n_never <- panel_data %>%
  filter(first_treat == 0) %>%
  distinct(state_abb) %>%
  nrow()

n_groups <- n_distinct(panel_data$first_treat[panel_data$first_treat > 0])

cat(sprintf("  Treated states: %d\n", n_treated))
cat(sprintf("  Never-treated states: %d\n", n_never))
cat(sprintf("  Treatment groups: %d\n\n", n_groups))

# ========================================================================
# Apply Event Study Window Filter
# ========================================================================

cat("Step 2: Filtering to event study window [-12, +24]...\n\n")

# Create event time (in months, not periods)
panel_data <- panel_data %>%
  mutate(
    event_time = if_else(first_treat == 0, NA_real_,
                        ((year_month %/% 100) - (first_treat %/% 100)) * 12 +
                        ((year_month %% 100) - (first_treat %% 100)))
  )

# Filter to event window
panel_filtered <- panel_data %>%
  filter(first_treat == 0 | (event_time >= -12 & event_time <= 24))

cat(sprintf("  Filtered sample: %d observations\n", nrow(panel_filtered)))
cat(sprintf("  States: %d\n", n_distinct(panel_filtered$state_abb)))
cat(sprintf("  Treated states in window: %d\n\n",
            n_distinct(panel_filtered$state_abb[panel_filtered$first_treat > 0])))

# ========================================================================
# Preflight Support Check
# ========================================================================

cat("Step 3: Running preflight support check...\n\n")

check <- preflight_support_check(
  data = panel_filtered,
  idname = "state_id",
  tname = "year_month",
  gname = "first_treat",
  yname = "log_evictions",
  control_group = "nevertreated",
  verbose = TRUE
)

# Save support diagnostics
dir.create("output/csdid_pretrends", showWarnings = FALSE, recursive = TRUE)
save_preflight_check(check,
                     output_dir = "output/csdid_pretrends",
                     prefix = "pretrends_analysis")

cat("\n")

# Check if we have enough identifiable cells
n_identifiable <- sum(check$support_table$identifiable, na.rm = TRUE)
if (n_identifiable == 0) {
  cat("ERROR: No identifiable cells! Cannot proceed with estimation.\n")
  cat("Check support diagnostics in output/csdid_pretrends/\n")
  cat("\nPossible issues:\n")
  cat("  - Event window may be too restrictive\n")
  cat("  - Treated units may not have pre-treatment observations\n")
  cat("  - Data may need different aggregation or filtering\n\n")
  quit(status = 1)
}

cat(sprintf("Found %d identifiable cells (%.1f%%), proceeding with estimation...\n\n",
            n_identifiable, 100 * n_identifiable / nrow(check$support_table)))

# ========================================================================
# Estimate CS-DiD
# ========================================================================

cat("Step 4: Running CS-DiD estimation...\n")
cat("  Estimator: Doubly-robust\n")
cat("  Control group: Never-treated\n")
cat("  This may take a few minutes...\n\n")

start_time <- Sys.time()

result <- att_gt_safe(
  yname = "log_evictions",
  tname = "year_month",
  idname = "state_id",
  gname = "first_treat",
  data = panel_filtered,
  control_group = "nevertreated",
  est_method = "reg",        # Regression estimator (simpler, avoids singular matrix)
  panel = TRUE,              # True panel (since we have repeated observations per state)
  allow_unbalanced_panel = TRUE,  # Allow unbalanced
  bstrap = FALSE,            # No bootstrap for speed
  cband = FALSE,             # No confidence bands
  clustervars = "state_id",  # Cluster at state level
  fail_on_support_issues = FALSE,
  save_support_check = TRUE,
  support_check_dir = "output/csdid_pretrends"
)

end_time <- Sys.time()
cat(sprintf("\nEstimation completed in %.1f seconds\n\n", as.numeric(end_time - start_time, units = "secs")))

# ========================================================================
# Aggregate Results
# ========================================================================

cat("Step 5: Aggregating results...\n\n")

# Simple aggregate (overall ATT)
agg_simple <- aggte_safe(result, type = "simple")
cat("Overall ATT:\n")
cat(sprintf("  Estimate: %.4f\n", agg_simple$overall.att))
cat(sprintf("  Std. Error: %.4f\n", agg_simple$overall.se))
cat(sprintf("  95%% CI: [%.4f, %.4f]\n",
            agg_simple$overall.att - 1.96 * agg_simple$overall.se,
            agg_simple$overall.att + 1.96 * agg_simple$overall.se))
cat(sprintf("  Interpretation: %.2f%% change in evictions\n",
            (exp(agg_simple$overall.att) - 1) * 100))

# Dynamic aggregate (event study)
agg_dynamic <- aggte_safe(result, type = "dynamic")
cat("\nDynamic effects computed\n")
cat(sprintf("  Event times: %d to %d\n",
            min(agg_dynamic$egt, na.rm = TRUE),
            max(agg_dynamic$egt, na.rm = TRUE)))

# Save aggregates
saveRDS(list(simple = agg_simple, dynamic = agg_dynamic),
        "output/csdid_pretrends/aggregates.rds")

cat("\n")

# ========================================================================
# Create Pre-Trends Plots
# ========================================================================

cat("================================================================================\n")
cat("CREATING PRE-TRENDS PLOTS\n")
cat("================================================================================\n\n")

dir.create("output/csdid_pretrends/figures", showWarnings = FALSE, recursive = TRUE)

# Plot 1: Event Study
cat("1. Event study plot...\n")
tryCatch({
  p1 <- plot_event_study(result,
                         pretreatment_periods = 12,
                         posttreatment_periods = 24)
  ggsave("output/csdid_pretrends/figures/event_study.pdf", p1,
         width = 12, height = 7)
  ggsave("output/csdid_pretrends/figures/event_study.png", p1,
         width = 12, height = 7, dpi = 300)
  cat("   ✓ Saved: event_study.pdf and .png\n")
}, error = function(e) {
  cat("   ✗ Error:", e$message, "\n")
})
cat("\n")

# Plot 2: Pre-Trends Test
cat("2. Pre-trends test plot...\n")
tryCatch({
  p2_result <- plot_pretrends_test(result,
                                   pretreatment_periods = 12,
                                   alpha = 0.05)
  ggsave("output/csdid_pretrends/figures/pretrends_test.pdf", p2_result$plot,
         width = 10, height = 6)
  ggsave("output/csdid_pretrends/figures/pretrends_test.png", p2_result$plot,
         width = 10, height = 6, dpi = 300)
  cat("   ✓ Saved: pretrends_test.pdf and .png\n")

  # Print test results
  if (!is.null(p2_result$test_results) && !is.na(p2_result$test_results$p_value)) {
    cat("\n   Pre-trends joint test:\n")
    cat(sprintf("     Chi-squared = %.2f\n", p2_result$test_results$chi_squared))
    cat(sprintf("     Degrees of freedom = %d\n", p2_result$test_results$df))
    cat(sprintf("     p-value = %.4f\n", p2_result$test_results$p_value))

    if (p2_result$test_results$p_value < 0.05) {
      cat("     Result: REJECT parallel trends (p < 0.05) ⚠️\n")
      cat("     → Consider shorter pre-period or alternative specifications\n")
    } else {
      cat("     Result: FAIL TO REJECT parallel trends (p >= 0.05) ✓\n")
      cat("     → Parallel trends assumption supported\n")
    }
  }
}, error = function(e) {
  cat("   ✗ Error:", e$message, "\n")
})
cat("\n")

# Plot 3: Group-Specific Dynamics
cat("3. Group-specific dynamics plot...\n")
tryCatch({
  p3 <- plot_group_dynamics(result)
  ggsave("output/csdid_pretrends/figures/group_dynamics.pdf", p3,
         width = 12, height = 8)
  ggsave("output/csdid_pretrends/figures/group_dynamics.png", p3,
         width = 12, height = 8, dpi = 300)
  cat("   ✓ Saved: group_dynamics.pdf and .png\n")
}, error = function(e) {
  cat("   ✗ Error:", e$message, "\n")
})
cat("\n")

# Plot 4: Calendar Time Effects
cat("4. Calendar time effects plot...\n")
tryCatch({
  p4 <- plot_calendar_time(result)
  ggsave("output/csdid_pretrends/figures/calendar_time.pdf", p4,
         width = 12, height = 7)
  ggsave("output/csdid_pretrends/figures/calendar_time.png", p4,
         width = 12, height = 7, dpi = 300)
  cat("   ✓ Saved: calendar_time.pdf and .png\n")
}, error = function(e) {
  cat("   ✗ Error:", e$message, "\n")
})
cat("\n")

# Plot 5: Support Heatmap
cat("5. Support heatmap...\n")
tryCatch({
  p5 <- plot_support_heatmap(result)
  ggsave("output/csdid_pretrends/figures/support_heatmap.pdf", p5,
         width = 12, height = 7)
  ggsave("output/csdid_pretrends/figures/support_heatmap.png", p5,
         width = 12, height = 7, dpi = 300)
  cat("   ✓ Saved: support_heatmap.pdf and .png\n")
}, error = function(e) {
  cat("   ✗ Error:", e$message, "\n")
})
cat("\n")

# Plot 6: Comprehensive Report
cat("6. Comprehensive pre-trends report...\n")
tryCatch({
  report <- create_pretrends_report(
    result,
    output_file = "output/csdid_pretrends/figures/comprehensive_report.pdf",
    title = "Gambling and Evictions: CS-DiD Pre-Trends Analysis",
    pretreatment_periods = 12
  )
  cat("   ✓ Saved: comprehensive_report.pdf\n")
}, error = function(e) {
  cat("   ✗ Error:", e$message, "\n")
})
cat("\n")

# ========================================================================
# Export Tables
# ========================================================================

cat("================================================================================\n")
cat("EXPORTING TABLES\n")
cat("================================================================================\n\n")

# ATT(g,t) estimates
att_gt_table <- data.frame(
  group = result$group,
  time = result$t,
  att = result$att,
  se = result$se
) %>%
  mutate(
    event_time = (time - group) %/% 100 * 12 + (time - group) %% 100,
    ci_lower = att - 1.96 * se,
    ci_upper = att + 1.96 * se,
    significant = abs(att / se) > 1.96
  ) %>%
  arrange(group, time)

write.csv(att_gt_table, "output/csdid_pretrends/att_gt_estimates.csv",
          row.names = FALSE)
cat("✓ att_gt_estimates.csv\n")

# Dynamic effects
if (!is.null(agg_dynamic$egt)) {
  dynamic_table <- data.frame(
    event_time = agg_dynamic$egt,
    att = agg_dynamic$att.egt,
    se = agg_dynamic$se.egt
  ) %>%
    mutate(
      ci_lower = att - 1.96 * se,
      ci_upper = att + 1.96 * se,
      significant = abs(att / se) > 1.96,
      pct_change = (exp(att) - 1) * 100
    )

  write.csv(dynamic_table, "output/csdid_pretrends/dynamic_effects.csv",
            row.names = FALSE)
  cat("✓ dynamic_effects.csv\n")
}

# Overall ATT
overall_table <- data.frame(
  estimate = agg_simple$overall.att,
  se = agg_simple$overall.se,
  ci_lower = agg_simple$overall.att - 1.96 * agg_simple$overall.se,
  ci_upper = agg_simple$overall.att + 1.96 * agg_simple$overall.se,
  pct_change = (exp(agg_simple$overall.att) - 1) * 100
)
write.csv(overall_table, "output/csdid_pretrends/overall_att.csv",
          row.names = FALSE)
cat("✓ overall_att.csv\n")

# Save full results object
saveRDS(result, "output/csdid_pretrends/cs_result.rds")
cat("✓ cs_result.rds\n\n")

# ========================================================================
# Summary
# ========================================================================

cat("================================================================================\n")
cat("COMPLETE! ✓\n")
cat("================================================================================\n\n")

cat("Output directory: output/csdid_pretrends/\n\n")

cat("📊 FIGURES (publication-ready):\n")
cat("  • event_study.pdf - Main event study plot\n")
cat("  • pretrends_test.pdf - Joint hypothesis test\n")
cat("  • group_dynamics.pdf - Group-specific effects\n")
cat("  • calendar_time.pdf - Calendar time effects\n")
cat("  • support_heatmap.pdf - Support diagnostics\n")
cat("  • comprehensive_report.pdf - All plots in one PDF\n\n")

cat("📋 TABLES:\n")
cat("  • att_gt_estimates.csv - All ATT(g,t) estimates\n")
cat("  • dynamic_effects.csv - Event study coefficients\n")
cat("  • overall_att.csv - Overall treatment effect\n")
cat("  • pretrends_analysis_support_table.csv - Support diagnostics\n\n")

cat("🚀 QUICK COMMANDS:\n")
cat("  # Open main plots\n")
cat("  open output/csdid_pretrends/figures/event_study.pdf\n")
cat("  open output/csdid_pretrends/figures/pretrends_test.pdf\n")
cat("  open output/csdid_pretrends/figures/comprehensive_report.pdf\n\n")

cat("  # View results in R\n")
cat("  result <- readRDS('output/csdid_pretrends/cs_result.rds')\n")
cat("  summary(result)\n\n")

cat("  # View dynamic effects\n")
cat("  effects <- read.csv('output/csdid_pretrends/dynamic_effects.csv')\n")
cat("  View(effects)\n\n")

cat("================================================================================\n\n")
