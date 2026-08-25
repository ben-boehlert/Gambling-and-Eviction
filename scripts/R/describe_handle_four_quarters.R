# ==============================================================================
# describe_handle_four_quarters.R
# Descriptive sports-betting Handle four quarters after online launch
# Paper: Gambling and Eviction, market ramp-up measurement component
# Inputs: data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv
#         data/raw/sports_gambling_legalization_dates.csv
#         data/raw/state_month_panel_with_treatment.csv
# Outputs: output/handle_four_quarters/*
# ==============================================================================

# 0. Setup ---------------------------------------------------------------------

library(data.table)
library(here)

SEED <- 20260814L
PRE_2025_END <- as.IDate("2025-01-01")
COVID_EXCLUSION_START <- as.IDate("2020-03-01")
COVID_EXCLUSION_END <- as.IDate("2021-07-01")
POST_COVID_PANEL_START <- as.IDate("2022-04-01")
POST_COVID_PANEL_END <- as.IDate("2024-12-01")
EXPECTED_MONTHS_PER_WINDOW <- 3L
EXPECTED_POST_COVID_MONTHS <- 33L

set.seed(SEED)

OUTPUT_DIR <- here("output", "handle_four_quarters")
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

# ==============================================================================
# Paper-to-Code Naming Map
# ==============================================================================
# Paper Notation       | Code Name                  | Description
# H_it                 | handle                     | Reported total Handle
# G_i                  | online_launch_month        | Operational online launch
# e_it                 | event_month                | Months since launch
# H_i^(peak,<2025)     | pre_2025_peak_handle       | Fixed pre-2025 state peak
# R_iw                 | handle_pct_pre_2025_peak   | Window average / peak
# Q_i^(full)           | first_full_quarter_start   | First full quarter
# ==============================================================================

# Convert a zero-based integer month index back to the first day of the month.
month_id_to_date <- function(month_id) {
  stopifnot(is.numeric(month_id))
  year <- month_id %/% 12L
  month <- month_id %% 12L + 1L
  as.IDate(sprintf("%04d-%02d-01", year, month))
}

# 1. Data loading and validation -----------------------------------------------

handle_path <- here(
  "data",
  "raw",
  "lsr_sports_betting_handle_revenue_by_state_month.csv"
)
schedule_path <- here(
  "data",
  "raw",
  "sports_gambling_legalization_dates.csv"
)
eviction_panel_path <- here(
  "data",
  "raw",
  "state_month_panel_with_treatment.csv"
)

if (!file.exists(handle_path)) {
  stop(sprintf("Handle data not found: %s", handle_path))
}
if (!file.exists(schedule_path)) {
  stop(sprintf("Legalization schedule not found: %s", schedule_path))
}
if (!file.exists(eviction_panel_path)) {
  stop(sprintf("Eviction panel not found: %s", eviction_panel_path))
}

handle_raw <- fread(handle_path)
schedule_raw <- fread(schedule_path)
eviction_panel_raw <- fread(eviction_panel_path)

required_handle <- c("State", "month_date", "Handle")
required_schedule <- c(
  "state",
  "online_start_date",
  "retail_start_date",
  "has_online"
)
stopifnot(all(required_handle %chin% names(handle_raw)))
stopifnot(all(required_schedule %chin% names(schedule_raw)))
stopifnot(all(
  c("state_abb", "month_date", "filings_count") %chin%
    names(eviction_panel_raw)
))

handle_data <- handle_raw[, .(
  state = State,
  month_date = as.IDate(month_date),
  handle = as.numeric(Handle)
)]
schedule <- schedule_raw[, .(
  state,
  online_launch_month = as.IDate(online_start_date),
  retail_launch_month = as.IDate(retail_start_date),
  has_online = as.logical(has_online)
)]

if (handle_data[, anyDuplicated(paste(state, month_date))] > 0L) {
  stop("Handle data contain duplicate state-month rows.")
}
if (handle_data[, any(is.na(state) | is.na(month_date))]) {
  stop("Handle data contain missing state names or month dates.")
}
if (handle_data[, any(!is.na(handle) & (!is.finite(handle) | handle < 0))]) {
  stop("Handle values must be finite and nonnegative when observed.")
}

# The source schedule records operational online start only to the month. The
# analysis treats that recorded month as event month zero; it does not use the
# legislative enactment date or the earlier retail launch date.
online_states <- schedule[
  has_online & !is.na(online_launch_month)
]
if (online_states[, anyDuplicated(state)] > 0L) {
  stop("Online legalization schedule contains duplicate states.")
}

online_states[, `:=`(
  launch_month_id = as.integer(format(online_launch_month, "%Y")) * 12L +
    as.integer(format(online_launch_month, "%m")) - 1L,
  launch_quarter_start_month =
    ((as.integer(format(online_launch_month, "%m")) - 1L) %/% 3L) * 3L + 1L
)]
online_states[, launch_quarter_start_id :=
  as.integer(format(online_launch_month, "%Y")) * 12L +
    launch_quarter_start_month - 1L]
online_states[, `:=`(
  first_full_quarter_start_id = launch_quarter_start_id + 3L,
  fourth_full_quarter_start_id = launch_quarter_start_id + 12L,
  retail_transition = fifelse(
    is.na(retail_launch_month),
    "online_only",
    fifelse(
      retail_launch_month < online_launch_month,
      "retail_before_online",
      fifelse(
        retail_launch_month > online_launch_month,
        "retail_after_online",
        "online_and_retail_same_month"
      )
    )
  )
)]
online_states[, launch_quarter_start_month := NULL]

# Reconstruct the exact 30-state post-COVID panel used in the support memo:
# all 33 state-month filing-count observations from April 2022 through December
# 2024. The launch cohort is the subset becoming operationally online in-window.
state_crosswalk <- data.table(
  state = c(state.name, "District of Columbia"),
  state_abb = c(state.abb, "DC")
)
eviction_panel <- eviction_panel_raw[, .(
  state_abb,
  month_date = as.IDate(month_date),
  filings_count = as.numeric(filings_count)
)]
post_covid_panel_states <- eviction_panel[
  month_date >= POST_COVID_PANEL_START &
    month_date <= POST_COVID_PANEL_END,
  .(
    n_months = uniqueN(month_date),
    n_observed_filings = sum(!is.na(filings_count))
  ),
  by = state_abb
][
  n_months == EXPECTED_POST_COVID_MONTHS &
    n_observed_filings == EXPECTED_POST_COVID_MONTHS
]
post_covid_panel_states <- merge(
  post_covid_panel_states,
  state_crosswalk,
  by = "state_abb",
  all.x = TRUE
)
if (nrow(post_covid_panel_states) != 30L) {
  stop(sprintf(
    "Expected 30 balanced post-COVID panel states; found %d.",
    nrow(post_covid_panel_states)
  ))
}
if (post_covid_panel_states[, any(is.na(state))]) {
  stop("State-name crosswalk failed for the post-COVID panel.")
}

post_covid_launch_cohort <- online_states[
  state %chin% post_covid_panel_states[, state] &
    online_launch_month >= POST_COVID_PANEL_START &
    online_launch_month <= POST_COVID_PANEL_END
]
if (nrow(post_covid_launch_cohort) != 8L) {
  stop(sprintf(
    "Expected 8 post-COVID legal online launches in the panel; found %d.",
    nrow(post_covid_launch_cohort)
  ))
}

handle_data[, month_id :=
  as.integer(format(month_date, "%Y")) * 12L +
    as.integer(format(month_date, "%m")) - 1L]

handle_coverage <- handle_data[, .(
  handle_data_start = min(month_date),
  handle_data_end = max(month_date),
  n_handle_months = .N,
  n_missing_reported_handle = sum(is.na(handle))
), by = state]

# Match the project's fixed peak rule exactly: online-era observations only,
# cap at December 2024, and exclude March 2020 through July 2021.
peak_candidates <- merge(
  handle_data,
  online_states[, .(state, online_launch_month)],
  by = "state",
  all = FALSE
)
pre_2025_peaks <- peak_candidates[
  month_date >= online_launch_month &
    month_date < PRE_2025_END &
    !(month_date >= COVID_EXCLUSION_START &
      month_date <= COVID_EXCLUSION_END) &
    !is.na(handle),
  .SD[which.max(handle)],
  by = state,
  .SDcols = c("month_date", "handle")
]
setnames(
  pre_2025_peaks,
  c("month_date", "handle"),
  c("pre_2025_peak_month", "pre_2025_peak_handle")
)

state_overview <- merge(
  online_states,
  handle_coverage,
  by = "state",
  all.x = TRUE
)
state_overview <- merge(
  state_overview,
  pre_2025_peaks,
  by = "state",
  all.x = TRUE
)
state_overview[, `:=`(
  has_handle_data = !is.na(handle_data_start),
  has_pre_2025_peak = !is.na(pre_2025_peak_handle),
  is_peak_before_online = !is.na(pre_2025_peak_month) &
    pre_2025_peak_month < online_launch_month,
  first_full_quarter_start =
    month_id_to_date(first_full_quarter_start_id),
  fourth_full_quarter_start =
    month_id_to_date(fourth_full_quarter_start_id)
)]
state_overview[, `:=`(
  is_post_covid_panel_state =
    state %chin% post_covid_panel_states[, state],
  is_post_covid_launch_cohort =
    state %chin% post_covid_launch_cohort[, state]
)]

# 2. Construct exact event-month windows ---------------------------------------

event_offsets <- rbindlist(list(
  data.table(
    window_id = "launch_block_m0_m2",
    window_label = "Launch block: event months 0-2",
    event_month = 0L:2L
  ),
  data.table(
    window_id = "fourth_exposure_block_m9_m11",
    window_label = "Fourth post-launch 3-month block: months 9-11",
    event_month = 9L:11L
  ),
  data.table(
    window_id = "event_quarter_plus_4_m12_m14",
    window_label = "Event quarter +4 block: months 12-14",
    event_month = 12L:14L
  )
))

event_base <- copy(state_overview)
event_base[, join_key := 1L]
event_offsets[, join_key := 1L]
expected_event <- merge(
  event_base,
  event_offsets,
  by = "join_key",
  allow.cartesian = TRUE
)
expected_event[, `:=`(
  window_family = "event_month",
  expected_month_id = launch_month_id + event_month
)]
expected_event[, expected_month_date :=
  month_id_to_date(expected_month_id)]
expected_event[, join_key := NULL]

expected_event <- merge(
  expected_event,
  handle_data[, .(state, month_id, handle)],
  by.x = c("state", "expected_month_id"),
  by.y = c("state", "month_id"),
  all.x = TRUE
)

# 3. Construct first-full-calendar-quarter windows -----------------------------

calendar_offsets <- rbindlist(list(
  data.table(
    window_id = "first_full_calendar_quarter",
    window_label = "First full calendar quarter after launch",
    quarter_start_source = "first_full_quarter_start_id",
    within_quarter_month = 0L:2L
  ),
  data.table(
    window_id = "fourth_full_calendar_quarter",
    window_label = "Fourth full calendar quarter after launch",
    quarter_start_source = "fourth_full_quarter_start_id",
    within_quarter_month = 0L:2L
  )
))

calendar_base <- copy(state_overview)
calendar_base[, join_key := 1L]
calendar_offsets[, join_key := 1L]
expected_calendar <- merge(
  calendar_base,
  calendar_offsets,
  by = "join_key",
  allow.cartesian = TRUE
)
expected_calendar[, expected_month_id := fifelse(
  quarter_start_source == "first_full_quarter_start_id",
  first_full_quarter_start_id,
  fourth_full_quarter_start_id
) + within_quarter_month]
expected_calendar[, `:=`(
  window_family = "calendar_quarter",
  expected_month_date = month_id_to_date(expected_month_id),
  event_month = expected_month_id - launch_month_id
)]
expected_calendar[, join_key := NULL]

expected_calendar <- merge(
  expected_calendar,
  handle_data[, .(state, month_id, handle)],
  by.x = c("state", "expected_month_id"),
  by.y = c("state", "month_id"),
  all.x = TRUE
)

# 4. State-window metrics and inclusion flags ----------------------------------

expected_windows <- rbindlist(
  list(expected_event, expected_calendar),
  use.names = TRUE,
  fill = TRUE
)

state_window_metrics <- expected_windows[, .(
  online_launch_month = first(online_launch_month),
  retail_launch_month = first(retail_launch_month),
  retail_transition = first(retail_transition),
  handle_data_start = first(handle_data_start),
  handle_data_end = first(handle_data_end),
  has_handle_data = first(has_handle_data),
  has_pre_2025_peak = first(has_pre_2025_peak),
  is_peak_before_online = first(is_peak_before_online),
  is_post_covid_panel_state = first(is_post_covid_panel_state),
  is_post_covid_launch_cohort = first(is_post_covid_launch_cohort),
  pre_2025_peak_handle = first(pre_2025_peak_handle),
  pre_2025_peak_month = first(pre_2025_peak_month),
  n_months_expected = .N,
  n_months_observed = sum(!is.na(handle)),
  expected_months = paste(format(expected_month_date, "%Y-%m"), collapse = ";"),
  observed_months = paste(
    format(expected_month_date[!is.na(handle)], "%Y-%m"),
    collapse = ";"
  ),
  calendar_months = paste(
    month.abb[as.integer(format(expected_month_date, "%m"))],
    collapse = ";"
  ),
  event_month_min = min(event_month),
  event_month_max = max(event_month),
  window_start_date = min(expected_month_date),
  window_end_date = max(expected_month_date),
  observed_total_handle = sum(handle, na.rm = TRUE)
), by = .(state, window_family, window_id, window_label)]

state_window_metrics[, `:=`(
  is_complete_window = n_months_observed == EXPECTED_MONTHS_PER_WINDOW,
  coverage_status = fifelse(
    n_months_observed == EXPECTED_MONTHS_PER_WINDOW,
    "complete",
    fifelse(n_months_observed == 0L, "missing", "partial")
  )
)]
state_window_metrics[, `:=`(
  total_handle = fifelse(
    is_complete_window,
    observed_total_handle,
    NA_real_
  ),
  average_monthly_handle = fifelse(
    is_complete_window,
    observed_total_handle / EXPECTED_MONTHS_PER_WINDOW,
    NA_real_
  )
)]
state_window_metrics[, handle_pct_pre_2025_peak := fifelse(
  is_complete_window & !is.na(pre_2025_peak_handle) &
    pre_2025_peak_handle > 0,
  100 * average_monthly_handle / pre_2025_peak_handle,
  NA_real_
)]

launch_reference <- state_window_metrics[
  window_id == "launch_block_m0_m2",
  .(
    state,
    launch_block_total_handle = total_handle,
    launch_block_is_complete = is_complete_window
  )
]
full_quarter_reference <- state_window_metrics[
  window_id == "first_full_calendar_quarter",
  .(
    state,
    first_full_quarter_total_handle = total_handle,
    first_full_quarter_is_complete = is_complete_window
  )
]

state_window_metrics <- merge(
  state_window_metrics,
  launch_reference,
  by = "state",
  all.x = TRUE
)
state_window_metrics <- merge(
  state_window_metrics,
  full_quarter_reference,
  by = "state",
  all.x = TRUE
)

state_window_metrics[, ratio_to_launch_block := fifelse(
  is_complete_window & launch_block_is_complete &
    !is.na(launch_block_total_handle) & launch_block_total_handle > 0,
  total_handle / launch_block_total_handle,
  NA_real_
)]
state_window_metrics[, ratio_to_family_reference := fifelse(
  window_family == "event_month",
  ratio_to_launch_block,
  fifelse(
    is_complete_window & first_full_quarter_is_complete &
      !is.na(first_full_quarter_total_handle) &
      first_full_quarter_total_handle > 0,
    total_handle / first_full_quarter_total_handle,
    NA_real_
  )
)]
state_window_metrics[, is_included_in_peak_distribution :=
  is_complete_window & !is.na(handle_pct_pre_2025_peak)]
state_window_metrics[, is_within_study_cutoff :=
  window_end_date < PRE_2025_END]

state_window_metrics[, exclusion_reason := fifelse(
  is_complete_window & !is.na(handle_pct_pre_2025_peak),
  "included",
  fifelse(
    is.na(handle_data_start),
    "no Handle series",
    fifelse(
      !is_complete_window & handle_data_end < window_end_date,
      "insufficient follow-up",
      fifelse(
        !is_complete_window,
        "internal missing month(s)",
        "no fixed pre-2025 peak"
      )
    )
  )
)]

setorder(state_window_metrics, window_family, window_id, state)

# 5. Cross-state summaries -----------------------------------------------------

eligible_extended <- state_window_metrics[
  is_included_in_peak_distribution == TRUE
]
eligible_study_cutoff <- eligible_extended[is_within_study_cutoff == TRUE]
eligible_post_covid_cohort <- eligible_extended[
  is_post_covid_launch_cohort == TRUE
]
eligible_post_covid_cutoff <- eligible_post_covid_cohort[
  is_within_study_cutoff == TRUE
]

summary_input <- rbindlist(list(
  copy(eligible_study_cutoff)[
    , summary_group := "all_states_study_cutoff"
  ],
  copy(eligible_extended)[
    , summary_group := "all_states_extended_followup"
  ],
  copy(eligible_post_covid_cohort)[
    , summary_group := "post_covid_panel_launch_cohort"
  ],
  copy(eligible_post_covid_cutoff)[
    , summary_group := "post_covid_panel_cohort_study_cutoff"
  ],
  copy(eligible_study_cutoff)[
    , summary_group := paste0("study_cutoff_", retail_transition)
  ]
))

summary_statistics <- summary_input[, .(
  n_states = .N,
  mean_total_handle = mean(total_handle),
  q25_total_handle = quantile(total_handle, probs = 0.25, names = FALSE),
  median_total_handle = median(total_handle),
  q75_total_handle = quantile(total_handle, probs = 0.75, names = FALSE),
  mean_average_monthly_handle = mean(average_monthly_handle),
  q25_average_monthly_handle = quantile(
    average_monthly_handle,
    probs = 0.25,
    names = FALSE
  ),
  median_average_monthly_handle = median(average_monthly_handle),
  q75_average_monthly_handle = quantile(
    average_monthly_handle,
    probs = 0.75,
    names = FALSE
  ),
  mean_pct_pre_2025_peak = mean(handle_pct_pre_2025_peak),
  q25_pct_pre_2025_peak = quantile(
    handle_pct_pre_2025_peak,
    probs = 0.25,
    names = FALSE
  ),
  median_pct_pre_2025_peak = median(handle_pct_pre_2025_peak),
  q75_pct_pre_2025_peak = quantile(
    handle_pct_pre_2025_peak,
    probs = 0.75,
    names = FALSE
  ),
  mean_ratio_to_launch_block = mean(
    ratio_to_launch_block,
    na.rm = TRUE
  ),
  median_ratio_to_launch_block = median(
    ratio_to_launch_block,
    na.rm = TRUE
  ),
  mean_ratio_to_family_reference = mean(
    ratio_to_family_reference,
    na.rm = TRUE
  ),
  median_ratio_to_family_reference = median(
    ratio_to_family_reference,
    na.rm = TRUE
  ),
  aggregate_total_handle = sum(total_handle),
  aggregate_pct_pre_2025_peak =
    100 * sum(total_handle) /
      (EXPECTED_MONTHS_PER_WINDOW * sum(pre_2025_peak_handle)),
  aggregate_ratio_to_launch_block =
    sum(total_handle, na.rm = TRUE) /
      sum(launch_block_total_handle, na.rm = TRUE),
  aggregate_ratio_to_family_reference =
    sum(total_handle, na.rm = TRUE) /
      sum(
        if (first(window_family) == "event_month") {
          launch_block_total_handle
        } else {
          first_full_quarter_total_handle
        },
        na.rm = TRUE
      )
), by = .(
  summary_group,
  window_family,
  window_id,
  window_label
)]
setorder(summary_statistics, window_family, window_id, summary_group)

support_checks <- summary_statistics[
  window_id == "fourth_full_calendar_quarter" &
    summary_group %chin% c(
      "all_states_study_cutoff",
      "post_covid_panel_launch_cohort",
      "post_covid_panel_cohort_study_cutoff"
    ),
  .(summary_group, n_states)
]
expected_support <- data.table(
  summary_group = c(
    "all_states_study_cutoff",
    "post_covid_panel_launch_cohort",
    "post_covid_panel_cohort_study_cutoff"
  ),
  expected_n_states = c(26L, 7L, 5L)
)
support_checks <- merge(
  support_checks,
  expected_support,
  by = "summary_group",
  all = TRUE
)
if (support_checks[
  is.na(n_states) | n_states != expected_n_states,
  .N
] > 0L) {
  stop("Fourth-full-quarter support counts do not match the audited design.")
}

seasonality_composition <- expected_windows[, .(
  n_state_months = .N
), by = .(
  window_family,
  window_id,
  calendar_month = month.abb[
    as.integer(format(expected_month_date, "%m"))
  ]
)]
seasonality_composition[, share :=
  n_state_months / sum(n_state_months),
  by = .(window_family, window_id)]

exclusion_audit <- state_window_metrics[
  window_id %chin% c(
    "fourth_exposure_block_m9_m11",
    "event_quarter_plus_4_m12_m14",
    "fourth_full_calendar_quarter"
  ) & (exclusion_reason != "included" | !is_within_study_cutoff),
  .(
    state,
    online_launch_month,
    retail_transition,
    window_family,
    window_id,
    expected_months,
    n_months_observed,
    exclusion_reason,
    is_within_study_cutoff,
    study_cutoff_status = fifelse(
      is_within_study_cutoff,
      "within December 2024 cutoff",
      "window extends beyond December 2024"
    )
  )
]

post_covid_cohort_audit <- state_overview[
  is_post_covid_launch_cohort == TRUE,
  .(
    state,
    online_launch_month,
    retail_launch_month,
    retail_transition,
    has_handle_data,
    handle_data_start,
    handle_data_end,
    has_pre_2025_peak,
    pre_2025_peak_month,
    pre_2025_peak_handle
  )
]
setorder(post_covid_cohort_audit, online_launch_month, state)

state_flags <- dcast(
  state_window_metrics,
  state + online_launch_month + retail_launch_month + retail_transition +
    handle_data_start + handle_data_end + pre_2025_peak_month +
    pre_2025_peak_handle + has_handle_data + has_pre_2025_peak +
    is_peak_before_online ~ window_id,
  value.var = "coverage_status"
)
setorder(state_flags, online_launch_month, state)

# 6. Export --------------------------------------------------------------------

fwrite(
  state_window_metrics,
  file.path(OUTPUT_DIR, "state_window_metrics.csv")
)
saveRDS(
  state_window_metrics,
  file.path(OUTPUT_DIR, "state_window_metrics.rds")
)
fwrite(state_flags, file.path(OUTPUT_DIR, "state_coverage_flags.csv"))
saveRDS(state_flags, file.path(OUTPUT_DIR, "state_coverage_flags.rds"))
fwrite(
  summary_statistics,
  file.path(OUTPUT_DIR, "summary_statistics.csv")
)
saveRDS(
  summary_statistics,
  file.path(OUTPUT_DIR, "summary_statistics.rds")
)
fwrite(exclusion_audit, file.path(OUTPUT_DIR, "exclusion_audit.csv"))
saveRDS(exclusion_audit, file.path(OUTPUT_DIR, "exclusion_audit.rds"))
fwrite(
  post_covid_cohort_audit,
  file.path(OUTPUT_DIR, "post_covid_panel_launch_cohort.csv")
)
saveRDS(
  post_covid_cohort_audit,
  file.path(OUTPUT_DIR, "post_covid_panel_launch_cohort.rds")
)
fwrite(
  seasonality_composition,
  file.path(OUTPUT_DIR, "seasonality_composition.csv")
)
saveRDS(
  seasonality_composition,
  file.path(OUTPUT_DIR, "seasonality_composition.rds")
)
saveRDS(
  list(
    handle_raw = handle_raw,
    schedule_raw = schedule_raw,
    eviction_panel_raw = eviction_panel_raw,
    handle_data = handle_data,
    post_covid_panel_states = post_covid_panel_states,
    post_covid_launch_cohort = post_covid_launch_cohort,
    state_overview = state_overview,
    expected_windows = expected_windows,
    state_window_metrics = state_window_metrics,
    summary_statistics = summary_statistics,
    exclusion_audit = exclusion_audit,
    post_covid_cohort_audit = post_covid_cohort_audit,
    seasonality_composition = seasonality_composition
  ),
  file.path(OUTPUT_DIR, "analysis_objects.rds")
)

# 7. Writer-facing results summary ---------------------------------------------

headline_ids <- c(
  "fourth_exposure_block_m9_m11",
  "event_quarter_plus_4_m12_m14",
  "fourth_full_calendar_quarter"
)
headline <- summary_statistics[
  summary_group %chin% c(
    "all_states_study_cutoff",
    "all_states_extended_followup",
    "post_covid_panel_launch_cohort",
    "post_covid_panel_cohort_study_cutoff"
  ) & window_id %chin% headline_ids
]
setkey(headline, summary_group, window_id)

format_billions <- function(x) {
  sprintf("$%.2f billion", x / 1e9)
}

format_summary_row <- function(group_id, window_key, display_label) {
  row <- headline[list(group_id, window_key)]
  if (nrow(row) != 1L) {
    stop(sprintf(
      "Missing headline summary row: %s / %s",
      group_id,
      window_key
    ))
  }
  first_full_ratio <- if (row[, window_family] == "calendar_quarter") {
    sprintf("%.2fx", row[, median_ratio_to_family_reference])
  } else {
    "n/a"
  }
  sprintf(
    paste0(
      "| %s | %d | %s | %s | %.1f%% | %.2fx | %s |"
    ),
    display_label,
    row[, n_states],
    format_billions(row[, median_total_handle]),
    format_billions(row[, median_average_monthly_handle]),
    row[, median_pct_pre_2025_peak],
    row[, median_ratio_to_launch_block],
    first_full_ratio
  )
}

missing_states <- unique(exclusion_audit[, state])
missing_text <- if (length(missing_states) == 0L) {
  "None."
} else {
  paste(sort(missing_states), collapse = ", ")
}

results_lines <- c(
  "# Sports-Betting Handle Four Quarters After Online Launch",
  "",
  "## Answer",
  "",
  paste0(
    "The table reports cross-state descriptive distributions of total ",
    "reported Handle. The median is the preferred interpretation of ",
    "‘typically’ because ",
    "state market sizes are highly skewed."
  ),
  "",
  paste0(
    "| Definition | N | Median 3-month Handle | Median monthly Handle | ",
    "Median % of fixed pre-2025 peak | Median ratio to launch block | ",
    "Median ratio to first full quarter |"
  ),
  "|---|---:|---:|---:|---:|---:|---:|",
  format_summary_row(
    "all_states_study_cutoff",
    "fourth_exposure_block_m9_m11",
    "All states; months 9-11; window ends by Dec. 2024"
  ),
  format_summary_row(
    "all_states_study_cutoff",
    "event_quarter_plus_4_m12_m14",
    "All states; months 12-14; window ends by Dec. 2024"
  ),
  format_summary_row(
    "all_states_study_cutoff",
    "fourth_full_calendar_quarter",
    "All states; fourth full quarter; window ends by Dec. 2024"
  ),
  format_summary_row(
    "all_states_extended_followup",
    "fourth_full_calendar_quarter",
    "All states; fourth full quarter; extended Handle follow-up"
  ),
  format_summary_row(
    "post_covid_panel_launch_cohort",
    "fourth_full_calendar_quarter",
    "Exact post-COVID panel launch cohort; extended Handle follow-up"
  ),
  format_summary_row(
    "post_covid_panel_cohort_study_cutoff",
    "fourth_full_calendar_quarter",
    "Exact post-COVID panel launch cohort; window ends by Dec. 2024"
  ),
  "",
  "Full means, quartiles, and dollar-weighted aggregate ratios are in ",
  "`summary_statistics.csv`. These are descriptive statistics; standard ",
  "errors, significance levels, and causal interpretations are not applicable.",
  "",
  "## Definitions",
  "",
  "- Operational online launch is `online_start_date` in the project ",
  "  schedule. ",
  "  Its recorded month is event month 0.",
  "- The fourth post-launch exposure block is event months 9-11.",
  "- Event quarter +4 is event months 12-14.",
  "- The fourth full calendar quarter begins nine months after the first full ",
  "  calendar quarter following the launch quarter. Its event-month ",
  "  composition ",
  "  varies with the launch month.",
  paste0(
    "- The fixed peak uses online-era observations only, is capped at ",
    "December ",
    "2024, and excludes March 2020 through July 2021."
  ),
  "- Handle is total reported Handle. The source does not split online from ",
  "  retail Handle, so each state's retail-versus-online launch sequence ",
  "  remains flagged.",
  "",
  "## Coverage and measurement flags",
  "",
  paste0(
    "- Scheduled online-launch states excluded from at least one headline ",
    "distribution: ",
    missing_text,
    "."
  ),
  "- Incomplete windows are excluded rather than prorated; see ",
  "  `exclusion_audit.csv` and `state_coverage_flags.csv`.",
  paste0(
    "- The exact post-COVID eviction-panel launch cohort contains eight ",
    "states: ",
    paste(post_covid_cohort_audit[, state], collapse = ", "),
    ". Florida has no Handle series, leaving seven with observed extended ",
    "fourth-quarter Handle."
  ),
  "- No seasonal adjustment is applied. Each state's exact calendar-month ",
  "  composition is stored in `state_window_metrics.csv`, and pooled month ",
  "  shares ",
  "  are in `seasonality_composition.csv`.",
  "- Ratios to the launch block compare with event months 0-2. The calendar ",
  "  output also reports the ratio to the first full calendar quarter; this ",
  "  is the preferred calendar-quarter ramp comparison.",
  "- A pre-2025 benchmark is deliberately fixed before 2025. Later-state ",
  "  windows can exceed 100% of that historical peak without constituting an ",
  "  error.",
  "",
  "## Paper-to-code naming map",
  "",
  "| Paper notation | Code name | Description |",
  "|---|---|---|",
  "| H_it | `handle` | Reported total state-month Handle |",
  "| G_i | `online_launch_month` | Operational online launch month |",
  "| e_it | `event_month` | Months since launch; launch month = 0 |",
  paste0(
    "| H_i^(peak,<2025) | `pre_2025_peak_handle` | Pre-2025 peak |"
  ),
  paste0(
    "| R_iw | `handle_pct_pre_2025_peak` | Window average as percent of peak |"
  ),
  paste0(
    "| Q_i^(full) | `first_full_quarter_start` | First full quarter |"
  )
)

writeLines(
  results_lines,
  con = file.path(OUTPUT_DIR, "results_summary.md"),
  useBytes = TRUE
)

message(sprintf(
  "Saved Handle ramp-up outputs for %d scheduled online-launch states to %s",
  nrow(state_overview),
  OUTPUT_DIR
))
