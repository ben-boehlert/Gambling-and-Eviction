################################################################################
# eviction_treatment_schedule.R
#
# Shared helpers for eviction analyses that need a canonical state-level
# treatment schedule. By default, the active eviction workflows should derive
# treatment timing from sports_gambling_legalization_dates.csv rather than rely
# on stale treat_start values embedded in older panel files.
################################################################################

eviction_state_name_to_abb <- function(state_name) {
  state_name <- trimws(as.character(state_name))
  lookup <- setNames(state.abb, state.name)
  lookup <- c(lookup, "District of Columbia" = "DC")
  unname(lookup[state_name])
}

load_eviction_treatment_schedule <- function(treat_file, treat_date_col, states = NULL) {
  if (!nzchar(treat_file)) {
    stop("treat_file must be provided when using TREAT_SOURCE='file'.", call. = FALSE)
  }
  if (!file.exists(treat_file)) {
    stop("Treatment file not found: ", treat_file, call. = FALSE)
  }

  raw <- readr::read_csv(treat_file, show_col_types = FALSE)

  if (!("state" %in% names(raw))) {
    stop("Treatment file must contain a 'state' column: ", treat_file, call. = FALSE)
  }
  if (!(treat_date_col %in% names(raw))) {
    stop(
      "Treatment column '", treat_date_col, "' not found in ", treat_file,
      ". Available columns: ", paste(names(raw), collapse = ", "),
      call. = FALSE
    )
  }

  sched <- raw %>%
    dplyr::transmute(
      state_abb = eviction_state_name_to_abb(.data$state),
      treat_start = as.Date(.data[[treat_date_col]])
    ) %>%
    dplyr::filter(!is.na(.data$state_abb)) %>%
    dplyr::group_by(.data$state_abb) %>%
    dplyr::summarise(
      treat_start = if (all(is.na(.data$treat_start))) {
        as.Date(NA)
      } else {
        min(.data$treat_start, na.rm = TRUE)
      },
      .groups = "drop"
    )

  if (is.null(states)) return(sched)

  dplyr::tibble(state_abb = sort(unique(as.character(states)))) %>%
    dplyr::left_join(sched, by = "state_abb")
}

resolve_eviction_treatment_schedule <- function(panel_df,
                                                treat_source = "file",
                                                treat_file = "",
                                                treat_date_col = "online_start_date",
                                                panel_treat_col = "treat_start") {
  treat_source <- tolower(trimws(treat_source))

  if (!("state_abb" %in% names(panel_df))) {
    stop("panel_df must contain state_abb to resolve treatment timing.", call. = FALSE)
  }

  if (treat_source == "file") {
    return(load_eviction_treatment_schedule(
      treat_file = treat_file,
      treat_date_col = treat_date_col,
      states = panel_df$state_abb
    ))
  }

  if (treat_source == "panel") {
    if (!(panel_treat_col %in% names(panel_df))) {
      stop(
        "panel_treat_col='", panel_treat_col, "' not found in panel_df while TREAT_SOURCE='panel'.",
        call. = FALSE
      )
    }

    return(
      panel_df %>%
        dplyr::transmute(
          state_abb = as.character(.data$state_abb),
          treat_start = as.Date(.data[[panel_treat_col]])
        ) %>%
        dplyr::group_by(.data$state_abb) %>%
        dplyr::summarise(
          treat_start = if (all(is.na(.data$treat_start))) {
            as.Date(NA)
          } else {
            min(.data$treat_start, na.rm = TRUE)
          },
          .groups = "drop"
        )
    )
  }

  stop("Unknown TREAT_SOURCE='", treat_source, "'. Use 'file' or 'panel'.", call. = FALSE)
}

################################################################################
# CANONICAL ADOPTION UNIVERSE
#
# Two defects motivated this block. Both were live in committed code on
# 2026-08-21 and both are silent -- they produce a smaller, wrong sample with no
# warning. Do not hand-roll either rule again; call these helpers.
#
# DEFECT 1 -- THE ABSENT-ROW TRAP.
#   sports_gambling_legalization_dates.csv contains a row ONLY for states that
#   legalized something. States that never legalized are ABSENT, not present
#   with an NA date. So:
#       inner_join(features, schedule)          # DROPS 13 never-adopters
#       schedule %>% pull(state_abb)            # is NOT the state universe
#   are both wrong, while
#       never <- setdiff(panel_states, ever)    # SAFE
#       D     <- state_abb %in% ever_online     # SAFE
#   are correct, because they take the universe from the panel. The 13 states
#   with no row at all are: AL AK CA GA HI ID MN NE NV OK SC TX UT.
#
# DEFECT 2 -- NEVADA IS NOT A NEVER-ADOPTER.
#   Nevada has had legal sports betting continuously since 1949 and is absent
#   from the schedule for exactly that reason: there was no post-PASPA
#   legalization event to record. Treating "absent from the schedule" as "never
#   treated" therefore puts an ALWAYS-TREATED state into the control pool. This
#   was verified to be happening: NV appears in the never_any control set in
#   output/longdiff_era_variance/placements.csv and is the flagged outlier_state
#   driving the IQR in post-era placements.
#   Delaware, Oregon and Montana carry explicit post-2018 dates in the schedule,
#   so whatever their pre-2018 status, they are handled by the ordinary path and
#   are NOT part of this exception.
################################################################################

# The 50 states plus DC. The universe of the adoption decision -- not whatever
# subset happens to appear in a data file.
EVICTION_STATE_UNIVERSE <- c(state.abb, "DC")

# States with legal sports betting predating the PASPA repeal, hence absent from
# the schedule for a reason that is NOT "never adopted". Never valid as controls.
PRE_PASPA_SPORTS_BETTING <- c("NV")

# States excluded from every June-2022-onward analysis sample for a documented,
# outcome-independent reason (decided by Ben, 2026-09-21; FINDINGS.md section 2).
# They are neither controls, switchers, nor noise donors.
#   WA -- Eviction Resolution Pilot Program (SB 5160): mandatory pre-filing
#         dispute resolution for nonpayment cases, 2021-11-01..2023-06-30. The
#         panel's WA series (Pierce County) averages 167 filings/month under it
#         and 290 in the year after -- a policy break inside the analysis window.
#   MN -- eviction filings are incompletely observed in public court records
#         owing to expungement (Minnesota Management and Budget, Evaluation of
#         Emergency Assistance in Minnesota, May 2026, PDF p. 39: since 2020,
#         3.7% of judgments, 26.8% of settled and 50.3% of dismissed cases
#         expunged). MN re-enters if counts inclusive of expunged cases are
#         obtained from the Minnesota Judicial Branch before the analysis lock.
DATA_QUALITY_EXCLUDED_STATES <- c("MN", "WA")

#' Adoption outcomes over the full 51-state universe
#'
#' Returns exactly one row per state in EVICTION_STATE_UNIVERSE, so a join can
#' never silently delete a never-adopter.
#'
#' @param treat_file path to sports_gambling_legalization_dates.csv
#' @param treat_date_col which date column defines adoption
#' @param censor_end last date at which an adoption could have been observed;
#'   adoptions dated after it are treated as not-yet-observed (censored)
#' @param origin the zero point for event time (default: first US legalization)
#' @return tibble: state_abb, adopt_date, ever, months_to_adopt, surv_time,
#'   pre_paspa_legal, control_eligible
eviction_adoption_outcomes <- function(treat_file,
                                       treat_date_col = "online_start_date",
                                       censor_end = as.Date("2024-12-01"),
                                       origin = as.Date("2018-06-01")) {
  sched <- load_eviction_treatment_schedule(
    treat_file = treat_file,
    treat_date_col = treat_date_col,
    states = EVICTION_STATE_UNIVERSE
  )

  out <- sched %>%
    dplyr::transmute(
      state_abb,
      adopt_date      = .data$treat_start,
      pre_paspa_legal = .data$state_abb %in% PRE_PASPA_SPORTS_BETTING,
      ever            = !is.na(.data$adopt_date) & .data$adopt_date <= censor_end,
      months_to_adopt = ifelse(.data$ever,
                               as.numeric(.data$adopt_date - origin) / 30.4375,
                               NA_real_),
      surv_time       = ifelse(.data$ever,
                               .data$months_to_adopt,
                               as.numeric(censor_end - origin) / 30.4375),
      # A state is usable as an untreated control only if it neither adopted in
      # the observation window nor already had legal sports betting.
      control_eligible = !.data$ever & !.data$pre_paspa_legal
    )

  stopifnot(
    nrow(out) == length(EVICTION_STATE_UNIVERSE),
    !any(duplicated(out$state_abb))
  )
  out
}

#' Never-treated control states, with pre-PASPA states removed
#'
#' @param panel_states states actually present in the analysis panel
#' @param treat_file,treat_date_col passed to eviction_adoption_outcomes()
#' @param ... further arguments to eviction_adoption_outcomes()
eviction_control_states <- function(panel_states,
                                    treat_file,
                                    treat_date_col = "online_start_date",
                                    ...) {
  out <- eviction_adoption_outcomes(treat_file, treat_date_col, ...)
  panel_states <- unique(as.character(panel_states))

  dropped <- intersect(panel_states, PRE_PASPA_SPORTS_BETTING)
  if (length(dropped)) {
    warning("Excluding pre-PASPA sports-betting state(s) from the control pool: ",
            paste(dropped, collapse = ", "),
            ". These are always-treated, not never-treated.", call. = FALSE)
  }

  intersect(panel_states, out$state_abb[out$control_eligible])
}

#' Hard check that no pre-PASPA state has leaked into a control pool
#'
#' @param states the control states an analysis is about to use
#' @param context label for the error message
#' @param action "stop" (default) or "warn"
assert_no_pre_paspa_controls <- function(states, context = "control pool",
                                        action = c("stop", "warn")) {
  action <- match.arg(action)
  bad <- intersect(unique(as.character(states)), PRE_PASPA_SPORTS_BETTING)
  if (length(bad)) {
    msg <- paste0(context, " contains pre-PASPA sports-betting state(s): ",
                  paste(bad, collapse = ", "),
                  ". These had legal sports betting before the repeal and are ",
                  "absent from the schedule for that reason -- they are ",
                  "always-treated, not never-treated. Use ",
                  "eviction_control_states() to build the control pool.")
    if (action == "stop") stop(msg, call. = FALSE) else warning(msg, call. = FALSE)
  }
  invisible(TRUE)
}
