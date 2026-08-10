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
