# =============================================================================
# rebuild_single_series_from_ets_internal.R   (2026-09-14)
#
# Rebuilds the 6 Eviction Lab "single series" states (LA MA MO NM NV RI) in
# data/raw/state_month_panel_with_treatment.csv from the internal county-month
# extract `ets_county_month.csv` (repo root, VERIFIED-SESSION, supplied
# 2026-09-03). Those 6 were the stalest states in the panel -- median 39 months
# behind vs 12 for the LSC group -- and the extract carries all of them far
# past their panel endpoints (RI +77 months, MO/NM +41, MA +31, LA +7, NV +6).
#
# SITE SUMMING IS CORRECT, NOT A DOUBLE COUNT. Two states have >1 site on one
# county: LA (NEWORLEANS-FCC + -SCC on 22071) and NV (three LASVEGAS-* on
# 32003). Verified 2026-09-14 that these are COMPLEMENTARY COURTS, not nested
# duplicates -- FCC vs SCC run 478 vs 106 in 2019-01 and are never equal in any
# of 85 shared months; the three Clark County jurisdictions likewise (0 of 125
# shared months identical). RI's PROVIDENCE (44007) and RHODE ISLAND
# (44001/03/05) cover disjoint counties, as do MO's MISSOURI and STLOUIS.
#
# PER-STATE BASKETS. RI/MA/LA/NV report a constant county set in every month
# (basket_share = 1). MO and NM do NOT: MO has 103 counties ever and ZERO
# present in all months (n_counties swings 1..85 across 118 composition
# changes, plus 7 calendar gaps); NM has 31 ever and 13 always. Both therefore
# get a FIXED BASKET from a per-state start, mirroring the 2026-08-28 per-state
# basket convention. This is a deliberate SCOPE CHANGE for MO and NM -- they
# move from a statewide single series to a county basket -- and their
# basket_share lands well below the 1.0 every other state carries. Flagged in
# the QA output and in docs/DATA_CURRENCY.md; do not cite MO/NM levels without
# reading it.
#
# Denominators are NOT filled here (the extract carries counts only). Run
# data_prep/fetch_acs_renter_denominators.R afterwards -- it needs network.
#
# Writes a NEW canonical panel; the prior vintage is moved to
# data/raw/deprecated/ by the caller and recorded in MOVES.md.
#
# Output: data/raw/state_month_panel_with_treatment.csv (rebuilt rows for 6),
#         data/processed/single_series_rebuild_qa.csv
#         data/processed/single_series_rebuild_overlap_comparison.csv
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(lubridate); library(glue)})

EXTRACT <- "ets_county_month.csv"
PANEL   <- "data/raw/state_month_panel_with_treatment.csv"
SRC_TAG <- "ets_internal_county_2026-09-03"

# Per-state basket start. NA = use the state's full span (coverage is constant).
BASKET_START <- list(LA = NA, MA = NA, NV = NA, RI = NA,
                     MO = as.Date("2020-01-01"), NM = as.Date("2020-01-01"))
FIPS <- c(`22` = "LA", `25` = "MA", `29` = "MO", `32` = "NV", `35` = "NM", `44` = "RI")

stopifnot(file.exists(EXTRACT), file.exists(PANEL))
old <- read_csv(PANEL, show_col_types = FALSE) %>% mutate(month_date = as.Date(month_date))

ext <- read_csv(EXTRACT, show_col_types = FALSE) %>%
  filter(!is.na(xcourtcofips), nzchar(as.character(xcourtcofips))) %>%
  mutate(fips = sprintf("%05d", as.integer(xcourtcofips)),
         state_abb = FIPS[as.character(as.integer(xcourtcofips) %/% 1000L)],
         month_date = make_date(xfileyear, xfilemonth, 1)) %>%
  filter(!is.na(state_abb))

# Sum complementary sites within a county-month (see header).
cty <- ext %>% group_by(state_abb, fips, month_date) %>%
  summarise(filings_count = sum(count, na.rm = TRUE), .groups = "drop")

build_state <- function(st) {
  s <- cty %>% filter(state_abb == st)
  start <- BASKET_START[[st]]
  if (!is.na(start)) s <- s %>% filter(month_date >= start)
  months <- sort(unique(s$month_date))
  per_month <- split(s$fips, s$month_date)
  basket <- Reduce(intersect, per_month)
  if (!length(basket)) stop(glue("{st}: empty fixed basket - widen the start"), call. = FALSE)
  max_rep <- max(lengths(per_month))
  s %>% filter(fips %in% basket) %>%
    group_by(state_abb, month_date) %>%
    summarise(filings_count = sum(filings_count), n_counties = n(), .groups = "drop") %>%
    mutate(basket_share = length(basket) / max_rep,
           panel_source = SRC_TAG)
}

new6 <- map_dfr(names(BASKET_START), build_state)

# Carry each state's existing treat_start forward (constant per state; do NOT
# re-derive it here -- the panel's treat_start convention is set upstream).
ts <- old %>% distinct(state_abb, treat_start) %>% filter(state_abb %in% names(BASKET_START))
new6 <- new6 %>% left_join(ts, by = "state_abb") %>%
  mutate(treat_start = as.Date(na_if(as.character(treat_start), "NA")),
         treated = !is.na(treat_start) & month_date >= treat_start,
         renter_occupied_housing_units = NA_real_,   # filled by the ACS script
         filings_per_1k_renters = NA_real_) %>%
  select(all_of(names(old)))

# ---- Overlap comparison BEFORE replacing (documents the seam) ---------------
cmp <- old %>% filter(state_abb %in% names(BASKET_START)) %>%
  select(state_abb, month_date, old_count = filings_count) %>%
  inner_join(new6 %>% select(state_abb, month_date, new_count = filings_count),
             by = c("state_abb", "month_date")) %>%
  mutate(ratio = new_count / old_count)
cmp_sum <- cmp %>% group_by(state_abb) %>%
  summarise(overlap_months = n(), median_ratio = median(ratio, na.rm = TRUE),
            min_ratio = min(ratio, na.rm = TRUE), max_ratio = max(ratio, na.rm = TRUE),
            share_within_5pct = mean(abs(ratio - 1) <= 0.05, na.rm = TRUE), .groups = "drop")
cat("=== OVERLAP COMPARISON (new vs current series, shared months) ===\n")
print(as.data.frame(cmp_sum), row.names = FALSE)
write_csv(cmp, "data/processed/single_series_rebuild_overlap_comparison.csv")

panel <- bind_rows(old %>% filter(!state_abb %in% names(BASKET_START)), new6) %>%
  arrange(state_abb, month_date)

qa <- new6 %>% group_by(state_abb) %>%
  summarise(months = n(), span_lo = min(month_date), span_hi = max(month_date),
            n_counties = first(n_counties), basket_share = first(basket_share),
            .groups = "drop") %>%
  left_join(old %>% group_by(state_abb) %>%
              summarise(old_months = n(), old_hi = max(month_date), .groups = "drop"),
            by = "state_abb") %>%
  mutate(months_gained = interval(old_hi, span_hi) %/% months(1))
# Persist the exact basket so the ACS denominator matches the numerator geography.
basket_out <- map_dfr(names(BASKET_START), function(st) {
  s <- cty %>% filter(state_abb == st)
  start <- BASKET_START[[st]]
  if (!is.na(start)) s <- s %>% filter(month_date >= start)
  b <- Reduce(intersect, split(s$fips, s$month_date))
  tibble(state_abb = st, fips = b)
})
write_csv(basket_out, "data/processed/single_series_rebuild_basket.csv")

cat("\n=== REBUILD QA ===\n"); print(as.data.frame(qa), row.names = FALSE)
write_csv(qa, "data/processed/single_series_rebuild_qa.csv")

stopifnot(!anyDuplicated(panel %>% select(state_abb, month_date)),
          !anyNA(panel$state_abb), !anyNA(panel$month_date))
write_csv(panel, PANEL)
cat(glue("\nWrote {PANEL}: {nrow(panel)} rows, {n_distinct(panel$state_abb)} states ",
         "(was {nrow(old)} rows)"), "\n")
