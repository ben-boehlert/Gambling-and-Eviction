#!/usr/bin/env Rscript
################################################################################
# build_county_exposure_panel.R
#
# Builds a county-month sports-betting "exposure" panel replicating the
# construction in Goss & Mangrum (NY Fed Staff Report 1184), Online Appendix
# A.1-A.2: for every contiguous-US + DC county, in every month 2016-01 to
# 2025-12, classify the county as (a) directly treated (own state's online
# sports betting is legal), (b) a border-spillover county (own state not yet
# legal, but within a short driving-equivalent distance of a state that IS
# legal), or (c) unexposed.
#
# Sources:
#   - Census 2020 Centers of Population, county file (population-weighted
#     centroids): https://www2.census.gov/geo/docs/reference/cenpop2020/county/CenPop2020_Mean_CO.txt
#   - tigris::states(cb = TRUE, resolution = "500k")  (cartographic boundary,
#     shoreline-clipped state polygons)
#   - data/raw/sports_gambling_legalization_dates.csv (online_start_date is
#     the treatment date used throughout this repo)
#
# Outputs (data/processed/):
#   county_state_border_distance_miles.csv  — static county x state distance
#                                              matrix (Euclidean, EPSG:5070),
#                                              one row per county x every
#                                              OTHER state (48 or 49 rows/county)
#   county_exposure_panel.csv               — county x month panel, 2016-01
#                                              to 2025-12, with own_legal,
#                                              dist_nearest_legal_mi,
#                                              nearest_legal_state, S15, S60,
#                                              and time-invariant Q15/Q60/G
#   county_exposure_panel_build_log.txt     — text log of build counts and
#                                              assertion results
#
# Treatment timing convention: the launch MONTH counts as treated
# (own_legal_it = 1 if online_start_date <= first day of month t). This
# matches the "launch month treated" convention used elsewhere in this repo
# (e.g. state_month_panel_with_treatment.csv's treat_start comparison).
#
# Top-coding: when no OTHER state is legal in month t, distance to nearest
# legal state is undefined. We top-code this at 9999 miles (not NA) to match
# Goss & Mangrum's appendix convention, so S15/S60 indicators (which compare
# against 15/60) are well-defined (always 0) in that case.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(stringr)
  library(lubridate)
  library(tibble)
  library(purrr)
  library(sf)
  library(tigris)
  library(units)
})

set.seed(20260810L)

options(tigris_use_cache = TRUE)
sf::sf_use_s2(TRUE)

t_start <- Sys.time()

# ----------------------------- paths ------------------------------------------

repo_root <- normalizePath(".", winslash = "/")

p_legal_dates <- file.path(repo_root, "data", "raw", "sports_gambling_legalization_dates.csv")

out_dist  <- file.path(repo_root, "data", "processed", "county_state_border_distance_miles.csv")
out_panel <- file.path(repo_root, "data", "processed", "county_exposure_panel.csv")
out_log   <- file.path(repo_root, "data", "processed", "county_exposure_panel_build_log.txt")

dir.create(dirname(out_dist), recursive = TRUE, showWarnings = FALSE)

log_lines <- character()
log_msg <- function(msg) {
  log_lines <<- c(log_lines, msg)
  cat(msg, "\n")
}

# ----------------------------- state FIPS xwalk -------------------------------
# Self-contained xwalk (mirrors state_fips_xwalk used elsewhere in this repo),
# CONUS + DC only (no AK/HI/territories).

state_fips_xwalk <- tribble(
  ~state_fips, ~state_abb, ~state_name,
   1, "AL", "Alabama",           4, "AZ", "Arizona",
   5, "AR", "Arkansas",          6, "CA", "California",
   8, "CO", "Colorado",          9, "CT", "Connecticut",
  10, "DE", "Delaware",         11, "DC", "District of Columbia",
  12, "FL", "Florida",          13, "GA", "Georgia",
  16, "ID", "Idaho",            17, "IL", "Illinois",
  18, "IN", "Indiana",          19, "IA", "Iowa",
  20, "KS", "Kansas",           21, "KY", "Kentucky",
  22, "LA", "Louisiana",        23, "ME", "Maine",
  24, "MD", "Maryland",         25, "MA", "Massachusetts",
  26, "MI", "Michigan",         27, "MN", "Minnesota",
  28, "MS", "Mississippi",      29, "MO", "Missouri",
  30, "MT", "Montana",          31, "NE", "Nebraska",
  32, "NV", "Nevada",           33, "NH", "New Hampshire",
  34, "NJ", "New Jersey",       35, "NM", "New Mexico",
  36, "NY", "New York",         37, "NC", "North Carolina",
  38, "ND", "North Dakota",     39, "OH", "Ohio",
  40, "OK", "Oklahoma",         41, "OR", "Oregon",
  42, "PA", "Pennsylvania",     44, "RI", "Rhode Island",
  45, "SC", "South Carolina",   46, "SD", "South Dakota",
  47, "TN", "Tennessee",        48, "TX", "Texas",
  49, "UT", "Utah",             50, "VT", "Vermont",
  51, "VA", "Virginia",         53, "WA", "Washington",
  54, "WV", "West Virginia",    55, "WI", "Wisconsin",
  56, "WY", "Wyoming"
)
stopifnot(nrow(state_fips_xwalk) == 49L)  # 48 contiguous states + DC

# ================================================================================
# STEP 1: county population-weighted centroids (Census 2020 CenPop)
# ================================================================================

log_msg("=== STEP 1: county population-weighted centroids ===")

cenpop_url <- "https://www2.census.gov/geo/docs/reference/cenpop2020/county/CenPop2020_Mean_CO.txt"
cenpop_raw <- read_csv(cenpop_url, show_col_types = FALSE)

log_msg(paste("CenPop2020 county rows downloaded:", nrow(cenpop_raw)))

centroids_all <- cenpop_raw %>%
  transmute(
    state_fips  = as.integer(STATEFP),
    county_fips_i = as.integer(COUNTYFP),
    county_fips = sprintf("%02d%03d", as.integer(STATEFP), as.integer(COUNTYFP)),
    county_name = COUNAME,
    latitude    = as.numeric(LATITUDE),
    longitude   = as.numeric(LONGITUDE)
  )

n_before_restrict <- nrow(centroids_all)

centroids <- centroids_all %>%
  inner_join(state_fips_xwalk, by = "state_fips")

n_dropped <- n_before_restrict - nrow(centroids)
log_msg(paste("Counties before CONUS+DC restriction:", n_before_restrict))
log_msg(paste("Counties dropped (AK/HI/territories):", n_dropped))
log_msg(paste("Counties kept (CONUS + DC):", nrow(centroids)))

stopifnot(!anyNA(centroids$county_fips))
stopifnot(!anyDuplicated(centroids$county_fips))
stopifnot(!any(centroids$state_abb %in% c("AK", "HI")))

centroids_sf <- st_as_sf(
  centroids,
  coords = c("longitude", "latitude"),
  crs = 4326,
  remove = FALSE
) %>%
  st_transform(5070)

# ================================================================================
# STEP 2: state boundaries (cartographic, shoreline-clipped)
# ================================================================================

log_msg("=== STEP 2: state boundaries (tigris cb=TRUE, 500k) ===")

states_sf_raw <- tigris::states(cb = TRUE, resolution = "500k", year = 2020)

states_sf <- states_sf_raw %>%
  filter(STUSPS %in% state_fips_xwalk$state_abb) %>%
  st_transform(5070) %>%
  select(state_abb = STUSPS, state_name_tigris = NAME, geometry)

log_msg(paste("States downloaded (raw):", nrow(states_sf_raw)))
log_msg(paste("States kept (CONUS + DC):", nrow(states_sf)))
stopifnot(nrow(states_sf) == 49L)

# Boundary lines (not filled polygons) — distance must be to the border line.
states_boundary_sf <- states_sf %>%
  mutate(geometry = st_boundary(geometry)) %>%
  st_cast("MULTILINESTRING")

# ================================================================================
# STEP 3: county-centroid to state-boundary distance matrix (EPSG:5070, miles)
# ================================================================================

log_msg("=== STEP 3: distance matrix (county centroid -> every OTHER state boundary) ===")

n_counties <- nrow(centroids_sf)
n_states   <- nrow(states_boundary_sf)

# st_distance() returns a matrix (counties x states) of meters in EPSG:5070.
dist_matrix_m <- st_distance(centroids_sf, states_boundary_sf)
stopifnot(dim(dist_matrix_m) == c(n_counties, n_states))

dist_matrix_mi <- units::set_units(dist_matrix_m, "mi") %>%
  units::drop_units()

colnames(dist_matrix_mi) <- states_boundary_sf$state_abb
rownames(dist_matrix_mi) <- centroids_sf$county_fips

dist_long <- as_tibble(dist_matrix_mi, rownames = "county_fips") %>%
  pivot_longer(-county_fips, names_to = "state_abb", values_to = "miles") %>%
  left_join(centroids %>% select(county_fips, own_state_abb = state_abb),
            by = "county_fips") %>%
  filter(state_abb != own_state_abb) %>%           # exclude own state
  select(county_fips, state_abb, miles)

log_msg(paste("Distance matrix rows (county x other-state):", nrow(dist_long)))
log_msg(paste("Expected (n_counties x 48):", n_counties * 48L))

stopifnot(nrow(dist_long) == n_counties * 48L)
stopifnot(all(dist_long$miles > 0))
stopifnot(!anyNA(dist_long$miles))

# every county has entries for every other state, and never its own state
own_state_check <- dist_long %>%
  left_join(centroids %>% select(county_fips, own_state_abb = state_abb),
            by = "county_fips") %>%
  filter(state_abb == own_state_abb)
stopifnot(nrow(own_state_check) == 0L)

counties_with_48 <- dist_long %>%
  count(county_fips) %>%
  filter(n == 48L) %>%
  nrow()
log_msg(paste("Counties with exactly 48 distance entries:", counties_with_48,
              "/", n_counties))
stopifnot(counties_with_48 == n_counties)

write_csv(dist_long, out_dist)
log_msg(paste("Wrote distance matrix:", out_dist))

# ================================================================================
# STEP 4: legalization dates
# ================================================================================

log_msg("=== STEP 4: legalization dates (online_start_date) ===")

legal_raw <- read_csv(p_legal_dates, show_col_types = FALSE)

dc_present <- "District of Columbia" %in% legal_raw$state
log_msg(paste("DC present in legalization dates CSV:", dc_present))

legal_dates <- legal_raw %>%
  transmute(
    state_name = state,
    online_start_date = as.Date(online_start_date)
  )

# Merge state names in the dates CSV to the boundary/centroid xwalk
legal_dates_matched <- legal_dates %>%
  left_join(state_fips_xwalk %>% select(state_name, state_abb), by = "state_name")

unmatched_states <- legal_dates_matched %>%
  filter(is.na(state_abb)) %>%
  pull(state_name)

log_msg(paste("States in legalization CSV total:", nrow(legal_dates)))
log_msg(paste("States in legalization CSV with online_start_date set:",
              sum(!is.na(legal_dates$online_start_date))))
log_msg(paste("Unmatched states (should be 0):", length(unmatched_states)))
if (length(unmatched_states) > 0) {
  log_msg(paste("  Unmatched:", paste(unmatched_states, collapse = ", ")))
}
stopifnot(length(unmatched_states) == 0L)

online_legal <- legal_dates_matched %>%
  filter(!is.na(online_start_date)) %>%
  select(state_abb, online_start_date) %>%
  arrange(online_start_date)

log_msg(paste("States with a non-missing online_start_date (ever legal, online):",
              nrow(online_legal)))
log_msg("Online-legal states and dates:")
walk2(online_legal$state_abb, online_legal$online_start_date,
      ~log_msg(paste0("  ", .x, ": ", .y)))

# G_i by state: own state's first legal (online) month, NA if never
state_G <- state_fips_xwalk %>%
  select(state_abb) %>%
  left_join(online_legal, by = "state_abb") %>%
  rename(G = online_start_date)

# ================================================================================
# STEP 5: monthly panel 2016-01 to 2025-12
# ================================================================================

log_msg("=== STEP 5: building monthly county x month panel ===")

months <- seq(as.Date("2016-01-01"), as.Date("2025-12-01"), by = "month")
n_months <- length(months)
log_msg(paste("Months in panel:", n_months, "(", first(months), "to", last(months), ")"))

county_state_key <- centroids %>%
  select(county_fips, county_name, state_abb)

n_counties_final <- nrow(county_state_key)

# Skeleton: county x month
panel_skeleton <- county_state_key %>%
  tidyr::crossing(month = months) %>%
  arrange(county_fips, month)

stopifnot(nrow(panel_skeleton) == n_counties_final * n_months)

# own_legal_it: own state's online_start_date <= first of month t
# (launch month counts as treated).
panel_own <- panel_skeleton %>%
  left_join(state_G, by = "state_abb") %>%
  mutate(own_legal = as.integer(!is.na(G) & G <= month))

# For each (state, month), is that state legal in that month? Build a long
# state x month legal-status table, then for each county x month look up the
# min distance among OTHER legal states (excluding own state, which dist_long
# already excludes).
state_month_legal <- state_fips_xwalk %>%
  select(state_abb) %>%
  tidyr::crossing(month = months) %>%
  left_join(online_legal, by = "state_abb") %>%
  mutate(state_legal = as.integer(!is.na(online_start_date) &
                                     online_start_date <= month)) %>%
  select(state_abb, month, state_legal)

# For each county x month, join distances to all OTHER states, keep only
# months where that other state is legal, take the min distance.
legal_states_by_month <- state_month_legal %>%
  filter(state_legal == 1L) %>%
  select(state_abb, month)

nearest_legal <- dist_long %>%
  inner_join(legal_states_by_month, by = "state_abb", relationship = "many-to-many") %>%
  group_by(county_fips, month) %>%
  slice_min(order_by = miles, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  transmute(
    county_fips,
    month,
    dist_nearest_legal_mi = miles,
    nearest_legal_state = state_abb
  )

panel <- panel_own %>%
  left_join(nearest_legal, by = c("county_fips", "month")) %>%
  mutate(
    dist_nearest_legal_mi = if_else(is.na(dist_nearest_legal_mi), 9999, dist_nearest_legal_mi),
    nearest_legal_state = if_else(is.na(nearest_legal_state) & own_legal == 0L,
                                   NA_character_, nearest_legal_state)
  )

log_msg(paste("Panel rows built:", nrow(panel)))
stopifnot(nrow(panel) == n_counties_final * n_months)

# S15/S60: own state not yet legal AND dist <= threshold
panel <- panel %>%
  mutate(
    S15 = as.integer(own_legal == 0L & dist_nearest_legal_mi <= 15),
    S60 = as.integer(own_legal == 0L & dist_nearest_legal_mi <= 60)
  )

# Q15/Q60: first month S15/S60 turns on (per county), NA if never
switch_month <- panel %>%
  group_by(county_fips) %>%
  summarise(
    Q15 = suppressWarnings(min(month[S15 == 1L], na.rm = TRUE)),
    Q60 = suppressWarnings(min(month[S60 == 1L], na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  mutate(
    Q15 = if_else(is.finite(Q15), Q15, as.Date(NA)),
    Q60 = if_else(is.finite(Q60), Q60, as.Date(NA))
  )

panel <- panel %>%
  select(-any_of(c("Q15", "Q60"))) %>%
  left_join(switch_month, by = "county_fips")

# Immunity assumption: once a county's own state legalizes (month >= G), it
# is no longer eligible for spillover treatment even if it remains within
# range of a neighboring legal state — S60/S15 must switch OFF at G.
panel <- panel %>%
  mutate(
    S15 = if_else(!is.na(G) & month >= G, 0L, S15),
    S60 = if_else(!is.na(G) & month >= G, 0L, S60)
  )

panel_final <- panel %>%
  transmute(
    county_fips, county_name, state_abb, month,
    own_legal, dist_nearest_legal_mi, nearest_legal_state,
    S15, S60, Q15, Q60, G
  ) %>%
  arrange(county_fips, month)

log_msg(paste("Final panel rows:", nrow(panel_final)))

# ================================================================================
# HARD ASSERTIONS
# ================================================================================

log_msg("=== ASSERTIONS ===")

# Key uniqueness / non-missingness, row count
key_id <- paste(panel_final$county_fips, panel_final$month)
stopifnot(!anyDuplicated(key_id))
stopifnot(!anyNA(panel_final$county_fips), !anyNA(panel_final$month))
stopifnot(nrow(panel_final) == n_counties_final * n_months)
log_msg(paste("PASS: key uniqueness + row count =", nrow(panel_final),
              "= n_counties (", n_counties_final, ") x 120"))

# dist_nearest_legal_mi weakly decreasing over time within county
monotone_check <- panel_final %>%
  arrange(county_fips, month) %>%
  group_by(county_fips) %>%
  mutate(diff_dist = dist_nearest_legal_mi - lag(dist_nearest_legal_mi)) %>%
  ungroup() %>%
  filter(!is.na(diff_dist))
n_violations <- sum(monotone_check$diff_dist > 1e-6)
log_msg(paste("Monotonicity violations (dist should be weakly decreasing):", n_violations))
stopifnot(n_violations == 0L)

# S15 <= S60
stopifnot(all(panel_final$S15 <= panel_final$S60))
log_msg("PASS: S15 <= S60 in every row")

# S60 * own_legal = 0 (mutually exclusive by construction)
stopifnot(all(panel_final$S60 * panel_final$own_legal == 0L))
log_msg("PASS: S60 * own_legal = 0 in every row")

# Immunity: for counties where Q60 < G, S60 switches OFF at G
immunity_check <- panel_final %>%
  filter(!is.na(Q60), !is.na(G), Q60 < G, month >= G)
stopifnot(all(immunity_check$S60 == 0L))
log_msg(paste("PASS: immunity assumption holds for", n_distinct(immunity_check$county_fips),
              "counties with Q60 < G"))

# ---- Spot checks ----
log_msg("=== SPOT CHECKS ===")

get_dist <- function(fips, target_state, target_month) {
  panel_final %>%
    filter(county_fips == fips, month == target_month) %>%
    pull(dist_nearest_legal_mi)
}

ks_date <- online_legal %>% filter(state_abb == "KS") %>% pull(online_start_date)
jackson_dist_to_ks <- dist_long %>% filter(county_fips == "29095", state_abb == "KS") %>% pull(miles)
log_msg(paste("Jackson County MO (29095) distance to Kansas:", round(jackson_dist_to_ks, 2), "mi"))
stopifnot(jackson_dist_to_ks < 15)
log_msg("PASS: Jackson County MO -> KS < 15 mi")

nj_date <- online_legal %>% filter(state_abb == "NJ") %>% pull(online_start_date)
ny_dist_to_nj <- dist_long %>% filter(county_fips == "36061", state_abb == "NJ") %>% pull(miles)
log_msg(paste("New York County NY (36061) distance to New Jersey:", round(ny_dist_to_nj, 2), "mi"))
stopifnot(ny_dist_to_nj < 10)
log_msg("PASS: New York County NY -> NJ < 10 mi")

tn_date <- online_legal %>% filter(state_abb == "TN") %>% pull(online_start_date)
catoosa_dist_to_tn <- dist_long %>% filter(county_fips == "13047", state_abb == "TN") %>% pull(miles)
log_msg(paste("Catoosa County GA (13047) distance to Tennessee:", round(catoosa_dist_to_tn, 2), "mi"))
stopifnot(catoosa_dist_to_tn < 15)
log_msg("PASS: Catoosa County GA -> TN < 15 mi")

ga_never_legal <- !("GA" %in% online_legal$state_abb)
log_msg(paste("Georgia never legalizes online sports betting:", ga_never_legal))
stopifnot(ga_never_legal)

catoosa_S60_at_tn_launch <- panel_final %>%
  filter(county_fips == "13047", month == tn_date) %>%
  pull(S60)
log_msg(paste("Catoosa County S60 in TN's launch month (", tn_date, "):", catoosa_S60_at_tn_launch))
stopifnot(catoosa_S60_at_tn_launch == 1L)
log_msg("PASS: Catoosa County GA S60 = 1 in TN's legalization month")

lowndes_dist_to_tn <- dist_long %>% filter(county_fips == "13185", state_abb == "TN") %>% pull(miles)
log_msg(paste("Lowndes County GA (13185) distance to Tennessee:", round(lowndes_dist_to_tn, 2), "mi"))
stopifnot(lowndes_dist_to_tn > 60)
log_msg("PASS: Lowndes County GA -> TN > 60 mi")

# ================================================================================
# WRITE OUTPUT
# ================================================================================

write_csv(panel_final, out_panel)
log_msg(paste("Wrote panel:", out_panel))

# ---- Exposure path summary table (60mi definition) ----
log_msg("=== EXPOSURE PATH SUMMARY (60mi definition) ===")

path_summary <- panel_final %>%
  group_by(county_fips) %>%
  summarise(
    ever_own_legal = any(own_legal == 1L),
    ever_S60 = any(S60 == 1L),
    .groups = "drop"
  ) %>%
  mutate(
    path = case_when(
      !ever_own_legal & !ever_S60 ~ "never_exposed",
      !ever_own_legal & ever_S60 ~ "spillover_only",
      ever_own_legal & !ever_S60 ~ "direct_only",
      ever_own_legal & ever_S60 ~ "spillover_then_direct"
    )
  ) %>%
  count(path, name = "n_counties") %>%
  arrange(desc(n_counties))

print(path_summary)
log_msg(paste(capture.output(print(path_summary)), collapse = "\n"))

t_end <- Sys.time()
runtime_secs <- as.numeric(difftime(t_end, t_start, units = "secs"))
log_msg(paste("Runtime (seconds):", round(runtime_secs, 1)))

writeLines(log_lines, out_log)
cat("\nLog written to:", out_log, "\n")

cat("\nALL CHECKS PASSED\n")
