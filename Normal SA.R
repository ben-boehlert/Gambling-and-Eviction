library(tidyverse)
library(lubridate)
library(fixest)

# ---- paths ----
path_county <- "monthly_county_data_download.csv"
path_sites  <- "all_sites_monthly_2020_2021.csv"
path_states <- "allstates_monthly_2020_2021.csv"
path_legal  <- "sports_gambling_legalization_dates.csv"

# ---- helpers ----
clean_state <- function(x) str_to_lower(x) |> str_replace_all("[^a-z]", "")
ym_int <- function(d) year(d) * 12L + month(d)

state_lookup <- tibble(
  st = c(state.abb, "DC"),
  state_name = c(state.name, "District of Columbia")
) %>% mutate(state_key = clean_state(state_name))

# ---- legalization timing ----
legal <- read_csv(path_legal, show_col_types = FALSE) %>%
  mutate(
    state_key = clean_state(state),
    online_start_date = as.Date(online_start_date),
    first_start_date  = as.Date(first_start_date),
    online_ym = if_else(!is.na(online_start_date), ym_int(online_start_date), NA_integer_),
    first_ym  = if_else(!is.na(first_start_date),  ym_int(first_start_date),  NA_integer_),
    has_online = coalesce(has_online, FALSE)
  ) %>%
  dplyr::select(state_key, online_ym, first_ym, has_online)

# ---- sanity: date ranges ----
rng_county <- read_csv(path_county, show_col_types = FALSE) %>%
  mutate(date = as.POSIXct(date, tz="UTC") |> as.Date()) %>%
  summarise(min=min(date), max=max(date), n_months=n_distinct(floor_date(date, "month")))
print(rng_county)

rng_sites <- read_csv(path_sites, show_col_types = FALSE) %>%
  mutate(date = my(month)) %>%
  summarise(min=min(date), max=max(date), n_months=n_distinct(date))
print(rng_sites)

rng_states <- read_csv(path_states, show_col_types = FALSE) %>%
  mutate(date = my(month)) %>%
  summarise(min=min(date), max=max(date), n_months=n_distinct(date))
print(rng_states)

# ============================================================
# all_sites: parse state from "City, ST" and AGGREGATE to city-month
# ============================================================
sites_agg <- read_csv(path_sites, show_col_types = FALSE) %>%
  tidyr::extract(city, into=c("city_name","st"), regex="^(.*),\\s*([A-Z]{2})$", remove=FALSE) %>%
  mutate(
    date = my(month),
    ym   = ym_int(date),
    st   = str_trim(st),
    state_key = state_lookup$state_key[match(st, state_lookup$st)]
  ) %>%
  filter(!is.na(state_key), !is.na(date)) %>%
  group_by(state_key, city_name, ym) %>%
  summarise(
    filings_2020 = sum(filings_2020, na.rm = TRUE),
    filings_avg  = sum(filings_avg,  na.rm = TRUE),
    filings_avg_prepandemic_baseline = sum(filings_avg_prepandemic_baseline, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    site_id = as.integer(factor(paste0(state_key, "::", city_name))),
    y = log(filings_2020 + 1)
  ) %>%
  left_join(legal, by="state_key") %>%
  mutate(g_online = if_else(has_online & !is.na(online_ym), online_ym, 0L)) %>%
  arrange(site_id, ym)

# ============================================================
# allstates: AGGREGATE to state-month
# ============================================================
states_agg <- read_csv(path_states, show_col_types = FALSE) %>%
  mutate(
    state_key = clean_state(state),
    date = my(month),
    ym   = ym_int(date)
  ) %>%
  filter(!is.na(state_key), !is.na(date)) %>%
  group_by(state_key, ym) %>%
  summarise(
    filings_2020 = sum(filings_2020, na.rm = TRUE),
    filings_avg  = sum(filings_avg,  na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    state_id = as.integer(factor(state_key)),
    y = log(filings_2020 + 1)
  ) %>%
  left_join(legal, by="state_key") %>%
  mutate(g_online = if_else(has_online & !is.na(online_ym), online_ym, 0L)) %>%
  arrange(state_id, ym)

# ============================================================
# Sun–Abraham event studies
# policy varies at state level => cluster by state_key
# ============================================================
m_sites <- feols(
  y ~ sunab(g_online, ym, ref.p = c(-1, -2)) | site_id + ym,
  data = sites_agg,
  cluster = ~ state_key
)
iplot(m_sites, main="Sun–Abraham (ETS/LSC all_sites aggregated)", xlab="Event time (months)")

m_states <- feols(
  y ~ sunab(g_online, ym, ref.p = c(-1, -2)) | state_id + ym,
  data = states_agg,
  cluster = ~ state_key
)
iplot(m_states, main="Sun–Abraham (ETS/LSC allstates aggregated)", xlab="Event time (months)")
