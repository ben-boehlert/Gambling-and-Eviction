#!/usr/bin/env Rscript
################################################################################
# run_csdid_pretrends.R
#
# Run CS-DiD estimation and generate pre-trends plots
################################################################################

library(dplyr)
library(readr)
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
# Load Data
# ========================================================================

cat("Loading data...\n")
panel_data <- readr::read_csv("data/raw/state_month_panel_with_treatment.csv",
                              show_col_types = FALSE)

cat(sprintf("  Loaded %d observations\n", nrow(panel_data)))
cat(sprintf("  Columns: %s\n\n", paste(names(panel_data), collapse = ", ")))

# Prepare data: convert month_date to year_month and treat_start to first_treat
cat("Preparing data for CS-DiD...\n")

# Create numeric state ID (CS-DiD requires numeric IDs)
state_lookup <- data.frame(
  state_abb = unique(panel_data$state_abb),
  state_id = seq_along(unique(panel_data$state_abb))
)

panel_data <- panel_data %>%
  left_join(state_lookup, by = "state_abb") %>%
  mutate(
    year_month = as.integer(format(as.Date(month_date), "%Y%m")),
    first_treat = case_when(
      is.na(treat_start) ~ 0,  # NA means never treated
      treat_start == "" ~ 0,    # Empty string means never treated
      TRUE ~ as.integer(format(as.Date(treat_start), "%Y%m"))
    ),
    log_evictions = log(filings_per_1k_renters + 0.001)  # Add small constant to avoid log(0)
  ) %>%
  filter(!is.na(year_month))  # Drop any rows with invalid dates

# Check data structure
cat("\nData structure:\n")
cat(sprintf("  Unique states: %d\n", n_distinct(panel_data$state_abb)))
cat(sprintf("  Time periods: %d to %d\n", min(panel_data$year_month), max(panel_data$year_month)))
cat(sprintf("  Treatment groups: %d\n", n_distinct(panel_data$first_treat[panel_data$first_treat > 0])))
cat(sprintf("  Never-treated states: %d\n\n", sum(panel_data$first_treat == 0 & !duplicated(panel_data$state_abb))))

# Create event time variable
panel_data <- panel_data %>%
  mutate(event_time = year_month - first_treat)

# Don't filter by event window - use full data for CS-DiD
# (CS-DiD will handle the event study aggregation automatically)
panel_filtered <- panel_data

cat(sprintf("  Using full panel data (no event window filtering)\n"))
cat(sprintf("  Final sample: %d observations\n", nrow(panel_filtered)))
cat(sprintf("  States in final sample: %d\n\n", n_distinct(panel_filtered$state_abb)))

# Check for missing values
missing_outcome <- sum(is.na(panel_filtered$log_evictions))
if (missing_outcome > 0) {
  cat(sprintf("  Warning: %d missing values in log_evictions\n", missing_outcome))
  panel_filtered <- panel_filtered %>% filter(!is.na(log_evictions))
  cat(sprintf("  Dropped missing values, new N = %d\n\n", nrow(panel_filtered)))
}

# ========================================================================
# Preflight Support Check
# ========================================================================

cat("Running preflight support check...\n\n")

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

# ========================================================================
# Estimate CS-DiD
# ========================================================================

cat("Running CS-DiD estimation...\n")
cat("  This may take a few minutes...\n\n")

result <- att_gt_safe(
  yname = "log_evictions",
  tname = "year_month",
  idname = "state_id",
  gname = "first_treat",
  data = panel_filtered,
  control_group = "nevertreated",
  est_method = "reg",        # Regression estimator (more stable than dr)
  panel = FALSE,             # Repeated cross-sections for unbalanced panel
  bstrap = FALSE,            # No bootstrap for speed (change to TRUE for final)
  cband = FALSE,             # No confidence bands for speed
  clustervars = "state_id",  # Cluster at state level
  fail_on_support_issues = FALSE,
  save_support_check = TRUE,
  support_check_dir = "output/csdid_pretrends"
)

cat("\nCS-DiD estimation complete!\n\n")

# ========================================================================
# Aggregate Results
# ========================================================================

cat("Aggregating results...\n")

# Simple aggregate (overall ATT)
agg_simple <- aggte_safe(result, type = "simple")
cat(sprintf("\nOverall ATT: %.4f (SE: %.4f)\n",
            agg_simple$overall.att, agg_simple$overall.se))
cat(sprintf("  95%% CI: [%.4f, %.4f]\n",
            agg_simple$overall.att - 1.96 * agg_simple$overall.se,
            agg_simple$overall.att + 1.96 * agg_simple$overall.se))

# Dynamic aggregate (event study)
agg_dynamic <- aggte_safe(result, type = "dynamic")
cat("\nDynamic effects computed\n")

# Save aggregates
saveRDS(list(simple = agg_simple, dynamic = agg_dynamic),
        "output/csdid_pretrends/aggregates.rds")

# ========================================================================
# Create Pre-Trends Plots
# ========================================================================

cat("\n")
cat("================================================================================\n")
cat("CREATING PRE-TRENDS PLOTS\n")
cat("================================================================================\n\n")

dir.create("output/csdid_pretrends/figures", showWarnings = FALSE, recursive = TRUE)

# Plot 1: Event Study
cat("1. Creating event study plot...\n")
p1 <- plot_event_study(result,
                       pretreatment_periods = 12,
                       posttreatment_periods = 24)
ggsave("output/csdid_pretrends/figures/event_study.pdf", p1,
       width = 12, height = 7)
ggsave("output/csdid_pretrends/figures/event_study.png", p1,
       width = 12, height = 7, dpi = 300)
cat("   Saved: event_study.pdf and .png\n\n")

# Plot 2: Pre-Trends Test
cat("2. Creating pre-trends test plot...\n")
p2_result <- plot_pretrends_test(result,
                                 pretreatment_periods = 12,
                                 alpha = 0.05)
ggsave("output/csdid_pretrends/figures/pretrends_test.pdf", p2_result$plot,
       width = 10, height = 6)
ggsave("output/csdid_pretrends/figures/pretrends_test.png", p2_result$plot,
       width = 10, height = 6, dpi = 300)
cat("   Saved: pretrends_test.pdf and .png\n")

# Print test results
if (!is.null(p2_result$test_results)) {
  cat("\n   Pre-trends joint test:\n")
  cat(sprintf("     Chi-squared = %.2f\n", p2_result$test_results$joint_chisq))
  cat(sprintf("     Degrees of freedom = %d\n", p2_result$test_results$joint_df))
  cat(sprintf("     p-value = %.4f\n", p2_result$test_results$joint_p))

  if (!is.na(p2_result$test_results$joint_p) && p2_result$test_results$joint_p < 0.05) {
    cat("     Result: REJECT parallel trends (p < 0.05)\n")
  } else if (!is.na(p2_result$test_results$joint_p)) {
    cat("     Result: FAIL TO REJECT parallel trends (p >= 0.05)\n")
  }
}
cat("\n")

# Plot 3: Group-Specific Dynamics
cat("3. Creating group-specific dynamics plot...\n")
p3 <- plot_group_dynamics(result)
ggsave("output/csdid_pretrends/figures/group_dynamics.pdf", p3,
       width = 12, height = 8)
ggsave("output/csdid_pretrends/figures/group_dynamics.png", p3,
       width = 12, height = 8, dpi = 300)
cat("   Saved: group_dynamics.pdf and .png\n\n")

# Plot 4: Calendar Time Effects
cat("4. Creating calendar time effects plot...\n")
p4 <- plot_calendar_time(result)
ggsave("output/csdid_pretrends/figures/calendar_time.pdf", p4,
       width = 12, height = 7)
ggsave("output/csdid_pretrends/figures/calendar_time.png", p4,
       width = 12, height = 7, dpi = 300)
cat("   Saved: calendar_time.pdf and .png\n\n")

# Plot 5: Support Heatmap
cat("5. Creating support heatmap...\n")
p5 <- plot_support_heatmap(result)
ggsave("output/csdid_pretrends/figures/support_heatmap.pdf", p5,
       width = 12, height = 7)
ggsave("output/csdid_pretrends/figures/support_heatmap.png", p5,
       width = 12, height = 7, dpi = 300)
cat("   Saved: support_heatmap.pdf and .png\n\n")

# ========================================================================
# Create Comprehensive Report
# ========================================================================

cat("6. Creating comprehensive pre-trends report...\n")
report <- create_pretrends_report(
  result,
  output_file = "output/csdid_pretrends/figures/comprehensive_report.pdf",
  alpha = 0.05
)
cat("   Saved: comprehensive_report.pdf\n\n")

# ========================================================================
# Export Tables
# ========================================================================

cat("Exporting tables...\n")

# ATT(g,t) estimates
att_gt_table <- data.frame(
  group = result$group,
  time = result$t,
  att = result$att,
  se = result$se,
  event_time = result$t - result$group
) %>%
  mutate(
    ci_lower = att - 1.96 * se,
    ci_upper = att + 1.96 * se,
    significant = abs(att / se) > 1.96
  ) %>%
  arrange(group, time)

write.csv(att_gt_table, "output/csdid_pretrends/att_gt_estimates.csv",
          row.names = FALSE)
cat("   Saved: att_gt_estimates.csv\n")

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
      significant = abs(att / se) > 1.96
    )

  write.csv(dynamic_table, "output/csdid_pretrends/dynamic_effects.csv",
            row.names = FALSE)
  cat("   Saved: dynamic_effects.csv\n")
}

# Pre-trends test results
if (!is.null(p2_result$test_results)) {
  write.csv(as.data.frame(p2_result$test_results),
            "output/csdid_pretrends/pretrends_test_results.csv",
            row.names = FALSE)
  cat("   Saved: pretrends_test_results.csv\n")
}

# Save full results object
saveRDS(result, "output/csdid_pretrends/cs_result.rds")
cat("   Saved: cs_result.rds\n\n")

# ========================================================================
# Summary
# ========================================================================

cat("================================================================================\n")
cat("COMPLETE!\n")
cat("================================================================================\n\n")

cat("Output directory: output/csdid_pretrends/\n\n")

cat("Figures created:\n")
cat("  1. event_study.pdf - Main event study plot with pre-trends highlighted\n")
cat("  2. pretrends_test.pdf - Joint hypothesis test for parallel trends\n")
cat("  3. group_dynamics.pdf - Group-specific treatment effects\n")
cat("  4. calendar_time.pdf - Calendar time effects\n")
cat("  5. support_heatmap.pdf - Support diagnostics heatmap\n")
cat("  6. comprehensive_report.pdf - All plots in one PDF\n\n")

cat("Tables created:\n")
cat("  • att_gt_estimates.csv - All ATT(g,t) estimates\n")
cat("  • dynamic_effects.csv - Event study coefficients\n")
cat("  • pretrends_test_results.csv - Pre-trends test statistics\n")
cat("  • pretrends_analysis_support_table.csv - Support diagnostics\n\n")

cat("Open plots:\n")
cat("  open output/csdid_pretrends/figures/event_study.pdf\n")
cat("  open output/csdid_pretrends/figures/pretrends_test.pdf\n")
cat("  open output/csdid_pretrends/figures/comprehensive_report.pdf\n\n")

cat("View results in R:\n")
cat("  result <- readRDS('output/csdid_pretrends/cs_result.rds')\n")
cat("  summary(result)\n\n")

cat("================================================================================\n\n")
