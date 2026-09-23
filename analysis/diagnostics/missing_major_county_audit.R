# =============================================================================
# missing_major_county_audit.R  (2026-09-14)
#
#   Rscript analysis/diagnostics/missing_major_county_audit.R
#   CENSUS_API_KEY=... ACS=TRUE Rscript analysis/diagnostics/missing_major_county_audit.R
#
# Question: "Colorado's panel series is missing Denver. Does any other state
# have a missing MAJOR county?"
#
# A county can go missing from a state's series two different ways, and they
# need different evidence:
#
#   (A) EXCLUDED FROM THE BASKET -- the county is in the LSC CCDI feed but does
#       not report in every basket-window month, so the fixed-basket rule drops
#       it. Its renter count IS in the feed, so this is fully measurable here.
#
#   (B) ABSENT FROM THE FEED -- the county never appears at all (Denver CO,
#       St. Louis County MO). The feed carries no renter count for it, so
#       offline we can only NAME these; ranking them by size needs ACS.
#       Set ACS=TRUE with a CENSUS_API_KEY to get the real denominators.
#
# `basket_share` in the panel does not answer either question: it is a count of
# counties, so it understates a basket holding the populous ones and overstates
# one holding the empty ones.
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(lubridate); library(glue)})

BASKET_START <- as.Date("2016-01-01")
BASKET_END   <- as.Date("2024-12-01")
BASKET_DROP  <- c(as.Date("2020-03-01"), as.Date("2021-07-31"))
USE_ACS      <- toupper(Sys.getenv("ACS", "FALSE")) %in% c("TRUE", "1", "YES")
OUT_DIR      <- "data/processed"

# ---- state fips crosswalk (same construction as the panel rebuild) ----------
fips_xwalk <- tibble(state_abb = state.abb, state_name = state.name) %>%
  bind_rows(tibble(state_abb = "DC", state_name = "District of Columbia")) %>%
  mutate(state_fips = as.integer(c(
    1,2,4,5,6,8,9,10,12,13,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,
    31,32,33,34,35,36,37,38,39,40,41,42,44,45,46,47,48,49,50,51,53,54,55,56,11)))

cty <- read_csv("data/raw/monthly_county_data_download.csv",
                show_col_types = FALSE, col_types = cols(fips = col_character())) %>%
  mutate(fips       = str_pad(fips, 5, pad = "0"),
         month_date = floor_date(as.Date(date), "month"),
         state_fips = as.integer(fips) %/% 1000L) %>%
  inner_join(fips_xwalk, by = "state_fips") %>%
  filter(!is.na(filings_count))

# ---- reproduce the fixed basket exactly (rebuild_state_month_panel.R:150-166)
basket_window <- cty %>%
  filter(month_date >= BASKET_START, month_date <= BASKET_END,
         !(month_date >= BASKET_DROP[1] & month_date <= BASKET_DROP[2]))

state_months <- basket_window %>% distinct(state_abb, month_date) %>%
  count(state_abb, name = "n_state_months")

basket <- basket_window %>% count(state_abb, fips, name = "n_obs") %>%
  inner_join(state_months, by = "state_abb") %>%
  filter(n_obs == n_state_months) %>% select(state_abb, fips)

# ---- one renter count per county in the feed --------------------------------
cty_renters <- cty %>% group_by(state_abb, fips, name) %>%
  summarise(renters = max(renter_occupied_housing_units, na.rm = TRUE),
            months  = n(), .groups = "drop") %>%
  mutate(renters = if_else(is.finite(renters), renters, NA_real_),
         in_basket = paste(state_abb, fips) %in% paste(basket$state_abb, basket$fips))

# ---- (A) largest county excluded from each state's basket -------------------
excluded_top <- cty_renters %>% filter(!in_basket) %>%
  group_by(state_abb) %>% slice_max(renters, n = 5, with_ties = FALSE) %>%
  ungroup()

state_cov <- cty_renters %>% group_by(state_abb) %>%
  summarise(feed_counties    = n(),
            basket_counties  = sum(in_basket),
            feed_renters     = sum(renters, na.rm = TRUE),
            basket_renters   = sum(renters[in_basket], na.rm = TRUE),
            .groups = "drop") %>%
  mutate(basket_share_of_feed_renters = basket_renters / feed_renters) %>%
  left_join(excluded_top %>% group_by(state_abb) %>%
              slice_max(renters, n = 1, with_ties = FALSE) %>%
              transmute(state_abb,
                        largest_excluded = name,
                        largest_excluded_renters = renters),
            by = "state_abb")

# ---- (B) counties absent from the feed entirely -----------------------------
adj <- read_lines("data/raw/county_adjacency_census.txt", locale = locale(encoding = "latin1"))
all_counties <- tibble(raw = adj) %>%
  separate(raw, into = c("name_a", "fips_a", "name_b", "fips_b"), sep = "\t",
           fill = "right", extra = "merge") %>%
  filter(!is.na(fips_a), str_detect(fips_a, "^\\s*\"?\\d{5}")) %>%
  transmute(fips = str_extract(fips_a, "\\d{5}"),
            county_name = str_remove_all(name_a, '"') %>% str_trim()) %>%
  filter(county_name != "") %>% distinct(fips, .keep_all = TRUE) %>%
  mutate(state_fips = as.integer(fips) %/% 1000L) %>%
  inner_join(fips_xwalk, by = "state_fips")

absent <- all_counties %>%
  anti_join(cty_renters %>% distinct(fips), by = "fips") %>%
  semi_join(state_cov, by = "state_abb")

absent_summary <- absent %>% group_by(state_abb) %>%
  summarise(absent_counties = n(),
            absent_names = paste(sort(county_name), collapse = "; "),
            .groups = "drop")

report <- state_cov %>% left_join(absent_summary, by = "state_abb") %>%
  mutate(absent_counties = replace_na(absent_counties, 0L),
         state_counties  = feed_counties + absent_counties) %>%
  arrange(basket_share_of_feed_renters)

write_csv(report,       file.path(OUT_DIR, "missing_major_county_audit.csv"))
write_csv(excluded_top, file.path(OUT_DIR, "missing_major_county_excluded_top5.csv"))
write_csv(absent,       file.path(OUT_DIR, "missing_major_county_absent_from_feed.csv"))

cat("\n== (A) Basket renter coverage OF THE FEED, worst first ==\n")
report %>%
  transmute(state_abb, basket_counties, feed_counties, state_counties,
            pct_feed_renters = sprintf("%.1f%%", 100 * basket_share_of_feed_renters),
            largest_excluded, largest_excluded_renters, absent_counties) %>%
  print(n = Inf)

cat("\n== (B) Counties absent from the LSC feed entirely (size unknown offline) ==\n")
absent_summary %>% arrange(desc(absent_counties)) %>% print(n = Inf)

if (USE_ACS) {
  stopifnot(nzchar(Sys.getenv("CENSUS_API_KEY")))
  suppressPackageStartupMessages(library(tidycensus))
  acs <- get_acs(geography = "county", variables = c(renters = "B25003_003"),
                 year = 2023, survey = "acs5", output = "wide") %>%
    transmute(fips = GEOID, acs_renters = rentersE)
  absent_ranked <- absent %>% left_join(acs, by = "fips") %>%
    arrange(state_abb, desc(acs_renters))
  state_true <- cty_renters %>% left_join(acs, by = "fips") %>%
    group_by(state_abb) %>%
    summarise(basket_acs_renters = sum(acs_renters[in_basket], na.rm = TRUE), .groups = "drop") %>%
    left_join(acs %>% mutate(state_fips = as.integer(fips) %/% 1000L) %>%
                inner_join(fips_xwalk, by = "state_fips") %>%
                group_by(state_abb) %>%
                summarise(state_acs_renters = sum(acs_renters, na.rm = TRUE), .groups = "drop"),
              by = "state_abb") %>%
    mutate(basket_share_of_state_renters = basket_acs_renters / state_acs_renters) %>%
    arrange(basket_share_of_state_renters)
  write_csv(absent_ranked, file.path(OUT_DIR, "missing_major_county_absent_ranked_acs.csv"))
  write_csv(state_true,    file.path(OUT_DIR, "missing_major_county_state_coverage_acs.csv"))
  cat("\n== (C) TRUE basket share of STATE renters (ACS 2023 5-yr) ==\n")
  print(state_true, n = Inf)
  cat("\n== Largest counties absent from the feed, by state (ACS) ==\n")
  absent_ranked %>% group_by(state_abb) %>% slice_max(acs_renters, n = 3, with_ties = FALSE) %>%
    ungroup() %>% print(n = Inf)
}

cat("\nWrote:", file.path(OUT_DIR, "missing_major_county_audit.csv"), "\n")
