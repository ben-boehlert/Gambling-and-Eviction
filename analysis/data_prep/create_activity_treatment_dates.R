#!/usr/bin/env Rscript

# =============================================================================
# Create Activity-Based Treatment Dates
# =============================================================================
# Purpose: Generate treatment dates based on gambling handle activity thresholds
# Approach: Use percentage-of-peak and absolute dollar thresholds
# Output: activity_treatment_dates.csv with multiple threshold definitions
#         plus a state-level treatment/control classification and codebook
#
# 2026-08-14 revision (mirrors data_prep/build_panel_handle50_treatment.R;
# original output preserved in data/processed/deprecated/):
#   1. Restricted to states with a verified ONLINE start date (drops NV --
#      absent from the schedule, online pre-PASPA -- and retail-only MS/MT).
#   2. All thresholds computed on ONLINE-ERA handle only (months >= online
#      start), so no retail-era artifact (DE was previously dated 2018-09,
#      64 months before its Jan 2024 online launch) and all lags are >= 0.
#   3. COVID window default aligned to the power-framework protocol
#      (2020-03-01..2021-07-31), env-overridable; do not mix with the
#      2022-03-31 calibration convention or the Sep-2021 eviction-recovery
#      month unawares.

library(dplyr)
library(readr)
library(lubridate)

PANEL_FILE <- Sys.getenv(
  "PANEL_IN",
  "data/raw/state_month_panel_with_treatment.csv"
)
HANDLE_FILE <- Sys.getenv(
  "HANDLE_FILE",
  "data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv"
)
SCHEDULE_FILE <- Sys.getenv(
  "SCHEDULE_FILE",
  "data/raw/sports_gambling_legalization_dates.csv"
)
OUTPUT_FILE <- Sys.getenv(
  "ACTIVITY_OUT_FILE",
  "data/processed/activity_treatment_dates.csv"
)
CLASSIFICATION_FILE <- Sys.getenv(
  "CLASSIFICATION_FILE",
  "data/processed/handle50_state_classification.csv"
)
CODEBOOK_FILE <- Sys.getenv(
  "CODEBOOK_FILE",
  "data/processed/handle50_state_classification_codebook.csv"
)

PEAK_CALIBRATION_END <- as.Date(Sys.getenv("PEAK_CALIBRATION_END", "2024-12-31"))
STUDY_START <- as.Date(Sys.getenv("STUDY_START", "2016-01-01"))
if (is.na(PEAK_CALIBRATION_END) || is.na(STUDY_START)) {
  stop("STUDY_START and PEAK_CALIBRATION_END must be valid YYYY-MM-DD dates")
}

source(file.path("data_prep", "handle_state_classification.R"))

# Peak-base COVID exclusion: default = power-framework protocol window.
COVID_START <- as.Date(Sys.getenv("COVID_START", "2020-03-01"))
COVID_END <- as.Date(Sys.getenv("COVID_END", "2021-07-31"))

# -----------------------------------------------------------------------------
# 1. Load Data
# -----------------------------------------------------------------------------

cat("\n")
cat(strrep("=", 80), "\n")
cat("Activity-Based Treatment Date Generation\n")
cat(strrep("=", 80), "\n\n")

# Load gambling handle data
cat("Loading handle data from:", HANDLE_FILE, "\n")
handle_data <- read_csv(HANDLE_FILE, show_col_types = FALSE)

handle_calibration <- handle_data %>%
  mutate(month_date = as.Date(month_date)) %>%
  filter(
    month_date <= PEAK_CALIBRATION_END,
    !is.na(Handle),
    Handle >= 0
  )

cat("  States with handle data:", n_distinct(handle_data$State), "\n")
cat(
  "  Date range:",
  as.character(min(handle_data$month_date)), "to",
  as.character(max(handle_data$month_date)),
  "\n\n"
)
cat("  Calibration cutoff:", as.character(PEAK_CALIBRATION_END), "\n")
cat(
  "  Peak COVID exclusion:",
  as.character(COVID_START), "to", as.character(COVID_END),
  "\n"
)
cat("  Calibration states:", n_distinct(handle_calibration$State), "\n")
cat(
  "  Calibration date range:",
  as.character(min(handle_calibration$month_date)), "to",
  as.character(max(handle_calibration$month_date)),
  "\n\n"
)

# Load existing treatment dates for comparison
cat("Loading legal dates from:", SCHEDULE_FILE, "\n")
gambling_dates <- read_csv(SCHEDULE_FILE, show_col_types = FALSE)

# --- Restrict to online states and online-era handle (2026-08-14 fix) -------
# NV never appears in the schedule (online pre-PASPA) and retail-only states
# (MS, MT) have no online date; both are excluded here. Handle months before
# a state's online start are retail-era and never enter peaks or thresholds.
online_universe <- gambling_dates %>%
  filter(!is.na(online_start_date)) %>%
  transmute(State = state, online_start = as.Date(online_start_date))

excluded_states <- setdiff(unique(handle_calibration$State),
                           online_universe$State)
if (length(excluded_states) > 0) {
  cat("  Excluded (no online start date):",
      paste(sort(excluded_states), collapse = ", "), "\n")
}

handle_calibration <- handle_calibration %>%
  inner_join(online_universe, by = "State") %>%
  filter(month_date >= online_start) %>%
  dplyr::select(-online_start)

cat("  Online-era calibration sample:", nrow(handle_calibration), "rows,",
    n_distinct(handle_calibration$State), "states\n")

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

peak_analysis <- handle_calibration %>%
  filter(month_date < COVID_START | month_date > COVID_END) %>%
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
  find_pct_threshold_date(handle_calibration, pct)
})

# Merge all percentage thresholds.
pct_dates <- Reduce(
  function(x, y) left_join(x, y, by = "State"),
  pct_dates_list
)

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
  find_dollar_threshold_date(handle_calibration, threshold)
})

# Merge all dollar thresholds.
dollar_dates <- Reduce(
  function(x, y) left_join(x, y, by = "State"),
  dollar_dates_list
)

cat("  Dollar thresholds calculated for varying states\n\n")

# -----------------------------------------------------------------------------
# 6. Combine with Legal Dates and State Abbreviations
# -----------------------------------------------------------------------------

cat("Merging thresholds and classifying all panel states...\n")

activity_metrics <- pct_dates %>%
  left_join(dollar_dates, by = "State") %>%
  left_join(state_crosswalk, by = c("State" = "state_name")) %>%
  dplyr::select(state_abb, State, everything())

panel_states <- read_csv(PANEL_FILE, show_col_types = FALSE) %>%
  distinct(state_abb) %>%
  pull(state_abb)

state_classification <- classify_handle_states(
  panel_states = panel_states,
  legal_schedule = gambling_dates,
  threshold_dates = activity_metrics %>%
    transmute(
      state_abb,
      handle_threshold_start = treat_50pct_peak
    ),
  handle_data_states = state_name_to_abb(unique(handle_calibration$State)),
  study_start = STUDY_START,
  study_cutoff = PEAK_CALIBRATION_END,
  threshold_fraction = 0.5
)

stopifnot(
  state_classification$handle_treatment_status[
    state_classification$state_abb == "FL"
  ] == "legally_online_missing_handle",
  !state_classification$control_eligible[
    state_classification$state_abb == "FL"
  ],
  state_classification$handle_treatment_status[
    state_classification$state_abb == "NV"
  ] == "pre_sample_treated",
  !state_classification$analysis_eligible[
    state_classification$state_abb == "NV"
  ]
)

# Retain the legacy threshold columns, but extend the file to the full panel
# universe so missing exposure and valid untreated controls are distinguishable.
activity_dates <- state_classification %>%
  rename(State = state_name) %>%
  left_join(
    activity_metrics %>% select(-State),
    by = "state_abb"
  )

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
  Threshold = c("Legal online by cutoff", "10% of peak", "25% of peak", "50% of peak",
                "75% of peak", "$100M cumulative", "$500M cumulative", "$1B cumulative"),
  `States Meeting` = c(
    sum(
      !is.na(activity_dates$legal_online_start) &
        activity_dates$legal_online_start <= PEAK_CALIBRATION_END
    ),
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

cat("Saving activity-based treatment dates to:", OUTPUT_FILE, "\n")

# Create output directory if needed
dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)

# Save
classification_codebook <- handle_classification_codebook()
write_csv(activity_dates, OUTPUT_FILE)
write_csv(state_classification, CLASSIFICATION_FILE)
write_csv(classification_codebook, CODEBOOK_FILE)
saveRDS(activity_dates, paired_rds_path(OUTPUT_FILE))
saveRDS(state_classification, paired_rds_path(CLASSIFICATION_FILE))
saveRDS(classification_codebook, paired_rds_path(CODEBOOK_FILE))

cat("  Saved", nrow(activity_dates), "rows,", ncol(activity_dates), "columns\n\n")
cat("  Saved state classification:", CLASSIFICATION_FILE, "\n")
cat("  Saved classification codebook:", CODEBOOK_FILE, "\n\n")
cat("  Saved paired RDS checkpoints for all three outputs\n\n")

cat(strrep("=", 80), "\n")
cat("Activity-based treatment dates created successfully!\n")
cat(strrep("=", 80), "\n\n")

cat("Next steps:\n")
cat("  1. Review: data/processed/activity_treatment_dates.csv\n")
cat("  2. Add specifications to pretrends_modern.R using these dates\n")
cat("  3. Compare pre-trends: legal dates vs. activity-based dates\n\n")
