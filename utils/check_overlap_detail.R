#!/usr/bin/env Rscript
################################################################################
# check_overlap_detail.R
# Check if states with both county and state-level data have temporal overlap
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
})

# State FIPS mapping
fips_to_state <- function(state_fips) {
  lookup <- c(
    `1`="AL", `2`="AK", `4`="AZ", `5`="AR", `6`="CA", `8`="CO", `9`="CT",
    `10`="DE", `11`="DC", `12`="FL", `13`="GA", `15`="HI", `16`="ID",
    `17`="IL", `18`="IN", `19`="IA", `20`="KS", `21`="KY", `22`="LA",
    `23`="ME", `24`="MD", `25`="MA", `26`="MI", `27`="MN", `28`="MS",
    `29`="MO", `30`="MT", `31`="NE", `32`="NV", `33`="NH", `34`="NJ",
    `35`="NM", `36`="NY", `37`="NC", `38`="ND", `39`="OH", `40`="OK",
    `41`="OR", `42`="PA", `44`="RI", `45`="SC", `46`="SD", `47`="TN",
    `48`="TX", `49`="UT", `50`="VT", `51`="VA", `53`="WA", `54`="WV",
    `55`="WI", `56`="WY"
  )
  unname(lookup[as.character(as.integer(state_fips))])
}

state_from_geo_id <- function(geo_id) {
  # Extract state abbreviation from geo_id
  geo_lower <- tolower(trimws(as.character(geo_id)))

  # Map common state names to abbreviations
  state_map <- c(
    "colorado" = "CO", "delaware" = "DE", "florida" = "FL",
    "indiana" = "IN", "arkansas" = "AR", "connecticut" = "CT",
    "arizona" = "AZ", "alabama" = "AL", "kentucky" = "KY",
    "louisiana" = "LA", "massachusetts" = "MA", "northcarolina" = "NC"
  )

  geo_clean <- gsub("[^a-z]", "", geo_lower)
  toupper(unname(state_map[geo_clean]))
}

cat("=== CHECKING OVERLAP DETAIL ===\n\n")

# Load combined data
combined <- read_csv("combined_monthly_panel.csv", show_col_types = FALSE)

# Get county data with state mapping
county_data <- combined %>%
  filter(geo_level == "county") %>%
  mutate(
    state_fips = floor(as.numeric(fips) / 1000),
    state_abb = fips_to_state(state_fips)
  ) %>%
  filter(!is.na(state_abb)) %>%
  group_by(state_abb, month_date) %>%
  summarise(
    county_filings = sum(filings_count, na.rm = TRUE),
    n_counties = n(),
    .groups = "drop"
  )

# Get state-level data
state_data <- combined %>%
  filter(geo_level == "state") %>%
  mutate(state_abb = state_from_geo_id(geo_id)) %>%
  filter(!is.na(state_abb)) %>%
  select(state_abb, month_date, state_filings = filings_count, source)

# Find states in both
county_states <- unique(county_data$state_abb)
state_level_states <- unique(state_data$state_abb)
overlap_states <- intersect(county_states, state_level_states)

cat(glue("States with both county and state-level data: {length(overlap_states)}\n"))
cat("  ", paste(overlap_states, collapse = ", "), "\n\n")

# Check temporal overlap for each state
for (state in overlap_states) {
  cat(glue("--- {state} ---\n"))

  county_dates <- county_data %>%
    filter(state_abb == state) %>%
    pull(month_date)

  state_dates <- state_data %>%
    filter(state_abb == state) %>%
    pull(month_date)

  cat(glue("  County data: {min(county_dates)} to {max(county_dates)} ({length(county_dates)} months)\n"))
  cat(glue("  State data:  {min(state_dates)} to {max(state_dates)} ({length(state_dates)} months)\n"))

  # Check for temporal overlap
  temporal_overlap <- intersect(county_dates, state_dates)

  if (length(temporal_overlap) > 0) {
    cat(glue("  ⚠ TEMPORAL OVERLAP: {length(temporal_overlap)} months\n"))
    cat(glue("    Overlapping period: {min(temporal_overlap)} to {max(temporal_overlap)}\n"))

    # Show a sample comparison
    sample_overlap <- state_data %>%
      filter(state_abb == state, month_date %in% temporal_overlap) %>%
      slice(1:3) %>%
      left_join(
        county_data %>% filter(state_abb == state),
        by = c("state_abb", "month_date")
      ) %>%
      select(month_date, state_filings, county_filings, n_counties, source)

    cat("    Sample comparison:\n")
    print(sample_overlap, n = 3)
  } else {
    cat("  ✓ No temporal overlap - different time periods\n")
  }

  cat("\n")
}

cat("\n=== SUMMARY ===\n")
cat("The overlap check shows whether states have both county and state-level\n")
cat("data for the SAME time periods (temporal overlap) or different periods.\n")
