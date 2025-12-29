# Test to see what's in the att object
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

cat("=== Calling CS estimator (suppressing output) ===\n")
att <- suppressWarnings(
  did::att_gt(
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
)

cat("\n=== ATT Object Structure ===\n")
cat("Class:", class(att), "\n")
cat("Group values in att$group:", paste(sort(unique(att$group)), collapse = ", "), "\n")
cat("Time values in att$t:", paste(range(att$t), collapse = " to "), "\n")
cat("Number of group-time estimates:", length(att$att), "\n\n")

cat("=== Group-Time Combinations ===\n")
gt_combos <- tibble(
  group = att$group,
  time = att$t,
  att_est = att$att,
  se = att$se
) %>%
  arrange(group, time)

print(gt_combos %>%
  group_by(group) %>%
  summarise(
    n_periods = n(),
    min_time = min(time),
    max_time = max(time),
    .groups = "drop"
  ))

cat("\n=== Trying aggte with type='simple' ===\n")
result <- tryCatch({
  agg <- did::aggte(att, type = "simple")
  list(
    success = TRUE,
    overall_att = agg$overall.att,
    overall_se = agg$overall.se
  )
}, error = function(e) {
  list(
    success = FALSE,
    error = as.character(e)
  )
})

if (result$success) {
  cat("✓ Success!\n")
  cat("  Overall ATT:", result$overall_att, "\n")
  cat("  Overall SE:", result$overall_se, "\n")
} else {
  cat("❌ Error:", result$error, "\n")
}
