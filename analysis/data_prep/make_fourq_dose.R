#!/usr/bin/env Rscript
################################################################################
# make_fourq_dose.R
#
# NY Fed-style (Goss & Mangrum, FRBNY SR 1184) early-exposure DOSE for each
# online-legalizing state: mean monthly sports-betting Handle over the four
# complete calendar quarters after the launch quarter (launch quarter omitted
# as a transition, matching quality_reports/handle_four_quarters_data_profile.md),
# normalized per adult (18+) resident.
#
# WHY per adult, not per renter: the state panel's renter_occupied_housing_units
# covers only ETS-covered counties (and is 0/NA for RI, LA, MA, MO), so a
# statewide-handle / partial-coverage-renters ratio is inconsistent. Per-adult
# matches the NY Fed convention; a per-renter variant needs statewide ACS
# renter counts (not built here).
#
# The dose is measured from launch+~15 months of handle data only — it never
# touches eviction outcomes, and for COVID-era launchers the dose window may
# overlap the dropped COVID OUTCOME months without harm (the splice drops
# eviction months, not handle data).
#
# Output: data/processed/fourq_dose_per_adult.csv
#   state, state_abb, online_start_date, n_months_observed (>=12 required),
#   fourq_handle_mean_monthly, adults_18plus, dose_per_adult_month, in_ets_panel,
#   dose_tercile (within in-panel complete-4Q states)
#
# Run from the repository root:  Rscript analysis/data_prep/make_fourq_dose.R
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(lubridate)
})

stopifnot(file.exists("power_simulation_cs.R"))

h <- read_csv("data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv",
              show_col_types = FALSE) %>%
  transmute(state = .data$State, month_date = as.Date(.data$month_date),
            handle = as.numeric(.data$Handle)) %>%
  filter(!is.na(.data$handle))

sched <- read_csv("data/raw/sports_gambling_legalization_dates.csv",
                  show_col_types = FALSE) %>%
  transmute(state = .data$state,
            online_start_date = as.Date(.data$online_start_date))

adults <- read_csv("data/processed/state_adult_population_monthly.csv",
                   show_col_types = FALSE) %>%
  group_by(.data$State) %>%
  summarise(adults_18plus = mean(.data$pop18, na.rm = TRUE), .groups = "drop")

panel_states <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                         show_col_types = FALSE) %>%
  distinct(.data$state_abb) %>% pull()

abbm <- c(setNames(state.abb, state.name), "District of Columbia" = "DC")

dose <- sched %>%
  filter(!is.na(.data$online_start_date)) %>%
  rowwise() %>%
  do({
    st <- .$state; lg <- .$online_start_date
    q0_end <- ceiling_date(lg, "quarter") - days(1)
    fq <- h %>% filter(.data$state == st, .data$month_date > q0_end,
                       .data$month_date <= q0_end %m+% months(12))
    tibble(state = st, state_abb = unname(abbm[st]), online_start_date = lg,
           n_months_observed = nrow(fq),
           fourq_handle_mean_monthly = mean(fq$handle))
  }) %>%
  ungroup() %>%
  filter(!is.na(.data$fourq_handle_mean_monthly)) %>%
  left_join(adults, by = c("state" = "State")) %>%
  mutate(dose_per_adult_month =
           .data$fourq_handle_mean_monthly / .data$adults_18plus,
         in_ets_panel = .data$state_abb %in% panel_states)

# Terciles among the analysis-usable set only (in panel, complete window).
usable <- dose$in_ets_panel & dose$n_months_observed >= 12L
dose$dose_tercile <- NA_integer_
dose$dose_tercile[usable] <- ntile(dose$dose_per_adult_month[usable], 3)

stopifnot(!anyDuplicated(dose$state_abb))
write_csv(dose, "data/processed/fourq_dose_per_adult.csv")
cat(sprintf(
  "fourq_dose_per_adult.csv: %d states with handle (%d in-panel complete-4Q); dose $/adult-mo p25 %.1f median %.1f p75 %.1f\n",
  nrow(dose), sum(usable),
  quantile(dose$dose_per_adult_month[usable], .25),
  median(dose$dose_per_adult_month[usable]),
  quantile(dose$dose_per_adult_month[usable], .75)))
