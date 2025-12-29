# ============================================================
# COMBINED PANEL ANALYSIS
# Uses BOTH LSC county data AND ETS state data optimally
# Strategy: Use LSC as primary, fill gaps with ETS
# ============================================================

library(tidyverse)
library(lubridate)
library(fixest)

# -----------------------------
# Paths
# -----------------------------
path_legal     <- "sports_gambling_legalization_dates.csv"
path_lsc       <- "monthly_county_data_download.csv"
path_allstates <- "allstates_monthly_2020_2021.csv"

# -----------------------------
# Helpers
# -----------------------------
clean_state <- function(x) str_to_lower(x) |> str_replace_all("[^a-z]", "")
ym_int <- function(date) year(as.Date(date)) * 12L + month(as.Date(date))

# State FIPS mapping
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

# -----------------------------
# Legalization timing
# -----------------------------
legal <- readr::read_csv(path_legal, show_col_types = FALSE) %>%
  mutate(
    state_key = clean_state(state),
    online_start_date = as.Date(online_start_date),
    online_ym = if_else(!is.na(online_start_date), ym_int(online_start_date), NA_integer_)
  ) %>%
  dplyr::select(state_key, online_ym, has_online)

# ============================================================
# STRATEGY 1: County-level panel (LSC) - PRIMARY ANALYSIS
# Best for DiD because of granularity and long time series
# ============================================================
cat("\n=== BUILDING PRIMARY PANEL: LSC County-Month ===\n")

county_panel <- readr::read_csv(path_lsc, show_col_types = FALSE) %>%
  mutate(
    fips = as.integer(fips),
    date = as.Date(date),
    ym = ym_int(date),
    state_fips = as.integer(fips %/% 1000L)
  ) %>%
  left_join(state_fips_map, by = "state_fips") %>%
  mutate(state_key = clean_state(state)) %>%
  left_join(legal, by = "state_key") %>%
  mutate(
    filings = filings_count,
    y_log1p = log(filings + 1),
    y_rate = 1000 * filings / renter_occupied_housing_units,
    y_log_rate = log(y_rate + 0.01),
    ym = as.integer(ym)
  ) %>%
  filter(!is.na(state_key), !is.na(ym), !is.na(fips))

# Valid cohorts
valid_cohorts_county <- county_panel %>%
  filter(has_online == TRUE, !is.na(online_ym)) %>%
  group_by(state_key, online_ym) %>%
  summarise(cohort_in_data = any(ym == online_ym), .groups = "drop") %>%
  filter(cohort_in_data) %>%
  pull(online_ym) %>%
  unique()

county_panel <- county_panel %>%
  mutate(
    g_online = if_else(
      has_online == TRUE & !is.na(online_ym) & online_ym %in% valid_cohorts_county,
      as.integer(online_ym),
      0L
    ),
    panel_source = "LSC_county"
  )

cat("LSC County Panel:\n")
cat("  States:", n_distinct(county_panel$state_key), "\n")
cat("  Counties:", n_distinct(county_panel$fips), "\n")
cat("  Time periods:", min(county_panel$date), "to", max(county_panel$date), "\n")
cat("  Observations:", nrow(county_panel), "\n")
cat("  Treated obs:", sum(county_panel$g_online > 0), "\n\n")

# ============================================================
# STRATEGY 2: State-level panel (ETS) for additional states
# Add states NOT in LSC + use as robustness check
# ============================================================
cat("=== BUILDING SUPPLEMENTAL PANEL: ETS State-Month ===\n")

state_panel <- readr::read_csv(path_allstates, show_col_types = FALSE) %>%
  mutate(
    state_key = clean_state(state),
    date = lubridate::my(month),
    ym = ym_int(date)
  ) %>%
  group_by(state_key, ym, date) %>%
  summarise(
    filings = sum(filings_2020, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  left_join(legal, by = "state_key") %>%
  mutate(
    ym = as.integer(ym),
    y_log1p = log(filings + 1)
  ) %>%
  filter(!is.na(state_key), !is.na(ym))

# Valid cohorts for state panel
valid_cohorts_state <- state_panel %>%
  filter(has_online == TRUE, !is.na(online_ym)) %>%
  group_by(state_key, online_ym) %>%
  summarise(cohort_in_data = any(ym == online_ym), .groups = "drop") %>%
  filter(cohort_in_data) %>%
  pull(online_ym) %>%
  unique()

state_panel <- state_panel %>%
  mutate(
    g_online = if_else(
      has_online == TRUE & !is.na(online_ym) & online_ym %in% valid_cohorts_state,
      as.integer(online_ym),
      0L
    ),
    state_id = as.integer(as.factor(state_key)),
    panel_source = "ETS_state"
  )

cat("ETS State Panel:\n")
cat("  States:", n_distinct(state_panel$state_key), "\n")
cat("  Time periods:", min(state_panel$date), "to", max(state_panel$date), "\n")
cat("  Observations:", nrow(state_panel), "\n")
cat("  Treated obs:", sum(state_panel$g_online > 0), "\n\n")

# ============================================================
# IDENTIFY COMPLEMENTARITY
# ============================================================
cat("=== DATA COMPLEMENTARITY ===\n")

lsc_states <- unique(county_panel$state_key)
ets_states <- unique(state_panel$state_key)

overlap_states <- intersect(lsc_states, ets_states)
lsc_only <- setdiff(lsc_states, ets_states)
ets_only <- setdiff(ets_states, lsc_states)

cat("States in BOTH datasets (", length(overlap_states), "):\n  ",
    paste(overlap_states, collapse=", "), "\n\n")
cat("States ONLY in LSC (", length(lsc_only), "):\n  ",
    paste(lsc_only, collapse=", "), "\n\n")
cat("States ONLY in ETS (", length(ets_only), "):\n  ",
    paste(ets_only, collapse=", "), "\n\n")

# ============================================================
# ANALYSIS 1: Primary County-Level Analysis (LSC)
# ============================================================
cat("\n========================================\n")
cat("ANALYSIS 1: COUNTY-LEVEL PANEL (LSC)\n")
cat("========================================\n\n")

m_county <- feols(
  y_log1p ~ sunab(g_online, ym, ref.p = c(-1, -2)) | fips + ym,
  data = county_panel,
  weights = ~ renter_occupied_housing_units,
  cluster = ~ state_key
)

cat("Sun-Abraham Results (County-Level):\n")
print(summary(m_county))

jpeg("Combined_County_Panel.jpeg", width = 800, height = 600)
iplot(m_county,
      main = "Sun-Abraham: County-Month Panel (LSC)",
      xlab = "Months Relative to Online Gambling Legalization",
      ylab = "Log(Filings + 1)")
abline(h = 0, lty = 2, col = "gray50")
dev.off()
cat("\nPlot saved: Combined_County_Panel.jpeg\n")

# ============================================================
# ANALYSIS 2: State-Level for Additional Coverage (ETS)
# ============================================================
cat("\n========================================\n")
cat("ANALYSIS 2: STATE-LEVEL PANEL (ETS)\n")
cat("Includes 3 additional states not in LSC\n")
cat("========================================\n\n")

m_state <- feols(
  y_log1p ~ sunab(g_online, ym, ref.p = c(-1, -2)) | state_id + ym,
  data = state_panel,
  cluster = ~ state_key
)

cat("Sun-Abraham Results (State-Level):\n")
print(summary(m_state))

jpeg("Combined_State_Panel.jpeg", width = 800, height = 600)
iplot(m_state,
      main = "Sun-Abraham: State-Month Panel (ETS)\n(Includes MO, NM, RI not in LSC)",
      xlab = "Months Relative to Online Gambling Legalization",
      ylab = "Log(Filings + 1)")
abline(h = 0, lty = 2, col = "gray50")
dev.off()
cat("\nPlot saved: Combined_State_Panel.jpeg\n")

# ============================================================
# ANALYSIS 3: Overlap Period Comparison (Robustness)
# Compare LSC vs ETS in states/periods where both exist
# ============================================================
cat("\n========================================\n")
cat("ANALYSIS 3: ROBUSTNESS CHECK\n")
cat("Compare LSC vs ETS in overlap states\n")
cat("========================================\n\n")

# Aggregate county data to state level for comparison
overlap_start <- max(min(county_panel$date), min(state_panel$date))
overlap_end <- min(max(county_panel$date), max(state_panel$date))

county_agg_state <- county_panel %>%
  filter(state_key %in% overlap_states,
         date >= overlap_start,
         date <= overlap_end) %>%
  group_by(state_key, ym, date) %>%
  summarise(
    filings_total = sum(filings, na.rm = TRUE),
    g_online = first(g_online),
    .groups = "drop"
  ) %>%
  mutate(
    y_log1p = log(filings_total + 1),
    source = "LSC_aggregated",
    state_id = as.integer(as.factor(state_key))
  )

state_overlap <- state_panel %>%
  filter(state_key %in% overlap_states,
         date >= overlap_start,
         date <= overlap_end) %>%
  mutate(source = "ETS_direct")

# Run both models
m_lsc_overlap <- feols(
  y_log1p ~ sunab(g_online, ym, ref.p = c(-1, -2)) | state_id + ym,
  data = county_agg_state,
  cluster = ~ state_key
)

m_ets_overlap <- feols(
  y_log1p ~ sunab(g_online, ym, ref.p = c(-1, -2)) | state_id + ym,
  data = state_overlap,
  cluster = ~ state_key
)

cat("Overlap Period Comparison (", length(overlap_states), " states, ",
    format(overlap_start), " to ", format(overlap_end), "):\n\n")

cat("LSC (aggregated to state-month):\n")
print(summary(m_lsc_overlap))

cat("\nETS (direct state-month):\n")
print(summary(m_ets_overlap))

# ============================================================
# SUMMARY TABLE
# ============================================================
cat("\n========================================\n")
cat("SUMMARY: WHY USE BOTH DATASETS\n")
cat("========================================\n\n")

summary_df <- tibble(
  Dataset = c("LSC (County-Month)", "ETS (State-Month)", "Combined Strategy"),
  States = c(
    length(lsc_states),
    length(ets_states),
    length(unique(c(lsc_states, ets_states)))
  ),
  `Geographic Units` = c(
    n_distinct(county_panel$fips),
    n_distinct(state_panel$state_id),
    "County + State"
  ),
  `Time Span` = c(
    "2016-2025 (117 mo)",
    "2020-2025 (71 mo)",
    "2016-2025"
  ),
  Observations = c(
    nrow(county_panel),
    nrow(state_panel),
    nrow(county_panel) + nrow(state_panel)
  ),
  `Best For` = c(
    "Primary analysis (power + long pre-period)",
    "Adds MO, NM, RI; robustness check",
    "Maximum coverage"
  )
)

print(summary_df)

cat("\n\nRECOMMENDATION:\n")
cat("1. PRIMARY: Use LSC county-month panel (most power, longest time series)\n")
cat("2. SUPPLEMENTAL: Report ETS results for Missouri, New Mexico, Rhode Island\n")
cat("3. ROBUSTNESS: Compare LSC vs ETS in overlap states as validation\n")
cat("\nBoth datasets are complementary - LSC gives you statistical power,\n")
cat("ETS gives you additional state coverage!\n")

cat("\n=== Analysis Complete ===\n")
