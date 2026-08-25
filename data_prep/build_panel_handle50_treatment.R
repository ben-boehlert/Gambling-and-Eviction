#!/usr/bin/env Rscript
################################################################################
# build_panel_handle50_treatment.R
#
# Creates a modified state-month panel where treat_start = first month
# a state's Handle reaches THRESHOLD (default 50%) of its peak monthly Handle.
#
# COVID handling:
#   - Peak Handle is computed EXCLUDING COVID months (so the threshold is meaningful)
#   - Peak calibration and threshold search are capped at the study cutoff
#     (default: 2024-12-31), preventing later market growth from changing
#     historical treatment dates
#   - The threshold search includes COVID months within the calibration window
#   - States that crossed 50% during COVID keep their actual treatment date
#   - In a post-COVID analysis window, these become "always treated" —
#     CS-DiD correctly excludes them from the control pool
#
# Inputs:
#   - data/raw/state_month_panel_with_treatment.csv  (existing panel)
#   - data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv  (handle data)
#   - data/raw/sports_gambling_legalization_dates.csv  (online start dates)
#
# Output:
#   - data/processed/state_month_panel_handle50_treatment.csv
#   - data/processed/handle50_state_classification.csv
#   - data/processed/handle50_state_classification_codebook.csv
#
# Usage:
#   Rscript data_prep/build_panel_handle50_treatment.R
#   HANDLE_THRESHOLD=0.6 Rscript data_prep/build_panel_handle50_treatment.R
#   PEAK_CALIBRATION_END=2024-12-31 Rscript data_prep/build_panel_handle50_treatment.R
#
# 2026-08-14 revision (three fixes; original preserved in
# data/processed/deprecated/):
#   1. Treatment coding restricted to states with a verified ONLINE start date
#     in the schedule CSV, with an explicit NV guard. Previously NV (absent
#     from the schedule; online-treated pre-PASPA) and the retail-only states
#     MS/MT were coded treated off total handle.
#   2. Peak calibration and threshold search use ONLINE-ERA handle only
#     (months >= online_start_date). Previously DE was dated 2018-09 -- 64
#     months before its Jan 2024 online launch -- because its small retail-era
#     peak made 50% trivially reachable. All treat dates are now >= the
#     state's online start by construction.
#   3. COVID window default aligned to the power-framework protocol
#     (2020-03-01..2021-07-31), env-overridable. Other windows in use in this
#     repo: 2020-03..2022-03 (calibration-script convention; the previous
#     default here) and Sep 2021 (eviction-recovery month). The window only
#     shapes the peak base, but do not mix windows across artifacts unawares.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

# --- Configuration ---
PANEL_IN     <- Sys.getenv("PANEL_IN", "data/raw/state_month_panel_with_treatment.csv")
HANDLE_FILE <- Sys.getenv(
  "HANDLE_FILE",
  "data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv"
)
OUT_FILE     <- Sys.getenv("OUT_FILE", "data/processed/state_month_panel_handle50_treatment.csv")
CLASSIFICATION_FILE <- Sys.getenv(
  "CLASSIFICATION_FILE",
  "data/processed/handle50_state_classification.csv"
)
CODEBOOK_FILE <- Sys.getenv(
  "CODEBOOK_FILE",
  "data/processed/handle50_state_classification_codebook.csv"
)
THRESHOLD    <- as.numeric(Sys.getenv("HANDLE_THRESHOLD", "0.5"))
PEAK_CALIBRATION_END <- as.Date(Sys.getenv("PEAK_CALIBRATION_END", "2024-12-31"))
STUDY_START <- as.Date(Sys.getenv("STUDY_START", "2016-01-01"))

if (is.na(PEAK_CALIBRATION_END) || is.na(STUDY_START)) {
  stop("STUDY_START and PEAK_CALIBRATION_END must be valid YYYY-MM-DD dates")
}

source(file.path("data_prep", "handle_state_classification.R"))

# COVID exclusion window for the peak base — default = power-framework
# protocol window (R/power/config.R). Override via env for the calibration
# convention (COVID_END=2022-03-31) or recovery-based (COVID_END=2021-08-31).
COVID_START <- as.Date(Sys.getenv("COVID_START", "2020-03-01"))
COVID_END   <- as.Date(Sys.getenv("COVID_END",   "2021-07-31"))
SCHEDULE_FILE <- Sys.getenv("SCHEDULE_FILE",
                            "data/raw/sports_gambling_legalization_dates.csv")

cat(sprintf("Building panel with Handle %.0f%% treatment threshold\n", THRESHOLD * 100))
cat(sprintf("  COVID exclusion: %s to %s\n", COVID_START, COVID_END))
cat(sprintf("  Peak calibration cutoff: %s\n", PEAK_CALIBRATION_END))

# --- Read online start dates (treatment universe) ---
online_dates <- read_csv(SCHEDULE_FILE, show_col_types = FALSE) %>%
  mutate(state_abb = state_name_to_abb(state),
         online_start = as.Date(online_start_date)) %>%
  filter(!is.na(state_abb), !is.na(online_start)) %>%
  select(state_abb, online_start)

# --- Read handle data (online-era months of online states only) ---
handle_all <- read_csv(HANDLE_FILE, show_col_types = FALSE) %>%
  filter(!is.na(Handle), Handle > 0) %>%
  mutate(
    state_abb  = state_name_to_abb(State),
    month_date = as.Date(month_date),
    is_covid   = month_date >= COVID_START & month_date <= COVID_END
  ) %>%
  filter(!is.na(state_abb),
         state_abb != "NV")   # never in the schedule; online pre-PASPA

dropped <- setdiff(unique(handle_all$state_abb), online_dates$state_abb)
if (length(dropped) > 0L) {
  cat(sprintf("  Excluded (handle data but no online start date): %s\n",
              paste(sort(dropped), collapse = ", ")))
}

handle <- handle_all %>%
  inner_join(online_dates, by = "state_abb") %>%
  filter(month_date >= online_start)

cat(sprintf("  Online-era handle data: %d rows, %d states\n",
            nrow(handle), n_distinct(handle$state_abb)))

# Restrict both the peak calculation and threshold search to the prespecified
# study window. Without this cap, adding later LSR releases can increase a
# state's observed peak and retroactively move its treatment date.
handle_calibration <- handle %>%
  filter(month_date <= PEAK_CALIBRATION_END)

cat(sprintf(
  "  Calibration sample: %d rows, %d states through %s\n",
  nrow(handle_calibration),
  n_distinct(handle_calibration$state_abb),
  PEAK_CALIBRATION_END
))

# --- Compute peak Handle per state (excluding COVID) ---
peaks <- handle_calibration %>%
  filter(!is_covid) %>%
  group_by(state_abb) %>%
  summarise(peak_handle = max(Handle, na.rm = TRUE), .groups = "drop") %>%
  filter(is.finite(peak_handle), peak_handle > 0)

cat(sprintf("  States with non-COVID peak Handle: %d\n", nrow(peaks)))

# --- Find first month reaching THRESHOLD * peak within calibration window ---
# States that crossed during COVID keep their actual date; in a post-COVID
# analysis window they become "always treated" and CS-DiD handles them correctly.
handle50 <- handle_calibration %>%
  inner_join(peaks, by = "state_abb") %>%
  filter(Handle >= THRESHOLD * peak_handle) %>%
  group_by(state_abb) %>%
  summarise(handle_treat_start = min(month_date), .groups = "drop")

cat(sprintf("  States reaching %.0f%% of peak: %d\n", THRESHOLD * 100, nrow(handle50)))
cat("\n  Treatment dates:\n")
handle50_sorted <- handle50 %>% arrange(handle_treat_start)
for (i in seq_len(nrow(handle50_sorted))) {
  cat(sprintf("    %s: %s\n", handle50_sorted$state_abb[i], handle50_sorted$handle_treat_start[i]))
}

# --- Classify every panel state before constructing the estimator panel ---
panel_raw <- read_csv(PANEL_IN, show_col_types = FALSE) %>%
  mutate(
    state_abb  = as.character(state_abb),
    month_date = as.Date(month_date)
  )

state_classification <- classify_handle_states(
  panel_states = panel_raw$state_abb,
  legal_schedule = read_csv(SCHEDULE_FILE, show_col_types = FALSE),
  threshold_dates = handle50 %>%
    rename(handle_threshold_start = handle_treat_start),
  handle_data_states = unique(handle_calibration$state_abb),
  study_start = STUDY_START,
  study_cutoff = PEAK_CALIBRATION_END,
  threshold_fraction = THRESHOLD
)

# Missing Handle is missing exposure, not evidence of no treatment. These
# guards prevent Florida-like states from silently entering the control pool.
stopifnot(
  state_classification$handle_treatment_status[
    state_classification$state_abb == "FL"
  ] == "legally_online_missing_handle",
  !state_classification$analysis_eligible[
    state_classification$state_abb == "FL"
  ],
  state_classification$handle_treatment_status[
    state_classification$state_abb == "NV"
  ] == "pre_sample_treated",
  !state_classification$analysis_eligible[
    state_classification$state_abb == "NV"
  ]
)

dir.create(dirname(CLASSIFICATION_FILE), recursive = TRUE, showWarnings = FALSE)
classification_codebook <- handle_classification_codebook()
write_csv(state_classification, CLASSIFICATION_FILE)
write_csv(classification_codebook, CODEBOOK_FILE)
saveRDS(state_classification, paired_rds_path(CLASSIFICATION_FILE))
saveRDS(classification_codebook, paired_rds_path(CODEBOOK_FILE))

status_counts <- state_classification %>%
  count(handle_treatment_status, analysis_eligible, name = "n_states")
cat("\n  State classification:\n")
print(status_counts)

# --- Replace treat_start and remove states that cannot identify this estimand ---
panel <- panel_raw %>%
  select(-treat_start, -treated) %>%
  inner_join(
    state_classification %>%
      filter(analysis_eligible) %>%
      select(
        state_abb, legal_online_start, handle_threshold_start,
        handle_treatment_status, control_eligible, analysis_eligible,
        exclusion_reason, treat_start
      ),
    by = "state_abb"
  ) %>%
  mutate(
    treated     = !is.na(treat_start) & month_date >= treat_start
  )

# Keep the original analysis columns first and append classification fields.
panel <- panel %>%
  select(state_abb, month_date, filings_count, renter_occupied_housing_units,
         filings_per_1k_renters, treat_start, treated,
         legal_online_start, handle_threshold_start,
         handle_treatment_status, control_eligible, analysis_eligible,
         exclusion_reason)

if (any(panel$state_abb %in% c("FL", "NV"))) {
  stop("Florida and Nevada must be absent from the estimator-ready Handle panel")
}
if (any(is.na(panel$treat_start) & !panel$control_eligible)) {
  stop("A missing-exposure state was coded as an eligible never-treated control")
}

n_treated_states <- n_distinct(panel$state_abb[!is.na(panel$treat_start)])
n_never_treated  <- n_distinct(panel$state_abb[is.na(panel$treat_start)])
cat(sprintf("\n  Panel: %d treated states, %d never-treated states\n",
            n_treated_states, n_never_treated))

dir.create(dirname(OUT_FILE), recursive = TRUE, showWarnings = FALSE)
write_csv(panel, OUT_FILE)
saveRDS(panel, paired_rds_path(OUT_FILE))
cat(sprintf("  Wrote: %s\n", OUT_FILE))
cat(sprintf("  Wrote: %s\n", CLASSIFICATION_FILE))
cat(sprintf("  Wrote: %s\n", CODEBOOK_FILE))
cat(sprintf("  Wrote paired RDS checkpoints for all three outputs\n"))
