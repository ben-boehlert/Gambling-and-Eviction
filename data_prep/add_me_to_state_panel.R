#!/usr/bin/env Rscript
# ============================================================================
# add_me_to_state_panel.R  (2026-09-17)
#
# Splice Maine: LIVE LSC through 2023-05, then the FISCAL-YEAR-CORRECTED Maine
# Judicial Branch series from 2023-06.
#
# THE BUG THIS CORRECTS. data/raw/monthly_expansion/me_fed_state_month_
# courtsource.csv (parsed from the Maine Judicial Branch "15-Year Monthly FED
# Filing Trends", fed-monthly15yr-report.pdf) labels JUNE THROUGH DECEMBER of
# every year one year too LATE. Maine's judicial year boundary falls at June in
# that report, and the parser wrote the year label as a calendar year, so
# Jun-Dec of judicial year Y landed on calendar year Y instead of Y-1.
#
# EVIDENCE (against the live 2026-09-17 LSC download, 89 overlapping months):
#   as parsed                       : 27 exact (30%), mean |diff| 49.81 filings
#   relabel Jun-Dec back 12 months  : 64 exact (72%), mean |diff|  0.92, max 13
#   relabel Jul-Dec back 12 months  :                 mean |diff| 11.15
# June is the boundary, not July. The residual is LSC's own small revisions --
# the same +/-1-3 noise every other state shows between LSC vintages. Jan-May
# never matches the lagged LSC (0 of 40), confirming the shift is Jun-Dec only.
# The symptom that exposed it: as parsed, Maine showed NO COVID moratorium
# (2020-06/07/08 = 424/502/546, which are 2019's figures) and then a
# moratorium-shaped collapse a year late.
#
# WHY SPLICE RATHER THAN REPLACE. LSC is authoritative where it exists and is
# already in the panel via the county download. The corrected court series is
# needed only for 2023-06 onward, where LSC publishes zeros and then stops.
# Splicing keeps LSC's values and uses the court series only to extend.
#
# The PDF is NOT in the repo. If it is ever re-downloaded, re-parse it with the
# June boundary and check this file's numbers rather than trusting the relabel.
#
# Input : data/raw/monthly_expansion/me_fed_state_month_courtsource.csv
#         data/raw/state_month_panel_with_treatment.csv (ME's LSC rows)
# Output: data/raw/state_month_panel_with_treatment.csv (ME rows replaced)
#         data/raw/monthly_expansion/me_fed_state_month_fyfixed.csv (audit)
# Run from the project root:  Rscript data_prep/add_me_to_state_panel.R
#
# ME must also be listed in KEEP_OLD in rebuild_state_month_panel.R, or the
# next rebuild silently reverts Maine to the LSC-only county series.
# ============================================================================
suppressMessages({ library(tidyverse); library(lubridate); library(glue) })

PANEL <- "data/raw/state_month_panel_with_treatment.csv"
COURT <- "data/raw/monthly_expansion/me_fed_state_month_courtsource.csv"
SPLICE_AT <- as.Date("2023-06-01")   # first month taken from the court series
LABEL <- "me_jb_fed_fyfixed_2026-09-17"

court <- read_csv(COURT, show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date),
         # THE FIX: Jun-Dec labels are one year too late.
         month_date = if_else(month(month_date) >= 6,
                              month_date %m-% months(12), month_date)) %>%
  arrange(month_date) %>%
  select(month_date, filings_count = fed_filings)
stopifnot("corrected court series has duplicate months" = !anyDuplicated(court$month_date))
write_csv(court %>% mutate(source = paste0(LABEL, " (Jun-Dec relabelled -12mo)")),
          "data/raw/monthly_expansion/me_fed_state_month_fyfixed.csv")

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
             "{nrow(me_ext)} FY-corrected court months ",
             "({format(min(me_ext$month_date), '%Y-%m')}..{format(max(me_ext$month_date), '%Y-%m')}) ",
             "= {nrow(me_new)} months, no gaps. Panel {nrow(panel)} -> {nrow(out)} rows."))
