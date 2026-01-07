#!/usr/bin/env Rscript
################################################################################
# merge_ets_combined.R
#
# Combines state and city ETS data into a single panel:
#   - Use state-level data where available
#   - Add city-level data only for states NOT in state-level data
#   - Extract state from city names (e.g., "Houston, TX" -> TX)
#
# Input:
#   - merged_ets_states_monthly.csv
#   - merged_ets_sites_monthly.csv
#
# Output:
#   - merged_ets_combined.csv (state or city level, depending on availability)
################################################################################

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(glue)
})

cat("=== Combining ETS State and City Data ===\n\n")

################################################################################
# 1. Read merged state data
################################################################################

cat("1. Reading merged_ets_states_monthly.csv...\n")

states <- read_csv("merged_ets_states_monthly.csv", show_col_types = FALSE)

cat(glue("  {nrow(states)} rows, {n_distinct(states$location_std)} states\n"))
cat(glue("  Date range: {min(states$month_date)} to {max(states$month_date)}\n"))

# Get list of states we already have
states_available <- unique(states$location_std)
cat(glue("  States with data: {paste(sort(states_available), collapse=', ')}\n"))

################################################################################
# 2. Read merged city data
################################################################################

cat("\n2. Reading merged_ets_sites_monthly.csv...\n")

cities <- read_csv("merged_ets_sites_monthly.csv", show_col_types = FALSE)

cat(glue("  {nrow(cities)} rows, {n_distinct(cities$location_std)} cities\n"))
cat(glue("  Date range: {min(cities$month_date)} to {max(cities$month_date)}\n"))

################################################################################
# 3. Extract state from city names
################################################################################

cat("\n3. Extracting state from city names...\n")

# Extract state abbreviation from city names like "Houston, TX"
cities <- cities %>%
  mutate(
    # Extract 2-letter state code after comma
    state_abb = str_extract(location, "(?<=,\\s{0,2})[A-Z]{2}$"),
    state_abb = str_trim(state_abb)
  )

# State abbreviation to full name mapping
state_abb_to_name <- c(
  "AL" = "alabama", "AK" = "alaska", "AZ" = "arizona", "AR" = "arkansas",
  "CA" = "california", "CO" = "colorado", "CT" = "connecticut", "DE" = "delaware",
  "DC" = "districtofcolumbia", "FL" = "florida", "GA" = "georgia", "HI" = "hawaii",
  "ID" = "idaho", "IL" = "illinois", "IN" = "indiana", "IA" = "iowa",
  "KS" = "kansas", "KY" = "kentucky", "LA" = "louisiana", "ME" = "maine",
  "MD" = "maryland", "MA" = "massachusetts", "MI" = "michigan", "MN" = "minnesota",
  "MS" = "mississippi", "MO" = "missouri", "MT" = "montana", "NE" = "nebraska",
  "NV" = "nevada", "NH" = "newhampshire", "NJ" = "newjersey", "NM" = "newmexico",
  "NY" = "newyork", "NC" = "northcarolina", "ND" = "northdakota", "OH" = "ohio",
  "OK" = "oklahoma", "OR" = "oregon", "PA" = "pennsylvania", "RI" = "rhodeisland",
  "SC" = "southcarolina", "SD" = "southdakota", "TN" = "tennessee", "TX" = "texas",
  "UT" = "utah", "VT" = "vermont", "VA" = "virginia", "WA" = "washington",
  "WV" = "westvirginia", "WI" = "wisconsin", "WY" = "wyoming"
)

cities <- cities %>%
  mutate(
    state_name = state_abb_to_name[state_abb],
    state_name = if_else(is.na(state_name), NA_character_, state_name),
    # Standardize Rhode Island to match states file (has space)
    state_name = if_else(state_name == "rhodeisland", "rhode island", state_name)
  )

# Check how many cities have state identified
cities_with_state <- cities %>%
  filter(!is.na(state_name)) %>%
  distinct(location_std)

cat(glue("  {nrow(cities_with_state)}/{n_distinct(cities$location_std)} cities have state identified\n"))

# Show cities without state identified
cities_no_state <- cities %>%
  filter(is.na(state_name)) %>%
  distinct(location_std, location) %>%
  pull(location)

if (length(cities_no_state) > 0) {
  cat("  ⚠ Cities without state abbreviation:\n")
  cat(glue("    {paste(head(cities_no_state, 10), collapse=', ')}\n"))
}

################################################################################
# 4. Aggregate cities to state level for states not in state data
################################################################################

cat("\n4. Aggregating cities to state level...\n")

# Identify which states are represented in cities but NOT in state data
city_states <- cities %>%
  filter(!is.na(state_name)) %>%
  distinct(state_name) %>%
  pull(state_name)

states_from_cities_only <- setdiff(city_states, states_available)

cat(glue("  States in city data but not in state data: {length(states_from_cities_only)}\n"))
if (length(states_from_cities_only) > 0) {
  cat(glue("    {paste(sort(states_from_cities_only), collapse=', ')}\n"))
}

# Aggregate city data to state level for these states
if (length(states_from_cities_only) > 0) {
  cities_aggregated <- cities %>%
    filter(state_name %in% states_from_cities_only) %>%
    group_by(state_name, month_date) %>%
    summarise(
      filings_count = sum(filings_count, na.rm = TRUE),
      filings_avg = mean(filings_avg, na.rm = TRUE),
      n_cities = n(),
      .groups = "drop"
    ) %>%
    mutate(
      location = state_name,
      location_std = state_name,
      is_state = TRUE,
      source = "cities_aggregated"
    ) %>%
    select(location, location_std, month_date, filings_count, filings_avg, is_state, source)

  cat(glue("  Aggregated: {nrow(cities_aggregated)} state-month observations from cities\n"))
} else {
  cities_aggregated <- tibble(
    location = character(),
    location_std = character(),
    month_date = as.Date(character()),
    filings_count = numeric(),
    filings_avg = numeric(),
    is_state = logical(),
    source = character()
  )
  cat("  No cities to aggregate (all states already have state-level data)\n")
}

################################################################################
# 5. Combine state data with aggregated city data
################################################################################

cat("\n5. Combining state and city data...\n")

# Add source column to state data
states_with_source <- states %>%
  mutate(source = "state_level")

# Combine
combined <- bind_rows(
  states_with_source,
  cities_aggregated
) %>%
  arrange(location_std, month_date)

cat(glue("  Combined: {nrow(combined)} rows, {n_distinct(combined$location_std)} states\n"))
cat(glue("  Date range: {min(combined$month_date)} to {max(combined$month_date)}\n"))

# Summary by source
source_summary <- combined %>%
  group_by(source) %>%
  summarise(
    n_obs = n(),
    n_states = n_distinct(location_std),
    mean_filings = mean(filings_count, na.rm = TRUE),
    .groups = "drop"
  )

cat("\n  Data sources:\n")
print(source_summary)

################################################################################
# 6. Data quality checks
################################################################################

cat("\n6. Data quality checks...\n")

# Check for duplicates
dupes <- combined %>%
  group_by(location_std, month_date) %>%
  filter(n() > 1) %>%
  ungroup()

if (nrow(dupes) > 0) {
  cat("  ⚠ WARNING: Found duplicates:\n")
  dupes %>%
    distinct(location_std, month_date, source) %>%
    slice_head(n = 5) %>%
    print()

  # Keep state_level over cities_aggregated
  combined <- combined %>%
    group_by(location_std, month_date) %>%
    arrange(desc(source == "state_level")) %>%
    slice(1) %>%
    ungroup()

  cat("  ✓ Duplicates resolved (kept state_level data)\n")
} else {
  cat("  ✓ No duplicates found\n")
}

# Check for gaps in time series
gaps <- combined %>%
  group_by(location_std) %>%
  arrange(month_date) %>%
  mutate(
    gap_months = as.numeric(difftime(month_date, lag(month_date), units = "days")) / 30.44
  ) %>%
  filter(gap_months > 1.5) %>%
  ungroup()

if (nrow(gaps) > 0) {
  cat(glue("  ⚠ Found {nrow(gaps)} gaps in time series\n"))
  gaps %>%
    select(location, month_date, gap_months) %>%
    slice_head(n = 5) %>%
    print()
} else {
  cat("  ✓ No gaps in time series\n")
}

################################################################################
# 7. Write output
################################################################################

cat("\n7. Writing output file...\n")

write_csv(combined, "merged_ets_combined.csv")
cat(glue("  ✓ merged_ets_combined.csv ({nrow(combined)} rows)\n"))

################################################################################
# 8. Summary
################################################################################

cat("\n=== SUMMARY ===\n")
cat("\nCombined ETS panel:\n")
cat(glue("  Time period: {min(combined$month_date)} to {max(combined$month_date)}\n"))
cat(glue("  States/regions: {n_distinct(combined$location_std)}\n"))
cat(glue("  Observations: {nrow(combined)}\n"))
cat(glue("  Mean filings/month: {round(mean(combined$filings_count, na.rm=TRUE), 1)}\n"))

# List all states
all_states <- combined %>%
  distinct(location_std) %>%
  arrange(location_std) %>%
  pull(location_std)

cat("\nStates included:\n")
cat(glue("  {paste(all_states, collapse=', ')}\n"))

# States from each source
cat("\nStates by source:\n")
cat(glue("  State-level data: {paste(sort(states_available), collapse=', ')}\n"))
if (length(states_from_cities_only) > 0) {
  cat(glue("  Aggregated from cities: {paste(sort(states_from_cities_only), collapse=', ')}\n"))
}

cat("\n✓ Merge complete!\n")
