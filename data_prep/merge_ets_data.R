#!/usr/bin/env Rscript
################################################################################
# merge_ets_data.R
#
# Merges three ETS (Eviction Tracking System) data files:
#   1. historical_ets_data_monthly.csv (2012-2019, state+city level)
#   2. allstates_monthly_2020_2021 (3).csv (2020-2025, census tract level)
#   3. all_sites_monthly_2020_2021.csv (2020-2025, city level, duplicated)
#
# CRITICAL:
#   - States file is at census tract level (GEOID) - must aggregate to state
#   - Sites file has massive duplication - must collapse
#   - Historical file is already aggregated
#
# Output:
#   - merged_ets_states_monthly.csv (state-level panel 2012-2025)
#   - merged_ets_sites_monthly.csv (city-level panel 2012-2025)
################################################################################

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(glue)
})

set.seed(123)

cat("=== Merging ETS Data ===\n\n")

################################################################################
# 1. Read historical data (2012-2019)
################################################################################

cat("1. Reading historical_ets_data_monthly.csv...\n")

hist <- read_csv("historical_ets_data_monthly.csv", show_col_types = FALSE) %>%
  rename(
    location = xsite,
    year = xfileyear,
    month_num = xfilemonth,
    filings_count = N
  ) %>%
  mutate(
    # Create month_date (first of month)
    month_date = as.Date(paste(year, month_num, "01", sep = "-")),
    # Standardize location names to lowercase for matching
    location_std = str_to_lower(str_trim(location))
  )

cat(glue("  {nrow(hist)} rows, {n_distinct(hist$location)} locations, {min(hist$year)}-{max(hist$year)}\n"))

# Identify which are states vs cities
# US state names for matching
us_states <- c(
  "alabama", "alaska", "arizona", "arkansas", "california", "colorado",
  "connecticut", "delaware", "florida", "georgia", "hawaii", "idaho",
  "illinois", "indiana", "iowa", "kansas", "kentucky", "louisiana",
  "maine", "maryland", "massachusetts", "michigan", "minnesota",
  "mississippi", "missouri", "montana", "nebraska", "nevada",
  "newhampshire", "newjersey", "newmexico", "newyork", "northcarolina",
  "northdakota", "ohio", "oklahoma", "oregon", "pennsylvania",
  "rhodeisland", "southcarolina", "southdakota", "tennessee", "texas",
  "utah", "vermont", "virginia", "washington", "westvirginia",
  "wisconsin", "wyoming", "districtofcolumbia"
)

# Remove spaces/punctuation for matching
us_states_nospc <- str_replace_all(us_states, "[^a-z]", "")

hist <- hist %>%
  mutate(
    location_nospc = str_replace_all(location_std, "[^a-z]", ""),
    is_state = location_nospc %in% us_states_nospc
  )

cat(glue("  {sum(hist$is_state)} state observations\n"))
cat(glue("  {sum(!hist$is_state)} city observations\n"))

################################################################################
# 2. Read and AGGREGATE census tract data to state level (2020-2025)
################################################################################

cat("\n2. Reading allstates_monthly_2020_2021 (3).csv...\n")
cat("   (This file has census tract-level data - aggregating to state)\n")

# Check if the census tract file exists
tract_file <- "allstates_monthly_2020_2021 (3).csv"
if (!file.exists(tract_file)) {
  cat("   ⚠ Census tract file not found, trying allstates_monthly_2020_2021.csv instead\n")
  tract_file <- "allstates_monthly_2020_2021.csv"
}

states_2020_raw <- read_csv(tract_file, show_col_types = FALSE)
cat(glue("   Raw: {nrow(states_2020_raw)} rows\n"))

# Check if we have GEOID (census tract file) or just state-month (aggregate file)
if ("GEOID" %in% names(states_2020_raw)) {
  cat("   Census tract level detected - aggregating by state+month\n")

  states_2020 <- states_2020_raw %>%
    mutate(
      # Parse month: "01/2020" -> 2020-01-01
      month_date = parse_date_time(month, orders = "m/Y", quiet = TRUE) %>% floor_date("month") %>% as.Date(),
      location_std = str_to_lower(str_trim(state))
    ) %>%
    group_by(state, location_std, month_date) %>%
    summarise(
      # Sum filings across all census tracts
      filings_count = sum(filings_2020, na.rm = TRUE),
      # Average the avg (weighted by count would be better, but we'll use mean)
      filings_avg = mean(filings_avg, na.rm = TRUE),
      n_tracts = n(),
      .groups = "drop"
    ) %>%
    mutate(is_state = TRUE) %>%
    rename(location = state) %>%
    select(-n_tracts)

  cat(glue("   Aggregated: {nrow(states_2020)} state-month observations\n"))
  cat(glue("   {n_distinct(states_2020$location)} states\n"))

} else {
  cat("   Aggregate state-month file detected - collapsing duplicates\n")

  # This is the old file with duplication - collapse it
  states_2020 <- states_2020_raw %>%
    mutate(
      # Parse month: "Jan-20" -> 2020-01-01
      month_date = parse_date_time(month, orders = c("b-y", "b y"), quiet = TRUE) %>%
        floor_date("month") %>%
        as.Date(),
      location_std = str_to_lower(str_trim(state))
    ) %>%
    group_by(state, location_std, month_date) %>%
    summarise(
      filings_count = sum(filings_2020, na.rm = TRUE),
      filings_avg = sum(filings_avg, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(is_state = TRUE) %>%
    rename(location = state)

  cat(glue("   Collapsed: {nrow(states_2020)} state-month observations\n"))
  cat(glue("   {n_distinct(states_2020$location)} states\n"))
}

cat(glue("   Date range: {min(states_2020$month_date)} to {max(states_2020$month_date)}\n"))

################################################################################
# 3. Read and COLLAPSE sites 2020-2025 data (MASSIVE DUPLICATION)
################################################################################

cat("\n3. Reading all_sites_monthly_2020_2021.csv...\n")
cat("   (This file has massive duplication at city level)\n")

sites_2020_raw <- read_csv("all_sites_monthly_2020_2021.csv", show_col_types = FALSE)
cat(glue("   Raw: {nrow(sites_2020_raw)} rows\n"))

# Check if there's a GEOID column (tract-level detail)
if ("GEOID" %in% names(sites_2020_raw)) {
  cat("   Census tract level detected - aggregating by city+month\n")

  sites_2020 <- sites_2020_raw %>%
    mutate(
      month_date = parse_date_time(month, orders = "m/Y", quiet = TRUE) %>% floor_date("month") %>% as.Date(),
      location_std = str_to_lower(str_trim(city))
    ) %>%
    group_by(city, location_std, month_date) %>%
    summarise(
      filings_count = sum(filings_2020, na.rm = TRUE),
      filings_avg = mean(filings_avg, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(is_state = FALSE) %>%
    rename(location = city)

} else {
  cat("   City-month level with duplication - collapsing\n")

  # Collapse duplicates
  sites_2020 <- sites_2020_raw %>%
    mutate(
      # Parse month: "20-Jan" -> 2020-01-01
      month_date = parse_date_time(month, orders = c("y-b", "y b"), quiet = TRUE) %>%
        floor_date("month") %>%
        as.Date(),
      location_std = str_to_lower(str_trim(city))
    ) %>%
    group_by(city, location_std, month_date) %>%
    summarise(
      # Sum the filings across all duplicate rows
      filings_count = sum(filings_2020, na.rm = TRUE),
      filings_avg = sum(filings_avg, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(is_state = FALSE) %>%
    rename(location = city)
}

cat(glue("   Collapsed: {nrow(sites_2020)} rows, {n_distinct(sites_2020$location)} sites\n"))
cat(glue("   Date range: {min(sites_2020$month_date)} to {max(sites_2020$month_date)}\n"))

################################################################################
# 4. Merge states: historical + 2020-2025
################################################################################

cat("\n4. Merging state-level data...\n")

# Historical states (2012-2019)
hist_states <- hist %>%
  filter(is_state) %>%
  mutate(
    # Add filings_avg = NA for consistency (not available pre-2020)
    filings_avg = NA_real_
  ) %>%
  select(location, location_std, month_date, filings_count, filings_avg, is_state)

cat(glue("  Historical states: {nrow(hist_states)} rows, {n_distinct(hist_states$location)} states\n"))

# Combine with 2020-2025 states
states_merged <- bind_rows(
  hist_states,
  states_2020
) %>%
  arrange(location_std, month_date)

cat(glue("  Merged states: {nrow(states_merged)} rows, {n_distinct(states_merged$location_std)} unique states\n"))
cat(glue("  Date range: {min(states_merged$month_date)} to {max(states_merged$month_date)}\n"))

# Check for duplicates
dupes_states <- states_merged %>%
  group_by(location_std, month_date) %>%
  filter(n() > 1) %>%
  ungroup()

if (nrow(dupes_states) > 0) {
  cat("  ⚠ WARNING: Found duplicates, keeping first occurrence:\n")
  dupes_states %>%
    distinct(location_std, month_date) %>%
    slice_head(n = 5) %>%
    print()

  states_merged <- states_merged %>%
    group_by(location_std, month_date) %>%
    slice(1) %>%
    ungroup()
}

################################################################################
# 5. Merge sites: historical + 2020-2025
################################################################################

cat("\n5. Merging city-level data...\n")

# Historical cities (2012-2019)
hist_cities <- hist %>%
  filter(!is_state) %>%
  mutate(
    # Add filings_avg = NA for consistency
    filings_avg = NA_real_
  ) %>%
  select(location, location_std, month_date, filings_count, filings_avg, is_state)

cat(glue("  Historical cities: {nrow(hist_cities)} rows, {n_distinct(hist_cities$location)} cities\n"))

# Combine with 2020-2025 sites
sites_merged <- bind_rows(
  hist_cities,
  sites_2020
) %>%
  arrange(location_std, month_date)

cat(glue("  Merged sites: {nrow(sites_merged)} rows, {n_distinct(sites_merged$location_std)} unique sites\n"))
cat(glue("  Date range: {min(sites_merged$month_date)} to {max(sites_merged$month_date)}\n"))

# Check for duplicates (more likely for cities due to naming inconsistencies)
dupes_sites <- sites_merged %>%
  group_by(location_std, month_date) %>%
  filter(n() > 1) %>%
  ungroup()

if (nrow(dupes_sites) > 0) {
  cat("  ⚠ WARNING: Found duplicates, keeping first occurrence:\n")
  dupes_sites %>%
    distinct(location_std, month_date) %>%
    slice_head(n = 5) %>%
    print()

  sites_merged <- sites_merged %>%
    group_by(location_std, month_date) %>%
    slice(1) %>%
    ungroup()
}

################################################################################
# 6. Data quality checks
################################################################################

cat("\n6. Data quality checks...\n")

# Check for gaps in time series
check_gaps <- function(df, label) {
  gaps <- df %>%
    group_by(location_std) %>%
    arrange(month_date) %>%
    mutate(
      gap_months = as.numeric(difftime(month_date, lag(month_date), units = "days")) / 30.44
    ) %>%
    filter(gap_months > 1.5) %>%  # More than 1.5 months = gap
    ungroup()

  if (nrow(gaps) > 0) {
    cat(glue("  ⚠ {label}: Found {nrow(gaps)} gaps in time series\n"))
    gaps %>%
      select(location, month_date, gap_months) %>%
      slice_head(n = 5) %>%
      print()
  } else {
    cat(glue("  ✓ {label}: No gaps in time series\n"))
  }
}

check_gaps(states_merged, "States")
check_gaps(sites_merged, "Sites")

# Check coverage by year
cat("\n  Coverage by year:\n")

coverage_states <- states_merged %>%
  mutate(year = year(month_date)) %>%
  group_by(year) %>%
  summarise(
    n_obs = n(),
    n_locations = n_distinct(location_std),
    mean_filings = mean(filings_count, na.rm = TRUE),
    sum_filings = sum(filings_count, na.rm = TRUE)
  )

cat("  States:\n")
print(coverage_states)

coverage_sites <- sites_merged %>%
  mutate(year = year(month_date)) %>%
  group_by(year) %>%
  summarise(
    n_obs = n(),
    n_locations = n_distinct(location_std),
    mean_filings = mean(filings_count, na.rm = TRUE),
    sum_filings = sum(filings_count, na.rm = TRUE)
  )

cat("\n  Sites:\n")
print(coverage_sites)

################################################################################
# 7. Write output files
################################################################################

cat("\n7. Writing output files...\n")

# States
write_csv(states_merged, "merged_ets_states_monthly.csv")
cat(glue("  ✓ merged_ets_states_monthly.csv ({nrow(states_merged)} rows)\n"))

# Sites
write_csv(sites_merged, "merged_ets_sites_monthly.csv")
cat(glue("  ✓ merged_ets_sites_monthly.csv ({nrow(sites_merged)} rows)\n"))

################################################################################
# 8. Summary
################################################################################

cat("\n=== SUMMARY ===\n")
cat("\nState-level panel:\n")
cat(glue("  Time period: {min(states_merged$month_date)} to {max(states_merged$month_date)}\n"))
cat(glue("  States: {n_distinct(states_merged$location_std)}\n"))
cat(glue("  Observations: {nrow(states_merged)}\n"))
cat(glue("  Mean filings/month: {round(mean(states_merged$filings_count, na.rm=TRUE), 1)}\n"))

cat("\nCity-level panel:\n")
cat(glue("  Time period: {min(sites_merged$month_date)} to {max(sites_merged$month_date)}\n"))
cat(glue("  Cities: {n_distinct(sites_merged$location_std)}\n"))
cat(glue("  Observations: {nrow(sites_merged)}\n"))
cat(glue("  Mean filings/month: {round(mean(sites_merged$filings_count, na.rm=TRUE), 1)}\n"))

cat("\nData sources:\n")
cat("  2020+ states: Aggregated from census tract level\n")
cat("  2020+ cities: Collapsed from duplicated city-month records\n")
cat("  2012-2019: Already aggregated in historical file\n")

cat("\n✓ Merge complete!\n")
