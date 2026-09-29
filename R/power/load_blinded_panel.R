################################################################################
# R/power/load_blinded_panel.R
#
# The single sanctioned entry point for untreated outcome data
# (POWER_SIMULATION_BLINDNESS_PROTOCOL.md §5.1). Joins the treatment schedule,
# applies the per-state anticipation cutoff (§4) as a floor in EVERY sample,
# layers the sample-specific restriction, applies the COVID filter, builds
# outcome transforms, sets g = 0 for all rows (untreated by construction), and
# calls assert_blinded() before returning.
#
# Working directory is assumed to be the repository root.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
})

# Sourced-alongside dependencies.
if (!exists("power_paths", mode = "function")) source("R/power/config.R")
if (!exists("assert_blinded", mode = "function")) source("R/power/blindness_checks.R")
if (!exists("load_eviction_treatment_schedule", mode = "function")) {
  if (!file.exists("utils/eviction_treatment_schedule.R")) {
    stop("utils/eviction_treatment_schedule.R not found; run from repo root.",
         call. = FALSE)
  }
  source("utils/eviction_treatment_schedule.R")
}

# Local FIPS -> state abbreviation crosswalk (avoids sourcing the heavy
# power_simulation_cs.R just for its embedded table).
.power_fips_xwalk <- tibble::tribble(
  ~state_fips, ~state_abb,
  1L, "AL",  2L, "AK",  4L, "AZ",  5L, "AR",  6L, "CA",  8L, "CO",
  9L, "CT", 10L, "DE", 11L, "DC", 12L, "FL", 13L, "GA", 15L, "HI",
  16L, "ID", 17L, "IL", 18L, "IN", 19L, "IA", 20L, "KS", 21L, "KY",
  22L, "LA", 23L, "ME", 24L, "MD", 25L, "MA", 26L, "MI", 27L, "MN",
  28L, "MS", 29L, "MO", 30L, "MT", 31L, "NE", 32L, "NV", 33L, "NH",
  34L, "NJ", 35L, "NM", 36L, "NY", 37L, "NC", 38L, "ND", 39L, "OH",
  40L, "OK", 41L, "OR", 42L, "PA", 44L, "RI", 45L, "SC", 46L, "SD",
  47L, "TN", 48L, "TX", 49L, "UT", 50L, "VT", 51L, "VA", 53L, "WA",
  54L, "WV", 55L, "WI", 56L, "WY"
)

#' Build a per-state schedule with both the chosen-definition and first-any date
#'
#' Cutoffs always use \code{first_start_date} (protocol §4) so that no sample is
#' "untreated" under one definition while treated under another.
#'
#' @param schedule_path Path to the gambling legalization dates CSV.
#' @param treat_def Chosen treatment-definition column.
#' @return Tibble: state_abb, g (chosen def, Date), g_first (first-any, Date).
#' @keywords internal
.load_gambling_schedule <- function(schedule_path, treat_def) {
  assert_no_forbidden_paths(schedule_path)
  g_def <- load_eviction_treatment_schedule(schedule_path, treat_def) %>%
    rename(g = "treat_start")
  g_first <- load_eviction_treatment_schedule(schedule_path, "first_start_date") %>%
    rename(g_first = "treat_start")
  full_join(g_def, g_first, by = "state_abb")
}

#' Read + normalize the county-month panel (untreated-agnostic; cutoffs later)
#' @keywords internal
.read_county_panel <- function(path) {
  raw <- guarded_read_csv(path)
  raw %>%
    mutate(
      state_fips = as.integer(.data$fips) %/% 1000L,
      month_date = floor_date(as.Date(.data$date), "month")
    ) %>%
    filter(!.data$state_fips %in% c(72L, 78L)) %>%    # exclude PR / USVI
    left_join(.power_fips_xwalk, by = "state_fips") %>%
    filter(!is.na(.data$state_abb), .data$state_abb != "ME") %>%
    transmute(
      unit_id       = as.character(.data$fips),
      state_abb     = .data$state_abb,
      month_date    = .data$month_date,
      filings_count = as.numeric(.data$filings_count),
      renters       = as.numeric(.data$renter_occupied_housing_units)
    )
}

#' Read + normalize the state-month panel (ignore embedded treat_start)
#' @keywords internal
.read_state_panel <- function(path) {
  raw <- guarded_read_csv(path)
  raw %>%
    # MAINE -- exclusion REMOVED 2026-09-17. It was added with the framework
    # (12725a5) with no comment, and it was right at the time: Maine's series
    # came from a Judicial Branch parse whose JUNE-DECEMBER labels were one
    # year too late (a judicial-year boundary written as a calendar year), so
    # Maine showed no COVID moratorium at all and then a moratorium-shaped
    # collapse a year late. Maine was the only affected state.
    # Repaired 2026-09-17: live LSC through 2023-05 (89 months, matching LSC
    # exactly) spliced to the fiscal-year-corrected court series from 2023-06
    # (data_prep/add_me_to_state_panel.R; the relabel validates against LSC at
    # mean |diff| 0.92 filings over 89 overlapping months). ME is now a clean
    # 113-month series with no interior gaps AND a switcher under the inclusion
    # rule, so excluding it would leave the simulation unable to represent a
    # cohort the real design estimates. Blinded panel 39 -> 40 states.
    transmute(
      unit_id       = as.character(.data$state_abb),
      state_abb     = as.character(.data$state_abb),
      month_date    = floor_date(as.Date(.data$month_date), "month"),
      filings_count = as.numeric(.data$filings_count),
      renters       = as.numeric(.data$renter_occupied_housing_units)
    )
}

#' Read + normalize the state-month MORTGAGE DELINQUENCY panel
#'
#' The outcome is a RATE in percentage points, not a count, so this reader
#' fills \code{filings_count} / \code{renters} with NA and carries the rate in
#' \code{delinq_pp}. Two consequences the caller must respect:
#'   * the count mechanisms (count_nb, count_pois, thinning) are unavailable —
#'     use \code{mechanism = "deterministic"}, which adds delta on the outcome
#'     scale, so delta is in PERCENTAGE POINTS, not a proportional change;
#'   * outcome is \code{y_pp} (levels) or, since 2026-09-29, the opt-in
#'     \code{y_log_pp} (log of the rate). The count log transforms are NOT
#'     built. Logs were withheld until then because the source series is
#'     published to 0.1pp and 87% of design-window state-months sit at or
#'     below 1.0pp, so one rounding tick is a 17%+
#'     relative move on the log scale (probe: 2026-09-04).
#' @keywords internal
.read_state_mortgage_panel <- function(path) {
  raw <- guarded_read_csv(path)
  raw %>%
    transmute(
      unit_id       = as.character(.data$state_abb),
      state_abb     = as.character(.data$state_abb),
      month_date    = floor_date(as.Date(.data$month_date), "month"),
      delinq_pp     = as.numeric(.data$delinquency_rate),
      filings_count = NA_real_,
      renters       = NA_real_
    ) %>%
    filter(!is.na(.data$delinq_pp))
}

#' Load a blinded untreated calibration panel
#'
#' @param level "county", "state", or "state_mortgage" (rate outcome).
#' @param treat_def Treatment-definition column for the schedule join. Cutoffs
#'   always use first_start_date regardless (protocol §4).
#' @param anticipation Anticipation exclusion window in months (default 6).
#' @param sample "S1" (universal cutoff, all states), "S2" (per-state risk set),
#'   or "S3" (never-treated states only). The per-state anticipation cutoff is a
#'   floor applied in every sample.
#' @param covid "drop" (remove the config window), "pre", "covid", "post", or
#'   "keep".
#' @param quarterly Aggregate to quarter (counts summed, renters averaged).
#' @param config A power config list (see \code{read_power_config}).
#' @return A tibble with columns unit_id, state_abb, month_date, t,
#'   filings_count, renters, y_log1p, y_lograte, y_asinh, g (all 0). Attributes:
#'   sample_id, treat_def, anticipation, universal_cutoff, covid, covid_window,
#'   level, quarterly, never_treated. \code{assert_blinded()} passes before
#'   return.
#' @export
load_blinded_panel <- function(level = c("county", "state", "state_mortgage"),
                               treat_def = c("online_start_date",
                                             "first_start_date",
                                             "retail_start_date",
                                             # handle50 market maturation
                                             # (requires a schedule file that
                                             # carries the column, e.g.
                                             # data/processed/
                                             # maturation50_schedule.csv);
                                             # blindness cutoffs still use
                                             # first_start_date regardless.
                                             "maturation50_start_date",
                                             # handle reaches 75% of ramp
                                             # (data/processed/ramp75_schedule.csv)
                                             "ramp75_start_date",
                                             # uniform online launch + 12 months
                                             # (data/processed/shift12_schedule.csv).
                                             # Unlike maturation50/ramp75 this
                                             # uses NO outcome data: it is a
                                             # fixed pre-specifiable lag, so it
                                             # is blind by construction. See
                                             # data_prep/build_shift12_schedule.R
                                             # for why ramp75 is a data-vintage
                                             # artifact (lag correlates 0.957
                                             # with months observed).
                                             "shift12_start_date"),
                               anticipation = 6L,
                               sample = c("S1", "S2", "S3"),
                               covid = c("drop", "pre", "covid", "post", "keep"),
                               quarterly = FALSE,
                               time_agg = NULL,
                               complete_periods_only = FALSE,
                               config = read_power_config()) {
  level     <- match.arg(level)
  treat_def <- match.arg(treat_def)
  sample    <- match.arg(sample)
  covid     <- match.arg(covid)
  # `time_agg` supersedes the legacy boolean `quarterly`; when it is NULL the
  # boolean decides, so every existing call is bit-for-bit unchanged.
  time_agg <- if (is.null(time_agg)) {
    if (isTRUE(quarterly)) "quarter" else "month"
  } else {
    match.arg(time_agg, c("month", "quarter", "year"))
  }
  quarterly <- identical(time_agg, "quarter")
  complete_periods_only <- isTRUE(complete_periods_only)
  anticipation     <- as.integer(anticipation)
  universal_cutoff <- as.Date(config$universal_cutoff)
  covid_win        <- as.Date(config$covid_drop)

  sched <- .load_gambling_schedule(config$schedule, treat_def)

  is_rate <- identical(level, "state_mortgage")
  base <- if (level == "county") {
    .read_county_panel(config$county_panel)
  } else if (is_rate) {
    .read_state_mortgage_panel(config$mortgage_panel %||%
                                 "data/processed/mortgage_treatment_panel.csv")
  } else {
    .read_state_panel(config$state_panel)
  }
  # A rate panel has no counts to be missing; its own NA filter ran in the
  # reader. Applying the count filter here would empty it.
  if (!is_rate) base <- base %>% filter(!is.na(.data$filings_count))

  # Panel-start floor (config.R: default 2016-01-01). A handful of states in
  # the raw state-month panel carry legacy pre-2016 data; without this floor
  # those states alone would contribute years of extra unbalanced history to
  # every calibration sample, silently changing sample composition (see
  # config.R panel_floor doc comment).
  panel_floor <- as.Date(config$panel_floor %||% "2016-01-01")
  base <- base %>% filter(.data$month_date >= panel_floor)

  # Attach first-any treatment date for the cutoff logic.
  base <- base %>%
    left_join(sched %>% select("state_abb", "g_first"), by = "state_abb")

  # Per-state anticipation cutoff = blindness floor, applied in EVERY sample.
  # never-treated (g_first NA) keep all months.
  base_bl <- base %>%
    filter(is.na(.data$g_first) |
             .data$month_date < (.data$g_first %m-% months(anticipation)))

  panel <- switch(
    sample,
    S1 = base_bl %>% filter(.data$month_date <= universal_cutoff),
    S2 = base_bl,
    # S3 = never-treated states. Pre-PASPA sports-betting states are excluded:
    # they are absent from the schedule because there was no post-PASPA
    # legalization event, not because they never adopted, so treating them as
    # never-treated puts an always-treated state in the control sample.
    # See docs/methodology/ADOPTION_UNIVERSE_AUDIT.md.
    S3 = base_bl %>% filter(is.na(.data$g_first),
                            !.data$state_abb %in% PRE_PASPA_SPORTS_BETTING)
  )

  panel <- switch(
    covid,
    drop  = panel %>% filter(.data$month_date < covid_win[1] |
                               .data$month_date > covid_win[2]),
    pre   = panel %>% filter(.data$month_date < covid_win[1]),
    covid = panel %>% filter(.data$month_date >= covid_win[1] &
                               .data$month_date <= covid_win[2]),
    post  = panel %>% filter(.data$month_date > covid_win[2]),
    keep  = panel
  )

  # Aggregation to coarser periods. NOTE the ordering: the COVID filter above
  # runs FIRST, so a period straddling the COVID boundary arrives here holding
  # only its surviving months (covid = "drop" leaves 2020Q1 = Jan+Feb and
  # 2021Q3 = Aug+Sep; annual 2020 = 2 months, 2021 = 5). Summing those yields a
  # mechanically depressed count that is an aggregation artifact, not a real
  # level change — `complete_periods_only = TRUE` removes any unit-period that
  # does not hold its full complement of months (3 / 12). Default FALSE keeps
  # historical behavior byte-identical.
  n_dropped_incomplete <- 0L
  if (time_agg != "month") {
    per_len <- if (time_agg == "quarter") 3L else 12L
    panel <- panel %>%
      mutate(period = floor_date(.data$month_date, time_agg)) %>%
      group_by(.data$unit_id, .data$state_abb, .data$period) %>%
      summarise(
        # A COUNT aggregates by summing; a RATE aggregates by averaging.
        # Summing delinq_pp across months would fabricate a level shift
        # proportional to period length.
        filings_count = if (is_rate) NA_real_
                        else sum(.data$filings_count, na.rm = TRUE),
        delinq_pp     = if (is_rate) mean(.data$delinq_pp, na.rm = TRUE)
                        else NA_real_,
        renters       = mean(.data$renters, na.rm = TRUE),
        n_months      = dplyr::n_distinct(.data$month_date),
        .groups = "drop"
      ) %>%
      rename(month_date = "period")
    if (complete_periods_only) {
      n_dropped_incomplete <- sum(panel$n_months < per_len, na.rm = TRUE)
      panel <- panel %>% filter(.data$n_months >= per_len)
    }
    panel$n_months <- NULL
  }

  # Integer time index (contiguous within the returned panel).
  tkey <- switch(
    time_agg,
    month   = year(panel$month_date) * 12L + (month(panel$month_date) - 1L),
    quarter = year(panel$month_date) * 4L + (quarter(panel$month_date) - 1L),
    year    = year(panel$month_date)
  )
  panel$t <- as.integer(tkey - min(tkey) + 1L)

  panel <- if (is_rate) {
    # y_pp is the rate in percentage points; pair with mechanism =
    # "deterministic", so delta is read in percentage points.
    # y_log_pp (2026-09-29) = log(rate): opt-in, for testing whether the
    # 0.1pp rounding makes a proportional spec unusable. Under "deterministic"
    # its delta is in LOG POINTS. The rate is never 0 in the source (minimum
    # 0.2pp since 2016), so no offset is added; a non-positive value stops.
    if (any(panel$delinq_pp <= 0, na.rm = TRUE))
      stop("state_mortgage: non-positive delinquency rate; y_log_pp undefined.",
           call. = FALSE)
    panel %>%
      mutate(y_pp = .data$delinq_pp, y_log_pp = log(.data$delinq_pp), g = 0) %>%
      select("unit_id", "state_abb", "month_date", "t",
             "filings_count", "renters", "y_pp", "y_log_pp", "g") %>%
      arrange(.data$state_abb, .data$unit_id, .data$month_date)
  } else {
    panel %>%
      mutate(
        y_log1p   = log1p(.data$filings_count),
        y_lograte = log(.data$filings_count / .data$renters * 1000 + 0.01),
        y_asinh   = asinh(.data$filings_count),
        g         = 0
      ) %>%
      select("unit_id", "state_abb", "month_date", "t",
             "filings_count", "renters",
             "y_log1p", "y_lograte", "y_asinh", "g") %>%
      arrange(.data$state_abb, .data$unit_id, .data$month_date)
  }

  attr(panel, "sample_id")        <- sample
  attr(panel, "treat_def")        <- treat_def
  attr(panel, "anticipation")     <- anticipation
  attr(panel, "universal_cutoff") <- universal_cutoff
  attr(panel, "covid")            <- covid
  attr(panel, "covid_window")     <- covid_win
  attr(panel, "level")            <- level
  attr(panel, "quarterly")        <- quarterly
  attr(panel, "time_agg")         <- time_agg
  attr(panel, "complete_periods_only")        <- complete_periods_only
  attr(panel, "n_periods_dropped_incomplete") <- n_dropped_incomplete
  # Never-treated = panel states with no first-any treatment date. Derived from
  # the panel (the schedule CSV lists treated states only), so states absent
  # from the schedule correctly count as never-treated -- EXCEPT the pre-PASPA
  # sports-betting states, which are absent for the opposite reason (they were
  # already treated) and are excluded here. Fixed 2026-08-21; previously NV
  # appeared in this attribute at level="state".
  attr(panel, "never_treated")    <-
    sort(setdiff(unique(base$state_abb[is.na(base$g_first)]),
                 PRE_PASPA_SPORTS_BETTING))

  # Appended last so the eviction panels' existing attribute ORDER is
  # untouched (positional all.equal comparisons stay clean).
  attr(panel, "outcome_kind")     <- if (is_rate) "rate_pp" else "count"

  assert_blinded(panel, sched, anticipation, universal_cutoff)

  panel
}
