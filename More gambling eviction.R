install.packages(c("usethis", "gitcreds", "gert"))

usethis::use_git_config(
  user.name  = "ben-boehlert",
  user.email = "bhboehlert@gmail.com"  # whatever email you use on GitHub
)


################################################################################
# SPORTS GAMBLING AND EVICTIONS: DIFFERENCE-IN-DIFFERENCES ANALYSIS
# Single-script version with cleaned code + methodological fixes
#
# DATA:
# 1. State monthly (10 states, 2020–2025)  
#       -> allstates_monthly_2020_2021.csv
# 2. Annual county court (51 states, 2000–2023)  
#       -> county_court-issued_2000_2023_ben_update_5_12.csv
# 3. City monthly (36 cities, 20 states, 2020–2025)  
#       -> all_sites_monthly_2020_2021.csv
# 4. Gambling treatment timing  
#       -> Gambing.xlsx
#
# MAIN OUTPUTS:
#  - did_results_comprehensive.csv
#  - trends_annual.png
#  - event_study_annual.png
#  - event_study_city_cleaned.png
#  - event_study_expanded_cleaned.png
#  - event_study_comparison.png
#  - coefficient_comparison.png
################################################################################

# ==============================================================================
# 0. SETUP
# ==============================================================================

rm(list = ls())

packages <- c(
  "tidyverse", "fixest", "did", "readxl", "lubridate",
  "modelsummary", "ggplot2", "patchwork", "broom"
)

load_or_install <- function(pkgs) {
  for (pkg in pkgs) {
    if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
      install.packages(pkg, repos = "https://cloud.r-project.org")
      library(pkg, character.only = TRUE)
    }
  }
}

load_or_install(packages)
theme_set(theme_minimal(base_size = 12))

cat("\n=============================================\n")
cat("SPORTS GAMBLING & EVICTIONS: DiD ANALYSIS\n")
cat("=============================================\n\n")

# ---- helpers -----------------------------------------------------------------

# Cut relative months into 6-month bins
cut_rel_time_months <- function(m) {
  case_when(
    is.na(m)            ~ NA_integer_,
    m <  -18            ~ -3L,
    m >= -18 & m < -12  ~ -2L,
    m >= -12 & m <  -6  ~ -1L,
    m >=  -6 & m <   0  ~  0L,
    m >=   0 & m <   6  ~  1L,
    m >=   6 & m <  12  ~  2L,
    m >=  12 & m <  18  ~  3L,
    m >=  18 & m <  24  ~  4L,
    m >=  24 & m <  36  ~  5L,
    TRUE                ~  6L
  )
}

# Extract event-study coefficients from a fixest model
# If treated_tag is supplied (e.g. "#treated"), restrict to those terms
# Helper: extract event-study coefficients from fixest model
extract_es <- function(model, pattern = "rel_time_bin", ref = 0L) {
  if (is.null(model)) return(NULL)
  
  cf   <- coef(model)
  se_v <- se(model)
  pv   <- pvalue(model)
  
  idx <- grepl(pattern, names(cf))
  
  tibble(
    rel_time_bin = as.integer(stringr::str_extract(names(cf)[idx], "-?\\d+")),
    coef         = cf[idx],
    se           = se_v[idx],
    pval         = pv[idx]
  ) %>%
    bind_rows(tibble(rel_time_bin = ref, coef = 0, se = 0, pval = 1)) %>%
    arrange(rel_time_bin) %>%
    mutate(
      ci_low  = coef - 1.96 * se,
      ci_high = coef + 1.96 * se
    )
}

# State abbreviation map for city data
abbrev_to_full <- c(
  "AZ" = "Arizona",      "CT" = "Connecticut", "DE" = "Delaware",
  "FL" = "Florida",      "IN" = "Indiana",     "LA" = "Louisiana",
  "MA" = "Massachusetts","MN" = "Minnesota",   "MO" = "Missouri",
  "NV" = "Nevada",       "NM" = "New Mexico",  "NY" = "New York",
  "OH" = "Ohio",         "PA" = "Pennsylvania","RI" = "Rhode Island",
  "SC" = "South Carolina","TN" = "Tennessee",  "TX" = "Texas",
  "VA" = "Virginia",     "WI" = "Wisconsin"
)

# ==============================================================================
# 1. LOAD GAMBLING TREATMENT DATA
# ==============================================================================

gambling <- readxl::read_excel("Gambing.xlsx") %>%
  mutate(
    State      = str_trim(State),
    treat_year = lubridate::year(First_Start)
  )

cat("Gambling treatment data loaded for",
    nrow(gambling), "states.\n\n")

# ==============================================================================
# 2. ANNUAL COURT DATA (STATE-YEAR PANEL)
# ==============================================================================

cat("Loading annual county court data...\n")

annual_raw <- readr::read_csv(
  "county_court-issued_2000_2023_ben_update_5_12.csv",
  show_col_types = FALSE
)

annual_panel <- annual_raw %>%
  mutate(state = str_trim(state)) %>%
  group_by(state, year) %>%
  summarise(
    evictions  = sum(filings_observed, na.rm = TRUE),
    n_counties = n(),
    .groups    = "drop"
  ) %>%
  filter(!is.na(state), !is.na(year)) %>%
  left_join(
    gambling %>% select(State, First_Start, Online),
    by = c("state" = "State")
  ) %>%
  mutate(
    treat_year    = lubridate::year(First_Start),
    treated       = if_else(!is.na(treat_year) & year >= treat_year, 1L, 0L),
    ever_treated  = if_else(!is.na(First_Start), 1L, 0L),
    log_evictions = log(evictions + 1)
  )

cat("Annual panel:", nrow(annual_panel), "obs,",
    n_distinct(annual_panel$state), "states.\n\n")

annual_switchers <- annual_panel %>%
  group_by(state) %>%
  summarise(
    ever_treated = first(ever_treated),
    treat_year   = first(treat_year),
    min_treated  = min(treated),
    max_treated  = max(treated),
    has_variation = min_treated != max_treated,
    .groups      = "drop"
  )

cat("Annual treatment variation:\n")
cat("  States with pre/post variation:", sum(annual_switchers$has_variation), "\n")
cat("  Always treated:", sum(annual_switchers$min_treated == 1), "\n")
cat("  Never treated:", sum(annual_switchers$max_treated == 0), "\n\n")

# Event-study relative time:
#  - For ever-treated states: year - treat_year
#  - For never-treated: set rel_time_years = NA; we’ll give them a dummy bin 0
annual_panel <- annual_panel %>%
  mutate(
    rel_time_years = if_else(
      ever_treated == 1L,
      year - treat_year,
      NA_integer_
    ),
    rel_time_bin = case_when(
      is.na(rel_time_years) ~ 0L,             # label for never-treated
      rel_time_years <= -5  ~ -5L,
      rel_time_years >=  5  ~  5L,
      TRUE                  ~ as.integer(rel_time_years)
    )
  )

# ==============================================================================
# 3. STATE MONTHLY PANEL (10 STATES)
# ==============================================================================

cat("Loading state monthly data...\n")

state_raw <- readr::read_csv(
  "allstates_monthly_2020_2021.csv",
  show_col_types = FALSE
)

state_monthly <- state_raw %>%
  mutate(
    date = lubridate::floor_date(
      lubridate::parse_date_time(
        month, orders = c("my", "ym", "ymd", "mdy")
      ),
      "month"
    )
  ) %>%
  filter(!is.na(date)) %>%
  group_by(state, date) %>%
  summarise(
    evictions            = sum(filings_2020, na.rm = TRUE),
    evictions_historical = sum(filings_avg,  na.rm = TRUE),
    .groups              = "drop"
  ) %>%
  left_join(
    gambling %>% select(State, First_Start, Online),
    by = c("state" = "State")
  ) %>%
  mutate(
    treat_year      = lubridate::year(First_Start),
    treated         = if_else(!is.na(First_Start) & date >= First_Start, 1L, 0L),
    ever_treated    = if_else(!is.na(First_Start), 1L, 0L),
    log_evictions   = log(evictions + 1),
    year            = lubridate::year(date),
    covid           = if_else(year %in% c(2020, 2021), 1L, 0L),
    rel_time_months = if_else(
      !is.na(First_Start),
      as.integer(lubridate::interval(First_Start, date) %/% months(1)),
      NA_integer_
    )
  ) %>%
  mutate(
    state = stringr::str_to_title(stringr::str_replace_all(state, "_", " ")),
    state = case_when(
      state == "Newmexico"   ~ "New Mexico",
      TRUE                   ~ state
    )
  )

cat("State monthly panel:", nrow(state_monthly), "obs,",
    n_distinct(state_monthly$state), "states.\n\n")

# ==============================================================================
# 4. CITY MONTHLY PANEL (36 CITIES, 20 STATES)
# ==============================================================================

cat("Loading city monthly data...\n")

city_raw <- readr::read_csv(
  "all_sites_monthly_2020_2021.csv",
  show_col_types = FALSE
)

city_panel <- city_raw %>%
  rename(
    evictions            = filings_2020,
    evictions_historical = filings_avg_prepandemic_baseline
  ) %>%
  mutate(
    state_abbrev = stringr::str_extract(city, "(?<=, )[A-Z]{2}$"),
    state_abbrev = dplyr::case_when(
      city %in% c("Fort Lauderdale", "Miami", "Palm Beach") ~ "FL",
      TRUE                                                 ~ state_abbrev
    ),
    state = abbrev_to_full[state_abbrev],
    date  = lubridate::parse_date_time(month, orders = "my")
  ) %>%
  filter(!is.na(date), !is.na(state)) %>%
  left_join(
    gambling %>% select(State, First_Start, Online),
    by = c("state" = "State")
  ) %>%
  mutate(
    treat_year      = lubridate::year(First_Start),
    treated         = if_else(!is.na(First_Start) & date >= First_Start, 1L, 0L),
    ever_treated    = if_else(!is.na(First_Start), 1L, 0L),
    log_evictions   = log(evictions + 1),
    year            = lubridate::year(date),
    covid           = if_else(year %in% c(2020, 2021), 1L, 0L),
    rel_time_months = if_else(
      !is.na(First_Start),
      as.integer(lubridate::interval(First_Start, date) %/% months(1)),
      NA_integer_
    )
  )

cat("City panel:", nrow(city_panel), "obs,",
    n_distinct(city_panel$city), "cities,",
    n_distinct(city_panel$state), "states.\n\n")

# Identify 'always treated' states in city data (no pre-period before Jan 2020)
data_start <- as.Date("2020-01-01")

city_treatment_timing <- city_panel %>%
  group_by(state) %>%
  summarise(
    First_Start  = first(First_Start),
    treat_year   = first(treat_year),
    ever_treated = first(ever_treated),
    n_cities     = n_distinct(city),
    .groups      = "drop"
  ) %>%
  mutate(
    months_pre_treat = if_else(
      !is.na(First_Start),
      pmax(0, as.numeric(difftime(First_Start, data_start, units = "days")) / 30),
      NA_real_
    ),
    treatment_status = case_when(
      ever_treated == 0              ~ "Never treated",
      months_pre_treat == 0          ~ "Always treated (no pre-period)",
      months_pre_treat < 12          ~ "Limited pre-period (<12 mo)",
      TRUE                           ~ "Good pre-period (12+ mo)"
    )
  )

always_treated_states <- city_treatment_timing %>%
  filter(treatment_status == "Always treated (no pre-period)") %>%
  pull(state)

cat("Always-treated states in city data:",
    paste(always_treated_states, collapse = ", "), "\n\n")

city_panel_clean <- city_panel %>%
  filter(!state %in% always_treated_states)
# 1. Start from your cleaned city panel with ONE row per city-month.
# If your current city_panel_clean is already aggregated, great.
# If not, enforce it explicitly:

city_panel_monthly <- city_panel_clean %>%
  group_by(city, state, date, First_Start) %>%   # add other grouping vars if needed
  summarise(
    log_evictions = mean(log_evictions, na.rm = TRUE),
    .groups = "drop"
  )

# Sanity check: should now be one row per city-month
city_panel_monthly %>%
  count(city, date) %>%
  summarise(min_n = min(n), max_n = max(n))
# You want min_n = 1 and max_n = 1

cat("Cleaned city panel:", nrow(city_panel_clean), "obs,",
    n_distinct(city_panel_clean$city), "cities,",
    n_distinct(city_panel_clean$state), "states.\n\n")

# ==============================================================================
# 5. EXPANDED MONTHLY PANEL (STATE + CITY AGGREGATED)
#    *** Methodological fix: only drop states that are treated in
#    *** EVERY observed month (always_treated_in_sample). Future-treated
#    *** states remain as controls.
# ==============================================================================

cat("Constructing expanded monthly panel (state + aggregated city)...\n")

monthly_states <- unique(state_monthly$state)

city_state_agg <- city_panel %>%
  filter(!state %in% monthly_states) %>%
  group_by(state, date) %>%
  summarise(
    evictions            = sum(evictions, na.rm = TRUE),
    evictions_historical = sum(evictions_historical, na.rm = TRUE),
    .groups              = "drop"
  ) %>%
  left_join(
    gambling %>% select(State, First_Start, Online),
    by = c("state" = "State")
  ) %>%
  mutate(source = "city_aggregated")

state_monthly_prep <- state_monthly %>%
  select(state, date, evictions, evictions_historical, First_Start, Online) %>%
  mutate(source = "state_monthly")

expanded_panel <- bind_rows(state_monthly_prep, city_state_agg) %>%
  mutate(
    treat_year      = lubridate::year(First_Start),
    treated         = if_else(!is.na(First_Start) & date >= First_Start, 1L, 0L),
    ever_treated    = if_else(!is.na(First_Start), 1L, 0L),
    log_evictions   = log(evictions + 1),
    year            = lubridate::year(date),
    covid           = if_else(year %in% c(2020, 2021), 1L, 0L),
    is_city_source  = if_else(source == "city_aggregated", 1L, 0L),
    rel_time_months = if_else(
      !is.na(First_Start),
      as.integer(lubridate::interval(First_Start, date) %/% months(1)),
      NA_integer_
    )
  )

cat("Expanded panel:", nrow(expanded_panel), "obs,",
    n_distinct(expanded_panel$state), "states.\n\n")

# Treatment status in expanded panel
exp_treatment <- expanded_panel %>%
  group_by(state) %>%
  summarise(
    source     = first(source),
    treat_date = first(First_Start),
    ever_treated = !all(is.na(First_Start)),
    min_treated  = min(treated),
    max_treated  = max(treated),
    treated_in_sample         = any(treated == 1),
    always_treated_in_sample  = all(treated == 1),
    .groups = "drop"
  )

always_treated_exp <- exp_treatment %>%
  filter(always_treated_in_sample) %>%
  pull(state)

expanded_panel_clean <- expanded_panel %>%
  filter(!state %in% always_treated_exp)

cat("Expanded panel (cleaned):", nrow(expanded_panel_clean), "obs,",
    n_distinct(expanded_panel_clean$state), "states.\n\n")

# ==============================================================================
# 6. COMBINED ANNUAL PANEL (USING MONTHLY WHERE AVAILABLE)
# ==============================================================================

state_monthly_annual <- state_monthly %>%
  mutate(year = lubridate::year(date)) %>%
  group_by(state, year) %>%
  summarise(
    evictions = sum(evictions, na.rm = TRUE),
    .groups   = "drop"
  ) %>%
  mutate(source = "monthly_aggregated")

monthly_state_list <- unique(state_monthly_annual$state)

annual_for_combine <- annual_panel %>%
  filter(!state %in% monthly_state_list) %>%
  select(state, year, evictions) %>%
  mutate(source = "annual")

combined_annual <- bind_rows(state_monthly_annual, annual_for_combine) %>%
  left_join(
    gambling %>% select(State, First_Start, Online),
    by = c("state" = "State")
  ) %>%
  mutate(
    treat_year     = lubridate::year(First_Start),
    treated        = if_else(!is.na(treat_year) & year >= treat_year, 1L, 0L),
    ever_treated   = if_else(!is.na(First_Start), 1L, 0L),
    log_evictions  = log(evictions + 1),
    rel_time_years = if_else(!is.na(treat_year),
                             year - treat_year,
                             NA_integer_)
  )

cat("Combined annual panel:", nrow(combined_annual), "obs,",
    n_distinct(combined_annual$state), "states.\n\n")

# ==============================================================================
# 7. ESTIMATION
# ==============================================================================

results_list <- list()

# ----------------------------------------------------------------------
# 7.1 Annual TWFE + improved event study
#     (keeps never-treated states in regression)
# ----------------------------------------------------------------------

cat("Annual TWFE + event study...\n")

m_annual <- feols(
  log_evictions ~ treated | state + year,
  data    = annual_panel,
  cluster = ~state
)

results_list[["Annual (51 states)"]] <- tibble(
  N_obs   = nrow(annual_panel),
  N_units = n_distinct(annual_panel$state),
  ATT     = coef(m_annual)["treated"],
  SE      = se(m_annual)["treated"],
  p_value = pvalue(m_annual)["treated"]
)
# Rebuild rel_time_years and rel_time_bin cleanly
annual_panel <- annual_panel %>%
  mutate(
    # event time only defined for ever-treated states
    rel_time_years = if_else(
      ever_treated == 1L,
      year - treat_year,
      NA_integer_
    ),
    # cap at +/-5 for treated states; keep NA on never-treated
    rel_time_bin = case_when(
      ever_treated == 0L              ~ NA_integer_,      # never-treated
      rel_time_years <= -5            ~ -5L,
      rel_time_years >=  5            ~  5L,
      TRUE                            ~ as.integer(rel_time_years)
    )
  )

# Event-study: interactions with ever_treated (group indicator),
# NOT the time-varying post dummy
m_annual_es <- feols(
  log_evictions ~ i(rel_time_bin, ever_treated, ref = -1) | state + year,
  data    = annual_panel,
  cluster = ~state
)

# This version of extract_es has no treated_tag argument — just use:
es_annual <- extract_es(
  m_annual_es,
  pattern = "rel_time_bin",
  ref     = -1L
)


# ----------------------------------------------------------------------
# 7.2 Combined annual TWFE
# ----------------------------------------------------------------------

m_comb <- feols(
  log_evictions ~ treated | state + year,
  data    = combined_annual,
  cluster = ~state
)

results_list[["Combined annual"]] <- tibble(
  N_obs   = nrow(combined_annual),
  N_units = n_distinct(combined_annual$state),
  ATT     = coef(m_comb)["treated"],
  SE      = se(m_comb)["treated"],
  p_value = pvalue(m_comb)["treated"]
)

# ----------------------------------------------------------------------
# 7.3 City-level TWFE (full, cleaned, variants) + event study
# ----------------------------------------------------------------------

cat("City-level models...\n")

m_city_full <- feols(
  log_evictions ~ treated | city + date,
  data    = city_panel,
  cluster = ~state
)

results_list[["City (full 36)"]] <- tibble(
  N_obs   = nrow(city_panel),
  N_units = n_distinct(city_panel$city),
  ATT     = coef(m_city_full)["treated"],
  SE      = se(m_city_full)["treated"],
  p_value = pvalue(m_city_full)["treated"]
)

m_city_clean <- feols(
  log_evictions ~ treated | city + date,
  data    = city_panel_clean,
  cluster = ~state
)

results_list[["City (cleaned)"]] <- tibble(
  N_obs   = nrow(city_panel_clean),
  N_units = n_distinct(city_panel_clean$city),
  ATT     = coef(m_city_clean)["treated"],
  SE      = se(m_city_clean)["treated"],
  p_value = pvalue(m_city_clean)["treated"]
)

city_panel_excl <- city_panel_clean %>%
  filter(!state_abbrev %in% c("TX", "FL", "NV"))

m_city_excl <- feols(
  log_evictions ~ treated | city + date,
  data    = city_panel_excl,
  cluster = ~state
)

results_list[["City (cleaned, excl. TX/FL/NV)"]] <- tibble(
  N_obs   = nrow(city_panel_excl),
  N_units = n_distinct(city_panel_excl$city),
  ATT     = coef(m_city_excl)["treated"],
  SE      = se(m_city_excl)["treated"],
  p_value = pvalue(m_city_excl)["treated"]
)

m_city_post <- feols(
  log_evictions ~ treated | city + date,
  data    = city_panel_clean %>% filter(date >= as.Date("2022-01-01")),
  cluster = ~state
)

results_list[["City (cleaned, post-2022)"]] <- tibble(
  N_obs   = nrow(city_panel_clean %>% filter(date >= as.Date("2022-01-01"))),
  N_units = n_distinct(city_panel_clean$city),
  ATT     = coef(m_city_post)["treated"],
  SE      = se(m_city_post)["treated"],
  p_value = pvalue(m_city_post)["treated"]
)

# Event-study for cleaned city panel
city_panel_clean <- city_panel_clean %>%
  mutate(rel_time_bin = cut_rel_time_months(rel_time_months))

m_city_es <- feols(
  log_evictions ~ i(rel_time_bin, ref = 0) | city + date,
  data    = city_panel_clean %>% filter(!is.na(rel_time_bin)),
  cluster = ~state
)

es_city <- extract_es(m_city_es, pattern = "rel_time_bin", ref = 0L)

# ----------------------------------------------------------------------
# 7.4 Expanded panel TWFE + event study (using cleaned panel)
# ----------------------------------------------------------------------

cat("Expanded panel models...\n")

m_exp_full <- feols(
  log_evictions ~ treated | state + date,
  data    = expanded_panel,
  cluster = ~state
)

results_list[["Expanded (full)"]] <- tibble(
  N_obs   = nrow(expanded_panel),
  N_units = n_distinct(expanded_panel$state),
  ATT     = coef(m_exp_full)["treated"],
  SE      = se(m_exp_full)["treated"],
  p_value = pvalue(m_exp_full)["treated"]
)

m_exp_clean <- feols(
  log_evictions ~ treated | state + date,
  data    = expanded_panel_clean,
  cluster = ~state
)

results_list[["Expanded (cleaned)"]] <- tibble(
  N_obs   = nrow(expanded_panel_clean),
  N_units = n_distinct(expanded_panel_clean$state),
  ATT     = coef(m_exp_clean)["treated"],
  SE      = se(m_exp_clean)["treated"],
  p_value = pvalue(m_exp_clean)["treated"]
)

m_exp_post <- feols(
  log_evictions ~ treated | state + date,
  data    = expanded_panel_clean %>% filter(date >= as.Date("2022-01-01")),
  cluster = ~state
)

results_list[["Expanded (cleaned, post-2022)"]] <- tibble(
  N_obs   = nrow(expanded_panel_clean %>% filter(date >= as.Date("2022-01-01"))),
  N_units = n_distinct(expanded_panel_clean$state),
  ATT     = coef(m_exp_post)["treated"],
  SE      = se(m_exp_post)["treated"],
  p_value = pvalue(m_exp_post)["treated"]
)

# Heterogeneity by data source (state vs city-sourced)
expanded_panel_clean <- expanded_panel_clean %>%
  mutate(
    treat_city  = treated * is_city_source,
    treat_state = treated * (1 - is_city_source)
  )

m_exp_het <- feols(
  log_evictions ~ treat_city + treat_state | state + date,
  data    = expanded_panel_clean,
  cluster = ~state
)

# Event-study on expanded panel (cleaned)
expanded_panel_clean <- expanded_panel_clean %>%
  mutate(rel_time_bin = cut_rel_time_months(rel_time_months))

m_exp_es <- feols(
  log_evictions ~ i(rel_time_bin, ref = 0) | state + date,
  data    = expanded_panel_clean %>% filter(!is.na(rel_time_bin)),
  cluster = ~state
)

es_exp <- extract_es(m_exp_es, pattern = "rel_time_bin", ref = 0L)

# ==============================================================================
# 8. CALLAWAY–SANT'ANNA ESTIMATORS (CITY & ANNUAL)
# ==============================================================================

# ==============================================================================
# 8. CALLAWAY–SANT'ANNA ESTIMATORS (CITY & ANNUAL)
# ==============================================================================

cat("Callaway–Sant'Anna estimators...\n")

# City (cleaned)
city_cs <- city_panel_clean %>%
  mutate(
    city_id    = as.integer(factor(city)),
    time_index = as.integer(difftime(date, min(date), units = "days") / 30),
    first_treat = if_else(
      is.na(First_Start),
      0L,
      as.integer(difftime(First_Start, min(date), units = "days") / 30)
    )
  ) %>%
  filter(!is.na(log_evictions)) %>%
  as.data.frame()

cs_city <- tryCatch(
  att_gt(
    yname  = "log_evictions",
    tname  = "time_index",
    idname = "city_id",
    gname  = "first_treat",
    data   = city_cs,
    control_group = "nevertreated",
    base_period   = "universal",
    panel         = FALSE
  ),
  error = function(e) { message("CS (city) error: ", e$message); NULL }
)

if (!is.null(cs_city)) {
  cs_city_simple <- aggte(cs_city, type = "simple", na.rm = TRUE)
  
  cat(
    "CS city overall ATT:",
    round(cs_city_simple$overall.att, 4),
    "SE:", round(cs_city_simple$overall.se, 4), "\n"
  )
  
  # Optional: drop CS into the main results table
  results_list[["City (CS simple)"]] <- tibble(
    N_obs   = nrow(city_cs),
    N_units = dplyr::n_distinct(city_cs$city_id),
    ATT     = cs_city_simple$overall.att,
    SE      = cs_city_simple$overall.se,
    # back-of-the-envelope p-value
    p_value = 2 * (1 - pnorm(abs(cs_city_simple$overall.att /
                                   cs_city_simple$overall.se)))
  )
}



nrow(city_cs)
# 661315

summarise(city_cs,
          n_cities  = n_distinct(city_id),
          n_periods = n_distinct(time_index),
          n_groups  = n_distinct(first_treat)
)
# n_cities n_periods n_groups
#       28        71        7


max_year <- max(annual_panel$year, na.rm = TRUE)

annual_cs <- annual_panel %>%
  mutate(
    state_id = as.integer(factor(state)),
    first_treat = case_when(
      is.na(treat_year)           ~ 0L,                # never treated
      treat_year > max_year       ~ 0L,                # treated after sample ends -> never-treated here
      TRUE                        ~ as.integer(treat_year)
    )
  ) %>%
  filter(!is.na(log_evictions)) %>%
  as.data.frame()


cs_annual <- tryCatch(
  att_gt(
    yname  = "log_evictions",
    tname  = "year",
    idname = "state_id",
    gname  = "first_treat",
    data   = annual_cs,
    control_group = "nevertreated",
    base_period   = "universal"
  ),
  error = function(e) { message("CS (annual) error: ", e$message); NULL }
)

if (!is.null(cs_annual)) {
  cs_annual_simple <- aggte(cs_annual, type = "simple")
  cat("CS annual overall ATT:",
      round(cs_annual_simple$overall.att, 4),
      "SE:", round(cs_annual_simple$overall.se, 4), "\n\n")
}

# ==============================================================================
# 9. RESULTS TABLE + COEFFICIENT PLOT
# ==============================================================================

results_table <- bind_rows(results_list, .id = "Specification") %>%
  mutate(
    pct_change = (exp(ATT) - 1) * 100,
    across(c(ATT, SE, p_value, pct_change), ~ round(., 4))
  )

print(results_table)
readr::write_csv(results_table, "did_results_comprehensive.csv")

p_coef <- ggplot(results_table,
                 aes(x = ATT, y = reorder(Specification, ATT))) +
  geom_vline(xintercept = 0, linewidth = 1) +
  geom_errorbarh(aes(xmin = ATT - 1.96 * SE,
                     xmax = ATT + 1.96 * SE),
                 height = 0.2) +
  geom_point(size = 3, color = "steelblue") +
  labs(
    title = "Effect Estimates Across Specifications",
    x     = "ATT (Log Evictions)",
    y     = NULL
  ) +
  xlim(-0.6, 0.6)

ggsave("coefficient_comparison.png", p_coef,
       width = 10, height = 6, dpi = 150)

# ==============================================================================
# 10. VISUALIZATIONS: EVENT STUDIES & TRENDS
# ==============================================================================

bin_labels <- c(
  "-3" = "<-18mo", "-2" = "-18 to -12", "-1" = "-12 to -6",
  "0"  = "-6 to 0", "1"  = "0–6mo", "2" = "6–12mo",
  "3"  = "12–18mo", "4" = "18–24mo", "5" = "24–36mo",
  "6"  = "36+mo"
)

# --- Annual event study -------------------------------------------------------

annual_bin_labels <- c(
  "-5" = "≤-5", "-4" = "-4", "-3" = "-3", "-2" = "-2", "-1" = "-1",
  "0"  = "0", "1" = "+1", "2" = "+2", "3" = "+3", "4" = "+4", "5" = "≥+5"
)

p_es_annual <- ggplot(es_annual, aes(x = rel_time_bin, y = coef)) +
  geom_ribbon(aes(ymin = ci_low, ymax = ci_high),
              alpha = 0.3, fill = "steelblue") +
  geom_line(color = "steelblue", linewidth = 1) +
  geom_point(color = "steelblue", size = 3) +
  geom_hline(yintercept = 0, linewidth = 0.5) +
  geom_vline(xintercept = -0.5, linetype = "dashed",
             color = "red", linewidth = 1) +
  scale_x_continuous(
    breaks = es_annual$rel_time_bin,
    labels = annual_bin_labels[as.character(es_annual$rel_time_bin)]
  ) +
  labs(
    title    = "Event Study: Annual Court Data (51 States)",
    subtitle = "Reference period: 1 year before treatment (treated states)",
    x        = "Years Relative to Treatment",
    y        = "Effect on Log Evictions"
  )

ggsave("event_study_annual.png", p_es_annual,
       width = 10, height = 6, dpi = 150)

# --- Annual treated vs control trends ----------------------------------------

annual_trends <- annual_panel %>%
  group_by(year, ever_treated) %>%
  summarise(
    log_evictions = mean(log_evictions, na.rm = TRUE),
    .groups       = "drop"
  ) %>%
  mutate(group = if_else(ever_treated == 1, "Treated", "Control"))

p_trends_annual <- ggplot(annual_trends,
                          aes(x = year, y = log_evictions, color = group)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 2) +
  geom_vline(xintercept = 2018, linetype = "dashed", alpha = 0.5) +
  scale_color_manual(values = c("Treated" = "steelblue",
                                "Control" = "orange")) +
  labs(
    title    = "Treated vs Control Trends: Annual Court Data",
    subtitle = "Vertical line = first state legalizes (2018)",
    x        = "Year",
    y        = "Log Evictions",
    color    = NULL
  ) +
  theme(legend.position = "bottom")

ggsave("trends_annual.png", p_trends_annual,
       width = 10, height = 6, dpi = 150)

# --- City event study (cleaned) ----------------------------------------------

p_es_city <- ggplot(es_city, aes(x = rel_time_bin, y = coef)) +
  geom_ribbon(aes(ymin = ci_low, ymax = ci_high),
              alpha = 0.3, fill = "darkgreen") +
  geom_line(color = "darkgreen", linewidth = 1) +
  geom_point(color = "darkgreen", size = 3) +
  geom_hline(yintercept = 0) +
  geom_vline(xintercept = 0.5, linetype = "dashed", color = "red") +
  scale_x_continuous(
    breaks = es_city$rel_time_bin,
    labels = bin_labels[as.character(es_city$rel_time_bin)]
  ) +
  labs(
    title    = "Event Study: City-Level (Cleaned Sample)",
    subtitle = "Excluding 'always treated' states (no pre-period)",
    x        = "6-Month Periods Relative to Treatment",
    y        = "Effect on Log Evictions"
  ) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave("event_study_city_cleaned.png", p_es_city,
       width = 10, height = 6, dpi = 150)

# --- Expanded event study (cleaned) -----------------------------------------

p_es_expanded <- ggplot(es_exp, aes(x = rel_time_bin, y = coef)) +
  geom_ribbon(aes(ymin = ci_low, ymax = ci_high),
              alpha = 0.3, fill = "purple") +
  geom_line(color = "purple", linewidth = 1) +
  geom_point(color = "purple", size = 3) +
  geom_hline(yintercept = 0, linewidth = 0.5) +
  geom_vline(xintercept = 0.5, linetype = "dashed",
             color = "red", linewidth = 1) +
  scale_x_continuous(
    breaks = es_exp$rel_time_bin,
    labels = bin_labels[as.character(es_exp$rel_time_bin)]
  ) +
  labs(
    title    = "Event Study: Expanded Panel (State + City Combined)",
    subtitle = paste0(
      "Cleaned sample: ",
      n_distinct(expanded_panel_clean$state),
      " states (excluding always-treated-in-sample)"
    ),
    x = "6-Month Periods Relative to Treatment",
    y = "Effect on Log Evictions"
  ) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave("event_study_expanded_cleaned.png", p_es_expanded,
       width = 10, height = 6, dpi = 150)

# --- City vs Expanded comparison --------------------------------------------

es_city_plot <- es_city %>% mutate(panel = "City (cleaned)")
es_exp_plot  <- es_exp  %>% mutate(panel = "Expanded (state + city)")

es_combined <- bind_rows(es_city_plot, es_exp_plot)

p_comparison <- ggplot(es_combined,
                       aes(x = rel_time_bin, y = coef,
                           color = panel, fill = panel)) +
  geom_ribbon(aes(ymin = ci_low, ymax = ci_high),
              alpha = 0.2, color = NA) +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  geom_hline(yintercept = 0) +
  geom_vline(xintercept = 0.5, linetype = "dashed", color = "red") +
  scale_x_continuous(
    breaks = -3:6,
    labels = bin_labels[as.character(-3:6)]
  ) +
  scale_color_manual(values = c("City (cleaned)" = "darkgreen",
                                "Expanded (state + city)" = "purple")) +
  scale_fill_manual(values  = c("City (cleaned)" = "darkgreen",
                                "Expanded (state + city)" = "purple")) +
  labs(
    title = "Event Study Comparison: City vs Expanded Panel",
    x     = "6-Month Periods Relative to Treatment",
    y     = "Effect on Log Evictions",
    color = "Sample",
    fill  = "Sample"
  ) +
  theme(
    axis.text.x  = element_text(angle = 45, hjust = 1),
    legend.position = "bottom"
  )

ggsave("event_study_comparison.png", p_comparison,
       width = 12, height = 6, dpi = 150)

# ==============================================================================
# 11. FINAL CONSOLE SUMMARY
# ==============================================================================

cat("\n=============================================\n")
cat("FINAL SUMMARY\n")
cat("=============================================\n")
cat("Key models written to did_results_comprehensive.csv\n")
cat("Figures saved:\n")
cat("  trends_annual.png\n")
cat("  event_study_annual.png\n")
cat("  event_study_city_cleaned.png\n")
cat("  event_study_expanded_cleaned.png\n")
cat("  event_study_comparison.png\n")
cat("  coefficient_comparison.png\n")
cat("=============================================\n\n")
