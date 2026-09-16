# =============================================================================
# add_mi_to_state_panel.R   (2026-09-14)
#
# Adds MICHIGAN to data/raw/state_month_panel_with_treatment.csv from
# data/raw/michigan/mi_lt_statewide_month_year.csv -- the statewide monthly
# Landlord/Tenant new-filing series parsed 2026-09-03 by
# data_prep/parse_mi_jdw_lt_filings_pdf.py out of the Michigan Courts Judicial
# Data Warehouse PDF (conditional-dismissals.pdf). MI has never been in the
# panel: it is absent from the LSC CCDI county download and from the Eviction
# Lab internal extract, so this is the first monthly MI series the project has.
#
# SCOPE: STATEWIDE, MINUS SIX JURISDICTIONS. The JDW report excludes Berrien
# County, Grand Rapids, Dearborn Heights, Center Line & Warren, Northern Macomb
# County, and Grandville & Walker. It publishes no county values, so the missing
# footprint cannot be reconstructed -- n_counties and basket_share are NA, the
# MD / NH / WI / OR convention for a statewide court source. The QA block below
# measures the shortfall against the annual county dashboard (~94%), which means
# a statewide ACS denominator UNDERSTATES MI's rate by roughly 6%. That is a
# constant absorbed by state fixed effects, but MI LEVELS ARE NOT COMPARABLE to
# other states'. Recorded in docs/STATE_SOURCES.md.
#
# 21 INTERIOR GAPS, AND WHY THEY ARE OMITTED ROWS. 68 of the 89 calendar months
# are recoverable; the other 21 are `unlabelled_in_source` -- Power BI omitted
# the bar label, so no value exists. The panel forbids NA filings_count (see
# analysis/diagnostics/panel_preflight_audit.R and the note in
# censor_series_start_ramps.R), so those months are simply absent rows. They are
# never zero-filled and never interpolated. The series is complete 2019-01
# through 2023-01; every gap falls in 2023-02 or later.
#
# WHAT MI IS WORTH, BY TREATMENT DEFINITION (clean-anchor rule: 6-month
# pre-launch baseline, outcomes 12-24 months post, COVID 2020-03..2021-07
# dropped):
#   online  2021-01 (the panel's treat_start): baseline 0 of 0 eligible -- all
#           six baseline months fall inside the COVID drop window -- outcomes
#           13 of 13. Outcomes without a baseline.
#   shift12 2022-01 (the PAP headline schedule): baseline 5 of 5 eligible,
#           outcomes 2 of 13. The outcome window lands in MI's gap field.
#   first_start 2020-03 (retail): baseline 6 of 6, outcomes 8 of 8. MI is a
#           FULL clean switcher only on this definition.
# MI is therefore NOT a clean-anchor switcher under either headline definition.
# It is added because it is a real cluster with 68 real months, not because it
# raises the headline switcher count. See FINDINGS.md and
# docs/findings-archive/2026-09-14_wa-mi-panel-addition.md.
#
# Denominators are NOT filled here. Run data_prep/fetch_acs_renter_denominators.R
# afterwards -- it needs network and pulls STATEWIDE MI renters (see the ~6%
# caveat above).
#
# IDEMPOTENT: re-running replaces MI's rows rather than duplicating them, and
# CARRIES FORWARD any denominator the ACS script has already filled for a month
# it rewrites -- otherwise a re-run would silently blank the rates. Genuinely new
# months still arrive NA and need the ACS script.
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(lubridate); library(glue)})

PANEL   <- "data/raw/state_month_panel_with_treatment.csv"
MONTHLY <- "data/raw/michigan/mi_lt_statewide_month_year.csv"
ANNUAL  <- "data/raw/michigan/mi_state_year_landlord_tenant_filings.csv"
DEPR    <- "data/raw/deprecated/state_month_panel_with_treatment_pre_wa_mi_2026-09-14.csv"
SRC     <- "mi_jdw_statewide_2026-09-03"
TREAT   <- as.Date("2021-01-01")          # online_start_date for Michigan
COVERAGE_BOUNDS <- c(0.90, 0.98)          # JDW footprint vs the county dashboard

stopifnot(file.exists(PANEL), file.exists(MONTHLY), file.exists(ANNUAL))

raw <- read_csv(MONTHLY, show_col_types = FALSE)

mi_obs <- raw %>%
  filter(!is.na(filings)) %>%
  transmute(month_date = make_date(year, month_num, 1),
            filings_count = as.numeric(filings),
            source_kind = source) %>%
  arrange(month_date)

stopifnot(nrow(mi_obs) > 0, all(mi_obs$filings_count >= 0), !anyDuplicated(mi_obs$month_date))

cat("Source of each observed month:\n")
print(as.data.frame(count(mi_obs, source_kind)), row.names = FALSE)

# --- QA: how much of Michigan does the JDW series actually cover? ------------
# 2019 is the only year where the monthly series is complete for all 12 months,
# so it is the only year the two products can be compared.
jdw_2019 <- sum(mi_obs$filings_count[year(mi_obs$month_date) == 2019])
dash_2019 <- read_csv(ANNUAL, show_col_types = FALSE) %>%
  filter(year == 2019) %>% pull(reported_county_sum) %>% as.numeric()
stopifnot(length(dash_2019) == 1, is.finite(dash_2019),
          sum(year(mi_obs$month_date) == 2019) == 12)
coverage <- jdw_2019 / dash_2019
cat(glue("Footprint QA (2019): JDW monthly {format(jdw_2019, big.mark=',')} vs county-dashboard ",
         "{format(dash_2019, big.mark=',')} = {sprintf('%.3f', coverage)} coverage"), "\n")
stopifnot(coverage >= COVERAGE_BOUNDS[1], coverage <= COVERAGE_BOUNDS[2])

mi <- mi_obs %>%
  transmute(month_date, filings_count,
            state_abb = "MI",
            treat_start = TREAT,
            treated = month_date >= TREAT,
            renter_occupied_housing_units = NA_real_,  # fill via the ACS script
            filings_per_1k_renters = NA_real_,
            panel_source = SRC, n_counties = NA_integer_, basket_share = NA_real_)

# --- gap inventory -----------------------------------------------------------
span <- interval(min(mi$month_date), max(mi$month_date)) %/% months(1) + 1
holes <- setdiff(seq(min(mi$month_date), max(mi$month_date), by = "month"), mi$month_date)
cat(glue("MI series: {format(min(mi$month_date),'%Y-%m')}..{format(max(mi$month_date),'%Y-%m')}, ",
         "{nrow(mi)} months of {span}, interior gaps: {length(holes)}"), "\n")
cat("  gap months:", paste(format(as.Date(holes, origin = "1970-01-01"), "%Y-%m"),
                           collapse = " "), "\n")
cat(glue("  contiguous through {format(max(mi$month_date[mi$month_date < min(as.Date(holes, origin='1970-01-01'))]), '%Y-%m')}"), "\n")
stopifnot(span - nrow(mi) == length(holes))

p <- read_csv(PANEL, show_col_types = FALSE) %>% mutate(month_date = as.Date(month_date))
dir.create(dirname(DEPR), recursive = TRUE, showWarnings = FALSE)
if (!file.exists(DEPR)) {
  write_csv(p, DEPR); message("Preserved pre-WA/MI vintage -> ", DEPR)
}

# Carry forward any denominator already filled for a month we are rewriting, so
# re-running this script does not wipe fetch_acs_renter_denominators.R's work.
mi <- mi %>%
  rows_patch(p %>% filter(state_abb == "MI") %>%
               filter(!is.na(renter_occupied_housing_units)) %>%
               select(month_date, renter_occupied_housing_units),
             by = "month_date", unmatched = "ignore") %>%
  mutate(filings_per_1k_renters =
           if_else(is.na(renter_occupied_housing_units) | renter_occupied_housing_units <= 0,
                   NA_real_, filings_count / renter_occupied_housing_units * 1000))
kept <- sum(!is.na(mi$renter_occupied_housing_units))
if (kept) cat(glue("Carried forward existing denominators for {kept} MI month(s)"), "\n")

had <- sum(p$state_abb == "MI")
out <- bind_rows(p %>% filter(state_abb != "MI"), mi %>% select(all_of(names(p)))) %>%
  arrange(state_abb, month_date)
stopifnot(!anyDuplicated(out %>% select(state_abb, month_date)), !anyNA(out$filings_count))
write_csv(out, PANEL)
cat(glue("Wrote {PANEL}: {nrow(out)} rows ({nrow(p)} before; MI had {had}), ",
         "{n_distinct(out$state_abb)} states\n"))
