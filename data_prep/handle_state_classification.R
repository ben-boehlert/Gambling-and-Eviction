#!/usr/bin/env Rscript

# =============================================================================
# Handle-Based Treatment State Classification
# =============================================================================
# Purpose: Keep missing exposure data distinct from valid untreated controls.
# Inputs: Panel-state universe, legal online dates, observed Handle threshold
#         dates, and the prespecified study window.
# Outputs: One auditable row per panel state plus a variable codebook.

state_name_to_abb <- function(state_name) {
  state_name <- trimws(state_name)
  name_map <- c(stats::setNames(state.abb, state.name),
                "District of Columbia" = "DC")
  unname(name_map[state_name])
}

state_abb_to_name <- function(state_abb) {
  abb_map <- c(stats::setNames(state.name, state.abb),
               "DC" = "District of Columbia")
  unname(abb_map[state_abb])
}

paired_rds_path <- function(path) {
  if (grepl("\\.csv$", path, ignore.case = TRUE)) {
    return(sub("\\.csv$", ".rds", path, ignore.case = TRUE))
  }
  paste0(path, ".rds")
}

classify_handle_states <- function(panel_states,
                                   legal_schedule,
                                   threshold_dates,
                                   handle_data_states,
                                   study_start,
                                   study_cutoff,
                                   threshold_fraction = 0.5) {
  stopifnot(
    inherits(study_start, "Date"),
    inherits(study_cutoff, "Date"),
    study_start <= study_cutoff,
    threshold_fraction > 0,
    threshold_fraction <= 1
  )

  panel_universe <- dplyr::tibble(
    state_abb = sort(unique(as.character(panel_states)))
  ) %>%
    dplyr::mutate(state_name = state_abb_to_name(state_abb))

  legal_dates <- legal_schedule %>%
    dplyr::transmute(
      state_abb = state_name_to_abb(state),
      legal_online_start = as.Date(online_start_date)
    ) %>%
    dplyr::filter(!is.na(state_abb)) %>%
    dplyr::distinct(state_abb, .keep_all = TRUE)

  threshold_dates <- threshold_dates %>%
    dplyr::transmute(
      state_abb = as.character(state_abb),
      handle_threshold_start = as.Date(handle_threshold_start)
    ) %>%
    dplyr::distinct(state_abb, .keep_all = TRUE)

  classification <- panel_universe %>%
    dplyr::left_join(legal_dates, by = "state_abb") %>%
    dplyr::left_join(threshold_dates, by = "state_abb") %>%
    dplyr::mutate(
      study_start = study_start,
      study_cutoff = study_cutoff,
      handle_threshold_fraction = threshold_fraction,
      handle_data_available = state_abb %in% handle_data_states,
      handle_threshold_observed = !is.na(handle_threshold_start),
      handle_treatment_status = dplyr::case_when(
        state_abb == "NV" ~ "pre_sample_treated",
        !is.na(legal_online_start) & legal_online_start < study_start ~
          "pre_sample_treated",
        !is.na(legal_online_start) & legal_online_start > study_cutoff ~
          "not_yet_online_after_cutoff",
        is.na(legal_online_start) ~ "never_online_in_window",
        handle_threshold_observed ~ "observed_handle_threshold_treated",
        TRUE ~ "legally_online_missing_handle"
      ),
      control_eligible = handle_treatment_status %in% c(
        "not_yet_online_after_cutoff", "never_online_in_window"
      ),
      analysis_eligible = handle_treatment_status %in% c(
        "observed_handle_threshold_treated",
        "not_yet_online_after_cutoff",
        "never_online_in_window"
      ),
      exclusion_reason = dplyr::case_when(
        handle_treatment_status == "pre_sample_treated" ~
          "Sports betting exposure predates the study window",
        handle_treatment_status == "legally_online_missing_handle" ~
          "Online betting began within the study window but Handle exposure is missing",
        TRUE ~ NA_character_
      ),
      treat_start = dplyr::if_else(
        handle_treatment_status == "observed_handle_threshold_treated",
        handle_threshold_start,
        as.Date(NA)
      )
    ) %>%
    dplyr::select(
      state_abb, state_name, study_start, study_cutoff,
      legal_online_start, handle_threshold_fraction,
      handle_threshold_start, handle_data_available,
      handle_threshold_observed, handle_treatment_status,
      control_eligible, analysis_eligible, exclusion_reason, treat_start
    ) %>%
    dplyr::arrange(state_abb)

  if (anyDuplicated(classification$state_abb) > 0L) {
    stop("State classification contains duplicate state abbreviations")
  }
  if (any(is.na(classification$handle_treatment_status))) {
    stop("Every panel state must receive a Handle treatment status")
  }
  if (any(
    classification$handle_treatment_status == "legally_online_missing_handle" &
      classification$control_eligible
  )) {
    stop("Missing-exposure states cannot be eligible untreated controls")
  }
  if (any(
    classification$handle_treatment_status == "pre_sample_treated" &
      classification$control_eligible
  )) {
    stop("Pre-sample-treated states cannot be eligible untreated controls")
  }
  if (any(
    classification$analysis_eligible &
      is.na(classification$treat_start) &
      !classification$control_eligible
  )) {
    stop("Eligible untreated observations must have an explicit control status")
  }
  if (any(
    classification$handle_threshold_observed &
      !is.na(classification$legal_online_start) &
      classification$handle_threshold_start < classification$legal_online_start
  )) {
    stop("A Handle threshold date occurs before legal online launch")
  }

  classification
}

handle_classification_codebook <- function() {
  dplyr::tribble(
    ~variable_name, ~label, ~type, ~source, ~construction_notes,
    "state_abb", "State abbreviation", "character", "Eviction panel",
    "Unique state identifier in the estimator panel",
    "state_name", "State name", "character", "R state crosswalk",
    "Full state name derived from state_abb",
    "study_start", "Study-window start", "date", "Configuration",
    "States treated before this date are classified pre-sample treated",
    "study_cutoff", "Study-window cutoff", "date", "Configuration",
    "Legal launches after this date remain eligible not-yet-treated controls",
    "legal_online_start", "Legal online betting start", "date",
    "sports_gambling_legalization_dates.csv",
    "Verified online launch date; missing means no online launch in the schedule",
    "handle_threshold_fraction", "Fraction of peak Handle", "double",
    "Configuration", "Default 0.50; peak is calibrated through study_cutoff",
    "handle_threshold_start", "First Handle threshold month", "date",
    "LSR monthly Handle data",
    "First online-era month reaching the configured share of non-COVID peak",
    "handle_data_available", "Online-era Handle observed by cutoff", "logical",
    "LSR monthly Handle data",
    "True when at least one eligible Handle month is present by study_cutoff",
    "handle_threshold_observed", "Handle threshold observed", "logical",
    "Derived", "True when handle_threshold_start is nonmissing",
    "handle_treatment_status", "Treatment/control classification", "character",
    "Derived", paste(
      "One of observed_handle_threshold_treated, legally_online_missing_handle,",
      "pre_sample_treated, not_yet_online_after_cutoff, or never_online_in_window"
    ),
    "control_eligible", "Eligible untreated control", "logical", "Derived",
    "True only for not-yet-online-after-cutoff and never-online-in-window states",
    "analysis_eligible", "Eligible for Handle estimator panel", "logical", "Derived",
    "False for pre-sample-treated states and legally treated states missing Handle",
    "exclusion_reason", "Estimator-panel exclusion reason", "character", "Derived",
    "Nonmissing when analysis_eligible is false",
    "treat_start", "Estimator treatment date", "date", "Derived",
    "Handle threshold date for observed treated states; missing for eligible controls"
  )
}
