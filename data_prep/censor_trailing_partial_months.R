# =============================================================================
# censor_trailing_partial_months.R  (2026-09-14)
#
# Censors TRAILING PARTIAL MONTHS: the final month of a series that reports far
# below its own recent level because the extract was cut mid-month, not because
# filings collapsed. The mirror image of censor_series_start_ramps.R, which
# handles the same artifact at the START of a series.
#
# FOUND WHILE ADDING WA (2026-09-14). The Eviction Lab internal extract
# `ets_county_month.csv` cuts each site at its own collection date, and the
# 2026-09-14 single-series rebuild carried those cut months straight into the
# panel. Measured as the final month over the median of the preceding six:
#
#   LA 2026-03   119 vs  390   0.31
#   MA 2026-06   346 vs  651   0.53
#   MO 2026-06   399 vs 1588   0.25
#   NM 2026-06   166 vs 1006   0.17
#   WA 2026-06   125 vs  328   0.38   (dropped upstream by add_wa_to_state_panel.R)
#
# NV (1.11) and RI (0.90) end a month earlier and are CLEAN -- they are not
# touched. No non-extract state is affected: the LSC CCDI county download and
# the court sources (MD NH WI) publish whole months.
#
# WHY REMOVE RATHER THAN NA: these are TRAILING months, so dropping them simply
# ends the series a month earlier. That keeps the panel free of NA filings,
# which the pre-flight audit asserts, and avoids a spurious level break in the
# last observation of five states -- a break that would otherwise contaminate
# any end-of-sample event-time cell and any "months stale" reading.
#
# Folded into the 2026-09-14 vintage boundary alongside the WA and MI additions;
# it does not create a separate one. IDEMPOTENT: re-running is a no-op.
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(lubridate); library(glue)})

PANEL <- "data/raw/state_month_panel_with_treatment.csv"
DEPR  <- "data/raw/deprecated/state_month_panel_with_treatment_pre_wa_mi_2026-09-14.csv"

CENSOR <- tribble(~state_abb, ~month_date,
                  "LA", as.Date("2026-03-01"),
                  "MA", as.Date("2026-06-01"),
                  "MO", as.Date("2026-06-01"),
                  "NM", as.Date("2026-06-01"),
                  "WA", as.Date("2026-06-01"))

p <- read_csv(PANEL, show_col_types = FALSE) %>% mutate(month_date = as.Date(month_date))

# Each censored month must actually BE the state's last, and must actually look
# partial. Guards against censoring a real month if the panel is ever rebuilt
# from a fresher extract that carries complete data for these dates.
check <- p %>%
  semi_join(CENSOR, by = c("state_abb", "month_date")) %>%
  left_join(p %>% group_by(state_abb) %>% summarise(last_month = max(month_date),
                                                    .groups = "drop"),
            by = "state_abb") %>%
  rowwise() %>%
  mutate(prior6_median = median(p$filings_count[p$state_abb == state_abb &
                                                p$month_date <  month_date &
                                                p$month_date >= month_date %m-% months(6)]),
         ratio = round(filings_count / prior6_median, 2),
         is_last = month_date == last_month) %>%
  ungroup()

if (!nrow(check)) { message("No trailing partial months present - already censored. No-op."); quit(save = "no") }

cat("Censoring:\n")
print(as.data.frame(check %>% select(state_abb, month_date, filings_count,
                                     prior6_median, ratio, is_last)), row.names = FALSE)
stopifnot(all(check$is_last), all(check$ratio < 0.75))

dir.create(dirname(DEPR), recursive = TRUE, showWarnings = FALSE)
if (!file.exists(DEPR)) { write_csv(p, DEPR); message("Preserved pre-censor vintage -> ", DEPR) }

out <- p %>% anti_join(CENSOR, by = c("state_abb", "month_date")) %>%
  arrange(state_abb, month_date)
stopifnot(nrow(out) == nrow(p) - nrow(check),
          !anyDuplicated(out %>% select(state_abb, month_date)),
          !anyNA(out$filings_count))
write_csv(out, PANEL)
cat(glue("Wrote {PANEL}: {nrow(out)} rows ({nrow(p)} before, {nrow(check)} censored), ",
         "{n_distinct(out$state_abb)} states\n"))
