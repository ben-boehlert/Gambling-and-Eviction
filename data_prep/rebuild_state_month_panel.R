#!/usr/bin/env Rscript
# ============================================================================
# rebuild_state_month_panel.R
#
# Rebuild data/raw/state_month_panel_with_treatment.csv WITHOUT the ETS
# double count diagnosed 2026-08-20
# (analysis/diagnostics/statepanel_double_count_audit.R).
#
# THE BUG: for 12 states the old panel was
#   filings_count = sum(county download) + merged_ets_combined.csv series
# an exact addition on 891 of 916 overlap state-months (the other 25 are WI,
# already repaired by 08c). The two components cover the same filings, and
# because each ETS series has its own span the double count switched on/off
# mid-panel: cities series START 2020-01 (AZ OH SC TN TX jump up), state_level
# series END 2023-02 (CT DE IN MN PA VA drop), FL/RI/NY state series end
# 2019-12 (drop). 1.2x-2.4x level breaks with no eviction content.
#
# THE SOURCE FILE IS A HYBRID, NOT AN LSC DOWNLOAD.
#   monthly_county_data_download.csv began as an LSC CCDI pull, but court-source
#   series were MERGED INTO IT. As of 2026-09-17 the local file holds 124,325
#   rows to the live download's 120,357; the live file is a strict subset, and
#   all 3,968 local-only keys are NC (3,600) and ME (368). LSC's own NC series
#   ends 2023-06 and its ME series ends 2023-12; everything after that is
#   NC AOC Summary Ejectment and Maine Judicial Branch FED respectively.
#   => RE-DOWNLOADING THIS FILE IS DESTRUCTIVE, NOT A REFRESH. It deletes
#      NC 2023-07..2026-06 and ME 2024-01..2025-11. NC is a switcher under the
#      inclusion rule whose entire outcome window lives in that range.
#   => A fresh LSC pull lacking those rows is NOT evidence of a retraction.
#   The HYBRID_SOURCE block below restamps panel_source accordingly, because the
#   inherited `county_download_fixed_basket` label has caused this exact
#   misreading more than once. See docs/DATA_PROVENANCE.md §1 (correction
#   2026-09-14) and docs/STATE_SOURCES.md.
#
# REBUILD RULES (one consistent source per state):
#   COUNTY   sum of monthly_county_data_download.csv, for every state in the
#            download except NH and WI. NOTE this is the hybrid file above, so
#            "county" does not imply "LSC" for NC (2023-07+) or ME (2024-01+).
#   KEEP-OLD rows carried from the PRE-FIX panel where it is single-source:
#              NH  court-source repair (06_; download has the 2023H2 zero-fill)
#              WI  court-source repair (08c_)
#              MD  Judiciary monthly Landlord/Tenant COMPLAINT filings parsed
#                  from annual-statistics PDFs (07_). NOT the Socrata
#                  post-judgment warrant extract, which 07_ supersedes.
#              LA MA MO NM NV RI  ETS-only series; no county rows exist, so
#                  these were never double counted. They carry NO renter
#                  denominator -> rate is NA, never fabricated.
#   NY       county sums 2019-01+ only; the pre-2019 block is a different-basket
#            ETS series (seam at 2019-01).
#
# KNOWN REMAINING LIMITATION — NOT fixed here, flagged in the output:
#   The county download's reporting basket CHANGES over time, so a state total
#   is a composition-varying sum. Severe cases: FL drops Miami-Dade and Lee at
#   2024-01 (one month after FL's own treatment date), TN falls 36 -> 12 -> 3
#   counties over 2024-03/04, TX loses Harris at 2024-05 (renter denominator
#   -48%). A state-month presence check does NOT catch this. This script emits
#   `n_counties` and `basket_share` on every row plus a coverage QA file so
#   downstream code can censor; it does NOT silently pick a basket.
#
# Output:
#   data/raw/state_month_panel_with_treatment.csv       (canonical, replaced)
#   data/raw/deprecated/state_month_panel_with_treatment_double_counted_2026-08-20.csv
#       (pre-fix original; written ONCE and never overwritten)
#   data/processed/state_panel_rebuild_source_table.csv    per-state provenance
#   data/processed/state_panel_rebuild_field_changes.csv   field-level QA
#   data/processed/state_panel_coverage_qa.csv             composition QA
#   data/processed/state_panel_plausibility_flags.csv      value-credibility QA
#
# Idempotent: reads KEEP-OLD rows from the preserved pre-fix panel when it
# exists, so re-running does not fold already-fixed values back in.
#
# Usage: Rscript data_prep/rebuild_state_month_panel.R
# ============================================================================

suppressMessages({ library(tidyverse); library(lubridate); library(glue) })
theme_set(theme_minimal())

PANEL_PATH <- "data/raw/state_month_panel_with_treatment.csv"
DEPR_DIR   <- "data/raw/deprecated"
DEPR_PATH  <- file.path(DEPR_DIR,
  "state_month_panel_with_treatment_double_counted_2026-08-20.csv")
OUT_DIR    <- "data/processed"
dir.create(DEPR_DIR, showWarnings = FALSE, recursive = TRUE)

source("utils/eviction_treatment_schedule.R")

# ID added 2026-09-14. Idaho is no longer sourced from the county download: it
# now carries the statewide 44-county Idaho Judicial Branch A12 series
# (data_prep/add_id_to_state_panel.R). Leaving ID out of KEEP_OLD would rebuild
# it from the download's fixed basket -- silently reverting Idaho to Twin Falls
# County alone, with no error and no diff in the QA tables, exactly the failure
# mode documented for MD and the single-series six below.
#
# MI, WA, OR added 2026-09-14 -- BUG FIX, not a new feature. All three were
# added to the panel earlier the same day (add_mi_to_state_panel.R,
# add_wa_to_state_panel.R, add_oregon_to_state_panel.R) but never entered this
# list. None of the three has a single row in monthly_county_data_download.csv
# (verified: 0 rows for fips prefixes 26 / 53 / 41), so they could not arrive
# via county_part either -- `new <- bind_rows(county_part, keepold_part)` simply
# DROPPED them. Any run of this script deleted MI (68 rows),
# WA (113) and OR (103) from the panel silently: exit status 0, no invariant
# tripped, and the field-change QA reports rows_dropped only for states it still
# knows about. Confirmed empirically on 2026-09-14 (4,304 rows -> 4,020, three
# states gone); the panel was restored from backup and this list fixed.
#
# THE INVARIANT: every state whose series does not come from
# monthly_county_data_download.csv must appear here. Add the state to KEEP_OLD
# in the SAME commit as its add_*_to_state_panel.R script.
# ME added 2026-09-17. Maine is now a SPLICE: live LSC through 2023-05 plus the
# fiscal-year-corrected Maine Judicial Branch series from 2023-06
# (data_prep/add_me_to_state_panel.R). Without ME here the rebuild would take
# Maine from the county download alone and silently truncate it at 2023-05,
# dropping the corrected extension and ME's switcher status with it -- the same
# failure mode documented above for ID, MI, WA and OR.
KEEP_OLD <- c("NH", "WI", "MD", "LA", "MA", "MO", "NM", "NV", "RI", "ID",
              "MI", "WA", "OR", "ME")
NY_START <- as.Date("2019-01-01")

# ---- Basket policy (decision 2026-08-20: FIXED BASKET) ---------------------
# A county-sum state total is only comparable over time if the SAME counties
# are in it every month. BASKET_MODE="fixed" (default) restricts each state to
# the counties reporting in EVERY month of the basket window, then emits a
# state-month only when the whole basket reports. This trades counties for a
# well-defined estimand: FL drops Miami-Dade and Lee one month after its own
# treatment date, TN falls 36 -> 12 -> 3 counties, TX loses Harris (-48%
# denominator) — all pure composition, none of it eviction dynamics.
# BASKET_MODE="as_reported" reproduces the pre-decision behaviour.
# 2026-08-28: basket start is PER STATE (each state's own first reporting
# month), not the global BASKET_START — see the basket block below. Restores
# SC / NY / CO / HI, which the global 2016-01 start silently excluded.
BASKET_MODE  <- Sys.getenv("BASKET_MODE", "fixed")
BASKET_START <- as.Date(Sys.getenv("BASKET_START", "2016-01-01"))
BASKET_END   <- as.Date(Sys.getenv("BASKET_END",   "2024-12-01"))
BASKET_DROP  <- c(as.Date(Sys.getenv("BASKET_DROP_START", "2020-03-01")),
                  as.Date(Sys.getenv("BASKET_DROP_END",   "2021-07-31")))
MIN_BASKET_COUNTIES <- as.integer(Sys.getenv("MIN_BASKET_COUNTIES", "1"))
stopifnot(BASKET_MODE %in% c("fixed", "as_reported"))

fips_xwalk <- tibble(
  state_fips = c(1L,2L,4L,5L,6L,8L,9L,10L,11L,12L,13L,15L,16L,17L,18L,19L,20L,
                 21L,22L,23L,24L,25L,26L,27L,28L,29L,30L,31L,32L,33L,34L,35L,
                 36L,37L,38L,39L,40L,41L,42L,44L,45L,46L,47L,48L,49L,50L,51L,
                 53L,54L,55L,56L),
  state_abb  = c("AL","AK","AZ","AR","CA","CO","CT","DE","DC","FL","GA","HI",
                 "ID","IL","IN","IA","KS","KY","LA","ME","MD","MA","MI","MN",
                 "MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH",
                 "OK","OR","PA","RI","SC","SD","TN","TX","UT","VT","VA","WA",
                 "WV","WI","WY"))

# ---- Preserve the pre-fix panel ONCE; never overwrite it -------------------
if (!file.exists(DEPR_PATH)) {
  file.copy(PANEL_PATH, DEPR_PATH)
  message("Preserved pre-fix panel -> ", DEPR_PATH)
} else {
  message("Pre-fix panel already preserved; leaving ", DEPR_PATH, " untouched.")
}
# KEEP-OLD rows come from the CURRENT canonical panel when it exists.
#
# 2026-09-14 FIX. This previously read DEPR_PATH unconditionally, with the
# comment "KEEP-OLD rows always come from the PRE-FIX panel, so re-runs are
# idempotent." That held only while nothing else ever touched those 9 states.
# It stopped holding on 2026-09-03, when MD was extended to 2026-06, and again
# on 2026-09-14, when LA/MA/MO/NM/NV/RI were rebuilt from the Eviction Lab
# internal county extract. Re-running the script in either state would have
# SILENTLY REVERTED those repairs -- MD back to 2025-11, RI back to 2019-12 --
# with no error and no diff in the QA tables, because the reverted values are
# internally consistent.
#
# Reading the current panel keeps re-runs idempotent (the county-sourced 30 are
# rebuilt from the download either way) AND preserves every downstream repair.
# The 2026-08-20 archive stays the cold-build fallback.
keepold_src <- if (file.exists(PANEL_PATH)) PANEL_PATH else DEPR_PATH
message("KEEP-OLD rows sourced from: ", keepold_src)
old <- read_csv(keepold_src, show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date),
         treat_start = suppressWarnings(as.Date(treat_start)))
# Cold-build fallback lacks the basket columns added later; add them as NA so
# the KEEP-OLD select below is valid in both paths.
for (cc in c("n_counties", "basket_share", "panel_source"))
  if (!cc %in% names(old)) old[[cc]] <- NA

cty <- read_csv("data/raw/monthly_county_data_download.csv",
                show_col_types = FALSE,
                col_types = cols(fips = col_character())) %>%
  mutate(month_date = floor_date(as.Date(date), "month"),
         state_fips = as.integer(fips) %/% 1000L) %>%
  inner_join(fips_xwalk, by = "state_fips") %>%
  filter(!is.na(filings_count))

# `percent_of_historical_average` is LSC's OWN plausibility measure and it is
# the only signal that separates a collection failure from low evictions: the
# basket-completeness guard below checks that every basket county REPORTS, not
# that what it reports is credible. UT 2023-11/12 passed every structural check
# (all 6 basket counties present, basket_share 1.00) while reading 9% and 16%
# of historical average statewide -- see VALUE_CENSOR. Dropping this column at
# ingest, as every build before 2026-09-17 did, discards the evidence.
# `.fil_for_pct` is precomputed per ROW rather than derived inside summarise():
# summarise() masks sequentially, so an expression referring to filings_count
# after `filings_count = sum(filings_count)` sees the scalar aggregate, not the
# column. That silently reduced coverage to 209 of 4,301 rows on first write.
cty <- cty %>%
  mutate(.hist_avg = if_else(is.finite(percent_of_historical_average) &
                               percent_of_historical_average > 0,
                             filings_count / (percent_of_historical_average / 100),
                             NA_real_),
         .fil_for_pct = if_else(is.na(.hist_avg), NA_real_,
                                as.numeric(filings_count)))

# ---- Fixed basket: counties reporting in EVERY basket-window month --------
# PER-STATE BASKET START (2026-08-28). The 2026-08-20 rule counted required
# months from the GLOBAL BASKET_START, so any state whose county series begins
# after 2016-01 had an empty basket and vanished from the panel entirely —
# silently excluding SC (series from 2018-08), NY and CO (2019-01), HI
# (2020-01). The required-month set is now per state: the calendar months the
# STATE reports at all (>=1 county), inside [BASKET_START, BASKET_END] and
# outside BASKET_DROP. A county must report in every one of those months to
# enter its state's basket; a statewide gap month is a missing panel row, not
# grounds for emptying the basket. Within-state fixedness is unchanged and
# still asserted below.
basket_window <- cty %>%
  filter(month_date >= BASKET_START, month_date <= BASKET_END,
         !(month_date >= BASKET_DROP[1] & month_date <= BASKET_DROP[2]))

state_months <- basket_window %>%
  distinct(state_abb, month_date) %>%
  count(state_abb, name = "n_state_months")

basket <- basket_window %>%
  count(state_abb, fips, name = "n_obs") %>%
  inner_join(state_months, by = "state_abb") %>%
  filter(n_obs == n_state_months) %>%
  select(state_abb, fips)

basket_size <- basket %>% count(state_abb, name = "basket_n")

if (identical(BASKET_MODE, "fixed")) {
  cty <- cty %>% semi_join(basket, by = c("state_abb", "fips")) %>%
    semi_join(basket_size %>% filter(basket_n >= MIN_BASKET_COUNTIES),
              by = "state_abb")
}

cty_state <- cty %>% group_by(state_abb, month_date) %>%
  summarise(filings_count = sum(filings_count),
            renter_occupied_housing_units =
              sum(renter_occupied_housing_units, na.rm = TRUE),
            n_counties = n_distinct(fips),
            # State-level percent of historical average: filings over the summed
            # county historical averages, NOT a mean of county percentages (which
            # would weight a 1-filing county like Salt Lake).
            lsc_pct_of_hist_avg =
              if (all(is.na(.hist_avg))) NA_real_ else
                round(100 * sum(.fil_for_pct, na.rm = TRUE) /
                        sum(.hist_avg, na.rm = TRUE), 1),
            # Share of the basket the measure actually covers, so a percentage
            # resting on two of eighteen counties is not read as statewide.
            lsc_pct_coverage =
              round(sum(!is.na(.hist_avg)) / n_distinct(fips), 3),
            .groups = "drop")

if (identical(BASKET_MODE, "fixed")) {
  # Emit a state-month ONLY when the entire fixed basket reports; a partial
  # basket is exactly the artifact this mode exists to remove.
  cty_state <- cty_state %>% inner_join(basket_size, by = "state_abb") %>%
    filter(n_counties == basket_n) %>% select(-basket_n)
}

# Composition context: modal monthly basket size per state.
modal_basket <- cty_state %>% group_by(state_abb) %>%
  summarise(modal_n = as.numeric(names(sort(table(n_counties),
                                            decreasing = TRUE))[1]),
            max_n = max(n_counties), .groups = "drop")

county_part <- cty_state %>%
  filter(!state_abb %in% KEEP_OLD) %>%
  filter(!(state_abb == "NY" & month_date < NY_START)) %>%
  left_join(modal_basket, by = "state_abb") %>%
  mutate(basket_share = round(n_counties / modal_n, 3),
         panel_source = if (identical(BASKET_MODE, "fixed"))
                          "county_download_fixed_basket" else
                          "county_download_sum") %>%
  select(-modal_n, -max_n)

# 2026-09-14: the 6 former "single series" states (LA MA MO NM NV RI) were
# rebuilt from the Eviction Lab internal county extract by
# data_prep/rebuild_single_series_from_ets_internal.R. They now carry a real
# county basket, so their panel_source / n_counties / basket_share must be
# CARRIED THROUGH, not re-stamped. Re-stamping them (the pre-2026-09-14
# behavior) silently wiped the THIN-BASKET metadata that flags MO (0.34) and
# NM (0.48) as non-statewide -- the exact safety information a reader needs
# before quoting their levels.
keepold_part <- old %>%
  filter(state_abb %in% KEEP_OLD) %>%
  select(state_abb, month_date, filings_count,
         renter_occupied_housing_units, n_counties, basket_share, panel_source) %>%
  # Not LSC-sourced, so LSC's plausibility measure does not exist for these.
  mutate(lsc_pct_of_hist_avg = NA_real_, lsc_pct_coverage = NA_real_) %>%
  mutate(panel_source = case_when(
           state_abb == "NH" ~ "nh_court_source_repair_2026-07-23",
           state_abb == "WI" ~ "wi_court_source_repair_2026-07-23",
           state_abb == "MD" ~ "md_judiciary_lt_complaint_filings",
           # preserve whatever the rebuilt series declared
           TRUE              ~ panel_source),
         n_counties   = if_else(state_abb %in% c("NH","WI","MD"), NA_integer_,
                                as.integer(n_counties)),
         basket_share = if_else(state_abb %in% c("NH","WI","MD"), NA_real_,
                                as.numeric(basket_share)))

sched <- load_eviction_treatment_schedule(
  "data/raw/sports_gambling_legalization_dates.csv", "online_start_date")

new <- bind_rows(county_part, keepold_part) %>%
  left_join(sched %>% select(state_abb, treat_start), by = "state_abb") %>%
  mutate(
    # A missing or zero denominator yields a MISSING rate. Never substitute 1:
    # that fabricated finite rates up to 6.9 million per 1k renters in the
    # 2026-08-20 first cut (404 rows across LA MA MO NM NV RI).
    renter_occupied_housing_units =
      if_else(is.na(renter_occupied_housing_units) |
              renter_occupied_housing_units <= 0,
              NA_real_, as.numeric(renter_occupied_housing_units)),
    filings_per_1k_renters =
      if_else(is.na(renter_occupied_housing_units), NA_real_,
              filings_count / renter_occupied_housing_units * 1000),
    treated = !is.na(treat_start) & month_date >= treat_start) %>%
  select(state_abb, month_date, filings_count,
         renter_occupied_housing_units, filings_per_1k_renters,
         treat_start, treated, panel_source, n_counties, basket_share,
         lsc_pct_of_hist_avg, lsc_pct_coverage) %>%
  arrange(state_abb, month_date)

# ---- THE PANEL IS A HYBRID: relabel the rows the county file does not own ---
# monthly_county_data_download.csv is NOT a pristine LSC download. It is a
# hybrid: court-source series were merged into it, so rows that arrive through
# county_part carry `county_download_fixed_basket` whether or not LSC ever
# published them (DATA_PROVENANCE.md §1 correction, 2026-09-14). Two states are
# affected, and the wrong label has now caused the same misreading twice --
# most recently 2026-09-17, when a fresh LSC pull was read as a RETRACTION of
# NC rather than as the absence of rows LSC never had.
#   NC 2023-07 -> : NC AOC Summary Ejectment (09a_/09b_/09c_). LSC's NC stops 2023-06.
#   (ME was here until 2026-09-17; it is now a KEEP_OLD splice instead.)
# Re-downloading the county file DELETES these rows. It is destructive, not a
# refresh. Both states are switchers under the inclusion rule, and NC's entire
# outcome window (2025-03..2026-03) lives in the locally-added range.
# ME is no longer listed: since 2026-09-17 it is a KEEP_OLD splice carrying its
# own panel_source (LSC through 2023-05, me_jb_fed_fyfixed_2026-09-17 after).
HYBRID_SOURCE <- tribble(
  ~state_abb, ~from,                  ~label,
  "NC",       as.Date("2023-07-01"),  "nc_aoc_summary_ejectment")
for (i in seq_len(nrow(HYBRID_SOURCE))) {
  hit <- new$state_abb == HYBRID_SOURCE$state_abb[i] &
    new$month_date >= HYBRID_SOURCE$from[i]
  new$panel_source[hit]        <- HYBRID_SOURCE$label[i]
  new$lsc_pct_of_hist_avg[hit] <- NA_real_   # not an LSC series; no LSC measure
  new$lsc_pct_coverage[hit]    <- NA_real_
  message(glue("Hybrid source relabelled: {HYBRID_SOURCE$state_abb[i]} ",
               "{sum(hit)} row(s) -> {HYBRID_SOURCE$label[i]}"))
}

# Series-start ramp censor, re-applied on every rebuild. county_part is rebuilt
# from the raw download, so the months that data_prep/censor_series_start_ramps.R
# removed come straight back unless they are dropped here too. Confirmed
# 2026-09-14 15:17: a re-run of this script after the Idaho swap restored
# CT 2016-01 and 2016-02 (4,304 -> 4,306 rows) with exit status 0 and no QA
# flag; caught and re-censored 2026-09-16. Keep this list identical to CENSOR
# in censor_series_start_ramps.R. NH 2018-12 is listed for symmetry -- NH is in
# KEEP_OLD, so it never re-enters via county_part.
RAMP_CENSOR <- tibble(
  state_abb  = c("CT", "CT", "NH"),
  month_date = as.Date(c("2016-01-01", "2016-02-01", "2018-12-01")))
n_ramp <- nrow(semi_join(new, RAMP_CENSOR, by = c("state_abb", "month_date")))
new <- anti_join(new, RAMP_CENSOR, by = c("state_abb", "month_date"))
message(glue("Series-start ramp censor re-applied: {n_ramp} row(s) removed."))

# ---- VALUE CENSOR: months that REPORT but do not MEASURE -------------------
# Added 2026-09-17. The ramp censor above removes series-start artifacts and
# the basket rule removes composition artifacts. Neither catches a month where
# every basket county is present and every one of them reports a collapsed
# count -- a collection failure inside an otherwise healthy series. Both cases
# below are confirmed against the live LSC download (a 2026-09-17 pull is
# identical to the local file on these months, so they are upstream, not an
# ingest bug) and at county level.
#
#   UT 2023-11, 2023-12. Every Utah county collapses in the same two months and
#     every one recovers: Salt Lake 413 -> 24 -> 47 -> 432, reporting counties
#     18 -> 9 -> 7 -> 20. Statewide 9.1% and 16.2% of historical average, with
#     the flanking months at 115% and 111%. No eviction process does this.
#     Consequence if left in: these two months sit inside NC's inclusion-rule
#     baseline [2023-09, 2024-02], and UT is one of only five clean controls at
#     that calendar position -- they inflated NC's placebo long-difference SD
#     from 0.054 to 0.329 and the design's pooled SE by 13%
#     (analysis/diagnostics/covid_window_variance_profile.R).
#   CO 2023-11. CO's series ENDS here at 12.7% of historical average: an
#     uncensored trailing partial. DATA_PROVENANCE.md records CO as stale at
#     2023-11 but not that its final month is a fragment, so no rule caught it.
#     The 2026-09-14 trailing-partial censor covered LA/MA/MO/NM only.
VALUE_CENSOR <- tibble(
  state_abb  = c("UT", "UT", "CO"),
  month_date = as.Date(c("2023-11-01", "2023-12-01", "2023-11-01")))
n_val <- nrow(semi_join(new, VALUE_CENSOR, by = c("state_abb", "month_date")))
new <- anti_join(new, VALUE_CENSOR, by = c("state_abb", "month_date"))
message(glue("Value censor applied: {n_val} row(s) removed (UT 2023-11/12, CO 2023-11)."))

# ---- Plausibility band censor (decision 2026-09-17) ------------------------
# LSC's own `percent_of_historical_average` is the only signal that separates a
# collection failure from low evictions; the basket rule checks that counties
# REPORT, never that what they report is credible.
#
# TWO BANDS, because terminal months are empirically the worse offenders. Of the
# 27 LSC-sourced states, the final month is the one that misbehaves: AR 194.1,
# MN 159.3, ND 154.6, TX 145.4, AZ 143.6, CT 62.9, OH 45.0, DE 44.1 — against a
# median final-month reading of 95.4 and an all-month median of 98.3. A series
# end is a fragment (a court stops reporting mid-month) or a dump (a backlog
# clears), and it fails in BOTH directions, which a one-sided floor cannot see.
#   INTERIOR month: 50-150%   (loose)
#   TERMINAL month: 70-130%   (tight)
#
# THE BANDS APPLY RELATIVE TO THE STATE'S OWN LOCAL LEVEL, not to the raw LSC
# percentage. `percent_of_historical_average` compares a month to a FIXED
# historical baseline, so a state whose filing level has genuinely shifted sits
# persistently outside any absolute band: post-2021 median readings run AR 171,
# ND 153, TX 132, DE 66, VA 82. Applying 50-150 to the raw percentage deleted
# AR's entire post-2022 series (43 months, a switcher's whole outcome window)
# and six consecutive DE months -- level offsets, not failures. What UT 2023-11,
# OH 2025-06 and MN 2025-09 have in common is a LOCAL discontinuity: a month far
# from its OWN neighbours. `lsc_rel_to_local` divides each month's reading by a
# leave-one-out centred median of the same state's nearby non-COVID months, so
# the level offset divides out and only the break survives.
#
# Applied ITERATIVELY: censoring a terminal month promotes the month before it to
# terminal, and a degrading tail degrades over several months (AZ runs 7). The
# loop stops when nothing fails, and every removal is written to the QA file.
#
# The COVID era is exempt: filings genuinely were a fraction of normal under the
# moratoria, and the panel carries those months for specs that use covid="keep".
# A month whose LSC measure covers less than half the basket is also exempt --
# a percentage resting on two of eighteen counties is not a statewide reading.
PLAUS_WINDOW   <- 6L    # +/- months in the local-level median
PLAUS_MIN_NEI  <- 5L    # rolling neighbours required before a month can be judged
PLAUS_MIN_YEARS<- 3L    # other years of the same calendar month for a seasonal baseline
# BREADTH-AWARE BANDS (2026-09-17, second decision). A single band ignores how
# noisy a series structurally is. Per-state robust dispersion of the relative
# measure runs from 4.1 (PA, 58 counties) to 17.0 (MS, ONE county) -- a 4x
# spread -- so a fixed +/-50 band is ~3 state-sigmas in Mississippi and ~12 in
# Pennsylvania. Eight of the ten months the fixed band removed were thin-basket
# states, where a large deviation is expected rather than evidence of failure.
# The band is now K state-sigmas, robust-scaled:
#   interior K = 7.0, terminal K = 4.2
# calibrated so that AT MEDIAN DISPERSION (s = 7.2) they reproduce Ben's
# original bands almost exactly: 7.0 x 7.2 = +/-50 -> 50-150%, and
# 4.2 x 7.2 = +/-30 -> 70-130%. A thin series gets a proportionally wider band;
# a broad, well-behaved series like MN (s = 7.45) gets held to its own spread.
PLAUS_K_INTERIOR <- as.numeric(Sys.getenv("PLAUS_K_INTERIOR", "7.0"))
PLAUS_K_TERMINAL <- as.numeric(Sys.getenv("PLAUS_K_TERMINAL", "4.2"))
PLAUS_S_MIN      <- 4      # floor: never band a state tighter than the tightest observed
PLAUS_S_MAX      <- 15     # ceiling: a pathological series does not earn an unlimited band
PLAUS_S_MIN_OBS  <- 24L    # months required before a state gets its OWN dispersion
# The exemption runs to 2022-06, not 2021-12. The moratorium UNWIND is not over
# when the moratoria end: with the window closing 2021-12 the breadth-aware band
# flagged CT 2022-01/02, TX 2022-01/03, VA 2022-01/02/05, NY 2022-01, GA 2022-02,
# MN 2022-01/02 and NC 2022-01 -- eleven states moving together in one direction
# in the same two quarters, which is a recovery, not eleven simultaneous
# collection failures. The repo's own older specs used a 2022-03 COVID boundary
# for the same reason (CLAUDE.md, COVID drop window).
PLAUS_COVID    <- as.Date(c("2020-03-01", "2022-06-30"))
PLAUS_MIN_COV  <- 0.5
stopifnot(PLAUS_K_INTERIOR > PLAUS_K_TERMINAL, PLAUS_K_TERMINAL > 0,
          PLAUS_S_MIN < PLAUS_S_MAX)


# Expected reading for each state-month = a LOCAL level times a SEASONAL factor,
# both estimated leave-one-out from the state's own history with COVID months
# excluded. Each half is there because the other alone fails:
#   * Rolling level ALONE flagged NY every July for four straight years
#     (relative readings 192/177/194/218). NY simply files far more in July.
#   * Same-month-across-all-years ALONE flagged AR's entire series in both
#     directions: AR's level shifts around 2022 (median reading ~80 before,
#     ~170 after), so pooling Marches across the break makes every month look
#     anomalous. A level shift is not a failure either.
# Level handles the shift, factor handles the season, and what survives both is
# a genuine local discontinuity -- which is what UT 2023-11, OH 2025-06 and
# MN 2025-09 are. Months too sparse to judge get NA and are NEVER censored.
.local_level <- function(df) {
  df <- df %>% arrange(state_abb, month_date) %>%
    mutate(.moy = month(month_date),
           .ref = if_else(month_date >= PLAUS_COVID[1] & month_date <= PLAUS_COVID[2],
                          NA_real_, lsc_pct_of_hist_avg))
  loo_med <- function(v, k, min_n) {
    nb <- v[-k]; nb <- nb[!is.na(nb)]
    if (length(nb) < min_n) NA_real_ else median(nb)
  }
  # (1) local level: centred rolling leave-one-out median
  df <- df %>% group_by(state_abb) %>%
    mutate(.roll = vapply(seq_along(.ref), function(k) {
             lo <- max(1L, k - PLAUS_WINDOW); hi <- min(length(.ref), k + PLAUS_WINDOW)
             loo_med(.ref[lo:hi], k - lo + 1L, PLAUS_MIN_NEI)
           }, numeric(1)),
           .ratio = if_else(is.na(.roll) | .roll <= 0, NA_real_, .ref / .roll)) %>%
    # (2) seasonal factor: this calendar month's typical ratio in OTHER years
    group_by(state_abb, .moy) %>%
    mutate(.seasf = vapply(seq_along(.ratio),
                           function(k) loo_med(.ratio, k, PLAUS_MIN_YEARS), numeric(1))) %>%
    ungroup() %>%
    mutate(.seasf = coalesce(.seasf, 1),
           lsc_local_level = if_else(is.na(.roll), NA_real_, .roll * .seasf),
           lsc_level_basis = case_when(is.na(.roll)                ~ NA_character_,
                                       abs(.seasf - 1) < 1e-9      ~ "level",
                                       TRUE                        ~ "level x season"),
           lsc_rel_to_local = if_else(is.na(lsc_local_level) | lsc_local_level <= 0,
                                      NA_real_,
                                      round(100 * lsc_pct_of_hist_avg / lsc_local_level, 1))) %>%
    select(-.moy, -.ref, -.roll, -.ratio, -.seasf)
  df
}

# Per-state dispersion, computed ONCE on the uncensored panel: recomputing it
# inside the loop would shrink s as outliers are removed and the rule would
# ratchet. States with too little history fall back to the pooled median.
.s0 <- .local_level(new) %>%
  filter(!is.na(lsc_rel_to_local),
         month_date < PLAUS_COVID[1] | month_date > PLAUS_COVID[2]) %>%
  group_by(state_abb) %>%
  summarise(n_rel = n(), s_raw = IQR(lsc_rel_to_local) / 1.349, .groups = "drop")
.s_pool <- median(.s0$s_raw[.s0$n_rel >= PLAUS_S_MIN_OBS], na.rm = TRUE)
state_scale <- .s0 %>%
  mutate(s_state = if_else(n_rel >= PLAUS_S_MIN_OBS & is.finite(s_raw), s_raw, .s_pool),
         s_state = pmin(pmax(s_state, PLAUS_S_MIN), PLAUS_S_MAX))
message(glue("Breadth-aware scale: pooled s = {round(.s_pool, 2)}; ",
             "per-state s spans {round(min(state_scale$s_state), 2)}-",
             "{round(max(state_scale$s_state), 2)} across {nrow(state_scale)} states."))

band_removed <- new[0, c("state_abb", "month_date", "filings_count",
                         "lsc_pct_of_hist_avg")] %>%
  mutate(lsc_rel_to_local = numeric(0), s_state = numeric(0), z = numeric(0),
         band = character(0), lsc_level_basis = character(0),
         position = character(0), pass = integer(0))

for (pass_i in 1:24) {
  terminal <- new %>% group_by(state_abb) %>%
    summarise(last_m = max(month_date), .groups = "drop")
  cand <- .local_level(new) %>% left_join(terminal, by = "state_abb") %>%
    left_join(state_scale %>% select(state_abb, s_state), by = "state_abb") %>%
    mutate(
      is_term = month_date == last_m,
      k   = if_else(is_term, PLAUS_K_TERMINAL, PLAUS_K_INTERIOR),
      lo  = 100 - k * s_state,
      hi  = 100 + k * s_state,
      z   = round((lsc_rel_to_local - 100) / s_state, 2),
      fails = !is.na(lsc_rel_to_local) & !is.na(s_state) &
        (is.na(lsc_pct_coverage) | lsc_pct_coverage >= PLAUS_MIN_COV) &
        !(month_date >= PLAUS_COVID[1] & month_date <= PLAUS_COVID[2]) &
        (lsc_rel_to_local < lo | lsc_rel_to_local > hi))
  bad <- cand %>% filter(fails)
  if (nrow(bad) == 0L) break
  band_removed <- bind_rows(band_removed,
    bad %>% transmute(state_abb, month_date, filings_count, lsc_pct_of_hist_avg,
                      lsc_rel_to_local, s_state = round(s_state, 2), z,
                      band = paste0(round(lo), "-", round(hi), "%"), lsc_level_basis,
                      position = if_else(is_term, "terminal", "interior"),
                      pass = pass_i))
  new <- anti_join(new, bad %>% select(state_abb, month_date),
                   by = c("state_abb", "month_date"))
}
band_removed <- band_removed %>% arrange(state_abb, month_date)
write_csv(band_removed, file.path(OUT_DIR, "state_panel_plausibility_censor.csv"))
message(glue("Plausibility band censor: {nrow(band_removed)} row(s) removed ",
             "across {n_distinct(band_removed$state_abb)} state(s) in ",
             "{max(c(0L, band_removed$pass))} pass(es) ",
             "[interior {PLAUS_K_INTERIOR} x s, terminal {PLAUS_K_TERMINAL} x s]."))
if (nrow(band_removed) > 0) print(as.data.frame(band_removed))

# What survives but sits near a band edge -- surfaced, never censored.
plaus <- .local_level(new) %>%
  left_join(new %>% group_by(state_abb) %>% summarise(last_m = max(month_date),
                                                      .groups = "drop"),
            by = "state_abb") %>%
  left_join(state_scale %>% select(state_abb, s_state), by = "state_abb") %>%
  filter(!is.na(lsc_pct_of_hist_avg),
         (is.na(lsc_pct_coverage) | lsc_pct_coverage >= PLAUS_MIN_COV),
         !(month_date >= PLAUS_COVID[1] & month_date <= PLAUS_COVID[2]),
         !is.na(lsc_rel_to_local), !is.na(s_state),
         abs(lsc_rel_to_local - 100) / s_state > 0.8 * PLAUS_K_TERMINAL) %>%
  transmute(state_abb, month_date, filings_count, lsc_pct_of_hist_avg,
            lsc_rel_to_local, s_state = round(s_state, 2),
            z = round((lsc_rel_to_local - 100) / s_state, 2),
            lsc_level_basis, lsc_pct_coverage, n_counties, basket_share,
            position = if_else(month_date == last_m, "terminal", "interior")) %>%
  arrange(z)
write_csv(plaus, file.path(OUT_DIR, "state_panel_plausibility_flags.csv"))
message(glue("Plausibility WATCH (surviving, near a band edge): {nrow(plaus)} row(s) -> ",
             "{file.path(OUT_DIR, 'state_panel_plausibility_flags.csv')}"))
if (nrow(plaus) > 0) print(as.data.frame(plaus))

if (identical(BASKET_MODE, "fixed")) {
  # The point of the mode: within a state the basket must never move.
  chk <- new %>% filter(grepl("fixed_basket", panel_source)) %>%
    group_by(state_abb) %>% summarise(k_n = n_distinct(n_counties),
                                      k_r = n_distinct(renter_occupied_housing_units),
                                      .groups = "drop")
  stopifnot("fixed basket is not fixed"        = max(chk$k_n) == 1,
            "fixed basket denominator moved"   = max(chk$k_r) == 1)
}

# ---- Invariants: fail loudly rather than print a summary after the fact ----
stopifnot(
  "duplicate state-month key"      = !anyDuplicated(new[c("state_abb","month_date")]),
  "negative or NA filings"         = all(is.finite(new$filings_count) & new$filings_count >= 0),
  "non-finite rate slipped in"     = all(is.na(new$filings_per_1k_renters) |
                                          is.finite(new$filings_per_1k_renters)),
  "implausible rate (>200/1k)"     = all(is.na(new$filings_per_1k_renters) |
                                          new$filings_per_1k_renters < 200),
  "denominator present but zero"   = all(is.na(new$renter_occupied_housing_units) |
                                          new$renter_occupied_housing_units > 0),
  "treat_start not state-constant" = new %>% group_by(state_abb) %>%
                                       summarise(k = n_distinct(treat_start)) %>%
                                       pull(k) %>% max() == 1)

# ---- Field-level change QA (not filings only) ------------------------------
fld <- full_join(
  old %>% select(state_abb, month_date, o_f = filings_count,
                 o_r = renter_occupied_housing_units,
                 o_rate = filings_per_1k_renters, o_t = treat_start),
  new %>% select(state_abb, month_date, n_f = filings_count,
                 n_r = renter_occupied_housing_units,
                 n_rate = filings_per_1k_renters, n_t = treat_start,
                 panel_source),
  by = c("state_abb", "month_date"))

field_changes <- fld %>% group_by(state_abb) %>%
  summarise(rows_old = sum(!is.na(o_f)), rows_new = sum(!is.na(n_f)),
            rows_dropped = sum(!is.na(o_f) & is.na(n_f)),
            filings_changed = sum(!is.na(o_f) & !is.na(n_f) & abs(o_f - n_f) > 0.5),
            denom_changed  = sum(!is.na(o_r) & !is.na(n_r) & abs(o_r - n_r) > 0.5),
            rate_now_na    = sum(!is.na(o_rate) & is.na(n_rate)),
            treat_changed  = sum(!is.na(o_f) & !is.na(n_f) &
                                 !identical(o_t, n_t) & (is.na(o_t) != is.na(n_t) |
                                 (!is.na(o_t) & !is.na(n_t) & o_t != n_t))),
            source = first(na.omit(panel_source)), .groups = "drop") %>%
  arrange(desc(filings_changed))

# ---- Coverage / composition QA --------------------------------------------
coverage_qa <- county_part %>% group_by(state_abb) %>%
  summarise(basket_start = min(month_date),
            months = n(), min_n = min(n_counties), max_n = max(n_counties),
            median_n = median(n_counties),
            min_basket_share = min(basket_share),
            months_below_90pct = sum(basket_share < 0.90),
            last_full_month = suppressWarnings(max(month_date[basket_share >= 0.99])),
            .groups = "drop") %>%
  mutate(composition_risk = case_when(
    min_basket_share < 0.50 ~ "SEVERE - basket collapses; censor tail or fix basket",
    min_basket_share < 0.85 ~ "MODERATE - visible churn",
    TRUE ~ "ok")) %>%
  arrange(min_basket_share)

write_csv(new, PANEL_PATH)
write_csv(field_changes, file.path(OUT_DIR, "state_panel_rebuild_source_table.csv"))
write_csv(field_changes, file.path(OUT_DIR, "state_panel_rebuild_field_changes.csv"))
write_csv(coverage_qa,   file.path(OUT_DIR, "state_panel_coverage_qa.csv"))

cat(glue("\nRebuilt: {nrow(new)} rows, {n_distinct(new$state_abb)} states ",
         "(pre-fix: {nrow(old)} rows, {n_distinct(old$state_abb)}).\n",
         "Rates NA by design (no denominator): ",
         "{sum(is.na(new$filings_per_1k_renters))} rows.\n\n"))
cat("---- field-level changes vs pre-fix panel ----\n")
print(as.data.frame(field_changes %>% filter(filings_changed > 0 | rows_dropped > 0 |
                                             rate_now_na > 0)), digits = 3)
cat("\n---- composition risk (county-sourced states) ----\n")
print(as.data.frame(coverage_qa %>% filter(composition_risk != "ok")), digits = 3)
