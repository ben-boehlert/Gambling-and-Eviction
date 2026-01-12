#!/usr/bin/env Rscript
################################################################################
# check_panel_size.R
# Quick diagnostic to show panel sizes for different configurations
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

# Helper functions
getenv1 <- function(key, default = "") {
  v <- Sys.getenv(key, unset = default)
  if (!nzchar(v)) default else v
}

ym_index <- function(date) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
}

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

build_state_panel <- function(df) {
  county_state <- df %>%
    dplyr::filter(geo_level == "county") %>%
    dplyr::mutate(
      fips_num = suppressWarnings(as.integer(fips)),
      state_fips = as.integer(floor(fips_num / 1000)),
      state_abb = fips_to_state_abb(state_fips),
      month_date = as.Date(month_date),
      filings_count = as.numeric(filings_count),
      renter_occupied_housing_units = as.numeric(renter_occupied_housing_units)
    ) %>%
    dplyr::filter(!is.na(state_abb), !is.na(month_date)) %>%
    dplyr::group_by(state_abb, month_date) %>%
    dplyr::summarise(
      filings_count = sum(filings_count, na.rm = TRUE),
      renter_occupied_housing_units = sum(renter_occupied_housing_units, na.rm = TRUE),
      .groups = "drop"
    )

  county_states <- unique(county_state$state_abb)

  state_fallback <- df %>%
    dplyr::filter(geo_level == "state") %>%
    dplyr::transmute(
      state_abb = state_abbr_from_geoid(geo_id),
      month_date = as.Date(month_date),
      filings_count = as.numeric(filings_count),
      renter_occupied_housing_units = as.numeric(renter_occupied_housing_units)
    ) %>%
    dplyr::filter(!is.na(state_abb), !is.na(month_date)) %>%
    dplyr::filter(!(state_abb %in% county_states))

  out <- dplyr::bind_rows(county_state, state_fallback) %>%
    dplyr::arrange(state_abb, month_date)

  out
}

state_abbr_from_geoid <- function(geo_id) {
  x <- tolower(trimws(as.character(geo_id)))
  key <- gsub("[^a-z]", "", x)
  name_key <- gsub("[^a-z]", "", tolower(state.name))
  m <- setNames(state.abb, name_key)
  unname(m[key])
}

# Load data
DATA_FILE <- getenv1("DATA_FILE", "combined_monthly_panel.csv")
TREAT_FILE <- getenv1("TREAT_FILE", "state_month_panel_with_treatment.csv")

cat("Loading data...\n")
df_all <- readr::read_csv(DATA_FILE, show_col_types = FALSE)
panel_raw <- build_state_panel(df_all)

treat <- readr::read_csv(TREAT_FILE, show_col_types = FALSE) %>%
  transmute(
    state_abb = as.character(state_abb),
    month_date = as.Date(month_date),
    treat_start = as.Date(treat_start),
    treated = as.logical(treated)
  ) %>%
  arrange(state_abb, month_date)

panel <- panel_raw %>%
  left_join(treat, by = c("state_abb", "month_date")) %>%
  filter(state_abb %in% unique(treat$state_abb))

# Scenario 1: Exclude ME, extend to 2024-12-31
panel1 <- panel %>%
  filter(state_abb != "ME") %>%
  filter(month_date <= as.Date("2024-12-31"))

# Add treatment indicators
panel1 <- panel1 %>%
  group_by(state_abb) %>%
  mutate(treat_start_state = if (all(is.na(treat_start))) as.Date(NA) else min(treat_start, na.rm = TRUE)) %>%
  ungroup() %>%
  mutate(
    t = ym_index(month_date),
    g = ifelse(is.na(treat_start_state), 0L, ym_index(treat_start_state)),
    g = as.integer(g),
    untreated_obs = (g == 0L) | (t < g)
  )

# Count state-months
cat("\n=== WITHOUT COVID EXCLUSION (full 2016-2024) ===\n")
cat("Total state-months:", nrow(panel1), "\n")
cat("Untreated state-months:", sum(panel1$untreated_obs, na.rm = TRUE), "\n")
cat("Treated state-months:", sum(!panel1$untreated_obs, na.rm = TRUE), "\n")
cat("Unique states:", n_distinct(panel1$state_abb), "\n")
cat("Date range:", min(panel1$month_date), "to", max(panel1$month_date), "\n")

# Check COVID period
covid_period <- panel1 %>%
  filter(month_date >= as.Date("2020-03-01") & month_date < as.Date("2021-06-01"))
cat("COVID period (2020-03-01 to 2021-06-01) state-months:", nrow(covid_period), "\n")
cat("COVID period untreated state-months:", sum(covid_period$untreated_obs, na.rm = TRUE), "\n")

# Non-COVID period
non_covid <- panel1 %>%
  filter(!(month_date >= as.Date("2020-03-01") & month_date < as.Date("2021-06-01")))
cat("\n=== WITH COVID EXCLUSION (excluding 2020-03 to 2021-06) ===\n")
cat("Non-COVID state-months:", nrow(non_covid), "\n")
cat("Non-COVID untreated state-months:", sum(non_covid$untreated_obs, na.rm = TRUE), "\n")
cat("Non-COVID treated state-months:", sum(!non_covid$untreated_obs, na.rm = TRUE), "\n")

# Check late period (2023+)
late_period <- panel1 %>% filter(month_date >= as.Date("2023-01-01"))
cat("\n=== LATE PERIOD (2023+) ===\n")
cat("Late period state-months:", nrow(late_period), "\n")
cat("Late period untreated state-months:", sum(late_period$untreated_obs, na.rm = TRUE), "\n")
cat("Late period treated state-months:", sum(!late_period$untreated_obs, na.rm = TRUE), "\n")

# Check how many states untreated per month in late period
late_untreated_by_month <- late_period %>%
  filter(untreated_obs) %>%
  group_by(month_date) %>%
  summarise(n_untreated_states = n_distinct(state_abb), .groups = "drop") %>%
  arrange(month_date)

cat("\nUntreated states per month in 2023+:\n")
print(late_untreated_by_month, n = Inf)

cat("\n=== SUMMARY ===\n")
cat("Months with <5 untreated states:", sum(late_untreated_by_month$n_untreated_states < 5), "\n")
cat("Months with <15 untreated states:", sum(late_untreated_by_month$n_untreated_states < 15), "\n")
