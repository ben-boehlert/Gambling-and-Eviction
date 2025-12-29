# Diagnose why only 2 cohorts appear when 7 are created
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
  cluster_level = "state",
  estimand = "overall_att",
  alpha = 0.05
)

source("power_simulation_cs.R", echo = FALSE, verbose = FALSE)

panel_df <- load_panel(cfg)
cluster_var <- "state_abb"
treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)
baseline <- build_untreated_sample(panel_df, treat_schedule_std)

cat("=== BASELINE SAMPLE ===\n")
cat("Total rows:", nrow(baseline), "\n")
cat("Unique counties:", n_distinct(baseline$unit_id), "\n")
cat("Unique states:", n_distinct(baseline$state_abb), "\n\n")

placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline)

cat("=== PLACEBO SCHEDULE ===\n")
cat("Total units:", nrow(placebo), "\n")
cat("Units with treatment (g_placebo > 0):", sum(placebo$g_placebo > 0), "\n")
cat("Unique placebo dates:\n")
print(placebo %>%
  filter(g_placebo > 0) %>%
  count(g_placebo) %>%
  arrange(g_placebo))

cat("\n=== PLACEBO BY STATE ===\n")
placebo_with_state <- baseline %>%
  distinct(unit_id, state_abb) %>%
  left_join(placebo, by = "unit_id")

print(placebo_with_state %>%
  filter(g_placebo > 0) %>%
  group_by(state_abb, g_placebo) %>%
  summarise(n_counties = n(), .groups = "drop") %>%
  arrange(g_placebo, state_abb))

# Now impose effect and check what happens
df_sim <- impose_effect(baseline, placebo, effect_size = 3.0, cfg)

cat("\n=== AFTER IMPOSE_EFFECT ===\n")
cat("Total rows:", nrow(df_sim), "\n")
cat("Units with g_placebo > 0:", sum(df_sim$g_placebo > 0, na.rm = TRUE), "\n")
cat("Unique g_placebo values:\n")
print(df_sim %>%
  filter(!is.na(g_placebo) & g_placebo > 0) %>%
  count(g_placebo) %>%
  arrange(g_placebo))

# Do time remapping (this is what run_estimator_and_extract_p does)
time_mapping <- df_sim %>%
  distinct(time_id) %>%
  arrange(time_id) %>%
  mutate(time_id_seq = row_number())

cat("\n=== TIME MAPPING ===\n")
cat("Number of unique time_id values:", nrow(time_mapping), "\n")
cat("Range of time_id:", min(time_mapping$time_id), "to", max(time_mapping$time_id), "\n")
cat("Range of time_id_seq:", min(time_mapping$time_id_seq), "to", max(time_mapping$time_id_seq), "\n")

# Remap g_placebo values
g_mapping <- df_sim %>%
  filter(!is.na(g_placebo) & g_placebo > 0L) %>%
  distinct(g_placebo) %>%
  left_join(time_mapping, by = c("g_placebo" = "time_id")) %>%
  select(g_placebo, g_placebo_seq = time_id_seq)

cat("\n=== G_PLACEBO MAPPING ===\n")
print(g_mapping %>% arrange(g_placebo))

df_in <- df_sim %>%
  left_join(time_mapping, by = "time_id") %>%
  left_join(g_mapping, by = "g_placebo") %>%
  mutate(
    gname = if_else(is.na(g_placebo) | g_placebo == 0L, 0L, coalesce(g_placebo_seq, 0L))
  )

cat("\n=== FINAL DF_IN (gname) ===\n")
cat("Rows with gname > 0:", sum(df_in$gname > 0), "\n")
cat("Unique gname values (excluding 0):\n")
print(df_in %>%
  filter(gname > 0) %>%
  count(gname) %>%
  arrange(gname))

cat("\n=== COHORTS BY STATE ===\n")
print(df_in %>%
  filter(gname > 0) %>%
  group_by(gname, state_abb) %>%
  summarise(
    n_counties = n_distinct(unit_id),
    n_obs = n(),
    .groups = "drop"
  ) %>%
  arrange(gname, state_abb))

cat("\n=== SUMMARY OF GNAME VALUES ===\n")
gname_summary <- df_in %>%
  group_by(gname) %>%
  summarise(
    n_obs = n(),
    n_counties = n_distinct(unit_id),
    n_states = n_distinct(state_abb),
    .groups = "drop"
  ) %>%
  arrange(gname)
print(gname_summary)

cat("\n=== CHECK: Are all treated counties in baseline? ===\n")
treated_counties <- placebo %>% filter(g_placebo > 0) %>% pull(unit_id)
baseline_counties <- unique(baseline$unit_id)
counties_not_in_baseline <- setdiff(treated_counties, baseline_counties)
if (length(counties_not_in_baseline) > 0) {
  cat("WARNING: Some treated counties are NOT in baseline:\n")
  print(counties_not_in_baseline)
} else {
  cat("OK: All treated counties are in baseline\n")
}

cat("\n=== CHECK: Time range for treated counties ===\n")
treated_time_ranges <- df_in %>%
  filter(unit_id %in% treated_counties) %>%
  group_by(unit_id, gname) %>%
  summarise(
    min_time = min(time_id_seq),
    max_time = max(time_id_seq),
    g_first = first(g_placebo),
    .groups = "drop"
  )
print(treated_time_ranges)
