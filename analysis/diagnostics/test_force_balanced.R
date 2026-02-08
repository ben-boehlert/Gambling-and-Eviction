#!/usr/bin/env Rscript
################################################################################
# test_force_balanced.R
#
# What happens if we set allow_unbalanced_panel=FALSE on actual unbalanced data?
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(did)
})

cat("TESTING: What happens with allow_unbalanced_panel=FALSE?\n")
cat("========================================================\n\n")

# Check if we have saved panel data from previous run
if (!file.exists("/tmp/cs_test_out/panel_for_diagnosis.rds")) {
  cat("Panel data not found. Need to extract from actual data.\n")
  cat("Loading actual data files...\n\n")

  # Load the actual panel structure (minimal version)
  if (!file.exists("combined_monthly_panel.csv")) {
    stop("combined_monthly_panel.csv not found. Run from repo root.")
  }

  df <- read_csv("combined_monthly_panel.csv", show_col_types = FALSE)
  treat <- read_csv("state_month_panel_with_treatment.csv", show_col_types = FALSE)

  # Build state panel (simplified)
  panel <- df %>%
    mutate(
      fips_num = suppressWarnings(as.integer(fips)),
      state_fips = as.integer(floor(fips_num / 1000))
    ) %>%
    filter(!is.na(state_fips)) %>%
    group_by(state_fips, month_date) %>%
    summarise(
      filings_count = sum(as.numeric(filings_count), na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      y = log1p(filings_count),
      id = as.integer(factor(state_fips)),
      t = as.integer(factor(as.Date(month_date)))
    ) %>%
    select(id, t, y) %>%
    filter(!is.na(y), is.finite(y))

  # Merge treatment
  # (simplified - just assign random for this test)
  states <- unique(panel$id)
  n_states <- length(states)
  g_vals <- c(rep(0, floor(n_states*0.3)),
              rep(40, floor(n_states*0.25)),
              rep(60, floor(n_states*0.25)),
              rep(80, n_states - floor(n_states*0.3) - 2*floor(n_states*0.25)))

  panel <- panel %>%
    group_by(id) %>%
    mutate(g = g_vals[id]) %>%
    ungroup()

} else {
  cat("Loading saved panel data...\n")
  panel_data <- readRDS("/tmp/cs_test_out/panel_for_diagnosis.rds")
  panel <- panel_data$panel %>%
    select(id, t, g, yhat) %>%
    rename(y = yhat)
}

cat("Panel structure:\n")
cat("  n_states:", length(unique(panel$id)), "\n")
cat("  n_obs:", nrow(panel), "\n")
obs_per_state <- panel %>% count(id) %>% pull(n)
cat("  obs per state: min=", min(obs_per_state), ", median=", median(obs_per_state),
    ", max=", max(obs_per_state), "\n")
cat("  Is balanced?", ifelse(length(unique(obs_per_state)) == 1, "YES", "NO"), "\n\n")

# Try with allow_unbalanced_panel=FALSE
cat("Attempting did::att_gt with allow_unbalanced_panel=FALSE...\n")
result <- tryCatch({
  est <- did::att_gt(
    yname = "y",
    tname = "t",
    idname = "id",
    gname = "g",
    xformla = ~ 1,
    data = panel,
    panel = TRUE,
    control_group = "notyettreated",
    allow_unbalanced_panel = FALSE,  # <-- FORCE BALANCED
    est_method = "reg",
    bstrap = FALSE,  # Faster for test
    cband = FALSE
  )

  agg <- did::aggte(est, type = "simple", na.rm = TRUE)

  list(
    success = TRUE,
    att = as.numeric(agg$overall.att),
    se = as.numeric(agg$overall.se)
  )
}, error = function(e) {
  list(success = FALSE, error_msg = e$message)
})

if (result$success) {
  cat("\n*** UNEXPECTED: It worked! ***\n")
  cat("  ATT:", result$att, "\n")
  cat("  SE:", result$se, "\n")
  cat("\nThis means the panel might actually be balanced.\n")
} else {
  cat("\n*** EXPECTED: It failed with error: ***\n")
  cat(result$error_msg, "\n\n")

  if (grepl("balance", result$error_msg, ignore.case = TRUE)) {
    cat("Error confirms panel is unbalanced.\n")
    cat("Need to balance the panel before using CS-DiD.\n")
  }
}
