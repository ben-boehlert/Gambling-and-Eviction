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
# EXTENDED 2026-09-14 to cover the two states added the same day, which also
# arrive without denominators:
#   WA (tag ets_internal_county_wa_2026-09-14) -- PIERCE COUNTY only (53053),
#      because the WA series is Tacoma alone. A statewide denominator would
#      overstate it roughly 9x.
#   MI (tag mi_jdw_statewide_2026-09-03) -- all 83 MI counties, i.e. statewide.
#      The JDW numerator covers ~94% of the state's court footprint (six
#      excluded jurisdictions), so MI's rate is understated by ~6%. That is a
#      constant absorbed by state fixed effects; MI LEVELS ARE NOT COMPARABLE.
# The union of years is unchanged (2015-2026), so the six original states pull
# exactly the same ACS vintages they did before.
#
# Extended again the same day for ID (tag id_courts_a12_2026-09-14), which another
# session moved from the Twin Falls LSC basket to a statewide 44-county series --
# its old 10,312 denominator was Twin Falls' and is wrong for a statewide
# numerator by ~19x, so ID is statewide here too.
#
# This script only TOUCHES THOSE 9 STATES. The other 33 carry denominators that
# ship inside the LSC CCDI county download; it never overwrites those.
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(tidycensus); library(glue)})

PANEL   <- "data/raw/state_month_panel_with_treatment.csv"
BASKET  <- "data/processed/single_series_rebuild_basket.csv"
SRC_TAG <- "ets_internal_county_2026-09-03"

# Geography for the tags whose denominators are NOT read from BASKET. Each entry
# is the set of county FIPS whose renters form that state's denominator.
EXTRA_GEO <- list(
  `ets_internal_county_wa_2026-09-14` = tibble(state_abb = "WA", fips = "53053")
)

# Tags whose numerator is the WHOLE state: denominator = every county in it.
# Resolved from the ACS pull itself so no county list is hardcoded or kept in sync.
STATEWIDE <- c(`mi_jdw_statewide_2026-09-03` = "26",   # Michigan, 83 counties
               `id_courts_a12_2026-09-14`    = "16")   # Idaho, 44 counties

if (!nzchar(Sys.getenv("CENSUS_API_KEY")))
  stop("CENSUS_API_KEY not set. census_api_key('...', install = TRUE)", call. = FALSE)
if (!file.exists(BASKET))
  stop(glue("{BASKET} missing - run data_prep/rebuild_single_series_from_ets_internal.R first"),
       call. = FALSE)

panel  <- read_csv(PANEL,  show_col_types = FALSE) %>% mutate(month_date = as.Date(month_date))
basket <- read_csv(BASKET, show_col_types = FALSE) %>% mutate(fips = sprintf("%05d", as.integer(fips)))

TAGS <- c(SRC_TAG, names(EXTRA_GEO), names(STATEWIDE))
target <- panel %>% filter(panel_source %in% TAGS)
if (!nrow(target)) stop("No rebuilt rows found; nothing to do.", call. = FALSE)
years <- sort(unique(year(target$month_date)))

message(glue("Pulling ACS 5-year B25003_003 for {n_distinct(target$state_abb)} states, ",
             "years {min(years)}-{max(years)}"))

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

sw_geo <- imap_dfr(STATEWIDE, function(prefix, tag) {
  st <- unique(target$state_abb[target$panel_source == tag])
  if (!length(st)) return(tibble(state_abb = character(), fips = character()))
  g <- acs %>% distinct(fips) %>% filter(str_starts(fips, prefix)) %>% mutate(state_abb = st)
  stopifnot(nrow(g) >= 10)      # a real state, not an empty prefix match
  g
})
geo <- bind_rows(basket %>% select(state_abb, fips),
                 bind_rows(EXTRA_GEO) %>% select(state_abb, fips),
                 sw_geo %>% select(state_abb, fips)) %>%
  distinct(state_abb, fips)

den <- geo %>% inner_join(acs, by = "fips", relationship = "many-to-many") %>%
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
  summarise(months = n(), geo_counties = first(n_cty),
            renters = first(renter_occupied_housing_units),
            acs_years = paste(range(acs_year_used), collapse = "-"),
            median_rate = median(filings_per_1k_renters, na.rm = TRUE), .groups = "drop")
cat("\n=== ACS DENOMINATOR QA ===\n"); print(as.data.frame(qa), row.names = FALSE)
write_csv(qa, "data/processed/single_series_acs_denominator_qa.csv")

panel_out <- bind_rows(panel %>% filter(!panel_source %in% TAGS),
                       out %>% select(all_of(names(panel)))) %>%
  arrange(state_abb, month_date)
stopifnot(nrow(panel_out) == nrow(panel),
          !anyDuplicated(panel_out %>% select(state_abb, month_date)))
write_csv(panel_out, PANEL)
message(glue("Updated {PANEL} - denominators filled for {nrow(out)} rows across ",
             "{n_distinct(out$state_abb)} states."))
