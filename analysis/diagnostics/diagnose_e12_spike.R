#!/usr/bin/env Rscript
################################################################################
# diagnose_e12_spike.R
#
# Diagnostic to understand why SE spikes at e=-12 then drops at e=-11
################################################################################

library(dplyr)
library(readr)

# Helper functions (copied from main script)
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

state_name_to_abb <- function(state_name) {
  state_name <- trimws(state_name)
  m <- setNames(state.abb, state.name)
  m2 <- c(m, "District of Columbia" = "DC")
  unname(m2[state_name])
}

state_abbr_from_geoid <- function(geo_id) {
  x <- tolower(trimws(as.character(geo_id)))
  key <- gsub("[^a-z]", "", x)
  name_key <- gsub("[^a-z]", "", tolower(state.name))
  m <- setNames(state.abb, name_key)
  unname(m[key])
}

ym_index <- function(date) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
}

# Build state panel
cat("Loading data...\n")
df_all <- readr::read_csv("data/raw/combined_monthly_panel.csv", show_col_types = FALSE)

county_state <- df_all %>%
  filter(geo_level == "county") %>%
  mutate(
    fips_num = suppressWarnings(as.integer(fips)),
    state_fips = as.integer(floor(fips_num / 1000)),
    state_abb = fips_to_state_abb(state_fips),
    month_date = as.Date(month_date),
    filings_count = as.numeric(filings_count)
  ) %>%
  filter(!is.na(state_abb), !is.na(month_date)) %>%
  group_by(state_abb, month_date) %>%
  summarise(filings_count = sum(filings_count, na.rm = TRUE), .groups = "drop")

county_states <- unique(county_state$state_abb)

state_fallback <- df_all %>%
  filter(geo_level == "state") %>%
  transmute(
    state_abb = state_abbr_from_geoid(geo_id),
    month_date = as.Date(month_date),
    filings_count = as.numeric(filings_count)
  ) %>%
  filter(!is.na(state_abb), !is.na(month_date)) %>%
  filter(!(state_abb %in% county_states))

panel_raw <- bind_rows(county_state, state_fallback) %>%
  arrange(state_abb, month_date)

# Load gambling dates
gambling_raw <- readr::read_csv("data/raw/sports_gambling_legalization_dates.csv", show_col_types = FALSE)
gambling_dates <- gambling_raw %>%
  mutate(
    state_abb = state_name_to_abb(state),
    online_start_date = as.Date(online_start_date, format = "%Y-%m-%d")
  ) %>%
  dplyr::select(state_abb, online_start_date) %>%
  filter(!is.na(state_abb))

all_states <- tibble(state_abb = unique(panel_raw$state_abb))
gambling_dates <- all_states %>% left_join(gambling_dates, by = "state_abb")

# Build baseline panel
panel <- panel_raw %>%
  filter(state_abb != "ME") %>%  # Exclude Maine
  left_join(gambling_dates, by = "state_abb") %>%
  mutate(
    t = ym_index(month_date),
    g = ifelse(is.na(online_start_date), 0L, ym_index(online_start_date)),
    g = as.integer(g),
    id = as.integer(as.factor(state_abb)),
    e = if_else(g > 0L, as.integer(t - g), NA_integer_),
    y = log1p(pmax(as.numeric(filings_count), 0))
  ) %>%
  filter(!is.na(y))

cat("\nPanel constructed. Total states:", n_distinct(panel$state_abb), "\n")

# Diagnostic 1: Panel balance around e=-12
cat("\n=== DIAGNOSTIC 1: Panel Balance Around e=-12 ===\n")

balance <- panel %>%
  filter(!is.na(e), e >= -15, e <= -9) %>%
  group_by(e) %>%
  summarise(
    n_states = n_distinct(state_abb),
    n_obs = n(),
    total_filings = sum(filings_count, na.rm = TRUE),
    avg_filings = mean(filings_count, na.rm = TRUE),
    var_filings = var(filings_count, na.rm = TRUE),
    .groups = "drop"
  )

print(balance)

# Diagnostic 2: Which states are present at each event time?
cat("\n=== DIAGNOSTIC 2: State Composition at Each Event Time ===\n")

states_by_e <- panel %>%
  filter(!is.na(e), e >= -15, e <= -9) %>%
  group_by(e) %>%
  summarise(states = paste(sort(unique(state_abb)), collapse = ", "), .groups = "drop")

# Check if e=-12 has different states
states_e13 <- panel %>% filter(e == -13) %>% pull(state_abb) %>% unique() %>% sort()
states_e12 <- panel %>% filter(e == -12) %>% pull(state_abb) %>% unique() %>% sort()
states_e11 <- panel %>% filter(e == -11) %>% pull(state_abb) %>% unique() %>% sort()

missing_at_e12 <- setdiff(states_e13, states_e12)
added_at_e12 <- setdiff(states_e12, states_e13)

cat("\nStates at e=-13:", length(states_e13), "\n")
cat("States at e=-12:", length(states_e12), "\n")
cat("States at e=-11:", length(states_e11), "\n")

if (length(missing_at_e12) > 0) {
  cat("\nStates MISSING at e=-12 (present at e=-13):\n")
  cat(paste(missing_at_e12, collapse = ", "), "\n")
}

if (length(added_at_e12) > 0) {
  cat("\nStates ADDED at e=-12 (not present at e=-13):\n")
  cat(paste(added_at_e12, collapse = ", "), "\n")
}

# Diagnostic 3: Check observations in Jan 2019 specifically
cat("\n=== DIAGNOSTIC 3: January 2019 Data ===\n")

jan2019 <- panel_raw %>%
  filter(month_date == as.Date("2019-01-01")) %>%
  arrange(state_abb) %>%
  select(state_abb, filings_count)

dec2018 <- panel_raw %>%
  filter(month_date == as.Date("2018-12-01")) %>%
  arrange(state_abb) %>%
  select(state_abb, filings_count)

cat("\nStates in Dec 2018:", nrow(dec2018), "\n")
cat("States in Jan 2019:", nrow(jan2019), "\n")

states_dec <- dec2018$state_abb
states_jan <- jan2019$state_abb

missing_jan <- setdiff(states_dec, states_jan)
added_jan <- setdiff(states_jan, states_dec)

if (length(missing_jan) > 0) {
  cat("\nStates with data in Dec 2018 but NOT Jan 2019:\n")
  cat(paste(missing_jan, collapse = ", "), "\n")
}

if (length(added_jan) > 0) {
  cat("\nStates with data in Jan 2019 but NOT Dec 2018:\n")
  cat(paste(added_jan, collapse = ", "), "\n")
}

# Diagnostic 4: Variance decomposition
cat("\n=== DIAGNOSTIC 4: Variance Pattern ===\n")

var_pattern <- panel %>%
  filter(!is.na(e), e >= -15, e <= -9) %>%
  group_by(e) %>%
  summarise(
    var_y = var(y, na.rm = TRUE),
    sd_y = sd(y, na.rm = TRUE),
    .groups = "drop"
  )

print(var_pattern)

cat("\n=== CONCLUSION ===\n")
cat("If n_states or n_obs changes at e=-12, that explains the SE spike.\n")
cat("If variance spikes at e=-12, that also contributes.\n")
cat("Check above diagnostics for the specific cause.\n")
