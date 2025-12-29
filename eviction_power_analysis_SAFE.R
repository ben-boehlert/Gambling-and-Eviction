################################################################################
# SAFE VERSION - Simulated Power Analysis for Eviction-Gambling Study
# Following Black et al. (2021) and Burlig et al. (2020) Methodology
################################################################################

# This version removes dependencies that might cause crashes
library(tidyverse)
library(fixest)
library(lubridate)

set.seed(20251224)

cat("=================================================================================\n")
cat("SIMULATED POWER ANALYSIS: Sports Gambling -> Eviction Filings\n")
cat("=================================================================================\n\n")

################################################################################
# 1. DATA PREPARATION
################################################################################

cat("Step 1: Loading data files...\n")

# Load data with error handling
county_monthly <- tryCatch({
  read_csv("monthly_county_data_download.csv", show_col_types = FALSE)
}, error = function(e) {
  stop("Error loading county data: ", e$message)
})

sites_monthly <- tryCatch({
  read_csv("all_sites_monthly_2020_2021.csv", show_col_types = FALSE)
}, error = function(e) {
  stop("Error loading sites data: ", e$message)
})

gambling_dates <- tryCatch({
  read_csv("sports_gambling_legalization_dates.csv", show_col_types = FALSE)
}, error = function(e) {
  stop("Error loading gambling dates: ", e$message)
})

cat(sprintf("  County data: %d rows\n", nrow(county_monthly)))
cat(sprintf("  Sites data: %d rows\n", nrow(sites_monthly)))
cat(sprintf("  Gambling dates: %d states\n\n", nrow(gambling_dates)))

################################################################################
# Build Panel 1: County data -> State-month
################################################################################

cat("Step 2: Building Panel 1 (County data -> State-month)...\n")

panel1 <- county_monthly %>%
  mutate(
    date = ymd_hms(date),
    year_month = floor_date(date, "month"),
    state_fips = str_sub(as.character(fips), 1, 2)
  ) %>%
  group_by(state_fips, year_month) %>%
  summarise(
    filings = sum(filings_count, na.rm = TRUE),
    renter_hh = sum(renter_occupied_housing_units, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  filter(!is.na(state_fips), renter_hh > 0) %>%
  mutate(
    filings_per_1000_renters = (filings / renter_hh) * 1000
  )

cat(sprintf("  Panel 1: %d state-months, %d states\n\n",
            nrow(panel1), n_distinct(panel1$state_fips)))

################################################################################
# Build Panel 2: Sites data -> State-month
################################################################################

cat("Step 3: Building Panel 2 (Sites data -> State-month)...\n")

# State FIPS mapping
state_fips_map <- tibble(
  state_abbrev = c(state.abb, "DC"),
  state_fips = c(sprintf("%02d", 1:50), "11")
)

panel2_raw <- sites_monthly %>%
  mutate(
    state_abbrev = str_trim(str_extract(city, "[A-Z]{2}$")),
    year_month = my(month)
  ) %>%
  filter(!is.na(state_abbrev), !is.na(year_month))

panel2 <- panel2_raw %>%
  left_join(state_fips_map, by = "state_abbrev") %>%
  filter(!is.na(state_fips)) %>%
  group_by(state_fips, year_month) %>%
  summarise(
    filings_2020 = sum(filings_2020, na.rm = TRUE),
    .groups = "drop"
  )

# Get renter denominator from county data
renter_by_state <- county_monthly %>%
  mutate(state_fips = str_sub(as.character(fips), 1, 2)) %>%
  group_by(state_fips) %>%
  summarise(
    renter_hh = median(renter_occupied_housing_units, na.rm = TRUE),
    .groups = "drop"
  )

panel2 <- panel2 %>%
  left_join(renter_by_state, by = "state_fips") %>%
  mutate(
    filings = filings_2020,
    filings_per_1000_renters = (filings / renter_hh) * 1000
  ) %>%
  filter(!is.na(filings_per_1000_renters), renter_hh > 0)

cat(sprintf("  Panel 2: %d state-months, %d states\n\n",
            nrow(panel2), n_distinct(panel2$state_fips)))

################################################################################
# Merge gambling dates
################################################################################

cat("Step 4: Merging gambling legalization dates...\n")

gambling_dates_clean <- gambling_dates %>%
  left_join(state_fips_map, by = c("state" = "state_abbrev")) %>%
  filter(!is.na(state_fips)) %>%
  mutate(treatment_date = ymd(first_start_date)) %>%
  select(state_fips, treatment_date)

panel1 <- panel1 %>%
  left_join(gambling_dates_clean, by = "state_fips") %>%
  mutate(
    treated_state = !is.na(treatment_date),
    post_treatment = if_else(treated_state & year_month >= treatment_date, 1, 0, missing = 0)
  )

cat(sprintf("  Treated states in panel 1: %d\n",
            sum(panel1 %>% distinct(state_fips, treated_state) %>% pull(treated_state))))
cat(sprintf("  Never-treated states: %d\n\n",
            sum(!(panel1 %>% distinct(state_fips, treated_state) %>% pull(treated_state)))))

################################################################################
# Create analysis panel
################################################################################

analysis_panel <- panel1 %>%
  mutate(
    state = state_fips,
    month = year_month,
    outcome = filings_per_1000_renters
  ) %>%
  select(state, month, outcome, treated_state, post_treatment, treatment_date) %>%
  arrange(state, month)

cat(sprintf("Analysis panel created: %d observations, %d states, %d months\n",
            nrow(analysis_panel),
            n_distinct(analysis_panel$state),
            n_distinct(analysis_panel$month)))
cat(sprintf("Date range: %s to %s\n\n",
            min(analysis_panel$month), max(analysis_panel$month)))

################################################################################
# Calibrate error process from UNTREATED data only
################################################################################

cat("=================================================================================\n")
cat("CALIBRATING ERROR PROCESS (UNTREATED DATA ONLY)\n")
cat("=================================================================================\n\n")

# Identify untreated observations
untreated_data <- analysis_panel %>%
  filter(!treated_state | (treated_state & post_treatment == 0))

cat(sprintf("Untreated data: %d observations from %d states\n\n",
            nrow(untreated_data), n_distinct(untreated_data$state)))

# Estimate baseline model
cat("Estimating baseline model: outcome ~ 1 | state + month\n")

baseline_model <- feols(
  outcome ~ 1 | state + month,
  data = untreated_data,
  cluster = ~state
)

print(summary(baseline_model))

# Extract residuals
untreated_data$residual <- resid(baseline_model)

# Calculate basic error statistics
error_stats <- untreated_data %>%
  group_by(state) %>%
  summarise(
    sigma2 = var(residual, na.rm = TRUE),
    n_obs = n(),
    .groups = "drop"
  )

cat("\n")
cat(sprintf("Mean residual variance (sigma^2): %.4f\n", mean(error_stats$sigma2, na.rm = TRUE)))
cat(sprintf("Median observations per state: %.0f\n\n", median(error_stats$n_obs)))

################################################################################
# Save workspace
################################################################################

cat("Saving workspace...\n")
save(
  analysis_panel,
  untreated_data,
  baseline_model,
  error_stats,
  gambling_dates_clean,
  file = "eviction_power_workspace_SAFE.RData"
)

cat("\n=================================================================================\n")
cat("DATA PREPARATION COMPLETE\n")
cat("=================================================================================\n\n")
cat("Output saved to: eviction_power_workspace_SAFE.RData\n")
cat("Next: Run power simulations\n\n")
