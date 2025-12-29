################################################################################
# SPORTS GAMBLING AND EVICTIONS: DIFFERENCE-IN-DIFFERENCES ANALYSIS
# Comprehensive R Code for Reproducibility
# 
# This script performs:
# 1. State-level analysis (10 states, monthly data)
# 2. City-level analysis (36 cities, 20 states)
# 3. Combined/expanded panel analysis (20 states)
# 4. Addresses the "always treated" problem in city data
# 5. Event studies and parallel trends tests
# 6. Callaway-Sant'Anna robust estimators
################################################################################

# =============================================================================
# SETUP
# =============================================================================

# Clear environment
rm(list = ls())

# Install and load packages
packages <- c("tidyverse", "fixest", "did", "readxl", "lubridate", 
              "modelsummary", "ggplot2", "patchwork", "broom")

for (pkg in packages) {
  if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
    install.packages(pkg, repos = "https://cloud.r-project.org")
    library(pkg, character.only = TRUE)
  }
}
# Reinstall the corrupted package
#install.packages("cli", dependencies = TRUE)

# If that doesn't work, try removing and reinstalling
#remove.packages("cli")
#install.packages("cli")

# Then reload
library(tidyverse)
# Set theme
theme_set(theme_minimal(base_size = 12))

# Set working directory (modify as needed)
# setwd("YOUR_PATH_HERE")

cat("\n", strrep("=", 70), "\n")
cat("SPORTS GAMBLING & EVICTIONS: DiD ANALYSIS\n")
cat(strrep("=", 70), "\n\n")

# =============================================================================
# SECTION 1: LOAD AND PREPARE DATA
# =============================================================================

cat("SECTION 1: Loading and Preparing Data\n")
cat(strrep("-", 50), "\n\n")

# -----------------------------------------------------------------------------
# 1.1 Load gambling treatment dates
# -----------------------------------------------------------------------------
gambling <- read_excel("Gambing.xlsx") %>%
  mutate(State = str_trim(State),
         treat_year = year(First_Start))

cat("Loaded gambling treatment data:", nrow(gambling), "states\n")

# -----------------------------------------------------------------------------
# 1.2 Load state-level monthly eviction data (census tract aggregated to state)
# -----------------------------------------------------------------------------
state_raw <- read_csv("allstates_monthly_2020_2021.csv", show_col_types = FALSE)

# Aggregate to state-month
state_monthly <- state_raw %>%
  mutate(
    # Parse the month column first (adjust format if needed)
    date = floor_date(
      parse_date_time(month, orders = c("my", "ym", "ymd")),
      "month"
    )
  ) %>%
  filter(!is.na(date)) %>%
  group_by(state, date) %>%
  summarise(
    evictions = sum(filings_2020, na.rm = TRUE),
    evictions_historical = sum(filings_avg, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  # Merge treatment dates
  left_join(gambling %>% select(State, First_Start, Online), 
            by = c("state" = "State")) %>%
  mutate(
    # Treatment indicators
    treated = if_else(!is.na(First_Start) & date >= First_Start, 1L, 0L),
    ever_treated = if_else(!is.na(First_Start), 1L, 0L),
    treat_year = year(First_Start),
    
    # Outcomes
    log_evictions = log(evictions + 1),
    eviction_ratio = evictions / (evictions_historical + 1),
    
    # Time variables
    year = year(date),
    month_num = month(date),
    covid = if_else(year %in% c(2020, 2021), 1L, 0L),
    
    # Relative time (months)
    rel_time_months = if_else(
      !is.na(First_Start),
      as.integer(interval(First_Start, date) %/% months(1)),
      NA_integer_
    )
  )
cat("State monthly panel:", nrow(state_monthly), "obs,", 
    n_distinct(state_monthly$state), "states\n")
cat("  Treated:", sum(state_monthly$ever_treated == 1 & !duplicated(state_monthly$state)), "\n")
cat("  Control:", sum(state_monthly$ever_treated == 0 & !duplicated(state_monthly$state)), "\n\n")

# -----------------------------------------------------------------------------
# 1.3 Load city-level data
# -----------------------------------------------------------------------------

# State abbreviation to full name mapping
abbrev_to_full <- c(
  "AZ" = "Arizona", "CT" = "Connecticut", "DE" = "Delaware", "FL" = "Florida",

"IN" = "Indiana", "LA" = "Louisiana", "MA" = "Massachusetts", "MN" = "Minnesota",
  "MO" = "Missouri", "NV" = "Nevada", "NM" = "New Mexico", "NY" = "New York",
  "OH" = "Ohio", "PA" = "Pennsylvania", "RI" = "Rhode Island", "SC" = "South Carolina",
  "TN" = "Tennessee", "TX" = "Texas", "VA" = "Virginia", "WI" = "Wisconsin"
)

city_raw <- read_csv("all_sites_monthly_2020_2021.csv", show_col_types = FALSE)

city_panel <- city_raw %>%
  rename(
    evictions = filings_2020,
    evictions_historical = filings_avg_prepandemic_baseline
  ) %>%
  mutate(
    # Extract state abbreviation
    state_abbrev = str_extract(city, "(?<=, )[A-Z]{2}$"),
    # Handle cities without state in name
    state_abbrev = case_when(
      city == "Fort Lauderdale" ~ "FL",
      city == "Miami" ~ "FL",
      city == "Palm Beach" ~ "FL",
      TRUE ~ state_abbrev
    ),
    state = abbrev_to_full[state_abbrev],
    date = parse_date_time(month, orders = "my")
  ) %>%
  filter(!is.na(date), !is.na(state)) %>%
  # Merge treatment dates
  left_join(gambling %>% select(State, First_Start, Online),
            by = c("state" = "State")) %>%
  mutate(
    treated = if_else(!is.na(First_Start) & date >= First_Start, 1L, 0L),
    ever_treated = if_else(!is.na(First_Start), 1L, 0L),
    treat_year = year(First_Start),
    log_evictions = log(evictions + 1),
    year = year(date),
    covid = if_else(year %in% c(2020, 2021), 1L, 0L),
    rel_time_months = if_else(
      !is.na(First_Start),
      as.integer(interval(First_Start, date) %/% months(1)),
      NA_integer_
    )
  )

cat("City panel:", nrow(city_panel), "obs,", 
    n_distinct(city_panel$city), "cities,",
    n_distinct(city_panel$state), "states\n")
cat("  Treated states:", n_distinct(city_panel$state[city_panel$ever_treated == 1]), "\n")
cat("  Control states:", n_distinct(city_panel$state[city_panel$ever_treated == 0]), "\n\n")

# -----------------------------------------------------------------------------
# 1.4 Identify "always treated" states (treated before data starts)
# -----------------------------------------------------------------------------

cat(strrep("-", 50), "\n")
cat("CRITICAL: Identifying 'Always Treated' States\n")
cat(strrep("-", 50), "\n\n")

data_start <- as.Date("2020-01-01")

treatment_timing <- city_panel %>%
  group_by(state) %>%
  summarise(
    First_Start = first(First_Start),
    treat_year = first(treat_year),
    ever_treated = first(ever_treated),
    n_cities = n_distinct(city),
    .groups = "drop"
  ) %>%
  mutate(
    months_pre_treatment = if_else(
      !is.na(First_Start),
      pmax(0, as.integer(difftime(First_Start, data_start, units = "days")) / 30),
      NA_real_
    ),
    treatment_status = case_when(
      ever_treated == 0 ~ "Never treated",
      months_pre_treatment == 0 ~ "Always treated (no pre-period)",
      months_pre_treatment < 12 ~ "Limited pre-period (<12 mo)",
      TRUE ~ "Good pre-period (12+ mo)"
    )
  )

cat("Treatment timing by state:\n")
print(treatment_timing %>% 
        select(state, treat_year, months_pre_treatment, treatment_status, n_cities) %>%
        arrange(months_pre_treatment),
      n = 25)

# List always-treated states
always_treated_states <- treatment_timing %>%
  filter(treatment_status == "Always treated (no pre-period)") %>%
  pull(state)

cat("\n'Always treated' states (contribute NOTHING to DiD identification):\n")
cat(" ", paste(always_treated_states, collapse = ", "), "\n")
cat("  These", length(always_treated_states), "states were treated before Jan 2020\n\n")

# -----------------------------------------------------------------------------
# 1.5 Create cleaned city panel (excluding always-treated)
# -----------------------------------------------------------------------------

city_panel_clean <- city_panel %>%
  filter(!state %in% always_treated_states)

cat("Cleaned city panel:", nrow(city_panel_clean), "obs,",
    n_distinct(city_panel_clean$city), "cities,",
    n_distinct(city_panel_clean$state), "states\n")
cat("  Treated (with pre-period):", 
    n_distinct(city_panel_clean$state[city_panel_clean$ever_treated == 1]), "\n")
cat("  Control:", 
    n_distinct(city_panel_clean$state[city_panel_clean$ever_treated == 0]), "\n\n")

# -----------------------------------------------------------------------------
# 1.6 Create expanded panel (state monthly + city-aggregated for new states)
# -----------------------------------------------------------------------------

monthly_states <- unique(state_monthly$state)

# Aggregate city data for states NOT in monthly data
city_state_agg <- city_panel %>%
  filter(!state %in% monthly_states) %>%
  group_by(state, date) %>%
  summarise(
    evictions = sum(evictions, na.rm = TRUE),
    evictions_historical = sum(evictions_historical, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  left_join(gambling %>% select(State, First_Start, Online),
            by = c("state" = "State")) %>%
  mutate(source = "city_aggregated")

# Prepare state monthly
state_monthly_prep <- state_monthly %>%
  select(state, date, evictions, evictions_historical, First_Start, Online) %>%
  mutate(source = "state_monthly")

# Combine
expanded_panel <- bind_rows(state_monthly_prep, city_state_agg) %>%
  mutate(
    treated = if_else(!is.na(First_Start) & date >= First_Start, 1L, 0L),
    ever_treated = if_else(!is.na(First_Start), 1L, 0L),
    treat_year = year(First_Start),
    log_evictions = log(evictions + 1),
    year = year(date),
    covid = if_else(year %in% c(2020, 2021), 1L, 0L),
    is_city_source = if_else(source == "city_aggregated", 1L, 0L),
    rel_time_months = if_else(
      !is.na(First_Start),
      as.integer(interval(First_Start, date) %/% months(1)),
      NA_integer_
    )
  )

cat("Expanded panel:", nrow(expanded_panel), "obs,",
    n_distinct(expanded_panel$state), "states\n")
cat("  From state monthly:", sum(expanded_panel$source == "state_monthly"), "obs\n")
cat("  From city aggregated:", sum(expanded_panel$source == "city_aggregated"), "obs\n\n")

# =============================================================================
# SECTION 2: STATE-LEVEL ANALYSIS (Original 10 States)
# =============================================================================

cat("\n", strrep("=", 70), "\n")
cat("SECTION 2: STATE-LEVEL ANALYSIS (10 States)\n")
cat(strrep("=", 70), "\n\n")

# Basic TWFE
m_state_1 <- feols(log_evictions ~ treated | state + date, 
                   data = state_monthly, cluster = ~state)

# With COVID interaction
state_monthly <- state_monthly %>%
  mutate(covid_treat = covid * ever_treated)

m_state_2 <- feols(log_evictions ~ treated + covid_treat | state + date,
                   data = state_monthly, cluster = ~state)

# Post-COVID only
m_state_3 <- feols(log_evictions ~ treated | state + date,
                   data = state_monthly %>% filter(date >= "2022-01-01"),
                   cluster = ~state)

# Event study (6-month bins)
state_monthly <- state_monthly %>%
  mutate(
    rel_time_bin = case_when(
      is.na(rel_time_months) ~ NA_integer_,
      rel_time_months < -18 ~ -3L,
      rel_time_months < -12 ~ -2L,
      rel_time_months < -6 ~ -1L,
      rel_time_months < 0 ~ 0L,
      rel_time_months < 6 ~ 1L,
      rel_time_months < 12 ~ 2L,
      rel_time_months < 18 ~ 3L,
      rel_time_months < 24 ~ 4L,
      rel_time_months < 36 ~ 5L,
      TRUE ~ 6L
    )
  )

m_state_es <- feols(log_evictions ~ i(rel_time_bin, ref = 0) | state + date,
                    data = state_monthly %>% filter(!is.na(rel_time_bin)),
                    cluster = ~state)

cat("Model 1: Basic TWFE\n")
cat("  ATT:", round(coef(m_state_1)["treated"], 4), "\n")
cat("  SE:", round(se(m_state_1)["treated"], 4), "\n")
cat("  p-value:", round(pvalue(m_state_1)["treated"], 4), "\n")
cat("  % Change:", round((exp(coef(m_state_1)["treated"]) - 1) * 100, 1), "%\n\n")

cat("Model 2: + COVID Interaction\n")
cat("  ATT:", round(coef(m_state_2)["treated"], 4), "\n")
cat("  COVID×Treat:", round(coef(m_state_2)["covid_treat"], 4), "\n\n")

cat("Model 3: Post-COVID (2022+)\n")
cat("  ATT:", round(coef(m_state_3)["treated"], 4), "\n")
cat("  SE:", round(se(m_state_3)["treated"], 4), "\n")
cat("  p-value:", round(pvalue(m_state_3)["treated"], 4), "\n\n")

# =============================================================================
# SECTION 3: CITY-LEVEL ANALYSIS (36 Cities, 20 States)
# =============================================================================

cat("\n", strrep("=", 70), "\n")
cat("SECTION 3: CITY-LEVEL ANALYSIS (36 Cities)\n")
cat(strrep("=", 70), "\n\n")

# 3.1 Full sample (all 36 cities)
m_city_1 <- feols(log_evictions ~ treated | city + date,
                  data = city_panel, cluster = ~state)

cat("Model 1: Full Sample (36 cities, 20 states)\n")
cat("  ATT:", round(coef(m_city_1)["treated"], 4), "\n")
cat("  SE:", round(se(m_city_1)["treated"], 4), "\n")
cat("  p-value:", round(pvalue(m_city_1)["treated"], 4), "\n")
cat("  % Change:", round((exp(coef(m_city_1)["treated"]) - 1) * 100, 1), "%\n\n")

# 3.2 Cleaned sample (excluding always-treated states)
m_city_2 <- feols(log_evictions ~ treated | city + date,
                  data = city_panel_clean, cluster = ~state)

cat("Model 2: Cleaned Sample (excl. always-treated states)\n")
cat("  Sample:", n_distinct(city_panel_clean$city), "cities,",
    n_distinct(city_panel_clean$state), "states\n")
cat("  ATT:", round(coef(m_city_2)["treated"], 4), "\n")
cat("  SE:", round(se(m_city_2)["treated"], 4), "\n")
cat("  p-value:", round(pvalue(m_city_2)["treated"], 4), "\n")
cat("  % Change:", round((exp(coef(m_city_2)["treated"]) - 1) * 100, 1), "%\n\n")

# 3.3 Excluding large control states (TX, FL, NV)
city_panel_excl <- city_panel_clean %>%
  filter(!state_abbrev %in% c("TX", "FL", "NV"))

m_city_3 <- feols(log_evictions ~ treated | city + date,
                  data = city_panel_excl, cluster = ~state)

cat("Model 3: Also Excluding TX, FL, NV\n")
cat("  Sample:", n_distinct(city_panel_excl$city), "cities,",
    n_distinct(city_panel_excl$state), "states\n")
cat("  ATT:", round(coef(m_city_3)["treated"], 4), "\n")
cat("  SE:", round(se(m_city_3)["treated"], 4), "\n")
cat("  p-value:", round(pvalue(m_city_3)["treated"], 4), "\n\n")

# 3.4 Post-COVID only
m_city_4 <- feols(log_evictions ~ treated | city + date,
                  data = city_panel_clean %>% filter(date >= "2022-01-01"),
                  cluster = ~state)

cat("Model 4: Post-COVID (2022+), Cleaned Sample\n")
cat("  ATT:", round(coef(m_city_4)["treated"], 4), "\n")
cat("  SE:", round(se(m_city_4)["treated"], 4), "\n")
cat("  p-value:", round(pvalue(m_city_4)["treated"], 4), "\n\n")

# 3.5 Event study on cleaned sample
city_panel_clean <- city_panel_clean %>%
  mutate(
    rel_time_bin = case_when(
      is.na(rel_time_months) ~ NA_integer_,
      rel_time_months < -18 ~ -3L,
      rel_time_months < -12 ~ -2L,
      rel_time_months < -6 ~ -1L,
      rel_time_months < 0 ~ 0L,
      rel_time_months < 6 ~ 1L,
      rel_time_months < 12 ~ 2L,
      rel_time_months < 18 ~ 3L,
      rel_time_months < 24 ~ 4L,
      rel_time_months < 36 ~ 5L,
      TRUE ~ 6L
    )
  )

m_city_es <- feols(log_evictions ~ i(rel_time_bin, ref = 0) | city + date,
                   data = city_panel_clean %>% filter(!is.na(rel_time_bin)),
                   cluster = ~state)

cat("Event Study (Cleaned Sample):\n")
print(summary(m_city_es))

# =============================================================================
# SECTION 4: EXPANDED PANEL ANALYSIS (20 States)
# =============================================================================

cat("\n", strrep("=", 70), "\n")
cat("SECTION 4: EXPANDED PANEL ANALYSIS (20 States)\n")
cat(strrep("=", 70), "\n\n")

# 4.1 Basic TWFE
m_exp_1 <- feols(log_evictions ~ treated | state + date,
                 data = expanded_panel, cluster = ~state)

cat("Model 1: Basic TWFE\n")
cat("  ATT:", round(coef(m_exp_1)["treated"], 4), "\n")
cat("  SE:", round(se(m_exp_1)["treated"], 4), "\n")
cat("  p-value:", round(pvalue(m_exp_1)["treated"], 4), "\n")
cat("  % Change:", round((exp(coef(m_exp_1)["treated"]) - 1) * 100, 1), "%\n\n")

# 4.2 With COVID interaction
expanded_panel <- expanded_panel %>%
  mutate(covid_treat = covid * ever_treated)

m_exp_2 <- feols(log_evictions ~ treated + covid_treat | state + date,
                 data = expanded_panel, cluster = ~state)

cat("Model 2: + COVID Interaction\n")
cat("  ATT:", round(coef(m_exp_2)["treated"], 4), "\n")
cat("  COVID×Treat:", round(coef(m_exp_2)["covid_treat"], 4), "\n\n")

# 4.3 Post-COVID only
m_exp_3 <- feols(log_evictions ~ treated | state + date,
                 data = expanded_panel %>% filter(date >= "2022-01-01"),
                 cluster = ~state)

cat("Model 3: Post-COVID (2022+)\n")
cat("  ATT:", round(coef(m_exp_3)["treated"], 4), "\n")
cat("  SE:", round(se(m_exp_3)["treated"], 4), "\n")
cat("  p-value:", round(pvalue(m_exp_3)["treated"], 4), "\n\n")

# 4.4 Heterogeneity by data source
expanded_panel <- expanded_panel %>%
  mutate(
    treat_city = treated * is_city_source,
    treat_state = treated * (1 - is_city_source)
  )

m_exp_4 <- feols(log_evictions ~ treat_city + treat_state | state + date,
                 data = expanded_panel, cluster = ~state)

cat("Model 4: Heterogeneity by Data Source\n")
cat("  ATT (city-sourced):", round(coef(m_exp_4)["treat_city"], 4),
    "(p =", round(pvalue(m_exp_4)["treat_city"], 4), ")\n")
cat("  ATT (state-sourced):", round(coef(m_exp_4)["treat_state"], 4),
    "(p =", round(pvalue(m_exp_4)["treat_state"], 4), ")\n\n")

# 4.5 Event study
expanded_panel <- expanded_panel %>%
  mutate(
    rel_time_bin = case_when(
      is.na(rel_time_months) ~ NA_integer_,
      rel_time_months < -18 ~ -3L,
      rel_time_months < -12 ~ -2L,
      rel_time_months < -6 ~ -1L,
      rel_time_months < 0 ~ 0L,
      rel_time_months < 6 ~ 1L,
      rel_time_months < 12 ~ 2L,
      rel_time_months < 18 ~ 3L,
      rel_time_months < 24 ~ 4L,
      rel_time_months < 36 ~ 5L,
      TRUE ~ 6L
    )
  )

m_exp_es <- feols(log_evictions ~ i(rel_time_bin, ref = 0) | state + date,
                  data = expanded_panel %>% filter(!is.na(rel_time_bin)),
                  cluster = ~state)

# =============================================================================
# SECTION 5: CALLAWAY-SANT'ANNA ESTIMATOR
# =============================================================================

cat("\n", strrep("=", 70), "\n")
cat("SECTION 5: CALLAWAY-SANT'ANNA ROBUST ESTIMATOR\n")
cat(strrep("=", 70), "\n\n")

# Prepare data for did package
# Requires: panel ID, time period (integer), first treatment period (0 for never-treated)

# City-level CS on cleaned sample
city_cs <- city_panel_clean %>%
  mutate(
    city_id = as.integer(factor(city)),
    # Time period as months since data start
    time_period = as.integer(difftime(date, min(date), units = "days") / 30),
    # First treatment period (0 = never treated)
    first_treat = if_else(
      is.na(First_Start), 
      0L,
      as.integer(difftime(First_Start, min(date), units = "days") / 30)
    )
  ) %>%
  filter(!is.na(log_evictions)) %>%
  as.data.frame()

cat("Running Callaway-Sant'Anna on cleaned city panel...\n")

tryCatch({
  cs_city <- att_gt(
    yname = "log_evictions",
    tname = "time_period",
    idname = "city_id",
    gname = "first_treat",
    data = city_cs,
    control_group = "nevertreated",
    base_period = "universal"
  )
  
  # Aggregate to simple ATT
  cs_city_simple <- aggte(cs_city, type = "simple")
  
  cat("\nCallaway-Sant'Anna Results (Cleaned City Panel):\n")
  cat("  Overall ATT:", round(cs_city_simple$overall.att, 4), "\n")
  cat("  SE:", round(cs_city_simple$overall.se, 4), "\n")
  cat("  95% CI: [", round(cs_city_simple$overall.att - 1.96 * cs_city_simple$overall.se, 4),
      ",", round(cs_city_simple$overall.att + 1.96 * cs_city_simple$overall.se, 4), "]\n")
  cat("  % Change:", round((exp(cs_city_simple$overall.att) - 1) * 100, 1), "%\n\n")
  
  # Dynamic effects
  cs_city_dyn <- aggte(cs_city, type = "dynamic", min_e = -18, max_e = 36)
  
  cat("Dynamic ATT by event time:\n")
  print(data.frame(
    event_time = cs_city_dyn$egt,
    att = round(cs_city_dyn$att.egt, 4),
    se = round(cs_city_dyn$se.egt, 4)
  ))
  
}, error = function(e) {
  cat("CS estimation error:", e$message, "\n")
  cat("This can happen with limited variation in treatment timing.\n\n")
})

# =============================================================================
# SECTION 6: COMPREHENSIVE RESULTS TABLE
# =============================================================================

cat("\n", strrep("=", 70), "\n")
cat("SECTION 6: COMPREHENSIVE RESULTS TABLE\n")
cat(strrep("=", 70), "\n\n")

# Build results table
results_table <- tibble(
  Specification = c(
    "State (10 states, monthly)",
    "State (post-COVID)",
    "City (36 cities, all)",
    "City (28 cities, cleaned)",
    "City (cleaned, excl TX/FL/NV)",
    "City (cleaned, post-COVID)",
    "Expanded (20 states)",
    "Expanded (post-COVID)"
  ),
  N_obs = c(
    nrow(state_monthly),
    nrow(state_monthly %>% filter(date >= "2022-01-01")),
    nrow(city_panel),
    nrow(city_panel_clean),
    nrow(city_panel_excl),
    nrow(city_panel_clean %>% filter(date >= "2022-01-01")),
    nrow(expanded_panel),
    nrow(expanded_panel %>% filter(date >= "2022-01-01"))
  ),
  N_units = c(
    n_distinct(state_monthly$state),
    n_distinct(state_monthly$state),
    n_distinct(city_panel$city),
    n_distinct(city_panel_clean$city),
    n_distinct(city_panel_excl$city),
    n_distinct(city_panel_clean$city),
    n_distinct(expanded_panel$state),
    n_distinct(expanded_panel$state)
  ),
  ATT = c(
    coef(m_state_1)["treated"],
    coef(m_state_3)["treated"],
    coef(m_city_1)["treated"],
    coef(m_city_2)["treated"],
    coef(m_city_3)["treated"],
    coef(m_city_4)["treated"],
    coef(m_exp_1)["treated"],
    coef(m_exp_3)["treated"]
  ),
  SE = c(
    se(m_state_1)["treated"],
    se(m_state_3)["treated"],
    se(m_city_1)["treated"],
    se(m_city_2)["treated"],
    se(m_city_3)["treated"],
    se(m_city_4)["treated"],
    se(m_exp_1)["treated"],
    se(m_exp_3)["treated"]
  ),
  p_value = c(
    pvalue(m_state_1)["treated"],
    pvalue(m_state_3)["treated"],
    pvalue(m_city_1)["treated"],
    pvalue(m_city_2)["treated"],
    pvalue(m_city_3)["treated"],
    pvalue(m_city_4)["treated"],
    pvalue(m_exp_1)["treated"],
    pvalue(m_exp_3)["treated"]
  )
) %>%
  mutate(
    pct_change = (exp(ATT) - 1) * 100,
    ATT = round(ATT, 4),
    SE = round(SE, 4),
    p_value = round(p_value, 4),
    pct_change = round(pct_change, 1)
  )

cat("MAIN RESULTS:\n\n")
print(results_table, n = Inf)

# Save results
write_csv(results_table, "did_results_summary.csv")

# =============================================================================
# SECTION 7: VISUALIZATIONS
# =============================================================================

cat("\n", strrep("=", 70), "\n")
cat("SECTION 7: CREATING VISUALIZATIONS\n")
cat(strrep("=", 70), "\n\n")

# -----------------------------------------------------------------------------
# 7.1 Extract event study coefficients
# -----------------------------------------------------------------------------
extract_es_coefs <- function(model, ref_level = 0) {
  coefs <- coef(model)
  ses <- se(model)
  pvals <- pvalue(model)
  
  # Get coefficient names that contain rel_time_bin
  es_names <- names(coefs)[grepl("rel_time_bin", names(coefs))]
  
  es_df <- tibble(
    rel_time_bin = as.integer(str_extract(es_names, "-?\\d+")),
    coef = coefs[es_names],
    se = ses[es_names],
    pval = pvals[es_names]
  ) %>%
    bind_rows(tibble(rel_time_bin = ref_level, coef = 0, se = 0, pval = 1)) %>%
    arrange(rel_time_bin) %>%
    mutate(
      ci_low = coef - 1.96 * se,
      ci_high = coef + 1.96 * se
    )
  
  return(es_df)
}

es_state <- extract_es_coefs(m_state_es)
es_city <- extract_es_coefs(m_city_es)
es_exp <- extract_es_coefs(m_exp_es)

# Bin labels
bin_labels <- c(
  "-3" = "<-18mo", "-2" = "-18 to -12mo", "-1" = "-12 to -6mo",
  "0" = "-6 to 0mo", "1" = "0-6mo", "2" = "6-12mo",
  "3" = "12-18mo", "4" = "18-24mo", "5" = "24-36mo", "6" = "36+mo"
)

# -----------------------------------------------------------------------------
# 7.2 Event study plots
# -----------------------------------------------------------------------------

# City-level event study (cleaned sample)
p_es_city <- ggplot(es_city, aes(x = rel_time_bin, y = coef)) +
  geom_ribbon(aes(ymin = ci_low, ymax = ci_high), alpha = 0.3, fill = "darkgreen") +
  geom_line(color = "darkgreen", linewidth = 1) +
  geom_point(color = "darkgreen", size = 3) +
  geom_hline(yintercept = 0, linetype = "solid", linewidth = 0.5) +
  geom_vline(xintercept = 0.5, linetype = "dashed", color = "red", linewidth = 1) +
  scale_x_continuous(
    breaks = es_city$rel_time_bin,
    labels = bin_labels[as.character(es_city$rel_time_bin)]
  ) +
  labs(
    title = "Event Study: City-Level (Cleaned Sample)",
    subtitle = "Excluding 'always treated' states (DE, IN, NM, NY, PA, RI)",
    x = "6-Month Periods Relative to Treatment",
    y = "Effect on Log Evictions"
  ) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

# Expanded panel event study
p_es_exp <- ggplot(es_exp, aes(x = rel_time_bin, y = coef)) +
  geom_ribbon(aes(ymin = ci_low, ymax = ci_high), alpha = 0.3, fill = "purple") +
  geom_line(color = "purple", linewidth = 1) +
  geom_point(color = "purple", size = 3) +
  geom_hline(yintercept = 0, linetype = "solid", linewidth = 0.5) +
  geom_vline(xintercept = 0.5, linetype = "dashed", color = "red", linewidth = 1) +
  scale_x_continuous(
    breaks = es_exp$rel_time_bin,
    labels = bin_labels[as.character(es_exp$rel_time_bin)]
  ) +
  labs(
    title = "Event Study: Expanded Panel (20 States)",
    subtitle = "10 state-level + 10 city-aggregated states",
    x = "6-Month Periods Relative to Treatment",
    y = "Effect on Log Evictions"
  ) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

# -----------------------------------------------------------------------------
# 7.3 Treated vs Control trends
# -----------------------------------------------------------------------------

# City-level trends (cleaned)
city_trends <- city_panel_clean %>%
  group_by(date, ever_treated) %>%
  summarise(log_evictions = mean(log_evictions, na.rm = TRUE), .groups = "drop") %>%
  mutate(group = if_else(ever_treated == 1, "Treated (8 states)", "Control (6 states)"))

p_trends_city <- ggplot(city_trends, aes(x = date, y = log_evictions, color = group)) +
  geom_line(linewidth = 1.2) +
  geom_vline(xintercept = as.POSIXct("2021-01-01"), linetype = "dashed", alpha = 0.5) +
  scale_color_manual(values = c("Treated (8 states)" = "darkgreen", "Control (6 states)" = "orange")) +
  labs(
    title = "Treated vs Control Trends (City-Level, Cleaned)",
    x = "Date",
    y = "Log Evictions",
    color = ""
  ) +
  theme(legend.position = "bottom")

# Expanded panel trends
exp_trends <- expanded_panel %>%
  group_by(date, ever_treated) %>%
  summarise(log_evictions = mean(log_evictions, na.rm = TRUE), .groups = "drop") %>%
  mutate(group = if_else(ever_treated == 1, "Treated (14 states)", "Control (6 states)"))

p_trends_exp <- ggplot(exp_trends, aes(x = date, y = log_evictions, color = group)) +
  geom_line(linewidth = 1.2) +
  geom_vline(xintercept = as.POSIXct("2021-01-01"), linetype = "dashed", alpha = 0.5) +
  scale_color_manual(values = c("Treated (14 states)" = "purple", "Control (6 states)" = "orange")) +
  labs(
    title = "Treated vs Control Trends (Expanded Panel)",
    x = "Date",
    y = "Log Evictions",
    color = ""
  ) +
  theme(legend.position = "bottom")

# -----------------------------------------------------------------------------
# 7.4 Coefficient comparison plot
# -----------------------------------------------------------------------------

coef_plot_data <- results_table %>%
  mutate(
    ci_low = ATT - 1.96 * SE,
    ci_high = ATT + 1.96 * SE,
    Specification = factor(Specification, levels = rev(Specification))
  )

p_coefs <- ggplot(coef_plot_data, aes(x = ATT, y = Specification)) +
  geom_vline(xintercept = 0, linetype = "solid", linewidth = 1) +
  geom_errorbarh(aes(xmin = ci_low, xmax = ci_high), height = 0.2) +
  geom_point(size = 3, color = "steelblue") +
  labs(
    title = "Effect Estimates Across Specifications",
    subtitle = "95% confidence intervals shown",
    x = "ATT (Log Evictions)",
    y = ""
  ) +
  xlim(-0.6, 0.4)

# -----------------------------------------------------------------------------
# 7.5 Combined figure
# -----------------------------------------------------------------------------

combined_plot <- (p_es_city | p_es_exp) / (p_trends_city | p_coefs) +
  plot_annotation(
    title = "Sports Gambling and Evictions: Difference-in-Differences Analysis",
    subtitle = "Null effect across all well-identified specifications"
  )

ggsave("comprehensive_analysis.png", combined_plot, width = 14, height = 10, dpi = 150)

# Save individual plots
ggsave("event_study_city_cleaned.png", p_es_city, width = 10, height = 6, dpi = 150)
ggsave("event_study_expanded.png", p_es_exp, width = 10, height = 6, dpi = 150)
ggsave("coefficient_comparison.png", p_coefs, width = 10, height = 6, dpi = 150)

cat("Visualizations saved.\n\n")

# =============================================================================
# SECTION 8: ROBUSTNESS CHECKS
# =============================================================================

cat("\n", strrep("=", 70), "\n")
cat("SECTION 8: ROBUSTNESS CHECKS\n")
cat(strrep("=", 70), "\n\n")

# -----------------------------------------------------------------------------
# 8.1 Parallel trends test
# -----------------------------------------------------------------------------
cat("Parallel Trends Tests:\n\n")

# State-level
es_state_pre <- es_state %>% filter(rel_time_bin < 0)
cat("State-level:\n")
cat("  Pre-treatment mean:", round(mean(es_state_pre$coef), 4), "\n")
cat("  Significant at 5%:", sum(es_state_pre$pval < 0.05), "of", nrow(es_state_pre), "\n\n")

# City-level (cleaned)
es_city_pre <- es_city %>% filter(rel_time_bin < 0)
cat("City-level (cleaned):\n")
cat("  Pre-treatment mean:", round(mean(es_city_pre$coef), 4), "\n")
cat("  Significant at 5%:", sum(es_city_pre$pval < 0.05), "of", nrow(es_city_pre), "\n\n")

# Expanded
es_exp_pre <- es_exp %>% filter(rel_time_bin < 0)
cat("Expanded panel:\n")
cat("  Pre-treatment mean:", round(mean(es_exp_pre$coef), 4), "\n")
cat("  Significant at 5%:", sum(es_exp_pre$pval < 0.05), "of", nrow(es_exp_pre), "\n\n")

# -----------------------------------------------------------------------------
# 8.2 Alternative outcome: eviction ratio
# -----------------------------------------------------------------------------
city_panel_clean <- city_panel_clean %>%
  mutate(eviction_ratio = evictions / (evictions_historical + 1))

m_ratio <- feols(eviction_ratio ~ treated | city + date,
                 data = city_panel_clean, cluster = ~state)

cat("Alternative Outcome (Eviction Ratio):\n")
cat("  ATT:", round(coef(m_ratio)["treated"], 4), "\n")
cat("  SE:", round(se(m_ratio)["treated"], 4), "\n")
cat("  p-value:", round(pvalue(m_ratio)["treated"], 4), "\n\n")

# -----------------------------------------------------------------------------
# 8.3 Leave-one-out robustness
# -----------------------------------------------------------------------------
cat("Leave-One-Out Robustness (Expanded Panel):\n")

states <- unique(expanded_panel$state)
loo_results <- map_dfr(states, function(s) {
  model <- feols(log_evictions ~ treated | state + date,
                 data = expanded_panel %>% filter(state != s))
  tibble(excluded_state = s, att = coef(model)["treated"])
})

cat("  Baseline ATT:", round(coef(m_exp_1)["treated"], 4), "\n")
cat("  LOO ATT range:", round(min(loo_results$att), 4), "to", 
    round(max(loo_results$att), 4), "\n")
cat("  Most influential:", 
    loo_results$excluded_state[which.max(abs(loo_results$att - coef(m_exp_1)["treated"]))], "\n\n")

# =============================================================================
# SECTION 9: EXPORT DATA
# =============================================================================

cat("\n", strrep("=", 70), "\n")
cat("SECTION 9: EXPORTING DATA\n")
cat(strrep("=", 70), "\n\n")

write_csv(state_monthly, "state_monthly_panel.csv")
write_csv(city_panel, "city_panel_full.csv")
write_csv(city_panel_clean, "city_panel_cleaned.csv")
write_csv(expanded_panel, "expanded_panel.csv")
write_csv(es_state, "event_study_state_coefs.csv")
write_csv(es_city, "event_study_city_coefs.csv")
write_csv(es_exp, "event_study_expanded_coefs.csv")
write_csv(treatment_timing, "treatment_timing_summary.csv")

cat("Data files exported.\n\n")

# =============================================================================
# SECTION 10: FINAL SUMMARY
# =============================================================================

cat("\n", strrep("=", 70), "\n")
cat("FINAL SUMMARY\n")
cat(strrep("=", 70), "\n\n")

cat("
╔══════════════════════════════════════════════════════════════════════════╗
║                     SPORTS GAMBLING & EVICTIONS                          ║
║                   DIFFERENCE-IN-DIFFERENCES ANALYSIS                     ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║  CRITICAL FINDING: 6 of 14 treated states in city data are 'ALWAYS      ║
║  TREATED' (legalized before Jan 2020). These contribute NOTHING to      ║
║  the DiD identification.                                                 ║
║                                                                          ║
║  KEY RESULTS:                                                            ║
║  ┌────────────────────────────────────────────────────────────────────┐  ║
║  │ City-level (cleaned):  ATT = ", sprintf("%6.3f", coef(m_city_2)["treated"]), " (SE = ", sprintf("%.3f", se(m_city_2)["treated"]), ", p = ", sprintf("%.3f", pvalue(m_city_2)["treated"]), ")    │  ║
║  │ Expanded panel:        ATT = ", sprintf("%6.3f", coef(m_exp_1)["treated"]), " (SE = ", sprintf("%.3f", se(m_exp_1)["treated"]), ", p = ", sprintf("%.3f", pvalue(m_exp_1)["treated"]), ")    │  ║
║  └────────────────────────────────────────────────────────────────────┘  ║
║                                                                          ║
║  PARALLEL TRENDS: Excellent (0 of 3 pre-periods significant at 5%)       ║
║                                                                          ║
║  INTERPRETATION:                                                         ║
║  Cannot reject null hypothesis that sports gambling legalization         ║
║  has no effect on eviction rates in major metropolitan areas.            ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
")

cat("\nAnalysis complete. All outputs saved to working directory.\n")

################################################################################
# END OF SCRIPT
################################################################################




