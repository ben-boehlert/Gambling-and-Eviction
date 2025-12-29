# Single simulation test with maximum verbosity
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(did)
  library(fixest)
  library(glue)
})

set.seed(123)

# Minimal config
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
  did_bstrap = FALSE,  # No bootstrap
  did_biters = 50,
  did_cband = FALSE,
  cluster_level = "state",
  estimand = "overall_att",
  target_h = 12,
  alpha = 0.05
)

cat("Loading functions from power_simulation_cs.R...\n")
source("power_simulation_cs.R", echo = FALSE)

cat("\n=== SINGLE SIMULATION TEST ===\n\n")

# Load data
cat("1. Loading panel...\n")
panel_df <- load_panel(cfg)
cat("   Units:", n_distinct(panel_df$unit_id), "\n")
cat("   unit_id class:", class(panel_df$unit_id), "\n")
cat("   unit_id example:", head(panel_df$unit_id, 3), "\n\n")

# Treatment schedule
cat("2. Building treatment schedule...\n")
cluster_var <- "state_abb"
treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)
cat("   Treated units:", sum(treat_schedule_std$ever_treated & treat_schedule_std$g_id > 0), "\n\n")

# Baseline
cat("3. Building baseline (A1)...\n")
baseline <- build_untreated_sample(panel_df, treat_schedule_std)
cat("   Baseline obs:", nrow(baseline), "\n")
cat("   Baseline units:", n_distinct(baseline$unit_id), "\n\n")

# Placebo schedule
cat("4. Drawing placebo schedule...\n")
placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = baseline)
cat("   Placebo treated:", sum(placebo$g_placebo > 0), "\n\n")

# Impose effect
cat("5. Imposing effect (1.0)...\n")
df_sim <- impose_effect(baseline, placebo, effect_size = 1.0, cfg)
cat("   Sim data obs:", nrow(df_sim), "\n\n")

# Prepare for CS
cat("6. Preparing data for CS estimator...\n")
df_in <- df_sim %>%
  mutate(gname = as.integer(if_else(is.na(g_placebo), 0L, g_placebo)))

cat("   gname distribution:\n")
print(df_in %>% count(gname) %>% arrange(gname))

cat("\n   unit_id class in df_in:", class(df_in$unit_id), "\n")
cat("   gname class:", class(df_in$gname), "\n")
cat("   time_id class:", class(df_in$time_id), "\n\n")

if (all(df_in$gname == 0L)) {
  stop("❌ All gname = 0, no treated units!")
}

# Run CS estimator
cat("7. Running CS estimator...\n")
result <- tryCatch({
  args <- list(
    yname = "outcome_sim",
    tname = "time_id",
    idname = "unit_id",
    gname = "gname",
    data = df_in,
    panel = TRUE,
    control_group = "notyettreated",
    bstrap = cfg$did_bstrap,
    biters = cfg$did_biters,
    cband = cfg$did_cband,
    clustervars = cluster_var
  )

  if (!is.null(cfg$weights_var) && cfg$weights_var %in% names(df_in)) {
    args$weightsname <- cfg$weights_var
  }

  fmls <- names(formals(did::att_gt))
  if ("cores" %in% fmls) args$cores <- 1L
  if ("ncores" %in% fmls) args$ncores <- 1L
  if ("parallel" %in% fmls) args$parallel <- FALSE

  cat("   Calling did::att_gt...\n")
  att <- do.call(did::att_gt, args)

  cat("   ✓ att_gt succeeded\n")
  cat("   Aggregating...\n")

  agg <- did::aggte(att, type = "simple")

  cat("   ✓ aggte succeeded\n")
  cat("   Overall ATT:", agg$overall.att, "\n")
  cat("   Overall SE:", agg$overall.se, "\n")

  est <- agg$overall.att
  se <- agg$overall.se

  cat("   is.finite(est):", is.finite(est), "\n")
  cat("   is.finite(se):", is.finite(se), "\n")
  cat("   se > 0:", se > 0, "\n")

  if (is.finite(est) && is.finite(se) && se > 0) {
    p <- 2 * pnorm(-abs(est / se))
    cat("   ✓ p-value:", p, "\n")
    list(success = TRUE, p = p, est = est, se = se)
  } else {
    cat("   ❌ est or se not usable\n")
    list(success = TRUE, p = NA, est = est, se = se)
  }

}, error = function(e) {
  cat("   ❌ ERROR:", conditionMessage(e), "\n")
  list(success = FALSE, error = conditionMessage(e))
})

cat("\n=== RESULT ===\n")
if (result$success) {
  cat("✓ CS estimator ran\n")
  cat("  p =", result$p, "\n")
  cat("  est =", result$est, "\n")
  cat("  se =", result$se, "\n")
} else {
  cat("✗ CS estimator failed:\n")
  cat(" ", result$error, "\n")
}
