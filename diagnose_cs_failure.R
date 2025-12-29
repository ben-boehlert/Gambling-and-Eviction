# Diagnostic script to understand why CS estimator is returning NA p-values
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(did)
  library(fixest)
  library(glue)
})

set.seed(20251224)

# Source the main functions
source("power_simulation_cs.R", echo = FALSE, verbose = FALSE)

cat("=== DIAGNOSTIC: CS Estimator Failure ===\n\n")

# Load panel
cat("1. Loading panel...\n")
panel_df <- load_panel(cfg)
cat("   ✓ Loaded:", n_distinct(panel_df$unit_id), "units,", n_distinct(panel_df$time_id), "months\n\n")

# Get treatment schedule
cat("2. Creating treatment schedule...\n")
cluster_var <- case_when(
  cfg$cluster_level == "unit" ~ "unit_id",
  cfg$cluster_level == "state" ~ if ("state_abb" %in% names(panel_df)) "state_abb" else "unit_id",
  TRUE ~ "unit_id"
)
cat("   Cluster variable:", cluster_var, "\n")

treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)
cat("   ✓ Treated units:", sum(treat_schedule_std$ever_treated & treat_schedule_std$g_id > 0), "\n\n")

# Build baseline (A1)
cat("3. Building untreated baseline (A1)...\n")
baseline <- build_untreated_sample(panel_df, treat_schedule_std)
cat("   ✓ Baseline has:", nrow(baseline), "observations\n")
cat("   ✓ Units:", n_distinct(baseline$unit_id), "\n")
cat("   ✓ Clusters:", n_distinct(baseline[[cluster_var]]), "\n\n")

# Draw ONE placebo schedule
cat("4. Drawing placebo schedule...\n")
placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline)
cat("   ✓ Placebo treated units:", sum(placebo$g_placebo > 0), "\n")
cat("   ✓ Never-treated units:", sum(placebo$g_placebo == 0), "\n\n")

# Impose effect
cat("5. Imposing effect (size = 1.0)...\n")
df_sim <- impose_effect(baseline, placebo, effect_size = 1.0, cfg)
cat("   ✓ Simulation data has:", nrow(df_sim), "observations\n\n")

# Check gname distribution
cat("6. Checking gname (treatment cohort) distribution...\n")
df_in <- df_sim %>%
  mutate(gname = as.integer(if_else(is.na(g_placebo), 0L, g_placebo)))

gname_summary <- df_in %>%
  group_by(gname) %>%
  summarise(
    n_obs = n(),
    n_units = n_distinct(unit_id),
    .groups = "drop"
  ) %>%
  arrange(gname)

print(gname_summary)

if (all(df_in$gname == 0L)) {
  cat("\n❌ ERROR: All gname = 0 (no treated units)!\n")
  stop("Cannot run CS estimator with no treated units")
}

cat("\n7. Attempting CS estimator (att_gt)...\n")

# Try to run CS estimator with error capture
result <- tryCatch({
  args <- list(
    yname = "outcome_sim",
    tname = "time_id",
    idname = "unit_id",
    gname = "gname",
    data = df_in,
    panel = TRUE,
    control_group = "notyettreated",
    bstrap = cfg$did_bstrap,
    biters = cfg$did_biters,
    cband = cfg$did_cband,
    clustervars = cluster_var
  )

  if (!is.null(cfg$weights_var) && cfg$weights_var %in% names(df_in)) {
    args$weightsname <- cfg$weights_var
  }

  if ("allow_unbalanced_panel" %in% names(formals(did::att_gt))) {
    args$allow_unbalanced_panel <- TRUE
  }

  cat("   Running with:\n")
  cat("     - control_group:", args$control_group, "\n")
  cat("     - bstrap:", args$bstrap, "( biters:", args$biters, ")\n")
  cat("     - clustervars:", args$clustervars, "\n")
  cat("     - weightsname:", args$weightsname %||% "NULL", "\n\n")

  att <- do.call(did::att_gt, args)

  cat("   ✓ att_gt succeeded\n\n")

  # Aggregate
  cat("8. Aggregating to overall ATT...\n")
  agg <- did::aggte(att, type = "simple")

  cat("   ✓ aggte succeeded\n")
  cat("   Overall ATT:", agg$overall.att, "\n")
  cat("   Overall SE:", agg$overall.se, "\n")

  # Compute p-value
  est <- agg$overall.att
  se <- agg$overall.se

  cat("\n9. Computing p-value...\n")
  cat("   est is finite?", is.finite(est), "\n")
  cat("   se is finite?", is.finite(se), "\n")
  cat("   se > 0?", se > 0, "\n")

  if (is.finite(est) && is.finite(se) && se > 0) {
    p <- 2 * pnorm(-abs(est / se))
    cat("   ✓ p-value:", p, "\n")
  } else {
    cat("   ❌ Cannot compute p-value (est or se is non-finite or se <= 0)\n")
    p <- NA_real_
  }

  list(success = TRUE, p = p, est = est, se = se)

}, error = function(e) {
  cat("   ❌ ERROR in CS estimator:\n")
  cat("   ", conditionMessage(e), "\n")
  list(success = FALSE, error = conditionMessage(e))
})

cat("\n=== SUMMARY ===\n")
if (result$success) {
  cat("CS estimator ran successfully\n")
  cat("Result: p =", result$p, ", est =", result$est, ", se =", result$se, "\n")

  if (is.na(result$p)) {
    cat("\n⚠️  P-value is NA despite successful estimation\n")
    cat("This suggests est or se is non-finite\n")
  }
} else {
  cat("CS estimator FAILED\n")
  cat("Error:", result$error, "\n")
}
