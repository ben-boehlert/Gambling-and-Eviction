# ============================================================
# Fixed Sun-Abraham and DiD Analysis
# Aggregates monthly data into clean panel and runs proper estimators
# ============================================================

library(tidyverse)
library(lubridate)
library(fixest)
library(did)
library(didimputation)

# -----------------------------
# Paths
# -----------------------------
path_legal     <- "sports_gambling_legalization_dates.csv"
path_lsc       <- "monthly_county_data_download.csv"
path_all_sites <- "all_sites_monthly_2020_2021.csv"
path_allstates <- "allstates_monthly_2020_2021.csv"

# -----------------------------
# Helpers
# -----------------------------
clean_state <- function(x) str_to_lower(x) |> str_replace_all("[^a-z]", "")

# FIX: Proper ETS month parsing
ets_month_to_date <- function(x) {
  lubridate::my(x)  # Use lubridate::my() which handles "Jan-20" format
}

ym_int <- function(date) {
  date <- as.Date(date)
  year(date) * 12L + month(date)
}

# State FIPS -> state name (lower)
state_fips_map <- tibble::tribble(
  ~state_fips, ~state,
  1L,"alabama", 2L,"alaska", 4L,"arizona", 5L,"arkansas", 6L,"california",
  8L,"colorado", 9L,"connecticut", 10L,"delaware", 11L,"district of columbia",
  12L,"florida", 13L,"georgia", 15L,"hawaii", 16L,"idaho", 17L,"illinois",
  18L,"indiana", 19L,"iowa", 20L,"kansas", 21L,"kentucky", 22L,"louisiana",
  23L,"maine", 24L,"maryland", 25L,"massachusetts", 26L,"michigan",
  27L,"minnesota", 28L,"mississippi", 29L,"missouri", 30L,"montana",
  31L,"nebraska", 32L,"nevada", 33L,"new hampshire", 34L,"new jersey",
  35L,"new mexico", 36L,"new york", 37L,"north carolina", 38L,"north dakota",
  39L,"ohio", 40L,"oklahoma", 41L,"oregon", 42L,"pennsylvania",
  44L,"rhode island", 45L,"south carolina", 46L,"south dakota",
  47L,"tennessee", 48L,"texas", 49L,"utah", 50L,"vermont", 51L,"virginia",
  53L,"washington", 54L,"west virginia", 55L,"wisconsin", 56L,"wyoming"
) %>%
  mutate(state_key = clean_state(state))

abbr_map <- tibble(
  state_abbr = c(state.abb, "DC"),
  state      = c(state.name, "District of Columbia")
) %>%
  mutate(state = str_to_lower(state),
         state_key = clean_state(state))

# -----------------------------
# Legalization timing
# -----------------------------
legal <- readr::read_csv(path_legal, show_col_types = FALSE) %>%
  mutate(
    state = str_to_lower(state),
    state_key = clean_state(state),
    first_start_date  = as.Date(first_start_date),
    online_start_date = as.Date(online_start_date),
    retail_start_date = as.Date(retail_start_date),
    first_ym  = if_else(!is.na(first_start_date),  ym_int(first_start_date),  NA_integer_),
    online_ym = if_else(!is.na(online_start_date), ym_int(online_start_date), NA_integer_),
    retail_ym = if_else(!is.na(retail_start_date), ym_int(retail_start_date), NA_integer_)
  ) %>%
  dplyr::select(state_key, first_ym, online_ym, retail_ym, has_online, has_retail)

cat("\n=== Treatment Summary ===\n")
print(legal %>% filter(has_online == TRUE) %>%
  select(state_key, online_ym) %>% arrange(online_ym))

# ============================================================
# 1) LSC COUNTY-MONTH PANEL (2016+)
# ============================================================
cat("\n=== Loading LSC County-Month Data ===\n")
county_raw <- readr::read_csv(path_lsc, show_col_types = FALSE) %>%
  mutate(
    fips = as.integer(fips),
    date = as.Date(date),
    ym   = year(date) * 12L + month(date),
    state_fips = as.integer(fips %/% 1000L)
  ) %>%
  left_join(state_fips_map, by = "state_fips") %>%
  mutate(state_key = clean_state(state)) %>%
  left_join(legal, by = "state_key") %>%
  mutate(
    filings = filings_count,
    y_log1p = log(filings + 1),
    y_rate  = 1000 * filings / renter_occupied_housing_units,
    y_log_rate = log(y_rate + 0.01)
  ) %>%
  filter(!is.na(state_key), !is.na(ym), !is.na(fips))

# FIX: Only use cohorts that actually appear in the time periods
# sunab() requires g values to appear in the t variable
valid_cohorts <- county_raw %>%
  filter(has_online == TRUE, !is.na(online_ym)) %>%
  group_by(state_key, online_ym) %>%
  summarise(cohort_in_data = any(ym == online_ym), .groups = "drop") %>%
  filter(cohort_in_data) %>%
  pull(online_ym) %>%
  unique()

cat("Valid treatment cohorts:", length(valid_cohorts), "\n")

county <- county_raw %>%
  mutate(
    # Ensure g_online and ym have same type (integer)
    ym = as.integer(ym),
    # Only assign cohort if it's valid (appears in data)
    g_online = if_else(
      has_online == TRUE & !is.na(online_ym) & online_ym %in% valid_cohorts,
      as.integer(online_ym),
      0L
    )
  ) %>%
  arrange(fips, ym)

county_rng <- county %>%
  summarise(
    min_date = min(date),
    max_date = max(date),
    n_months = n_distinct(ym),
    n_states = n_distinct(state_key),
    n_counties = n_distinct(fips),
    n_treated_states = sum(has_online == TRUE, na.rm = TRUE) / n_distinct(ym)
  )
print(county_rng)

# ============================================================
# 2) ETS ALL_SITES (city/court panel, 2020+) - AGGREGATED
# ============================================================
cat("\n=== Loading and Aggregating ETS All Sites Data ===\n")
sites_raw <- readr::read_csv(path_all_sites, show_col_types = FALSE) %>%
  mutate(
    state_abbr = str_extract(city, "(?<=,\\s)[A-Z]{2}$"),
    month_date = ets_month_to_date(month),  # FIX: Use proper lubridate::my()
    ym = year(month_date) * 12L + month(month_date)
  ) %>%
  left_join(abbr_map, by = "state_abbr") %>%
  mutate(state_key = clean_state(state)) %>%
  filter(!is.na(state_key), !is.na(ym)) %>%
  # AGGREGATION: Group by state-month to create clean panel
  group_by(state_key, ym) %>%
  summarise(
    month_date = first(month_date),
    filings = sum(filings_2020, na.rm = TRUE),
    filings_avg = sum(filings_avg, na.rm = TRUE),
    filings_baseline = sum(filings_avg_prepandemic_baseline, na.rm = TRUE),
    n_sites = n(),
    .groups = "drop"
  ) %>%
  left_join(legal, by = "state_key")

# FIX: Only use valid cohorts
valid_cohorts_sites <- sites_raw %>%
  filter(has_online == TRUE, !is.na(online_ym)) %>%
  group_by(state_key, online_ym) %>%
  summarise(cohort_in_data = any(ym == online_ym), .groups = "drop") %>%
  filter(cohort_in_data) %>%
  pull(online_ym) %>%
  unique()

sites <- sites_raw %>%
  mutate(
    state_id = as.integer(as.factor(state_key)),
    ym = as.integer(ym),
    y_log1p = log(filings + 1),
    y_log_baseline = log((filings + 1) / (filings_baseline + 1)),

    # FIX: Don't use isTRUE() in vectorized context
    g_online = if_else(
      has_online == TRUE & !is.na(online_ym) & online_ym %in% valid_cohorts_sites,
      as.integer(online_ym),
      0L
    )
  ) %>%
  arrange(state_key, ym)

sites_rng <- sites %>%
  summarise(
    min_date = min(month_date),
    max_date = max(month_date),
    n_months = n_distinct(ym),
    n_states = n_distinct(state_key),
    avg_sites_per_state = mean(n_sites)
  )
print(sites_rng)

# ============================================================
# 3) ETS ALLSTATES (state-month) - CLEANED
# ============================================================
cat("\n=== Loading and Cleaning ETS AllStates Data ===\n")
states_raw <- readr::read_csv(path_allstates, show_col_types = FALSE) %>%
  mutate(
    state_key = clean_state(state),
    month_date = ets_month_to_date(month),  # FIX: Use proper lubridate::my()
    ym = year(month_date) * 12L + month(month_date)
  ) %>%
  group_by(state_key, ym, month_date) %>%
  summarise(
    filings = sum(filings_2020, na.rm = TRUE),
    filings_avg = sum(filings_avg, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  left_join(legal, by = "state_key")

# FIX: Only use valid cohorts
valid_cohorts_states <- states_raw %>%
  filter(has_online == TRUE, !is.na(online_ym)) %>%
  group_by(state_key, online_ym) %>%
  summarise(cohort_in_data = any(ym == online_ym), .groups = "drop") %>%
  filter(cohort_in_data) %>%
  pull(online_ym) %>%
  unique()

states <- states_raw %>%
  mutate(
    state_id = as.integer(as.factor(state_key)),
    ym = as.integer(ym),
    y_log1p = log(filings + 1),

    # FIX: Don't use isTRUE() in vectorized context
    g_online = if_else(
      has_online == TRUE & !is.na(online_ym) & online_ym %in% valid_cohorts_states,
      as.integer(online_ym),
      0L
    )
  ) %>%
  filter(!is.na(state_key), !is.na(ym)) %>%
  arrange(state_key, ym)

states_rng <- states %>%
  summarise(
    min_date = min(month_date),
    max_date = max(month_date),
    n_months = n_distinct(ym),
    n_states = n_distinct(state_key)
  )
print(states_rng)

# ============================================================
# ANALYSIS 1: County-Month Panel (LSC) - Main Analysis
# ============================================================
cat("\n\n========================================\n")
cat("ANALYSIS 1: COUNTY-MONTH PANEL (LSC)\n")
cat("========================================\n\n")

# --- Sun-Abraham Event Study ---
cat("--- Running Sun-Abraham (County-Month) ---\n")
cat("Treated observations:", sum(county$g_online > 0), "\n")
cat("Control observations:", sum(county$g_online == 0), "\n")

m_sa_county <- feols(
  y_log1p ~ sunab(g_online, ym, ref.p = c(-1, -2)) | fips + ym,
  data    = county,
  weights = ~ renter_occupied_housing_units,
  cluster = ~ state_key
)

cat("\nSun-Abraham Results (County-Month):\n")
print(summary(m_sa_county))

# Save plot
jpeg("SA_county_month.jpeg", width = 800, height = 600)
iplot(m_sa_county,
      main = "Sun-Abraham: County-Month Panel (LSC)",
      xlab = "Months Relative to Online Gambling Legalization",
      ylab = "Log(Filings + 1)")
dev.off()
cat("Plot saved to: SA_county_month.jpeg\n")

# NOTE: Callaway-Sant'Anna (did::att_gt) is not compatible with this unbalanced panel
# The panel has 1,212 counties missing in some periods, which causes CS to fail.
# This is fine - Sun-Abraham and BJS are both robust alternatives.

# --- Borusyak-Jaravel-Spiess Imputation ---
cat("\n--- Running Borusyak-Jaravel-Spiess Imputation (County-Month) ---\n")
# For BJS, never-treated should be coded as beyond sample
max_ym_county <- max(county$ym, na.rm = TRUE)
county_bjs <- county %>%
  mutate(g_online_bjs = if_else(g_online == 0L, max_ym_county + 1L, g_online))

imp_county <- didimputation::did_imputation(
  data = county_bjs,
  yname = "y_log1p",
  gname = "g_online_bjs",
  tname = "ym",
  idname = "fips",
  cluster_var = "state_key"
)
cat("\nBJS Imputation Results (County-Month):\n")
print(imp_county)

# ============================================================
# ANALYSIS 2: State-Month Panel (ETS All Sites Aggregated)
# ============================================================
cat("\n\n========================================\n")
cat("ANALYSIS 2: STATE-MONTH PANEL (ETS All Sites Aggregated)\n")
cat("========================================\n\n")

# --- Sun-Abraham Event Study ---
cat("--- Running Sun-Abraham (State-Month from Sites) ---\n")
m_sa_sites <- feols(
  y_log1p ~ sunab(g_online, ym, ref.p = c(-1, -2)) | state_id + ym,
  data    = sites,
  cluster = ~ state_key
)

cat("\nSun-Abraham Results (State-Month Sites):\n")
print(summary(m_sa_sites))

jpeg("SA_sites_aggregated.jpeg", width = 800, height = 600)
iplot(m_sa_sites,
      main = "Sun-Abraham: State-Month Panel (ETS Sites Aggregated)",
      xlab = "Months Relative to Online Gambling Legalization",
      ylab = "Log(Filings + 1)")
dev.off()
cat("Plot saved to: SA_sites_aggregated.jpeg\n")

# --- Standard TWFE for comparison ---
cat("\n--- Running Standard TWFE (State-Month from Sites) ---\n")
m_twfe_sites <- feols(
  y_log1p ~ i(g_online > 0 & ym >= g_online) | state_id + ym,
  data    = sites,
  cluster = ~ state_key
)
cat("\nStandard TWFE Results (State-Month Sites):\n")
print(summary(m_twfe_sites))

# ============================================================
# ANALYSIS 3: State-Month Panel (ETS AllStates)
# ============================================================
cat("\n\n========================================\n")
cat("ANALYSIS 3: STATE-MONTH PANEL (ETS AllStates)\n")
cat("========================================\n\n")

# --- Sun-Abraham Event Study ---
cat("--- Running Sun-Abraham (AllStates) ---\n")
m_sa_states <- feols(
  y_log1p ~ sunab(g_online, ym, ref.p = c(-1, -2)) | state_id + ym,
  data    = states,
  cluster = ~ state_key
)

cat("\nSun-Abraham Results (AllStates):\n")
print(summary(m_sa_states))

jpeg("SA_allstates.jpeg", width = 800, height = 600)
iplot(m_sa_states,
      main = "Sun-Abraham: State-Month Panel (ETS AllStates)",
      xlab = "Months Relative to Online Gambling Legalization",
      ylab = "Log(Filings + 1)")
dev.off()
cat("Plot saved to: SA_allstates.jpeg\n")

# ============================================================
# SUMMARY: Compare Estimates Across Specifications
# ============================================================
cat("\n\n========================================\n")
cat("SUMMARY: COMPARISON OF ESTIMATES\n")
cat("========================================\n\n")

# Extract ATT from each method
extract_att <- function(model) {
  if (inherits(model, "fixest")) {
    # For Sun-Abraham, average post-treatment coefficients
    coefs <- coef(model)
    post_idx <- which(str_detect(names(coefs), "sunab::") &
                      as.numeric(str_extract(names(coefs), "[0-9]+")) >= 0)
    if (length(post_idx) > 0) {
      return(mean(coefs[post_idx], na.rm = TRUE))
    }
  }
  return(NA_real_)
}

summary_table <- tibble(
  Panel = c("County-Month (LSC)", "State-Month (Sites Agg)", "State-Month (AllStates)"),
  SA_ATT = c(
    extract_att(m_sa_county),
    extract_att(m_sa_sites),
    extract_att(m_sa_states)
  ),
  N_obs = c(nrow(county), nrow(sites), nrow(states)),
  N_units = c(n_distinct(county$fips), n_distinct(sites$state_id), n_distinct(states$state_id))
)

print(summary_table)

cat("\n=== Analysis Complete ===\n")
cat("All plots saved to working directory.\n")
