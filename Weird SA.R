# ============================================================
# Rebuild panels from raw CSVs + run better tests
#   LSC: monthly_county_data_download.csv  (2016+)
#   ETS: all_sites_monthly_2020_2021.csv   (2020+; city/court sites)
#   ETS: allstates_monthly_2020_2021.csv   (2020+; state-month)
#   Legalization: sports_gambling_legalization_dates.csv
# ============================================================

library(tidyverse)
library(lubridate)
library(fixest)        # sunab
library(did)           # Callaway-Sant'Anna
library(didimputation) # Borusyak-Jaravel-Spiess
library(fwildclusterboot)

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

ets_month_to_date <- function(x) {
  # ETS months look like "Jan-20"
  as.Date(paste0("01-", x), format = "%d-%b-%y")
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

# ============================================================
# 1) LSC COUNTY-MONTH PANEL (2016+)
# ============================================================
county <- readr::read_csv(path_lsc, show_col_types = FALSE) %>%
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
    y_log_rate = log(y_rate + 0.01),
    
    # did::att_gt wants never-treated coded as 0
    g_online_did = if_else(isTRUE(has_online) & !is.na(online_ym), online_ym, 0L)
  ) %>%
  filter(!is.na(state_key), !is.na(ym), !is.na(fips)) %>%
  arrange(fips, ym)

county_rng <- county %>%
  summarise(min_date = min(date), max_date = max(date),
            n_months = n_distinct(ym),
            n_states = n_distinct(state_key),
            n_counties = n_distinct(fips))
print(county_rng)

max_ym_county <- max(county$ym, na.rm = TRUE)

county <- county %>%
  mutate(
    # sunab/didimputation: code never-treated as "after sample" so they are never-treated controls
    g_online_sa  = if_else(g_online_did == 0L, max_ym_county + 1L, g_online_did),
    g_online_imp = g_online_sa
  )

# ============================================================
# 2) ETS ALL_SITES (city/court panel, 2020+)
#   Columns are: city, month, filings_2020, filings_avg, filings_avg_prepandemic_baseline
# ============================================================
sites <- readr::read_csv(path_all_sites, show_col_types = FALSE) %>%
  mutate(
    state_abbr = str_extract(city, "(?<=,\\s)[A-Z]{2}$"),
    month_date = ets_month_to_date(month),
    ym = year(month_date) * 12L + month(month_date)
  ) %>%
  left_join(abbr_map, by = "state_abbr") %>%
  mutate(
    state_key = clean_state(state),
    site_id   = as.integer(as.factor(paste0(state_key, "||", city))),
    
    filings = filings_2020,
    y_log1p = log(filings + 1),
    
    base = filings_avg_prepandemic_baseline,
    y_log_relbase = log((filings + 1) / (pmax(base, 0) + 1))
  ) %>%
  left_join(legal, by = "state_key") %>%
  mutate(
    g_online_did = if_else(isTRUE(has_online) & !is.na(online_ym), online_ym, 0L)
  ) %>%
  filter(!is.na(state_key), !is.na(site_id), !is.na(ym)) %>%
  arrange(site_id, ym)

sites_rng <- sites %>%
  summarise(min_date = min(month_date), max_date = max(month_date),
            n_months = n_distinct(ym),
            n_states = n_distinct(state_key),
            n_sites = n_distinct(site_id))
print(sites_rng)

max_ym_sites <- max(sites$ym, na.rm = TRUE)
sites <- sites %>%
  mutate(
    g_online_sa  = if_else(g_online_did == 0L, max_ym_sites + 1L, g_online_did),
    g_online_imp = g_online_sa
  )

# ============================================================
# 3) ETS ALLSTATES (state-month)
# ============================================================
states <- readr::read_csv(path_allstates, show_col_types = FALSE) %>%
  mutate(
    state_key = clean_state(state),
    month_date = ets_month_to_date(month),
    ym = year(month_date) * 12L + month(month_date)
  ) %>%
  group_by(state_key, ym, month_date) %>%
  summarise(
    filings = sum(filings_2020, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  left_join(legal, by = "state_key") %>%
  mutate(
    y_log1p = log(filings + 1),
    g_online_did = if_else(isTRUE(has_online) & !is.na(online_ym), online_ym, 0L)
  ) %>%
  filter(!is.na(state_key), !is.na(ym)) %>%
  arrange(state_key, ym)

states_rng <- states %>%
  summarise(min_date = min(month_date), max_date = max(month_date),
            n_months = n_distinct(ym),
            n_states = n_distinct(state_key))
print(states_rng)

max_ym_states <- max(states$ym, na.rm = TRUE)
states <- states %>%
  mutate(
    g_online_sa  = if_else(g_online_did == 0L, max_ym_states + 1L, g_online_did),
    g_online_imp = g_online_sa,
    state_id = as.integer(as.factor(state_key))
  )

# ============================================================
# Diagnostics helpers
# ============================================================

support_by_event_time_raw <- function(df, g, t, cohort_level = c("state", "cohort")) {
  cohort_level <- match.arg(cohort_level)
  gsym <- rlang::sym(g); tsym <- rlang::sym(t)
  
  d <- df %>%
    filter(!!gsym > 0) %>%
    mutate(e = !!tsym - !!gsym)
  
  if (cohort_level == "cohort") {
    d %>% group_by(e) %>%
      summarise(n_cohorts = n_distinct(!!gsym), .groups = "drop") %>%
      arrange(e)
  } else {
    d %>% group_by(e) %>%
      summarise(n_states = n_distinct(state_key), .groups = "drop") %>%
      arrange(e)
  }
}

wald_pretest_aggte_ginv <- function(es_obj, pre_min, pre_max) {
  beta <- es_obj$att.egt
  egt  <- es_obj$egt
  V    <- es_obj$V
  
  idx <- which(egt >= pre_min & egt <= pre_max & !is.na(beta))
  if (length(idx) == 0) return(tibble(df = 0L, stat = NA_real_, p = NA_real_))
  
  Vsub <- V[idx, idx, drop = FALSE]
  b    <- beta[idx]
  
  r <- qr(Vsub)$rank
  Vinv <- MASS::ginv(Vsub)
  W <- as.numeric(t(b) %*% Vinv %*% b)
  tibble(df = r, stat = W, p = 1 - pchisq(W, df = r))
}

extract_sunab_e <- function(m, e) {
  b <- coef(m)
  nm <- names(b)
  hit <- nm[str_detect(nm, paste0("::", e, "\\b"))]
  if (length(hit) != 1) return(NA_real_)
  unname(b[hit])
}

loso_sunab <- function(df, y, g_sa, id, t, e = 18L, w = NULL) {
  states <- sort(unique(df$state_key))
  map_dfr(states, function(drop_state) {
    dsub <- df %>% filter(state_key != drop_state)
    fml  <- as.formula(paste0(
      y, " ~ sunab(", g_sa, ", ", t, ", ref.p = c(-1,-2), ",
      "bin.rel = list('<=-24' = -999:-24, '>=36' = 36:999)) | ",
      id, " + ", t
    ))
    m <- feols(fml, data = dsub,
               weights = if (!is.null(w)) as.formula(paste0("~", w)) else NULL,
               cluster = ~ state_key)
    tibble(dropped_state = drop_state, est_e = extract_sunab_e(m, e))
  })
}

# ============================================================
# MAIN: LSC COUNTY-MONTH
# ============================================================

Y <- "y_log1p"

# --- Sun–Abraham (trim/bin extreme leads/lags to stabilize VCOV)
m_sa_county <- feols(
  y_log1p ~ sunab(g_online_sa, ym, ref.p = c(-1, -2),
                  bin.rel = list("<=-24" = -999:-24, ">=36" = 36:999)) | fips + ym,
  data    = county,
  weights = ~ renter_occupied_housing_units,
  cluster = ~ state_key
)
iplot(m_sa_county, main = "Sun–Abraham (LSC county-month)", xlab = "Event time (months)", xlim = c(-24, 36))

# Support (how many treated cohorts even exist at each e?)
print(support_by_event_time_raw(county, g = "g_online_did", t = "ym", cohort_level = "cohort"))

# --- Callaway–Sant’Anna (not-yet-treated controls)
att_cs <- did::att_gt(
  yname   = Y,
  tname   = "ym",
  idname  = "fips",           # numeric already
  gname   = "g_online_did",   # 0 = never treated
  data    = county,
  panel   = TRUE,
  control_group = "notyettreated",
  clustervars   = "state_key",
  bstrap  = TRUE,
  biters  = 999,
  weightsname = "renter_occupied_housing_units"
)

es_cs <- did::aggte(att_cs, type = "dynamic", min_e = -24, max_e = 36)
print(summary(es_cs))
did::ggdid(es_cs)

# Pretrend joint test (robust to singular V via ginv)
print(wald_pretest_aggte_ginv(es_cs, pre_min = -12, pre_max = -3))

# --- Borusyak–Jaravel–Spiess (imputation)
imp <- didimputation::did_imputation(
  data = county,
  yname = Y,
  gname = "g_online_imp",   # never treated = after sample
  tname = "ym",
  idname = "fips",
  cluster_var = "state_key",
  horizon = -24:36,
  pretrends = -12:-3
)
print(imp)

# --- Leave-one-state-out sensitivity at +18 (Sun–Abraham)
loso18 <- loso_sunab(county, y = "y_log1p", g_sa = "g_online_sa", id = "fips", t = "ym",
                     e = 18L, w = "renter_occupied_housing_units")
print(loso18 %>% arrange(desc(est_e)))

# --- Wild cluster bootstrap p-value for one coefficient (example: event time +18)
# NOTE: param name depends on fixest naming; we search it.
pname <- names(coef(m_sa_county))[str_detect(names(coef(m_sa_county)), "::18\\b")][1]
if (!is.na(pname)) {
  bt <- fwildclusterboot::boottest(m_sa_county, param = pname, clustid = "state_key", B = 999)
  print(bt)
}

# ============================================================
# ROBUSTNESS: ETS ALL_SITES (city/court panel)
# ============================================================
m_sa_sites <- feols(
  y_log1p ~ sunab(g_online_sa, ym, ref.p = c(-1, -2),
                  bin.rel = list("<=-12" = -999:-12, ">=24" = 24:999)) | site_id + ym,
  data    = sites,
  cluster = ~ state_key
)
iplot(m_sa_sites, main = "Sun–Abraham (ETS all_sites)", xlab = "Event time (months)", xlim = c(-12, 24))

# ============================================================
# ROBUSTNESS: ETS ALLSTATES (state-month)  (LOW POWER)
# ============================================================
m_sa_states <- feols(
  y_log1p ~ sunab(g_online_sa, ym, ref.p = c(-1, -2),
                  bin.rel = list("<=-12" = -999:-12, ">=24" = 24:999)) | state_id + ym,
  data    = states,
  cluster = ~ state_key
)
iplot(m_sa_states, main = "Sun–Abraham (ETS allstates)", xlab = "Event time (months)", xlim = c(-12, 24))
