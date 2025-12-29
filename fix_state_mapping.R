################################################################################
# FIX: Create proper state FIPS mapping
# The state.fips dataset doesn't exist in standard R
################################################################################

# Create complete state FIPS mapping manually
create_state_fips_map <- function() {
  tibble(
    state_fips = sprintf("%02d", 1:56),
    state_abb = c(
      "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL",  # 01-10
      "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME",  # 11-20
      "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH",  # 21-30
      "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI",  # 31-40
      "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI",  # 41-50
      "WY", "AS", "GU", "MP", "PR", "VI"                           # 51-56 (territories)
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
      "Vermont", "Virginia", "Washington", "West Virginia", "Wisconsin",
      "Wyoming", "American Samoa", "Guam", "Northern Mariana Islands",
      "Puerto Rico", "U.S. Virgin Islands"
    )
  )
}

# Test it
state_map <- create_state_fips_map()
print(head(state_map, 10))

cat("\nState mapping created successfully.\n")
cat(sprintf("Total states/territories: %d\n", nrow(state_map)))
cat(sprintf("50 states + DC: rows 1-51\n"))

# Export as CSV for reference
write.csv(state_map, "state_fips_mapping.csv", row.names = FALSE)
cat("\nSaved to: state_fips_mapping.csv\n")
