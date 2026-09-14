# =============================================================================
# report_basket_population_coverage.R  (2026-09-14)   *** NEEDS NETWORK ***
#
#   Rscript analysis/diagnostics/report_basket_population_coverage.R
#
# Answers "how much of the state do MO's 29 and NM's 14 basket counties
# actually cover?" in POPULATION and RENTER terms, which `basket_share` does
# not measure -- it is a count of counties, so it understates a basket that
# holds the populous ones and overstates one that holds the empty ones.
#
# Offline proxy already computed 2026-09-14 from ets_county_month.csv (basket
# share of all REPORTING counties' filings, 2020-01+):
#   NM  96.1% (median; 92.8-97.9)  -- all six major metros in basket
#   MO  86.6% (median; 78.9-91.0)  -- BUT St. Louis County (29189) and Jackson
#                                     County / Kansas City (29095) never report
#                                     at ALL in the source, so MO's ceiling is
#                                     set by source coverage, not by the basket.
# This script replaces those proxies with real ACS denominators.
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(tidycensus); library(glue)})
if (!nzchar(Sys.getenv("CENSUS_API_KEY"))) stop("CENSUS_API_KEY not set.", call. = FALSE)

YEAR <- 2023   # latest ACS 5-year likely available; lower if the pull errors
basket <- read_csv("data/processed/single_series_rebuild_basket.csv", show_col_types = FALSE) %>%
  mutate(fips = sprintf("%05d", as.integer(fips)))

acs <- get_acs(geography = "county",
               variables = c(renters = "B25003_003", total_hh = "B25003_001"),
               year = YEAR, survey = "acs5", output = "wide") %>%
  transmute(fips = GEOID, state_fips = substr(GEOID, 1, 2),
            renters = rentersE, households = total_hhE)

SF <- c(LA = "22", MA = "25", MO = "29", NM = "35", NV = "32", RI = "44")

out <- map_dfr(names(SF), function(st) {
  state_all <- acs %>% filter(state_fips == SF[[st]])
  b <- basket %>% filter(state_abb == st) %>% pull(fips)
  in_b <- state_all %>% filter(fips %in% b)
  tibble(state_abb = st,
         basket_counties = length(b), state_counties = nrow(state_all),
         basket_share_counties = length(b) / nrow(state_all),
         basket_renters = sum(in_b$renters), state_renters = sum(state_all$renters),
         renter_coverage = sum(in_b$renters) / sum(state_all$renters),
         household_coverage = sum(in_b$households) / sum(state_all$households))
})

cat(glue("\n=== BASKET COVERAGE, ACS {YEAR} 5-year ===\n\n"))
print(as.data.frame(out %>% mutate(across(ends_with("coverage"), ~ scales::percent(.x, 0.1)),
                                   basket_share_counties = scales::percent(basket_share_counties, 0.1))),
      row.names = FALSE)
cat("\nNOTE: renter_coverage is the number that belongs in any statement about",
    "\nwhat these series represent -- `basket_share` in the panel counts COUNTIES.\n")
write_csv(out, "data/processed/single_series_basket_population_coverage.csv")
