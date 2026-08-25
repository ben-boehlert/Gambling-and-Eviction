# ==============================================================================
# fig1_singleton_cohorts_timeline.R
#
# Diagnostic figure: Gantt-style state-month coverage/treatment timeline,
# illustrating that online sports-gambling legalization dates are almost all
# unique across states -- i.e., under monthly timing every Callaway-Sant'Anna
# / Sun-Abraham cohort contains (close to) exactly one state, which is the
# structural reason those estimators run 4-5x noisier than TWFE on this
# design (see CLAUDE.md, "Heterogeneity-Robust Estimator Calibration").
#
# Companion panel compares cohort sizes under monthly timing (as observed)
# vs. annual aggregation (grouping treated states by calendar year of their
# online date), showing that coarsening the timing would create multi-state
# cohorts.
#
# Inputs:
#   data/raw/state_month_panel_with_treatment.csv
#   data/raw/sports_gambling_legalization_dates.csv
#   utils/eviction_treatment_schedule.R (loader; sourced, not rewritten)
#
# Outputs:
#   figures/estimator_diagnostics/fig1_singleton_cohorts_timeline.png
#   figures/estimator_diagnostics/fig1_singleton_cohorts_timeline.pdf
# ==============================================================================

library(tidyverse)
library(here)
library(patchwork)

theme_set(theme_minimal(base_size = 12))

# Okabe-Ito palette (colorblind-safe)
OKABE_ITO <- c(
  orange     = "#E69F00",
  sky_blue   = "#56B4E9",
  bluish_grn = "#009E73",
  vermillion = "#D55E00"
)

COVID_START <- as.Date("2020-03-01")
COVID_END   <- as.Date("2022-03-31")

# Display window for the Gantt panel. Only one state (verified below) has
# coverage before this date; truncating avoids ~3.5 years of near-total dead
# space while the caption documents the state and date range cut off.
DISPLAY_START <- as.Date("2015-07-01")

# Revision-round layout constants (coordinator request 2026-08-12): taller
# figure so 39 state rows are individually legible, small-but-readable axis
# text, single legend (fill only -- no data-coverage alpha channel).
FIG_WIDTH_IN  <- 10
FIG_HEIGHT_IN <- 13
FIG_DPI       <- 300
MAIN_HEIGHT_RATIO <- 4 / 5  # patchwork heights = c(4, 1) main:companion
AXIS_TEXT_PT  <- 7

panel_file <- here::here("data", "raw", "state_month_panel_with_treatment.csv")
sched_file <- here::here("data", "raw", "sports_gambling_legalization_dates.csv")
schedule_helper <- here::here("utils", "eviction_treatment_schedule.R")

source(schedule_helper)

# ------------------------------------------------------------------------
# 1. Load panel; drop the panel's own (stale) treat_start/treated columns --
#    treatment timing is computed fresh from the repaired legalization CSV.
# ------------------------------------------------------------------------
panel <- readr::read_csv(panel_file, show_col_types = FALSE) |>
  dplyr::select(-dplyr::any_of(c("treat_start", "treated")))

stopifnot(all(c("state_abb", "month_date", "filings_per_1k_renters") %in% names(panel)))

panel_states <- sort(unique(panel$state_abb))
panel_range  <- range(panel$month_date)

message(sprintf(
  "Panel: %d states, %s to %s",
  length(panel_states), format(panel_range[1]), format(panel_range[2])
))

# ------------------------------------------------------------------------
# 2. Treatment schedule from the repaired legalization-dates CSV.
#    "Treated in panel" = online date falls within the observed panel range.
#    Never-treated (in panel) = no online date, OR online date after the
#    panel's last observed month (e.g., MO Dec-2025).
# ------------------------------------------------------------------------
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

n_treated       <- sum(schedule$treated_in_panel)
n_never_treated <- sum(!schedule$treated_in_panel)

message(sprintf(
  "Treated in panel: %d | Never-treated in panel: %d",
  n_treated, n_never_treated
))

# ------------------------------------------------------------------------
# 3. Cohort structure -- verify singleton claim in code (do not assert it).
# ------------------------------------------------------------------------
monthly_cohorts <- schedule |>
  dplyr::filter(.data$treated_in_panel) |>
  dplyr::count(.data$treat_start, name = "n_states") |>
  dplyr::arrange(.data$treat_start)

non_singleton <- monthly_cohorts |> dplyr::filter(.data$n_states > 1L)
n_cohorts_monthly <- nrow(monthly_cohorts)
n_singleton <- sum(monthly_cohorts$n_states == 1L)

if (nrow(non_singleton) > 0L) {
  shared_states <- schedule |>
    dplyr::filter(.data$treated_in_panel, .data$treat_start %in% non_singleton$treat_start) |>
    dplyr::arrange(.data$treat_start, .data$state_abb) |>
    dplyr::group_by(.data$treat_start) |>
    dplyr::summarise(states = paste(.data$state_abb, collapse = ", "), .groups = "drop")
  shared_txt <- paste(
    sprintf("%s (%s)", format(shared_states$treat_start, "%b %Y"), shared_states$states),
    collapse = "; "
  )
  cohort_note <- sprintf(
    "%d treated states -> %d monthly cohorts: %d singleton (n=1), %d shared: %s",
    n_treated, n_cohorts_monthly, n_singleton, nrow(non_singleton), shared_txt
  )
} else {
  cohort_note <- sprintf(
    "%d treated states -> %d monthly cohorts, ALL singleton (n=1 state each)",
    n_treated, n_cohorts_monthly
  )
}
message(cohort_note)

# ------------------------------------------------------------------------
# 4. Build the state x month coverage grid.
#    Coverage = non-missing filings_per_1k_renters over the FULL panel
#    month range (a month with no row in `panel` counts as not covered).
# ------------------------------------------------------------------------
all_months <- seq(panel_range[1], panel_range[2], by = "1 month")

grid <- tidyr::expand_grid(state_abb = panel_states, month_date = all_months) |>
  dplyr::left_join(
    panel |> dplyr::select("state_abb", "month_date", "filings_per_1k_renters"),
    by = c("state_abb", "month_date")
  ) |>
  dplyr::mutate(covered = !is.na(.data$filings_per_1k_renters)) |>
  dplyr::left_join(
    schedule |> dplyr::select("state_abb", "treat_start", "treated_in_panel"),
    by = "state_abb"
  ) |>
  dplyr::mutate(
    treat_group = ifelse(.data$treated_in_panel, "Treated (in panel)", "Never-treated (in panel)")
  )

# Which state(s) have real coverage before the display truncation point?
# Computed from the data, not asserted -- reported in the caption and in
# the run log.
early_coverage <- grid |>
  dplyr::filter(.data$covered, .data$month_date < DISPLAY_START) |>
  dplyr::group_by(.data$state_abb) |>
  dplyr::summarise(earliest = min(.data$month_date), .groups = "drop") |>
  dplyr::arrange(.data$earliest)

if (nrow(early_coverage) > 0L) {
  early_txt <- paste(
    sprintf("%s (from %s)", early_coverage$state_abb, format(early_coverage$earliest, "%Y-%m")),
    collapse = ", "
  )
  truncation_note <- sprintf(
    "Display truncated to %s onward; %s had earlier coverage not shown here.",
    format(DISPLAY_START, "%Y-%m"), early_txt
  )
} else {
  truncation_note <- sprintf("Display truncated to %s onward; no state had earlier coverage.", format(DISPLAY_START, "%Y-%m"))
}
message(sprintf(
  "States with coverage before %s (cut off by display truncation): %s",
  format(DISPLAY_START), if (nrow(early_coverage) > 0L) paste(early_txt) else "none"
))

# ------------------------------------------------------------------------
# 5. Row order: treated states by ascending online date, then never-treated
#    states alphabetically.
# ------------------------------------------------------------------------
treated_order <- schedule |>
  dplyr::filter(.data$treated_in_panel) |>
  dplyr::arrange(.data$treat_start, .data$state_abb) |>
  dplyr::pull(.data$state_abb)

never_order <- schedule |>
  dplyr::filter(!.data$treated_in_panel) |>
  dplyr::arrange(.data$state_abb) |>
  dplyr::pull(.data$state_abb)

state_order <- c(treated_order, never_order)
stopifnot(setequal(state_order, panel_states))

grid <- grid |>
  dplyr::mutate(
    state_abb = factor(.data$state_abb, levels = rev(state_order)),
    treat_group = factor(
      .data$treat_group,
      levels = c("Treated (in panel)", "Never-treated (in panel)")
    )
  )

# ------------------------------------------------------------------------
# 6. Main Gantt tile plot.
#    - Truncated to DISPLAY_START onward (dead pre-2015-07 space dropped).
#    - Fill encodes treated/never-treated ONLY; uncovered state-months are
#      simply not drawn (blank background), so there is one legend, not two.
#    - COVID band is drawn AFTER the tile layer (semi-transparent, on top)
#      so it stays visible over covered tiles, not just in data gaps.
# ------------------------------------------------------------------------
grid_display <- grid |> dplyr::filter(.data$month_date >= DISPLAY_START)

treat_markers <- schedule |>
  dplyr::filter(.data$treated_in_panel, .data$treat_start >= DISPLAY_START) |>
  dplyr::mutate(state_abb = factor(.data$state_abb, levels = rev(state_order)))

# Light alternating row bands purely as a reading aid across 39 rows.
zebra <- tibble::tibble(state_abb = state_order) |>
  dplyr::mutate(
    row_idx = dplyr::row_number(),
    y_num = as.numeric(factor(.data$state_abb, levels = rev(state_order)))
  ) |>
  dplyr::filter(.data$row_idx %% 2L == 1L)

p_main <- ggplot() +
  geom_rect(
    data = zebra,
    aes(ymin = .data$y_num - 0.5, ymax = .data$y_num + 0.5),
    xmin = -Inf, xmax = Inf, fill = "grey93", inherit.aes = FALSE
  ) +
  geom_tile(
    data = grid_display |> dplyr::filter(.data$covered),
    aes(x = .data$month_date, y = .data$state_abb, fill = .data$treat_group),
    height = 0.85
  ) +
  geom_point(
    data = treat_markers,
    aes(x = .data$treat_start, y = .data$state_abb),
    shape = 17, size = 1.8, color = "black", inherit.aes = FALSE
  ) +
  annotate(
    "rect",
    xmin = COVID_START, xmax = COVID_END, ymin = -Inf, ymax = Inf,
    fill = "grey20", alpha = 0.35
  ) +
  geom_vline(xintercept = c(COVID_START, COVID_END), linetype = "dashed", color = "grey20", linewidth = 0.4) +
  scale_fill_manual(
    name = NULL,
    values = c(
      "Treated (in panel)"        = unname(OKABE_ITO["vermillion"]),
      "Never-treated (in panel)"  = unname(OKABE_ITO["sky_blue"])
    )
  ) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y", expand = c(0.01, 0.01)) +
  scale_y_discrete(drop = FALSE) +
  labs(
    title = "Every online-legalization date is (almost) a cohort of one",
    subtitle = cohort_note,
    x = NULL,
    y = NULL,
    caption = stringr::str_wrap(
      paste0(
        "Black triangles mark each treated state's online legalization month. ",
        "Dark band with dashed boundaries = COVID window (2020-03 to 2022-03), excluded from estimation samples. ",
        "Blank cells = state-month not covered by the ETS panel. ",
        truncation_note, " ",
        "Source: state_month_panel_with_treatment.csv; sports_gambling_legalization_dates.csv (repaired 2026-08-10)."
      ),
      width = 130
    )
  ) +
  theme(
    legend.position = "bottom",
    axis.text.y = element_text(size = AXIS_TEXT_PT),
    axis.text.x = element_text(size = 9),
    plot.caption = element_text(hjust = 0, size = 8, color = "grey30")
  )

# ------------------------------------------------------------------------
# 7. Companion panel: cohort sizes, monthly (as-is) vs. annual aggregation.
# ------------------------------------------------------------------------
annual_cohorts <- schedule |>
  dplyr::filter(.data$treated_in_panel) |>
  dplyr::mutate(cohort_year = lubridate::year(.data$treat_start)) |>
  dplyr::count(.data$cohort_year, name = "n_states")

cohort_compare <- dplyr::bind_rows(
  monthly_cohorts |>
    dplyr::transmute(
      granularity = "Monthly timing (as observed)",
      cohort_label = format(.data$treat_start, "%Y-%m"),
      cohort_order = .data$treat_start,
      n_states = .data$n_states
    ),
  annual_cohorts |>
    dplyr::transmute(
      granularity = "Annual aggregation (by calendar year)",
      cohort_label = as.character(.data$cohort_year),
      cohort_order = as.Date(sprintf("%d-01-01", .data$cohort_year)),
      n_states = .data$n_states
    )
) |>
  dplyr::mutate(
    granularity = factor(
      .data$granularity,
      levels = c("Monthly timing (as observed)", "Annual aggregation (by calendar year)")
    )
  )

# preserve chronological x-order within each facet
cohort_compare <- cohort_compare |>
  dplyr::group_by(.data$granularity) |>
  dplyr::mutate(cohort_label = forcats::fct_reorder(.data$cohort_label, .data$cohort_order)) |>
  dplyr::ungroup()

p_companion <- ggplot(cohort_compare, aes(x = .data$cohort_label, y = .data$n_states)) +
  geom_col(fill = unname(OKABE_ITO["orange"])) +
  geom_text(aes(label = .data$n_states), vjust = -0.4, size = 3) +
  facet_wrap(~ .data$granularity, scales = "free_x") +
  scale_y_continuous(breaks = scales::breaks_pretty(), expand = expansion(mult = c(0, 0.15))) +
  labs(
    x = "Cohort (treatment timing unit)",
    y = "States in cohort"
  ) +
  theme(
    axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 1, size = 6),
    strip.text = element_text(face = "bold")
  )

fig1 <- p_main / p_companion + patchwork::plot_layout(heights = c(4, 1))

# ------------------------------------------------------------------------
# 8. Row-legibility sanity check (coordinator-requested, revision round).
#    Engineering estimate, not a rendered-pixel measurement: allocate the
#    main block's share of total figure height, subtract a conservative
#    (generous) allowance for title/subtitle/legend/caption/axis chrome,
#    and confirm the remaining per-row pixel budget clears the axis-text
#    glyph height (with 30% line-height slack). Actual legibility is also
#    confirmed by visual inspection of the rendered PNG.
# ------------------------------------------------------------------------
CHROME_PT <- 170  # title + subtitle + legend + caption + x-axis/margins
main_block_height_in <- FIG_HEIGHT_IN * MAIN_HEIGHT_RATIO
panel_height_in <- main_block_height_in - (CHROME_PT / 72)
panel_height_px <- panel_height_in * FIG_DPI
n_rows <- length(state_order)
per_row_px <- panel_height_px / n_rows
required_label_px <- (AXIS_TEXT_PT / 72) * FIG_DPI * 1.3

message(sprintf(
  "Row legibility check: est. panel height %.0f px / %d rows = %.1f px/row (need >= %.1f px for %gpt labels)",
  panel_height_px, n_rows, per_row_px, required_label_px, AXIS_TEXT_PT
))
stopifnot(per_row_px >= required_label_px)

out_dir <- here::here("figures", "estimator_diagnostics")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

ggsave(
  file.path(out_dir, "fig1_singleton_cohorts_timeline.png"),
  fig1, width = FIG_WIDTH_IN, height = FIG_HEIGHT_IN, dpi = FIG_DPI
)
ggsave(
  file.path(out_dir, "fig1_singleton_cohorts_timeline.pdf"),
  fig1, width = FIG_WIDTH_IN, height = FIG_HEIGHT_IN
)

message(sprintf(
  "Saved fig1_singleton_cohorts_timeline.png / .pdf (%g x %g in @ %g dpi)",
  FIG_WIDTH_IN, FIG_HEIGHT_IN, FIG_DPI
))
