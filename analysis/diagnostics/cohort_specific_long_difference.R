#!/usr/bin/env Rscript
# ==============================================================================
# cohort_specific_long_difference.R
# Cohort-specific long differences for staggered online-gambling adoption
#
# Inputs:
#   data/raw/monthly_county_data_download.csv
#   data/raw/sports_gambling_legalization_dates.csv
# Outputs:
#   output/border_diagnostic/cohort_specific_long_difference/*
#
# This is a transparent cohort-calendar long-difference design. It is not an
# implementation of the formal Lee-Wooldridge transformation estimator.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(here)
  library(lubridate)
})

SEED <- 20260803L
ALPHA <- 0.05
MIN_COUNTIES <- 5L
DROP_STATES <- c("ME", "NH")
COVID_START <- as.IDate("2020-03-01")
COVID_END <- as.IDate("2022-03-01")

set.seed(SEED)

OUT_DIR <- here(
  "output", "border_diagnostic", "cohort_specific_long_difference"
)
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# ============================================================
# Paper-to-Code Naming Map
# ============================================================
# Paper Notation | Code Name     | Description
# Y_it           | y, y_rate     | Log filings and log filings rate
# G_i            | treat_start   | First online-treatment month
# DeltaY_i(g,h)  | state_change  | State long difference in cohort calendar
# ATT(g,h)       | att_gh        | Cohort-by-horizon contrast
# ATT(h)         | att_h         | Equal-treated-state aggregate contrast
# ============================================================

state_fips_xwalk <- data.table(
  state_fips = c(
    1L, 2L, 4L, 5L, 6L, 8L, 9L, 10L, 11L, 12L, 13L, 15L,
    16L, 17L, 18L, 19L, 20L, 21L, 22L, 23L, 24L, 25L, 26L,
    27L, 28L, 29L, 30L, 31L, 32L, 33L, 34L, 35L, 36L, 37L,
    38L, 39L, 40L, 41L, 42L, 44L, 45L, 46L, 47L, 48L, 49L,
    50L, 51L, 53L, 54L, 55L, 56L
  ),
  state_abb = c(
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC",
    "FL", "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY",
    "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT",
    "NE", "NV", "NH", "NJ", "NM", "NY", "NC", "ND", "OH",
    "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT",
    "VT", "VA", "WA", "WV", "WI", "WY"
  )
)

state_name_xwalk <- data.table(
  state = c(state.name, "District of Columbia"),
  state_abb = c(state.abb, "DC")
)

horizon_definitions <- data.table(
  horizon = c("placebo", "months_0_11", "months_12_23", "months_24_35"),
  pre_start = c(-30L, -30L, -30L, -30L),
  pre_end = c(-19L, -7L, -7L, -7L),
  post_start = c(-18L, 0L, 12L, 24L),
  post_end = c(-7L, 11L, 23L, 35L),
  pre_total = c(12L, 24L, 24L, 24L),
  post_total = c(12L, 12L, 12L, 12L),
  is_placebo = c(TRUE, FALSE, FALSE, FALSE)
)

specifications <- data.table(
  specification = c(
    "primary", "not_yet_controls", "rate_outcome",
    "renter_weighted", "strict_coverage", "complete_coverage",
    "online_first_clean"
  ),
  outcome = c("y", "y", "y_rate", "y", "y", "y", "y"),
  control_group = c(
    "never", "not_yet", "never", "never", "never", "never",
    "never_any"
  ),
  state_weight = c("equal_county", "equal_county", "equal_county",
                   "renter", "equal_county", "equal_county",
                   "equal_county"),
  pre_fraction = c(0.50, 0.50, 0.50, 0.50, 0.75, 1.00, 0.50),
  post_fraction = c(0.50, 0.50, 0.50, 0.50, 0.75, 1.00, 0.50),
  treated_regime = c(
    "all_online", "all_online", "all_online", "all_online",
    "all_online", "all_online", "online_first_or_simultaneous"
  )
)

#' Add an integer number of months to a monthly date.
#'
#' @param date A date coercible to Date.
#' @param offset Integer number of months.
#' @return IDate at the first day of the resulting month.
add_months <- function(date, offset) {
  as.IDate(as.Date(date) %m+% months(as.integer(offset)))
}

#' Return whether two closed date intervals overlap.
#'
#' @param start First date of the interval.
#' @param end Last date of the interval.
#' @return Logical scalar.
overlaps_covid <- function(start, end) {
  isTRUE(start <= COVID_END && end >= COVID_START)
}

#' Safely calculate a finite mean.
#'
#' @param x Numeric vector.
#' @return Finite mean or NA_real_.
safe_mean <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) == 0L) {
    return(NA_real_)
  }
  mean(x)
}

#' Collapse county changes to state changes for one cohort calendar.
#'
#' @param panel County-month data.table.
#' @param cohort_start Cohort treatment month.
#' @param horizon_row One-row horizon definition.
#' @param spec_row One-row specification definition.
#' @return data.table with one row per state and cohort calendar.
build_state_changes <- function(
  panel,
  cohort_start,
  horizon_row,
  spec_row
) {
  stopifnot(is.data.table(panel))
  stopifnot(nrow(horizon_row) == 1L, nrow(spec_row) == 1L)

  pre_start_date <- add_months(cohort_start, horizon_row[["pre_start"]])
  pre_end_date <- add_months(cohort_start, horizon_row[["pre_end"]])
  post_start_date <- add_months(cohort_start, horizon_row[["post_start"]])
  post_end_date <- add_months(cohort_start, horizon_row[["post_end"]])
  outcome_name <- spec_row[["outcome"]]

  pre_required <- as.integer(ceiling(
    horizon_row[["pre_total"]] * spec_row[["pre_fraction"]]
  ))
  post_required <- as.integer(ceiling(
    horizon_row[["post_total"]] * spec_row[["post_fraction"]]
  ))

  period_data <- panel[
    (month_date >= pre_start_date & month_date <= pre_end_date) |
      (month_date >= post_start_date & month_date <= post_end_date)
  ]
  if (nrow(period_data) == 0L) {
    return(data.table())
  }

  period_data[, period := fifelse(
    month_date >= pre_start_date & month_date <= pre_end_date,
    "pre", "post"
  )]
  period_data <- period_data[is.finite(get(outcome_name))]
  if (nrow(period_data) == 0L) {
    return(data.table())
  }

  county_period <- period_data[, .(
    outcome_mean = safe_mean(get(outcome_name)),
    renter_mean = safe_mean(renter_units),
    n_months = uniqueN(month_date)
  ), by = .(state_abb, fips, treat_start, period)]

  county_wide <- dcast(
    county_period,
    state_abb + fips + treat_start ~ period,
    value.var = c("outcome_mean", "renter_mean", "n_months")
  )
  required_names <- c(
    "outcome_mean_pre", "outcome_mean_post", "renter_mean_pre",
    "n_months_pre", "n_months_post"
  )
  if (!all(required_names %in% names(county_wide))) {
    return(data.table())
  }

  county_wide <- county_wide[
    n_months_pre >= pre_required & n_months_post >= post_required &
      is.finite(outcome_mean_pre) & is.finite(outcome_mean_post)
  ]
  if (nrow(county_wide) == 0L) {
    return(data.table())
  }
  county_wide[, county_change := outcome_mean_post - outcome_mean_pre]
  county_wide[, renter_weight := fifelse(
    is.finite(renter_mean_pre) & renter_mean_pre > 0,
    renter_mean_pre,
    NA_real_
  )]

  if (identical(spec_row[["state_weight"]], "renter")) {
    state_changes <- county_wide[is.finite(renter_weight), .(
      state_change = weighted.mean(county_change, renter_weight),
      n_counties = .N,
      renter_weight_sum = sum(renter_weight)
    ), by = .(state_abb, treat_start)]
  } else {
    state_changes <- county_wide[, .(
      state_change = safe_mean(county_change),
      n_counties = .N,
      renter_weight_sum = sum(renter_weight, na.rm = TRUE)
    ), by = .(state_abb, treat_start)]
  }
  state_changes <- state_changes[is.finite(state_change)]

  state_metadata <- unique(panel[, .(
    state_abb,
    first_start_date,
    retail_start_date,
    online_regime
  )])
  state_changes <- merge(
    state_changes,
    state_metadata,
    by = "state_abb",
    all.x = TRUE,
    sort = FALSE
  )

  treated_states <- panel[
    !is.na(treat_start) & treat_start == cohort_start,
    .(state_abb, online_regime)
  ]
  treated_states <- unique(treated_states)
  if (identical(
    spec_row[["treated_regime"]],
    "online_first_or_simultaneous"
  )) {
    treated_states <- treated_states[
      online_regime == "online_first_or_simultaneous"
    ]
  }
  treated_states <- treated_states[["state_abb"]]
  is_placebo <- horizon_row[["is_placebo"]]
  eligibility_end <- if (is_placebo) post_end_date else post_end_date

  state_changes[, is_treated_cohort := state_abb %chin% treated_states]
  if (identical(spec_row[["control_group"]], "never")) {
    state_changes[, is_control := is.na(treat_start)]
  } else if (identical(spec_row[["control_group"]], "not_yet")) {
    state_changes[, is_control :=
      !is_treated_cohort &
        (is.na(treat_start) | treat_start > eligibility_end)]
  } else if (identical(spec_row[["control_group"]], "never_any")) {
    state_changes[, is_control :=
      !is_treated_cohort &
        (is.na(first_start_date) | first_start_date > eligibility_end)]
  } else {
    stop("Unknown control group: ", spec_row[["control_group"]])
  }
  state_changes[, `:=`(
    cohort_start = as.IDate(cohort_start),
    horizon = horizon_row[["horizon"]],
    specification = spec_row[["specification"]],
    pre_start_date = pre_start_date,
    pre_end_date = pre_end_date,
    post_start_date = post_start_date,
    post_end_date = post_end_date,
    pre_required = pre_required,
    post_required = post_required
  )]
  state_changes[]
}

#' Estimate cohort-specific contrasts from state changes.
#'
#' @param state_cells State/cohort/horizon changes.
#' @param drop_state Optional state to omit.
#' @param allowed_treated Optional fixed treated-state composition.
#' @return data.table with one row per supported cohort cell.
estimate_cells <- function(
  state_cells,
  drop_state = NA_character_,
  allowed_treated = NULL
) {
  stopifnot(is.data.table(state_cells))
  data <- state_cells
  if (!is.na(drop_state)) {
    data <- data[state_abb != drop_state]
  }
  if (!is.null(allowed_treated)) {
    data <- data[!is_treated_cohort | state_abb %chin% allowed_treated]
  }
  if (nrow(data) == 0L) {
    return(data.table())
  }

  cell_estimates <- data[, {
    treated <- .SD[is_treated_cohort == TRUE]
    controls <- .SD[is_control == TRUE]
    if (nrow(treated) == 0L || nrow(controls) == 0L) {
      list(
        is_supported = FALSE,
        att_gh = NA_real_,
        n_treated_states = nrow(treated),
        n_control_states = nrow(controls),
        n_treated_counties = sum(treated[["n_counties"]]),
        n_control_counties = sum(controls[["n_counties"]]),
        treated_states = paste(sort(treated[["state_abb"]]), collapse = ";"),
        control_states = paste(sort(controls[["state_abb"]]), collapse = ";")
      )
    } else {
      list(
        is_supported = TRUE,
        att_gh = mean(treated[["state_change"]]) -
          mean(controls[["state_change"]]),
        n_treated_states = nrow(treated),
        n_control_states = nrow(controls),
        n_treated_counties = sum(treated[["n_counties"]]),
        n_control_counties = sum(controls[["n_counties"]]),
        treated_states = paste(sort(treated[["state_abb"]]), collapse = ";"),
        control_states = paste(sort(controls[["state_abb"]]), collapse = ";")
      )
    }
  }, by = .(
    specification, horizon, cohort_start, pre_start_date, pre_end_date,
    post_start_date, post_end_date
  )]
  cell_estimates[]
}

#' Aggregate supported cells with equal treated-state weights.
#'
#' @param state_cells State/cohort/horizon changes.
#' @param specification_name Specification to retain.
#' @param horizon_name Horizon to retain.
#' @param drop_state Optional state to omit.
#' @param allowed_treated Optional fixed treated-state composition.
#' @return Named list containing aggregate estimate and cell details.
estimate_aggregate <- function(
  state_cells,
  specification_name,
  horizon_name,
  drop_state = NA_character_,
  allowed_treated = NULL
) {
  subset <- state_cells[
    specification == specification_name & horizon == horizon_name
  ]
  cells <- estimate_cells(subset, drop_state, allowed_treated)
  cells <- cells[is_supported & is.finite(att_gh)]
  if (nrow(cells) == 0L || sum(cells[["n_treated_states"]]) == 0L) {
    return(list(estimate = NA_real_, cells = cells))
  }
  estimate <- weighted.mean(
    cells[["att_gh"]],
    w = cells[["n_treated_states"]]
  )
  list(estimate = estimate, cells = cells)
}

#' Identify treated states supported in all three post horizons.
#'
#' @param state_cells State/cohort/horizon changes for one specification.
#' @param specification_name Specification to retain.
#' @return Character vector of supported treated states.
find_common_treated <- function(state_cells, specification_name) {
  post_horizons <- c("months_0_11", "months_12_23", "months_24_35")
  data <- state_cells[
    specification == specification_name &
      horizon %chin% post_horizons & is_treated_cohort
  ]
  if (nrow(data) == 0L) {
    return(character())
  }
  support <- data[, .(n_horizons = uniqueN(horizon)), by = state_abb]
  support[n_horizons == length(post_horizons), state_abb]
}

#' Calculate delete-one-state jackknife inference.
#'
#' @param state_cells Full state-cell data.
#' @param specification_name Specification name.
#' @param horizon_name Horizon name.
#' @param aggregation_sample Available or common-post composition.
#' @param allowed_treated Optional fixed treated-state composition.
#' @return Named list with summary and replicate data.table.
jackknife_aggregate <- function(
  state_cells,
  specification_name,
  horizon_name,
  aggregation_sample,
  allowed_treated = NULL
) {
  base <- estimate_aggregate(
    state_cells,
    specification_name,
    horizon_name,
    allowed_treated = allowed_treated
  )
  base_estimate <- base[["estimate"]]
  if (!is.finite(base_estimate)) {
    return(list(summary = NULL, replicates = data.table()))
  }

  base_cells <- base[["cells"]]
  cohorts <- base_cells[["cohort_start"]]
  relevant <- state_cells[
    specification == specification_name & horizon == horizon_name &
      cohort_start %in% cohorts & (is_treated_cohort | is_control)
  ]
  if (!is.null(allowed_treated)) {
    relevant <- relevant[
      !is_treated_cohort | state_abb %chin% allowed_treated
    ]
  }
  jackknife_states <- sort(unique(relevant[["state_abb"]]))
  n_states <- length(jackknife_states)
  if (n_states == 0L) {
    return(list(summary = NULL, replicates = data.table()))
  }

  estimates <- vapply(
    jackknife_states,
    \(state) estimate_aggregate(
      state_cells,
      specification_name,
      horizon_name,
      drop_state = state,
      allowed_treated = allowed_treated
    )[["estimate"]],
    numeric(1L)
  )
  replicates <- data.table(
    specification = specification_name,
    horizon = horizon_name,
    aggregation_sample = aggregation_sample,
    dropped_state = jackknife_states,
    estimate_leave_one_out = estimates,
    base_estimate = base_estimate
  )
  replicates[, influence := estimate_leave_one_out - base_estimate]
  replicates[, is_valid := is.finite(estimate_leave_one_out)]

  valid <- replicates[is_valid == TRUE]
  n_valid <- nrow(valid)
  jackknife_se <- NA_real_
  df <- NA_integer_
  ci_low <- NA_real_
  ci_high <- NA_real_
  p_value <- NA_real_
  max_influence <- NA_real_
  max_influence_state <- NA_character_
  if (n_valid >= 2L) {
    valid_mean <- mean(valid[["estimate_leave_one_out"]])
    jackknife_se <- sqrt(
      ((n_valid - 1L) / n_valid) *
        sum((valid[["estimate_leave_one_out"]] - valid_mean)^2)
    )
    df <- n_valid - 1L
    if (is.finite(jackknife_se) && jackknife_se > 0) {
      critical <- qt(1 - ALPHA / 2, df = df)
      ci_low <- base_estimate - critical * jackknife_se
      ci_high <- base_estimate + critical * jackknife_se
      p_value <- 2 * pt(-abs(base_estimate / jackknife_se), df = df)
      p_value <- pmin(pmax(p_value, 0), 1)
    }
    max_row <- valid[which.max(abs(influence))]
    max_influence <- abs(max_row[["influence"]])
    max_influence_state <- max_row[["dropped_state"]]
  }

  summary <- data.table(
    specification = specification_name,
    horizon = horizon_name,
    aggregation_sample = aggregation_sample,
    att_h = base_estimate,
    jackknife_se = jackknife_se,
    ci_low = ci_low,
    ci_high = ci_high,
    p_value = p_value,
    pct_effect = 100 * expm1(base_estimate),
    pct_ci_low = 100 * expm1(ci_low),
    pct_ci_high = 100 * expm1(ci_high),
    n_cohorts = nrow(base_cells),
    n_treated_states = sum(base_cells[["n_treated_states"]]),
    n_control_states_union = uniqueN(
      relevant[is_control == TRUE, state_abb]
    ),
    n_jackknife_states = n_states,
    n_valid_replicates = n_valid,
    jackknife_df = df,
    max_abs_influence = max_influence,
    max_influence_state = max_influence_state,
    covid_any = any(mapply(
      \(a, b, c, d) overlaps_covid(a, b) || overlaps_covid(c, d),
      base_cells[["pre_start_date"]],
      base_cells[["pre_end_date"]],
      base_cells[["post_start_date"]],
      base_cells[["post_end_date"]]
    ))
  )
  list(summary = summary, replicates = replicates)
}

# 1. Data loading and sample construction -------------------------------------

county_path <- here("data", "raw", "monthly_county_data_download.csv")
treatment_path <- here(
  "data", "raw", "sports_gambling_legalization_dates.csv"
)
if (!file.exists(county_path)) {
  stop("County-month input not found: ", county_path)
}
if (!file.exists(treatment_path)) {
  stop("Treatment input not found: ", treatment_path)
}

county_raw <- fread(county_path)
raw_n_rows <- nrow(county_raw)
raw_n_states <- uniqueN(as.integer(county_raw[["fips"]]) %/% 1000L)
county_raw[, `:=`(
  fips = as.integer(fips),
  state_fips = as.integer(fips) %/% 1000L,
  month_date = as.IDate(substr(as.character(date), 1L, 10L)),
  filings_count = as.numeric(filings_count),
  renter_units = as.numeric(renter_occupied_housing_units)
)]
county_raw <- merge(
  county_raw,
  state_fips_xwalk,
  by = "state_fips",
  all.x = TRUE,
  sort = FALSE
)
county_raw <- county_raw[
  !is.na(state_abb) & !is.na(month_date) & !state_abb %chin% DROP_STATES
]
crosswalk_n_rows <- nrow(county_raw)

county_counts <- unique(county_raw[, .(state_abb, fips)])[ 
  , .(n_counties = .N), by = state_abb
]
eligible_states <- county_counts[
  n_counties >= MIN_COUNTIES, state_abb
]
county_raw <- county_raw[state_abb %chin% eligible_states]
restricted_n_rows <- nrow(county_raw)

treatment_raw <- fread(treatment_path)
required_treatment_columns <- c(
  "state", "first_start_date", "online_start_date",
  "retail_start_date", "has_online"
)
if (!all(required_treatment_columns %in% names(treatment_raw))) {
  stop(
    "Online-treatment file lacks required columns: ",
    paste(
      setdiff(required_treatment_columns, names(treatment_raw)),
      collapse = ", "
    )
  )
}
treatment_raw[, `:=`(
  first_start_date = as.IDate(first_start_date),
  online_start_date = as.IDate(online_start_date),
  retail_start_date = as.IDate(retail_start_date)
)]
treatment_state <- merge(
  treatment_raw[, .(
    state,
    first_start_date,
    online_start_date,
    retail_start_date,
    has_online
  )],
  state_name_xwalk,
  by = "state",
  all.x = TRUE,
  sort = FALSE
)
if (anyNA(treatment_state[["state_abb"]])) {
  stop(
    "State-name crosswalk failed for: ",
    paste(
      treatment_state[is.na(state_abb), state],
      collapse = ", "
    )
  )
}
treatment_state[, treat_start := online_start_date]
treatment_state[, online_regime := fcase(
  is.na(online_start_date), "no_online",
  !is.na(retail_start_date) & retail_start_date < online_start_date,
  "retail_first",
  default = "online_first_or_simultaneous"
)]
treatment_state <- treatment_state[, .(
  state_abb,
  treat_start,
  online_start_date,
  retail_start_date,
  first_start_date,
  has_online,
  online_regime
)]

panel <- merge(
  county_raw,
  treatment_state,
  by = "state_abb",
  all.x = TRUE,
  sort = FALSE
)
panel[is.na(has_online), has_online := FALSE]
panel[is.na(online_regime), online_regime := "no_online"]
panel[, y := log1p(pmax(filings_count, 0))]
panel[, filings_per_1k := fifelse(
  is.finite(renter_units) & renter_units > 0,
  1000 * pmax(filings_count, 0) / renter_units,
  NA_real_
)]
panel[, y_rate := log1p(pmax(filings_per_1k, 0))]
panel[!is.finite(y), y := NA_real_]
panel[!is.finite(y_rate), y_rate := NA_real_]
setorder(panel, state_abb, fips, month_date)

cohorts <- sort(unique(panel[!is.na(treat_start), treat_start]))
if (length(cohorts) == 0L) {
  stop("No treated cohorts found after sample restrictions.")
}
states_without_online_launch <- sort(unique(
  panel[is.na(treat_start), state_abb]
))
retail_or_other_without_online <- sort(intersect(
  treatment_state[is.na(treat_start), state_abb],
  unique(panel[["state_abb"]])
))

drop_audit <- data.table(
  stage = c(
    "raw county rows", "after state crosswalk and ME/NH drop",
    "after >=5-county restriction", "final joined panel"
  ),
  n_rows = c(
    raw_n_rows,
    crosswalk_n_rows,
    restricted_n_rows,
    nrow(panel)
  ),
  note = c(
    sprintf("%d raw state FIPS values", raw_n_states),
    "Invalid state matches plus ME/NH removed",
    sprintf("%d states retained", length(eligible_states)),
    sprintf("%d counties retained", uniqueN(panel[["fips"]]))
  )
)

analysis_summary <- panel[, .(
  n_rows = .N,
  n_states = uniqueN(state_abb),
  n_counties = uniqueN(fips),
  n_treated_states = uniqueN(state_abb[!is.na(treat_start)]),
  n_never_states = uniqueN(state_abb[is.na(treat_start)]),
  y_mean = safe_mean(y),
  y_median = median(y, na.rm = TRUE),
  y_sd = sd(y, na.rm = TRUE),
  y_rate_mean = safe_mean(y_rate),
  y_rate_median = median(y_rate, na.rm = TRUE),
  y_rate_sd = sd(y_rate, na.rm = TRUE),
  first_month = min(month_date),
  last_month = max(month_date)
)]

message("Final panel summary:")
message(
  sprintf(
    "  %d rows; %d states; %d counties; %d treated states; %d never states",
    analysis_summary[["n_rows"]], analysis_summary[["n_states"]],
    analysis_summary[["n_counties"]],
    analysis_summary[["n_treated_states"]],
    analysis_summary[["n_never_states"]]
  )
)

# 2. Cohort-calendar transformations -----------------------------------------

n_tasks <- nrow(specifications) * nrow(horizon_definitions) * length(cohorts)
state_cell_list <- vector("list", n_tasks)
task_index <- 0L
for (spec_index in seq_len(nrow(specifications))) {
  spec_row <- specifications[spec_index]
  for (horizon_index in seq_len(nrow(horizon_definitions))) {
    horizon_row <- horizon_definitions[horizon_index]
    for (cohort_index in seq_along(cohorts)) {
      task_index <- task_index + 1L
      state_cell_list[[task_index]] <- build_state_changes(
        panel,
        cohorts[[cohort_index]],
        horizon_row,
        spec_row
      )
    }
  }
}
state_cell_changes <- rbindlist(state_cell_list, fill = TRUE)
if (nrow(state_cell_changes) == 0L) {
  stop("No valid state-cell long differences were constructed.")
}

treated_states_observed <- unique(panel[!is.na(treat_start), .(
  cohort_start = treat_start,
  state_abb,
  online_regime,
  merge_key = 1L
)])
specification_horizons <- specifications[, .(
  specification,
  treated_regime,
  merge_key = 1L
)]
specification_horizons <- merge(
  specification_horizons,
  horizon_definitions[, .(horizon, merge_key = 1L)],
  by = "merge_key",
  allow.cartesian = TRUE
)
treated_state_expectations <- merge(
  treated_states_observed,
  specification_horizons,
  by = "merge_key",
  allow.cartesian = TRUE
)
treated_state_expectations[, merge_key := NULL]
treated_state_expectations <- treated_state_expectations[
  treated_regime == "all_online" |
    online_regime == "online_first_or_simultaneous"
]
treated_state_expectations <- merge(
  treated_state_expectations,
  horizon_definitions,
  by = "horizon",
  all.x = TRUE,
  sort = FALSE
)
treated_state_expectations[, `:=`(
  pre_start_date = add_months(cohort_start, pre_start),
  pre_end_date = add_months(cohort_start, pre_end),
  post_start_date = add_months(cohort_start, post_start),
  post_end_date = add_months(cohort_start, post_end)
)]
state_date_support <- panel[, .(
  state_first_month = min(month_date),
  state_last_month = max(month_date)
), by = state_abb]
treated_state_support <- merge(
  treated_state_expectations,
  unique(state_cell_changes[is_treated_cohort == TRUE, .(
    specification,
    horizon,
    cohort_start,
    state_abb,
    n_counties
  )]),
  by = c("specification", "horizon", "cohort_start", "state_abb"),
  all.x = TRUE,
  sort = FALSE
)
treated_state_support <- merge(
  treated_state_support,
  state_date_support,
  by = "state_abb",
  all.x = TRUE,
  sort = FALSE
)
treated_state_support[, is_supported_state := !is.na(n_counties)]
treated_state_support[, exclusion_reason := fcase(
  is_supported_state, "supported",
  post_end_date > state_last_month, "insufficient post follow-up",
  pre_start_date < state_first_month,
  "insufficient clean-pre calendar coverage",
  default = "county-level coverage threshold not met"
)]

regime_support_long <- treated_state_support[
  specification %chin% c("primary", "online_first_clean"),
  .(is_supported = any(is_supported_state)),
  by = .(state_abb, specification, horizon)
]
regime_support_long[, support_name := paste(
  specification,
  horizon,
  sep = "_"
)]
regime_support_wide <- dcast(
  regime_support_long,
  state_abb ~ support_name,
  value.var = "is_supported",
  fill = FALSE
)
online_treated_regime <- merge(
  treatment_state[!is.na(online_start_date), .(
    state_abb,
    online_start_date,
    retail_start_date,
    first_start_date,
    online_regime
  )],
  regime_support_wide,
  by = "state_abb",
  all.x = TRUE,
  sort = FALSE
)
online_treated_regime <- online_treated_regime[
  state_abb %chin% unique(panel[["state_abb"]])
]
online_treated_regime[, clean_design_eligible :=
  online_regime == "online_first_or_simultaneous"]
setorder(online_treated_regime, online_start_date, state_abb)

# 3. Cell support and descriptive cohort estimates ---------------------------

cell_estimates_all <- estimate_cells(state_cell_changes)
cell_estimates_all[, covid_overlap := mapply(
  \(a, b, c, d) overlaps_covid(a, b) || overlaps_covid(c, d),
  pre_start_date, pre_end_date, post_start_date, post_end_date
)]
cell_estimates_all[, pct_effect := 100 * expm1(att_gh)]

expected_cells <- unique(treated_state_expectations[, .(
  specification,
  horizon,
  cohort_start
)])
cohort_state_map <- panel[!is.na(treat_start), .(
  expected_treated_states = paste(sort(unique(state_abb)), collapse = ";")
), by = .(cohort_start = treat_start)]
expected_cells <- merge(
  expected_cells,
  cohort_state_map,
  by = "cohort_start",
  all.x = TRUE,
  sort = FALSE
)
expected_cells <- merge(
  expected_cells,
  horizon_definitions,
  by = "horizon",
  all.x = TRUE,
  sort = FALSE
)
expected_cells[, `:=`(
  pre_start_date = add_months(cohort_start, pre_start),
  pre_end_date = add_months(cohort_start, pre_end),
  post_start_date = add_months(cohort_start, post_start),
  post_end_date = add_months(cohort_start, post_end)
)]

support_by_cell <- merge(
  expected_cells,
  cell_estimates_all,
  by = c(
    "specification", "horizon", "cohort_start", "pre_start_date",
    "pre_end_date", "post_start_date", "post_end_date"
  ),
  all.x = TRUE,
  sort = FALSE
)
support_by_cell[is.na(is_supported), is_supported := FALSE]
support_by_cell[is.na(n_treated_states), n_treated_states := 0L]
support_by_cell[is.na(n_control_states), n_control_states := 0L]
support_by_cell[, exclusion_reason := fcase(
  is_supported, "supported",
  n_treated_states == 0L, "treated cohort lacks county coverage",
  n_control_states == 0L, "no eligible control state has county coverage",
  default = "unsupported for unspecified support reason"
)]
support_by_cell[, covid_overlap := mapply(
  \(a, b, c, d) overlaps_covid(a, b) || overlaps_covid(c, d),
  pre_start_date, pre_end_date, post_start_date, post_end_date
)]

cell_estimates <- cell_estimates_all[is_supported == TRUE]
setorder(cell_estimates, specification, horizon, cohort_start)

# 4. Equal-treated-state aggregation and jackknife inference ------------------

aggregate_list <- list()
replicate_list <- list()
aggregate_index <- 0L
replicate_index <- 0L

for (specification_name in specifications[["specification"]]) {
  common_treated <- find_common_treated(
    state_cell_changes,
    specification_name
  )
  for (horizon_name in horizon_definitions[["horizon"]]) {
    samples <- "available"
    if (!identical(horizon_name, "placebo")) {
      samples <- c(samples, "common_post")
    }
    for (aggregation_sample in samples) {
      allowed_treated <- NULL
      if (identical(aggregation_sample, "common_post")) {
        allowed_treated <- common_treated
      }
      result <- jackknife_aggregate(
        state_cell_changes,
        specification_name,
        horizon_name,
        aggregation_sample,
        allowed_treated
      )
      if (!is.null(result[["summary"]])) {
        aggregate_index <- aggregate_index + 1L
        aggregate_list[[aggregate_index]] <- result[["summary"]]
      }
      if (nrow(result[["replicates"]]) > 0L) {
        replicate_index <- replicate_index + 1L
        replicate_list[[replicate_index]] <- result[["replicates"]]
      }
    }
  }
}

aggregate_estimates <- rbindlist(aggregate_list, fill = TRUE)
leave_one_state_out <- rbindlist(replicate_list, fill = TRUE)
if (nrow(aggregate_estimates) == 0L) {
  stop("No aggregate estimates could be computed.")
}
aggregate_estimates[, horizon_order := match(
  horizon,
  horizon_definitions[["horizon"]]
)]
setorder(
  aggregate_estimates,
  specification,
  aggregation_sample,
  horizon_order
)
aggregate_estimates[, horizon_order := NULL]

# 5. Export tabular and serialized artifacts ---------------------------------

fwrite(
  cell_estimates,
  file.path(OUT_DIR, "cell_estimates.csv")
)
fwrite(
  aggregate_estimates,
  file.path(OUT_DIR, "aggregate_estimates.csv")
)
fwrite(
  support_by_cell,
  file.path(OUT_DIR, "support_by_cell.csv")
)
fwrite(
  leave_one_state_out,
  file.path(OUT_DIR, "leave_one_state_out.csv")
)
fwrite(
  treated_state_support,
  file.path(OUT_DIR, "treated_state_support.csv")
)
fwrite(
  online_treated_regime,
  file.path(OUT_DIR, "online_treated_regime.csv")
)

saveRDS(panel, file.path(OUT_DIR, "analysis_panel.rds"))
saveRDS(
  treatment_state,
  file.path(OUT_DIR, "online_treatment_schedule.rds")
)
saveRDS(
  state_cell_changes,
  file.path(OUT_DIR, "state_cell_changes.rds")
)
saveRDS(cell_estimates, file.path(OUT_DIR, "cell_estimates.rds"))
saveRDS(
  aggregate_estimates,
  file.path(OUT_DIR, "aggregate_estimates.rds")
)
saveRDS(
  leave_one_state_out,
  file.path(OUT_DIR, "leave_one_state_out.rds")
)
saveRDS(support_by_cell, file.path(OUT_DIR, "support_by_cell.rds"))
saveRDS(
  treated_state_support,
  file.path(OUT_DIR, "treated_state_support.rds")
)
saveRDS(
  online_treated_regime,
  file.path(OUT_DIR, "online_treated_regime.rds")
)
saveRDS(drop_audit, file.path(OUT_DIR, "drop_audit.rds"))
saveRDS(analysis_summary, file.path(OUT_DIR, "analysis_summary.rds"))
saveRDS(
  list(
    specifications = specifications,
    horizons = horizon_definitions,
    seed = SEED,
    alpha = ALPHA,
    covid_interval = c(COVID_START, COVID_END),
    treatment_source = paste(
      "data", "raw", "sports_gambling_legalization_dates.csv",
      sep = "/"
    ),
    treatment_definition = "online_start_date",
    regime_definition = paste(
      "retail_first if retail_start_date < online_start_date;",
      "online_first_or_simultaneous otherwise"
    ),
    clean_control_definition = paste(
      "no first gambling launch through the cohort-window endpoint"
    ),
    states_without_online_launch = states_without_online_launch
  ),
  file.path(OUT_DIR, "analysis_parameters.rds")
)

# 6. Publication-ready aggregate figure --------------------------------------

plot_data <- aggregate_estimates[
  aggregation_sample == "available" |
    (specification == "primary" & aggregation_sample == "common_post")
]
plot_data[, plot_spec := fcase(
  specification == "primary" & aggregation_sample == "available",
  "Primary",
  specification == "primary" & aggregation_sample == "common_post",
  "Primary, common composition",
  specification == "not_yet_controls", "Not-yet controls",
  specification == "rate_outcome", "Rate outcome",
  specification == "renter_weighted", "Renter weighted",
  specification == "strict_coverage", "Strict coverage",
  specification == "complete_coverage", "Complete coverage",
  specification == "online_first_clean", "Online-first clean"
)]
plot_data[, horizon_label := factor(
  horizon,
  levels = c("placebo", "months_0_11", "months_12_23", "months_24_35"),
  labels = c("Placebo pre-period", "Months 0-11", "Months 12-23",
             "Months 24-35")
)]

aggregate_plot <- ggplot(
  plot_data,
  aes(
    x = horizon_label,
    y = pct_effect,
    ymin = pct_ci_low,
    ymax = pct_ci_high,
    color = plot_spec,
    shape = horizon == "placebo"
  )
) +
  geom_hline(yintercept = 0, color = "grey45", linetype = "dashed") +
  geom_errorbar(
    position = position_dodge(width = 0.58),
    width = 0.12,
    linewidth = 0.45
  ) +
  geom_point(
    position = position_dodge(width = 0.58),
    size = 2.1
  ) +
  scale_shape_manual(
    values = c(`TRUE` = 17, `FALSE` = 16),
    guide = "none"
  ) +
  labs(
    x = NULL,
    y = "Transformed long-difference contrast (%)",
    color = "Specification",
    title = "Cohort-specific long-difference contrasts",
    subtitle = paste(
      "Descriptive contrasts with equal treated-state weights;",
      "bars use state-jackknife 95% CIs"
    )
  ) +
  theme_minimal(base_size = 10.5, base_family = "serif") +
  theme(
    legend.position = "bottom",
    legend.box = "vertical",
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank(),
    axis.text.x = element_text(angle = 20, hjust = 1)
  )

ggsave(
  file.path(OUT_DIR, "aggregate_estimates.png"),
  aggregate_plot,
  width = 9,
  height = 6,
  dpi = 300,
  bg = "white"
)
saveRDS(aggregate_plot, file.path(OUT_DIR, "aggregate_plot.rds"))

# 7. Results summary ----------------------------------------------------------

format_result <- function(row) {
  if (nrow(row) == 0L) {
    return("not estimable")
  }
  sprintf(
    "%+.1f%% (95%% CI %+.1f%% to %+.1f%%; jackknife SE %.3f; p=%.3f; %d treated states)",
    row[["pct_effect"]], row[["pct_ci_low"]], row[["pct_ci_high"]],
    row[["jackknife_se"]], row[["p_value"]],
    row[["n_treated_states"]]
  )
}

primary_results <- aggregate_estimates[
  specification == "primary" & aggregation_sample == "available"
]
primary_common <- aggregate_estimates[
  specification == "primary" & aggregation_sample == "common_post"
]
online_first_clean_results <- aggregate_estimates[
  specification == "online_first_clean" &
    aggregation_sample == "available"
]
primary_support <- support_by_cell[specification == "primary"]
unsupported_primary <- primary_support[is_supported == FALSE]
primary_state_support <- treated_state_support[
  specification == "primary"
]
post_state_support <- primary_state_support[horizon != "placebo"]
excluded_all_post <- post_state_support[, .(
  n_supported = sum(is_supported_state)
), by = state_abb][n_supported == 0L, state_abb]
excluded_all_details <- post_state_support[
  state_abb %chin% excluded_all_post & is_supported_state == FALSE,
  .(
    reasons = paste(sort(unique(exclusion_reason)), collapse = "; ")
  ),
  by = state_abb
]
excluded_all_text <- if (nrow(excluded_all_details) == 0L) {
  "none"
} else {
  paste(
    sprintf(
      "%s (%s)",
      excluded_all_details[["state_abb"]],
      excluded_all_details[["reasons"]]
    ),
    collapse = ", "
  )
}
partial_support_details <- post_state_support[, .(
  n_supported = sum(is_supported_state),
  supported_horizons = paste(
    horizon[is_supported_state],
    collapse = ", "
  ),
  excluded_horizons = paste(
    horizon[!is_supported_state],
    collapse = ", "
  ),
  reasons = paste(
    sort(unique(exclusion_reason[!is_supported_state])),
    collapse = "; "
  )
), by = state_abb][n_supported > 0L & n_supported < 3L]
partial_support_text <- if (nrow(partial_support_details) == 0L) {
  "none"
} else {
  paste(
    sprintf(
      "%s (supported: %s; excluded: %s; %s)",
      partial_support_details[["state_abb"]],
      partial_support_details[["supported_horizons"]],
      partial_support_details[["excluded_horizons"]],
      partial_support_details[["reasons"]]
    ),
    collapse = "; "
  )
}
common_states <- find_common_treated(state_cell_changes, "primary")
clean_common_states <- find_common_treated(
  state_cell_changes,
  "online_first_clean"
)
retail_first_states <- online_treated_regime[
  online_regime == "retail_first", state_abb
]
online_first_states <- online_treated_regime[
  online_regime == "online_first_or_simultaneous", state_abb
]
sensitivity_results <- aggregate_estimates[
  specification != "primary" & aggregation_sample == "available"
]
sensitivity_results[, specification_label := fcase(
  specification == "not_yet_controls", "Not-yet controls",
  specification == "rate_outcome", "Rate outcome",
  specification == "renter_weighted", "Renter weighted",
  specification == "strict_coverage", "Strict coverage",
  specification == "complete_coverage", "Complete coverage",
  specification == "online_first_clean", "Online-first clean"
)]
sensitivity_results[, horizon_order := match(
  horizon,
  horizon_definitions[["horizon"]]
)]
setorder(sensitivity_results, specification_label, horizon_order)
robustness_lines <- c(
  "| Specification | Horizon | Contrast (%) | 95% CI (%) | SE | p-value |",
  "|---|---:|---:|---:|---:|---:|",
  vapply(
    seq_len(nrow(sensitivity_results)),
    \(index) {
      row <- sensitivity_results[index]
      sprintf(
        "| %s | %s | %+.1f | [%+.1f, %+.1f] | %.3f | %.3f |",
        row[["specification_label"]], row[["horizon"]],
        row[["pct_effect"]], row[["pct_ci_low"]],
        row[["pct_ci_high"]], row[["jackknife_se"]],
        row[["p_value"]]
      )
    },
    character(1L)
  )
)
primary_influence_lines <- vapply(
  seq_len(nrow(primary_results)),
  \(index) {
    row <- primary_results[index]
    sprintf(
      "- %s: %s, maximum absolute leave-one-out change %.3f log points.",
      row[["horizon"]], row[["max_influence_state"]],
      row[["max_abs_influence"]]
    )
  },
  character(1L)
)

summary_lines <- c(
  "# Cohort-specific long-difference results",
  "",
  "## Main findings",
  "",
  paste0(
    "- Placebo pre-period: ",
    format_result(primary_results[horizon == "placebo"]), "."
  ),
  paste0(
    "- Months 0-11 after online launch: ",
    format_result(primary_results[horizon == "months_0_11"]), "."
  ),
  paste0(
    "- Months 12-23 after online launch: ",
    format_result(primary_results[horizon == "months_12_23"]), "."
  ),
  paste0(
    "- Months 24-35 after online launch: ",
    format_result(primary_results[horizon == "months_24_35"]), "."
  ),
  "",
  "The point estimates are log contrasts transformed as 100*(exp(ATT)-1). ",
  "This percentage transformation is descriptive unless the design's ",
  "identifying assumptions hold. ",
  "The design does not produce evidence that is robustly distinguishable from ",
  "zero if the state-jackknife interval includes zero. The placebo is an ",
  "important diagnostic: a nonzero placebo indicates differential movement ",
  "before treatment rather than a causal post-treatment effect.",
  "",
  "## Design and estimand",
  "",
  "For each exact online-legalization month g, the primary design compares a ",
  "24-month untreated county premean (g-30 through g-7, leaving a six-month ",
  "anticipation gap) with fixed exposure windows g through g+11, g+12 through ",
  "g+23, and g+24 through g+35. States without an online launch are transformed using ",
  "the same cohort-calendar window boundaries. Primary county means require ",
  "coverage in both windows but may use only 12/24 pre and 6/12 post months; ",
  "they therefore need not average identical observed month sets. County ",
  "changes are averaged to one ",
  "state-cohort cell, and cohort contrasts are aggregated with equal treated-",
  "state weights. This is a cohort-specific long-difference design, not a claim ",
  "to implement the formal published Lee-Wooldridge estimator.",
  "Treatment timing is `online_start_date` from ",
  "`data/raw/sports_gambling_legalization_dates.csv`; first retail or other ",
  "launch dates do not define treatment in this analysis.",
  "The primary estimand mixes online-first/simultaneous states with states ",
  "that already had retail betting before online launch. Its controls are ",
  "states without an online launch, including some with retail betting. A ",
  "causal interpretation therefore requires prior retail exposure and retail-",
  "only control histories not to invalidate parallel cumulative changes or ",
  "alter the response to online access.",
  "",
  "The placebo compares g-30:g-19 with g-18:g-7. Per-cell estimates are ",
  "descriptive because most cohorts contain one treated state. Aggregate ",
  "inference uses a delete-one-state jackknife and never substitutes county-",
  "clustered standard errors.",
  "",
  "## Composition-stable primary estimates",
  "",
  paste0(
    "Treated states supported at all three post horizons: ",
    if (length(common_states) == 0L) "none" else paste(common_states, collapse = ", "),
    "."
  ),
  paste0(
    "- Months 0-11: ",
    format_result(primary_common[horizon == "months_0_11"]), "."
  ),
  paste0(
    "- Months 12-23: ",
    format_result(primary_common[horizon == "months_12_23"]), "."
  ),
  paste0(
    "- Months 24-35: ",
    format_result(primary_common[horizon == "months_24_35"]), "."
  ),
  "",
  "## Retail-history regime split and clean sensitivity",
  "",
  paste0(
    "Retail-first online-treated states: ",
    paste(retail_first_states, collapse = ", "),
    ". Online-first or simultaneous states: ",
    paste(online_first_states, collapse = ", "),
    "."
  ),
  paste0(
    "The online-first clean sensitivity has complete three-horizon support for ",
    paste(clean_common_states, collapse = ", "),
    ". CO is in the online-first/simultaneous regime but lacks clean-pre ",
    "support. The resulting four treated states make inference especially ",
    "fragile."
  ),
  paste0(
    "- Clean placebo: ",
    format_result(online_first_clean_results[horizon == "placebo"]), "."
  ),
  paste0(
    "- Clean months 0-11: ",
    format_result(
      online_first_clean_results[horizon == "months_0_11"]
    ),
    "."
  ),
  paste0(
    "- Clean months 12-23: ",
    format_result(
      online_first_clean_results[horizon == "months_12_23"]
    ),
    "."
  ),
  paste0(
    "- Clean months 24-35: ",
    format_result(
      online_first_clean_results[horizon == "months_24_35"]
    ),
    "."
  ),
  "",
  "For each cohort endpoint, clean controls have no first sports-betting ",
  "launch of any type by that endpoint. The contrast therefore targets first ",
  "sports-betting access delivered online (possibly bundled with same-month ",
  "retail), not the incremental effect of adding online access after retail.",
  "",
  "## Sample and support",
  "",
  sprintf(
    "The joined panel contains %d states (%d online-treated and %d without an online launch), %d counties, and %d county-month rows from %s through %s.",
    analysis_summary[["n_states"]],
    analysis_summary[["n_treated_states"]],
    analysis_summary[["n_never_states"]],
    analysis_summary[["n_counties"]],
    analysis_summary[["n_rows"]],
    analysis_summary[["first_month"]],
    analysis_summary[["last_month"]]
  ),
  sprintf(
    "Primary coverage requires at least 12 of 24 pre months and 6 of 12 post months for the same county. There are %d unsupported primary cohort-horizon cells.",
    nrow(unsupported_primary)
  ),
  paste0(
    "Online-treated states excluded from every post horizon: ",
    excluded_all_text,
    ". Partially supported online-treated states: ",
    partial_support_text,
    ". See `treated_state_support.csv`."
  ),
  paste0(
    "States appearing in the legalization schedule but lacking an online launch ",
    "date are classified as never treated for this online-access estimand: ",
    paste(retail_or_other_without_online, collapse = ", "),
    ". Notably, MT, NC, and ND remain controls; their retail launch dates are ",
    "not used."
  ),
  if (nrow(unsupported_primary) == 0L) {
    "No primary cells were excluded for support."
  } else {
    paste0(
      "Unsupported primary cells: ",
      paste(
        sprintf(
          "%s [%s]/%s (%s)",
          unsupported_primary[["cohort_start"]],
          unsupported_primary[["expected_treated_states"]],
          unsupported_primary[["horizon"]],
          unsupported_primary[["exclusion_reason"]]
        ),
        collapse = "; "
      ),
      "."
    )
  },
  "",
  "## Robustness specifications",
  "",
  "The output reports six planned sensitivities: controls that are never or ",
  "not yet treated through the window endpoint; the log filing rate; within-",
  "state renter weighting; and stricter county coverage (18/24 pre months and ",
  "9/12 post months). The complete-coverage specification requires every ",
  "calendar month (24/24 pre and 12/12 post) for the same county. The online-",
  "first clean specification restricts treated states by regime and requires ",
  "controls to have no betting launch of any type through the endpoint.",
  "",
  robustness_lines,
  "",
  "## COVID and inference caveats",
  "",
  "COVID overlap is flagged whenever either comparison interval intersects ",
  "March 2020 through March 2022. Calendar matching does not remove differential ",
  "pandemic shocks or recovery paths. Many early-cohort post windows and later-",
  "cohort pre windows overlap this interval, so these contrasts still require a ",
  "parallel cumulative-shocks assumption.",
  "The aggregate `covid_any` flag is TRUE whenever any included cohort cell ",
  "overlaps the COVID interval, including for a placebo aggregate when one or ",
  "more of its cohort-calendar windows overlaps that interval.",
  "",
  "Treatment is assigned at the state level and the effective sample is small. ",
  "Delete-one-state jackknife intervals are approximate; `leave_one_state_out.csv` ",
  "reports every replicate, invalid replicates, and the most influential state. ",
  "A singleton treated cohort cannot support credible cell-specific inference.",
  "",
  "Largest absolute leave-one-state-out changes in the primary estimates:",
  "",
  primary_influence_lines,
  "",
  "## Outcome summary statistics",
  "",
  sprintf(
    "Across county-month observations, y has mean %.3f, median %.3f, and SD %.3f; y_rate has mean %.3f, median %.3f, and SD %.3f.",
    analysis_summary[["y_mean"]], analysis_summary[["y_median"]],
    analysis_summary[["y_sd"]], analysis_summary[["y_rate_mean"]],
    analysis_summary[["y_rate_median"]], analysis_summary[["y_rate_sd"]]
  ),
  "",
  "## Paper-to-code naming map",
  "",
  "| Paper notation | Code name | Meaning |",
  "|---|---|---|",
  "| Y_it | y, y_rate | Log filings and log filing rate |",
  "| G_i | treat_start | First online-treatment month |",
  "| DeltaY_i(g,h) | state_change | State long difference |",
  "| ATT(g,h) | att_gh | Cohort-by-horizon contrast |",
  "| ATT(h) | att_h | Equal-treated-state aggregate contrast |"
)
writeLines(
  summary_lines,
  con = file.path(OUT_DIR, "results_summary.md"),
  useBytes = TRUE
)

message("Primary aggregate estimates:")
message(
  paste(
    sprintf(
      "  %s: ATT=%+.4f, SE=%.4f, p=%.3f, percent=%+.1f%%",
      primary_results[["horizon"]], primary_results[["att_h"]],
      primary_results[["jackknife_se"]], primary_results[["p_value"]],
      primary_results[["pct_effect"]]
    ),
    collapse = "\n"
  )
)
message("Session information:")
print(sessionInfo())
