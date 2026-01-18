#!/usr/bin/env Rscript
################################################################################
# debug_csdid.R
#
# Debug CS-DiD segfault by testing different configurations
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
})

# Check if did package is installed
has_did <- requireNamespace("did", quietly = TRUE)

if (!has_did) {
  cat("did package not installed. Install with:\n")
  cat("  install.packages('did')\n")
  quit(status = 1)
}

library(did)

cat("did package loaded successfully\n")
cat("did version:", as.character(packageVersion("did")), "\n\n")

# Load baseline event study data
cat("Loading baseline panel data...\n")
baseline_coefs <- readr::read_csv(
  "output/pretrends_evaluation/baseline/event_study_coefs.csv",
  show_col_types = FALSE
)

# We need to reconstruct the panel from the raw data
# Load helper functions
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

# Load raw data
cat("Loading raw data files...\n")
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

# Build panel with treatment dates
panel <- panel_raw %>%
  left_join(gambling_dates, by = "state_abb") %>%
  filter(state_abb != "ME") %>%
  mutate(
    t = ym_index(month_date),
    g = ifelse(is.na(online_start_date), 0L, ym_index(online_start_date)),
    g = as.integer(g),
    e = if_else(g > 0L, as.integer(t - g), NA_integer_),
    y = log1p(pmax(as.numeric(filings_count), 0))
  ) %>%
  filter(is.na(e) | (e >= -12 & e <= 24)) %>%
  filter(!is.na(y))

cat(glue("\nPanel structure:\n"))
cat(glue("  States: {n_distinct(panel$state_abb)}\n"))
cat(glue("  Treated: {n_distinct(panel$state_abb[panel$g > 0])}\n"))
cat(glue("  Never-treated: {n_distinct(panel$state_abb[panel$g == 0])}\n"))
cat(glue("  Observations: {nrow(panel)}\n"))
cat(glue("  Time range: {min(panel$t)} to {max(panel$t)}\n\n"))

# Check balance
cat("Checking panel balance...\n")
balance_check <- panel %>%
  group_by(state_abb) %>%
  summarise(
    n_obs = n(),
    min_t = min(t),
    max_t = max(t),
    is_treated = any(g > 0),
    .groups = "drop"
  )

cat("Observations per state:\n")
print(summary(balance_check$n_obs))
cat("\n")

# Check if panel is balanced
all_states <- unique(panel$state_abb)
all_times <- unique(panel$t)
expected_obs <- length(all_states) * length(all_times)
actual_obs <- nrow(panel)
cat(glue("Panel balance: {actual_obs} / {expected_obs} = {round(100*actual_obs/expected_obs, 1)}%\n\n"))

if (actual_obs < expected_obs) {
  cat("PANEL IS UNBALANCED - this may cause issues with did package\n\n")
}

# Prepare for CS-DiD
panel_cs <- panel %>%
  mutate(
    gname = if_else(g > 0, as.integer(g), 0L),
    year = as.integer(t),
    obs_id = row_number()
  ) %>%
  select(state_abb, year, gname, y, obs_id) %>%
  filter(!is.na(y), !is.na(gname), !is.na(year))

cat("CS-DiD input data:\n")
cat(glue("  Rows: {nrow(panel_cs)}\n"))
cat(glue("  Unique states: {n_distinct(panel_cs$state_abb)}\n"))
cat(glue("  Unique years: {n_distinct(panel_cs$year)}\n"))
cat(glue("  Unique gnames: {n_distinct(panel_cs$gname)}\n"))
cat(glue("  Treatment groups: {paste(sort(unique(panel_cs$gname[panel_cs$gname > 0])), collapse=', ')}\n\n"))

# Test 1: Minimal example with just 2 cohorts
cat("=== TEST 1: Minimal example (2 earliest cohorts + never-treated) ===\n")
cohorts <- sort(unique(panel_cs$gname[panel_cs$gname > 0]))
cat(glue("Available cohorts: {paste(cohorts, collapse=', ')}\n"))

if (length(cohorts) >= 2) {
  panel_minimal <- panel_cs %>%
    filter(gname == 0 | gname %in% cohorts[1:2])

  cat(glue("Minimal panel: {nrow(panel_minimal)} obs, {n_distinct(panel_minimal$gname)} groups\n"))

  cat("Attempting CS-DiD with minimal panel...\n")
  tryCatch({
    att_minimal <- did::att_gt(
      yname = "y",
      tname = "year",
      idname = "obs_id",
      gname = "gname",
      data = as.data.frame(panel_minimal),
      control_group = "nevertreated",
      clustervars = "state_abb",
      est_method = "reg",
      base_period = "universal",
      anticipation = 0,
      bstrap = FALSE,
      cband = FALSE,
      panel = FALSE,
      print_details = FALSE
    )
    cat("SUCCESS! Minimal CS-DiD worked\n")
    cat("Summary:\n")
    print(summary(att_minimal))
  }, error = function(e) {
    cat("FAILED with error:\n")
    cat(e$message, "\n\n")
  })
}

cat("\n=== TEST 2: Balanced panel (fill missing with NA) ===\n")
cat("Creating balanced panel...\n")

# Create all state-time combinations
all_combos <- expand.grid(
  state_abb = all_states,
  year = all_times,
  stringsAsFactors = FALSE
)

panel_balanced <- all_combos %>%
  left_join(panel_cs %>% select(state_abb, year, gname, y), by = c("state_abb", "year")) %>%
  group_by(state_abb) %>%
  mutate(
    gname = first(gname[!is.na(gname)]),
    gname = if_else(is.na(gname), 0L, as.integer(gname))
  ) %>%
  ungroup() %>%
  mutate(obs_id = row_number())

cat(glue("Balanced panel: {nrow(panel_balanced)} obs\n"))
cat(glue("  With y: {sum(!is.na(panel_balanced$y))}\n"))
cat(glue("  Missing y: {sum(is.na(panel_balanced$y))}\n\n"))

cat("Attempting CS-DiD with balanced panel...\n")
tryCatch({
  att_balanced <- did::att_gt(
    yname = "y",
    tname = "year",
    idname = "obs_id",
    gname = "gname",
    data = as.data.frame(panel_balanced),
    control_group = "nevertreated",
    clustervars = "state_abb",
    est_method = "reg",
    base_period = "universal",
    anticipation = 0,
    bstrap = FALSE,
    cband = FALSE,
    panel = FALSE,
    print_details = FALSE
  )
  cat("SUCCESS! Balanced panel CS-DiD worked\n")
  cat("Summary:\n")
  print(summary(att_balanced))
}, error = function(e) {
  cat("FAILED with error:\n")
  cat(e$message, "\n\n")
})

cat("\n=== TEST 3: Single cohort ===\n")
if (length(cohorts) >= 1) {
  panel_single <- panel_cs %>%
    filter(gname == 0 | gname == cohorts[1])

  cat(glue("Single cohort panel: {nrow(panel_single)} obs, cohort = {cohorts[1]}\n"))

  cat("Attempting CS-DiD with single cohort...\n")
  tryCatch({
    att_single <- did::att_gt(
      yname = "y",
      tname = "year",
      idname = "obs_id",
      gname = "gname",
      data = as.data.frame(panel_single),
      control_group = "nevertreated",
      clustervars = "state_abb",
      est_method = "reg",
      base_period = "universal",
      anticipation = 0,
      bstrap = FALSE,
      cband = FALSE,
      panel = FALSE,
      print_details = FALSE
    )
    cat("SUCCESS! Single cohort CS-DiD worked\n")
    cat("Summary:\n")
    print(summary(att_single))
  }, error = function(e) {
    cat("FAILED with error:\n")
    cat(e$message, "\n\n")
  })
}

cat("\n=== TEST 4: Full panel with panel=TRUE (requires balanced) ===\n")
cat("Attempting CS-DiD with panel=TRUE on balanced data...\n")
tryCatch({
  # Use state_abb as idname for panel data
  panel_for_panel_true <- panel_balanced %>%
    mutate(id = as.integer(as.factor(state_abb)))

  att_panel_true <- did::att_gt(
    yname = "y",
    tname = "year",
    idname = "id",
    gname = "gname",
    data = as.data.frame(panel_for_panel_true),
    control_group = "nevertreated",
    clustervars = "id",
    est_method = "reg",
    base_period = "universal",
    anticipation = 0,
    bstrap = FALSE,
    cband = FALSE,
    panel = TRUE,  # Changed to TRUE
    print_details = FALSE
  )
  cat("SUCCESS! panel=TRUE worked\n")
  cat("Summary:\n")
  print(summary(att_panel_true))
}, error = function(e) {
  cat("FAILED with error:\n")
  cat(e$message, "\n\n")
})

cat("\n=== SUMMARY ===\n")
cat("Check which tests passed above to identify the issue.\n")
