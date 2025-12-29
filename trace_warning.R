# Trace exactly where the Inf warning comes from
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(did)
})

set.seed(999)

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
df_sim <- impose_effect(baseline, placebo, effect_size = 0.5, cfg)

# Do the remapping
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

cat("Data prepared for att_gt:\n")
cat("  Rows:", nrow(df_in), "\n")
cat("  gname class:", class(df_in$gname), "\n")
cat("  gname range:", min(df_in$gname), "to", max(df_in$gname), "\n")
cat("  time_id_seq class:", class(df_in$time_id_seq), "\n")
cat("  time_id_seq range:", min(df_in$time_id_seq), "to", max(df_in$time_id_seq), "\n\n")

cat("Checking for any NA or Inf values in key columns:\n")
cat("  gname NAs:", sum(is.na(df_in$gname)), "\n")
cat("  gname Infs:", sum(is.infinite(df_in$gname)), "\n")
cat("  time_id_seq NAs:", sum(is.na(df_in$time_id_seq)), "\n")
cat("  time_id_seq Infs:", sum(is.infinite(df_in$time_id_seq)), "\n\n")

cat("Calling did::att_gt with remapped data...\n\n")

# Call att_gt with full error/warning tracing
result <- tryCatch(
  withCallingHandlers({
    did::att_gt(
      yname = "outcome_sim",
      tname = "time_id_seq",
      idname = "unit_id",
      gname = "gname",
      data = df_in,
      panel = TRUE,
      control_group = "notyettreated",
      bstrap = FALSE,
      clustervars = cluster_var,
      est_method = "ipw"
    )
  }, warning = function(w) {
    cat("\n⚠️  WARNING from did::att_gt:\n")
    cat("   ", conditionMessage(w), "\n")
    cat("   Call:", deparse(sys.call(-1))[1], "\n\n")
    invokeRestart("muffleWarning")
  }),
  error = function(e) {
    cat("\n❌ ERROR from did::att_gt:\n")
    cat("   ", conditionMessage(e), "\n")
    NULL
  }
)

if (!is.null(result)) {
  cat("\n✓ att_gt completed\n")
  agg <- did::aggte(result, type = "simple")
  cat("Overall ATT:", agg$overall.att, "\n")
  cat("Overall SE:", agg$overall.se, "\n")
}
