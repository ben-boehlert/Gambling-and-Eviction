#!/usr/bin/env Rscript
################################################################################
# build_panel_handle50_treatment.R
#
# Creates a modified state-month panel where treat_start = first month
# a state's Handle reaches THRESHOLD (default 50%) of its peak monthly Handle.
#
# COVID handling:
#   - Peak Handle is computed EXCLUDING COVID months (so the threshold is meaningful)
#   - The threshold search includes ALL months (including COVID)
#   - States that crossed 50% during COVID keep their actual treatment date
#   - In a post-COVID analysis window, these become "always treated" —
#     CS-DiD correctly excludes them from the control pool
#
# Inputs:
#   - data/raw/state_month_panel_with_treatment.csv  (existing panel)
#   - data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv  (handle data)
#
# Output:
#   - data/processed/state_month_panel_handle50_treatment.csv
#
# Usage:
#   Rscript data_prep/build_panel_handle50_treatment.R
#   HANDLE_THRESHOLD=0.6 Rscript data_prep/build_panel_handle50_treatment.R
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

# --- Configuration ---
PANEL_IN     <- Sys.getenv("PANEL_IN", "data/raw/state_month_panel_with_treatment.csv")
HANDLE_FILE  <- Sys.getenv("HANDLE_FILE", "data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv")
OUT_FILE     <- Sys.getenv("OUT_FILE", "data/processed/state_month_panel_handle50_treatment.csv")
THRESHOLD    <- as.numeric(Sys.getenv("HANDLE_THRESHOLD", "0.5"))

# COVID exclusion window — must match the analysis panel's DROP window
COVID_START <- as.Date("2020-03-01")
COVID_END   <- as.Date("2022-03-31")

cat(sprintf("Building panel with Handle %.0f%% treatment threshold\n", THRESHOLD * 100))
cat(sprintf("  COVID exclusion: %s to %s\n", COVID_START, COVID_END))

# --- State name crosswalk ---
state_name_to_abb <- function(state_name) {
  state_name <- trimws(state_name)
  m <- setNames(state.abb, state.name)
  m2 <- c(m, "District of Columbia" = "DC")
  unname(m2[state_name])
}

# --- Read handle data ---
handle <- read_csv(HANDLE_FILE, show_col_types = FALSE) %>%
  filter(!is.na(Handle), Handle > 0) %>%
  mutate(
    state_abb  = state_name_to_abb(State),
    month_date = as.Date(month_date),
    is_covid   = month_date >= COVID_START & month_date <= COVID_END
  ) %>%
  filter(!is.na(state_abb))

cat(sprintf("  Handle data: %d rows, %d states\n", nrow(handle), n_distinct(handle$state_abb)))

# --- Compute peak Handle per state (excluding COVID) ---
peaks <- handle %>%
  filter(!is_covid) %>%
  group_by(state_abb) %>%
  summarise(peak_handle = max(Handle, na.rm = TRUE), .groups = "drop") %>%
  filter(is.finite(peak_handle), peak_handle > 0)

cat(sprintf("  States with non-COVID peak Handle: %d\n", nrow(peaks)))

# --- Find first month reaching THRESHOLD * peak (searching ALL months incl COVID) ---
# States that crossed during COVID keep their actual date; in a post-COVID
# analysis window they become "always treated" and CS-DiD handles them correctly.
handle50 <- handle %>%
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

# --- Read existing panel and replace treat_start ---
panel <- read_csv(PANEL_IN, show_col_types = FALSE) %>%
  mutate(
    state_abb  = as.character(state_abb),
    month_date = as.Date(month_date)
  ) %>%
  select(-treat_start, -treated) %>%
  left_join(handle50, by = "state_abb") %>%
  mutate(
    treat_start = handle_treat_start,
    treated     = !is.na(treat_start) & month_date >= treat_start
  ) %>%
  select(-handle_treat_start)

# Reorder columns to match original
panel <- panel %>%
  select(state_abb, month_date, filings_count, renter_occupied_housing_units,
         filings_per_1k_renters, treat_start, treated)

n_treated_states <- n_distinct(panel$state_abb[!is.na(panel$treat_start)])
n_never_treated  <- n_distinct(panel$state_abb[is.na(panel$treat_start)])
cat(sprintf("\n  Panel: %d treated states, %d never-treated states\n",
            n_treated_states, n_never_treated))

dir.create(dirname(OUT_FILE), recursive = TRUE, showWarnings = FALSE)
write_csv(panel, OUT_FILE)
cat(sprintf("  Wrote: %s\n", OUT_FILE))
