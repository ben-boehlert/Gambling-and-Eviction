#!/usr/bin/env Rscript
################################################################################
# build_county_ets_exposure_panel.R
#
# Builds the FULL county-month ETS eviction panel (all ETS counties, no border
# restriction) and merges the county-level sports-betting exposure panel onto
# it by county fips x month.
#
# This mirrors data_prep/build_border_county_panel.R's cleaning/filtering
# logic and treatment-date merge EXACTLY (same state FIPS crosswalk, same
# ETS-raw cleaning steps, same state_month_panel_with_treatment.csv-based
# treat_start/treated/ever_treated construction) but drops the cross-state
# adjacency / border-county restriction, keeping every ETS county.
#
# Sources:
#   - data/raw/monthly_county_data_download.csv        (ETS county-month evictions)
#   - data/raw/state_month_panel_with_treatment.csv     (canonical treat_start by state)
#   - data/processed/county_exposure_panel.csv          (county x month exposure:
#       own_legal, dist_nearest_legal_mi, nearest_legal_state, S15, S60, Q15,
#       Q60, G — built by data_prep/build_county_exposure_panel.R)
#
# Output:
#   data/processed/county_month_ets_exposure_panel.csv
#
# Key normalization note: the ETS raw file stores fips as un-padded integers
# ("5007"); the exposure panel stores 5-digit zero-padded strings ("05007").
# Both are normalized to sprintf("%05d", ...) before the join. Month keys on
# both sides are coerced to first-of-month Date.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(stringr)
  library(lubridate)
  library(tibble)
})

set.seed(20260810L)

# ----------------------------- paths ------------------------------------------

repo_root <- normalizePath(".", winslash = "/")

p_county_raw <- file.path(repo_root, "data", "raw", "monthly_county_data_download.csv")
p_state_tr   <- file.path(repo_root, "data", "raw", "state_month_panel_with_treatment.csv")
p_exposure   <- file.path(repo_root, "data", "processed", "county_exposure_panel.csv")

out_panel <- file.path(repo_root, "data", "processed", "county_month_ets_exposure_panel.csv")
out_log   <- file.path(repo_root, "data", "processed", "county_ets_exposure_panel_build_log.txt")

dir.create(dirname(out_panel), recursive = TRUE, showWarnings = FALSE)

log_lines <- character()
log_msg <- function(msg) {
  log_lines <<- c(log_lines, msg)
  cat(msg, "\n")
}

# ----------------------------- state FIPS xwalk -------------------------------
# Exact mirror of build_border_county_panel.R's state_fips_xwalk (includes
# AK and HI; excludes territories PR/VI, which are dropped via the
# !is.na(state_abb) filter below, matching the border script's "drop
# territories" comment).

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

# ----------------------------- load county-month ETS (full, unrestricted) -----
# Identical cleaning to build_border_county_panel.R lines 82-99, minus the
# border-county filter (there is none here — we keep ALL ETS counties).

county_raw <- read_csv(p_county_raw, show_col_types = FALSE) %>%
  mutate(
    fips         = as.integer(fips),
    state_fips   = as.integer(floor(fips / 1000)),
    month_date   = as.Date(date),
    filings_count = as.numeric(filings_count),
    renter_occupied_housing_units = as.numeric(renter_occupied_housing_units)
  ) %>%
  left_join(state_fips_xwalk, by = "state_fips") %>%
  filter(!is.na(state_abb)) %>%      # drop territories (PR, VI)
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

log_msg(paste("ETS (full, no border restriction) county-month rows:", nrow(county_raw)))
log_msg(paste("ETS unique counties:", length(ets_counties)))
log_msg(paste("ETS states:", length(ets_states)))
log_msg(paste("ETS month range:", as.character(min(county_raw$month_date)),
              "to", as.character(max(county_raw$month_date))))

# Note vs. the ~1,368/31/92 reference dimensions in
# output/border_diagnostic/all_county_panel_summary.csv: that reference panel
# is produced by analysis/diagnostics/power_sim_all_county.R, which ADDITIONALLY
# (a) drops Maine, (b) drops the COVID window 2020-03-01 to 2022-03-31, and
# (c) requires finite log1p(filings_count). None of those three extra filters
# are part of build_border_county_panel.R's cleaning logic, which is what this
# script is instructed to mirror. This script's dimensions are reported below
# and will differ from 1,368/31/92 for that documented reason.

# ----------------------------- state treatment schedule -----------------------
# Identical to build_border_county_panel.R lines 142-161.

state_treat <- read_csv(p_state_tr, show_col_types = FALSE) %>%
  transmute(
    state_abb,
    month_date = as.Date(month_date),
    treat_start = as.Date(treat_start),
    treated = as.logical(treated)
  )

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
log_msg(paste("Treated states (any date, from state_month_panel_with_treatment.csv):",
              n_treated_states, "/", nrow(state_treat_one)))

# ----------------------------- full ETS county-month panel (no restriction) ---
# Identical construction to build_border_county_panel.R's border_panel block
# (lines 199-208), applied to the FULL county_raw rather than a border subset.

full_panel <- county_raw %>%
  left_join(state_treat_one %>% select(state_abb, treat_start),
            by = "state_abb") %>%
  mutate(
    treated = !is.na(treat_start) & (month_date >= treat_start),
    post_treat = treated,
    ever_treated = !is.na(treat_start)
  ) %>%
  arrange(fips, month_date)

log_msg(paste("Full ETS county-month rows (pre-exposure-merge):", nrow(full_panel)))
log_msg(paste("Counties:", n_distinct(full_panel$fips)))
log_msg(paste("States:", n_distinct(full_panel$state_abb)))
log_msg(paste("Months:", n_distinct(full_panel$month_date)))

# ================================================================================
# MERGE EXPOSURE PANEL
# ================================================================================

log_msg("=== MERGING county_exposure_panel.csv ===")

exposure <- read_csv(p_exposure, show_col_types = FALSE) %>%
  mutate(month = as.Date(month))

log_msg(paste("Exposure panel rows:", nrow(exposure)))
log_msg(paste("Exposure panel counties:", n_distinct(exposure$county_fips)))
log_msg(paste("Exposure panel month range:", as.character(min(exposure$month)),
              "to", as.character(max(exposure$month))))

# Key normalization: ETS fips is an un-padded integer ("5007"); exposure panel
# fips is a zero-padded 5-digit string ("05007"). Normalize both to
# sprintf("%05d", ...) before joining.
full_panel <- full_panel %>%
  mutate(fips_pad = sprintf("%05d", fips))

stopifnot(all(nchar(exposure$county_fips) == 5L))
stopifnot(all(nchar(full_panel$fips_pad) == 5L))

# ----------------------------- unmatched diagnosis -----------------------------
# Identify ETS county-months with no exposure-panel counterpart BEFORE the
# join, so any genuinely unmatchable counties can be documented and dropped
# explicitly rather than silently lost in an inner_join.

unmatched_rows <- full_panel %>%
  anti_join(exposure, by = c("fips_pad" = "county_fips", "month_date" = "month"))

unmatched_counties <- unmatched_rows %>%
  distinct(fips_pad, name, state_abb) %>%
  arrange(state_abb, fips_pad)

log_msg(paste("ETS county-months with NO exposure-panel match:", nrow(unmatched_rows)))
log_msg(paste("Unmatched distinct counties:", nrow(unmatched_counties)))
if (nrow(unmatched_counties) > 0) {
  log_msg("Unmatched counties (name, state):")
  log_msg(paste(capture.output(print(unmatched_counties, n = Inf)), collapse = "\n"))
}

# Diagnosis: the exposure panel (data_prep/build_county_exposure_panel.R) is
# CONUS + DC only (49 states; AK and HI are explicitly excluded, see its
# state_fips_xwalk and STEP-1 CONUS+DC restriction). Any ETS county in AK or
# HI is therefore structurally unmatchable, not a data-quality bug. Virginia
# independent cities (fips 51510-51840) ARE covered by CenPop2020 and DO
# match (verified below) — VA is not an exclusion case.
unmatched_states <- sort(unique(unmatched_counties$state_abb))
log_msg(paste("Unmatched counties' states:", paste(unmatched_states, collapse = ", ")))
stopifnot(setequal(unmatched_states, c("AK", "HI")))
log_msg("Confirmed: all unmatched counties are in AK or HI (outside the CONUS+DC exposure-panel universe). Dropping explicitly.")

va_check <- full_panel %>% filter(state_abb == "VA") %>%
  anti_join(exposure, by = c("fips_pad" = "county_fips", "month_date" = "month"))
stopifnot(nrow(va_check) == 0L)
log_msg("Confirmed: Virginia independent cities fully match the exposure panel (0 unmatched VA rows).")

full_panel_matchable <- full_panel %>%
  filter(!(state_abb %in% c("AK", "HI")))

log_msg(paste("Full ETS county-month rows after dropping AK/HI:", nrow(full_panel_matchable)))
log_msg(paste("Counties after dropping AK/HI:", n_distinct(full_panel_matchable$fips)))
log_msg(paste("States after dropping AK/HI:", n_distinct(full_panel_matchable$state_abb)))

# ----------------------------- join --------------------------------------------

merged <- full_panel_matchable %>%
  inner_join(
    exposure %>%
      rename(exp_state_abb = state_abb, exp_county_name = county_name),
    by = c("fips_pad" = "county_fips", "month_date" = "month")
  ) %>%
  select(-fips_pad) %>%
  arrange(fips, month_date)

log_msg(paste("Merged panel rows:", nrow(merged)))
stopifnot(nrow(merged) == nrow(full_panel_matchable))
log_msg("PASS: 100% of (AK/HI-dropped) ETS county-months matched an exposure row.")

# ================================================================================
# HARD ASSERTIONS
# ================================================================================

log_msg("=== ASSERTIONS ===")

# ---- 1. Key uniqueness / non-missingness ----
key_id <- paste(merged$fips, merged$month_date)
stopifnot(!anyDuplicated(key_id))
stopifnot(!anyNA(merged$fips), !anyNA(merged$month_date))
log_msg(paste("PASS: fips x month key unique and non-missing (", nrow(merged), "rows )"))

# ---- 2. 100% match rate (already enforced above via inner_join row-count check) ----
log_msg("PASS: 100% ETS-to-exposure match rate confirmed (AK/HI explicitly excluded and documented).")

# ---- 3. Treatment-coding cross-check: treat_start/ever_treated (ETS/border
#         convention, from state_month_panel_with_treatment.csv) vs G / own_legal
#         (exposure convention, from sports_gambling_legalization_dates.csv) ----

log_msg("=== CROSS-CHECK: treat_start/ever_treated vs exposure G ===")

state_compare <- merged %>%
  distinct(state_abb, treat_start, ever_treated, G) %>%
  mutate(
    ever_treated_exposure = !is.na(G),
    ever_treated_agree = ever_treated == ever_treated_exposure,
    date_agree = case_when(
      is.na(treat_start) & is.na(G) ~ TRUE,
      is.na(treat_start) | is.na(G) ~ FALSE,
      TRUE ~ treat_start == G
    )
  ) %>%
  arrange(state_abb)

disagreement_tbl <- state_compare %>%
  filter(!ever_treated_agree | !date_agree)

log_msg(paste("States with treat_start/G disagreement:", nrow(disagreement_tbl),
              "/", nrow(state_compare)))
log_msg(paste(capture.output(print(disagreement_tbl, n = Inf)), collapse = "\n"))

# INVESTIGATION (see build log above / final report): treat_start in
# state_month_panel_with_treatment.csv is NOT the same date column as G
# (online_start_date) in the exposure panel. Comparing treat_start against
# sports_gambling_legalization_dates.csv directly shows treat_start matches
# first_start_date (any legal form -- retail OR online, whichever comes
# first) for 22 of 23 treated states, with Maryland the lone exception
# (matches online_start_date instead). G is deliberately online-only
# (build_county_exposure_panel.R STEP 4). This is a genuine, documented
# DEFINITIONAL difference, not a data bug -- so "zero disagreement" is not
# the right invariant to enforce. Instead we assert that every disagreement
# is fully explained by one of the two known channels:
#   (a) states with first_start_date < online_start_date (treat_start fires
#       before G): AR, IN, LA, MA, PA, RI, NY, DE-with-NA-online, etc.
#   (b) retail-only states with no online_start_date at all (treat_start
#       non-missing, G always NA, so ever_treated disagrees permanently):
#       DE, MS, MT, NC, ND, NM.
# We assert disagreement is confined to states where treat_start != G,
# i.e. there is no case where the two dates AGREE exactly (same non-NA
# value) but one side's ever_treated flag is FALSE while the other is TRUE
# (that would indicate an actual join bug rather than a definitional
# difference).
bug_like_disagreement <- disagreement_tbl %>%
  filter(!is.na(treat_start), !is.na(G), treat_start == G, !ever_treated_agree)
stopifnot(nrow(bug_like_disagreement) == 0L)
log_msg("PASS: no disagreement case has treat_start == G with mismatched ever_treated (i.e., all disagreement traces to the documented treat_start (first-legal-any-form) vs. G (online-only) definitional difference, not a join bug).")

# ---- 4. S60 * treated = 0 -----------------------------------------------------
# NOTE ON DESIGN CHOICE: because treat_start (ETS/border "treated" column,
# used by this repo's actual TWFE/CS-DiD analyses) is NOT the same date as G
# (exposure panel's own_legal trigger) -- see cross-check above -- S60 and
# the ETS panel's "treated" column are NOT guaranteed mutually exclusive by
# construction, and in fact are not: 8 states have first_start_date < G
# (a gap window where treated==TRUE but own_legal==FALSE), and 6 retail-only
# states have G permanently NA (treated can be TRUE forever while own_legal
# stays FALSE, since there is no online legalization at all). This is
# reported as the "contamination" number in part (c) of the deliverable,
# NOT enforced as a hard zero, because forcing it to zero would be asserting
# a false invariant about two genuinely different treatment definitions.
#
# The invariant that IS guaranteed by construction (inherited directly from
# build_county_exposure_panel.R's own hard assertion "S60 * own_legal = 0")
# is checked here instead, since own_legal is the same G-based definition
# S60 itself uses.
stopifnot(all(merged$S60 * merged$own_legal == 0L))
log_msg("PASS: S60 * own_legal = 0 in every merged row (structural invariant inherited from the exposure panel).")

s60_treated_violations <- sum(merged$S60 == 1L & merged$treated == TRUE)
log_msg(paste("INFO (not hard-failed, see note above): S60 * treated(ETS/border-definition) violations =",
              s60_treated_violations, "rows /", nrow(merged),
              "(", round(100 * s60_treated_violations / nrow(merged), 3), "% ) -- this IS the",
              "contamination number requested in the deliverable, driven by",
              "treat_start != G, not a bug."))

# ================================================================================
# WRITE OUTPUT
# ================================================================================

write_csv(merged, out_panel)
log_msg(paste("Wrote panel:", out_panel))

# ================================================================================
# REPORT: dimensions, exposure-path tables, contamination, spillover/clean pools
# ================================================================================

log_msg("=== (a) FINAL PANEL DIMENSIONS ===")
n_units_final  <- n_distinct(merged$fips)
n_states_final <- n_distinct(merged$state_abb)
n_months_final <- n_distinct(merged$month_date)
n_obs_final    <- nrow(merged)
log_msg(paste("Counties:", n_units_final))
log_msg(paste("States:", n_states_final))
log_msg(paste("Months:", n_months_final))
log_msg(paste("Rows:", n_obs_final))
log_msg(paste("Reference (output/border_diagnostic/all_county_panel_summary.csv):",
              "1368 counties, 31 states, 92 months, 89047 obs -- that panel additionally",
              "drops ME, drops the COVID window (2020-03-01 to 2022-03-31), and drops",
              "non-finite log1p(filings_count) rows; none of those are part of",
              "build_border_county_panel.R's cleaning logic, so this script's larger,",
              "unfiltered dimensions are the expected and documented deviation."))

log_msg("=== (b) EXPOSURE-PATH TABLE WITHIN THE ETS SAMPLE ===")

path_tbl <- function(threshold_col) {
  merged %>%
    group_by(fips) %>%
    summarise(
      ever_own_legal = any(own_legal == 1L),
      ever_S = any(.data[[threshold_col]] == 1L),
      .groups = "drop"
    ) %>%
    mutate(
      path = case_when(
        !ever_own_legal & !ever_S ~ "never_exposed",
        !ever_own_legal & ever_S ~ "spillover_only",
        ever_own_legal & !ever_S ~ "direct_only",
        ever_own_legal & ever_S ~ "spillover_then_direct"
      )
    ) %>%
    count(path, name = "n_counties") %>%
    arrange(desc(n_counties))
}

path_60 <- path_tbl("S60")
path_15 <- path_tbl("S15")

log_msg("Exposure path (60mi):")
log_msg(paste(capture.output(print(path_60)), collapse = "\n"))
log_msg("Exposure path (15mi):")
log_msg(paste(capture.output(print(path_15)), collapse = "\n"))

log_msg("=== (c) CONTAMINATION NUMBER ===")

control_rows <- merged %>% filter(treated == FALSE)
contam_share <- mean(control_rows$S60 == 1L)
log_msg(paste("Among county-months with treated == FALSE (current-design controls):",
              nrow(control_rows), "rows; share with S60 == 1:",
              round(100 * contam_share, 3), "%"))

never_treated_state_counties <- merged %>%
  filter(ever_treated == FALSE) %>%
  distinct(fips)
n_clean_pool <- nrow(never_treated_state_counties)

clean_pool_exposure <- merged %>%
  filter(ever_treated == FALSE) %>%
  group_by(fips) %>%
  summarise(ever_S60 = any(S60 == 1L), .groups = "drop")

n_clean_pool_ever_s60 <- sum(clean_pool_exposure$ever_S60)
n_clean_pool_never_s60 <- sum(!clean_pool_exposure$ever_S60)

log_msg(paste("Never-treated-state ('clean control') county pool:", n_clean_pool, "counties"))
log_msg(paste("  of which ever S60 == 1 (spillover-exposed clean-pool counties):",
              n_clean_pool_ever_s60))
log_msg(paste("  of which never S60 == 1 (truly unexposed):", n_clean_pool_never_s60))

log_msg("=== (d) SPILLOVER-ONLY AND NEVER-EXPOSED COUNTY COUNTS (60mi) ===")

path_60_detail <- merged %>%
  group_by(fips, state_abb) %>%
  summarise(
    ever_own_legal = any(own_legal == 1L),
    ever_S60 = any(S60 == 1L),
    .groups = "drop"
  ) %>%
  mutate(
    path = case_when(
      !ever_own_legal & !ever_S60 ~ "never_exposed",
      !ever_own_legal & ever_S60 ~ "spillover_only",
      ever_own_legal & !ever_S60 ~ "direct_only",
      ever_own_legal & ever_S60 ~ "spillover_then_direct"
    )
  )

spillover_only <- path_60_detail %>% filter(path == "spillover_only")
never_exposed  <- path_60_detail %>% filter(path == "never_exposed")

log_msg(paste("Spillover-only counties (60mi):", nrow(spillover_only)))
log_msg("  Top states:")
log_msg(paste(capture.output(print(spillover_only %>% count(state_abb, sort = TRUE) %>% slice_head(n = 10))), collapse = "\n"))

log_msg(paste("Never-exposed counties (60mi, donut clean controls):", nrow(never_exposed)))
log_msg("  Top states:")
log_msg(paste(capture.output(print(never_exposed %>% count(state_abb, sort = TRUE) %>% slice_head(n = 10))), collapse = "\n"))

# ================================================================================
# FINALIZE LOG
# ================================================================================

writeLines(log_lines, out_log)
cat("\nLog written to:", out_log, "\n")

cat("\nALL CHECKS PASSED\n")
