# =============================================================================
# add_oregon_to_state_panel.R   (2026-09-14)
#
# Adds OREGON to data/raw/state_month_panel_with_treatment.csv. OR online sports
# betting began 2019-10 and OR has never been in the panel, so this adds a new
# (partial) switcher.
#
# TWO SOURCES, SPLICED -- and the splice is unavoidable:
#   pre  2018-01..2019-12  Oregon Judicial Department "Cases Filed" PDFs,
#                          monthly statewide Landlord Tenant counts
#                          (data/raw/monthly_expansion/or_raw/or_ojd_lt_state_month_2018_2020.csv)
#   post 2020-01..2026-07  Evicted in Oregon dashboard (Lisa Bates, PSU; underlying
#                          OJD circuit-court records)
#                          (data/raw/evicted_in_oregon/oregon_statewide_monthly_2020_2026.tsv)
#
# The dashboard begins 2020-01, so it alone gives OR NO pre-treatment window
# (launch 2019-10). The OJD PDFs end 2020-12. OR's clean-anchor baseline is
# 2019-04..2019-09 (OJD only) and its surviving outcome months are 2021-08/09/10
# (dashboard only), so both sources are required or OR cannot be a switcher.
#
# SEAM, MEASURED on the 12-month overlap (2020-01..2020-12): dashboard / OJD
# median **0.991** (range 0.978-1.000, 12/12 within 5%). The dashboard runs ~0.9%
# below OJD, consistent with it being circuit-court only. Because OR's baseline
# comes from OJD and its outcome from the dashboard, that 0.9% enters OR's dy
# directly as ~0.009 log points -- about 7% of the 0.127 MDE.
#
# RESCALE defaults to FALSE: raw source values are preserved and the seam is an
# order of magnitude below the MDE. Set RESCALE=TRUE to put OJD on the dashboard
# level using the measured overlap ratio (a standard splice adjustment, well
# identified on 12 months) if you would rather remove it than disclose it.
#
# KNOWN LIMITS (from data/raw/evicted_in_oregon/README.md):
#   - circuit court only; justice-court filings in 13 counties are absent
#   - statewide only (county x month exists for the latest 12 months only), so
#     n_counties / basket_share are NA, matching MD/NH/WI convention
#   - the dashboard is MUTABLE (publisher revised Apr 2026 after first capture)
#
# IDEMPOTENT: re-running replaces OR's rows rather than duplicating them.
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(lubridate); library(glue)})

PANEL  <- "data/raw/state_month_panel_with_treatment.csv"
OJD    <- "data/raw/monthly_expansion/or_raw/or_ojd_lt_state_month_2018_2020.csv"
DASH   <- "data/raw/evicted_in_oregon/oregon_statewide_monthly_2020_2026.tsv"
SRC    <- "or_ojd_plus_evictedinoregon_2026-09-14"
SPLICE <- as.Date("2020-01-01")     # dashboard takes over here
RESCALE <- FALSE

ojd <- read_csv(OJD, show_col_types = FALSE) %>%
  transmute(month_date = as.Date(month_date), filings_count = as.numeric(filings_count))
dash <- read_tsv(DASH, show_col_types = FALSE) %>%
  transmute(month_date = mdy(Month), filings_count = as.numeric(Total)) %>%
  filter(!is.na(month_date))

ov <- inner_join(ojd, dash, by = "month_date", suffix = c("_ojd", "_dash"))
ratio <- median(ov$filings_count_dash / ov$filings_count_ojd)
cat(glue("Overlap {nrow(ov)} months: dashboard/OJD median ratio {sprintf('%.4f', ratio)} ",
         "(= {sprintf('%+.4f', log(ratio))} log points at the seam)"), "\n")

or <- bind_rows(
  ojd  %>% filter(month_date < SPLICE) %>%
    mutate(filings_count = if (RESCALE) filings_count * ratio else filings_count),
  dash %>% filter(month_date >= SPLICE)
) %>% arrange(month_date) %>%
  mutate(state_abb = "OR",
         treat_start = as.Date("2019-10-01"),          # online_start_date
         treated = month_date >= treat_start,
         renter_occupied_housing_units = NA_real_,     # fill via the ACS script
         filings_per_1k_renters = NA_real_,
         panel_source = SRC, n_counties = NA_integer_, basket_share = NA_real_)

stopifnot(!anyDuplicated(or$month_date), all(or$filings_count >= 0))
gaps <- which(diff(interval(min(or$month_date), or$month_date) %/% months(1)) > 1)
cat(glue("OR series: {format(min(or$month_date),'%Y-%m')}..{format(max(or$month_date),'%Y-%m')}, ",
         "{nrow(or)} months, interior gaps: {length(gaps)}"), "\n")

p <- read_csv(PANEL, show_col_types = FALSE) %>% mutate(month_date = as.Date(month_date))
had <- sum(p$state_abb == "OR")
out <- bind_rows(p %>% filter(state_abb != "OR"), or %>% select(all_of(names(p)))) %>%
  arrange(state_abb, month_date)
stopifnot(!anyDuplicated(out %>% select(state_abb, month_date)), !anyNA(out$filings_count))
write_csv(out, PANEL)
cat(glue("Wrote {PANEL}: {nrow(out)} rows ({nrow(p)} before; OR had {had}), ",
         "{n_distinct(out$state_abb)} states\n"))
