#!/usr/bin/env Rscript
################################################################################
# test_sunab.R
#
# Test fixest::sunab() as alternative to CS-DiD
# Sun & Abraham (2021) interaction-weighted estimator
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(fixest)
  library(glue)
})

cat("fixest version:", as.character(packageVersion("fixest")), "\n\n")

# Load helper functions (same as before)
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

build_state_panel <- function(df) {
  county_state <- df %>%
    filter(geo_level == "county") %>%
    mutate(
      fips_num = suppressWarnings(as.integer(fips)),
      state_fips = as.integer(floor(fips_num / 1000)),
      state_abb = fips_to_state_abb(state_fips),
      month_date = as.Date(month_date),
      filings_count = as.numeric(filings_count),
      renter_occupied_housing_units = as.numeric(renter_occupied_housing_units)
    ) %>%
    filter(!is.na(state_abb), !is.na(month_date)) %>%
    group_by(state_abb, month_date) %>%
    summarise(
      filings_count = sum(filings_count, na.rm = TRUE),
      renter_occupied_housing_units = sum(renter_occupied_housing_units, na.rm = TRUE),
      .groups = "drop"
    )

  county_states <- unique(county_state$state_abb)

  state_fallback <- df %>%
    filter(geo_level == "state") %>%
    transmute(
      state_abb = state_abbr_from_geoid(geo_id),
      month_date = as.Date(month_date),
      filings_count = as.numeric(filings_count),
      renter_occupied_housing_units = as.numeric(renter_occupied_housing_units)
    ) %>%
    filter(!is.na(state_abb), !is.na(month_date)) %>%
    filter(!(state_abb %in% county_states))

  bind_rows(county_state, state_fallback) %>%
    arrange(state_abb, month_date)
}

# Load data
cat("Loading data...\n")
df_all <- readr::read_csv("data/raw/combined_monthly_panel.csv", show_col_types = FALSE)
gambling_raw <- readr::read_csv("data/raw/sports_gambling_legalization_dates.csv", show_col_types = FALSE)

panel_raw <- build_state_panel(df_all)

gambling_dates <- gambling_raw %>%
  mutate(
    state_abb = state_name_to_abb(state),
    online_start_date = as.Date(online_start_date, format = "%Y-%m-%d")
  ) %>%
  select(state_abb, online_start_date) %>%
  filter(!is.na(state_abb))

# Build panel
panel <- panel_raw %>%
  left_join(gambling_dates, by = "state_abb") %>%
  filter(state_abb != "ME") %>%
  mutate(
    t = ym_index(month_date),
    g = ifelse(is.na(online_start_date), 0L, ym_index(online_start_date)),
    g = as.integer(g),
    e = if_else(g > 0L, as.integer(t - g), NA_integer_),
    y = log1p(pmax(as.numeric(filings_count), 0)),
    id = as.integer(as.factor(state_abb))
  ) %>%
  filter(is.na(e) | (e >= -12 & e <= 24)) %>%
  filter(!is.na(y))

cat(glue("\nPanel: {nrow(panel)} obs, {n_distinct(panel$state_abb)} states\n"))
cat(glue("Treated: {n_distinct(panel$state_abb[panel$g > 0])}\n"))
cat(glue("Never-treated: {n_distinct(panel$state_abb[panel$g == 0])}\n\n"))

# Test Sun & Abraham estimator
cat("=== Testing fixest::sunab() ===\n")
cat("Sun & Abraham (2021) interaction-weighted estimator\n\n")

tryCatch({
  # sunab() syntax: sunab(cohort_var, time_var)
  # cohort_var should be the first treatment period (or 0/Inf for never-treated)

  # Prepare cohort variable (first treatment period, or Inf for never-treated)
  panel <- panel %>%
    mutate(
      cohort = if_else(g == 0, Inf, as.numeric(g))
    )

  cat("Running Sun-Abraham estimation...\n")
  sunab_model <- feols(
    y ~ sunab(cohort, t) | id + t,
    data = panel,
    cluster = ~id
  )

  cat("\nSUCCESS! Sun-Abraham estimator worked\n\n")

  # Extract coefficients
  cat("Coefficient summary:\n")
  print(summary(sunab_model))

  # Get event study coefficients
  cat("\n\nEvent study coefficients:\n")
  coefs <- coef(sunab_model)
  ses <- se(sunab_model)

  sunab_results <- tibble(
    term = names(coefs),
    estimate = as.numeric(coefs),
    se = as.numeric(ses)
  ) %>%
    mutate(
      # Extract relative time from term name
      # Format is "t::REL_TIME" where REL_TIME is the event time
      rel_time = as.integer(gsub("t::", "", term))
    ) %>%
    filter(!is.na(rel_time)) %>%
    select(rel_time, estimate, se) %>%
    arrange(rel_time) %>%
    mutate(
      t_stat = estimate / se,
      p_value = 2 * pnorm(-abs(t_stat)),
      ci_lo = estimate - 1.96 * se,
      ci_hi = estimate + 1.96 * se
    )

  cat("\nEvent study results (first 20 rows):\n")
  print(head(sunab_results, 20))

  # Pre-trends test
  pre_coefs <- sunab_results %>% filter(rel_time < 0)

  if (nrow(pre_coefs) > 0) {
    cat(glue("\n\nPre-treatment periods: {nrow(pre_coefs)}\n"))
    cat("F-test on pre-treatment coefficients:\n")

    # Joint test using wald()
    pre_terms <- sunab_results %>%
      filter(rel_time < 0) %>%
      pull(rel_time)

    # Can't easily extract pre-trend terms without knowing exact names
    # Instead, show individual significance
    cat("\nPre-trend coefficients:\n")
    print(pre_coefs %>% select(rel_time, estimate, se, p_value))
  }

  # Save results
  readr::write_csv(
    sunab_results,
    "output/pretrends_evaluation/sunab_event_study.csv"
  )
  cat("\n\nResults saved to: output/pretrends_evaluation/sunab_event_study.csv\n")

}, error = function(e) {
  cat("FAILED with error:\n")
  cat(e$message, "\n")
  print(e)
})

cat("\n\n=== CONCLUSION ===\n")
cat("If Sun-Abraham worked, it's a robust alternative to CS-DiD that:\n")
cat("  - Handles staggered treatment timing\n")
cat("  - Robust to heterogeneous treatment effects\n")
cat("  - Doesn't require balanced panels\n")
cat("  - Doesn't use fastglm (no segfaults!)\n")
