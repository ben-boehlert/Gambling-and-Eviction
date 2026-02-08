#!/usr/bin/env Rscript

# =============================================================================
# Create Activity-Based Treatment Dates
# =============================================================================
# Purpose: Generate treatment dates based on gambling handle activity thresholds
# Approach: Use percentage-of-peak and absolute dollar thresholds
# Output: activity_treatment_dates.csv with multiple threshold definitions

library(dplyr)
library(readr)
library(lubridate)

# -----------------------------------------------------------------------------
# 1. Load Data
# -----------------------------------------------------------------------------

cat("\n")
cat(strrep("=", 80), "\n")
cat("Activity-Based Treatment Date Generation\n")
cat(strrep("=", 80), "\n\n")

# Load gambling handle data
handle_file <- "data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv"
cat("Loading handle data from:", handle_file, "\n")
handle_data <- read_csv(handle_file, show_col_types = FALSE)

cat("  States with handle data:", n_distinct(handle_data$State), "\n")
cat("  Date range:", min(handle_data$month_date), "to", max(handle_data$month_date), "\n\n")

# Load existing treatment dates for comparison
gambling_dates_file <- "data/raw/sports_gambling_legalization_dates.csv"
cat("Loading legal dates from:", gambling_dates_file, "\n")
gambling_dates <- read_csv(gambling_dates_file, show_col_types = FALSE)

# -----------------------------------------------------------------------------
# 2. State Name Crosswalk
# -----------------------------------------------------------------------------
# Handle data uses full names (e.g., "New Jersey")
# Eviction data uses abbreviations (e.g., "NJ")

cat("\nCreating state name crosswalk...\n")

state_crosswalk <- tibble(
  state_name = state.name,
  state_abb = state.abb
) %>%
  bind_rows(tibble(state_name = "District of Columbia", state_abb = "DC"))

cat("  Crosswalk entries:", nrow(state_crosswalk), "\n\n")

# -----------------------------------------------------------------------------
# 3. Calculate Peak Handle for Each State
# -----------------------------------------------------------------------------

cat("Calculating peak handle for each state...\n")

peak_analysis <- handle_data %>%
  group_by(State) %>%
  summarise(
    peak_handle = max(Handle, na.rm = TRUE),
    first_month = min(month_date),
    last_month = max(month_date),
    n_months = n(),
    .groups = "drop"
  ) %>%
  arrange(desc(peak_handle))

cat("  States with peak calculations:", nrow(peak_analysis), "\n")
cat("  Largest peak:", peak_analysis$State[1], "at $",
    format(peak_analysis$peak_handle[1], big.mark = ","), "\n")
cat("  Smallest peak:", peak_analysis$State[nrow(peak_analysis)], "at $",
    format(peak_analysis$peak_handle[nrow(peak_analysis)], big.mark = ","), "\n\n")

# -----------------------------------------------------------------------------
# 4. Percentage-of-Peak Thresholds
# -----------------------------------------------------------------------------

cat("Computing percentage-of-peak treatment dates...\n")

# Define percentage thresholds
pct_thresholds <- c(10, 25, 50, 75)

# Function to find first month reaching percentage of peak
find_pct_threshold_date <- function(data, pct) {
  data %>%
    group_by(State) %>%
    arrange(State, month_date) %>%
    left_join(peak_analysis %>% dplyr::select(State, peak_handle), by = "State") %>%
    mutate(
      pct_of_peak = (Handle / peak_handle) * 100
    ) %>%
    filter(pct_of_peak >= pct) %>%
    summarise(
      treat_date = min(month_date),
      .groups = "drop"
    ) %>%
    rename(!!paste0("treat_", pct, "pct_peak") := treat_date)
}

# Calculate for each threshold
pct_dates_list <- lapply(pct_thresholds, function(pct) {
  cat("  ", pct, "% of peak threshold...\n")
  find_pct_threshold_date(handle_data, pct)
})

# Merge all percentage thresholds
pct_dates <- pct_dates_list[[1]]
for (i in 2:length(pct_dates_list)) {
  pct_dates <- pct_dates %>%
    left_join(pct_dates_list[[i]], by = "State")
}

cat("  Percentage thresholds calculated for", nrow(pct_dates), "states\n\n")

# -----------------------------------------------------------------------------
# 5. Absolute Dollar Thresholds
# -----------------------------------------------------------------------------

cat("Computing absolute dollar threshold treatment dates...\n")

# Define dollar thresholds (cumulative handle)
dollar_thresholds <- c(100e6, 500e6, 1e9)  # $100M, $500M, $1B

# Function to find first month reaching cumulative handle threshold
find_dollar_threshold_date <- function(data, threshold) {
  data %>%
    group_by(State) %>%
    arrange(State, month_date) %>%
    mutate(
      cumulative_handle = cumsum(Handle)
    ) %>%
    filter(cumulative_handle >= threshold) %>%
    summarise(
      treat_date = min(month_date),
      .groups = "drop"
    ) %>%
    rename(!!paste0("treat_", threshold/1e6, "M") := treat_date)
}

# Calculate for each threshold
dollar_dates_list <- lapply(dollar_thresholds, function(threshold) {
  cat("  $", threshold/1e6, "M cumulative threshold...\n")
  find_dollar_threshold_date(handle_data, threshold)
})

# Merge all dollar thresholds
dollar_dates <- dollar_dates_list[[1]]
for (i in 2:length(dollar_dates_list)) {
  dollar_dates <- dollar_dates %>%
    left_join(dollar_dates_list[[i]], by = "State")
}

cat("  Dollar thresholds calculated for varying states\n\n")

# -----------------------------------------------------------------------------
# 6. Combine with Legal Dates and State Abbreviations
# -----------------------------------------------------------------------------

cat("Merging with legal dates and state abbreviations...\n")

# Add state abbreviations
activity_dates <- pct_dates %>%
  left_join(dollar_dates, by = "State") %>%
  left_join(state_crosswalk, by = c("State" = "state_name")) %>%
  dplyr::select(state_abb, State, everything())

# Add legal online start dates for comparison
# gambling_dates uses full state names in 'state' column, matching handle data 'State' column
activity_dates <- activity_dates %>%
  left_join(
    gambling_dates %>% dplyr::select(state, online_start_date),
    by = c("State" = "state")
  ) %>%
  rename(legal_online_start = online_start_date)

cat("  Final dataset has", nrow(activity_dates), "states\n")
cat("  Variables:", paste(names(activity_dates), collapse = ", "), "\n\n")

# -----------------------------------------------------------------------------
# 7. Calculate Time Lags (Legal to Activity Threshold)
# -----------------------------------------------------------------------------

cat("Calculating time lags from legal date to activity thresholds...\n")

activity_dates <- activity_dates %>%
  mutate(
    # Months from legal to 50% peak
    lag_to_50pct = ifelse(
      !is.na(legal_online_start) & !is.na(treat_50pct_peak),
      interval(legal_online_start, treat_50pct_peak) %/% months(1),
      NA_integer_
    ),
    # Months from legal to $500M
    lag_to_500M = ifelse(
      !is.na(legal_online_start) & !is.na(treat_500M),
      interval(legal_online_start, treat_500M) %/% months(1),
      NA_integer_
    ),
    # Months from legal to $1B
    lag_to_1000M = ifelse(
      !is.na(legal_online_start) & !is.na(`treat_1000M`),
      interval(legal_online_start, `treat_1000M`) %/% months(1),
      NA_integer_
    )
  )

# Summary statistics
cat("\nTime lag summary (legal to 50% of peak):\n")
lag_summary <- activity_dates %>%
  filter(!is.na(lag_to_50pct)) %>%
  summarise(
    min = min(lag_to_50pct),
    q25 = quantile(lag_to_50pct, 0.25),
    median = median(lag_to_50pct),
    q75 = quantile(lag_to_50pct, 0.75),
    max = max(lag_to_50pct)
  )
print(lag_summary)

cat("\nStates with longest lag to 50% peak:\n")
activity_dates %>%
  filter(!is.na(lag_to_50pct)) %>%
  arrange(desc(lag_to_50pct)) %>%
  dplyr::select(state_abb, State, legal_online_start, treat_50pct_peak, lag_to_50pct) %>%
  head(5) %>%
  print()

cat("\nStates with shortest lag to 50% peak:\n")
activity_dates %>%
  filter(!is.na(lag_to_50pct)) %>%
  arrange(lag_to_50pct) %>%
  dplyr::select(state_abb, State, legal_online_start, treat_50pct_peak, lag_to_50pct) %>%
  head(5) %>%
  print()

# -----------------------------------------------------------------------------
# 8. Coverage Analysis
# -----------------------------------------------------------------------------

cat("\n", strrep("=", 80), "\n")
cat("Coverage Analysis\n")
cat(strrep("=", 80), "\n\n")

coverage <- tibble(
  Threshold = c("Legal (online)", "10% of peak", "25% of peak", "50% of peak",
                "75% of peak", "$100M cumulative", "$500M cumulative", "$1B cumulative"),
  `States Meeting` = c(
    sum(!is.na(activity_dates$legal_online_start)),
    sum(!is.na(activity_dates$treat_10pct_peak)),
    sum(!is.na(activity_dates$treat_25pct_peak)),
    sum(!is.na(activity_dates$treat_50pct_peak)),
    sum(!is.na(activity_dates$treat_75pct_peak)),
    sum(!is.na(activity_dates$treat_100M)),
    sum(!is.na(activity_dates$treat_500M)),
    sum(!is.na(activity_dates$`treat_1000M`))
  )
)

print(coverage)

cat("\nRECOMMENDATION:\n")
cat("  Primary: 50% of peak (", sum(!is.na(activity_dates$treat_50pct_peak)),
    " states, median lag = ", lag_summary$median, " months)\n")
cat("  Alternative 1: $500M cumulative (", sum(!is.na(activity_dates$treat_500M)), " states)\n")
cat("  Alternative 2: $1B cumulative (", sum(!is.na(activity_dates$`treat_1000M`)), " states)\n\n")

# -----------------------------------------------------------------------------
# 9. Save Output
# -----------------------------------------------------------------------------

output_file <- "data/processed/activity_treatment_dates.csv"
cat("Saving activity-based treatment dates to:", output_file, "\n")

# Create output directory if needed
dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)

# Save
write_csv(activity_dates, output_file)

cat("  Saved", nrow(activity_dates), "rows,", ncol(activity_dates), "columns\n\n")

cat(strrep("=", 80), "\n")
cat("Activity-based treatment dates created successfully!\n")
cat(strrep("=", 80), "\n\n")

cat("Next steps:\n")
cat("  1. Review: data/processed/activity_treatment_dates.csv\n")
cat("  2. Add specifications to pretrends_modern.R using these dates\n")
cat("  3. Compare pre-trends: legal dates vs. activity-based dates\n\n")
