################################################################################
# WORKING PANEL BUILDER - Fixes state mapping issue
################################################################################

library(tidyverse)
library(lubridate)

# Create state FIPS mapping (replaces missing state.fips)
STATE_FIPS_MAP <- tibble(
  state_fips = sprintf("%02d", 1:51),
  state_abb = c(
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL",
    "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME",
    "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH",
    "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI",
    "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"
  ),
  state_name = c(
    "Alabama", "Alaska", "Arizona", "Arkansas", "California",
    "Colorado", "Connecticut", "Delaware", "District of Columbia", "Florida",
    "Georgia", "Hawaii", "Idaho", "Illinois", "Indiana",
    "Iowa", "Kansas", "Kentucky", "Louisiana", "Maine",
    "Maryland", "Massachusetts", "Michigan", "Minnesota", "Mississippi",
    "Missouri", "Montana", "Nebraska", "Nevada", "New Hampshire",
    "New Jersey", "New Mexico", "New York", "North Carolina", "North Dakota",
    "Ohio", "Oklahoma", "Oregon", "Pennsylvania", "Rhode Island",
    "South Carolina", "South Dakota", "Tennessee", "Texas", "Utah",
    "Vermont", "Virginia", "Washington", "West Virginia", "Wisconsin", "Wyoming"
  )
)

build_state_month_from_county <- function(county_file) {
  cat("Building state-month panel from county data...\n")

  # Read county data
  county_data <- read_csv(county_file, show_col_types = FALSE)

  cat(sprintf("  Loaded %d county-month observations\n", nrow(county_data)))

  # Process and aggregate
  state_month <- county_data %>%
    mutate(
      # Parse date
      date = ymd_hms(date),
      year_month = floor_date(date, "month"),
      # Extract state FIPS (first 2 digits)
      state_fips = str_sub(as.character(fips), 1, 2)
    ) %>%
    # Aggregate to state-month
    group_by(state_fips, year_month) %>%
    summarise(
      filings = sum(filings_count, na.rm = TRUE),
      renter_hh = sum(renter_occupied_housing_units, na.rm = TRUE),
      n_counties = n(),
      .groups = "drop"
    ) %>%
    # Filter valid data
    filter(!is.na(state_fips), renter_hh > 0) %>%
    # Calculate rate
    mutate(
      filings_per_1000 = (filings / renter_hh) * 1000
    ) %>%
    # Add state names and abbreviations
    left_join(STATE_FIPS_MAP, by = "state_fips") %>%
    # Rename for consistency
    rename(
      state = state_fips,
      month = year_month
    )

  cat(sprintf("  Created %d state-months for %d states\n",
              nrow(state_month), n_distinct(state_month$state)))

  return(state_month)
}

build_state_month_from_sites <- function(sites_file) {
  cat("Building state-month panel from sites data...\n")

  # Read sites data
  sites_data <- read_csv(sites_file, show_col_types = FALSE)

  cat(sprintf("  Loaded %d site-month observations\n", nrow(sites_data)))

  # Process
  state_month <- sites_data %>%
    mutate(
      # Extract state abbreviation from city (e.g., "Albuquerque, NM")
      state_abb = str_trim(str_extract(city, "[A-Z]{2}$")),
      # Parse month (e.g., "Jan-20")
      month = my(month)
    ) %>%
    filter(!is.na(state_abb), !is.na(month)) %>%
    # Join to get state FIPS
    left_join(STATE_FIPS_MAP, by = "state_abb") %>%
    filter(!is.na(state_fips)) %>%
    # Aggregate to state-month
    group_by(state = state_fips, state_abb, month) %>%
    summarise(
      filings = sum(filings_2020, na.rm = TRUE),
      n_sites = n(),
      .groups = "drop"
    )

  # Need renter HH denominator - get from county data if available
  cat("  Note: Sites data needs renter_hh from county data for rates\n")

  cat(sprintf("  Created %d state-months for %d states\n",
              nrow(state_month), n_distinct(state_month$state)))

  return(state_month)
}

# Test the functions
cat("\n=== TESTING PANEL BUILDERS ===\n\n")

tryCatch({
  panel1 <- build_state_month_from_county("monthly_county_data_download.csv")
  cat("\n✓ County panel built successfully\n")
  print(head(panel1))

  # Save it
  write_csv(panel1, "panel1_county_state_month.csv")
  cat("\nSaved to: panel1_county_state_month.csv\n")

}, error = function(e) {
  cat("\n✗ Error building county panel:", e$message, "\n")
})

cat("\n")

tryCatch({
  panel2 <- build_state_month_from_sites("all_sites_monthly_2020_2021.csv")
  cat("\n✓ Sites panel built successfully\n")
  print(head(panel2))

  # Save it
  write_csv(panel2, "panel2_sites_state_month.csv")
  cat("\nSaved to: panel2_sites_state_month.csv\n")

}, error = function(e) {
  cat("\n✗ Error building sites panel:", e$message, "\n")
})

cat("\n=== DONE ===\n")
cat("\nYou can now use these panels for analysis.\n")
cat("The county panel (panel1) has filings_per_1000 already calculated.\n\n")
