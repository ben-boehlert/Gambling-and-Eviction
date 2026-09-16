# =============================================================================
# add_id_to_state_panel.R   (2026-09-14)
#
# Replaces IDAHO in data/raw/state_month_panel_with_treatment.csv with the
# STATEWIDE 44-county monthly A12 (Unlawful Detainer/Eviction) series pulled
# from the Idaho Judicial Branch dashboard by
# data_prep/pull_id_powerbi_eviction_filings.R.
#
# Run (after the puller):  Rscript data_prep/add_id_to_state_panel.R
#
# WHAT CHANGES. Idaho was in the panel as TWIN FALLS COUNTY ALONE -- the only
# Idaho county that clears the fixed-basket rule in the LSC CCDI download
# (1 of 44 counties, 10,312 renters, mean 13.6 filings/month). It is replaced
# by all 44 counties, mean 255.7 filings/month.
#
#   ID before: 2016-01..2025-05, 113 months, 1 county
#   ID after:  2021-01..2026-06,  66 months, 44 counties
#
# THIS IS A SCOPE CHANGE AND A SHORTENING, DELIBERATELY BOTH.
#
# (a) Scope. The two series measure the same thing -- the puller asserts Twin
#     Falls reproduces the LSC annual totals (2021-2024: 129/138/156/180 vs
#     129/138/155/180) -- but over different geography. Idaho therefore gets a
#     FRESH panel-source tag, and no run may be paired across this boundary.
#
# (b) Shortening. 2016-2020 is NOT carried over from the Twin Falls series.
#     Splicing a 1-county series onto a 44-county one inside a single state
#     column is precisely the silent scope break that contaminated RI/MO/NM
#     before the 2026-09-14 rebuild. The Idaho dashboard's rolling five-year
#     window cannot supply pre-2021, so the choice is a short honest series or
#     a long dishonest one. The Twin Falls series is preserved verbatim at
#     data/raw/deprecated/id_twin_falls_lsc_series_pre_2026-09-14.csv.
#
# WHAT THIS BUYS. The post-COVID scenario keeps months after 2021-07-31
# (R/power/config.R covid_drop), so the new series covers `mde_postcovid` in
# full with seven months to spare, and Idaho's volatility drops from rank 2 of
# 39 (SD of month-over-month log change 0.542) to roughly the panel median
# (0.165, median 0.148). Idaho remains unusable in `mde_spliced`, which needs
# 2016-2020. See FINDINGS.md and the RUN_LEDGER.md row for this vintage.
#
# TREATMENT: NONE, EVER. Idaho has no row in
# data/raw/sports_gambling_legalization_dates.csv because it never legalized
# sports betting (constitutional prohibition; no bill introduced as of 2026) --
# absent as a NEVER-legalizer, unlike NV, which is absent as ALWAYS-treated.
# treat_start stays NA and treated stays FALSE. Idaho is control-pool only;
# this addition buys a cleaner control, never a treated cluster.
#
# DENOMINATORS ARE NOT FILLED HERE, by the MI/WA convention. The old 10,312 was
# Twin Falls' and is wrong for a statewide numerator by ~19x. Run
# data_prep/fetch_acs_renter_denominators.R afterwards -- it needs network.
# Until then ID carries NA renters and NA filings_per_1k_renters. The live
# outcome is y_log1p = log1p(filings_count), which does not use the
# denominator, so no LIVE spec is blocked by this.
#
# IDEMPOTENT: re-running replaces Idaho's rows rather than duplicating them.
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(lubridate); library(glue)})

PANEL    <- "data/raw/state_month_panel_with_treatment.csv"
ID_STATE <- "data/raw/idaho/id_state_month_a12.csv"
DEPR     <- "data/raw/deprecated/state_month_panel_with_treatment_pre_id_statewide_2026-09-14.csv"
TF_DEPR  <- "data/raw/deprecated/id_twin_falls_lsc_series_pre_2026-09-14.csv"
SRC      <- "id_courts_a12_2026-09-14"
EXPECT_COUNTIES <- 44L

stopifnot(file.exists(PANEL), file.exists(ID_STATE))

id_raw <- read_csv(ID_STATE, show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date))

stopifnot(nrow(id_raw) > 0,
          all(id_raw$filings_count >= 0),
          !anyDuplicated(id_raw$month_date),
          all(id_raw$n_counties == EXPECT_COUNTIES))

# No interior gaps: a missing month here would be read downstream as a real
# calendar hole rather than a pull failure.
span <- seq(min(id_raw$month_date), max(id_raw$month_date), by = "month")
stopifnot(length(span) == nrow(id_raw))

p <- read_csv(PANEL, show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date),
         treat_start = suppressWarnings(as.Date(treat_start)))

# Idaho must be untreated in the incoming panel; if a treat_start ever appears
# the never-legalizer premise above has changed and this script is wrong.
stopifnot(all(is.na(p$treat_start[p$state_abb == "ID"])))

old_id <- p %>% filter(state_abb == "ID") %>% arrange(month_date)

dir.create(dirname(DEPR), recursive = TRUE, showWarnings = FALSE)
if (!file.exists(DEPR)) {
  write_csv(p, DEPR); message("Preserved pre-ID-statewide vintage -> ", DEPR)
} else {
  message("Pre-ID-statewide vintage already preserved; leaving ", DEPR, " untouched.")
}
if (!file.exists(TF_DEPR) && nrow(old_id) > 0) {
  write_csv(old_id, TF_DEPR); message("Preserved Twin Falls ID series -> ", TF_DEPR)
}

id_new <- id_raw %>%
  transmute(state_abb = "ID",
            month_date,
            filings_count = as.numeric(filings_count),
            renter_occupied_housing_units = NA_real_,  # fill via the ACS script
            filings_per_1k_renters = NA_real_,
            treat_start = as.Date(NA),
            treated = FALSE,
            panel_source = SRC,
            n_counties = as.integer(n_counties),
            basket_share = 1)

out <- bind_rows(p %>% filter(state_abb != "ID"),
                 id_new %>% select(all_of(names(p)))) %>%
  arrange(state_abb, month_date)

stopifnot(!anyDuplicated(out %>% select(state_abb, month_date)),
          !anyNA(out$filings_count),
          n_distinct(out$state_abb) == n_distinct(p$state_abb))

write_csv(out, PANEL)

# --- Report the swap in the terms a reader needs to judge it ----------------
vol <- function(x) sd(diff(log1p(x)), na.rm = TRUE)
common <- c(max(min(old_id$month_date), min(id_new$month_date)),
            min(max(old_id$month_date), max(id_new$month_date)))
o <- old_id %>% filter(month_date >= common[1], month_date <= common[2])
n <- id_new %>% filter(month_date >= common[1], month_date <= common[2])

cat(glue("
=== Idaho panel swap ===
before : {format(min(old_id$month_date),'%Y-%m')}..{format(max(old_id$month_date),'%Y-%m')} \\
({nrow(old_id)} months, 1 county, mean {round(mean(old_id$filings_count),1)}/mo)
after  : {format(min(id_new$month_date),'%Y-%m')}..{format(max(id_new$month_date),'%Y-%m')} \\
({nrow(id_new)} months, {EXPECT_COUNTIES} counties, mean {round(mean(id_new$filings_count),1)}/mo)
overlap {format(common[1],'%Y-%m')}..{format(common[2],'%Y-%m')}: \\
SD dlog {round(vol(o$filings_count),3)} -> {round(vol(n$filings_count),3)}
panel  : {nrow(out)} rows ({nrow(p)} before), {n_distinct(out$state_abb)} states
source : {SRC}
NOTE   : renters/rate are NA for ID until data_prep/fetch_acs_renter_denominators.R runs.
"), "\n")
