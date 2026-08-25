#!/usr/bin/env Rscript
# ==============================================================================
# handle_legalization_cohort_support.R
# Support diagnostics for updated sports-betting treatment definitions
# Paper: Gambling and Eviction, staggered-adoption design diagnostics
# Inputs: state eviction panel, legalization schedule, LSR Handle-50 panels
# Outputs: output/handle_cohort_support/{CSV,RDS,results_summary.md}
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
})

SEED <- 20260814L
set.seed(SEED)

# 0. Configuration -------------------------------------------------------------

PANEL_FILE <- "data/raw/state_month_panel_with_treatment.csv"
LEGALIZATION_FILE <- "data/raw/sports_gambling_legalization_dates.csv"
HANDLE_FILE <- "data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv"
HANDLE50_FILE <- "data/processed/state_month_panel_handle50_treatment.csv"
HANDLE_CLASSIFICATION_FILE <-
  "data/processed/handle50_state_classification.csv"
HANDLE50_PREVIOUS_FILE <- paste0(
  "data/processed/deprecated/",
  "state_month_panel_handle50_treatment_2026-08-14_prefix.csv"
)
OUT_DIR <- "output/handle_cohort_support"

MIN_DATE <- as.Date("2016-01-01")
MAX_DATE <- as.Date("2024-12-31")
COVID_START <- as.Date("2020-03-01")
COVID_END <- as.Date("2021-07-31")
SMALL_GROUP_CUTOFF <- 5L
LEGACY_EXCLUDE_STATES <- c("ID", "ME")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# ============================================================
# Paper-to-Code Naming Map
# ============================================================
# Paper Notation | Code Name               | Description
# $Y_{st}$       | filings_per_1k_renters  | Eviction filings per 1,000 renters
# $G_s$          | cohort_month            | State's first-treated month
# $e=t-G_s$      | event_time               | Relative month or year
# $ATT(g,t)$     | cs_group_time_support    | CS group-time comparison cell
# $\theta_e$     | sa_event_time_support    | Sun-Abraham relative-time coefficient
# ============================================================

required_files <- c(
  PANEL_FILE,
  LEGALIZATION_FILE,
  HANDLE_FILE,
  HANDLE50_FILE,
  HANDLE_CLASSIFICATION_FILE
)
missing_files <- required_files[!file.exists(required_files)]
if (length(missing_files) > 0L) {
  stop("Missing required input(s): ", paste(missing_files, collapse = ", "),
       call. = FALSE)
}

# 1. Helper functions ----------------------------------------------------------

state_name_to_abb <- function(state_name) {
  lookup <- c(setNames(state.abb, state.name), "District of Columbia" = "DC")
  unname(lookup[trimws(as.character(state_name))])
}

month_index <- function(x) {
  x <- as.Date(x)
  as.integer(format(x, "%Y")) * 12L + as.integer(format(x, "%m"))
}

first_nonmissing_date <- function(x) {
  x <- as.Date(x)
  if (all(is.na(x))) return(as.Date(NA))
  min(x, na.rm = TRUE)
}

extract_panel_schedule <- function(path, date_name) {
  read_csv(path, show_col_types = FALSE) %>%
    transmute(state_abb = as.character(state_abb),
              treatment_date = as.Date(treat_start)) %>%
    group_by(state_abb) %>%
    summarise(treatment_date = first_nonmissing_date(treatment_date),
              .groups = "drop") %>%
    mutate(treatment_definition = date_name)
}

period_table <- function(panel_df, grain) {
  if (identical(grain, "monthly")) {
    return(panel_df %>%
      distinct(period_date = month_date) %>%
      arrange(period_date) %>%
      mutate(period_value = month_index(period_date),
             period_label = format(period_date, "%Y-%m")))
  }

  panel_df %>%
    transmute(period_value = as.integer(format(month_date, "%Y"))) %>%
    distinct() %>%
    arrange(period_value) %>%
    mutate(period_date = as.Date(paste0(period_value, "-01-01")),
           period_label = as.character(period_value))
}

panel_availability <- function(panel_df, grain) {
  if (identical(grain, "monthly")) {
    return(panel_df %>%
      filter(!is.na(filings_count)) %>%
      transmute(state_abb, period_value = month_index(month_date)) %>%
      distinct())
  }

  panel_df %>%
    filter(!is.na(filings_count)) %>%
    transmute(state_abb,
              period_value = as.integer(format(month_date, "%Y"))) %>%
    distinct()
}

prepare_state_cohorts <- function(panel_df, schedule_df, grain) {
  max_panel_date <- max(panel_df$month_date)
  states <- panel_df %>% distinct(state_abb)

  out <- states %>%
    left_join(schedule_df %>% select(state_abb, treatment_date), by = "state_abb") %>%
    mutate(
      treatment_date = as.Date(treatment_date),
      treatment_date = if_else(treatment_date <= max_panel_date,
                               treatment_date, as.Date(NA)),
      treated_in_window = !is.na(treatment_date),
      cohort_value = if_else(
        treated_in_window,
        if (identical(grain, "monthly")) {
          month_index(treatment_date)
        } else {
          as.integer(format(treatment_date, "%Y"))
        },
        0L
      ),
      cohort_label = if_else(
        treated_in_window,
        if (identical(grain, "monthly")) {
          format(treatment_date, "%Y-%m")
        } else {
          format(treatment_date, "%Y")
        },
        "never"
      )
    )

  if (anyDuplicated(out$state_abb) > 0L) {
    stop("Treatment schedule produced duplicate state rows.", call. = FALSE)
  }
  out
}

summarise_design <- function(state_cohorts, sample_name,
                             treatment_definition, grain) {
  treated <- state_cohorts %>% filter(treated_in_window)
  cohorts <- treated %>% count(cohort_value, cohort_label, name = "cohort_size")
  n_treated <- nrow(treated)
  hhi <- if (n_treated > 0L) sum((cohorts$cohort_size / n_treated)^2) else NA_real_

  tibble(
    sample = sample_name,
    treatment_definition = treatment_definition,
    grain = grain,
    n_states = nrow(state_cohorts),
    n_treated = n_treated,
    n_never_treated = sum(!state_cohorts$treated_in_window),
    n_cohorts = nrow(cohorts),
    n_singleton_cohorts = sum(cohorts$cohort_size == 1L),
    n_cohorts_lt5 = sum(cohorts$cohort_size < SMALL_GROUP_CUTOFF),
    treated_states_in_singletons = sum(cohorts$cohort_size[cohorts$cohort_size == 1L]),
    share_treated_states_in_singletons = if (n_treated > 0L) {
      sum(cohorts$cohort_size[cohorts$cohort_size == 1L]) / n_treated
    } else {
      NA_real_
    },
    treated_states_in_cohorts_lt5 = sum(cohorts$cohort_size[
      cohorts$cohort_size < SMALL_GROUP_CUTOFF
    ]),
    share_treated_states_in_cohorts_lt5 = if (n_treated > 0L) {
      sum(cohorts$cohort_size[cohorts$cohort_size < SMALL_GROUP_CUTOFF]) / n_treated
    } else {
      NA_real_
    },
    largest_cohort = if (nrow(cohorts) > 0L) max(cohorts$cohort_size) else 0L,
    cohort_hhi = hhi,
    effective_number_of_cohorts = if (is.finite(hhi) && hhi > 0) 1 / hhi else NA_real_
  )
}

build_cohort_sizes <- function(state_cohorts, sample_name,
                               treatment_definition, grain, periods) {
  observed_values <- periods$period_value
  state_cohorts %>%
    filter(treated_in_window) %>%
    group_by(cohort_value, cohort_label) %>%
    summarise(
      cohort_size = n(),
      states = paste(sort(state_abb), collapse = ";"),
      treatment_date_min = min(treatment_date),
      treatment_date_max = max(treatment_date),
      .groups = "drop"
    ) %>%
    mutate(
      sample = sample_name,
      treatment_definition = treatment_definition,
      grain = grain,
      cohort_is_observed_period = cohort_value %in% observed_values,
      is_singleton = cohort_size == 1L,
      is_lt5 = cohort_size < SMALL_GROUP_CUTOFF
    ) %>%
    select(sample, treatment_definition, grain, everything())
}

build_calendar_controls <- function(state_cohorts, periods, panel_df,
                                    sample_name, treatment_definition, grain) {
  n_never <- sum(!state_cohorts$treated_in_window)
  availability <- panel_availability(panel_df, grain)
  periods %>%
    mutate(
      sample = sample_name,
      treatment_definition = treatment_definition,
      grain = grain,
      n_never_treated_controls = n_never,
      n_observed_states = vapply(
        period_value,
        function(period_i) {
          sum(availability$period_value == period_i)
        },
        integer(1L)
      ),
      n_observed_never_treated_controls = vapply(
        period_value,
        function(period_i) {
          observed <- availability$state_abb[
            availability$period_value == period_i
          ]
          sum(!state_cohorts$treated_in_window[
            match(observed, state_cohorts$state_abb)
          ])
        },
        integer(1L)
      ),
      n_not_yet_treated_controls = vapply(
        period_value,
        function(period_i) {
          observed <- availability$state_abb[
            availability$period_value == period_i
          ]
          state_rows <- match(observed, state_cohorts$state_abb)
          sum(!state_cohorts$treated_in_window[state_rows] |
                state_cohorts$cohort_value[state_rows] > period_i)
        },
        integer(1L)
      )
    ) %>%
    select(sample, treatment_definition, grain, everything())
}

build_cs_cells <- function(state_cohorts, periods, panel_df, sample_name,
                           treatment_definition, grain) {
  cohort_members <- state_cohorts %>%
    filter(treated_in_window) %>%
    count(cohort_value, cohort_label, name = "n_treated_states")
  availability <- panel_availability(panel_df, grain)

  state_ids <- state_cohorts$state_abb
  period_ids <- periods$period_value
  availability_matrix <- matrix(
    FALSE,
    nrow = length(state_ids),
    ncol = length(period_ids),
    dimnames = list(state_ids, as.character(period_ids))
  )
  availability_matrix[cbind(
    match(availability$state_abb, state_ids),
    match(availability$period_value, period_ids)
  )] <- TRUE

  cell_index <- tidyr::crossing(
    cohort_members %>%
      select(cohort_value, cohort_label, n_treated_states),
    periods %>% select(period_value, period_label, period_date)
  ) %>%
    filter(period_value >= cohort_value)
  cell_index <- cell_index %>%
    mutate(
      pre_period_value = vapply(
        cohort_value,
        function(cohort_i) {
          pre_values <- period_ids[period_ids < cohort_i]
          if (length(pre_values) > 0L) max(pre_values) else NA_integer_
        },
        integer(1L)
      ),
      has_pre_period = !is.na(pre_period_value)
    )

  get_complete <- function(row_i) {
    if (!cell_index$has_pre_period[row_i]) {
      return(rep(FALSE, length(state_ids)))
    }
    availability_matrix[, as.character(cell_index$pre_period_value[row_i])] &
      availability_matrix[, as.character(cell_index$period_value[row_i])]
  }

  n_treated_complete <- vapply(seq_len(nrow(cell_index)), function(row_i) {
    complete <- get_complete(row_i)
    is_group <- state_cohorts$cohort_value == cell_index$cohort_value[row_i] &
      state_cohorts$treated_in_window
    sum(complete & is_group)
  }, integer(1L))

  n_never <- vapply(seq_len(nrow(cell_index)), function(row_i) {
    complete <- get_complete(row_i)
    sum(complete & !state_cohorts$treated_in_window)
  }, integer(1L))

  n_not_yet <- vapply(seq_len(nrow(cell_index)), function(row_i) {
    complete <- get_complete(row_i)
    eligible <- !state_cohorts$treated_in_window |
      state_cohorts$cohort_value > cell_index$period_value[row_i]
    sum(complete & eligible)
  }, integer(1L))

  cells <- cell_index %>%
    mutate(
      sample = sample_name,
      treatment_definition = treatment_definition,
      grain = grain,
      event_time = period_value - cohort_value,
      n_treated_complete = n_treated_complete,
      treated_group_lt5 = n_treated_states < SMALL_GROUP_CUTOFF
    )

  bind_rows(
    cells %>% mutate(control_group = "never_treated",
                     n_controls = n_never),
    cells %>% mutate(control_group = "not_yet_treated",
                     n_controls = n_not_yet)
  ) %>%
    mutate(supported = has_pre_period & n_treated_complete > 0L &
             n_controls > 0L) %>%
    select(sample, treatment_definition, grain, control_group,
           cohort_value, cohort_label, period_value, period_label,
           period_date, event_time, pre_period_value, n_treated_states,
           n_treated_complete, n_controls, has_pre_period,
           treated_group_lt5, supported)
}

summarise_cs_cells <- function(cells) {
  cells %>%
    group_by(sample, treatment_definition, grain, control_group) %>%
    summarise(
      n_post_group_time_cells = n(),
      n_supported_cells = sum(supported),
      share_supported_cells = mean(supported),
      n_cells_with_treated_group_lt5 = sum(treated_group_lt5),
      share_cells_with_treated_group_lt5 = mean(treated_group_lt5),
      n_cells_with_incomplete_treated_group =
        sum(n_treated_complete < n_treated_states),
      min_controls = min(n_controls),
      median_controls = median(n_controls),
      n_cells_with_controls_lt5 = sum(n_controls < SMALL_GROUP_CUTOFF),
      max_supported_event_time = if (any(supported)) {
        max(event_time[supported])
      } else {
        NA_integer_
      },
      .groups = "drop"
    )
}

build_sa_support <- function(state_cohorts, periods, panel_df, controls,
                             sample_name, treatment_definition, grain) {
  treated <- state_cohorts %>% filter(treated_in_window)
  if (nrow(treated) == 0L) return(tibble())

  availability <- panel_availability(panel_df, grain)
  state_period <- treated %>%
    select(state_abb, cohort_value, cohort_label) %>%
    inner_join(availability, by = "state_abb") %>%
    left_join(periods %>% select(period_value, period_label),
              by = "period_value") %>%
    mutate(event_time = period_value - cohort_value) %>%
    left_join(
      controls %>% select(period_value,
                          n_observed_never_treated_controls,
                          n_not_yet_treated_controls),
      by = "period_value"
    )

  state_period %>%
    group_by(event_time) %>%
    summarise(
      n_contributing_states = n_distinct(state_abb),
      n_contributing_cohorts = n_distinct(cohort_value),
      n_calendar_periods = n_distinct(period_value),
      min_never_treated_controls =
        min(n_observed_never_treated_controls),
      min_not_yet_treated_controls = min(n_not_yet_treated_controls),
      max_not_yet_treated_controls = max(n_not_yet_treated_controls),
      states = paste(sort(unique(state_abb)), collapse = ";"),
      .groups = "drop"
    ) %>%
    mutate(
      sample = sample_name,
      treatment_definition = treatment_definition,
      grain = grain,
      contributing_states_lt5 = n_contributing_states < SMALL_GROUP_CUTOFF
    ) %>%
    select(sample, treatment_definition, grain, everything())
}

summarise_sa_support <- function(sa_support) {
  sa_support %>%
    group_by(sample, treatment_definition, grain) %>%
    summarise(
      min_event_time = min(event_time),
      max_event_time = max(event_time),
      n_relative_times = n(),
      n_relative_times_with_lt5_states = sum(contributing_states_lt5),
      share_relative_times_with_lt5_states = mean(contributing_states_lt5),
      first_post_event_time_with_lt5_states = {
        x <- event_time[event_time >= 0L & contributing_states_lt5]
        if (length(x) > 0L) min(x) else NA_integer_
      },
      last_post_event_time_with_at_least5_states = {
        x <- event_time[event_time >= 0L & !contributing_states_lt5]
        if (length(x) > 0L) max(x) else NA_integer_
      },
      .groups = "drop"
    )
}

save_object <- function(object, stem) {
  saveRDS(object, file.path(OUT_DIR, paste0(stem, ".rds")))
}

# 2. Load data and reproduce the analysis samples -----------------------------

panel_raw <- read_csv(PANEL_FILE, show_col_types = FALSE) %>%
  mutate(state_abb = as.character(state_abb),
         month_date = as.Date(month_date),
         embedded_treat_start = as.Date(treat_start))

if (anyDuplicated(panel_raw[c("state_abb", "month_date")]) > 0L) {
  stop("The raw panel has duplicate state-month keys.", call. = FALSE)
}

sample_restrictions <- tibble(
  restriction = "raw panel",
  n_rows = nrow(panel_raw),
  n_states = n_distinct(panel_raw$state_abb)
)

panel_window <- panel_raw %>%
  filter(month_date >= MIN_DATE, month_date <= MAX_DATE)
sample_restrictions <- bind_rows(
  sample_restrictions,
  tibble(restriction = "2016-01 through 2024-12",
         n_rows = nrow(panel_window),
         n_states = n_distinct(panel_window$state_abb))
)

panel_nocovid <- panel_window %>%
  filter(!(month_date >= COVID_START & month_date <= COVID_END))
sample_restrictions <- bind_rows(
  sample_restrictions,
  tibble(restriction = "drop 2020-03 through 2021-07",
         n_rows = nrow(panel_nocovid),
         n_states = n_distinct(panel_nocovid$state_abb))
)

coverage <- panel_nocovid %>% count(state_abb, name = "n_months")
coverage_threshold <- max(coverage$n_months)
current_states <- coverage %>%
  filter(n_months == coverage_threshold) %>%
  pull(state_abb)
panel_current <- panel_nocovid %>% filter(state_abb %in% current_states)

common_months <- panel_current %>%
  count(month_date, name = "n_states") %>%
  filter(n_states == length(current_states)) %>%
  pull(month_date)
panel_current <- panel_current %>% filter(month_date %in% common_months)

panel_legacy24 <- panel_current %>%
  filter(!(state_abb %in% LEGACY_EXCLUDE_STATES))

sample_restrictions <- bind_rows(
  sample_restrictions,
  tibble(restriction = "all panel states, 2016-2024 excluding COVID",
         n_rows = nrow(panel_nocovid),
         n_states = n_distinct(panel_nocovid$state_abb)),
  tibble(restriction = paste0("current exact balanced sample (", coverage_threshold,
                              " months)"),
         n_rows = nrow(panel_current),
         n_states = n_distinct(panel_current$state_abb)),
  tibble(restriction = "legacy 24-state sample (exclude ID and ME)",
         n_rows = nrow(panel_legacy24),
         n_states = n_distinct(panel_legacy24$state_abb))
)

if (n_distinct(panel_current$state_abb) != 26L ||
    n_distinct(panel_legacy24$state_abb) != 24L) {
  stop("Unexpected exact-sample dimensions; inspect panel coverage.", call. = FALSE)
}

samples <- list(all_panel_39 = panel_nocovid,
                current_exact_26 = panel_current,
                legacy_exact_24 = panel_legacy24)

handle_classification <- read_csv(
  HANDLE_CLASSIFICATION_FILE,
  show_col_types = FALSE
) %>%
  mutate(
    legal_online_start = as.Date(legal_online_start),
    handle_threshold_start = as.Date(handle_threshold_start),
    treat_start = as.Date(treat_start),
    control_eligible = as.logical(control_eligible),
    analysis_eligible = as.logical(analysis_eligible)
  )

required_classification_columns <- c(
  "state_abb",
  "handle_threshold_start",
  "handle_treatment_status",
  "control_eligible",
  "analysis_eligible",
  "exclusion_reason"
)
if (!all(required_classification_columns %in%
         names(handle_classification))) {
  stop(
    "Handle classification is missing required columns: ",
    paste(
      setdiff(required_classification_columns, names(handle_classification)),
      collapse = ", "
    ),
    call. = FALSE
  )
}
if (anyDuplicated(handle_classification$state_abb) > 0L) {
  stop("Handle classification has duplicate states.", call. = FALSE)
}

handle_exclusions <- handle_classification %>%
  filter(!analysis_eligible)
handle_eligible_states <- handle_classification %>%
  filter(analysis_eligible) %>%
  pull(state_abb)

expected_excluded_states <- c("FL", "NV")
if (!setequal(handle_exclusions$state_abb, expected_excluded_states)) {
  stop(
    "Unexpected Handle-analysis exclusions; expected FL and NV, got: ",
    paste(sort(handle_exclusions$state_abb), collapse = ", "),
    call. = FALSE
  )
}

handle_panel_raw <- read_csv(HANDLE50_FILE, show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date), treat_start = as.Date(treat_start))
if (any(handle_panel_raw$state_abb %in% handle_exclusions$state_abb)) {
  stop(
    "Estimator-ready Handle panel contains states classified as excluded.",
    call. = FALSE
  )
}
if (!setequal(unique(handle_panel_raw$state_abb), handle_eligible_states)) {
  stop(
    "Estimator-ready Handle panel does not match analysis-eligible states.",
    call. = FALSE
  )
}

sample_restrictions <- bind_rows(
  sample_restrictions,
  tibble(
    restriction = paste0(
      "Handle estimator panel (exclude ",
      paste(sort(handle_exclusions$state_abb), collapse = ", "),
      ")"
    ),
    n_rows = nrow(handle_panel_raw),
    n_states = n_distinct(handle_panel_raw$state_abb)
  )
)

# 3. Treatment schedules -------------------------------------------------------

legalization <- read_csv(LEGALIZATION_FILE, show_col_types = FALSE) %>%
  transmute(
    state_abb = state_name_to_abb(state),
    first_updated = as.Date(first_start_date),
    online_updated = as.Date(online_start_date),
    retail_updated = as.Date(retail_start_date)
  ) %>%
  filter(!is.na(state_abb))

embedded_schedule <- panel_raw %>%
  group_by(state_abb) %>%
  summarise(embedded_panel_legacy = first_nonmissing_date(embedded_treat_start),
            .groups = "drop")

handle50_updated <- handle_classification %>%
  transmute(
    state_abb,
    handle50_updated = handle_threshold_start
  )

handle50_previous <- if (file.exists(HANDLE50_PREVIOUS_FILE)) {
  extract_panel_schedule(HANDLE50_PREVIOUS_FILE, "handle50_previous_build") %>%
    select(state_abb, handle50_previous_build = treatment_date)
} else {
  tibble(state_abb = character(), handle50_previous_build = as.Date(character()))
}

schedule_wide <- panel_raw %>%
  distinct(state_abb) %>%
  left_join(embedded_schedule, by = "state_abb") %>%
  left_join(legalization, by = "state_abb") %>%
  left_join(handle50_updated, by = "state_abb") %>%
  left_join(handle50_previous, by = "state_abb") %>%
  left_join(
    handle_classification %>%
      select(
        state_abb,
        handle_treatment_status,
        handle_control_eligible = control_eligible,
        handle_analysis_eligible = analysis_eligible,
        handle_exclusion_reason = exclusion_reason
      ),
    by = "state_abb"
  )

schedule_columns <- c(
  "embedded_panel_legacy", "online_updated", "first_updated",
  "retail_updated", "handle50_previous_build", "handle50_updated"
)

schedules <- lapply(schedule_columns, function(column_i) {
  schedule_wide %>%
    transmute(state_abb,
              treatment_date = as.Date(.data[[column_i]]),
              treatment_definition = column_i)
})
names(schedules) <- schedule_columns

# Verify the updated activity-treatment table agrees with the updated panel.
activity_file <- "data/processed/activity_treatment_dates.csv"
if (file.exists(activity_file)) {
  activity_check <- read_csv(activity_file, show_col_types = FALSE) %>%
    transmute(state_abb, activity_handle50 = as.Date(treat_50pct_peak)) %>%
    inner_join(handle50_updated, by = "state_abb") %>%
    mutate(
      matches = (
        is.na(activity_handle50) & is.na(handle50_updated)
      ) | (
        !is.na(activity_handle50) & !is.na(handle50_updated) &
          activity_handle50 == handle50_updated
      )
    )
  if (any(!activity_check$matches, na.rm = TRUE)) {
    stop("Updated Handle-50 panel disagrees with activity_treatment_dates.csv.",
         call. = FALSE)
  }
} else {
  activity_check <- tibble()
}

# 4. Cohort, CS-cell, and SA relative-time diagnostics ------------------------

design_summary_list <- list()
cohort_sizes_list <- list()
calendar_controls_list <- list()
cs_cells_list <- list()
sa_support_list <- list()
state_cohort_list <- list()
counter <- 0L

for (sample_name in names(samples)) {
  panel_base_i <- samples[[sample_name]]
  for (treatment_definition in names(schedules)) {
    is_handle_estimator <- identical(
      treatment_definition,
      "handle50_updated"
    )
    panel_i <- if (is_handle_estimator) {
      panel_base_i %>% filter(state_abb %in% handle_eligible_states)
    } else {
      panel_base_i
    }
    output_sample_name <- if (is_handle_estimator) {
      paste0(sample_name, "_handle_eligible")
    } else {
      sample_name
    }
    schedule_i <- schedules[[treatment_definition]]
    for (grain in c("monthly", "annual")) {
      counter <- counter + 1L
      periods_i <- period_table(panel_i, grain)
      states_i <- prepare_state_cohorts(panel_i, schedule_i, grain)
      controls_i <- build_calendar_controls(
        states_i, periods_i, panel_i, output_sample_name,
        treatment_definition, grain
      )
      cs_i <- build_cs_cells(
        states_i, periods_i, panel_i, output_sample_name,
        treatment_definition, grain
      )

      design_summary_list[[counter]] <- summarise_design(
        states_i, output_sample_name, treatment_definition, grain
      )
      cohort_sizes_list[[counter]] <- build_cohort_sizes(
        states_i, output_sample_name, treatment_definition, grain,
        periods_i
      )
      calendar_controls_list[[counter]] <- controls_i
      cs_cells_list[[counter]] <- cs_i
      sa_support_list[[counter]] <- build_sa_support(
        states_i, periods_i, panel_i, controls_i, output_sample_name,
        treatment_definition, grain
      )
      state_cohort_list[[counter]] <- states_i %>%
        mutate(sample = output_sample_name,
               treatment_definition = treatment_definition,
               grain = grain) %>%
        select(sample, treatment_definition, grain, everything())
    }
  }
}

design_summary <- bind_rows(design_summary_list)
cohort_sizes <- bind_rows(cohort_sizes_list)
calendar_control_support <- bind_rows(calendar_controls_list)
cs_group_time_support <- bind_rows(cs_cells_list)
cs_support_summary <- summarise_cs_cells(cs_group_time_support)
sa_event_time_support <- bind_rows(sa_support_list)
sa_support_summary <- summarise_sa_support(sa_event_time_support)
state_cohorts <- bind_rows(state_cohort_list)

# 5. Legalization-to-Handle timing and before/after comparisons ----------------

handle_coverage <- read_csv(HANDLE_FILE, show_col_types = FALSE) %>%
  transmute(state_abb = state_name_to_abb(State)) %>%
  filter(!is.na(state_abb)) %>%
  distinct() %>%
  mutate(has_lsr_handle = TRUE)

date_comparison <- schedule_wide %>%
  filter(state_abb %in% unique(panel_nocovid$state_abb)) %>%
  left_join(handle_coverage, by = "state_abb") %>%
  mutate(
    is_current_exact_sample = state_abb %in% current_states,
    has_lsr_handle = coalesce(has_lsr_handle, FALSE),
    months_online_to_handle50 = if_else(
      !is.na(online_updated) & !is.na(handle50_updated),
      month_index(handle50_updated) - month_index(online_updated),
      NA_integer_
    ),
    months_first_to_online = if_else(
      !is.na(first_updated) & !is.na(online_updated),
      month_index(online_updated) - month_index(first_updated),
      NA_integer_
    ),
    months_retail_to_online = if_else(
      !is.na(retail_updated) & !is.na(online_updated),
      month_index(online_updated) - month_index(retail_updated),
      NA_integer_
    ),
    embedded_to_updated_online_changed =
      is.na(embedded_panel_legacy) != is.na(online_updated) |
      (!is.na(embedded_panel_legacy) & !is.na(online_updated) &
         embedded_panel_legacy != online_updated),
    previous_to_updated_handle50_changed =
      is.na(handle50_previous_build) != is.na(handle50_updated) |
      (!is.na(handle50_previous_build) & !is.na(handle50_updated) &
         handle50_previous_build != handle50_updated)
  ) %>%
  arrange(state_abb)

lag_summary <- bind_rows(lapply(
  c("all_panel_39", "current_exact_26"),
  function(sample_scope_i) {
    comparison_i <- if (identical(sample_scope_i, "current_exact_26")) {
      date_comparison %>% filter(is_current_exact_sample)
    } else {
      date_comparison
    }
    comparison_i %>% summarise(
    sample = sample_scope_i,
    states_with_online_and_handle50 = sum(!is.na(months_online_to_handle50)),
    mean_months_online_to_handle50 = mean(months_online_to_handle50, na.rm = TRUE),
    median_months_online_to_handle50 = median(months_online_to_handle50, na.rm = TRUE),
    min_months_online_to_handle50 = min(months_online_to_handle50, na.rm = TRUE),
    max_months_online_to_handle50 = max(months_online_to_handle50, na.rm = TRUE),
    updated_online_changes_vs_embedded = sum(embedded_to_updated_online_changed),
    updated_handle50_changes_vs_previous_build =
      sum(previous_to_updated_handle50_changed)
  )
  }
))
lag_current <- lag_summary %>% filter(sample == "current_exact_26")

# Compact horizon table for the event times commonly plotted in the paper.
focus_months <- c(-36L, -24L, -12L, -6L, -1L, 0L, 6L, 12L, 24L, 36L, 48L)
focus_years <- c(-4L, -3L, -2L, -1L, 0L, 1L, 2L, 3L, 4L, 5L, 6L)
sa_focus_horizons <- sa_event_time_support %>%
  filter((grain == "monthly" & event_time %in% focus_months) |
           (grain == "annual" & event_time %in% focus_years))

# 6. Export --------------------------------------------------------------------

csv_objects <- list(
  sample_restrictions = sample_restrictions,
  handle_state_classification = handle_classification,
  handle_analysis_exclusions = handle_exclusions,
  treatment_date_comparison = date_comparison,
  legalization_handle_lag_summary = lag_summary,
  design_summary = design_summary,
  cohort_sizes = cohort_sizes,
  calendar_control_support = calendar_control_support,
  cs_group_time_support = cs_group_time_support,
  cs_support_summary = cs_support_summary,
  sa_event_time_support = sa_event_time_support,
  sa_focus_horizons = sa_focus_horizons,
  sa_support_summary = sa_support_summary,
  state_cohorts = state_cohorts
)

for (object_name in names(csv_objects)) {
  write_csv(csv_objects[[object_name]],
            file.path(OUT_DIR, paste0(object_name, ".csv")),
            na = "NA")
  save_object(csv_objects[[object_name]], object_name)
}

save_object(panel_current, "analysis_panel_current_exact_26")
save_object(panel_legacy24, "analysis_panel_legacy_exact_24")
save_object(panel_nocovid, "analysis_panel_all_39")
save_object(
  panel_nocovid %>% filter(state_abb %in% handle_eligible_states),
  "analysis_panel_handle_eligible_all_37"
)
save_object(
  panel_current %>% filter(state_abb %in% handle_eligible_states),
  "analysis_panel_current_exact_handle_eligible_25"
)
save_object(schedule_wide, "treatment_schedules_wide")
save_object(activity_check, "activity_treatment_dates_check")
save_object(csv_objects, "all_support_diagnostics")

# 7. Results summary -----------------------------------------------------------

get_design <- function(sample_i, treatment_i, grain_i) {
  design_summary %>%
    filter(sample == sample_i,
           treatment_definition == treatment_i,
           grain == grain_i) %>%
    slice(1L)
}

get_cs <- function(sample_i, treatment_i, grain_i, control_i) {
  cs_support_summary %>%
    filter(sample == sample_i,
           treatment_definition == treatment_i,
           grain == grain_i,
           control_group == control_i) %>%
    slice(1L)
}

get_sa <- function(sample_i, treatment_i, grain_i) {
  sa_support_summary %>%
    filter(sample == sample_i,
           treatment_definition == treatment_i,
           grain == grain_i) %>%
    slice(1L)
}

fmt_pct <- function(x) sprintf("%.1f%%", 100 * x)
fmt_num <- function(x, digits = 1L) format(round(x, digits), nsmall = digits)

old24_m <- get_design("legacy_exact_24", "embedded_panel_legacy", "monthly")
online24_m <- get_design("legacy_exact_24", "online_updated", "monthly")
online39_m <- get_design("all_panel_39", "online_updated", "monthly")
handle39_m <- get_design(
  "all_panel_39_handle_eligible",
  "handle50_updated",
  "monthly"
)
online26_m <- get_design("current_exact_26", "online_updated", "monthly")
online26_y <- get_design("current_exact_26", "online_updated", "annual")
first26_m <- get_design("current_exact_26", "first_updated", "monthly")
retail26_m <- get_design("current_exact_26", "retail_updated", "monthly")
handle26_m <- get_design(
  "current_exact_26_handle_eligible",
  "handle50_updated",
  "monthly"
)
handle26_y <- get_design(
  "current_exact_26_handle_eligible",
  "handle50_updated",
  "annual"
)
handle_old26_m <- get_design(
  "current_exact_26", "handle50_previous_build", "monthly"
)
online_cs <- get_cs(
  "current_exact_26", "online_updated", "monthly", "not_yet_treated"
)
handle_cs <- get_cs(
  "current_exact_26_handle_eligible", "handle50_updated", "monthly",
  "not_yet_treated"
)
online_sa <- get_sa("current_exact_26", "online_updated", "monthly")
handle_sa <- get_sa(
  "current_exact_26_handle_eligible",
  "handle50_updated",
  "monthly"
)

online_new_states_24 <- date_comparison %>%
  filter(is_current_exact_sample,
         !(state_abb %in% LEGACY_EXCLUDE_STATES),
         is.na(embedded_panel_legacy), !is.na(online_updated)) %>%
  pull(state_abb)

online_removed_states_24 <- date_comparison %>%
  filter(is_current_exact_sample,
         !(state_abb %in% LEGACY_EXCLUDE_STATES),
         !is.na(embedded_panel_legacy), is.na(online_updated)) %>%
  pull(state_abb)

handle_changes <- date_comparison %>%
  filter(is_current_exact_sample,
         previous_to_updated_handle50_changed) %>%
  transmute(label = paste0(state_abb, " (",
                           if_else(is.na(handle50_previous_build), "never",
                                   format(handle50_previous_build, "%Y-%m")),
                           " -> ",
                           if_else(is.na(handle50_updated), "never",
                                   format(handle50_updated, "%Y-%m")), ")")) %>%
  pull(label)

summary_lines <- c(
  "# Updated legalization and Handle cohort-support diagnostic",
  "",
  "## Pre-Code Report",
  "",
  "**Strategy memo:** `docs/literature_review_2026-07_estimation_strategy.md` (estimation-strategy reassessment; no separate approved strategist memo/critic score found)",
  "**Domain profile:** loaded from `.claude/references/domain-profile.md`",
  "**Language:** R (from `AGENTS.md`)",
  "**Paper type:** reduced-form",
  "",
  "**Identification strategy:** Staggered state-level DiD of sports-gambling access on eviction outcomes; this script diagnoses support for CS group-time ATTs and Sun-Abraham relative-time coefficients without fitting outcome models.",
  "",
  "**Key variables:**",
  "- Outcome: $Y_{st}$ eviction filings per 1,000 renters -> `filings_per_1k_renters` (panel skeleton only)",
  "- Treatment: $G_s$ -> `cohort_month`, under updated online, first, retail, and Handle-50 definitions",
  "- Event time: $e=t-G_s$ -> `event_time`",
  "- Controls: eligible never-treated and not-yet-treated states; Handle support excludes states with missing exposure or pre-sample treatment",
  "- Fixed effects: none estimated; target estimators use state and calendar-period effects",
  "- Clustering: state",
  "",
  "**Data source:** the state eviction panel, updated legalization schedule, updated LSR Handle-50 treatment panel, and explicit Handle state classification.",
  "**Estimator:** Callaway-Sant'Anna and Sun-Abraham support only; no point estimates, standard errors, p-values, or significance levels are produced.",
  "**Robustness checks:** all 39 observed states for legal-date definitions; classification-eligible Handle subsets; current balanced and legacy samples; monthly versus annual cohorts; never-treated versus not-yet-treated controls; relative-time support.",
  "**Naming map confirms:** yes.",
  "",
  "Proceeding to implementation.",
  "",
  "The project references were loaded from `.claude/references/`; the `.Codex/references/` paths named in the generic coder instructions were not present.",
  "",
  "## Bottom line",
  "",
  paste0(
    "The updated dates do **not solve the small-cohort problem**. They make the current monthly design more fragmented: the current exact sample has ",
    online26_m$n_treated, " online-treated states spread over ", online26_m$n_cohorts,
    " monthly cohorts; ", online26_m$n_singleton_cohorts, " cohorts are singletons and ",
    fmt_pct(online26_m$share_treated_states_in_cohorts_lt5),
    " of treated states belong to cohorts smaller than five."
  ),
  paste0(
    "Across all 39 states appearing in the 2016-2024 panel, the updated online definition yields ",
    online39_m$n_treated, " treated states in ", online39_m$n_cohorts,
    " monthly cohorts. After excluding Florida (online-treated but missing Handle) and Nevada (pre-sample treated), the 37-state Handle-eligible sample yields ",
    handle39_m$n_treated, " treated states in ", handle39_m$n_cohorts,
    " cohorts and ", handle39_m$n_never_treated,
    " eligible controls. CS/SA support uses each state's actually observed months because this panel is unbalanced."
  ),
  paste0(
    "Moving treatment from legal access to 50% of the frozen non-COVID peak Handle only modestly pools states. In the Handle-eligible subset of the current balanced base sample (",
    handle26_m$n_states, " states), it produces ",
    handle26_m$n_treated, " treated states in ", handle26_m$n_cohorts,
    " monthly cohorts, with ", handle26_m$n_singleton_cohorts,
    " singleton cohorts and ", fmt_pct(handle26_m$share_treated_states_in_cohorts_lt5),
    " of treated states in groups smaller than five."
  ),
  paste0(
    "Annualizing treatment timing helps mechanically, although these comparison rows use ",
    online26_y$n_states, " states for online dates and ", handle26_y$n_states,
    " Handle-eligible states. Online dates collapse to ",
    online26_y$n_cohorts, " annual cohorts (largest cohort ", online26_y$largest_cohort,
    "), while Handle-50 dates collapse to ", handle26_y$n_cohorts,
    " annual cohorts (largest cohort ", handle26_y$largest_cohort,
    "). But ", fmt_pct(online26_y$share_treated_states_in_cohorts_lt5),
    " of online-treated states and ", fmt_pct(handle26_y$share_treated_states_in_cohorts_lt5),
    " of Handle-50-treated states still lie in annual cohorts smaller than five."
  ),
  "",
  "## What changed relative to the prior design",
  "",
  paste0(
    "On the legacy 24-state sample, the embedded schedule had ", old24_m$n_treated,
    " treated states, ", old24_m$n_never_treated, " never-treated controls, and ",
    old24_m$n_cohorts, " monthly cohorts. The updated online schedule has ",
    online24_m$n_treated, " treated states, ", online24_m$n_never_treated,
    " never-treated controls, and ", online24_m$n_cohorts, " cohorts. Newly treated states are: ",
    if (length(online_new_states_24) > 0L) paste(online_new_states_24, collapse = ", ") else "none",
    "; states removed from treatment because they are retail-only are: ",
    if (length(online_removed_states_24) > 0L) {
      paste(online_removed_states_24, collapse = ", ")
    } else {
      "none"
    }, "."
  ),
  paste0(
    "The current default exact sample adds repaired Maine and Idaho, yielding ",
    online26_m$n_states, " states: ", online26_m$n_treated, " treated and ",
    online26_m$n_never_treated, " never treated. This adds clusters, but not a large repeated cohort: the largest monthly online cohort has only ",
    online26_m$largest_cohort, " states."
  ),
  paste0(
    "The current 50%-Handle build changes ", lag_current$updated_handle50_changes_vs_previous_build,
    " dates/statuses relative to the immediately prior build",
    if (length(handle_changes) > 0L) paste0(": ", paste(handle_changes, collapse = "; "), ".") else "."
  ),
  paste0(
    "Among the ", lag_current$states_with_online_and_handle50,
    " current-sample states with both dates, 50% of peak is reached a median ",
    fmt_num(lag_current$median_months_online_to_handle50, 1L),
    " months after online launch (range ", lag_current$min_months_online_to_handle50,
    " to ", lag_current$max_months_online_to_handle50, "). The reshuffling reduces the number of monthly cohorts somewhat, but not enough to create any cohort of five states."
  ),
  paste0(
    "The estimator-ready Handle panel now excludes rather than recodes problematic states: ",
    paste(
      paste0(
        handle_exclusions$state_abb,
        " (`", handle_exclusions$handle_treatment_status, "`)"
      ),
      collapse = "; "
    ),
    ". Missouri remains an eligible control because its online start is after the 2024-12 study cutoff."
  ),
  "",
  "## Consequences for Callaway-Sant'Anna",
  "",
  paste0(
    "With not-yet-treated controls, all mechanically defined post-treatment group-time cells retain at least one control in the balanced sample: ",
    online_cs$n_supported_cells, "/", online_cs$n_post_group_time_cells,
    " for updated online dates and ", handle_cs$n_supported_cells, "/",
    handle_cs$n_post_group_time_cells, " for Handle-50. Formal existence is therefore not the main problem."
  ),
  paste0(
    "The problem is weak cluster support inside the treated side of each ATT(g,t): ",
    fmt_pct(online_cs$share_cells_with_treated_group_lt5),
    " of online-date cells and ", fmt_pct(handle_cs$share_cells_with_treated_group_lt5),
    " of Handle-50 cells inherit a treatment cohort smaller than five states. The same small state group is reused at every post-treatment t, so extra months do not create extra independent treated clusters."
  ),
  paste0(
    "The updated online design ends with only ", online_cs$min_controls,
    " not-yet/never-treated controls; Handle-50 ends with ", handle_cs$min_controls,
    ". Updated dates thus modestly shrink the late-period control reservoir while adding mostly singleton treated cohorts."
  ),
  "",
  "## Consequences for Sun-Abraham",
  "",
  paste0(
    "Sun-Abraham aggregates cohort-by-relative-time interactions, but far leads and lags are supported by progressively fewer states. For online treatment, the first nonnegative monthly event time supported by fewer than five treated states is e=",
    online_sa$first_post_event_time_with_lt5_states,
    "; the last post-treatment e with at least five states is ",
    online_sa$last_post_event_time_with_at_least5_states, "."
  ),
  paste0(
    "For Handle-50, the first post-treatment monthly e with fewer than five states is e=",
    handle_sa$first_post_event_time_with_lt5_states,
    "; the last e with at least five states is ",
    handle_sa$last_post_event_time_with_at_least5_states,
    ". See `sa_focus_horizons.csv` for exact counts at commonly plotted horizons."
  ),
  "The interaction-weighted aggregation prevents forbidden comparisons, but it cannot manufacture independent clusters. Long-horizon coefficients remain high-leverage combinations of a few states, which is the project’s existing calibration concern for SA.",
  "",
  "## Treatment-definition comparison (current exact base sample, monthly)",
  "",
  "| Definition | Treated | Never | Cohorts | Singleton cohorts | Largest cohort | Treated states in cohorts <5 |",
  "|---|---:|---:|---:|---:|---:|---:|",
  paste0("| Updated online | ", online26_m$n_treated, " | ", online26_m$n_never_treated,
         " | ", online26_m$n_cohorts, " | ", online26_m$n_singleton_cohorts,
         " | ", online26_m$largest_cohort, " | ",
         fmt_pct(online26_m$share_treated_states_in_cohorts_lt5), " |"),
  paste0("| Updated first | ", first26_m$n_treated, " | ", first26_m$n_never_treated,
         " | ", first26_m$n_cohorts, " | ", first26_m$n_singleton_cohorts,
         " | ", first26_m$largest_cohort, " | ",
         fmt_pct(first26_m$share_treated_states_in_cohorts_lt5), " |"),
  paste0("| Updated retail | ", retail26_m$n_treated, " | ", retail26_m$n_never_treated,
         " | ", retail26_m$n_cohorts, " | ", retail26_m$n_singleton_cohorts,
         " | ", retail26_m$largest_cohort, " | ",
         fmt_pct(retail26_m$share_treated_states_in_cohorts_lt5), " |"),
  paste0("| Prior Handle-50 build | ", handle_old26_m$n_treated, " | ",
         handle_old26_m$n_never_treated, " | ", handle_old26_m$n_cohorts,
         " | ", handle_old26_m$n_singleton_cohorts, " | ",
         handle_old26_m$largest_cohort, " | ",
         fmt_pct(handle_old26_m$share_treated_states_in_cohorts_lt5), " |"),
  paste0("| Updated Handle-50 | ", handle26_m$n_treated, " | ", handle26_m$n_never_treated,
         " | ", handle26_m$n_cohorts, " | ", handle26_m$n_singleton_cohorts,
         " | ", handle26_m$largest_cohort, " | ",
         fmt_pct(handle26_m$share_treated_states_in_cohorts_lt5), " |"),
  "",
  "## Interpretation and recommendation",
  "",
  "- Keep CS and SA as heterogeneity-robust diagnostics/robustness estimators, but do not treat conventional clustered inference as automatically reliable in singleton and very small cohorts.",
  "- Pre-specify a supported event window using `sa_event_time_support.csv`; bin or omit tails where fewer than five treated states contribute, and show the state count under every plotted coefficient.",
  "- Annualizing reduces the number of cohorts, but it is a precision-versus-timing tradeoff and does not fully cure small groups. Do not annualize solely to obtain larger cohort labels without acknowledging loss of monthly treatment timing.",
  "- The Handle-50 date is an intensity/maturation estimand, not a cleaner version of legalization. Its heterogeneous lag shifts composition across event time and is post-treatment by construction, so it is best framed as a complementary exposure definition rather than the primary legal-access treatment.",
  "- Continue the project’s calibrated did2s headline and use state-level wild bootstrap/randomization inference where applicable. The support tables here explain why adding updated treatment dates does not overturn that estimator ordering.",
  "",
  "## Reproducibility and artifacts",
  "",
  paste0("- Exact current sample: ", n_distinct(panel_current$state_abb), " states x ",
         n_distinct(panel_current$month_date), " observed months = ",
         format(nrow(panel_current), big.mark = ","), " observations."),
  paste0(
    "- Estimator-ready Handle panel: ",
    n_distinct(handle_panel_raw$state_abb), " states, ",
    format(nrow(handle_panel_raw), big.mark = ","),
    " observations; excluded states are exported in `handle_analysis_exclusions.csv`."
  ),
  paste0("- Dates: ", MIN_DATE, " through ", MAX_DATE, "; excluded ",
         COVID_START, " through ", COVID_END, "."),
  "- Every CSV has a same-named RDS, plus saved analysis panels, schedules, and a combined `all_support_diagnostics.rds`.",
  "- No outcome model was fitted, so point estimates, standard errors, and significance levels are not applicable.",
  "",
  "## Paper-to-Code Naming Map",
  "",
  "| Paper notation | Code name | Description |",
  "|---|---|---|",
  "| $Y_{st}$ | `filings_per_1k_renters` | Eviction filings per 1,000 renters |",
  "| $G_s$ | `cohort_value` / `cohort_label` | First-treated month or year |",
  "| $e=t-G_s$ | `event_time` | Relative month or year |",
  "| $ATT(g,t)$ | `cs_group_time_support` | CS group-time comparison cell |",
  "| $\\theta_e$ | `sa_event_time_support` | Sun-Abraham relative-time coefficient support |"
)

writeLines(summary_lines, file.path(OUT_DIR, "results_summary.md"))

message("Handle/legalization cohort-support diagnostic complete.")
message("  Current sample: ", n_distinct(panel_current$state_abb),
        " states, ", n_distinct(panel_current$month_date), " months")
message("  Outputs: ", OUT_DIR)
