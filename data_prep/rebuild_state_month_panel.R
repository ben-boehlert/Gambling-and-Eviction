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
# REBUILD RULES (one consistent source per state):
#   COUNTY   sum of monthly_county_data_download.csv, for every state in the
#            download except NH and WI.
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

KEEP_OLD <- c("NH", "WI", "MD", "LA", "MA", "MO", "NM", "NV", "RI")
NY_START <- as.Date("2019-01-01")

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
# KEEP-OLD rows always come from the PRE-FIX panel, so re-runs are idempotent.
old <- read_csv(DEPR_PATH, show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date),
         treat_start = suppressWarnings(as.Date(treat_start)))

cty <- read_csv("data/raw/monthly_county_data_download.csv",
                show_col_types = FALSE,
                col_types = cols(fips = col_character())) %>%
  mutate(month_date = floor_date(as.Date(date), "month"),
         state_fips = as.integer(fips) %/% 1000L) %>%
  inner_join(fips_xwalk, by = "state_fips") %>%
  filter(!is.na(filings_count))

cty_state <- cty %>% group_by(state_abb, month_date) %>%
  summarise(filings_count = sum(filings_count),
            renter_occupied_housing_units =
              sum(renter_occupied_housing_units, na.rm = TRUE),
            n_counties = n_distinct(fips), .groups = "drop")

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
         panel_source = "county_download_sum") %>%
  select(-modal_n, -max_n)

keepold_part <- old %>%
  filter(state_abb %in% KEEP_OLD) %>%
  select(state_abb, month_date, filings_count,
         renter_occupied_housing_units) %>%
  mutate(n_counties = NA_integer_, basket_share = NA_real_,
         panel_source = case_when(
           state_abb == "NH" ~ "nh_court_source_repair_2026-07-23",
           state_abb == "WI" ~ "wi_court_source_repair_2026-07-23",
           state_abb == "MD" ~ "md_judiciary_lt_complaint_filings",
           TRUE              ~ "ets_single_series_no_denominator"))

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
         treat_start, treated, panel_source, n_counties, basket_share) %>%
  arrange(state_abb, month_date)

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
  summarise(months = n(), min_n = min(n_counties), max_n = max(n_counties),
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
