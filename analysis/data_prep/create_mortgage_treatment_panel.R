#!/usr/bin/env Rscript
################################################################################
# create_mortgage_treatment_panel.R
#
# Merge mortgage delinquency panel with online gambling treatment dates
#
# Input:  data/processed/mortgage_delinquency_panel.csv
#         data/raw/sports_gambling_legalization_dates.csv
# Output: data/processed/mortgage_treatment_panel.csv
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

# State name to abbreviation mapping
state_name_to_abb <- function(name) {
  lookup <- c(
    "Alabama" = "AL", "Alaska" = "AK", "Arizona" = "AZ", "Arkansas" = "AR",
    "California" = "CA", "Colorado" = "CO", "Connecticut" = "CT", "Delaware" = "DE",
    "District of Columbia" = "DC", "Florida" = "FL", "Georgia" = "GA", "Hawaii" = "HI",
    "Idaho" = "ID", "Illinois" = "IL", "Indiana" = "IN", "Iowa" = "IA",
    "Kansas" = "KS", "Kentucky" = "KY", "Louisiana" = "LA", "Maine" = "ME",
    "Maryland" = "MD", "Massachusetts" = "MA", "Michigan" = "MI", "Minnesota" = "MN",
    "Mississippi" = "MS", "Missouri" = "MO", "Montana" = "MT", "Nebraska" = "NE",
    "Nevada" = "NV", "New Hampshire" = "NH", "New Jersey" = "NJ", "New Mexico" = "NM",
    "New York" = "NY", "North Carolina" = "NC", "North Dakota" = "ND", "Ohio" = "OH",
    "Oklahoma" = "OK", "Oregon" = "OR", "Pennsylvania" = "PA", "Rhode Island" = "RI",
    "South Carolina" = "SC", "South Dakota" = "SD", "Tennessee" = "TN", "Texas" = "TX",
    "Utah" = "UT", "Vermont" = "VT", "Virginia" = "VA", "Washington" = "WA",
    "West Virginia" = "WV", "Wisconsin" = "WI", "Wyoming" = "WY"
  )
  lookup[name]
}

cat("=== Mortgage Treatment Panel Creation ===\n")

# ========================== STEP 1: Load Data =================================
cat("\n[1/5] Loading mortgage panel...\n")

mortgage_file <- "data/processed/mortgage_delinquency_panel.csv"
if (!file.exists(mortgage_file)) {
  stop("Mortgage panel not found: ", mortgage_file,
       "\n  Run create_mortgage_delinquency_panel.R first")
}

mortgage_panel <- readr::read_csv(mortgage_file, show_col_types = FALSE)
cat("  Loaded", nrow(mortgage_panel), "rows\n")

# ========================== STEP 2: Load Gambling Dates =======================
cat("\n[2/5] Loading gambling legalization dates...\n")

gambling_file <- "data/raw/sports_gambling_legalization_dates.csv"
if (!file.exists(gambling_file)) {
  stop("Gambling dates file not found: ", gambling_file)
}

gambling_raw <- readr::read_csv(gambling_file, show_col_types = FALSE)

# Filter to online gambling only and create state abbreviations
gambling_dates <- gambling_raw %>%
  filter(has_online == TRUE) %>%  # CRITICAL: Online only
  mutate(
    state_abb = state_name_to_abb(state),
    online_start_date = as.Date(online_start_date, format = "%Y-%m-%d")
  ) %>%
  select(state_abb, online_start_date) %>%
  filter(!is.na(state_abb), !is.na(online_start_date))

cat("  States with online gambling:", nrow(gambling_dates), "\n")

# Show treatment dates
cat("\n  Treatment Date Range:\n")
cat("    Earliest:", as.character(min(gambling_dates$online_start_date)), "\n")
cat("    Latest:  ", as.character(max(gambling_dates$online_start_date)), "\n")

cat("\n  Treatment Timing:\n")
treatment_years <- gambling_dates %>%
  mutate(year = format(online_start_date, "%Y")) %>%
  count(year)
print(treatment_years)

# ========================== STEP 3: Create Full State List ===================
cat("\n[3/5] Creating complete state list...\n")

# All states in mortgage data
all_states <- tibble(state_abb = unique(mortgage_panel$state_abb))
cat("  Total states in mortgage data:", nrow(all_states), "\n")

# Left join to get both treated and never-treated
gambling_complete <- all_states %>%
  left_join(gambling_dates, by = "state_abb")

n_treated <- sum(!is.na(gambling_complete$online_start_date))
n_never_treated <- sum(is.na(gambling_complete$online_start_date))

cat("  Treated states (have online gambling):", n_treated, "\n")
cat("  Never-treated states (no online gambling):", n_never_treated, "\n")

# ========================== STEP 4: Merge with Panel =========================
cat("\n[4/5] Merging treatment dates with panel...\n")

mortgage_treatment_panel <- mortgage_panel %>%
  left_join(gambling_complete, by = "state_abb") %>%
  mutate(
    treatment_date = online_start_date,
    treated = !is.na(treatment_date)
  ) %>%
  select(state_abb, month_date, delinquency_rate, log_delinquency_rate,
         treatment_date, treated, fips_numeric)

cat("  Panel rows:", nrow(mortgage_treatment_panel), "\n")

# ========================== STEP 5: Validation ================================
cat("\n[5/5] Validation checks...\n")

# Check treatment assignment
validation <- mortgage_treatment_panel %>%
  group_by(state_abb, treated) %>%
  summarise(
    n_obs = n(),
    treatment_date = first(treatment_date),
    .groups = "drop"
  ) %>%
  arrange(treated, treatment_date)

cat("\n  Treatment Assignment by State:\n")
cat("    Treated states:", sum(validation$treated), "\n")
cat("    Never-treated states:", sum(!validation$treated), "\n")

# Show treated states
cat("\n  Treated States (Online Gambling Legalized):\n")
treated_states <- validation %>%
  filter(treated) %>%
  arrange(treatment_date)
print(treated_states, n = Inf)

# Show never-treated states
cat("\n  Never-Treated States:\n")
never_treated_states <- validation %>%
  filter(!treated) %>%
  pull(state_abb)
cat("   ", paste(never_treated_states, collapse = ", "), "\n")

# Check for any issues
if (any(is.na(mortgage_treatment_panel$state_abb))) {
  warning("  WARNING: Some rows have missing state_abb")
}

if (any(is.na(mortgage_treatment_panel$month_date))) {
  warning("  WARNING: Some rows have missing month_date")
}

# Date validation for treatment dates
invalid_dates <- mortgage_treatment_panel %>%
  filter(treated, !is.na(treatment_date)) %>%
  filter(format(treatment_date, "%d") != "01")

if (nrow(invalid_dates) > 0) {
  warning("  WARNING: Some treatment dates are not first of month")
  print(unique(invalid_dates$treatment_date))
}

cat("\n  All treatment dates on first of month: ",
    nrow(invalid_dates) == 0, "\n")

# ========================== STEP 6: Save Output ===============================
cat("\n[6/6] Saving output...\n")

output_file <- "data/processed/mortgage_treatment_panel.csv"
readr::write_csv(mortgage_treatment_panel, output_file)

cat("  Saved to:", output_file, "\n")

# Show sample rows
cat("\n  Sample rows (treated state):\n")
sample_treated <- mortgage_treatment_panel %>%
  filter(treated) %>%
  arrange(state_abb, month_date) %>%
  head(10)
print(sample_treated)

cat("\n  Sample rows (never-treated state):\n")
sample_never <- mortgage_treatment_panel %>%
  filter(!treated) %>%
  arrange(state_abb, month_date) %>%
  head(10)
print(sample_never)

cat("\n=== Treatment Panel Creation Complete ===\n")
