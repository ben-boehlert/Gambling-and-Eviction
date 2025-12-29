# Debug aggte failure
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(did)
})

cat("=== Package versions ===\n")
cat("did version:", as.character(packageVersion("did")), "\n")
cat("BMisc version:", as.character(packageVersion("BMisc")), "\n\n")

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

cat("=== Trying different aggte approaches ===\n\n")

# Try 1: Manual aggregation
cat("1. Manual aggregation:\n")
mean_att <- mean(att$att, na.rm = TRUE)
cat("   Mean of all group-time ATTs:", mean_att, "\n\n")

# Try 2: aggte with explicit parameters
cat("2. aggte with explicit parameters:\n")
result2 <- tryCatch({
  agg <- did::aggte(
    MP = att,
    type = "simple",
    balance_e = NULL,
    min_e = NULL,
    max_e = NULL,
    na.rm = TRUE
  )
  list(success = TRUE, att = agg$overall.att, se = agg$overall.se)
}, error = function(e) {
  list(success = FALSE, error = as.character(e))
})
if (result2$success) {
  cat("   ✓ ATT:", result2$att, "SE:", result2$se, "\n")
} else {
  cat("   ❌", result2$error, "\n")
}

# Try 3: aggte with dynamic aggregation first
cat("\n3. aggte with type='dynamic':\n")
result3 <- tryCatch({
  agg <- did::aggte(att, type = "dynamic")
  list(success = TRUE, class = class(agg))
}, error = function(e) {
  list(success = FALSE, error = as.character(e))
})
if (result3$success) {
  cat("   ✓ Success, class:", result3$class, "\n")
} else {
  cat("   ❌", result3$error, "\n")
}

# Try 4: Check att object structure
cat("\n4. Check att object names:\n")
cat("   Names in att object:", paste(names(att), collapse = ", "), "\n")

# Try 5: Try calling aggte through different namespace
cat("\n5. Using did:::aggte.MP directly:\n")
result5 <- tryCatch({
  agg <- did:::aggte.MP(att, type = "simple")
  list(success = TRUE, att = agg$overall.att, se = agg$overall.se)
}, error = function(e) {
  list(success = FALSE, error = as.character(e))
})
if (result5$success) {
  cat("   ✓ ATT:", result5$att, "SE:", result5$se, "\n")
} else {
  cat("   ❌", result5$error, "\n")
}

# Try 6: Check if it's the data.table issue
cat("\n6. Converting att to use non-data.table data:\n")
att_copy <- att
att_copy$DIDparams$data <- as.data.frame(att$DIDparams$data)
result6 <- tryCatch({
  agg <- did::aggte(att_copy, type = "simple")
  list(success = TRUE, att = agg$overall.att, se = agg$overall.se)
}, error = function(e) {
  list(success = FALSE, error = as.character(e))
})
if (result6$success) {
  cat("   ✓ ATT:", result6$att, "SE:", result6$se, "\n")
} else {
  cat("   ❌", result6$error, "\n")
}
