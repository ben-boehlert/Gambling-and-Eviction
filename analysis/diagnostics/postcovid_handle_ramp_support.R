#!/usr/bin/env Rscript

# ==============================================================================
# postcovid_handle_ramp_support.R
# Post-COVID support from legal dates and Handle maturation dates
# Paper: Gambling and Eviction, treatment-support diagnostic
# Inputs: ETS state-month panel, legalization schedule, LSR Handle data,
#         activity treatment dates, Handle state classification
# Outputs: output/postcovid_handle_ramp_support/*.csv, *.rds, *.md, *.png
# ==============================================================================

# 0. Setup --------------------------------------------------------------------

library(data.table)
library(ggplot2)
library(here)

SEED <- 20260814L
STUDY_START <- as.Date("2022-04-01")
STUDY_END <- as.Date("2024-12-01")
PEAK_CALIBRATION_END <- as.Date("2024-12-31")
COVID_PEAK_START <- as.Date("2020-03-01")
COVID_PEAK_END <- as.Date("2021-07-31")
MIN_COHORT_SIZE <- 5L

set.seed(SEED)

OUTPUT_DIR <- here("output", "postcovid_handle_ramp_support")
PANEL_FILE <- here(
  "data", "processed", "state_month_panel_handle50_treatment.csv"
)
ACTIVITY_FILE <- here(
  "data", "processed", "activity_treatment_dates.csv"
)
CLASSIFICATION_FILE <- here(
  "data", "processed", "handle50_state_classification.csv"
)
HANDLE_FILE <- here(
  "data", "raw", "lsr_sports_betting_handle_revenue_by_state_month.csv"
)
SUPPORT_FUNCTION_FILE <- here(
  "analysis", "diagnostics", "functions",
  "compute_postcovid_handle_support.R"
)

required_files <- c(
  PANEL_FILE, ACTIVITY_FILE, CLASSIFICATION_FILE, HANDLE_FILE,
  SUPPORT_FUNCTION_FILE
)
missing_files <- required_files[!file.exists(required_files)]
if (length(missing_files) > 0L) {
  stop(
    sprintf("Missing required files: %s", paste(missing_files, collapse = ", ")),
    call. = FALSE
  )
}

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
source(SUPPORT_FUNCTION_FILE)

# ============================================================
# Paper-to-Code Naming Map
# ============================================================
# Paper Notation       | Code Name                  | Description
# $Y_{st}$             | filings_count              | State-month filings
# $G_s^{legal}$        | online_start_date          | Online legal month
# $G_s^{25}$           | handle_25_date             | 25%-peak crossing
# $G_s^{50}$           | handle_50_date             | 50%-peak crossing
# $G_s^{75}$           | handle_75_date             | 75%-peak crossing
# $G_s^{50,S}$         | handle_50_sustained_date   | 3-month 50% crossing
# $C_s^q$              | is_pre_window_candidate    | Pre-window legal,
#                                                   | in-window threshold
# $e_{st}$             | event_time                 | Relative month
# ============================================================

# 1. Load and validate the analysis universe ----------------------------------

panel <- fread(PANEL_FILE)
panel[, month_date := as.Date(month_date)]
panel_window <- panel[
  month_date >= STUDY_START & month_date <= STUDY_END
]

expected_months <- seq(STUDY_START, STUDY_END, by = "month")
expected_n_months <- as.integer(length(expected_months))
panel_coverage <- panel_window[, .(
  n_months = uniqueN(month_date),
  n_rows = .N
), by = state_abb]

if (any(panel_coverage[["n_rows"]] != panel_coverage[["n_months"]])) {
  stop("The state-month panel has duplicate state-month rows.", call. = FALSE)
}

balanced_states <- panel_coverage[
  n_months == expected_n_months,
  sort(state_abb)
]
eligible_states <- sort(unique(panel[["state_abb"]]))

if (length(balanced_states) != 28L || length(eligible_states) != 37L) {
  stop(
    sprintf(
      "Unexpected sample dimensions: %d balanced and %d eligible states.",
      length(balanced_states), length(eligible_states)
    ),
    call. = FALSE
  )
}
if (any(c("FL", "NV") %chin% eligible_states)) {
  stop("Florida and Nevada must be excluded from Handle analysis.",
       call. = FALSE)
}

activity <- fread(ACTIVITY_FILE)
date_columns <- c(
  "legal_online_start", "treat_25pct_peak", "treat_50pct_peak",
  "treat_75pct_peak"
)
activity[, (date_columns) := lapply(.SD, as.Date), .SDcols = date_columns]

classification <- fread(CLASSIFICATION_FILE)
classification[, `:=`(
  legal_online_start = as.Date(legal_online_start),
  handle_threshold_start = as.Date(handle_threshold_start)
)]

stopifnot(
  classification[state_abb == "FL", analysis_eligible] == FALSE,
  classification[state_abb == "NV", analysis_eligible] == FALSE
)

# 2. Reconstruct sustained 50%-of-peak dates -------------------------------

state_crosswalk <- data.table(
  State = c(state.name, "District of Columbia"),
  state_abb = c(state.abb, "DC")
)
legal_dates <- activity[, .(state_abb, legal_online_start)]

handle <- fread(HANDLE_FILE)
handle[, month_date := as.Date(month_date)]
handle <- state_crosswalk[
  handle,
  on = "State",
  nomatch = 0L
]
handle <- legal_dates[
  handle,
  on = "state_abb",
  nomatch = 0L
]
handle <- handle[
  !is.na(legal_online_start) &
    month_date >= legal_online_start &
    month_date <= PEAK_CALIBRATION_END &
    !is.na(Handle) & Handle > 0
]

peaks <- handle[
  month_date < COVID_PEAK_START | month_date > COVID_PEAK_END,
  .(peak_handle = max(Handle)),
  by = state_abb
]
if (any(!is.finite(peaks[["peak_handle"]]) | peaks[["peak_handle"]] <= 0)) {
  stop("Invalid frozen Handle peak.", call. = FALSE)
}

handle <- peaks[handle, on = "state_abb", nomatch = 0L]
handle[, month_number := as.integer(
  (as.POSIXlt(month_date)$year + 1900L) * 12L + as.POSIXlt(month_date)$mon
)]
handle[, is_above_50 := Handle >= 0.5 * peak_handle]
setorder(handle, state_abb, month_date)
handle[, `:=`(
  lead_one_above = shift(is_above_50, 1L, type = "lead"),
  lead_two_above = shift(is_above_50, 2L, type = "lead"),
  lead_one_month = shift(month_number, 1L, type = "lead"),
  lead_two_month = shift(month_number, 2L, type = "lead")
), by = state_abb]

sustained_dates <- handle[
  is_above_50 == TRUE &
    lead_one_above == TRUE & lead_two_above == TRUE &
    lead_one_month == month_number + 1L &
    lead_two_month == month_number + 2L,
  .(handle_50_sustained_date = min(month_date)),
  by = state_abb
]

threshold_check <- activity[
  !is.na(treat_50pct_peak),
  .(state_abb, treat_50pct_peak)
]
threshold_check <- sustained_dates[
  threshold_check,
  on = "state_abb"
]
if (any(
  !is.na(threshold_check[["handle_50_sustained_date"]]) &
    threshold_check[["handle_50_sustained_date"]] <
      threshold_check[["treat_50pct_peak"]]
)) {
  stop("A sustained crossing precedes the first 50% crossing.",
       call. = FALSE)
}

# 3. Assemble legal and effective treatment schedules -------------------------

state_schedule <- activity[, .(
  state_abb,
  state_name = State,
  legal_online_start,
  handle_25_date = treat_25pct_peak,
  handle_50_date = treat_50pct_peak,
  handle_75_date = treat_75pct_peak
)]
state_schedule <- sustained_dates[
  state_schedule,
  on = "state_abb"
]

window_handle <- handle[
  month_date == STUDY_START,
  .(
    handle_at_window_start = Handle,
    peak_handle,
    handle_fraction_at_window_start = Handle / peak_handle
  ),
  by = state_abb
]
state_schedule <- window_handle[state_schedule, on = "state_abb"]

design_columns <- c(
  online_legal = "legal_online_start",
  handle_25 = "handle_25_date",
  handle_50 = "handle_50_date",
  handle_75 = "handle_75_date",
  handle_50_sustained = "handle_50_sustained_date"
)
sample_states <- list(
  balanced_postcovid_28 = balanced_states,
  all_handle_eligible_37 = eligible_states
)

diagnostics <- list()
diagnostic_index <- 0L
for (sample_name in names(sample_states)) {
  states_i <- sample_states[[sample_name]]
  schedule_i <- state_schedule[state_abb %chin% states_i]
  if (nrow(schedule_i) != length(states_i)) {
    stop(sprintf("Missing schedule rows in %s.", sample_name), call. = FALSE)
  }
  for (design_name in names(design_columns)) {
    diagnostic_index <- diagnostic_index + 1L
    date_column <- design_columns[[design_name]]
    schedule_design <- schedule_i[, .(
      state_abb,
      state_name,
      legal_online_start,
      effective_date = get(date_column),
      handle_at_window_start,
      peak_handle,
      handle_fraction_at_window_start
    )]
    diagnostics[[diagnostic_index]] <- compute_postcovid_handle_support(
      state_schedule = schedule_design,
      months = expected_months,
      sample_name = sample_name,
      design_name = design_name,
      min_cohort_size = MIN_COHORT_SIZE
    )
  }
}

bind_component <- \(component) {
  rbindlist(lapply(diagnostics, `[[`, component), fill = TRUE)
}

state_roles <- bind_component("state_roles")
cohort_sizes <- bind_component("cohort_sizes")
cs_support <- bind_component("cs_group_time_support")
sa_support <- bind_component("sa_event_time_support")
design_summary <- bind_component("design_summary")
cs_summary <- bind_component("cs_summary")
sa_summary <- bind_component("sa_summary")

# 4. Candidate-state and incremental-support diagnostics ----------------------

candidates <- state_roles[
  treatment_definition != "online_legal" &
    !is.na(legal_online_start) & legal_online_start < STUDY_START &
    is_usable_treated == TRUE
]
candidates[, `:=`(
  months_legal_before_window = as.integer(
    (as.POSIXlt(STUDY_START)$year - as.POSIXlt(legal_online_start)$year) *
      12L + as.POSIXlt(STUDY_START)$mon -
      as.POSIXlt(legal_online_start)$mon
  ),
  pre_threshold_months_in_window = as.integer(
    (as.POSIXlt(effective_date)$year - as.POSIXlt(STUDY_START)$year) *
      12L + as.POSIXlt(effective_date)$mon -
      as.POSIXlt(STUDY_START)$mon
  ),
  post_threshold_months_in_window = as.integer(
    (as.POSIXlt(STUDY_END)$year - as.POSIXlt(effective_date)$year) *
      12L + as.POSIXlt(STUDY_END)$mon -
      as.POSIXlt(effective_date)$mon + 1L
  )
)]

candidates[, recommendation := data.table::fcase(
  state_abb == "AR" & treatment_definition == "handle_25",
  "sensitivity_only_preferred",
  state_abb == "AR" & treatment_definition %chin%
    c("handle_50", "handle_50_sustained"),
  "sensitivity_only_speculative",
  default = "reject_as_untreated"
)]
candidates[, credibility_rank := data.table::fcase(
  recommendation == "sensitivity_only_preferred", 1L,
  recommendation == "sensitivity_only_speculative", 2L,
  default = 3L
)]
candidates[, credibility_reason := data.table::fcase(
  recommendation == "sensitivity_only_preferred",
  paste0(
    "Legalized one month before the window and joins the September 2022 ",
    "cohort, but the threshold is post-treatment."
  ),
  recommendation == "sensitivity_only_speculative",
  paste0(
    "Adds Arkansas after a longer legally exposed ramp; useful only as an ",
    "estimand-changing sensitivity."
  ),
  treatment_definition == "handle_75",
  paste0(
    "Already legally active and often above lower thresholds before the ",
    "window; 75% timing is endogenous and seasonal."
  ),
  default = paste0(
    "Legally exposed before the window; delayed sustained crossing does not ",
    "establish absence of earlier effects."
  )
)]
setorder(
  candidates, sample, credibility_rank, state_abb, treatment_definition
)

baseline_summary <- design_summary[
  treatment_definition == "online_legal",
  .(
    sample,
    baseline_treated = n_treated_in_window,
    baseline_cohorts = n_treatment_cohorts,
    baseline_singletons = n_singleton_cohorts,
    baseline_singleton_state_share = share_treated_states_in_singletons
  )
]
incremental_summary <- baseline_summary[
  design_summary,
  on = "sample"
]
incremental_summary[, `:=`(
  incremental_treated_vs_legal = n_treated_in_window - baseline_treated,
  incremental_cohorts_vs_legal = n_treatment_cohorts - baseline_cohorts,
  singleton_cohorts_change = n_singleton_cohorts - baseline_singletons,
  singleton_state_share_change =
    share_treated_states_in_singletons - baseline_singleton_state_share
)]

# 5. Export reproducible diagnostics ------------------------------------------

outputs <- list(
  panel_coverage = panel_coverage,
  frozen_handle_peaks = peaks,
  sustained_50_dates = sustained_dates,
  treatment_schedule = state_schedule,
  state_roles = state_roles,
  cohort_sizes = cohort_sizes,
  candidate_states = candidates,
  design_summary = design_summary,
  incremental_summary = incremental_summary,
  cs_group_time_support = cs_support,
  cs_support_summary = cs_summary,
  sa_event_time_support = sa_support,
  sa_support_summary = sa_summary
)

for (output_name in names(outputs)) {
  output_object <- outputs[[output_name]]
  fwrite(
    output_object,
    file.path(OUTPUT_DIR, paste0(output_name, ".csv")),
    na = ""
  )
  saveRDS(
    output_object,
    file.path(OUTPUT_DIR, paste0(output_name, ".rds"))
  )
}
saveRDS(diagnostics, file.path(OUTPUT_DIR, "all_support_diagnostics.rds"))

# This compact figure shows whether extra states are bought by smaller cohorts.
figure_data <- design_summary[sample == "balanced_postcovid_28"]
figure_data[, treatment_definition := factor(
  treatment_definition,
  levels = names(design_columns),
  labels = c("Online legal", "Handle 25%", "Handle 50%",
             "Handle 75%", "Sustained 50%")
)]

support_figure <- ggplot(
  figure_data,
  aes(x = treatment_definition, y = n_treated_in_window)
) +
  geom_col(fill = "#2C6E9B", width = 0.7) +
  geom_point(
    aes(y = n_treated_in_window * share_treated_states_in_singletons),
    color = "#B33A3A",
    size = 3
  ) +
  geom_text(
    aes(label = n_treated_in_window),
    vjust = -0.4,
    size = 3.5
  ) +
  scale_y_continuous(
    breaks = seq.int(0L, max(figure_data[["n_treated_in_window"]]) + 2L, 2L),
    expand = expansion(mult = c(0, 0.12))
  ) +
  labs(
    title = "Post-COVID treated-state support",
    subtitle = paste0(
      "Bars: usable treated states; red dots: treated states in singleton ",
      "cohorts"
    ),
    x = NULL,
    y = "Number of states",
    caption = "Balanced 28-state panel, April 2022–December 2024"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    axis.text.x = element_text(angle = 25, hjust = 1),
    panel.grid.minor = element_blank()
  )

ggsave(
  file.path(OUTPUT_DIR, "treated_and_singleton_support.png"),
  support_figure,
  width = 8,
  height = 5,
  dpi = 300
)
saveRDS(
  support_figure,
  file.path(OUTPUT_DIR, "treated_and_singleton_support_figure.rds")
)

# 6. Results summary -----------------------------------------------------------

exact_design <- design_summary[sample == "balanced_postcovid_28"]
exact_incremental <- incremental_summary[sample == "balanced_postcovid_28"]
exact_candidates <- candidates[sample == "balanced_postcovid_28"]
exact_cs <- cs_summary[sample == "balanced_postcovid_28"]
exact_sa <- sa_summary[sample == "balanced_postcovid_28"]

format_pct <- \(x) sprintf("%.1f%%", 100 * x)
design_line <- \(design_name, label) {
  d <- exact_design[treatment_definition == design_name]
  inc <- exact_incremental[treatment_definition == design_name]
  sprintf(
    "| %s | %d | %d | %d | %s | %+d |",
    label,
    d[["n_treated_in_window"]],
    d[["n_treatment_cohorts"]],
    d[["n_singleton_cohorts"]],
    format_pct(d[["share_treated_states_in_singletons"]]),
    inc[["incremental_treated_vs_legal"]]
  )
}

candidate_lines <- if (nrow(exact_candidates) > 0L) {
  vapply(
    seq_len(nrow(exact_candidates)),
    \(i) {
      row <- exact_candidates[i]
      sprintf(
        "| %s | %s | %s | %d | %.1f%% | %d | %s |",
        row[["state_abb"]],
        row[["treatment_definition"]],
        format(row[["effective_date"]], "%Y-%m"),
        row[["pre_threshold_months_in_window"]],
        100 * row[["handle_fraction_at_window_start"]],
        row[["n_treated_states"]],
        row[["recommendation"]]
      )
    },
    character(1L)
  )
} else {
  "| None | — | — | — | — | — | — |"
}

summary_lines <- c(
  "# Post-COVID Handle-ramp support diagnostic",
  "",
  "## Answer",
  "",
  paste0(
    "A Handle-ramp definition is **not credible as the main treatment date**. ",
    "Handle is realized after legalization, responds to demand and policy, and ",
    "is seasonal. Reclassifying legally exposed months as untreated therefore ",
    "changes the estimand from legal access to market maturation and imposes a ",
    "strong no-effect-during-ramp assumption."
  ),
  "",
  paste0(
    "There is one plausible exploratory sensitivity: Arkansas at 25% of its frozen ",
    "peak (September 2022). Arkansas legalized online in March 2022, only one ",
    "month before the analysis window, and the 25% date joins Kansas's ",
    "September 2022 cohort. Within the common Handle-measured sample, this adds ",
    "one state without adding a cohort. Relative to the full legal-date ITT ",
    "sample, however, Arkansas replaces rather than augments Florida because ",
    "Florida lacks Handle data. It is still post-treatment timing, so it should ",
    "be labeled as an exploratory different-estimand sensitivity only."
  ),
  "",
  paste0(
    "The 50% definition adds Arkansas as a new singleton cohort. The 75% and ",
    "sustained-50% definitions add more nominally treated states, but do so by ",
    "calling long-established legal markets untreated until later, often ",
    "football-season Handle peaks. Their apparent cohort pooling is not an ",
    "identification improvement."
  ),
  "",
  "## Balanced post-COVID sample",
  "",
  "| Treatment clock | Treated states | Cohorts | Singleton cohorts | States in singleton cohorts | Incremental states vs common-sample legal |",
  "|---|---:|---:|---:|---:|---:|",
  design_line("online_legal", "Online legal"),
  design_line("handle_25", "Handle 25%"),
  design_line("handle_50", "Handle 50%"),
  design_line("handle_75", "Handle 75%"),
  design_line("handle_50_sustained", "Sustained Handle 50%"),
  "",
  "The table uses the 28-state common Handle-measurement sample observed in all 33 months from April 2022 through December 2024. Florida is excluded because Handle is missing, and Nevada is excluded as pre-sample treated.",
  "",
  paste0(
    "**Comparison caveat:** the full legal-date ITT sample can retain Florida ",
    "and contains 8 treated states in 7 cohorts. The common-measurement legal ",
    "row above contains 7 treated states in 6 cohorts, while Handle 25% contains ",
    "8 treated states in 6 cohorts after Arkansas replaces Florida. Thus, the ",
    "Handle-25 design does not increase treated-state N relative to the actual ",
    "legal-date main design. A hybrid that keeps Florida on the legal clock and ",
    "Arkansas on the Handle clock would mix estimands and is not recommended."
  ),
  "",
  "## Pre-window legal states moved into the post-window treatment set",
  "",
  "| State | Clock | Effective month | Post-window pre-threshold months | Handle/peak at window start | Cohort size | Recommendation |",
  "|---|---|---|---:|---:|---:|---|",
  candidate_lines,
  "",
  "## CS and SA implications",
  "",
  paste0(
    "Every treatment clock still has small cohorts. Under CS, the share of ",
    "group-time cells attached to cohorts smaller than five ranges from ",
    format_pct(min(exact_cs[["share_cells_small_cohort"]], na.rm = TRUE)),
    " to ",
    format_pct(max(exact_cs[["share_cells_small_cohort"]], na.rm = TRUE)),
    ". All mechanically constructed cells retain at least one eligible ",
    "not-yet/never-treated control, so treated-cluster leverage—not formal ",
    "control existence—remains the constraint."
  ),
  "",
  paste0(
    "For SA, the number of contributing treated states at event month +12 ",
    "ranges from ",
    min(exact_sa[["n_states_at_event_12"]], na.rm = TRUE),
    " to ", max(exact_sa[["n_states_at_event_12"]], na.rm = TRUE),
    " across definitions. More nominal treatment dates do not create more ",
    "independent states, and tail support remains thin."
  ),
  "",
  "## Credibility ranking",
  "",
  "1. **Arkansas, 25% Handle: exploratory sensitivity preferred.** It is the smallest estimand departure and expands an existing common-sample cohort from one to two states, but does not add a net treated state relative to the full legal ITT.",
  "2. **Arkansas, 50% or sustained 50%: speculative sensitivity.** Adds one state but generally as a singleton after many legally exposed months.",
  "3. **75% Handle candidates and delayed sustained crossings in established markets: reject.** They depend heavily on realized growth, peak normalization, and sports seasonality.",
  "",
  "## Is it worth including?",
  "",
  paste0(
    "Possibly, but only as one clearly labeled exploratory market-maturation ",
    "sensitivity using Arkansas's 25% date. It provides a stress test of the ",
    "post-COVID sample and slightly improves the September 2022 cohort within ",
    "the Handle-measured sample, but it does not increase treated-state N over ",
    "the full legal ITT. It is **not enough to change ",
    "the small-cohort diagnosis**, justify CS/SA as headline estimators, or ",
    "replace legal-date treatment. Report the legal-date design first and ",
    "explain that the Handle clock is an endogenous maturation estimand."
  ),
  "",
  "## Identification caveats",
  "",
  "- Handle thresholds are post-treatment and may respond to the same economic conditions that affect evictions.",
  "- A threshold design assumes no effect of legal betting below the selected threshold; this cannot be verified from Handle support alone.",
  "- Frozen own-state peak normalization avoids future data revisions after 2024, but it makes thresholds relative and state-specific.",
  "- Seasonal clustering—especially at 75%—can manufacture larger fall cohorts without adding independent quasi-experimental variation.",
  "- Candidate states are not valid legal-access controls during their ramp months; they are only pre-effective observations under the alternative maturation estimand.",
  "",
  "## Paper-to-code naming map",
  "",
  "| Paper notation | Code name | Description |",
  "|---|---|---|",
  "| $Y_{st}$ | `filings_count` | State-month eviction filings (not modeled here) |",
  "| $G_s^{legal}$ | `legal_online_start` | Online legalization month |",
  "| $G_s^{25}$ | `handle_25_date` | First 25%-peak month |",
  "| $G_s^{50}$ | `handle_50_date` | First 50%-peak month |",
  "| $G_s^{75}$ | `handle_75_date` | First 75%-peak month |",
  "| $G_s^{50,S}$ | `handle_50_sustained_date` | First of three consecutive 50%-peak months |",
  "| $e_{st}$ | `event_time` | Months relative to effective treatment |",
  "",
  "## Reproducibility",
  "",
  "Run `Rscript analysis/diagnostics/postcovid_handle_ramp_support.R` from the project root. No outcome model is fitted and no production panel or runner is modified."
)

writeLines(summary_lines, file.path(OUTPUT_DIR, "results_summary.md"))
message("Wrote post-COVID Handle-ramp support diagnostics to: ", OUTPUT_DIR)
