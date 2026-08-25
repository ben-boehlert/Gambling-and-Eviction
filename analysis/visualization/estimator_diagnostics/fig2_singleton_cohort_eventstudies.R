# ==============================================================================
# fig2_singleton_cohort_eventstudies.R
#
# Diagnostic figure: per-cohort (per-state) event-study paths of log filings
# relative to the never-treated mean, re-centered to 0 at event time -1. Since
# every treated state is (almost always) its own cohort, each gray line here
# IS an entire cohort's ATT(g,t) path estimated from a single state (n=1).
# Cross-line dispersion is single-state sampling noise, not treatment-effect
# heterogeneity a heterogeneity-robust estimator could average away.
#
# Inputs:
#   data/raw/state_month_panel_with_treatment.csv
#   data/raw/sports_gambling_legalization_dates.csv
#   utils/eviction_treatment_schedule.R (loader; sourced, not rewritten)
#
# Outputs:
#   figures/estimator_diagnostics/fig2_singleton_cohort_eventstudies.png
#   figures/estimator_diagnostics/fig2_singleton_cohort_eventstudies.pdf
# ==============================================================================

library(tidyverse)
library(here)

theme_set(theme_minimal(base_size = 12))

has_ggrepel <- requireNamespace("ggrepel", quietly = TRUE)
if (has_ggrepel) library(ggrepel)

OKABE_ITO <- c(
  vermillion = "#D55E00",
  blue       = "#0072B2",
  bluish_grn = "#009E73",
  orange     = "#E69F00"
)

COVID_START <- as.Date("2020-03-01")
COVID_END   <- as.Date("2022-03-31")
EVENT_MIN   <- -36L
EVENT_MAX   <- 36L
N_HIGHLIGHT <- 4L  # top-2 / bottom-2 by mean post-period effect

panel_file <- here::here("data", "raw", "state_month_panel_with_treatment.csv")
sched_file <- here::here("data", "raw", "sports_gambling_legalization_dates.csv")
schedule_helper <- here::here("utils", "eviction_treatment_schedule.R")

source(schedule_helper)

# ------------------------------------------------------------------------
# 1. Load panel and treatment schedule (same construction as fig1).
# ------------------------------------------------------------------------
panel <- readr::read_csv(panel_file, show_col_types = FALSE) |>
  dplyr::select(-dplyr::any_of(c("treat_start", "treated")))

panel_states <- sort(unique(panel$state_abb))
panel_range  <- range(panel$month_date)

schedule <- load_eviction_treatment_schedule(
  treat_file     = sched_file,
  treat_date_col = "online_start_date",
  states         = panel_states
) |>
  dplyr::mutate(
    treated_in_panel = !is.na(.data$treat_start) &
      .data$treat_start >= panel_range[1] &
      .data$treat_start <= panel_range[2]
  )

treated_states <- schedule |> dplyr::filter(.data$treated_in_panel) |> dplyr::pull(.data$state_abb)
never_states   <- schedule |> dplyr::filter(!.data$treated_in_panel) |> dplyr::pull(.data$state_abb)

# ------------------------------------------------------------------------
# 2. Outcome transform. Guard against zeros/negatives before choosing log
#    vs. log1p (numerical discipline: never assume the offset is needed).
# ------------------------------------------------------------------------
has_nonpositive <- any(panel$filings_per_1k_renters <= 0, na.rm = TRUE)
panel <- panel |>
  dplyr::mutate(
    y = if (has_nonpositive) log1p(.data$filings_per_1k_renters) else log(.data$filings_per_1k_renters),
    covid = .data$month_date >= COVID_START & .data$month_date <= COVID_END
  )
message(sprintf(
  "Outcome transform: %s (non-positive values present: %s)",
  if (has_nonpositive) "log1p" else "log", has_nonpositive
))

# ------------------------------------------------------------------------
# 3. Never-treated control mean, by month (uses only never-treated states
#    with actual coverage that month).
# ------------------------------------------------------------------------
control_mean <- panel |>
  dplyr::filter(.data$state_abb %in% never_states, !is.na(.data$y)) |>
  dplyr::group_by(.data$month_date) |>
  dplyr::summarise(control_mean = mean(.data$y), n_control = dplyr::n(), .groups = "drop")

# ------------------------------------------------------------------------
# 4. Treated-state series: d_raw = y - control_mean(t), event_time = months
#    since online date.
# ------------------------------------------------------------------------
trt <- panel |>
  dplyr::filter(.data$state_abb %in% treated_states) |>
  dplyr::left_join(schedule |> dplyr::select("state_abb", "treat_start"), by = "state_abb") |>
  dplyr::left_join(control_mean, by = "month_date") |>
  dplyr::mutate(
    event_time = (lubridate::year(.data$month_date) - lubridate::year(.data$treat_start)) * 12L +
      (lubridate::month(.data$month_date) - lubridate::month(.data$treat_start)),
    d_raw = .data$y - .data$control_mean
  )

states_with_coverage <- sort(unique(trt$state_abb[!is.na(trt$d_raw)]))
states_no_coverage <- setdiff(treated_states, states_with_coverage)
if (length(states_no_coverage) > 0L) {
  message(sprintf(
    "Treated states with zero usable data (dropped from Fig 2): %s",
    paste(states_no_coverage, collapse = ", ")
  ))
}

# ------------------------------------------------------------------------
# 5. Re-centering reference: value at event_time == -1, using the nearest
#    available (non-missing, non-COVID) pre-period month if -1 itself is
#    unavailable or falls in the COVID window.
# ------------------------------------------------------------------------
ref <- trt |>
  dplyr::filter(.data$event_time < 0L, !is.na(.data$d_raw), !.data$covid) |>
  dplyr::group_by(.data$state_abb) |>
  dplyr::filter(.data$event_time == max(.data$event_time)) |>
  dplyr::summarise(
    ref_value = dplyr::first(.data$d_raw),
    ref_event_time = dplyr::first(.data$event_time),
    .groups = "drop"
  )

fallback_ref <- ref |> dplyr::filter(.data$ref_event_time != -1L)
if (nrow(fallback_ref) > 0L) {
  message(sprintf(
    "States where event time -1 was unavailable/COVID -- re-centered at nearest pre-period month instead: %s",
    paste(sprintf("%s (t=%d)", fallback_ref$state_abb, fallback_ref$ref_event_time), collapse = ", ")
  ))
}

states_no_ref <- setdiff(states_with_coverage, ref$state_abb)
if (length(states_no_ref) > 0L) {
  message(sprintf(
    "States with coverage but no valid pre-period reference (dropped): %s",
    paste(states_no_ref, collapse = ", ")
  ))
}

trt <- trt |>
  dplyr::inner_join(ref, by = "state_abb") |>
  dplyr::mutate(
    d_centered = .data$d_raw - .data$ref_value,
    # gap the plotted line across COVID months without dropping event_time
    d_plot = ifelse(.data$covid, NA_real_, .data$d_centered)
  ) |>
  dplyr::filter(.data$event_time >= EVENT_MIN, .data$event_time <= EVENT_MAX)

states_plotted <- sort(unique(trt$state_abb))

states_no_post <- setdiff(
  states_plotted,
  trt |>
    dplyr::filter(.data$event_time >= 0L, !is.na(.data$d_plot)) |>
    dplyr::pull(.data$state_abb) |>
    unique()
)
if (length(states_no_post) > 0L) {
  message(sprintf(
    "States plotted with pre-period-only coverage (no usable post-treatment data): %s",
    paste(states_no_post, collapse = ", ")
  ))
}

# ------------------------------------------------------------------------
# 6. Pick highlight states: most extreme mean post-treatment path (top 2 /
#    bottom 2), determined from the data -- not hardcoded.
# ------------------------------------------------------------------------
post_means <- trt |>
  dplyr::filter(.data$event_time >= 0L, !is.na(.data$d_plot)) |>
  dplyr::group_by(.data$state_abb) |>
  dplyr::summarise(mean_post = mean(.data$d_plot), n_post = dplyr::n(), .groups = "drop") |>
  dplyr::arrange(.data$mean_post)

n_avail <- nrow(post_means)
n_bottom <- min(2L, n_avail %/% 2L)
n_top <- min(N_HIGHLIGHT - n_bottom, n_avail - n_bottom)

highlight_states <- unique(c(
  utils::head(post_means$state_abb, n_bottom),
  utils::tail(post_means$state_abb, n_top)
))

message(sprintf(
  "Highlighted states (extreme mean post-treatment gap): %s",
  paste(highlight_states, collapse = ", ")
))
print(post_means, n = 30)

# ------------------------------------------------------------------------
# 7. Cross-cohort mean path (the CS-style aggregate across singleton
#    cohorts) and end-point labels for highlighted states.
# ------------------------------------------------------------------------
mean_path <- trt |>
  dplyr::filter(!is.na(.data$d_plot)) |>
  dplyr::group_by(.data$event_time) |>
  dplyr::summarise(d_plot = mean(.data$d_plot), n_states = dplyr::n(), .groups = "drop")

trt <- trt |>
  dplyr::mutate(is_highlight = .data$state_abb %in% highlight_states)

label_pts <- trt |>
  dplyr::filter(.data$is_highlight, !is.na(.data$d_plot)) |>
  dplyr::group_by(.data$state_abb) |>
  dplyr::filter(.data$event_time == max(.data$event_time)) |>
  dplyr::ungroup()

highlight_palette <- setNames(
  unname(OKABE_ITO)[seq_along(highlight_states)],
  highlight_states
)

n_gray <- length(states_plotted) - length(highlight_states)

subtitle_txt <- paste0(
  sprintf(
    "%d treated-state paths shown (of %d treated in panel; %d lack usable data). ",
    length(states_plotted), length(treated_states), length(states_no_coverage)
  ),
  "Each gray line is an entire cohort's ATT(g,t) path estimated from n=1 state -- ",
  "cross-line spread is single-state noise, not averageable treatment heterogeneity."
)

# ------------------------------------------------------------------------
# 8. Plot.
# ------------------------------------------------------------------------
p <- ggplot() +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey40", linewidth = 0.4) +
  geom_vline(xintercept = -0.5, linetype = "dotted", color = "grey60", linewidth = 0.4) +
  geom_line(
    data = trt |> dplyr::filter(!.data$is_highlight),
    aes(x = .data$event_time, y = .data$d_plot, group = .data$state_abb),
    color = "grey75", linewidth = 0.35, alpha = 0.8, na.rm = TRUE
  ) +
  geom_line(
    data = trt |> dplyr::filter(.data$is_highlight),
    aes(x = .data$event_time, y = .data$d_plot, color = .data$state_abb),
    linewidth = 0.9, na.rm = TRUE
  ) +
  geom_line(
    data = mean_path,
    aes(x = .data$event_time, y = .data$d_plot),
    color = "black", linewidth = 1.1, na.rm = TRUE
  ) +
  scale_color_manual(name = "Highlighted state", values = highlight_palette) +
  scale_x_continuous(breaks = seq(EVENT_MIN, EVENT_MAX, by = 12)) +
  coord_cartesian(xlim = c(EVENT_MIN, EVENT_MAX + (if (has_ggrepel) 0 else 6))) +
  labs(
    title = "Singleton-cohort event studies: each line is one state's ATT(g,t) path",
    subtitle = stringr::str_wrap(subtitle_txt, width = 130),
    x = "Event time (months since state's online legalization date)",
    y = "log(filings per 1k renters) - never-treated mean (re-centered to 0 at t = -1)",
    caption = stringr::str_wrap(
      paste0(
        "Bold black line = unweighted cross-cohort mean (CS-style aggregate). ",
        "Gap in a colored/gray line = COVID window (2020-03 to 2022-03), dropped from the series. ",
        "Source: state_month_panel_with_treatment.csv; sports_gambling_legalization_dates.csv (repaired 2026-08-10)."
      ),
      width = 130
    )
  ) +
  theme(
    legend.position = "bottom",
    plot.caption = element_text(hjust = 0, size = 8, color = "grey30")
  )

if (has_ggrepel) {
  p <- p + ggrepel::geom_text_repel(
    data = label_pts,
    aes(x = .data$event_time, y = .data$d_plot, label = .data$state_abb, color = .data$state_abb),
    fontface = "bold", size = 3.2, direction = "y", hjust = 0, nudge_x = 2,
    segment.size = 0.3, show.legend = FALSE, max.overlaps = Inf
  )
} else {
  p <- p + geom_text(
    data = label_pts,
    aes(x = .data$event_time, y = .data$d_plot, label = .data$state_abb, color = .data$state_abb),
    fontface = "bold", size = 3.2, hjust = 0, nudge_x = 1.5, show.legend = FALSE
  )
}

out_dir <- here::here("figures", "estimator_diagnostics")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

ggsave(
  file.path(out_dir, "fig2_singleton_cohort_eventstudies.png"),
  p, width = 10, height = 7, dpi = 300
)
ggsave(
  file.path(out_dir, "fig2_singleton_cohort_eventstudies.pdf"),
  p, width = 10, height = 7
)

message("Saved fig2_singleton_cohort_eventstudies.png / .pdf")
