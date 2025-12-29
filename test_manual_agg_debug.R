# Debug manual aggregation
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
treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)
baseline <- build_untreated_sample(panel_df, treat_schedule_std)
placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline)
df_sim <- impose_effect(baseline, placebo, effect_size = 3.0, cfg)

# Manually replicate run_estimator_and_extract_p with debugging
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

cat("=== CALLING ATT_GT ===\n")
att <- suppressWarnings(att_gt_safe(df_in, cfg, cluster_var = "state_abb"))

cat("\natt object class:", class(att), "\n")
cat("Number of group-time ATTs:", length(att$att), "\n")
cat("Mean of ATTs:", mean(att$att, na.rm = TRUE), "\n")
cat("inffunc is null?", is.null(att$inffunc), "\n")
if (!is.null(att$inffunc)) {
  cat("inffunc dimensions:", nrow(att$inffunc), "x", ncol(att$inffunc), "\n")
}

cat("\n=== TRYING AGGTE ===\n")
agg_result <- tryCatch({
  agg <- did::aggte(att, type = "simple")
  list(success = TRUE, att = agg$overall.att, se = agg$overall.se)
}, error = function(e) {
  cat("aggte failed with error:", as.character(e), "\n")
  cat("Falling back to manual aggregation...\n")

  est_manual <- mean(att$att, na.rm = TRUE)
  cat("Manual ATT:", est_manual, "\n")

  if (!is.null(att$inffunc) && nrow(att$inffunc) > 0) {
    cat("Computing SE from influence functions...\n")
    inf_simple <- rowMeans(att$inffunc, na.rm = TRUE)
    cat("inf_simple length:", length(inf_simple), "\n")
    cat("inf_simple range:", min(inf_simple), "to", max(inf_simple), "\n")
    se_manual <- sqrt(mean(inf_simple^2, na.rm = TRUE))
    cat("Manual SE:", se_manual, "\n")
  } else {
    cat("No influence functions available\n")
    se_manual <- NA_real_
  }

  list(success = FALSE, att = est_manual, se = se_manual)
})

cat("\n=== FINAL RESULT ===\n")
cat("Success:", agg_result$success, "\n")
cat("ATT:", agg_result$att, "\n")
cat("SE:", agg_result$se, "\n")

if (is.finite(agg_result$att) && is.finite(agg_result$se) && agg_result$se > 0) {
  p <- 2 * pnorm(-abs(agg_result$att / agg_result$se))
  cat("P-value:", p, "\n")
  cat("Reject at 0.05?", p < 0.05, "\n")
} else {
  cat("Cannot compute p-value\n")
}
