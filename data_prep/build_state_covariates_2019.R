################################################################################
# build_state_covariates_2019.R  (2026-09-29)
#
# State-level baseline covariates for the mortgage-delinquency design. Every
# value is a public aggregate measured in 2019 or earlier -- the last clean
# pre-COVID year, before any June-2022-design launch -- so none can respond to
# gambling legalization. Raw API responses are cached in data/raw/covariates/;
# delete a cache file to force a refetch.
#
# Sources
#   Foreclosure regime  RealtyTrac "Foreclosure Laws Comparison" table, Wayback
#                       snapshot 2010-12-30, the classification Mian, Sufi &
#                       Trebbi (2015, NBER w16685 Fig. 2) use. Parsed to
#                       data/raw/covariates/realtytrac_2010_foreclosure_laws.csv
#                       (judicial / nonjudicial bullets, comment, process days).
#                       judicial_only = judicial bullet and no non-judicial one.
#   ACS 2019 5-year     Census API, data profile tables (DP02/DP03/DP04/DP05).
#   Unemployment        BLS LAUS, seasonally adjusted state rate, 2019 mean of
#                       12 months (public API v1, no key).
#   House prices        FHFA purchase-only state HPI, seasonally adjusted,
#                       growth 2016Q4 -> 2019Q4.
#   FHA/VA share        CFPB HMDA Data Browser aggregates, 2019 originations
#                       (action 1), ALL loan purposes: (FHA + VA) / all. The API
#                       takes at most two filter criteria, so purpose cannot be
#                       fixed alongside action and loan type; refinances are in.
#
# Output: data/processed/state_covariates_2019.csv (51 rows: 50 states + DC).
# Run from the project root:  Rscript data_prep/build_state_covariates_2019.R
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(jsonlite)
  library(httr)
})
source("utils/eviction_treatment_schedule.R")

RAW <- "data/raw/covariates"
dir.create(RAW, recursive = TRUE, showWarnings = FALSE)
OUT <- "data/processed/state_covariates_2019.csv"
UA  <- user_agent("Mozilla/5.0")

states <- tibble(state_abb = EVICTION_STATE_UNIVERSE,
                 fips = sprintf("%02d", c(1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 15,
                                          16, 17, 18, 19, 20, 21, 22, 23, 24,
                                          25, 26, 27, 28, 29, 30, 31, 32, 33,
                                          34, 35, 36, 37, 38, 39, 40, 41, 42,
                                          44, 45, 46, 47, 48, 49, 50, 51, 53,
                                          54, 55, 56, 11)))
# EVICTION_STATE_UNIVERSE is state.abb (alphabetical by name) + DC; the FIPS
# vector above follows the same order. Guard it rather than trust it.
stopifnot(identical(states$state_abb[c(1, 5, 32, 51)], c("AL", "CA", "NY", "DC")),
          identical(states$fips[c(1, 5, 32, 51)], c("01", "06", "36", "11")))

cache_get <- function(file, fetch) {
  path <- file.path(RAW, file)
  if (!file.exists(path)) {
    txt <- fetch()
    writeLines(txt, path)
  }
  readLines(path, warn = FALSE)
}

# ---- Foreclosure regime (RealtyTrac 2010) ----------------------------------
rt <- read_csv(file.path(RAW, "realtytrac_2010_foreclosure_laws.csv"),
               show_col_types = FALSE) %>%
  mutate(state_abb = eviction_state_name_to_abb(state),
         judicial_only = as.integer(judicial == 1 & nonjudicial == 0),
         # process days: midpoint of a range, "+" dropped
         rt_process_days = vapply(strsplit(gsub("\\+", "", process_days), "-"),
                                  function(x) mean(as.numeric(x)), 0)) %>%
  select(state_abb, judicial_only, rt_comment = comment, rt_process_days)
stopifnot(nrow(rt) == 51, !anyNA(rt$state_abb), sum(rt$judicial_only) == 20)

# ---- ACS 2019 5-year profile -----------------------------------------------
acs_vars <- c(med_hh_income = "DP03_0062E", owner_occ_pct = "DP04_0046PE",
              age65_pct = "DP05_0024PE", ba_plus_pct = "DP02_0068PE",
              black_pct = "DP05_0038PE", hispanic_pct = "DP05_0071PE")
# The Census API requires a key (keyless requests redirect to a "Missing Key"
# page as of 2026-09-29). Set CENSUS_API_KEY in the environment to fetch; without
# it the ACS columns are written as NA and a warning is issued.
census_key <- Sys.getenv("CENSUS_API_KEY", "")
acs <- if (nzchar(census_key) || file.exists(file.path(RAW, "acs2019_profile_state.json"))) {
  acs_txt <- cache_get("acs2019_profile_state.json", function() {
    u <- paste0("https://api.census.gov/data/2019/acs/acs5/profile?get=NAME,",
                paste(acs_vars, collapse = ","), "&for=state:*&key=", census_key)
    txt <- content(GET(u, UA), as = "text", encoding = "UTF-8")
    if (!startsWith(trimws(txt), "[")) stop("Census API did not return JSON (bad key?)")
    txt
  })
  acs_m <- fromJSON(paste(acs_txt, collapse = ""))
  as_tibble(acs_m[-1, , drop = FALSE], .name_repair = ~ acs_m[1, ]) %>%
    rename(fips = state) %>%
    rename(!!!setNames(unname(acs_vars), names(acs_vars))) %>%
    mutate(across(all_of(names(acs_vars)), as.numeric)) %>%
    select(fips, all_of(names(acs_vars)))
} else {
  warning("CENSUS_API_KEY not set: ACS demographic columns written as NA.")
  tibble(fips = states$fips) %>%
    mutate(!!!setNames(rep(list(NA_real_), length(acs_vars)), names(acs_vars)))
}

# ---- BLS LAUS 2019 unemployment (SA), API v1 in batches of 25 ---------------
bls_ids <- paste0("LASST", states$fips, "0000000000003")
bls_txt <- cache_get("bls_laus_state_ur_sa_2019.json", function() {
  # 3 batches of 17: the API v1 cap is 25, and a 25/25/1 split returned the
  # lone DC series empty.
  res <- lapply(split(bls_ids, ceiling(seq_along(bls_ids) / 17)), function(ids) {
    r <- POST("https://api.bls.gov/publicAPI/v1/timeseries/data/", UA,
              body = list(seriesid = ids, startyear = "2019", endyear = "2019"),
              encode = "json")
    content(r, as = "parsed", simplifyVector = FALSE)$Results$series
  })
  toJSON(do.call(c, unname(res)), auto_unbox = TRUE)
})
bls <- fromJSON(paste(bls_txt, collapse = ""), simplifyVector = FALSE)
unemp <- bind_rows(lapply(bls, function(s) {
  v <- vapply(s$data, function(d) if (grepl("^M(0[1-9]|1[0-2])$", d$period))
    as.numeric(d$value) else NA_real_, 0)
  tibble(fips = substr(s$seriesID, 6, 7), unemp_2019 = mean(v, na.rm = TRUE),
         n_months = sum(!is.na(v)))
}))
stopifnot(nrow(unemp) == 51, all(unemp$n_months == 12))

# ---- FHFA purchase-only state HPI (SA) --------------------------------------
hpi_lines <- cache_get("fhfa_hpi_po_state.txt", function()
  content(GET("https://www.fhfa.gov/hpi/download/quarterly_datasets/hpi_po_state.txt",
              UA), as = "text", encoding = "UTF-8"))
hpi <- read_tsv(I(hpi_lines), show_col_types = FALSE) %>%
  filter(qtr == 4, yr %in% c(2016, 2019)) %>%
  select(state_abb = state, yr, indx_sa) %>%
  pivot_wider(names_from = yr, values_from = indx_sa, names_prefix = "y") %>%
  transmute(state_abb, hpi_growth_2016q4_2019q4 = 100 * (y2019 / y2016 - 1))

# ---- HMDA 2019 FHA/VA share of home-purchase originations -------------------
hmda_txt <- cache_get("hmda2019_orig_by_loantype_state.json", function() {
  res <- lapply(states$state_abb, function(s) {
    u <- paste0("https://ffiec.cfpb.gov/v2/data-browser-api/view/aggregations?",
                "years=2019&states=", s,
                "&actions_taken=1&loan_types=1,2,3,4")
    x <- fromJSON(content(GET(u, UA), as = "text", encoding = "UTF-8"),
                  simplifyVector = TRUE)
    if (length(x$aggregations$count) != 4L) stop("HMDA API: ", x$message %||% "unexpected response")
    tibble(state_abb = s, loan_type = x$aggregations$loan_types,
           count = x$aggregations$count)
  })
  toJSON(bind_rows(res))
})
hmda <- fromJSON(paste(hmda_txt, collapse = "")) %>% as_tibble() %>%
  group_by(state_abb) %>%
  summarise(fha_va_share_2019 = 100 * sum(count[loan_type %in% c("2", "3")]) /
              sum(count), .groups = "drop")

# ---- assemble ---------------------------------------------------------------
out <- states %>%
  left_join(rt, by = "state_abb") %>%
  left_join(acs, by = "fips") %>%
  left_join(unemp %>% select(fips, unemp_2019), by = "fips") %>%
  left_join(hpi, by = "state_abb") %>%
  left_join(hmda, by = "state_abb") %>%
  arrange(state_abb)
stopifnot(nrow(out) == 51,
          !anyNA(select(out, -rt_comment, -any_of(names(acs_vars)))))
write_csv(out, OUT)
message("wrote ", OUT, " (", nrow(out), " rows)")
