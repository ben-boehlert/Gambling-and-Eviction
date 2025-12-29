# Debug: Check if remapping is working
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
  did_biters = 50,
  did_cband = FALSE,
  cluster_level = "state",
  estimand = "overall_att",
  target_h = 12,
  alpha = 0.05
)

source("power_simulation_cs.R", echo = FALSE, verbose = FALSE)

panel_df <- load_panel(cfg)
cluster_var <- "state_abb"
treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)
baseline <- build_untreated_sample(panel_df, treat_schedule_std)
placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline)
df_sim <- impose_effect(baseline, placebo, effect_size = 1.0, cfg)

cat("=== BEFORE REMAPPING ===\n")
cat("time_id range:", min(df_sim$time_id), "to", max(df_sim$time_id), "\n")
cat("g_placebo range:", min(df_sim$g_placebo[df_sim$g_placebo > 0], na.rm=TRUE),
    "to", max(df_sim$g_placebo, na.rm=TRUE), "\n\n")

# Manually execute the remapping code from run_estimator_and_extract_p
time_mapping <- df_sim %>%
  distinct(time_id) %>%
  arrange(time_id) %>%
  mutate(time_id_seq = row_number())

cat("Time mapping created:\n")
print(head(time_mapping, 10))
cat("...\n")
print(tail(time_mapping, 10))

g_mapping <- df_sim %>%
  filter(!is.na(g_placebo) & g_placebo > 0L) %>%
  distinct(g_placebo) %>%
  left_join(time_mapping, by = c("g_placebo" = "time_id")) %>%
  select(g_placebo, g_placebo_seq = time_id_seq)

cat("\nG mapping created:\n")
print(head(g_mapping, 10))

df_in <- df_sim %>%
  left_join(time_mapping, by = "time_id") %>%
  left_join(g_mapping, by = "g_placebo") %>%
  mutate(
    gname = if_else(is.na(g_placebo) | g_placebo == 0L, 0L, coalesce(g_placebo_seq, 0L))
  )

cat("\n=== AFTER REMAPPING ===\n")
cat("time_id_seq range:", min(df_in$time_id_seq), "to", max(df_in$time_id_seq), "\n")
cat("gname range:", min(df_in$gname[df_in$gname > 0]), "to", max(df_in$gname), "\n")
cat("gname class:", class(df_in$gname), "\n")
cat("time_id_seq class:", class(df_in$time_id_seq), "\n\n")

cat("Sample of df_in for verification:\n")
print(df_in %>%
  select(unit_id, time_id, time_id_seq, g_placebo, g_placebo_seq, gname, state_abb) %>%
  filter(gname > 0) %>%
  head(10))
