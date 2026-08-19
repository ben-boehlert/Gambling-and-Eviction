#!/usr/bin/env Rscript
################################################################################
# make_maturation50_schedule.R
#
# Builds data/processed/maturation50_schedule.csv — a treatment schedule for
# the blinded power framework in which the ANALYSIS treatment date is market
# MATURATION (handle50: the first month a state's sports-betting handle
# reaches 50% of its own peak month; data/processed/activity_treatment_dates.csv
# column `treat_start`, infrastructure in docs/methodology/
# ACTIVITY_BASED_TREATMENT.md), while the BLINDNESS cutoff column
# (`first_start_date`, first legal sports betting of ANY kind) is carried over
# unchanged from data/raw/sports_gambling_legalization_dates.csv.
#
# Blindness note: maturation dates derive from betting-handle DATES only,
# never from eviction outcomes — permitted design information under
# POWER_SIMULATION_BLINDNESS_PROTOCOL.md §2 (same basis as the ramp75 lags in
# config/power_lpdid_gate_postcovid.yml). Because first_start_date <= the
# maturation date wherever both exist, the loader's blindness truncation
# (always first_start_date - anticipation) is STRICTLY conservative for the
# maturation treatment definition.
#
# Run from the repository root:
#   Rscript analysis/data_prep/make_maturation50_schedule.R
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

stopifnot(file.exists("power_simulation_cs.R"))

raw <- read_csv("data/raw/sports_gambling_legalization_dates.csv",
                show_col_types = FALSE)
act <- read_csv("data/processed/activity_treatment_dates.csv",
                show_col_types = FALSE)

stopifnot(all(c("state", "first_start_date", "online_start_date") %in%
                names(raw)),
          all(c("State", "treat_start", "handle_threshold_fraction") %in%
                names(act)),
          all(act$handle_threshold_fraction == 0.5))

out <- raw %>%
  transmute(state = .data$state,
            first_start_date  = as.Date(.data$first_start_date),
            online_start_date = as.Date(.data$online_start_date)) %>%
  full_join(act %>%
              transmute(state = .data$State,
                        maturation50_start_date = as.Date(.data$treat_start)),
            by = "state")

# Invariants: maturation never precedes first legal betting; a maturation date
# requires a legalization record.
bad <- out %>%
  filter(!is.na(.data$maturation50_start_date),
         is.na(.data$first_start_date) |
           .data$maturation50_start_date < .data$first_start_date)
stopifnot("maturation date precedes (or lacks) first legal betting" =
            nrow(bad) == 0L)
stopifnot(!anyDuplicated(out$state), !any(is.na(out$state)))

write_csv(out, "data/processed/maturation50_schedule.csv")
cat(sprintf(
  "maturation50_schedule.csv: %d states, %d with a maturation date (range %s..%s)\n",
  nrow(out), sum(!is.na(out$maturation50_start_date)),
  format(min(out$maturation50_start_date, na.rm = TRUE)),
  format(max(out$maturation50_start_date, na.rm = TRUE))))
