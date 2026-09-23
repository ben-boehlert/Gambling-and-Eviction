#!/usr/bin/env Rscript
################################################################################
# prep_twfe_power_rerun_inputs.R
#
# Reshapes the CURRENT state-month panel into the two input files the
# application-era TWFE power sim expects
# (analysis/main/power_simulation_twfe_statepanel_staggered_parallel_fixed.R),
# so that sim can be re-run on the current vintage without editing it.
#
# The old sim rebuilt its own state panel from combined_monthly_panel.csv. That
# path predates the 2026-08-20 rebuild, so here the rebuilt panel is passed in
# as geo_level == "state" rows, which the sim's fallback branch reads as-is.
#
# Pre-PASPA states (NV) are dropped via the canonical universe helper: NV has
# no schedule row because it is always-treated, not never-treated.
#
# Usage (from project root):
#   Rscript analysis/main/prep_twfe_power_rerun_inputs.R <out_dir>
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

source("utils/eviction_treatment_schedule.R")

args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) >= 1) args[1] else "output/twfe_power_rerun/inputs"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

panel_file <- "data/raw/state_month_panel_with_treatment.csv"
treat_file <- "data/raw/sports_gambling_legalization_dates.csv"

panel <- read_csv(panel_file, show_col_types = FALSE) %>%
  filter(!state_abb %in% PRE_PASPA_SPORTS_BETTING)

# The panel's treat_start must be the repaired schedule's online launch date.
sched <- eviction_adoption_outcomes(treat_file, "online_start_date",
                                    censor_end = max(panel$month_date))
panel_dates <- panel %>%
  group_by(state_abb) %>%
  summarise(panel_start = suppressWarnings(min(treat_start, na.rm = TRUE)),
            .groups = "drop") %>%
  mutate(panel_start = if_else(is.finite(panel_start), panel_start, as.Date(NA))) %>%
  left_join(select(sched, state_abb, adopt_date), by = "state_abb")
stopifnot(all(
  (is.na(panel_dates$panel_start) & is.na(panel_dates$adopt_date)) |
    (panel_dates$panel_start == panel_dates$adopt_date),
  na.rm = FALSE
))

controls <- eviction_control_states(unique(panel$state_abb), treat_file,
                                    "online_start_date",
                                    censor_end = max(panel$month_date))
assert_no_pre_paspa_controls(controls, context = "TWFE power re-run control pool")

data_out <- panel %>%
  transmute(
    geo_level = "state",
    geo_id = state.name[match(state_abb, state.abb)],
    fips = NA_integer_,
    month_date,
    filings_count,
    renter_occupied_housing_units,
    filings_per_1k_renters
  )
stopifnot(!anyNA(data_out$geo_id))

treat_out <- panel %>% select(state_abb, month_date, treat_start, treated)
stopifnot(!anyDuplicated(treat_out[c("state_abb", "month_date")]))

write_csv(data_out, file.path(out_dir, "data_state_rows.csv"))
write_csv(treat_out, file.path(out_dir, "treat_state_month.csv"))

cat(sprintf("States: %d (switchers %d, never-treated %d); rows: %d; months %s..%s\n",
            n_distinct(panel$state_abb),
            sum(!is.na(panel_dates$panel_start)),
            sum(is.na(panel_dates$panel_start)),
            nrow(panel), min(panel$month_date), max(panel$month_date)))
