#!/usr/bin/env Rscript
################################################################################
# build_state_month_panel_with_lsr.R
#
# Purpose:
#   Attach Legal Sports Report (LSR) sports betting handle/revenue/taxes series to
#   the repo's state-month eviction panel, producing a single analysis-ready CSV.
#
# Inputs:
#   - data/raw/state_month_panel_with_treatment.csv
#   - data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv
#
# Output:
#   - data/processed/state_month_panel_with_treatment_lsr.csv
#
# Notes:
#   - LSR values are totals at the state-month level (retail + online where both exist).
#   - By default we only impute zeros *before* each state's first LSR month; gaps
#     after reporting starts remain NA (so we don't treat missing reporting as 0).
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

POWER_SIM_LIBRARY_MODE <- TRUE
source("power_simulation_cs.R")

PANEL_IN <- Sys.getenv("PANEL_IN", "data/raw/state_month_panel_with_treatment.csv")
OUT_FILE <- Sys.getenv("OUT_FILE", "data/processed/state_month_panel_with_treatment_lsr.csv")

dir.create(dirname(OUT_FILE), recursive = TRUE, showWarnings = FALSE)

panel <- readr::read_csv(PANEL_IN, show_col_types = FALSE) %>%
  mutate(
    state_abb = as.character(state_abb),
    month_date = as.Date(month_date)
  )

cfg2 <- cfg
cfg2$data_dir <- "data/raw"

panel2 <- add_lsr_handle_revenue(panel, cfg2, impute_zero_pre_first = TRUE) %>%
  mutate(
    lsr_handle_per_1k_renters = if_else(
      "renter_occupied_housing_units" %in% names(.) &
        !is.na(renter_occupied_housing_units) & renter_occupied_housing_units > 0 &
        !is.na(lsr_handle),
      1000 * lsr_handle / renter_occupied_housing_units,
      NA_real_
    ),
    lsr_revenue_per_1k_renters = if_else(
      "renter_occupied_housing_units" %in% names(.) &
        !is.na(renter_occupied_housing_units) & renter_occupied_housing_units > 0 &
        !is.na(lsr_revenue),
      1000 * lsr_revenue / renter_occupied_housing_units,
      NA_real_
    )
  )

readr::write_csv(panel2, OUT_FILE)
cat("Wrote:", OUT_FILE, "\n")

################################################################################
# Example downstream uses (run interactively)
#
# 1) Validate/adjust treatment timing:
#    - Use the schedule-based start (first/retail/online) vs LSR-based "first
#      observed handle" month (lsr_first_date in read_sports_schedule()).
#
# 2) "Dose"/intensity summaries:
#    - Compute post-legalization average handle by state and report heterogeneity
#      in eviction effects by high/low-handle states.
#
# 3) Mechanism / exposure (interpret carefully):
#    - If you want an exposure-style regression, you can use lsr_log_handle or
#      lsr_handle_per_1k_renters; but note these are post-treatment variables.
#      A cleaner approach is often to treat legalization as the policy shock and
#      use handle only for descriptive mechanism checks or for IV-style designs.
################################################################################
