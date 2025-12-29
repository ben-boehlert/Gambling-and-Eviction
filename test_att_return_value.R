# Check what att_gt actually returns
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(did)
})

set.seed(111)

cfg <- list(
  data_dir = ".",
  panel_choice = "states_from_counties",
  outcome_preference = c("filings_count_per_1k_renters"),
  weights_var = "renter_occupied_housing_units",
  treat_date_col = "online_start_date",
  pre_len = 12, post_len = 12, effect_shape = "step", delay_h = 6,
  did_bstrap = FALSE, cluster_level = "state",
  estimand = "overall_att", alpha = 0.05
)

source("power_simulation_cs.R", echo = FALSE, verbose = FALSE)

panel_df <- load_panel(cfg)
cluster_var <- "state_abb"
treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)
baseline <- build_untreated_sample(panel_df, treat_schedule_std)
placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline)
df_sim <- impose_effect(baseline, placebo, effect_size = 2.0, cfg)

cat("Running run_estimator_and_extract_p with detailed output...\n\n")

# Manually run the function with instrumentation
time_mapping <- df_sim %>%
  distinct(time_id) %>%
  arrange(time_id) %>%
  mutate(time_id_seq = row_number())

g_mapping <- df_sim %>%
  filter(!is.na(g_placebo) & g_placebo > 0L) %>%
  distinct(g_placebo) %>%
  left_join(time_mapping, by = c("g_placebo" = "time_id")) %>%
  select(g_placebo, g_placebo_seq = time_id_seq)

df_in <- df_sim %>%
  left_join(time_mapping, by = "time_id") %>%
  left_join(g_mapping, by = "g_placebo") %>%
  mutate(
    gname = if_else(is.na(g_placebo) | g_placebo == 0L, 0L, coalesce(g_placebo_seq, 0L))
  )

cat("Calling att_gt_safe...\n")
att <- NULL
att <- tryCatch({
  att_gt_safe(df_in, cfg, cluster_var)
}, error = function(e) {
  cat("ERROR in att_gt_safe:", conditionMessage(e), "\n")
  NULL
})

cat("\n")
if (is.null(att)) {
  cat("❌ att_gt_safe returned NULL\n")
} else {
  cat("✓ att_gt_safe returned object\n")
  cat("  Class:", paste(class(att), collapse = ", "), "\n")
  cat("  Names:", paste(names(att)[1:min(10, length(names(att)))], collapse = ", "), "...\n\n")

  cat("Attempting aggte...\n")
  agg <- tryCatch({
    did::aggte(att, type = "simple")
  }, error = function(e) {
    cat("ERROR in aggte:", conditionMessage(e), "\n")
    NULL
  })

  if (!is.null(agg)) {
    cat("  ✓ aggte succeeded\n")
    cat("  overall.att:", agg$overall.att, "(class:", class(agg$overall.att), ")\n")
    cat("  overall.se:", agg$overall.se, "(class:", class(agg$overall.se), ")\n")
    cat("  is.finite(overall.att):", is.finite(agg$overall.att), "\n")
    cat("  is.finite(overall.se):", is.finite(agg$overall.se), "\n")

    if (is.finite(agg$overall.att) && is.finite(agg$overall.se) && agg$overall.se > 0) {
      p <- 2 * pnorm(-abs(agg$overall.att / agg$overall.se))
      cat("  ✓ Computed p-value:", p, "\n")
    }
  }
}
