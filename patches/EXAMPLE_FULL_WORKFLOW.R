#!/usr/bin/env Rscript
################################################################################
# EXAMPLE_FULL_WORKFLOW.R
#
# Complete example workflow for publishable CS-DiD estimation with:
# 1. Preflight support check
# 2. Safe CS-DiD estimation
# 3. Pre-trends testing and visualization
# 4. Cross-validation with alternative estimators
# 5. Publication-ready tables and figures
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(did)
  library(ggplot2)
})

cat("\n")
cat("========================================================================\n")
cat("EXAMPLE: Complete CS-DiD Workflow with Safety Checks\n")
cat("========================================================================\n\n")

# ========================================================================
# STEP 0: Load patches
# ========================================================================

cat("Step 0: Loading patch files...\n")
source("patches/preflight_support_check.R")
source("patches/att_gt_safe.R")
source("patches/plot_csdid_pretrends.R")
cat("✓ Patches loaded\n\n")

# ========================================================================
# STEP 1: Load and prepare your data
# ========================================================================

cat("Step 1: Loading data...\n")

# OPTION A: Load your actual gambling-eviction data
# Uncomment and adjust paths as needed:
# panel_data <- readr::read_csv("data/processed/gambling_eviction_panel.csv")

# OPTION B: For this example, create synthetic data
set.seed(123)
panel_data <- expand.grid(
  state_id = 1:30,
  year_month = 1:60
) %>%
  mutate(
    # Treatment: 10 states treated at different times
    first_treat = case_when(
      state_id <= 10 ~ 20 + (state_id %% 5) * 5,  # Treatment at t=20,25,30,35,40
      TRUE ~ 0  # Never treated
    ),
    # Outcome with treatment effect
    log_evictions = rnorm(n(), mean = 5, sd = 1) +
      0.02 * year_month +  # Time trend
      ifelse(state_id <= 10, 0.3, 0) +  # Level shift for treated
      ifelse(year_month >= first_treat & first_treat > 0, 0.5, 0)  # Treatment effect
  ) %>%
  # Create some unbalancedness (optional)
  filter(!(state_id <= 5 & year_month > 55))

cat(sprintf("  Data loaded: %d observations, %d states, %d periods\n",
            nrow(panel_data),
            n_distinct(panel_data$state_id),
            n_distinct(panel_data$year_month)))
cat("\n")

# ========================================================================
# STEP 2: Run preflight support check
# ========================================================================

cat("Step 2: Running preflight support check...\n")
cat("------------------------------------------------------------------------\n\n")

support_check <- preflight_support_check(
  data = panel_data,
  idname = "state_id",
  tname = "year_month",
  gname = "first_treat",
  yname = "log_evictions",
  control_group = "nevertreated",
  verbose = TRUE
)

# Save support diagnostics
save_preflight_check(
  support_check,
  output_dir = "output/example_csdid",
  prefix = "example"
)

cat("\n")

# ========================================================================
# STEP 3: Estimate CS-DiD with safety wrapper
# ========================================================================

cat("Step 3: Estimating CS-DiD with att_gt_safe()...\n")
cat("------------------------------------------------------------------------\n\n")

cs_result <- att_gt_safe(
  yname = "log_evictions",
  tname = "year_month",
  idname = "state_id",
  gname = "first_treat",
  data = panel_data,
  control_group = "nevertreated",
  est_method = "dr",  # Doubly robust
  base_period = "universal",
  anticipation = 0,
  clustervars = "state_id",
  panel = FALSE,  # Use repeated cross-sections for unbalanced
  bstrap = FALSE,  # Set TRUE for bootstrap inference (slower)
  fail_on_support_issues = FALSE,
  save_support_check = TRUE,
  support_check_dir = "output/example_csdid"
)

cat("\n")

# ========================================================================
# STEP 4: Aggregate and report results
# ========================================================================

cat("Step 4: Aggregating treatment effects...\n")
cat("------------------------------------------------------------------------\n\n")

# Simple ATT
cat("4a. Overall Average Treatment Effect:\n")
agg_simple <- aggte_safe(cs_result, type = "simple")
cat(sprintf("    ATT = %.4f (SE = %.4f)\n", agg_simple$overall.att, agg_simple$overall.se))
cat(sprintf("    95%% CI: [%.4f, %.4f]\n",
            agg_simple$overall.att - 1.96 * agg_simple$overall.se,
            agg_simple$overall.att + 1.96 * agg_simple$overall.se))
cat(sprintf("    NA cells excluded: %d\n\n", agg_simple$n_na_excluded))

# Dynamic (event study)
cat("4b. Dynamic treatment effects (event study):\n")
agg_dynamic <- aggte_safe(cs_result, type = "dynamic")
cat(sprintf("    Computed for %d event times\n", length(agg_dynamic$egt)))
cat(sprintf("    Range: [%d, %d]\n", min(agg_dynamic$egt), max(agg_dynamic$egt)))
cat("\n")

# Group-specific
cat("4c. Group-specific effects:\n")
agg_group <- aggte_safe(cs_result, type = "group")
cat(sprintf("    Computed for %d treatment groups\n", length(agg_group$egt)))
cat("\n")

# ========================================================================
# STEP 5: Test pre-trends
# ========================================================================

cat("Step 5: Testing parallel trends assumption...\n")
cat("------------------------------------------------------------------------\n\n")

pretrends_result <- plot_pretrends_test(cs_result, alpha = 0.05)

cat("Pre-trends test results:\n")
cat(sprintf("  Joint χ²(%d) = %.2f\n",
            pretrends_result$test_results$joint_df,
            pretrends_result$test_results$joint_chisq))
cat(sprintf("  p-value = %.4f\n", pretrends_result$test_results$joint_p))

if (pretrends_result$test_results$passes_pretrends) {
  cat("  ✓ Parallel trends assumption SUPPORTED\n")
} else {
  cat("  ✗ Parallel trends assumption VIOLATED\n")
  cat("  → Consider: specification changes, HonestDiD sensitivity analysis\n")
}
cat("\n")

# ========================================================================
# STEP 6: Create publication-ready plots
# ========================================================================

cat("Step 6: Creating plots...\n")
cat("------------------------------------------------------------------------\n\n")

# Ensure output directory exists
dir.create("output/example_csdid/figures", showWarnings = FALSE, recursive = TRUE)

# Main event study
cat("  6a. Event study plot...\n")
p_event <- plot_event_study(
  cs_result,
  title = "Event Study: Treatment Effect Over Time"
)
ggsave("output/example_csdid/figures/event_study.pdf", p_event,
       width = 10, height = 6)

# Pre-trends test plot
cat("  6b. Pre-trends test plot...\n")
ggsave("output/example_csdid/figures/pretrends_test.pdf",
       pretrends_result$plot,
       width = 10, height = 6)

# Group dynamics
cat("  6c. Group-specific dynamics...\n")
p_groups <- plot_group_dynamics(cs_result)
ggsave("output/example_csdid/figures/group_dynamics.pdf", p_groups,
       width = 10, height = 8)

# Support heatmap
if (!is.null(cs_result$support_diagnostics)) {
  cat("  6d. Support heatmap...\n")
  p_support <- plot_support_heatmap(cs_result)
  ggsave("output/example_csdid/figures/support_heatmap.pdf", p_support,
         width = 10, height = 6)
}

# Comprehensive report
cat("  6e. Full diagnostic report...\n")
report <- create_pretrends_report(
  cs_result,
  output_file = "output/example_csdid/figures/pretrends_report.pdf"
)

cat("  ✓ All plots saved to output/example_csdid/figures/\n\n")

# ========================================================================
# STEP 7: Export results for paper
# ========================================================================

cat("Step 7: Exporting results...\n")
cat("------------------------------------------------------------------------\n\n")

# Export ATT(g,t) table
att_gt_table <- data.frame(
  group = cs_result$group,
  time = cs_result$t,
  event_time = cs_result$t - cs_result$group,
  att = cs_result$att,
  se = cs_result$se,
  ci_lower = cs_result$att - 1.96 * cs_result$se,
  ci_upper = cs_result$att + 1.96 * cs_result$se
) %>%
  arrange(group, time)

write.csv(att_gt_table, "output/example_csdid/att_gt_estimates.csv", row.names = FALSE)
cat("  ✓ ATT(g,t) estimates saved to att_gt_estimates.csv\n")

# Export aggregate effects
aggregate_table <- data.frame(
  aggregation = c("Overall", rep("Dynamic", length(agg_dynamic$egt)), rep("Group", length(agg_group$egt))),
  period = c(NA, agg_dynamic$egt, agg_group$egt),
  att = c(agg_simple$overall.att, agg_dynamic$att.egt, agg_group$att.egt),
  se = c(agg_simple$overall.se, agg_dynamic$se.egt, agg_group$se.egt)
) %>%
  mutate(
    ci_lower = att - 1.96 * se,
    ci_upper = att + 1.96 * se
  )

write.csv(aggregate_table, "output/example_csdid/aggregate_effects.csv", row.names = FALSE)
cat("  ✓ Aggregate effects saved to aggregate_effects.csv\n")

# Export pre-trends test results
pretrends_table <- pretrends_result$test_results$individual_tests
write.csv(pretrends_table, "output/example_csdid/pretrends_test.csv", row.names = FALSE)
cat("  ✓ Pre-trends test results saved to pretrends_test.csv\n\n")

# ========================================================================
# STEP 8: (Optional) Cross-validate with alternative estimators
# ========================================================================

cat("Step 8: Cross-validation with alternative estimators...\n")
cat("------------------------------------------------------------------------\n\n")

# Sun-Abraham (via fixest)
if (requireNamespace("fixest", quietly = TRUE)) {
  cat("  8a. Sun-Abraham estimator (fixest::sunab)...\n")

  # Need to create a cohort variable (never-treated = 10000)
  panel_data_sa <- panel_data %>%
    mutate(cohort = ifelse(first_treat == 0, 10000, first_treat))

  sa_result <- fixest::feols(
    log_evictions ~ fixest::sunab(cohort, year_month) | state_id + year_month,
    data = panel_data_sa,
    cluster = "state_id"
  )

  sa_att <- mean(coef(sa_result)[grepl("^cohort::", names(coef(sa_result)))], na.rm = TRUE)

  cat(sprintf("      Sun-Abraham ATT ≈ %.4f\n", sa_att))
  cat(sprintf("      CS-DiD ATT      = %.4f\n", agg_simple$overall.att))
  cat(sprintf("      Difference      = %.4f\n\n", abs(sa_att - agg_simple$overall.att)))
} else {
  cat("  Skipping Sun-Abraham (fixest not installed)\n\n")
}

# didimputation (Borusyak et al.)
if (requireNamespace("didimputation", quietly = TRUE)) {
  cat("  8b. Imputation estimator (didimputation)...\n")

  di_result <- didimputation::did_imputation(
    data = panel_data,
    yname = "log_evictions",
    gname = "first_treat",
    tname = "year_month",
    idname = "state_id",
    first_stage = ~ 0 | state_id + year_month,
    cluster_var = "state_id"
  )

  di_att <- mean(di_result$estimate, na.rm = TRUE)

  cat(sprintf("      didimputation ATT ≈ %.4f\n", di_att))
  cat(sprintf("      CS-DiD ATT        = %.4f\n", agg_simple$overall.att))
  cat(sprintf("      Difference        = %.4f\n\n", abs(di_att - agg_simple$overall.att)))
} else {
  cat("  Skipping didimputation (package not installed)\n\n")
}

# ========================================================================
# SUMMARY
# ========================================================================

cat("\n")
cat("========================================================================\n")
cat("WORKFLOW COMPLETE\n")
cat("========================================================================\n\n")

cat("Results summary:\n")
cat(sprintf("  Overall ATT: %.4f (SE: %.4f)\n", agg_simple$overall.att, agg_simple$overall.se))
cat(sprintf("  Pre-trends test: p = %.4f (%s)\n",
            pretrends_result$test_results$joint_p,
            ifelse(pretrends_result$test_results$passes_pretrends, "PASS", "FAIL")))
cat(sprintf("  NA cells excluded: %d\n", agg_simple$n_na_excluded))
cat("\n")

cat("Output files:\n")
cat("  Tables:\n")
cat("    - output/example_csdid/att_gt_estimates.csv\n")
cat("    - output/example_csdid/aggregate_effects.csv\n")
cat("    - output/example_csdid/pretrends_test.csv\n")
cat("    - output/example_csdid/example_support_table.csv\n")
cat("  Figures:\n")
cat("    - output/example_csdid/figures/event_study.pdf\n")
cat("    - output/example_csdid/figures/pretrends_test.pdf\n")
cat("    - output/example_csdid/figures/group_dynamics.pdf\n")
cat("    - output/example_csdid/figures/support_heatmap.pdf\n")
cat("    - output/example_csdid/figures/pretrends_report.pdf\n")
cat("\n")

cat("Next steps:\n")
cat("  1. Review support diagnostics in output/example_csdid/example_support_table.csv\n")
cat("  2. Check pre-trends test results and plots\n")
cat("  3. Use tables and figures for paper\n")
cat("  4. Report support issues transparently in appendix\n")
cat("\n")

cat("========================================================================\n\n")
