#!/usr/bin/env Rscript
# ============================================================================
# rebuild_state_month_panel.R
#
# Rebuild data/raw/state_month_panel_with_treatment.csv WITHOUT the ETS
# double count diagnosed 2026-08-20 (see
# analysis/diagnostics/statepanel_double_count_audit.R).
#
# The old panel (no construction script survives) was, for 12 states,
#   filings_count = sum(monthly_county_data_download.csv counties)
#                 + merged_ets_combined.csv location series
# with the two sources covering the SAME filings — an exact double count
# whose on/off dates (2020-01 for cities series, 2023-02 / 2020-01 for
# state_level series) created 1.2x–2.4x mid-panel level breaks in
# AZ CT DE FL IN MN OH PA SC TN TX VA.
#
# Rebuild rules (one consistent source per state):
#   1. COUNTY   — sum of monthly_county_data_download.csv (filings & renters).
#                 Used for every state present in the download EXCEPT NH, WI.
#   2. KEEP-OLD — rows carried from the old panel where it is single-source
#                 and better than the download:
#                   NH  court-source repair (06_repair_nh_from_court_source.R;
#                       download has the 2023H2 zero-fill artifact, ends 2023)
#                   WI  court-source repair (08c; download is 2021-2024 only,
#                       partial baskets, ragged 2024 tail)
#                   MD  Socrata warrant petitions (07_merge_md_into_panel.R)
#                   LA MA MO NM NV RI  ETS-only series (no county rows exist;
#                       never double counted)
#   3. NY       — county sums 2019-01+ ONLY. The old panel's 2016-2018 block
#                 is a different-basket ETS series (seam at 2019-01); dropped.
#
# Treatment columns are recomputed from the REPAIRED legalization schedule
# (2026-08-10 repair: DE NC KY ME FL VT MO online dates added), so treat_start
# here differs from the old panel for those states by construction.
#
# Output:
#   data/raw/state_month_panel_with_treatment.csv        (canonical, replaced)
#   data/raw/deprecated/state_month_panel_with_treatment_double_counted_2026-08-20.csv
#   data/processed/state_panel_rebuild_source_table.csv  (per-state provenance)
#   data/processed/state_panel_rebuild_old_vs_new.csv    (per-state-month diff)
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

KEEP_OLD  <- c("NH", "WI", "MD", "LA", "MA", "MO", "NM", "NV", "RI")
NY_START  <- as.Date("2019-01-01")

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

old <- read_csv(PANEL_PATH, show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date),
         treat_start = suppressWarnings(as.Date(treat_start)))

cty_state <- read_csv("data/raw/monthly_county_data_download.csv",
                      show_col_types = FALSE) %>%
  mutate(month_date = floor_date(as.Date(date), "month"),
         state_fips = as.integer(fips) %/% 1000L) %>%
  inner_join(fips_xwalk, by = "state_fips") %>%
  filter(!is.na(filings_count)) %>%
  group_by(state_abb, month_date) %>%
  summarise(filings_count = sum(filings_count),
            renter_occupied_housing_units =
              sum(renter_occupied_housing_units, na.rm = TRUE),
            n_counties = n(), .groups = "drop")

county_part <- cty_state %>%
  filter(!state_abb %in% KEEP_OLD) %>%
  filter(!(state_abb == "NY" & month_date < NY_START)) %>%
  mutate(panel_source = "county_download_sum")

keepold_part <- old %>%
  filter(state_abb %in% KEEP_OLD) %>%
  select(state_abb, month_date, filings_count,
         renter_occupied_housing_units) %>%
  mutate(n_counties = NA_integer_,
         panel_source = case_when(
           state_abb == "NH" ~ "court_source_repair_2026-07-23",
           state_abb == "WI" ~ "court_source_repair_2026-07-23",
           state_abb == "MD" ~ "md_socrata_warrant_petitions",
           TRUE              ~ "ets_single_series"))

sched <- load_eviction_treatment_schedule(
  "data/raw/sports_gambling_legalization_dates.csv", "online_start_date")

new <- bind_rows(county_part, keepold_part) %>%
  left_join(sched %>% select(state_abb, treat_start), by = "state_abb") %>%
  mutate(filings_per_1k_renters =
           filings_count / pmax(renter_occupied_housing_units, 1) * 1000,
         treated = !is.na(treat_start) & month_date >= treat_start) %>%
  select(state_abb, month_date, filings_count,
         renter_occupied_housing_units, filings_per_1k_renters,
         treat_start, treated, panel_source, n_counties) %>%
  arrange(state_abb, month_date)

stopifnot(nrow(new) > 0,
          !anyDuplicated(new %>% select(state_abb, month_date)))

# ---- Old vs new comparison --------------------------------------------------
cmp <- full_join(
  old %>% select(state_abb, month_date, old_filings = filings_count),
  new %>% select(state_abb, month_date, new_filings = filings_count,
                 panel_source),
  by = c("state_abb", "month_date")) %>%
  mutate(diff = new_filings - old_filings)

cmp_state <- cmp %>% group_by(state_abb) %>%
  summarise(n_old = sum(!is.na(old_filings)), n_new = sum(!is.na(new_filings)),
            n_changed = sum(!is.na(diff) & abs(diff) > 0.5),
            median_new_over_old = median(new_filings / pmax(old_filings, 1),
                                         na.rm = TRUE),
            source = first(na.omit(panel_source)), .groups = "drop") %>%
  arrange(desc(n_changed))

# ---- Swap canonical (old copy preserved) ------------------------------------
file.copy(PANEL_PATH, DEPR_PATH, overwrite = TRUE)
write_csv(new, PANEL_PATH)
write_csv(cmp_state, file.path(OUT_DIR, "state_panel_rebuild_source_table.csv"))
write_csv(cmp %>% filter(!is.na(diff), abs(diff) > 0.5),
          file.path(OUT_DIR, "state_panel_rebuild_old_vs_new.csv"))

cat(glue("\nRebuilt panel: {nrow(new)} rows, ",
         "{n_distinct(new$state_abb)} states ",
         "(old: {nrow(old)} rows, {n_distinct(old$state_abb)}).\n",
         "Old panel preserved at {DEPR_PATH}\n\n"))
print(as.data.frame(cmp_state), digits = 3)
cat("\nStates with changed values are exactly the double-counted set",
    "(+ NY trim, + schedule-repair treat_start changes).\n")
