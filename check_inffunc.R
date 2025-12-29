# Check inffunc structure
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

att <- suppressWarnings(att_gt_safe(df_in, cfg, cluster_var = "state_abb"))

cat("=== INFFUNC STRUCTURE ===\n")
cat("Class:", class(att$inffunc), "\n")
cat("typeof:", typeof(att$inffunc), "\n")
cat("is.matrix:", is.matrix(att$inffunc), "\n")
cat("is.array:", is.array(att$inffunc), "\n")
cat("dim:", paste(dim(att$inffunc), collapse = " x "), "\n")
cat("length:", length(att$inffunc), "\n")

if (is.matrix(att$inffunc) || is.array(att$inffunc)) {
  cat("\n✓ It's a matrix/array\n")
  inf_simple <- rowMeans(att$inffunc, na.rm = TRUE)
  cat("inf_simple computed, length:", length(inf_simple), "\n")
} else if (is.list(att$inffunc)) {
  cat("\n✗ It's a list with", length(att$inffunc), "elements\n")
  cat("First element class:", class(att$inffunc[[1]]), "\n")
  if (is.numeric(att$inffunc[[1]])) {
    cat("First element length:", length(att$inffunc[[1]]), "\n")
  }
} else {
  cat("\n✗ Unknown structure\n")
  print(str(att$inffunc))
}
