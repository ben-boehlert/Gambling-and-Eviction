#' Compute post-COVID cohort support for one treatment schedule
#'
#' @param state_schedule data.table with one row per state and columns
#'   `state_abb`, `legal_online_start`, and `effective_date`.
#' @param months Date vector defining the balanced analysis window.
#' @param sample_name character scalar naming the state sample.
#' @param design_name character scalar naming the treatment definition.
#' @param min_cohort_size integer threshold for a small cohort.
#' @return named list of state roles, cohort sizes, CS group-time support,
#'   SA event-time support, and one-row summaries.
compute_postcovid_handle_support <- function(
  state_schedule,
  months,
  sample_name,
  design_name,
  min_cohort_size = 5L
) {
  stopifnot(data.table::is.data.table(state_schedule))
  stopifnot(
    all(c("state_abb", "legal_online_start", "effective_date") %in%
          names(state_schedule))
  )
  stopifnot(length(months) > 1L, min_cohort_size > 0L)

  month_number <- \(x) {
    x_lt <- as.POSIXlt(as.Date(x))
    as.integer((x_lt$year + 1900L) * 12L + x_lt$mon)
  }
  number_to_date <- \(x) {
    year <- x %/% 12L
    month_zero <- x %% 12L
    as.Date(sprintf("%04d-%02d-01", year, month_zero + 1L))
  }

  start_date <- min(as.Date(months))
  end_date <- max(as.Date(months))
  start_number <- month_number(start_date)
  end_number <- month_number(end_date)

  roles <- data.table::copy(state_schedule)
  roles[, `:=`(
    legal_online_start = as.Date(legal_online_start),
    effective_date = as.Date(effective_date)
  )]
  roles[, treatment_role := data.table::fcase(
    !is.na(effective_date) & effective_date < start_date,
    "always_treated_excluded",
    !is.na(effective_date) & effective_date >= start_date &
      effective_date <= end_date,
    "treated_in_window",
    !is.na(effective_date) & effective_date > end_date,
    "not_yet_treated_control",
    is.na(effective_date) &
      (is.na(legal_online_start) | legal_online_start > end_date),
    "never_or_not_yet_control",
    default = "missing_effective_date_excluded"
  )]
  roles[, has_reference_month :=
          treatment_role != "treated_in_window" |
          effective_date > start_date]
  roles[, is_usable_treated :=
          treatment_role == "treated_in_window" & has_reference_month]
  roles[, is_control_eligible := treatment_role %chin% c(
    "not_yet_treated_control", "never_or_not_yet_control"
  )]
  roles[, cohort_month := data.table::fifelse(
    is_usable_treated,
    as.character(effective_date),
    NA_character_
  )]
  roles[, `:=`(
    sample = sample_name,
    treatment_definition = design_name
  )]

  cohort_sizes <- roles[is_usable_treated == TRUE,
                        .(n_treated_states = .N),
                        by = .(sample, treatment_definition, cohort_month)]
  cohort_sizes[, `:=`(
    cohort_date = as.Date(cohort_month),
    is_singleton = n_treated_states == 1L,
    is_small_cohort = n_treated_states < min_cohort_size
  )]
  data.table::setorder(cohort_sizes, cohort_date)

  roles <- cohort_sizes[
    roles,
    on = .(sample, treatment_definition, cohort_month)
  ]
  roles[, `:=`(
    n_treated_states = data.table::fcoalesce(n_treated_states, 0L),
    is_singleton = data.table::fcoalesce(is_singleton, FALSE),
    is_small_cohort = data.table::fcoalesce(is_small_cohort, FALSE)
  )]

  usable_roles <- roles[
    treatment_role %chin% c(
      "treated_in_window", "not_yet_treated_control",
      "never_or_not_yet_control"
    )
  ]
  treated_roles <- roles[is_usable_treated == TRUE]

  cs_cells <- data.table::data.table()
  if (nrow(treated_roles) > 0L) {
    cohort_dates <- sort(unique(treated_roles[["effective_date"]]))
    cs_list <- vector("list", length(cohort_dates))
    for (g_index in seq_along(cohort_dates)) {
      group_date <- cohort_dates[g_index]
      post_months <- as.Date(months[months >= group_date])
      group_size <- treated_roles[
        effective_date == group_date,
        data.table::uniqueN(state_abb)
      ]
      cs_list[[g_index]] <- data.table::data.table(
        sample = sample_name,
        treatment_definition = design_name,
        cohort_date = group_date,
        calendar_month = post_months,
        event_time = month_number(post_months) - month_number(group_date),
        n_treated_states = as.integer(group_size)
      )
    }
    cs_cells <- data.table::rbindlist(cs_list)
    cs_cells[, n_eligible_controls := vapply(
      calendar_month,
      \(calendar_date) usable_roles[
        is_control_eligible == TRUE |
          (is_usable_treated == TRUE & effective_date > calendar_date),
        data.table::uniqueN(state_abb)
      ],
      integer(1L)
    )]
    cs_cells[, `:=`(
      has_control_support = n_eligible_controls > 0L,
      has_small_treated_cohort = n_treated_states < min_cohort_size
    )]
  }

  sa_support <- data.table::data.table()
  if (nrow(treated_roles) > 0L) {
    sa_rows <- vector("list", nrow(treated_roles))
    for (state_index in seq_len(nrow(treated_roles))) {
      group_date <- treated_roles[["effective_date"]][state_index]
      group_number <- month_number(group_date)
      event_times <- seq.int(start_number - group_number,
                             end_number - group_number)
      sa_rows[[state_index]] <- data.table::data.table(
        state_abb = treated_roles[["state_abb"]][state_index],
        cohort_date = group_date,
        event_time = event_times
      )
    }
    sa_state_support <- data.table::rbindlist(sa_rows)
    sa_support <- sa_state_support[, .(
      n_treated_states = data.table::uniqueN(state_abb),
      n_cohorts = data.table::uniqueN(cohort_date)
    ), by = event_time]
    sa_support[, `:=`(
      sample = sample_name,
      treatment_definition = design_name,
      calendar_date_at_window_start = number_to_date(start_number),
      has_at_least_five_states = n_treated_states >= min_cohort_size
    )]
    data.table::setcolorder(
      sa_support,
      c("sample", "treatment_definition", "event_time",
        "n_treated_states", "n_cohorts", "has_at_least_five_states",
        "calendar_date_at_window_start")
    )
    data.table::setorder(sa_support, event_time)
  }

  n_treated <- nrow(treated_roles)
  n_singleton_states <- treated_roles[is_singleton == TRUE, .N]
  n_small_states <- treated_roles[is_small_cohort == TRUE, .N]
  design_summary <- data.table::data.table(
    sample = sample_name,
    treatment_definition = design_name,
    n_states_in_scope = nrow(roles),
    n_usable_states = nrow(usable_roles),
    n_treated_in_window = n_treated,
    n_treatment_cohorts = nrow(cohort_sizes),
    n_singleton_cohorts = cohort_sizes[is_singleton == TRUE, .N],
    share_treated_states_in_singletons = if (n_treated > 0L) {
      n_singleton_states / n_treated
    } else {
      NA_real_
    },
    n_small_cohorts = cohort_sizes[is_small_cohort == TRUE, .N],
    share_treated_states_in_small_cohorts = if (n_treated > 0L) {
      n_small_states / n_treated
    } else {
      NA_real_
    },
    max_cohort_size = if (nrow(cohort_sizes) > 0L) {
      max(cohort_sizes[["n_treated_states"]])
    } else {
      0L
    },
    n_always_treated_excluded = roles[
      treatment_role == "always_treated_excluded", .N
    ],
    n_missing_effective_excluded = roles[
      treatment_role == "missing_effective_date_excluded", .N
    ],
    n_controls_at_window_end = usable_roles[
      is_control_eligible == TRUE, .N
    ]
  )

  cs_summary <- data.table::data.table(
    sample = sample_name,
    treatment_definition = design_name,
    n_group_time_cells = nrow(cs_cells),
    n_cells_with_controls = if (nrow(cs_cells) > 0L) {
      cs_cells[has_control_support == TRUE, .N]
    } else {
      0L
    },
    share_cells_small_cohort = if (nrow(cs_cells) > 0L) {
      mean(cs_cells[["has_small_treated_cohort"]])
    } else {
      NA_real_
    },
    min_controls = if (nrow(cs_cells) > 0L) {
      min(cs_cells[["n_eligible_controls"]])
    } else {
      NA_integer_
    }
  )

  sa_summary <- data.table::data.table(
    sample = sample_name,
    treatment_definition = design_name,
    n_event_times = nrow(sa_support),
    n_states_at_event_0 = if (nrow(sa_support[event_time == 0L]) > 0L) {
      sa_support[event_time == 0L, n_treated_states]
    } else {
      0L
    },
    n_states_at_event_12 = if (nrow(sa_support[event_time == 12L]) > 0L) {
      sa_support[event_time == 12L, n_treated_states]
    } else {
      0L
    },
    n_states_at_event_24 = if (nrow(sa_support[event_time == 24L]) > 0L) {
      sa_support[event_time == 24L, n_treated_states]
    } else {
      0L
    },
    max_post_event_with_five_states = if (
      nrow(sa_support[event_time >= 0L & has_at_least_five_states == TRUE]) > 0L
    ) {
      max(sa_support[
        event_time >= 0L & has_at_least_five_states == TRUE,
        event_time
      ])
    } else {
      NA_integer_
    }
  )

  list(
    state_roles = roles,
    cohort_sizes = cohort_sizes,
    cs_group_time_support = cs_cells,
    sa_event_time_support = sa_support,
    design_summary = design_summary,
    cs_summary = cs_summary,
    sa_summary = sa_summary
  )
}
