# =============================================================================
# single_series_currency_audit.R  (2026-09-14)
#
# Currency + integrity audit of the Eviction Lab single-series states
# (panel_source == "ets_single_series_no_denominator": LA MA MO NM NV RI per
# docs/DATA_PROVENANCE.md:116), benchmarked against every other source group.
#
# Trigger: MO was found to end 2023-01 -- 35 months before its 2025-12 online
# legalization -- AND to carry a 37-month interior hole (2016-12 -> 2020-01)
# that is not the COVID drop. If that is a property of the single-series group
# rather than of MO alone, it affects control-pool composition everywhere.
#
# Reports per state: span, staleness, interior gaps, denominator presence, and
# the role the state can actually play under the clean-anchor rule.
# Descriptive only, no estimation: blindness-safe.
#
# Output: output/single_series_audit/
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(lubridate); library(glue)})

CS <- as.Date("2020-03-01"); CE <- as.Date("2021-07-31")
TODAY <- as.Date("2026-09-01")
PRE <- 6; PLO <- 12; PHI <- 24
EXCL <- c("NV","ID","HI","MS")
OUT <- "output/single_series_audit"; dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

pan <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date))

ab <- c(Delaware="DE",`New Jersey`="NJ",`West Virginia`="WV",Pennsylvania="PA",`Rhode Island`="RI",
  Arkansas="AR",`New York`="NY",Iowa="IA",Indiana="IN",Oregon="OR",`New Hampshire`="NH",Illinois="IL",
  Michigan="MI",Colorado="CO",`District of Columbia`="DC",Tennessee="TN",Virginia="VA",
  `North Carolina`="NC",Arizona="AZ",Wyoming="WY",Connecticut="CT",Louisiana="LA",Maryland="MD",
  Kansas="KS",Massachusetts="MA",Ohio="OH",Kentucky="KY",Maine="ME",Florida="FL",Vermont="VT",
  Missouri="MO",Mississippi="MS",Montana="MT",`North Dakota`="ND",`New Mexico`="NM",
  `South Dakota`="SD",Washington="WA",Wisconsin="WI")
sched <- read_csv("data/raw/sports_gambling_legalization_dates.csv", show_col_types = FALSE) %>%
  mutate(st = ab[state], online = as.Date(online_start_date))
online <- setNames(sched$online, sched$st)

# Interior gaps that are NOT the COVID drop
gap_tbl <- pan %>% arrange(state_abb, month_date) %>%
  group_by(state_abb) %>%
  mutate(nxt = lead(month_date),
         gap = interval(month_date, nxt) %/% months(1)) %>%
  filter(!is.na(gap), gap > 1) %>%
  # a gap fully inside the COVID window is the expected drop, not a defect
  filter(!(month_date >= CS %m-% months(1) & nxt <= CE %m+% months(1))) %>%
  summarise(n_gaps = n(), max_gap_months = max(gap) - 1L,
            gap_detail = paste(glue("{format(month_date,'%Y-%m')}->{format(nxt,'%Y-%m')}"),
                               collapse = "; "),
            .groups = "drop")

aud <- pan %>% group_by(state_abb) %>%
  summarise(source   = paste(sort(unique(panel_source)), collapse = "|"),
            n_months = n(), span_lo = min(month_date), span_hi = max(month_date),
            has_denom = any(!is.na(renter_occupied_housing_units) &
                              renter_occupied_housing_units > 0),
            n_counties = paste(sort(unique(na.omit(n_counties))), collapse = ","),
            .groups = "drop") %>%
  left_join(gap_tbl, by = "state_abb") %>%
  mutate(n_gaps = replace_na(n_gaps, 0L), max_gap_months = replace_na(max_gap_months, 0L),
         gap_detail = replace_na(gap_detail, ""),
         stale_months = interval(span_hi, TODAY) %/% months(1),
         single_series = source == "ets_single_series_no_denominator",
         online = online[state_abb])

# Role under the clean-anchor rule
obs <- pan %>% filter(month_date < CS | month_date > CE) %>% distinct(state_abb, month_date)
obs_set <- split(obs$month_date, obs$state_abb)
aud <- aud %>% rowwise() %>%
  mutate(
    n_base = if (is.na(online)) NA_integer_ else
      sum(seq(online %m-% months(PRE), by = "month", length.out = PRE) %in% obs_set[[state_abb]]),
    n_out  = if (is.na(online)) NA_integer_ else
      sum(seq(online %m+% months(PLO), online %m+% months(PHI), by = "month") %in% obs_set[[state_abb]])
  ) %>% ungroup() %>%
  mutate(role = case_when(
    state_abb %in% EXCL                    ~ "EXCLUDED",
    is.na(online)                          ~ "control (never-legal)",
    n_base == PRE & n_out == 13            ~ "switcher (full)",
    n_base == PRE & n_out > 0              ~ glue("switcher (partial {n_out}/13)"),
    TRUE                                   ~ "not a switcher"
  ))

ss <- aud %>% filter(single_series) %>% arrange(span_hi)
cat("=== SINGLE-SERIES STATES (Eviction Lab, no renter denominator) ===\n")
print(as.data.frame(ss %>% select(state_abb, span_lo, span_hi, n_months, stale_months,
                                  n_gaps, max_gap_months, has_denom, online, role)),
      row.names = FALSE)
cat("\ninterior gaps (non-COVID):\n")
for (i in seq_len(nrow(ss))) if (nzchar(ss$gap_detail[i]))
  cat(glue("  {ss$state_abb[i]}: {ss$gap_detail[i]}"), "\n")

cat("\n=== BENCHMARK: staleness by source group ===\n")
print(as.data.frame(aud %>% group_by(single_series, source) %>%
  summarise(n_states = n(), median_span_hi = median(span_hi),
            median_stale = median(stale_months), median_months = median(n_months),
            states_with_gaps = sum(n_gaps > 0), .groups = "drop") %>%
  arrange(desc(single_series), desc(median_stale))), row.names = FALSE)

cat("\n=== ALL STATES, most stale first (top 10) ===\n")
print(as.data.frame(aud %>% arrange(desc(stale_months)) %>%
  select(state_abb, source, span_hi, stale_months, n_gaps, role) %>% head(10)),
  row.names = FALSE)

write_csv(aud %>% select(-gap_detail), file.path(OUT, "currency_audit.csv"))
write_csv(aud %>% filter(nzchar(gap_detail)) %>% select(state_abb, source, gap_detail),
          file.path(OUT, "interior_gaps.csv"))
message("Wrote ", OUT)
