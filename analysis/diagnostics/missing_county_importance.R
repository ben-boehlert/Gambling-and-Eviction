# =============================================================================
# missing_county_importance.R  (2026-09-16)
#
#   Rscript analysis/diagnostics/missing_county_importance.R
#
# Follow-on to missing_major_county_audit.R. That audit ranked missing
# counties (excluded-by-basket and absent-from-feed) by RENTER HOUSEHOLDS.
# This script answers the same "which missing counties matter" question in
# terms of EVICTION FILINGS and TIME:
#
#   Q1. Time structure of excluded-by-basket counties (present in the LSC
#       feed, dropped by the fixed-basket rule because they don't report
#       every basket-window month).
#   Q2. Filings importance of excluded AND absent counties, benchmarked
#       against the annual court-issued filings series.
#   Q3. Addability -- does the missing county show up in the Eviction Lab
#       internal county-month extract (ets_county_month.csv), or is its LSC
#       feed span nearly complete (so relaxing the basket rule would add it)?
#
# Basket reconstruction, fips crosswalk, and absent-from-feed logic are
# copied verbatim from missing_major_county_audit.R so state-level totals
# reproduce exactly (see verification block at the bottom of this file's
# console output).
# =============================================================================

suppressPackageStartupMessages({
  library(tidyverse); library(lubridate); library(glue); library(readxl)
})

BASKET_START <- as.Date("2016-01-01")
BASKET_END   <- as.Date("2024-12-01")
BASKET_DROP  <- c(as.Date("2020-03-01"), as.Date("2021-07-31"))
OUT_DIR      <- "data/processed"
LSC_RELAX_MAX_MISSING <- 12L  # "addable by relaxing the basket rule" threshold

# ---- state fips crosswalk (identical to missing_major_county_audit.R) ------
fips_xwalk <- tibble(state_abb = state.abb, state_name = state.name) %>%
  bind_rows(tibble(state_abb = "DC", state_name = "District of Columbia")) %>%
  mutate(state_fips = as.integer(c(
    1,2,4,5,6,8,9,10,12,13,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,
    31,32,33,34,35,36,37,38,39,40,41,42,44,45,46,47,48,49,50,51,53,54,55,56,11)))

cty <- read_csv("data/raw/monthly_county_data_download.csv",
                show_col_types = FALSE, col_types = cols(fips = col_character())) %>%
  mutate(fips       = str_pad(fips, 5, pad = "0"),
         month_date = floor_date(as.Date(date), "month"),
         state_fips = as.integer(fips) %/% 1000L) %>%
  inner_join(fips_xwalk, by = "state_fips") %>%
  filter(!is.na(filings_count))

# ---- reproduce the fixed basket exactly (rebuild_state_month_panel.R:150-166)
basket_window <- cty %>%
  filter(month_date >= BASKET_START, month_date <= BASKET_END,
         !(month_date >= BASKET_DROP[1] & month_date <= BASKET_DROP[2]))

state_months <- basket_window %>% distinct(state_abb, month_date) %>%
  count(state_abb, name = "n_state_months")

basket <- basket_window %>% count(state_abb, fips, name = "n_obs") %>%
  inner_join(state_months, by = "state_abb") %>%
  filter(n_obs == n_state_months) %>% select(state_abb, fips)

basket_counties_check <- basket %>% count(state_abb, name = "basket_counties")

# panel states = the states the prior audit reported (i.e. every state with
# at least one basket county, the panel's actual coverage universe)
panel_states <- sort(unique(basket$state_abb))

# all basket-window months (the "state reports in the basket window" calendar)
all_basket_months <- basket_window %>% distinct(month_date) %>% arrange(month_date) %>% pull(month_date)

cty_renters <- cty %>% group_by(state_abb, fips, name) %>%
  summarise(renters = max(renter_occupied_housing_units, na.rm = TRUE),
            months  = n(), .groups = "drop") %>%
  mutate(renters   = if_else(is.finite(renters), renters, NA_real_),
         in_basket = paste(state_abb, fips) %in% paste(basket$state_abb, basket$fips))

# ---- counties absent from the feed entirely (identical logic) --------------
adj <- read_lines("data/raw/county_adjacency_census.txt", locale = locale(encoding = "latin1"))
all_counties <- tibble(raw = adj) %>%
  separate(raw, into = c("name_a", "fips_a", "name_b", "fips_b"), sep = "\t",
           fill = "right", extra = "merge") %>%
  filter(!is.na(fips_a), str_detect(fips_a, "^\\s*\"?\\d{5}")) %>%
  transmute(fips = str_extract(fips_a, "\\d{5}"),
            county_name = str_remove_all(name_a, '"') %>% str_trim()) %>%
  filter(county_name != "") %>% distinct(fips, .keep_all = TRUE) %>%
  mutate(state_fips = as.integer(fips) %/% 1000L) %>%
  inner_join(fips_xwalk, by = "state_fips")

state_cov_states <- cty_renters %>% distinct(state_abb)
absent <- all_counties %>%
  anti_join(cty_renters %>% distinct(fips), by = "fips") %>%
  semi_join(state_cov_states, by = "state_abb") %>%
  filter(state_abb %in% panel_states)

# =============================================================================
# Q1. TIME STRUCTURE of counties excluded from the basket
# =============================================================================
excluded_counties <- cty_renters %>% filter(!in_basket, state_abb %in% panel_states) %>%
  select(state_abb, fips, name)

state_window_months <- basket_window %>% distinct(state_abb, month_date)

excluded_month_presence <- cty %>%
  semi_join(excluded_counties, by = c("state_abb", "fips")) %>%
  filter(month_date >= BASKET_START, month_date <= BASKET_END,
         !(month_date >= BASKET_DROP[1] & month_date <= BASKET_DROP[2])) %>%
  distinct(state_abb, fips, month_date)

# full state x county x basket-window-month grid, restricted to each
# county's own state's reporting calendar (state_window_months)
excluded_grid <- excluded_counties %>%
  inner_join(state_window_months, by = "state_abb", relationship = "many-to-many") %>%
  left_join(excluded_month_presence %>% mutate(present = TRUE),
            by = c("state_abb", "fips", "month_date")) %>%
  mutate(present = replace_na(present, FALSE))

gap_stats <- function(months_sorted, present_vec) {
  # months_sorted: ascending Date vector (the state's full basket-window
  # calendar); present_vec: logical, same length/order.
  n <- length(months_sorted)
  present_idx <- which(present_vec)
  missing_idx <- which(!present_vec)
  if (length(present_idx) == 0) {
    return(list(first_present = as.Date(NA), last_present = as.Date(NA),
                n_interior_gaps = NA_integer_, longest_gap = NA_integer_,
                classification = "never_present"))
  }
  first_i <- min(present_idx); last_i <- max(present_idx)
  interior_missing <- setdiff(missing_idx, c(seq_len(first_i - 1), seq(last_i + 1, n)))
  # count contiguous runs of interior missing months as "gaps"
  n_gaps <- 0L; longest <- 0L
  if (length(interior_missing) > 0) {
    runs <- split(interior_missing, cumsum(c(1, diff(interior_missing) != 1)))
    n_gaps <- length(runs)
    longest <- max(lengths(runs))
  }
  before_missing <- length(seq_len(first_i - 1))
  after_missing  <- length(missing_idx) - length(interior_missing) - before_missing
  # after_missing computed as: total missing - interior - before
  total_missing <- length(missing_idx)
  cls <- if (total_missing == 0) {
    "complete"
  } else if (before_missing == total_missing) {
    "late_start"
  } else if (after_missing == total_missing) {
    "trailing_dropout"
  } else if (before_missing == 0 && after_missing == 0) {
    "interior_only"
  } else {
    "mixed"
  }
  list(first_present = months_sorted[first_i], last_present = months_sorted[last_i],
       n_interior_gaps = n_gaps, longest_gap = longest, classification = cls)
}

excluded_time <- excluded_grid %>%
  arrange(state_abb, fips, month_date) %>%
  group_by(state_abb, fips, name) %>%
  group_modify(~{
    g <- gap_stats(.x$month_date, .x$present)
    tibble(months_in_window   = nrow(.x),
           months_present     = sum(.x$present),
           months_missing     = sum(!.x$present),
           first_present      = g$first_present,
           last_present        = g$last_present,
           n_interior_gaps    = g$n_interior_gaps,
           longest_gap        = g$longest_gap,
           classification     = g$classification)
  }) %>%
  ungroup() %>%
  mutate(size_bucket = case_when(
    months_missing <= 3  ~ "<=3",
    months_missing <= 12 ~ "4-12",
    months_missing <= 36 ~ "13-36",
    TRUE                 ~ ">36"
  ))

# total filings observed for the county in the feed, and its share of state
# feed filings over months where BOTH the county and the state are observed
county_filings <- cty %>% semi_join(excluded_counties, by = c("state_abb", "fips")) %>%
  group_by(state_abb, fips) %>%
  summarise(filings_total = sum(filings_count, na.rm = TRUE), .groups = "drop")

state_month_filings <- cty %>% filter(state_abb %in% panel_states) %>%
  group_by(state_abb, month_date) %>%
  summarise(state_month_filings = sum(filings_count, na.rm = TRUE), .groups = "drop")

county_state_overlap_share <- cty %>% semi_join(excluded_counties, by = c("state_abb", "fips")) %>%
  select(state_abb, fips, month_date, filings_count) %>%
  inner_join(state_month_filings, by = c("state_abb", "month_date")) %>%
  group_by(state_abb, fips) %>%
  summarise(filings_overlap        = sum(filings_count, na.rm = TRUE),
            state_filings_overlap  = sum(state_month_filings, na.rm = TRUE),
            .groups = "drop") %>%
  mutate(share_of_state_feed_filings = filings_overlap / state_filings_overlap)

missing_county_time_structure <- excluded_time %>%
  left_join(county_filings, by = c("state_abb", "fips")) %>%
  left_join(county_state_overlap_share %>% select(state_abb, fips, share_of_state_feed_filings),
            by = c("state_abb", "fips")) %>%
  arrange(state_abb, desc(filings_total))

write_csv(missing_county_time_structure, file.path(OUT_DIR, "missing_county_time_structure.csv"))

# =============================================================================
# Q2. FILINGS IMPORTANCE vs. the annual court benchmark
# =============================================================================
annual <- read_excel("data/raw/updated_county_issued_ANNUAL.xlsx", sheet = 1) %>%
  mutate(fips = str_pad(as.character(as.integer(fips_county)), 5, pad = "0"),
         state_name_clean = str_to_title(state))

state_name_map <- fips_xwalk %>% mutate(state_name_clean = str_to_title(state_name))
annual <- annual %>%
  left_join(state_name_map %>% select(state_abb, state_name_clean), by = "state_name_clean") %>%
  filter(!is.na(state_abb), state_abb %in% panel_states, !is.na(filings_observed))

# choose, per state, the latest year with any county coverage, preferring
# 2019 or 2022/2023 if the state has data in one of those years
state_year_avail <- annual %>% filter(filings_observed > 0 | !is.na(filings_observed)) %>%
  group_by(state_abb) %>% summarise(years_avail = list(sort(unique(year))), .groups = "drop")

pick_year <- function(years) {
  prefer <- c(2023, 2022, 2019)
  hit <- prefer[prefer %in% years]
  if (length(hit) > 0) return(hit[1])
  if (length(years) == 0) return(NA_integer_)
  max(years)
}

state_year_choice <- state_year_avail %>%
  rowwise() %>% mutate(bench_year = pick_year(years_avail)) %>% ungroup() %>%
  select(state_abb, bench_year)

annual_bench <- annual %>% inner_join(state_year_choice, by = "state_abb") %>%
  filter(year == bench_year)

county_status <- cty_renters %>% filter(state_abb %in% panel_states) %>%
  transmute(state_abb, fips,
            status = if_else(in_basket, "basket", "excluded")) %>%
  bind_rows(absent %>% transmute(state_abb, fips, status = "absent"))

annual_bench_status <- annual_bench %>%
  left_join(county_status, by = c("state_abb", "fips")) %>%
  mutate(status = replace_na(status, "unmatched"))

missing_county_filings_benchmark <- annual_bench_status %>%
  group_by(state_abb, bench_year) %>%
  summarise(state_total_filings = sum(filings_observed, na.rm = TRUE), .groups = "drop") %>%
  left_join(
    annual_bench_status %>% group_by(state_abb, status) %>%
      summarise(filings = sum(filings_observed, na.rm = TRUE), .groups = "drop") %>%
      pivot_wider(names_from = status, values_from = filings, values_fill = 0),
    by = "state_abb"
  ) %>%
  mutate(across(any_of(c("basket", "excluded", "absent", "unmatched")), ~replace_na(., 0))) %>%
  mutate(share_basket    = basket    / state_total_filings,
         share_excluded  = excluded  / state_total_filings,
         share_absent    = if ("absent" %in% names(.))  absent   / state_total_filings else 0,
         share_unmatched = if ("unmatched" %in% names(.)) unmatched / state_total_filings else 0) %>%
  arrange(state_abb)

states_with_no_benchmark <- panel_states[!panel_states %in% missing_county_filings_benchmark$state_abb]
if (length(states_with_no_benchmark) > 0) {
  missing_county_filings_benchmark <- bind_rows(
    missing_county_filings_benchmark,
    tibble(state_abb = states_with_no_benchmark, bench_year = NA_integer_,
           state_total_filings = NA_real_, note = "no benchmark rows for this state")
  ) %>% arrange(state_abb)
}

write_csv(missing_county_filings_benchmark, file.path(OUT_DIR, "missing_county_filings_benchmark.csv"))

# top-3 missing (excluded OR absent) counties per state by benchmark filings
missing_county_filings_top <- annual_bench_status %>%
  filter(status %in% c("excluded", "absent")) %>%
  group_by(state_abb) %>%
  slice_max(filings_observed, n = 3, with_ties = FALSE) %>%
  ungroup() %>%
  left_join(missing_county_filings_benchmark %>% select(state_abb, state_total_filings),
            by = "state_abb") %>%
  mutate(share_of_state = filings_observed / state_total_filings) %>%
  select(state_abb, county, fips, status, bench_year, filings_observed, share_of_state) %>%
  arrange(state_abb, desc(filings_observed))

write_csv(missing_county_filings_top, file.path(OUT_DIR, "missing_county_filings_top.csv"))

# =============================================================================
# Q3. ADDABILITY -- Eviction Lab extract coverage + LSC-relaxation candidates
# =============================================================================
ets <- read_csv("ets_county_month.csv", show_col_types = FALSE,
                col_types = cols(xcourtcofips = col_character())) %>%
  mutate(fips = str_pad(xcourtcofips, 5, pad = "0"),
         month_date = make_date(xfileyear, xfilemonth, 1))

ets_span <- ets %>% group_by(fips) %>%
  summarise(ets_months       = n_distinct(month_date),
            ets_first_month  = min(month_date),
            ets_last_month   = max(month_date),
            .groups = "drop")

missing_all <- bind_rows(
  excluded_counties %>% mutate(status = "excluded") %>% select(state_abb, fips, name, status),
  absent %>% transmute(state_abb, fips, name = county_name, status = "absent")
)

lsc_relax_candidates <- missing_county_time_structure %>%
  filter(months_missing <= LSC_RELAX_MAX_MISSING,
         classification == "trailing_dropout") %>%
  distinct(state_abb, fips) %>% mutate(addable_lsc_relax = TRUE)

missing_county_addability <- missing_all %>%
  left_join(ets_span, by = "fips") %>%
  left_join(lsc_relax_candidates, by = c("state_abb", "fips")) %>%
  mutate(addable_lsc_relax = replace_na(addable_lsc_relax, FALSE),
         addable_eviction_lab = !is.na(ets_months),
         addability = case_when(
           addable_lsc_relax   ~ "addable_via_lsc_relaxation",
           addable_eviction_lab ~ "addable_via_eviction_lab_extract",
           TRUE                 ~ "no_known_source"
         )) %>%
  arrange(state_abb, status, fips)

write_csv(missing_county_addability, file.path(OUT_DIR, "missing_county_addability.csv"))

addability_summary_by_state <- missing_county_addability %>%
  count(state_abb, addability) %>%
  pivot_wider(names_from = addability, values_from = n, values_fill = 0)

addability_summary_overall <- missing_county_addability %>% count(addability)

# =============================================================================
# VERIFICATION
# =============================================================================
cat("\n================ VERIFICATION ================\n")

prior_audit <- read_csv(file.path(OUT_DIR, "missing_major_county_audit.csv"), show_col_types = FALSE)
basket_check <- basket_counties_check %>%
  full_join(prior_audit %>% select(state_abb, basket_counties), by = "state_abb",
            suffix = c("_here", "_prior")) %>%
  mutate(basket_counties_here = replace_na(basket_counties_here, 0L),
         match = basket_counties_here == basket_counties_prior)
cat("(a) basket_counties reproduction: ",
    sum(basket_check$match, na.rm = TRUE), "/", nrow(basket_check),
    " states match prior audit exactly\n", sep = "")
if (any(!basket_check$match, na.rm = TRUE)) {
  cat("    MISMATCHES:\n"); print(basket_check %>% filter(!match))
}

cat("\n(b) FL/TX basket+excluded+absent+unmatched shares sum to 1:\n")
missing_county_filings_benchmark %>% filter(state_abb %in% c("FL", "TX")) %>%
  mutate(total_share = share_basket + share_excluded + share_absent + share_unmatched) %>%
  select(state_abb, bench_year, share_basket, share_excluded, share_absent,
         share_unmatched, total_share) %>%
  print()

cat("\n(c) Harris TX and Miami-Dade FL last-present-month spot check:\n")
missing_county_time_structure %>%
  filter((state_abb == "TX" & str_detect(name, "Harris")) |
         (state_abb == "FL" & str_detect(name, "Miami-Dade|Miami Dade"))) %>%
  select(state_abb, name, fips, first_present, last_present, classification, months_missing) %>%
  print()

# =============================================================================
# CONSOLE SUMMARY
# =============================================================================
cat("\n================ Q1: excluded-county time structure ================\n")
missing_county_time_structure %>% count(classification, size_bucket) %>%
  pivot_wider(names_from = size_bucket, values_from = n, values_fill = 0) %>% print()

cat("\nTop 10 excluded counties overall by feed filings total:\n")
missing_county_time_structure %>% arrange(desc(filings_total)) %>%
  select(state_abb, name, filings_total, months_missing, classification, share_of_state_feed_filings) %>%
  head(10) %>% print()

cat("\n================ Q2: filings share vs. annual benchmark ================\n")
missing_county_filings_benchmark %>%
  select(state_abb, bench_year, share_basket, share_excluded, share_absent, share_unmatched) %>%
  arrange(share_basket) %>% print(n = Inf)

cat("\n================ Q3: addability ================\n")
cat("\nOverall:\n"); print(addability_summary_overall)
cat("\nBy state:\n"); print(addability_summary_by_state, n = Inf)

cat("\nWrote:\n",
    file.path(OUT_DIR, "missing_county_time_structure.csv"), "\n",
    file.path(OUT_DIR, "missing_county_filings_benchmark.csv"), "\n",
    file.path(OUT_DIR, "missing_county_filings_top.csv"), "\n",
    file.path(OUT_DIR, "missing_county_addability.csv"), "\n", sep = "")
