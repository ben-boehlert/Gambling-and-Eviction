# =============================================================================
# censor_series_start_ramps.R  (2026-09-14)
#
# Censors SERIES-START RAMP months: leading months that report far below their
# own seasonal norm because coverage was incomplete at ingest, not because
# evictions actually fell.
#
# Identified by analysis/diagnostics/series_start_ramp_check.R (each leading
# month compared to the same calendar month in the following 3 years, COVID
# excluded so seasonality and the pandemic cannot false-positive):
#
#   CT 2016-01 = 0.15 of norm, 2016-02 = 0.19, then straight to 1.05 / 1.06
#   NH 2018-12 = 0.20 of norm, then 1.18 / 1.14 / 1.18
#
# WI 2019-01 (0.56, then 0.87) is NOT censored -- marginal, and plausibly real.
#
# WHY REMOVE RATHER THAN NA: these are LEADING months, so dropping them simply
# starts the series later (CT 2016-03, NH 2019-01). That keeps the panel free
# of NA filings, which the pre-flight audit asserts. An NA would instead create
# an interior hole the gap logic would have to reason about.
#
# IMPACT (verified below, and before the edit): neither month falls in any
# switcher's baseline or outcome window, nor supplies control mass in any live
# outcome month. The switcher set is unchanged. The value is elsewhere -- CT's
# two months inflate its measured pre-COVID volatility (pre_sigma 0.315 vs
# Ohio's 0.045), distorting any volatility-based diagnostic, and both would
# contaminate a 2016-anchored pre-period.
#
# Folded into the existing 2026-09-14 vintage boundary; it does not create a
# new one. IDEMPOTENT: re-running is a no-op.
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(glue)})
PANEL <- "data/raw/state_month_panel_with_treatment.csv"
DEPR  <- "data/raw/deprecated/state_month_panel_with_treatment_pre_ramp_censor_2026-09-14.csv"
CENSOR <- tribble(~state_abb, ~month_date,
                  "CT", as.Date("2016-01-01"),
                  "CT", as.Date("2016-02-01"),
                  "NH", as.Date("2018-12-01"))

p <- read_csv(PANEL, show_col_types = FALSE) %>% mutate(month_date = as.Date(month_date))
hit <- p %>% semi_join(CENSOR, by = c("state_abb", "month_date"))
if (!nrow(hit)) { message("No ramp months present - already censored. No-op."); quit(save = "no") }

dir.create(dirname(DEPR), recursive = TRUE, showWarnings = FALSE)
if (!file.exists(DEPR)) { write_csv(p, DEPR); message("Preserved pre-censor vintage -> ", DEPR) }

cat("Censoring:\n"); print(as.data.frame(hit %>% select(state_abb, month_date, filings_count)),
                           row.names = FALSE)

out <- p %>% anti_join(CENSOR, by = c("state_abb", "month_date")) %>% arrange(state_abb, month_date)
stopifnot(nrow(out) == nrow(p) - nrow(hit),
          !anyDuplicated(out %>% select(state_abb, month_date)),
          !anyNA(out$filings_count))

# leading-months-only assertion: censoring must not open an interior hole
for (s in unique(CENSOR$state_abb)) {
  before <- p %>% filter(state_abb == s) %>% pull(month_date)
  after  <- out %>% filter(state_abb == s) %>% pull(month_date)
  cens   <- CENSOR %>% filter(state_abb == s) %>% pull(month_date)
  stopifnot(all(cens < min(after)))   # every censored month precedes the new start
  cat(glue("  {s}: series start {format(min(before),'%Y-%m')} -> {format(min(after),'%Y-%m')} ",
           "({length(before)} -> {length(after)} months)"), "\n")
}

write_csv(out, PANEL)
cat(glue("\nWrote {PANEL}: {nrow(out)} rows ({nrow(p)} before), ",
         "{n_distinct(out$state_abb)} states\n"))
