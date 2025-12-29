# Test if att_gt actually returns something despite the warning
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(did)
})

set.seed(333)

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
placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline)
df_sim <- impose_effect(baseline, placebo, effect_size = 1.5, cfg)

# Apply remapping manually
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

cat("Calling did::att_gt...\n")
cat("  Data has", nrow(df_in), "rows\n")
cat("  gname range:", min(df_in$gname), "to", max(df_in$gname), "\n\n")

att <- NULL
att <- tryCatch({
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
}, error = function(e) {
  cat("ERROR:", conditionMessage(e), "\n")
  NULL
})

cat("\n")
if (is.null(att)) {
  cat("❌ att_gt returned NULL or errored\n")
} else {
  cat("✓ att_gt returned an object\n")
  cat("  Class:", class(att), "\n")
  cat("  Names:", paste(names(att), collapse = ", "), "\n\n")

  cat("Aggregating...\n")
  agg <- did::aggte(att, type = "simple")
  cat("  overall.att:", agg$overall.att, "\n")
  cat("  overall.se:", agg$overall.se, "\n\n")

  if (is.finite(agg$overall.att) && is.finite(agg$overall.se) && agg$overall.se > 0) {
    p <- 2 * pnorm(-abs(agg$overall.att / agg$overall.se))
    cat("  ✓ p-value:", p, "\n")
  } else {
    cat("  ❌ Cannot compute p-value (non-finite values)\n")
  }
}
