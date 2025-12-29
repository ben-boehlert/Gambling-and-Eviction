# Debug script to see what's happening with att_gt
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(did)
  library(fixest)
})

set.seed(20251224)

# Source the main script to get functions
source("power_simulation_cs.R")

# Build one simulated dataset
cat("Loading panel...\n")
panel_df <- load_panel(cfg)

cat("Building treatment schedule...\n")
treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)

cluster_var <- "unit_id"

cat("Building untreated baseline...\n")
baseline <- build_untreated_sample(panel_df, treat_schedule_std)

cat("Drawing placebo schedule...\n")
placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline)

cat("Imposing effect (size=0.5)...\n")
df_sim <- impose_effect(baseline, placebo, effect_size = 0.5, cfg)

cat("\nDataset summary:\n")
cat("  Rows:", nrow(df_sim), "\n")
cat("  Units:", n_distinct(df_sim$unit_id), "\n")
cat("  Time periods:", n_distinct(df_sim$time_id), "\n")
cat("  Treated units (g_placebo>0):", n_distinct(df_sim$unit_id[df_sim$g_placebo > 0]), "\n")
cat("  Never-treated units:", n_distinct(df_sim$unit_id[df_sim$g_placebo == 0]), "\n")
cat("  Treated obs:", sum(df_sim$g_placebo > 0), "\n")

cat("\nPreparing for att_gt...\n")
df_in <- df_sim %>%
  mutate(gname = as.integer(if_else(is.na(g_placebo), 0L, g_placebo)))

cat("  Unique gname values:", paste(sort(unique(df_in$gname)), collapse=", "), "\n")
cat("  gname distribution:\n")
print(table(df_in$gname))

cat("\nRunning att_gt (this may take a while with bootstrapping)...\n")
att_result <- tryCatch({
  att_gt_safe(df_in, cfg, cluster_var = cluster_var)
}, error = function(e) {
  cat("ERROR in att_gt:", conditionMessage(e), "\n")
  return(NULL)
})

if (!is.null(att_result)) {
  cat("\natt_gt succeeded! Attempting aggte...\n")

  agg_result <- tryCatch({
    did::aggte(att_result, type = "simple")
  }, error = function(e) {
    cat("ERROR in aggte:", conditionMessage(e), "\n")
    return(NULL)
  })

  if (!is.null(agg_result)) {
    cat("\naggte results:\n")
    cat("  overall.att:", agg_result$overall.att, "\n")
    cat("  overall.se:", agg_result$overall.se, "\n")
    cat("  is.finite(overall.att):", is.finite(agg_result$overall.att), "\n")
    cat("  is.finite(overall.se):", is.finite(agg_result$overall.se), "\n")

    if (is.finite(agg_result$overall.att) && is.finite(agg_result$overall.se) && agg_result$overall.se > 0) {
      p <- 2 * pnorm(-abs(agg_result$overall.att / agg_result$overall.se))
      cat("  p-value:", p, "\n")
    } else {
      cat("  p-value: NA (non-finite est or se)\n")
    }
  }
} else {
  cat("\natt_gt failed - cannot proceed to aggte\n")
}
