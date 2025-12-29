################################################################################
# SPORTS GAMBLING AND EVICTIONS: DIFFERENCE-IN-DIFFERENCES ANALYSIS
# Clean, single-script version
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
################################################################################

# ==============================================================================
# 0. SETUP
# ==============================================================================

rm(list = ls())

packages <- c(
  "tidyverse", "fixest", "did", "readxl", "lubridate",
  "modelsummary", "ggplot2", "broom"
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

# Helper: cut relative months into 6-month bins
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

# Helper: extract event-study coefficients from a fixest model
# where the i() generated names like "rel_time_bin::0"
extract_es <- function(model, pattern = "rel_time_bin::", ref = 0L) {
  if (is.null(model)) return(NULL)
  
  cf   <- coef(model)
  se_v <- se(model)
  pv   <- pvalue(model)
  
  idx  <- grepl(pattern, names(cf), fixed = TRUE)
  if (!any(idx)) return(NULL)
  
  lbls <- names(cf)[idx]
  
  tibble(
    rel_time_bin = as.integer(stringr::str_extract(lbls, "-?\\d+")),
    coef         = unname(cf[idx]),
    se           = unname(se_v[idx]),
    pval         = unname(pv[idx])
  ) %>%
    bind_rows(
      tibble(rel_time_bin = ref, coef = 0, se = 0, pval = 1)
    ) %>%
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
    State      = stringr::str_trim(State),
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
  mutate(state = stringr::str_trim(state)) %>%
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
    treat_year     = lubridate::year(First_Start),
    treated        = if_else(!is.na(treat_year) & year >= treat_year, 1L, 0L),
    ever_treated   = if_else(!is.na(First_Start), 1L, 0L),
    log_evictions  = log(evictions + 1),
    rel_time_years = if_else(!is.na(treat_year),
                             year - treat_year,
                             NA_integer_)
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
    has_variation = (min_treated != max_treated),
    n_pre        = sum(treated == 0),
    n_post       = sum(treated == 1),
    .groups      = "drop"
  )

cat("Annual treatment variation:\n")
cat("  States with pre/post variation:", sum(annual_switchers$has_variation), "\n")
cat("  Always treated:", sum(annual_switchers$min_treated == 1), "\n")
cat("  Never treated:", sum(annual_switchers$max_treated == 0), "\n\n")

annual_treated_states <- annual_panel %>%
  filter(ever_treated == 1L) %>%
  distinct(state) %>%
  arrange(state) %>%
  pull(state)

cat("Treated states in ANNUAL panel:\n")
print(annual_treated_states)

# ==============================================================================
# 3. STATE MONTHLY PANEL (10 STATES)
# ==============================================================================

cat("\nLoading state monthly data...\n")

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
    evictions             = sum(filings_2020, na.rm = TRUE),
    evictions_historical  = sum(filings_avg,  na.rm = TRUE),
    .groups               = "drop"
  ) %>%
  # Fix state name formatting
  mutate(
    state = stringr::str_to_title(stringr::str_replace_all(state, "_", " ")),
    state = dplyr::case_when(
      state == "Newmexico" ~ "New Mexico",
      TRUE                 ~ state
    )
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
  )

cat("State monthly panel:", nrow(state_monthly), "obs,",
    n_distinct(state_monthly$state), "states.\n\n")

state_switchers <- state_monthly %>%
  group_by(state) %>%
  summarise(
    ever_treated = first(ever_treated),
    treat_date   = first(First_Start),
    min_treated  = min(treated),
    max_treated  = max(treated),
    has_variation = (min_treated != max_treated),
    n_pre        = sum(treated == 0),
    n_post       = sum(treated == 1),
    .groups      = "drop"
  )

cat("State monthly treatment variation:\n")
print(state_switchers %>% select(state, treat_date, has_variation, n_pre, n_post))

# ==============================================================================
# 4. CITY MONTHLY PANEL (36 CITIES, 20 STATES)
# ==============================================================================

cat("\nLoading city monthly data...\n")

city_raw <- readr::read_csv(
  "all_sites_monthly_2020_2021.csv",
  show_col_types = FALSE
)

city_panel <- city_raw %>%
  rename(
    evictions             = filings_2020,
    evictions_historical  = filings_avg_prepandemic_baseline
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

# --- Identify and drop 'always treated' states in city data (for DiD) ---------

data_start <- as.Date("2020-01-01")

city_timing <- city_panel %>%
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

always_treated_states <- city_timing %>%
  filter(treatment_status == "Always treated (no pre-period)") %>%
  pull(state)

cat("Always-treated states in city data (no pre-period):\n")
print(always_treated_states)

city_panel_clean <- city_panel %>%
  filter(!state %in% always_treated_states)

cat("\nCleaned city panel:", nrow(city_panel_clean), "obs,",
    n_distinct(city_panel_clean$city), "cities,",
    n_distinct(city_panel_clean$state), "states.\n\n")

city_treated_states <- city_panel_clean %>%
  filter(ever_treated == 1L) %>%
  distinct(state) %>%
  arrange(state) %>%
  pull(state)

cat("Treated states in CLEANED CITY panel:\n")
print(city_treated_states)

# ==============================================================================
# 5. EXPANDED MONTHLY PANEL (STATE + AGGREGATED CITY)
#   — UNION OF STATE-MONTHLY AND CITY STATES, NO DROPPING OF TREATED STATES
# ==============================================================================

cat("\nConstructing expanded monthly panel (state + aggregated city)...\n")

monthly_states <- unique(state_monthly$state)

city_state_agg <- city_panel %>%
  filter(!state %in% monthly_states) %>%
  group_by(state, date) %>%
  summarise(
    evictions             = sum(evictions, na.rm = TRUE),
    evictions_historical  = sum(evictions_historical, na.rm = TRUE),
    .groups               = "drop"
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

expanded_treated_states <- expanded_panel %>%
  filter(ever_treated == 1L) %>%
  distinct(state) %>%
  arrange(state) %>%
  pull(state)

cat("Treated states in EXPANDED monthly panel:\n")
print(expanded_treated_states)

cat("\nTreated state sets:\n")
print(list(
  annual_treated   = annual_treated_states,
  city_treated     = city_treated_states,
  expanded_treated = expanded_treated_states
))

# ==============================================================================
# 6. TWFE MODELS
# ==============================================================================

results_list <- list()

## 6.1 Annual TWFE -------------------------------------------------------------

cat("\nEstimating TWFE on ANNUAL panel...\n")

m_annual <- feols(
  log_evictions ~ treated | state + year,
  data    = annual_panel,
  cluster = ~state
)

results_list[["Annual (state-year)"]] <- tibble(
  N_obs   = nrow(annual_panel),
  N_units = n_distinct(annual_panel$state),
  ATT     = coef(m_annual)["treated"],
  SE      = se(m_annual)["treated"],
  p_value = pvalue(m_annual)["treated"]
)

## 6.2 City-level TWFE (full / cleaned / post) --------------------------------

cat("Estimating city-level TWFE models...\n")

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

results_list[["City (cleaned, drop always-treated states)"]] <- tibble(
  N_obs   = nrow(city_panel_clean),
  N_units = n_distinct(city_panel_clean$city),
  ATT     = coef(m_city_clean)["treated"],
  SE      = se(m_city_clean)["treated"],
  p_value = pvalue(m_city_clean)["treated"]
)

m_city_post <- feols(
  log_evictions ~ treated | city + date,
  data    = city_panel_clean %>% filter(date >= as.Date("2022-01-01")),
  cluster = ~state
)

results_list[["City (cleaned, 2022+)"]] <- tibble(
  N_obs   = nrow(city_panel_clean %>% filter(date >= as.Date("2022-01-01"))),
  N_units = n_distinct(city_panel_clean$city),
  ATT     = coef(m_city_post)["treated"],
  SE      = se(m_city_post)["treated"],
  p_value = pvalue(m_city_post)["treated"]
)

## 6.3 Expanded panel TWFE -----------------------------------------------------

cat("Estimating expanded monthly TWFE models...\n")

m_expanded <- feols(
  log_evictions ~ treated | state + date,
  data    = expanded_panel,
  cluster = ~state
)

results_list[["Expanded monthly (state + city agg)"]] <- tibble(
  N_obs   = nrow(expanded_panel),
  N_units = n_distinct(expanded_panel$state),
  ATT     = coef(m_expanded)["treated"],
  SE      = se(m_expanded)["treated"],
  p_value = pvalue(m_expanded)["treated"]
)

m_expanded_post <- feols(
  log_evictions ~ treated | state + date,
  data    = expanded_panel %>% filter(date >= as.Date("2022-01-01")),
  cluster = ~state
)

results_list[["Expanded (2022+)"]] <- tibble(
  N_obs   = nrow(expanded_panel %>% filter(date >= as.Date("2022-01-01"))),
  N_units = n_distinct(expanded_panel$state),
  ATT     = coef(m_expanded_post)["treated"],
  SE      = se(m_expanded_post)["treated"],
  p_value = pvalue(m_expanded_post)["treated"]
)

# ==============================================================================
# 7. EVENT STUDIES (ANNUAL, CITY, EXPANDED)
# ==============================================================================

## 7.1 Annual event study ------------------------------------------------------

annual_panel <- annual_panel %>%
  mutate(
    rel_time_bin = case_when(
      ever_treated == 1L & !is.na(rel_time_years) ~ pmin(pmax(rel_time_years, -5L), 5L),
      TRUE                                        ~ NA_integer_
    )
  )

m_annual_es <- feols(
  log_evictions ~ i(rel_time_bin, ref = -1) | state + year,
  data    = annual_panel %>% filter(!is.na(rel_time_bin)),
  cluster = ~state
)

es_annual <- extract_es(m_annual_es, pattern = "rel_time_bin::", ref = -1L)

## 7.2 City event study (cleaned) ---------------------------------------------

city_panel_clean <- city_panel_clean %>%
  mutate(
    rel_time_bin = cut_rel_time_months(rel_time_months),
    rel_time_bin = if_else(ever_treated == 1L, rel_time_bin, NA_integer_)
  )

m_city_es <- feols(
  log_evictions ~ i(rel_time_bin, ref = 0) | city + date,
  data    = city_panel_clean %>% filter(!is.na(rel_time_bin)),
  cluster = ~state
)

es_city <- extract_es(m_city_es, pattern = "rel_time_bin::", ref = 0L)

## 7.3 Expanded panel event study ---------------------------------------------

expanded_panel <- expanded_panel %>%
  mutate(
    rel_time_bin = cut_rel_time_months(rel_time_months),
    rel_time_bin = if_else(ever_treated == 1L, rel_time_bin, NA_integer_)
  )

m_exp_es <- feols(
  log_evictions ~ i(rel_time_bin, ref = 0) | state + date,
  data    = expanded_panel %>% filter(!is.na(rel_time_bin)),
  cluster = ~state
)

es_exp <- extract_es(m_exp_es, pattern = "rel_time_bin::", ref = 0L)

# ==============================================================================
# 8. CALLAWAY–SANT'ANNA (OPTIONAL ROBUSTNESS)
# ==============================================================================

cat("\nRunning Callaway–Sant'Anna (this can generate warnings; that's fine)...\n")

## 8.1 Annual CS ---------------------------------------------------------------

annual_cs <- annual_panel %>%
  mutate(
    state_id   = as.integer(factor(state)),
    first_treat = if_else(is.na(treat_year), 0L, as.integer(treat_year))
  ) %>%
  filter(!is.na(log_evictions)) %>%
  as.data.frame()

cs_annual <- tryCatch(
  att_gt(
    yname        = "log_evictions",
    tname        = "year",
    idname       = "state_id",
    gname        = "first_treat",
    data         = annual_cs,
    control_group = "nevertreated",
    bstrap       = TRUE,
    clustervars  = "state_id",
    panel        = FALSE
  ),
  error = function(e) { message("CS (annual) error: ", e$message); NULL }
)

if (!is.null(cs_annual)) {
  cs_annual_simple <- aggte(cs_annual, type = "simple", na.rm = TRUE)
  cat("CS annual overall ATT:",
      round(cs_annual_simple$overall.att, 4),
      "SE:", round(cs_annual_simple$overall.se, 4), "\n\n")
}

## 8.2 City CS (cleaned) ------------------------------------------------------

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
    yname        = "log_evictions",
    tname        = "time_index",
    idname       = "city_id",
    gname        = "first_treat",
    data         = city_cs,
    control_group = "nevertreated",
    base_period   = "universal",
    panel         = FALSE
  ),
  error = function(e) { message("CS (city) error: ", e$message); NULL }
)

if (!is.null(cs_city)) {
  cs_city_simple <- aggte(cs_city, type = "simple", na.rm = TRUE)
  cat("CS city overall ATT:",
      round(cs_city_simple$overall.att, 4),
      "SE:", round(cs_city_simple$overall.se, 4), "\n\n")
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

## Annual ES plot -------------------------------------------------------------

annual_bin_labels <- c(
  "-5" = "≤-5", "-4" = "-4", "-3" = "-3", "-2" = "-2", "-1" = "-1",
  "0"  = "0", "1" = "+1", "2" = "+2", "3" = "+3", "4" = "+4", "5" = "≥+5"
)

if (!is.null(es_annual)) {
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
      subtitle = "Reference period: 1 year before treatment",
      x        = "Years Relative to Treatment",
      y        = "Effect on Log Evictions"
    )
  
  ggsave("event_study_annual.png", p_es_annual,
         width = 10, height = 6, dpi = 150)
}

## Annual treated vs control trends -------------------------------------------

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

## City ES plot (cleaned) -----------------------------------------------------

if (!is.null(es_city)) {
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
      subtitle = "Excluding always-treated states with no pre-period",
      x        = "6-Month Periods Relative to Treatment",
      y        = "Effect on Log Evictions"
    ) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  
  ggsave("event_study_city_cleaned.png", p_es_city,
         width = 10, height = 6, dpi = 150)
}

## Expanded ES plot -----------------------------------------------------------

if (!is.null(es_exp)) {
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
      title    = "Event Study: Expanded Panel (State + City Aggregated)",
      subtitle = paste0(
        "All treated states kept; ",
        n_distinct(expanded_panel$state), " states total"
      ),
      x = "6-Month Periods Relative to Treatment",
      y = "Effect on Log Evictions"
    ) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  
  ggsave("event_study_expanded_cleaned.png", p_es_expanded,
         width = 10, height = 6, dpi = 150)
}

## City vs Expanded comparison -------------------------------------------------

if (!is.null(es_city) && !is.null(es_exp)) {
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
}

# ==============================================================================
# 11. FINAL SUMMARY
# ==============================================================================

cat("\n=============================================\n")
cat("FINAL SUMMARY\n")
cat("=============================================\n")
cat("Key TWFE models written to did_results_comprehensive.csv\n")
cat("Figures saved:\n")
cat("  trends_annual.png\n")
cat("  event_study_annual.png\n")
cat("  event_study_city_cleaned.png\n")
cat("  event_study_expanded_cleaned.png\n")
cat("  event_study_comparison.png\n")
cat("  coefficient_comparison.png\n")
cat("=============================================\n\n")





annual_panel %>%
  mutate(group = if_else(ever_treated == 1L, "Treated", "Control")) %>%
  count(year, group) %>%
  tidyr::pivot_wider(names_from = group, values_from = n) %>% 
  print(n = Inf)





ctrl_diag <- annual_panel %>% 
  filter(ever_treated == 0L) %>% 
  group_by(year) %>%
  mutate(
    mean_log = mean(log_evictions, na.rm = TRUE),
    sd_log   = sd(log_evictions, na.rm = TRUE),
    z        = (log_evictions - mean_log) / sd_log
  ) %>%
  ungroup()

# Look at control outliers after 2018
ctrl_diag18<-ctrl_diag %>% 
  filter(year >= 2018) %>% 
  arrange(desc(z)) %>% 
  select(year, state, evictions, log_evictions, z) %>% 
  head(30)





good_states <- annual_panel %>%
  group_by(state) %>%
  summarise(
    min_year = min(year),
    max_year = max(year),
    .groups = "drop"
  ) %>%
  filter(min_year <= 2008, max_year >= 2023) %>%
  pull(state)

annual_trends_bal <- annual_panel %>%
  filter(state %in% good_states) %>%
  group_by(year, ever_treated) %>%
  summarise(
    mean_log = mean(log_evictions, na.rm = TRUE),
    median_log = median(log_evictions, na.rm = TRUE),
    .groups = "drop"
  )




p_trends_bal <- annual_trends_bal %>%
  mutate(group = if_else(ever_treated == 1L, "Treated", "Control")) %>%
  ggplot(aes(x = year, y = median_log, color = group)) +
  geom_line() +
  geom_point() +
  geom_vline(xintercept = 2018, linetype = "dashed") +
  labs(
    title = "Treated vs Control (Median, Balanced-ish Sample)",
    y = "Median log evictions"
  )




annual_panel_nid <- annual_panel %>%
  filter(state != "Idaho")
m_annual_nid <- feols(
  log_evictions ~ treated | state + year,
  data    = annual_panel_nid,
  cluster = ~state
)

coef(m_annual_nid)["treated"]
se(m_annual_nid)["treated"]



annual_trends_nid <- annual_panel_nid %>%
  group_by(year, ever_treated) %>%
  summarise(
    log_evictions = mean(log_evictions, na.rm = TRUE),
    .groups       = "drop"
  ) %>%
  mutate(group = if_else(ever_treated == 1L, "Treated", "Control"))

ggplot(annual_trends_nid,
       aes(x = year, y = log_evictions, color = group)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 2) +
  geom_vline(xintercept = 2018, linetype = "dashed", alpha = 0.5) +
  labs(
    title    = "Treated vs Control Trends: Annual Court Data (Idaho excluded)",
    subtitle = "Control group excludes Idaho due to clearly erroneous filings",
    x        = "Year",
    y        = "Log evictions",
    color    = NULL
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")



library(tidyverse)
library(readxl)
library(lubridate)

gambling <- read_excel("Gambing.xlsx") |>
  mutate(
    State      = str_trim(State),
    legal_year = year(First_Start),
    cohort = case_when(
      legal_year %in% 2018 ~ "wave_2018",
      legal_year %in% 2019 ~ "wave_2019",
      legal_year %in% 2020 ~ "wave_2020",
      legal_year %in% 2021 ~ "wave_2021",
      legal_year %in% 2022 ~ "wave_2022",
      legal_year %in% 2023 ~ "wave_2023",
      TRUE                 ~ "never"
    )
  )

# Sanity check: who’s in each year/cohort
split(gambling$State, gambling$legal_year)
table(gambling$legal_year)
table(gambling$cohort)
annual_panel <- read_csv("annual_state_panel.csv", show_col_types = FALSE) %>%
  rename(state = State,
         evictions = annual_evictions) %>%
  left_join(
    gambling %>% select(State, First_Start, Online),
    by = c("state" = "State")
  ) %>%
  mutate(
    treat_year      = lubridate::year(First_Start),
    treated         = if_else(!is.na(First_Start) & year >= treat_year, 1L, 0L),
    ever_treated    = if_else(!is.na(First_Start), 1L, 0L),
    log_evictions   = log(evictions + 1),
    rel_time_years  = if_else(
      !is.na(First_Start),
      as.integer(year - treat_year),
      NA_integer_
    )
  )







controls<- annual_panel %>%
  mutate(group = if_else(ever_treated == 1L, "Treated", "Control")) %>%
  group_by(year, group) %>%
  summarise(
    n_states = n_distinct(state),
    states   = paste(sort(unique(state)), collapse = ", "),
    .groups  = "drop"
  ) %>%
  arrange(year, group)

write_csv(controls, "annual_panel_control_states_by_year.csv")


filing_changes<-annual_panel %>%
  filter(ever_treated == 0L) %>%              # controls only
  arrange(state, year) %>%
  group_by(state) %>%
  mutate(delta = log_evictions - dplyr::lag(log_evictions)) %>%
  ungroup() %>%
  filter(year >= 2015) %>%                    # focus on the weird period
  arrange(delta) %>%                          # biggest drops first
  select(state, year, evictions, log_evictions, delta)

write_csv(filing_changes, "annual_panel_control_filing_changes_2015_2023.csv")






bad_controls <- c("California", "Utah", "Vermont", "Minnesota", "Idaho")

annual_clean <- annual_panel %>%
  filter(!(state %in% bad_controls & ever_treated == 0L))



annual_panel_bc <- annual_clean %>%
  filter(state != "Idaho")
m_annual_bc <- feols(
  log_evictions ~ treated | state + year,
  data    = annual_panel_bc,
  cluster = ~state
)

coef(m_annual_bc)["treated"]
se(m_annual_bc)["treated"]



annual_trends_bc <- annual_clean %>%
  group_by(year, ever_treated) %>%
  summarise(
    log_evictions = mean(log_evictions, na.rm = TRUE),
    .groups       = "drop"
  ) %>%
  mutate(group = if_else(ever_treated == 1L, "Treated", "Control"))


ggplot(annual_trends_bc,
       aes(x = year, y = log_evictions, color = group)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 2) +
  geom_vline(xintercept = 2018, linetype = "dashed", alpha = 0.5) +
  labs(
    title    = "Treated vs Control Trends: Annual Court Data (Idaho excluded)",
    subtitle = "Control group excludes Idaho due to clearly erroneous filings",
    x        = "Year",
    y        = "Log evictions",
    color    = NULL
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")

annual_panel %>%
  mutate(group = if_else(ever_treated == 1L, "Treated", "Control")) %>%
  count(year, group) %>%
  pivot_wider(names_from = group, values_from = n)





# Pre-COVID sample (2000–2019)
m_pre <- feols(
  log_evictions ~ treated | state + year,
  data    = annual_panel %>% filter(year <= 2019),
  cluster = ~state
)

coef(m_pre)["treated"]
se(m_pre)["treated"]


# Post-COVID sample (2020–2023) – mostly useless, but for comparison
m_post <- feols(
  log_evictions ~ treated | state + year,
  data    = annual_panel %>% filter(year >= 2020),
  cluster = ~state
)

coef(m_post)["treated"]
se(m_post)["treated"]


annual_pre2019 <- annual_panel |>
  filter(year <= 2019) |>
  filter(cohort %in% c("wave_2018", "wave_2019", "never"))

m_pre_early <- feols(
  log_evictions ~ treated | state + year,
  data    = annual_pre2019,
  cluster = ~state
)

