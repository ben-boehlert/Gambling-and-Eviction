# =============================================================================
# add_wa_to_state_panel.R   (2026-09-14)
#
# Adds WASHINGTON to data/raw/state_month_panel_with_treatment.csv from the
# Eviction Lab internal county-month extract `ets_county_month.csv` (repo root,
# VERIFIED-SESSION, supplied 2026-09-03). WA has never been in the panel: it is
# absent from the LSC CCDI county download, and the 2026-09-14 single-series
# rebuild (data_prep/rebuild_single_series_from_ets_internal.R) filters the same
# extract to six states and never looks at it.
#
# SCOPE: ONE COUNTY. The extract's only WA site is TACOMA = Pierce County
# (53053). This is the LA / MA / NV convention -- a single-jurisdiction series
# standing in for a state -- so n_counties = 1 and basket_share = 1, and WA
# LEVELS ARE NOT STATEWIDE. Recorded in docs/STATE_SOURCES.md.
#
# WA IS A CONTROL, NOT A SWITCHER. WA legalized retail-only sports betting in
# Sep 2021 and has NO online launch (sports_gambling_legalization_dates.csv:
# online_start_date empty, online_only FALSE, retail_only TRUE). The panel dates
# treatment from online_start_date, so WA enters with treat_start = NA and joins
# the never-treated control pool alongside WI/MS/NM. Under the clean-anchor rule
# it contributes 113 clean control months; under a first_start-dated spec it
# would be a thin-baseline switcher (only 2021-08 of its six baseline months
# survives the COVID drop), which is NOT the headline definition.
#
# TRAILING PARTIAL MONTH. The extract's last WA month, 2026-06, reports 125
# against a 328 median over the prior six months (0.38) -- the collection cut,
# not a real collapse. It is dropped here. The same defect exists in four states
# already in the panel (LA 2026-03, MA/MO/NM 2026-06); those are handled by
# data_prep/censor_trailing_partial_months.R in the same vintage.
#
# SERIES-START RAMP: NOT CENSORED. 2017-01 runs 0.68 of its 2018/2019 norm and
# 2017-02 runs 0.71. That is far milder than the CT (0.15/0.19) and NH (0.20)
# months censor_series_start_ramps.R removed, and comparable to WI's 0.56, which
# that script deliberately left in. Left in, and documented so the next ramp
# audit does not relitigate it.
#
# Denominators are NOT filled here (the extract carries counts only). Run
# data_prep/fetch_acs_renter_denominators.R afterwards -- it needs network and
# pulls PIERCE COUNTY renters, not statewide WA.
#
# IDEMPOTENT: re-running replaces WA's rows rather than duplicating them, and
# CARRIES FORWARD any denominator the ACS script has already filled for a month
# it rewrites -- otherwise a re-run would silently blank the rates. Genuinely new
# months still arrive NA and need the ACS script.
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(lubridate); library(glue)})

PANEL   <- "data/raw/state_month_panel_with_treatment.csv"
EXTRACT <- "ets_county_month.csv"
DEPR    <- "data/raw/deprecated/state_month_panel_with_treatment_pre_wa_mi_2026-09-14.csv"
SRC     <- "ets_internal_county_wa_2026-09-14"
WA_FIPS <- 53053L
PARTIAL_TAIL_MAX_RATIO <- 0.75   # a final month below this share of its prior-6 median is a cut

stopifnot(file.exists(PANEL), file.exists(EXTRACT))

wa_raw <- read_csv(EXTRACT, show_col_types = FALSE) %>%
  filter(suppressWarnings(as.integer(xcourtcofips)) == WA_FIPS) %>%
  transmute(month_date   = make_date(xfileyear, xfilemonth, 1),
            filings_count = as.numeric(count)) %>%
  group_by(month_date) %>%                      # single site, but never assume
  summarise(filings_count = sum(filings_count), .groups = "drop") %>%
  arrange(month_date)

stopifnot(nrow(wa_raw) > 0, !anyNA(wa_raw$filings_count), all(wa_raw$filings_count >= 0))

# --- drop the trailing partial month ----------------------------------------
n <- nrow(wa_raw)
tail_ratio <- wa_raw$filings_count[n] / median(wa_raw$filings_count[(n - 6):(n - 1)])
if (tail_ratio < PARTIAL_TAIL_MAX_RATIO) {
  cat(glue("Dropping trailing partial month {format(wa_raw$month_date[n], '%Y-%m')}: ",
           "{wa_raw$filings_count[n]} = {sprintf('%.2f', tail_ratio)} of the prior-6 median"), "\n")
  wa_raw <- wa_raw[-n, ]
} else {
  cat(glue("Final month kept ({sprintf('%.2f', tail_ratio)} of prior-6 median)"), "\n")
}

# --- series-start ramp report (informational; nothing is censored) ----------
# Each of the first three months against the same calendar month in the next
# three years, pre-COVID only, exactly as series_start_ramp_check.R does it.
lead3 <- wa_raw %>% slice_head(n = 3)
ramp <- lead3 %>%
  rowwise() %>%
  mutate(norm = median(wa_raw$filings_count[
           month(wa_raw$month_date) == month(month_date) &
           wa_raw$month_date >  month_date &
           wa_raw$month_date <= month_date %m+% months(36) &
           wa_raw$month_date <  as.Date("2020-03-01")]),
         ratio_to_norm = round(filings_count / norm, 2)) %>%
  ungroup() %>%
  select(month_date, filings_count, norm, ratio_to_norm)
cat("Series-start ramp check (informational -- nothing censored):\n")
print(as.data.frame(ramp), row.names = FALSE)

wa <- wa_raw %>%
  mutate(state_abb = "WA",
         treat_start = as.Date(NA),               # no online launch: control cluster
         treated = FALSE,
         renter_occupied_housing_units = NA_real_, # fill via the ACS script (Pierce Co.)
         filings_per_1k_renters = NA_real_,
         panel_source = SRC, n_counties = 1L, basket_share = 1)

span <- interval(min(wa$month_date), max(wa$month_date)) %/% months(1) + 1
cat(glue("WA series: {format(min(wa$month_date),'%Y-%m')}..{format(max(wa$month_date),'%Y-%m')}, ",
         "{nrow(wa)} months, interior gaps: {span - nrow(wa)}"), "\n")
stopifnot(!anyDuplicated(wa$month_date), span == nrow(wa))   # WA must be contiguous

p <- read_csv(PANEL, show_col_types = FALSE) %>% mutate(month_date = as.Date(month_date))
dir.create(dirname(DEPR), recursive = TRUE, showWarnings = FALSE)
if (!file.exists(DEPR)) {
  write_csv(p, DEPR); message("Preserved pre-WA/MI vintage -> ", DEPR)
}

# Carry forward any denominator already filled for a month we are rewriting, so
# re-running this script does not wipe fetch_acs_renter_denominators.R's work.
# New months arrive NA and the ACS script fills them on its next run.
wa <- wa %>%
  rows_patch(p %>% filter(state_abb == "WA") %>%
               filter(!is.na(renter_occupied_housing_units)) %>%
               select(month_date, renter_occupied_housing_units),
             by = "month_date", unmatched = "ignore") %>%
  mutate(filings_per_1k_renters =
           if_else(is.na(renter_occupied_housing_units) | renter_occupied_housing_units <= 0,
                   NA_real_, filings_count / renter_occupied_housing_units * 1000))
kept <- sum(!is.na(wa$renter_occupied_housing_units))
if (kept) cat(glue("Carried forward existing denominators for {kept} WA month(s)"), "\n")

had <- sum(p$state_abb == "WA")
out <- bind_rows(p %>% filter(state_abb != "WA"), wa %>% select(all_of(names(p)))) %>%
  arrange(state_abb, month_date)
stopifnot(!anyDuplicated(out %>% select(state_abb, month_date)), !anyNA(out$filings_count))
write_csv(out, PANEL)
cat(glue("Wrote {PANEL}: {nrow(out)} rows ({nrow(p)} before; WA had {had}), ",
         "{n_distinct(out$state_abb)} states\n"))
