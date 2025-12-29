# Test CS estimator directly with the prepared data
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(did)
})

set.seed(789)

cfg <- list(
  data_dir = ".",
  panel_choice = "counties",
  outcome_preference = c("filings_count_per_1k_renters"),
  weights_var = "renter_occupied_housing_units",
  treat_date_col = "online_start_date",
  pre_len = 12,
  post_len = 12,
  effect_shape = "step",
  delay_h = 6,
  did_bstrap = FALSE,
  did_biters = 1000,
  did_cband = TRUE,
  cluster_level = "state",
  estimand = "overall_att",
  alpha = 0.05
)

source("power_simulation_cs.R", echo = FALSE, verbose = FALSE)

panel_df <- load_panel(cfg)
treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)
baseline <- build_untreated_sample(panel_df, treat_schedule_std)
placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline)
df_sim <- impose_effect(baseline, placebo, effect_size = 3.0, cfg)

# Do time remapping
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
  ) %>%
  as.data.frame()

cat("=== CALLING CS ESTIMATOR ===\n")
cat("Data dimensions:", nrow(df_in), "rows x", ncol(df_in), "cols\n")
cat("Unique gname values:", paste(sort(unique(df_in$gname)), collapse = ", "), "\n")
cat("Range of time_id_seq:", min(df_in$time_id_seq), "to", max(df_in$time_id_seq), "\n\n")

# Call CS estimator with full verbosity
att <- did::att_gt(
  yname = "outcome_sim",
  tname = "time_id_seq",
  idname = "unit_id",
  gname = "gname",
  data = df_in,
  panel = TRUE,
  control_group = "notyettreated",
  bstrap = FALSE,
  clustervars = "state_abb",
  est_method = "ipw",
  weightsname = "renter_occupied_housing_units",
  allow_unbalanced_panel = TRUE
)

cat("\n=== CS ESTIMATOR RESULT ===\n")
cat("Class:", class(att), "\n")
print(summary(att))

cat("\n=== AGGREGATING TO OVERALL ATT ===\n")
agg <- did::aggte(att, type = "simple")
cat("Overall ATT:", agg$overall.att, "\n")
cat("Overall SE:", agg$overall.se, "\n")

if (is.finite(agg$overall.att) && is.finite(agg$overall.se) && agg$overall.se > 0) {
  p <- 2 * pnorm(-abs(agg$overall.att / agg$overall.se))
  cat("P-value:", p, "\n")
  cat("Reject at 0.05?", p < 0.05, "\n")
} else {
  cat("❌ Non-finite values - cannot compute p-value\n")
}
