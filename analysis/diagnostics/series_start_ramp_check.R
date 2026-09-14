# =============================================================================
# series_start_ramp_check.R  (2026-09-14)
#
# Detects SERIES-START RAMPS: the first months of a state's series reporting
# far below its eventual level, i.e. incomplete coverage at ingest rather than
# a real drop in evictions.
#
# Found in CT, where 2016-01/02 report 186/207 against a 1,152 median and then
# jump to ~1,100 and stay -- which also inflates CT's measured pre-COVID
# volatility (pre_sigma 0.315 vs Ohio's 0.045).
#
# METHOD. Seasonality would produce false positives against a flat level, so
# each early month is compared to the SAME CALENDAR MONTH in the following
# three years (its own seasonal norm). A ramp = consecutive leading months
# running far below their own seasonal norm. COVID months are excluded from
# the comparison so a 2020-start series is not flagged for the pandemic.
#
# Descriptive: blindness-safe.
# Output: output/series_start_ramp/series_start_ramp.csv
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(lubridate); library(glue)})
CS <- as.Date("2020-03-01"); CE <- as.Date("2021-07-31")
THRESH <- 0.60          # a leading month below 60% of its own seasonal norm is suspect
OUT <- "output/series_start_ramp"; dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

pan <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date))

chk <- function(s) {
  d <- pan %>% filter(state_abb == s) %>% arrange(month_date)
  if (nrow(d) < 36) return(NULL)
  start <- min(d$month_date)
  # seasonal norm: same calendar month, within 3 years of start, excluding the
  # first 12 months themselves and the COVID window
  ref <- d %>% filter(month_date >= start %m+% months(12),
                      month_date <= start %m+% months(48),
                      month_date < CS | month_date > CE) %>%
    group_by(m = month(month_date)) %>%
    summarise(norm = mean(filings_count), n_ref = n(), .groups = "drop") %>%
    filter(n_ref >= 2)
  lead12 <- d %>% slice_head(n = 12) %>% mutate(m = month(month_date)) %>%
    inner_join(ref, by = "m") %>%
    mutate(ratio = filings_count / norm, idx = row_number())
  if (!nrow(lead12)) return(NULL)
  # ramp length = how many CONSECUTIVE leading months are below threshold
  below <- lead12$ratio < THRESH
  runlen <- if (!below[1]) 0L else which(c(!below, TRUE))[1] - 1L
  tibble(state_abb = s, series_start = start, ramp_months = runlen,
         first_ratio = lead12$ratio[1],
         worst_ratio = if (runlen > 0) min(lead12$ratio[seq_len(runlen)]) else NA_real_,
         ratios_1to4 = paste(sprintf("%.2f", head(lead12$ratio, 4)), collapse = " "))
}

res <- map_dfr(sort(unique(pan$state_abb)), chk) %>% arrange(desc(ramp_months), first_ratio)
write_csv(res, file.path(OUT, "series_start_ramp.csv"))

flagged <- res %>% filter(ramp_months > 0)
cat(glue("Series-start ramp check: {nrow(res)} states assessed, {nrow(flagged)} flagged ",
         "(leading months below {THRESH*100}% of their own seasonal norm)"), "\n\n")
if (nrow(flagged)) {
  cat(sprintf("%-6s %-13s %7s %8s %8s  %s\n", "state", "starts", "ramp", "1st", "worst", "first 4 ratios"))
  pwalk(flagged, function(state_abb, series_start, ramp_months, first_ratio, worst_ratio, ratios_1to4)
    cat(sprintf("%-6s %-13s %7d %8.2f %8.2f  %s\n", state_abb, format(series_start, "%Y-%m"),
                ramp_months, first_ratio, worst_ratio, ratios_1to4)))
} else cat("  none\n")
cat("\nClean states (first month at/above its seasonal norm), for contrast:\n")
res %>% filter(ramp_months == 0) %>% slice_max(first_ratio, n = 5) %>%
  pwalk(function(state_abb, series_start, first_ratio, ...)
    cat(sprintf("  %-4s starts %s  first month = %.2f of norm\n", state_abb,
                format(series_start, "%Y-%m"), first_ratio)))
