#!/usr/bin/env Rscript
################################################################################
# verify_merge.R
# Verify that the data merge between panels is correct
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

fips_to_state_abb <- function(state_fips) {
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

state_abbr_from_geoid <- function(geo_id) {
  x <- tolower(trimws(as.character(geo_id)))
  key <- gsub("[^a-z]", "", x)
  name_key <- gsub("[^a-z]", "", tolower(state.name))
  m <- setNames(state.abb, name_key)
  unname(m[key])
}

cat("=== VERIFYING DATA MERGE ===\n\n")

# Load data
df_all <- read_csv("combined_monthly_panel.csv", show_col_types = FALSE)
treat <- read_csv("state_month_panel_with_treatment.csv", show_col_types = FALSE)

# Build county-aggregated state panel
county_state <- df_all %>%
  filter(geo_level == "county") %>%
  mutate(
    fips_num = suppressWarnings(as.integer(fips)),
    state_fips = as.integer(floor(fips_num / 1000)),
    state_abb = fips_to_state_abb(state_fips),
    month_date = as.Date(month_date)
  ) %>%
  filter(!is.na(state_abb), !is.na(month_date)) %>%
  group_by(state_abb, month_date) %>%
  summarise(n_counties = n(), .groups = "drop")

county_states <- unique(county_state$state_abb)

# Build state-level fallback panel
state_fallback <- df_all %>%
  filter(geo_level == "state") %>%
  mutate(
    state_abb = state_abbr_from_geoid(geo_id),
    month_date = as.Date(month_date)
  ) %>%
  filter(!is.na(state_abb), !is.na(month_date)) %>%
  group_by(state_abb, month_date) %>%
  summarise(n_state_rows = n(), .groups = "drop")

state_fallback_states <- unique(state_fallback$state_abb)

cat("1. DATA SOURCES\n")
cat("   County-level states (n=", length(county_states), "):\n")
cat("   ", paste(sort(county_states), collapse=", "), "\n\n")

cat("   State-level fallback states (n=", length(state_fallback_states), "):\n")
cat("   ", paste(sort(state_fallback_states), collapse=", "), "\n\n")

# Check for overlap
overlap <- intersect(county_states, state_fallback_states)
if (length(overlap) > 0) {
  cat("   WARNING: Overlap between county and state data:\n")
  cat("   ", paste(overlap, collapse=", "), "\n\n")
} else {
  cat("   ✓ No overlap between county and state sources (correct!)\n\n")
}

# Build full panel
panel_raw <- bind_rows(
  county_state %>% select(state_abb, month_date),
  state_fallback %>%
    filter(!state_abb %in% county_states) %>%
    select(state_abb, month_date)
)

cat("2. PANEL COVERAGE\n")
cat("   Total states in panel_raw:", n_distinct(panel_raw$state_abb), "\n")
cat("   States:", paste(sort(unique(panel_raw$state_abb)), collapse=", "), "\n\n")

# Check treatment file
treat_clean <- treat %>%
  mutate(
    state_abb = as.character(state_abb),
    month_date = as.Date(month_date)
  )

cat("3. TREATMENT FILE\n")
cat("   States in treatment file:", n_distinct(treat_clean$state_abb), "\n")
cat("   States:", paste(sort(unique(treat_clean$state_abb)), collapse=", "), "\n\n")

# Check merge
panel_states <- unique(panel_raw$state_abb)
treat_states <- unique(treat_clean$state_abb)

in_panel_not_treat <- setdiff(panel_states, treat_states)
in_treat_not_panel <- setdiff(treat_states, panel_states)

cat("4. MERGE CHECK\n")
if (length(in_panel_not_treat) > 0) {
  cat("   ⚠ In panel but NOT in treatment file:", paste(in_panel_not_treat, collapse=", "), "\n")
} else {
  cat("   ✓ All panel states have treatment data\n")
}

if (length(in_treat_not_panel) > 0) {
  cat("   ⚠ In treatment but NOT in panel:", paste(in_treat_not_panel, collapse=", "), "\n")
} else {
  cat("   ✓ All treatment states have panel data\n")
}

# After merge
panel_merged <- panel_raw %>%
  left_join(treat_clean %>% select(state_abb, month_date),
            by = c("state_abb", "month_date")) %>%
  filter(state_abb %in% treat_states)

cat("\n5. AFTER MERGE\n")
cat("   States in merged panel:", n_distinct(panel_merged$state_abb), "\n")
cat("   State-months in merged panel:", nrow(panel_merged), "\n")

# Check for missing states
final_states <- unique(panel_merged$state_abb)
missing_from_final <- setdiff(treat_states, final_states)
if (length(missing_from_final) > 0) {
  cat("   ⚠ States LOST in merge:", paste(missing_from_final, collapse=", "), "\n")
} else {
  cat("   ✓ No states lost in merge\n")
}

# Sample merge check
cat("\n6. SAMPLE VERIFICATION (first 5 states, Jan 2020)\n")
sample_check <- panel_merged %>%
  filter(month_date == as.Date("2020-01-01")) %>%
  arrange(state_abb) %>%
  head(5)
print(sample_check)

cat("\n=== MERGE VERIFICATION COMPLETE ===\n")
