# Panel artifact scan (L618): data-quality-only diagnostic for the
# switcher-vs-control long-difference design (baseline = launch-3..launch-1,
# outcome window = launch+6..launch+18, sample 2022-06 onward, used through
# 2025-09). NOT an estimation script: no treatment effects, no treated-vs-
# control outcome comparisons are computed. Read-only against data/.
#
# Run:
#   Rscript --vanilla analysis/diagnostics/panel_artifact_scan_l618.R

library(tidyverse)
library(lubridate)

theme_set(theme_minimal())

# ---- paths (all relative to project root) ----
panel_path   <- "data/raw/state_month_panel_with_treatment.csv"
sched_path   <- "data/raw/sports_gambling_legalization_dates.csv"
county_path  <- "data/raw/monthly_county_data_download.csv"
out_dir      <- "output/panel_artifact_scan_l618"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ---- design constants ----
SAMPLE_START <- as.Date("2022-06-01")
SAMPLE_END   <- as.Date("2025-09-01")
EXCLUDED_STATES <- c("NV", "HI", "MS")

SWITCHERS <- tribble(
  ~state_abb, ~launch,
  "KS", "2022-09-01",
  "MD", "2022-11-01",
  "OH", "2023-01-01",
  "MA", "2023-03-01",
  "KY", "2023-09-01",
  "ME", "2023-11-01",
  "FL", "2023-12-01",
  "DE", "2024-01-01",
  "VT", "2024-01-01",
  "NC", "2024-03-01"
) %>% mutate(launch = as.Date(launch))

# ==========================================================================
# LOAD
# ==========================================================================
panel <- read_csv(panel_path, show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date))

sched <- read_csv(sched_path, show_col_types = FALSE) %>%
  mutate(online_start_date = as.Date(online_start_date))

county <- read_csv(county_path, show_col_types = FALSE) %>%
  mutate(date = as.Date(date))

full_months <- seq(SAMPLE_START, SAMPLE_END, by = "month")
n_full_months <- length(full_months)

p <- panel %>%
  filter(!state_abb %in% EXCLUDED_STATES) %>%
  filter(month_date >= SAMPLE_START, month_date <= SAMPLE_END) %>%
  arrange(state_abb, month_date)

all_states <- sort(unique(panel$state_abb[!panel$state_abb %in% EXCLUDED_STATES]))

# state -> abb map for sched (sched$state is full name)
state_abb_lookup <- tibble(
  state = state.name, state_abb = state.abb
) %>%
  bind_rows(tibble(state = "District of Columbia", state_abb = "DC"))

sched_abb <- sched %>%
  left_join(state_abb_lookup, by = "state") %>%
  filter(!is.na(state_abb))

# ==========================================================================
# 1. MISSING STATE-MONTHS + which design cells they knock out
# ==========================================================================
grid <- expand_grid(state_abb = all_states, month_date = full_months)
present <- p %>% distinct(state_abb, month_date) %>% mutate(present = TRUE)

missing_months <- grid %>%
  left_join(present, by = c("state_abb", "month_date")) %>%
  mutate(present = replace_na(present, FALSE)) %>%
  filter(!present) %>%
  select(state_abb, month_date)

write_csv(missing_months, file.path(out_dir, "missing_state_months.csv"))

# For each switcher, determine baseline window (3 months) and outcome window
# (launch+6..launch+18), and which months are needed.
switcher_windows <- SWITCHERS %>%
  mutate(
    baseline_months = map(launch, ~ seq(.x %m-% months(3), .x %m-% months(1), by = "month")),
    outcome_months   = map(launch, ~ seq(.x %m+% months(6), .x %m+% months(18), by = "month"))
  )

# Function: is a given state-month present in p?
is_present <- function(st, dt) {
  any(p$state_abb == st & p$month_date == dt)
}

present_lookup <- present %>% mutate(key = paste(state_abb, month_date))
is_present_fast <- function(st, dt) paste(st, dt) %in% present_lookup$key

# ---- 1a. Switcher's own baseline/outcome completeness ----
switcher_self_check <- switcher_windows %>%
  mutate(
    baseline_present_n = map_int(baseline_months, ~ sum(map_lgl(.x, ~ is_present_fast(state_abb[1], .x)))),
    outcome_present_n  = map_int(outcome_months, ~ sum(map_lgl(.x, ~ is_present_fast(state_abb[1], .x))))
  )
# fix: state_abb[1] above is wrong inside rowwise map; redo with rowwise
switcher_self_check <- switcher_windows %>%
  rowwise() %>%
  mutate(
    baseline_present_n = sum(map_lgl(baseline_months, ~ is_present_fast(state_abb, .x))),
    outcome_present_n  = sum(map_lgl(outcome_months, ~ is_present_fast(state_abb, .x))),
    baseline_ok = baseline_present_n == 3,
    outcome_ok  = outcome_present_n >= 7,
    missing_baseline = paste(format(baseline_months[!map_lgl(baseline_months, ~is_present_fast(state_abb, .x))], "%Y-%m"), collapse = ";"),
    missing_outcome  = paste(format(outcome_months[!map_lgl(outcome_months, ~is_present_fast(state_abb, .x))], "%Y-%m"), collapse = ";")
  ) %>%
  ungroup() %>%
  select(state_abb, launch, baseline_present_n, baseline_ok, missing_baseline,
         outcome_present_n, outcome_ok, missing_outcome)

write_csv(switcher_self_check, file.path(out_dir, "switcher_self_completeness.csv"))

# ---- 1b. Control eligibility per switcher cohort ----
# A state is a control for a given switcher's cohort if:
#  - it has no online launch, OR its online launch is after that switcher's
#    outcome-window END month (never confounds the outcome window)
#  - it has the same 3 baseline months present AND the outcome-anchor month
#    (launch+12, the canonical single "outcome month") present.
# NOTE: per the prompt, "outcome window" is launch+6..launch+18 with >=7
# present; but eligibility also requires "the outcome month" present -- we
# interpret this as requiring enough of the outcome window (>=7) to be
# present for that candidate control's own would-be outcome timing is not
# applicable (controls don't have their own launch); operationally we check,
# for the control against the SWITCHER's baseline+outcome calendar months
# (shared calendar), whether the control has its 3 baseline months present
# and at least 7 of the outcome-window months present.
control_eligibility <- list()
for (i in seq_len(nrow(switcher_windows))) {
  sw <- switcher_windows[i, ]
  sw_abb <- sw$state_abb
  bmonths <- sw$baseline_months[[1]]
  omonths <- sw$outcome_months[[1]]

  candidates <- setdiff(all_states, sw_abb)
  for (cand in candidates) {
    cand_launch <- sched_abb$online_start_date[sched_abb$state_abb == cand]
    cand_launch <- if (length(cand_launch) == 0) as.Date(NA) else cand_launch[1]
    never_or_late <- is.na(cand_launch) || cand_launch > max(omonths)
    if (!never_or_late) next  # not eligible regardless of data completeness

    baseline_n <- sum(map_lgl(bmonths, ~ is_present_fast(cand, .x)))
    outcome_n  <- sum(map_lgl(omonths, ~ is_present_fast(cand, .x)))
    eligible_data <- (baseline_n == 3) && (outcome_n >= 7)

    control_eligibility[[length(control_eligibility) + 1]] <- tibble(
      switcher = sw_abb, launch = sw$launch, control_state = cand,
      cand_launch = cand_launch, never_or_late_ok = never_or_late,
      baseline_present_n = baseline_n, outcome_present_n = outcome_n,
      eligible = eligible_data
    )
  }
}
control_eligibility <- bind_rows(control_eligibility)
write_csv(control_eligibility, file.path(out_dir, "control_eligibility_by_switcher.csv"))

# Count how many switcher-cohort cells each missing state-month potentially
# knocks out: for a state-month that is missing, in how many (switcher,
# candidate-control) pairs would that month have been a required baseline or
# outcome month, restricted to pairs that pass the never_or_late_ok filter.
cells_knocked_out <- missing_months %>%
  rowwise() %>%
  mutate(
    n_cells_as_baseline_or_outcome = {
      st <- state_abb; dt <- month_date
      # As a switcher's OWN month (kills that switcher's whole self-check)
      is_switcher_month <- st %in% SWITCHERS$state_abb &&
        (dt %in% switcher_windows$baseline_months[[which(switcher_windows$state_abb == st)]] ||
         dt %in% switcher_windows$outcome_months[[which(switcher_windows$state_abb == st)]])
      # As a candidate control's month for any switcher cohort where dt falls
      # in that switcher's baseline or outcome window and control passes the
      # never_or_late_ok filter
      n_control_hits <- 0L
      for (j in seq_len(nrow(switcher_windows))) {
        if (switcher_windows$state_abb[j] == st) next
        bset <- switcher_windows$baseline_months[[j]]
        oset <- switcher_windows$outcome_months[[j]]
        if (!(dt %in% bset || dt %in% oset)) next
        cand_launch <- sched_abb$online_start_date[sched_abb$state_abb == st]
        cand_launch <- if (length(cand_launch) == 0) as.Date(NA) else cand_launch[1]
        never_or_late <- is.na(cand_launch) || cand_launch > max(oset)
        if (never_or_late) n_control_hits <- n_control_hits + 1L
      }
      n_control_hits + as.integer(is_switcher_month)
    }
  ) %>%
  ungroup() %>%
  filter(n_cells_as_baseline_or_outcome > 0) %>%
  arrange(desc(n_cells_as_baseline_or_outcome))

write_csv(cells_knocked_out, file.path(out_dir, "missing_months_design_impact.csv"))

# ==========================================================================
# 2. LEVEL SHIFTS / SPIKES / SPLICE SEAMS within state series
# ==========================================================================
level_checks <- p %>%
  arrange(state_abb, month_date) %>%
  group_by(state_abb) %>%
  mutate(
    log_f = log1p(filings_count),
    d_log = log_f - lag(log_f),
    d_n_counties = n_counties - lag(n_counties),
    d_basket_share = basket_share - lag(basket_share),
    source_change = panel_source != lag(panel_source)
  ) %>%
  ungroup()

# Flag big month-over-month log jumps (|d_log| > 0.5, i.e. filings roughly
# halve or double) -- potential spikes/collapses/partial months.
big_jumps <- level_checks %>%
  filter(!is.na(d_log), abs(d_log) > 0.5) %>%
  select(state_abb, month_date, filings_count, d_log, n_counties, d_n_counties,
         basket_share, d_basket_share, panel_source, source_change) %>%
  arrange(desc(abs(d_log)))

write_csv(big_jumps, file.path(out_dir, "big_month_over_month_jumps.csv"))

# Flag basket composition changes (n_counties or basket_share shift) not
# accompanied by a panel_source label change -- silent basket changes.
basket_shifts <- level_checks %>%
  filter(!is.na(d_n_counties), (d_n_counties != 0 | (!is.na(d_basket_share) & abs(d_basket_share) > 0.05))) %>%
  select(state_abb, month_date, n_counties, d_n_counties, basket_share, d_basket_share,
         panel_source, source_change, filings_count, d_log) %>%
  arrange(state_abb, month_date)

write_csv(basket_shifts, file.path(out_dir, "basket_composition_shifts.csv"))

# Splice seams: rows right around a panel_source change within a state.
splice_seams <- level_checks %>%
  filter(source_change) %>%
  select(state_abb, month_date, panel_source, d_log, filings_count, n_counties, basket_share)

write_csv(splice_seams, file.path(out_dir, "splice_seams.csv"))

# Partial final months: last observed month_date per state vs SAMPLE_END,
# and whether lsc_pct_of_hist_avg / lsc_pct_coverage looks depressed in the
# final observed month (a proxy for a partial-month cutoff).
final_month_check <- p %>%
  group_by(state_abb) %>%
  filter(month_date == max(month_date)) %>%
  ungroup() %>%
  select(state_abb, month_date, filings_count, lsc_pct_of_hist_avg, lsc_pct_coverage,
         n_counties, basket_share) %>%
  arrange(month_date)

write_csv(final_month_check, file.path(out_dir, "final_observed_month_by_state.csv"))

# ==========================================================================
# 3. VOLATILITY OF CONTROL-STATE SERIES (controls only, no treated-vs-control
#    outcome comparison -- purely descriptive dispersion of month-to-month
#    log changes and of each control's baseline->outcome long difference
#    computed against ITS OWN mean, not against any switcher)
# ==========================================================================
# Identify the ever-eligible control set (union across all switcher cohorts)
ever_control <- control_eligibility %>%
  filter(eligible) %>%
  distinct(control_state) %>%
  pull(control_state)

mom_vol <- level_checks %>%
  filter(state_abb %in% ever_control) %>%
  group_by(state_abb) %>%
  summarise(
    n_months = n(),
    mean_filings = mean(filings_count, na.rm = TRUE),
    median_n_counties = median(n_counties, na.rm = TRUE),
    sd_d_log = sd(d_log, na.rm = TRUE),
    mean_abs_d_log = mean(abs(d_log), na.rm = TRUE),
    max_abs_d_log = max(abs(d_log), na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(sd_d_log))

write_csv(mom_vol, file.path(out_dir, "control_state_mom_volatility.csv"))

# Long-difference volatility: for each control state and each switcher cohort
# for which it is eligible, compute (mean log outcome window) - (mean log
# baseline window), i.e. the same functional form the design uses, but this
# is NOT a treatment effect since these are controls compared to themselves
# over calendar time -- purely a noise/dispersion diagnostic.
long_diff_rows <- list()
for (i in seq_len(nrow(switcher_windows))) {
  sw <- switcher_windows[i, ]
  bmonths <- sw$baseline_months[[1]]
  omonths <- sw$outcome_months[[1]]
  elig_controls <- control_eligibility %>%
    filter(switcher == sw$state_abb, eligible) %>%
    pull(control_state)
  for (cand in elig_controls) {
    base_vals <- p %>% filter(state_abb == cand, month_date %in% bmonths) %>% pull(filings_count)
    out_vals  <- p %>% filter(state_abb == cand, month_date %in% omonths) %>% pull(filings_count)
    if (length(base_vals) == 0 || length(out_vals) == 0) next
    ld <- mean(log1p(out_vals)) - mean(log1p(base_vals))
    long_diff_rows[[length(long_diff_rows) + 1]] <- tibble(
      switcher_cohort = sw$state_abb, control_state = cand, long_diff_log = ld
    )
  }
}
long_diff_df <- bind_rows(long_diff_rows)

long_diff_vol <- long_diff_df %>%
  group_by(control_state) %>%
  summarise(
    n_cohorts = n(),
    mean_long_diff = mean(long_diff_log),
    sd_long_diff = sd(long_diff_log),
    max_abs_long_diff = max(abs(long_diff_log)),
    .groups = "drop"
  ) %>%
  arrange(desc(sd_long_diff))

write_csv(long_diff_vol, file.path(out_dir, "control_long_diff_volatility.csv"))
write_csv(long_diff_df, file.path(out_dir, "control_long_diff_by_cohort.csv"))

# ==========================================================================
# 4. COUNTY-LEVEL ANOMALIES WITHIN LSC BASKETS (Pinellas-style)
# ==========================================================================
# Map fips -> state via first two digits (state FIPS code). Build a lookup.
state_fips <- tibble::tribble(
  ~fips2, ~state_abb,
  "01","AL","02","AK","04","AZ","05","AR","06","CA","08","CO","09","CT",
  "10","DE","11","DC","12","FL","13","GA","15","HI","16","ID","17","IL",
  "18","IN","19","IA","20","KS","21","KY","22","LA","23","ME","24","MD",
  "25","MA","26","MI","27","MN","28","MS","29","MO","30","MT","31","NE",
  "32","NV","33","NH","34","NJ","35","NM","36","NY","37","NC","38","ND",
  "39","OH","40","OK","41","OR","42","PA","44","RI","45","SC","46","SD",
  "47","TN","48","TX","49","UT","50","VT","51","VA","53","WA","54","WV",
  "55","WI","56","WY"
)

county_anom <- county %>%
  mutate(fips2 = str_sub(sprintf("%05s", fips), 1, 2) %>% str_replace_all(" ", "0")) %>%
  left_join(state_fips, by = "fips2") %>%
  filter(date >= SAMPLE_START, date <= SAMPLE_END) %>%
  filter(!is.na(percent_of_historical_average)) %>%
  filter(percent_of_historical_average < 40 | percent_of_historical_average > 250) %>%
  # keep only anomalies in state-months that are actually present in the
  # state-month panel (i.e., the anomaly is "hiding" inside a kept month)
  inner_join(present %>% rename(date = month_date), by = c("state_abb", "date")) %>%
  select(state_abb, fips, name, date, filings_count, percent_of_historical_average) %>%
  arrange(desc(abs(percent_of_historical_average - 100)))

write_csv(county_anom, file.path(out_dir, "county_level_anomalies_in_kept_months.csv"))

# Also flag which of these county anomalies fall inside a switcher's own
# baseline/outcome window, or inside an eligible control's baseline/outcome
# window for some cohort (i.e., actually design-relevant, not just anywhere
# in the sample).
design_relevant_months <- bind_rows(
  switcher_windows %>% select(state_abb, dt = baseline_months) %>% unnest(dt),
  switcher_windows %>% select(state_abb, dt = outcome_months) %>% unnest(dt)
) %>% distinct()

# For controls, the relevant months are the union of baseline+outcome months
# of cohorts for which they are eligible (calendar months, but tagged to the
# control's own state).
control_relevant_months <- control_eligibility %>%
  filter(eligible) %>%
  rowwise() %>%
  mutate(
    bmonths = list(switcher_windows$baseline_months[[which(switcher_windows$state_abb == switcher)]]),
    omonths = list(switcher_windows$outcome_months[[which(switcher_windows$state_abb == switcher)]])
  ) %>%
  ungroup() %>%
  select(control_state, bmonths, omonths) %>%
  pivot_longer(c(bmonths, omonths), values_to = "dt") %>%
  unnest(dt) %>%
  distinct(state_abb = control_state, dt)

all_design_relevant <- bind_rows(design_relevant_months, control_relevant_months) %>% distinct()

county_anom_design_relevant <- county_anom %>%
  inner_join(all_design_relevant, by = c("state_abb", "date" = "dt")) %>%
  arrange(desc(abs(percent_of_historical_average - 100)))

write_csv(county_anom_design_relevant, file.path(out_dir, "county_anomalies_design_relevant.csv"))

# Impact-weight the design-relevant county anomalies: express the county's
# actual-minus-expected filings as a share of that state-month's total
# filings, so a Pinellas-in-FL-style event (small % swing but a big county)
# ranks above a 1-of-6-filings noise county with an extreme percent.
state_month_totals <- p %>% select(state_abb, month_date, state_total = filings_count)

county_anom_impact <- county_anom_design_relevant %>%
  mutate(
    expected_count = filings_count / (percent_of_historical_average / 100)
  ) %>%
  left_join(state_month_totals, by = c("state_abb", "date" = "month_date")) %>%
  mutate(
    shortfall = expected_count - filings_count,
    pct_of_state_total = 100 * abs(shortfall) / state_total
  ) %>%
  arrange(desc(pct_of_state_total))

write_csv(county_anom_impact, file.path(out_dir, "county_anomalies_impact_weighted.csv"))

# ==========================================================================
# DONE
# ==========================================================================
cat("Panel artifact scan complete. Outputs written to:", out_dir, "\n")
cat("Files:\n")
print(list.files(out_dir))
