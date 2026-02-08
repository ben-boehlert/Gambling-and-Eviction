#!/usr/bin/env Rscript
################################################################################
# create_mortgage_delinquency_panel.R
#
# Transform wide-format mortgage delinquency data to long state-month panel
#
# Input:  StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv (wide format)
# Output: data/processed/mortgage_delinquency_panel.csv (long format)
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
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

cat("=== Mortgage Delinquency Panel Creation ===\n")

# ========================== STEP 1: Read Data =================================
cat("\n[1/6] Reading mortgage data...\n")

input_file <- "StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv"
if (!file.exists(input_file)) {
  stop("Input file not found: ", input_file)
}

mortgage_wide <- readr::read_csv(input_file, show_col_types = FALSE)

cat("  Dimensions:", nrow(mortgage_wide), "rows x", ncol(mortgage_wide), "columns\n")

# ========================== STEP 2: Filter States =============================
cat("\n[2/6] Filtering to state-level data...\n")

mortgage_states <- mortgage_wide %>%
  filter(RegionType == "State")

cat("  States found:", nrow(mortgage_states), "\n")

# ========================== STEP 3: Extract Metadata ==========================
cat("\n[3/6] Extracting state metadata...\n")

state_meta <- mortgage_states %>%
  select(Name, FIPSCode) %>%
  mutate(
    state_abb = state_name_to_abb(Name),
    # Clean FIPS code: remove quotes
    fips_numeric = as.integer(gsub("'", "", FIPSCode))
  )

# Check for any missing state abbreviations
missing_states <- state_meta %>% filter(is.na(state_abb))
if (nrow(missing_states) > 0) {
  cat("  WARNING: States with missing abbreviations:\n")
  print(missing_states$Name)
}

cat("  Mapped", sum(!is.na(state_meta$state_abb)), "states to abbreviations\n")

# ========================== STEP 4: Pivot to Long =============================
cat("\n[4/6] Pivoting to long format...\n")

# Add row index for joining back metadata
mortgage_states <- mortgage_states %>%
  mutate(row_idx = row_number())

state_meta <- state_meta %>%
  mutate(row_idx = row_number())

# Pivot all date columns (those starting with "20")
mortgage_long <- mortgage_states %>%
  select(row_idx, starts_with("20")) %>%
  pivot_longer(
    cols = starts_with("20"),
    names_to = "month_date_str",
    values_to = "delinquency_rate"
  ) %>%
  # Join back metadata
  left_join(state_meta, by = "row_idx") %>%
  select(-row_idx, -Name, -FIPSCode) %>%
  # Parse dates
  mutate(
    month_date = as.Date(paste0(month_date_str, "-01"), format = "%Y-%m-%d"),
    delinquency_rate = as.numeric(delinquency_rate)
  ) %>%
  select(state_abb, month_date, delinquency_rate, fips_numeric)

cat("  Long panel rows:", nrow(mortgage_long), "\n")

# ========================== STEP 5: Create Log Outcome ========================
cat("\n[5/6] Creating log-transformed outcome...\n")

eps <- 0.01  # User-specified epsilon

mortgage_panel <- mortgage_long %>%
  mutate(
    log_delinquency_rate = log(pmax(delinquency_rate, 0) + eps)
  ) %>%
  # Remove any rows with missing state or date
  filter(!is.na(state_abb), !is.na(month_date), is.finite(log_delinquency_rate))

cat("  Epsilon value:", eps, "\n")
cat("  Final panel rows:", nrow(mortgage_panel), "\n")

# ========================== STEP 6: Validation ================================
cat("\n[6/6] Validation checks...\n")

# Check dimensions
n_states <- length(unique(mortgage_panel$state_abb))
n_months <- length(unique(mortgage_panel$month_date))
expected_rows <- n_states * n_months

cat("  Unique states:", n_states, "\n")
cat("  Unique months:", n_months, "\n")
cat("  Expected rows (if balanced):", expected_rows, "\n")
cat("  Actual rows:", nrow(mortgage_panel), "\n")

if (nrow(mortgage_panel) < expected_rows) {
  cat("  NOTE: Panel is unbalanced (some state-months missing)\n")
}

# Date range
date_range <- range(mortgage_panel$month_date)
cat("  Date range:", as.character(date_range[1]), "to", as.character(date_range[2]), "\n")

# Check for missing values
n_missing_delinq <- sum(is.na(mortgage_panel$delinquency_rate))
n_missing_log <- sum(!is.finite(mortgage_panel$log_delinquency_rate))

cat("  Missing delinquency_rate:", n_missing_delinq, "\n")
cat("  Non-finite log_delinquency_rate:", n_missing_log, "\n")

# Summary statistics
cat("\n  Delinquency Rate Summary:\n")
print(summary(mortgage_panel$delinquency_rate))

cat("\n  Log Delinquency Rate Summary:\n")
print(summary(mortgage_panel$log_delinquency_rate))

# ========================== STEP 7: Save Output ===============================
cat("\n[7/7] Saving output...\n")

output_dir <- "data/processed"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

output_file <- file.path(output_dir, "mortgage_delinquency_panel.csv")
readr::write_csv(mortgage_panel, output_file)

cat("  Saved to:", output_file, "\n")

# Show first few rows
cat("\n  First 10 rows:\n")
print(head(mortgage_panel, 10))

cat("\n=== Panel Creation Complete ===\n")
