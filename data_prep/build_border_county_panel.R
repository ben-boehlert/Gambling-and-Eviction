#!/usr/bin/env Rscript
################################################################################
# build_border_county_panel.R
#
# Builds the county-month border-discontinuity panel from:
#   - data/raw/monthly_county_data_download.csv      (ETS county-month eviction)
#   - data/processed/county_adjacency_edges.csv      (Census adjacency)
#   - data/raw/sports_gambling_legalization_dates.csv (state treatment dates)
#   - data/raw/state_month_panel_with_treatment.csv  (canonical treat_start by state)
#
# A "border county" is a county that has at least one Census-adjacent neighbor
# in a DIFFERENT state that also appears in the ETS panel. The "border pairs"
# file lists those cross-state edges (one row per directed edge). The
# "county_month_border_panel" file is the ETS county-month panel restricted to
# border counties.
#
# Treatment is at the state level: a county is treated from its state's
# online_start_date onward (per state_month_panel_with_treatment.csv's
# treat_start, which matches the convention used in the state-panel TWFE
# power sim).
#
# Outputs (data/processed/):
#   border_county_pairs.csv          — cross-state adjacency edges where BOTH
#                                       counties appear in the ETS panel.
#                                       Includes treatment status of each side.
#   county_month_border_panel.csv    — county-month subsample restricted to
#                                       border counties, with treat_start /
#                                       treated columns merged from state file.
#   border_panel_build_log.txt       — text log of build counts.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(stringr)
  library(lubridate)
  library(tibble)
})

set.seed(20260521L)

# ----------------------------- paths ------------------------------------------

repo_root <- normalizePath(".", winslash = "/")

p_county_raw <- file.path(repo_root, "data", "raw", "monthly_county_data_download.csv")
p_edges      <- file.path(repo_root, "data", "processed", "county_adjacency_edges.csv")
p_state_tr   <- file.path(repo_root, "data", "raw", "state_month_panel_with_treatment.csv")

out_pairs    <- file.path(repo_root, "data", "processed", "border_county_pairs.csv")
out_panel    <- file.path(repo_root, "data", "processed", "county_month_border_panel.csv")
out_log      <- file.path(repo_root, "data", "processed", "border_panel_build_log.txt")

dir.create(dirname(out_pairs), recursive = TRUE, showWarnings = FALSE)

log_lines <- character()
log_msg <- function(msg) {
  log_lines <<- c(log_lines, msg)
  cat(msg, "\n")
}

# ----------------------------- state FIPS xwalk -------------------------------
# Mirror of state_fips_xwalk in power_simulation_cs.R, kept self-contained so
# this script can be sourced/run independently of the larger config object.

state_fips_xwalk <- tribble(
  ~state_fips, ~state_abb,
   1, "AL",  2, "AK",  4, "AZ",  5, "AR",  6, "CA",  8, "CO",  9, "CT",
  10, "DE", 11, "DC", 12, "FL", 13, "GA", 15, "HI", 16, "ID",
  17, "IL", 18, "IN", 19, "IA", 20, "KS", 21, "KY", 22, "LA",
  23, "ME", 24, "MD", 25, "MA", 26, "MI", 27, "MN", 28, "MS",
  29, "MO", 30, "MT", 31, "NE", 32, "NV", 33, "NH", 34, "NJ",
  35, "NM", 36, "NY", 37, "NC", 38, "ND", 39, "OH", 40, "OK",
  41, "OR", 42, "PA", 44, "RI", 45, "SC", 46, "SD", 47, "TN",
  48, "TX", 49, "UT", 50, "VT", 51, "VA", 53, "WA", 54, "WV",
  55, "WI", 56, "WY"
)

# ----------------------------- load county-month ETS --------------------------

county_raw <- read_csv(p_county_raw, show_col_types = FALSE) %>%
  mutate(
    fips         = as.integer(fips),
    state_fips   = as.integer(floor(fips / 1000)),
    month_date   = as.Date(date),
    filings_count = as.numeric(filings_count),
    renter_occupied_housing_units = as.numeric(renter_occupied_housing_units)
  ) %>%
  left_join(state_fips_xwalk, by = "state_fips") %>%
  filter(!is.na(state_abb)) %>%      # drop territories
  mutate(
    filings_per_1k_renters = if_else(
      is.finite(renter_occupied_housing_units) & renter_occupied_housing_units > 0,
      1000 * filings_count / renter_occupied_housing_units,
      NA_real_
    )
  ) %>%
  filter(!is.na(month_date))

ets_counties <- sort(unique(county_raw$fips))
ets_states   <- sort(unique(county_raw$state_abb))

log_msg(paste("ETS county-month rows:", nrow(county_raw)))
log_msg(paste("ETS unique counties:", length(ets_counties)))
log_msg(paste("ETS states:", length(ets_states)))

# ----------------------------- load adjacency ---------------------------------

edges_all <- read_csv(p_edges, show_col_types = FALSE) %>%
  mutate(
    fips_a = as.integer(fips_a),
    fips_b = as.integer(fips_b),
    state_fips_a = as.integer(floor(fips_a / 1000)),
    state_fips_b = as.integer(floor(fips_b / 1000))
  ) %>%
  left_join(state_fips_xwalk, by = c("state_fips_a" = "state_fips")) %>%
  rename(state_abb_a = state_abb) %>%
  left_join(state_fips_xwalk, by = c("state_fips_b" = "state_fips")) %>%
  rename(state_abb_b = state_abb) %>%
  filter(!is.na(state_abb_a), !is.na(state_abb_b))

log_msg(paste("Total adjacency edges:", nrow(edges_all)))

# ----------------------------- cross-state edges restricted to ETS ------------

cross_state_edges <- edges_all %>%
  filter(state_abb_a != state_abb_b) %>%
  filter(fips_a %in% ets_counties, fips_b %in% ets_counties)

log_msg(paste("Cross-state edges where BOTH counties in ETS:",
              nrow(cross_state_edges)))

# Border-county FIPS = any county that appears as fips_a in cross_state_edges.
# (Edge list is symmetric, so this captures all border counties.)
border_fips <- sort(unique(cross_state_edges$fips_a))
log_msg(paste("Border counties (in ETS, with cross-state ETS neighbor):",
              length(border_fips)))

# ----------------------------- state treatment schedule -----------------------

state_treat <- read_csv(p_state_tr, show_col_types = FALSE) %>%
  transmute(
    state_abb,
    month_date = as.Date(month_date),
    treat_start = as.Date(treat_start),
    treated = as.logical(treated)
  )

# One adoption date per state (treat_start is constant within a state;
# never-treated states have NA throughout).
state_treat_one <- state_treat %>%
  group_by(state_abb) %>%
  summarise(
    treat_start = suppressWarnings(min(treat_start, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  mutate(
    treat_start = if_else(is.finite(treat_start), treat_start, as.Date(NA)),
    ever_treated = !is.na(treat_start)
  )

n_treated_states <- sum(state_treat_one$ever_treated)
log_msg(paste("Treated states (any date):", n_treated_states,
              "/", nrow(state_treat_one)))

# ----------------------------- annotate pairs with treatment ------------------

border_pairs <- cross_state_edges %>%
  select(fips_a, fips_b, state_abb_a, state_abb_b, name_a, name_b) %>%
  left_join(state_treat_one %>% select(state_abb, treat_start_a = treat_start,
                                       ever_treated_a = ever_treated),
            by = c("state_abb_a" = "state_abb")) %>%
  left_join(state_treat_one %>% select(state_abb, treat_start_b = treat_start,
                                       ever_treated_b = ever_treated),
            by = c("state_abb_b" = "state_abb")) %>%
  mutate(
    # "discontinuity" pair: exactly one side is ever-treated, OR both are
    # treated at different dates (the second case gives identifying
    # variation only over a finite window).
    treated_xor    = xor(ever_treated_a, ever_treated_b),
    treated_both   = ever_treated_a & ever_treated_b,
    same_date      = treated_both & (treat_start_a == treat_start_b),
    has_discontinuity = treated_xor | (treated_both & !same_date)
  )

log_msg(paste("Pairs with treatment discontinuity (xor or different dates):",
              sum(border_pairs$has_discontinuity)))
log_msg(paste("  of which treated_xor:", sum(border_pairs$treated_xor)))
log_msg(paste("  of which both-treated different dates:",
              sum(border_pairs$treated_both & !border_pairs$same_date)))

write_csv(border_pairs, out_pairs)
log_msg(paste("Wrote pairs:", out_pairs))

# ----------------------------- restricted county-month panel ------------------

# Restrict to border counties only.
border_panel <- county_raw %>%
  filter(fips %in% border_fips) %>%
  left_join(state_treat_one %>% select(state_abb, treat_start),
            by = "state_abb") %>%
  mutate(
    treated = !is.na(treat_start) & (month_date >= treat_start),
    post_treat = treated,
    ever_treated = !is.na(treat_start)
  ) %>%
  arrange(fips, month_date)

log_msg(paste("Border county-month rows:", nrow(border_panel)))
log_msg(paste("Border counties retained:", n_distinct(border_panel$fips)))
log_msg(paste("Border states represented:", n_distinct(border_panel$state_abb)))

# Useful diagnostics for the power-sim consumer.
n_border_treated_counties <- border_panel %>%
  filter(ever_treated) %>%
  distinct(fips) %>%
  nrow()
n_border_control_counties <- border_panel %>%
  filter(!ever_treated) %>%
  distinct(fips) %>%
  nrow()
log_msg(paste("Border counties in treated states:", n_border_treated_counties))
log_msg(paste("Border counties in never-treated states:",
              n_border_control_counties))

write_csv(border_panel, out_panel)
log_msg(paste("Wrote panel:", out_panel))

# ----------------------------- finalize log -----------------------------------

writeLines(log_lines, out_log)
cat("\nLog written to:", out_log, "\n")
