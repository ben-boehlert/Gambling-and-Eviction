# =============================================================================
# fetch_acs_renter_denominators.R   (2026-09-14)   *** NEEDS NETWORK ***
#
# Fills renter_occupied_housing_units / filings_per_1k_renters for the states
# rebuilt from ets_county_month.csv, which carries counts only.
#
# Run:  Rscript data_prep/fetch_acs_renter_denominators.R
#
# Requires CENSUS_API_KEY (already set in ~/.Renviron) and tidycensus.
#
# WHAT IT PULLS. ACS 5-year table B25003_003 (Tenure: renter-occupied housing
# units) at COUNTY level, for each ACS year spanned by the panel. County level
# matters: MO and NM are fixed county BASKETS (29 and 14 counties), not whole
# states, so a state-level denominator would overstate them roughly 3x and 2x
# and fabricate rates far below truth. The basket is read back out of the panel
# via data/processed/single_series_rebuild_basket.csv so the denominator always
# matches the numerator's geography.
#
# VINTAGE RULE. Each panel month takes the ACS 5-year estimate for its own
# calendar year where available, else the nearest available year (ACS 5-year
# runs ~2 years behind, so 2025/2026 months fall back to the latest release).
# The fallback year is recorded per row in acs_year_used so no rate is ever
# quoted without its vintage.
#
# This script only TOUCHES THE 6 REBUILT STATES. The other 33 carry
# denominators that ship inside the LSC CCDI county download; it never
# overwrites those.
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(tidycensus); library(glue)})

PANEL   <- "data/raw/state_month_panel_with_treatment.csv"
BASKET  <- "data/processed/single_series_rebuild_basket.csv"
SRC_TAG <- "ets_internal_county_2026-09-03"

if (!nzchar(Sys.getenv("CENSUS_API_KEY")))
  stop("CENSUS_API_KEY not set. census_api_key('...', install = TRUE)", call. = FALSE)
if (!file.exists(BASKET))
  stop(glue("{BASKET} missing - run data_prep/rebuild_single_series_from_ets_internal.R first"),
       call. = FALSE)

panel  <- read_csv(PANEL,  show_col_types = FALSE) %>% mutate(month_date = as.Date(month_date))
basket <- read_csv(BASKET, show_col_types = FALSE) %>% mutate(fips = sprintf("%05d", as.integer(fips)))

target <- panel %>% filter(panel_source == SRC_TAG)
if (!nrow(target)) stop("No rebuilt rows found; nothing to do.", call. = FALSE)
years <- sort(unique(year(target$month_date)))

message(glue("Pulling ACS 5-year B25003_003 for {length(unique(basket$state_abb))} states, ",
             "{n_distinct(basket$fips)} counties, years {min(years)}-{max(years)}"))

pull_year <- function(yr) {
  tryCatch({
    get_acs(geography = "county", variables = c(renters = "B25003_003"),
            year = yr, survey = "acs5", cache_table = TRUE) %>%
      transmute(fips = GEOID, acs_year = yr, renters = estimate)
  }, error = function(e) { message(glue("  {yr}: unavailable ({conditionMessage(e)})")); NULL })
}
acs <- map_dfr(years, pull_year)
if (!nrow(acs)) stop("No ACS years returned - check network / key.", call. = FALSE)
avail <- sort(unique(acs$acs_year))
message(glue("  ACS years returned: {paste(avail, collapse = ', ')}"))

# Nearest-available-year fallback, recorded per row.
map_year <- function(y) avail[which.min(abs(avail - y))]

den <- basket %>% inner_join(acs, by = "fips", relationship = "many-to-many") %>%
  group_by(state_abb, acs_year) %>%
  summarise(renters = sum(renters, na.rm = TRUE), n_cty = n(), .groups = "drop")

out <- target %>%
  mutate(acs_year_used = map_dbl(year(month_date), map_year)) %>%
  select(-renter_occupied_housing_units, -filings_per_1k_renters) %>%
  left_join(den %>% rename(acs_year_used = acs_year), by = c("state_abb", "acs_year_used")) %>%
  mutate(renter_occupied_housing_units = renters,
         filings_per_1k_renters = if_else(is.na(renters) | renters <= 0, NA_real_,
                                          filings_count / renters * 1000))

qa <- out %>% group_by(state_abb) %>%
  summarise(months = n(), basket_counties = first(n_cty),
            renters = first(renter_occupied_housing_units),
            acs_years = paste(range(acs_year_used), collapse = "-"),
            median_rate = median(filings_per_1k_renters, na.rm = TRUE), .groups = "drop")
cat("\n=== ACS DENOMINATOR QA ===\n"); print(as.data.frame(qa), row.names = FALSE)
write_csv(qa, "data/processed/single_series_acs_denominator_qa.csv")

panel_out <- bind_rows(panel %>% filter(panel_source != SRC_TAG),
                       out %>% select(all_of(names(panel)))) %>%
  arrange(state_abb, month_date)
stopifnot(nrow(panel_out) == nrow(panel),
          !anyDuplicated(panel_out %>% select(state_abb, month_date)))
write_csv(panel_out, PANEL)
message(glue("Updated {PANEL} - denominators filled for {nrow(out)} rows across ",
             "{n_distinct(out$state_abb)} states."))
