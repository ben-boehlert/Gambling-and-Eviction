# Debug att_gt_safe to see what it returns
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(did)
})

set.seed(789)

cfg <- list(
  data_dir = ".",
  panel_choice = "states_from_counties",
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
placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline)
df_sim <- impose_effect(baseline, placebo, effect_size = 3.0, cfg)

# Do remapping
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
att <- att_gt_safe(df_in, cfg, cluster_var)

cat("\natt_gt_safe returned:\n")
cat("  Class:", class(att), "\n")

if (inherits(att, "AGGTEobj")) {
  cat("  ✓ Got AGGTEobj directly\n")
  cat("  overall.att:", att$overall.att, "\n")
  cat("  overall.se:", att$overall.se, "\n")
} else if (inherits(att, "MP")) {
  cat("  ✓ Got MP object (att_gt result)\n")
  cat("  Need to aggregate...\n")
  agg <- did::aggte(att, type = "simple")
  cat("  overall.att:", agg$overall.att, "\n")
  cat("  overall.se:", agg$overall.se, "\n")

  if (is.finite(agg$overall.att) && is.finite(agg$overall.se) && agg$overall.se > 0) {
    p <- 2 * pnorm(-abs(agg$overall.att / agg$overall.se))
    cat("  p-value:", p, "\n")
  } else {
    cat("  ❌ Non-finite values\n")
  }
} else {
  cat("  ❌ Unexpected class\n")
}
