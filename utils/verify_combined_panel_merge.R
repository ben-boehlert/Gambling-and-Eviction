#!/usr/bin/env Rscript
################################################################################
# verify_combined_panel_merge.R
#
# Verifies that combined_monthly_panel.csv properly merges data from:
#   1. monthly_county_data_download.csv (county-level eviction data)
#   2. data/raw/ets_merged/merged_ets_combined.csv (state-level ETS data)
#
# Author: Verification script
# Date: 2026-01-16
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
})

cat("=== VERIFYING COMBINED_MONTHLY_PANEL.CSV MERGE ===\n\n")

################################################################################
# 1. Load all three files
################################################################################

cat("1. Loading data files...\n")

# Combined file
combined <- read_csv("combined_monthly_panel.csv", show_col_types = FALSE)
cat(glue("  combined_monthly_panel.csv: {nrow(combined)} rows\n"))

# County source
county_source <- read_csv("data/raw/monthly_county_data_download.csv", show_col_types = FALSE)
cat(glue("  monthly_county_data_download.csv: {nrow(county_source)} rows\n"))

# ETS source
ets_source <- read_csv("data/raw/ets_merged/merged_ets_combined.csv", show_col_types = FALSE)
cat(glue("  merged_ets_combined.csv: {nrow(ets_source)} rows\n"))

################################################################################
# 2. Analyze combined file structure
################################################################################

cat("\n2. Analyzing combined file structure...\n")

# Count by source
source_counts <- combined %>%
  group_by(source) %>%
  summarise(
    n_rows = n(),
    n_unique_locations = n_distinct(geo_id),
    date_min = min(month_date, na.rm = TRUE),
    date_max = max(month_date, na.rm = TRUE),
    .groups = "drop"
  )

cat("\n  Sources in combined file:\n")
print(source_counts, n = Inf)

# Count by geo_level
geo_counts <- combined %>%
  group_by(geo_level, source) %>%
  summarise(n_rows = n(), .groups = "drop")

cat("\n  Geo levels and sources:\n")
print(geo_counts, n = Inf)

################################################################################
# 3. Verify county data merge
################################################################################

cat("\n3. Verifying county data (source = 'ets_county_download')...\n")

county_in_combined <- combined %>%
  filter(source == "ets_county_download")

cat(glue("  County rows in combined: {nrow(county_in_combined)}\n"))
cat(glue("  County rows in source:   {nrow(county_source)}\n"))

# Compare row counts
if (nrow(county_in_combined) == nrow(county_source)) {
  cat("  ✓ Row counts match!\n")
} else {
  cat("  ⚠ Row counts DO NOT match!\n")
  cat(glue("    Difference: {nrow(county_in_combined) - nrow(county_source)} rows\n"))
}

# Check for missing counties
county_source_keys <- county_source %>%
  mutate(
    month_date = as.Date(date),
    key = paste(fips, month_date, sep = "_")
  ) %>%
  pull(key)

county_combined_keys <- county_in_combined %>%
  mutate(key = paste(fips, month_date, sep = "_")) %>%
  pull(key)

missing_in_combined <- setdiff(county_source_keys, county_combined_keys)
extra_in_combined <- setdiff(county_combined_keys, county_source_keys)

if (length(missing_in_combined) > 0) {
  cat(glue("  ⚠ {length(missing_in_combined)} county-month records missing in combined\n"))
  cat("    First 5 missing:\n")
  print(head(missing_in_combined, 5))
} else {
  cat("  ✓ All county-month records present\n")
}

if (length(extra_in_combined) > 0) {
  cat(glue("  ⚠ {length(extra_in_combined)} extra county-month records in combined\n"))
} else {
  cat("  ✓ No extra county-month records\n")
}

# Spot check values
cat("\n  Spot-checking county data values...\n")
sample_check <- county_source %>%
  mutate(month_date = as.Date(date)) %>%
  select(fips, month_date, filings_count, renter_occupied_housing_units) %>%
  slice(1:3) %>%
  left_join(
    county_in_combined %>%
      select(fips, month_date,
             filings_combined = filings_count,
             renters_combined = renter_occupied_housing_units),
    by = c("fips", "month_date")
  ) %>%
  mutate(
    filings_match = filings_count == filings_combined,
    renters_match = renter_occupied_housing_units == renters_combined
  )

if (all(sample_check$filings_match, na.rm = TRUE) && all(sample_check$renters_match, na.rm = TRUE)) {
  cat("  ✓ Sample values match source data\n")
} else {
  cat("  ⚠ Sample values DO NOT match!\n")
  print(sample_check)
}

################################################################################
# 4. Verify ETS state-level data merge
################################################################################

cat("\n4. Verifying ETS state-level data...\n")

ets_state_in_combined <- combined %>%
  filter(source == "state_level")

ets_state_in_source <- ets_source %>%
  filter(source == "state_level")

cat(glue("  State-level rows in combined: {nrow(ets_state_in_combined)}\n"))
cat(glue("  State-level rows in source:   {nrow(ets_state_in_source)}\n"))

if (nrow(ets_state_in_combined) == nrow(ets_state_in_source)) {
  cat("  ✓ Row counts match!\n")
} else {
  cat("  ⚠ Row counts DO NOT match!\n")
  cat(glue("    Difference: {nrow(ets_state_in_combined) - nrow(ets_state_in_source)} rows\n"))
}

# Check cities_aggregated
ets_cities_in_combined <- combined %>%
  filter(source == "cities_aggregated")

ets_cities_in_source <- ets_source %>%
  filter(source == "cities_aggregated")

cat(glue("\n  Cities-aggregated rows in combined: {nrow(ets_cities_in_combined)}\n"))
cat(glue("  Cities-aggregated rows in source:   {nrow(ets_cities_in_source)}\n"))

if (nrow(ets_cities_in_combined) == nrow(ets_cities_in_source)) {
  cat("  ✓ Row counts match!\n")
} else {
  cat("  ⚠ Row counts DO NOT match!\n")
}

################################################################################
# 5. Check for overlaps and gaps
################################################################################

cat("\n5. Checking for overlaps and gaps...\n")

# Check if any states have both county and state-level data
county_states <- combined %>%
  filter(geo_level == "county") %>%
  mutate(
    state_fips = floor(as.numeric(fips) / 1000),
    state_abb = case_when(
      state_fips == 1 ~ "AL", state_fips == 2 ~ "AK", state_fips == 4 ~ "AZ",
      state_fips == 5 ~ "AR", state_fips == 6 ~ "CA", state_fips == 8 ~ "CO",
      state_fips == 9 ~ "CT", state_fips == 10 ~ "DE", state_fips == 11 ~ "DC",
      state_fips == 12 ~ "FL", state_fips == 13 ~ "GA", state_fips == 15 ~ "HI",
      state_fips == 17 ~ "IL", state_fips == 18 ~ "IN", state_fips == 19 ~ "IA",
      state_fips == 20 ~ "KS", state_fips == 21 ~ "KY", state_fips == 22 ~ "LA",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(state_abb)) %>%
  distinct(state_abb) %>%
  pull(state_abb)

state_level_states <- combined %>%
  filter(geo_level == "state") %>%
  mutate(state_abb = toupper(substr(geo_id, 1, 2))) %>%
  distinct(state_abb) %>%
  pull(state_abb)

overlap <- intersect(county_states, state_level_states)

if (length(overlap) > 0) {
  cat(glue("  ⚠ {length(overlap)} states have BOTH county and state-level data:\n"))
  cat("    ", paste(overlap, collapse = ", "), "\n")
  cat("    This might be intentional if they cover different time periods.\n")
} else {
  cat("  ✓ No overlap - states have either county OR state-level data (not both)\n")
}

################################################################################
# 6. Summary
################################################################################

cat("\n=== SUMMARY ===\n\n")

cat("Combined file composition:\n")
cat(glue("  Total rows: {nrow(combined)}\n"))
cat(glue("  County-level (ets_county_download): {nrow(county_in_combined)} rows\n"))
cat(glue("  State-level (state_level): {nrow(ets_state_in_combined)} rows\n"))
cat(glue("  State-level (cities_aggregated): {nrow(ets_cities_in_combined)} rows\n"))
cat(glue("  Sum of components: {nrow(county_in_combined) + nrow(ets_state_in_combined) + nrow(ets_cities_in_combined)}\n"))

cat("\nDate ranges:\n")
cat(glue("  Overall: {min(combined$month_date)} to {max(combined$month_date)}\n"))
cat(glue("  County data: {min(county_in_combined$month_date, na.rm=TRUE)} to {max(county_in_combined$month_date, na.rm=TRUE)}\n"))
cat(glue("  State ETS: {min(ets_state_in_combined$month_date, na.rm=TRUE)} to {max(ets_state_in_combined$month_date, na.rm=TRUE)}\n"))
cat(glue("  Cities ETS: {min(ets_cities_in_combined$month_date, na.rm=TRUE)} to {max(ets_cities_in_combined$month_date, na.rm=TRUE)}\n"))

cat("\n✓ Verification complete!\n")
