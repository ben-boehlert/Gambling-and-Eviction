#!/usr/bin/env Rscript
# ============================================================================
# add_me_to_state_panel.R  (2026-09-17; court input replaced 2026-10-19)
#
# Splice Maine: LIVE LSC through 2023-05, then the Maine Judicial Branch
# "15-Year Monthly FED Filing Trends" series from 2023-06.
#
# WHY SPLICE RATHER THAN REPLACE. LSC is authoritative where it exists and is
# already in the panel via the county download. The court series is needed only
# for 2023-06 onward, where LSC publishes zeros and then stops. Splicing keeps
# LSC's values and uses the court series only to extend.
#
# 2026-10-19: the court input is now the per-page-header parse of the copy with
# newest ref date 2026-09-18 (data_prep/monthly_panel_expansion/
# 07c_parse_me_fed_monthly15yr.R), which runs to 2026-08 and needs NO relabel.
# The 2026-09-17 version of this script read the older single-header parse
# (me_fed_state_month_courtsource.csv) and shifted Jun-Dec back 12 months. That
# shift was right for that copy only: the PDF's pages are rolling 15-year
# windows updated one month at a time, so which pages lag a year depends on the
# copy's date, not on a June judicial-year boundary. On the overlap the new
# parse matches the shifted series in 118 of 120 months (max |diff| 1) and LSC
# in 63 of 89 (max |diff| 13, LSC's own revisions). The 2026-09-17 script is in
# data_prep/deprecated/add_me_to_state_panel_jun-dec-relabel_2026-09-17.R.
#
# Input : data/raw/monthly_expansion/me_fed_state_month_ref20260918.csv
#         data/raw/state_month_panel_with_treatment.csv (ME's LSC rows)
# Output: data/raw/state_month_panel_with_treatment.csv (ME rows replaced)
# Run from the project root:  Rscript data_prep/add_me_to_state_panel.R
#
# ME must also be listed in KEEP_OLD in rebuild_state_month_panel.R, or the
# next rebuild silently reverts Maine to the LSC-only county series.
# ============================================================================
suppressMessages({ library(tidyverse); library(lubridate); library(glue) })

PANEL <- "data/raw/state_month_panel_with_treatment.csv"
COURT <- "data/raw/monthly_expansion/me_fed_state_month_ref20260918.csv"
SPLICE_AT <- as.Date("2023-06-01")   # first month taken from the court series
LABEL <- "me_jb_fed_ref20260918"

court <- read_csv(COURT, show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date)) %>%
  arrange(month_date) %>%
  select(month_date, filings_count = fed_filings)
stopifnot("court series has duplicate months" = !anyDuplicated(court$month_date))

panel <- read_csv(PANEL, show_col_types = FALSE) %>% mutate(month_date = as.Date(month_date))
me_lsc <- panel %>% filter(state_abb == "ME", month_date < SPLICE_AT)
stopifnot("no LSC ME rows to splice onto" = nrow(me_lsc) > 0)

# The renter denominator is a constant ACS figure per state in this panel; carry
# it forward rather than leaving the rate NA on the extended months.
den <- unique(me_lsc$renter_occupied_housing_units)
stopifnot("ME renter denominator is not constant" = length(den) == 1L, is.finite(den))

me_ext <- court %>%
  filter(month_date >= SPLICE_AT) %>%
  transmute(state_abb = "ME", month_date, filings_count = as.numeric(filings_count),
            renter_occupied_housing_units = den,
            filings_per_1k_renters = filings_count / den * 1000,
            treat_start = unique(me_lsc$treat_start)[1],
            treated = !is.na(treat_start) & month_date >= treat_start,
            panel_source = LABEL,
            n_counties = NA_integer_, basket_share = NA_real_,
            lsc_pct_of_hist_avg = NA_real_, lsc_pct_coverage = NA_real_)

me_new <- bind_rows(me_lsc, me_ext) %>% arrange(month_date)
mi <- function(d) year(d) * 12L + (month(d) - 1L)
gaps <- setdiff(seq(mi(min(me_new$month_date)), mi(max(me_new$month_date))), mi(me_new$month_date))
stopifnot("spliced ME series has an interior gap" = length(gaps) == 0L)

out <- bind_rows(panel %>% filter(state_abb != "ME"), me_new) %>% arrange(state_abb, month_date)
stopifnot("duplicate state-month after splice" = !anyDuplicated(out[c("state_abb","month_date")]))
write_csv(out, PANEL)

message(glue("ME spliced: {nrow(me_lsc)} LSC months (..{format(max(me_lsc$month_date), '%Y-%m')}) + ",
             "{nrow(me_ext)} court months ",
             "({format(min(me_ext$month_date), '%Y-%m')}..{format(max(me_ext$month_date), '%Y-%m')}) ",
             "= {nrow(me_new)} months, no gaps. Panel {nrow(panel)} -> {nrow(out)} rows."))
