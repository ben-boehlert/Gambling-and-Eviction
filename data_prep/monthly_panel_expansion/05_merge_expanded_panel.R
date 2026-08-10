# ============================================================================
# 05_merge_expanded_panel.R
#
# Purpose: Merge MD/NJ/OR/IA county-month panels produced by scripts 01-04
#          onto the existing ETS/LSC monthly state panel for power gains.
#
# Inputs:
#   data/raw/monthly_expansion/md_county_month_panel.csv   (scripts 01)
#   data/raw/monthly_expansion/or_county_month_panel.csv   (scripts 02)
#   data/raw/monthly_expansion/nj_county_month_panel.csv   (scripts 03)
#   data/raw/monthly_expansion/ia_county_month_panel.csv   (scripts 04)
#   data/raw/state_month_panel_with_treatment.csv          (existing ETS panel)
#
# Output:
#   data/processed/state_month_panel_expanded.csv
#
# Strategy:
#   1. Aggregate each new state's county-month panel to state-month totals.
#   2. For MD, choose warrant_petitions as the filings analog (documented
#      caveat: this is post-judgment, not complaint-filing — see script 01).
#   3. Rbind new state-month rows onto existing ETS panel. Mark source.
#   4. Merge on treatment dates from sports_gambling_legalization_dates.csv.
#   5. Flag balance: which states cover which months, which drop when COVID
#      window is excluded.
#
# Author: Ben Boehlert / Claude Code
# Date:   2026-04-15
# ============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
})

PROJECT_ROOT <- here::here()
IN_DIR  <- file.path(PROJECT_ROOT, "data", "raw", "monthly_expansion")
OUT_DIR <- file.path(PROJECT_ROOT, "data", "processed")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# ---- Load existing ETS state panel ----------------------------------------
ets_panel <- read_csv(
  file.path(PROJECT_ROOT, "data", "raw", "state_month_panel_with_treatment.csv"),
  show_col_types = FALSE
) %>%
  mutate(month_date = as.Date(month_date)) %>%
  select(state_abb, month_date, filings_count, renter_occupied_housing_units,
         filings_per_1k_renters, treat_start, treated) %>%
  mutate(source = "ETS")

# ---- Load each new state panel (handle empty stubs gracefully) ------------
safe_read <- function(path) {
  if (!file.exists(path)) return(NULL)
  x <- read_csv(path, show_col_types = FALSE)
  if (nrow(x) == 0) return(NULL)
  x
}

md <- safe_read(file.path(IN_DIR, "md_county_month_panel.csv"))
or <- safe_read(file.path(IN_DIR, "or_county_month_panel.csv"))
nj <- safe_read(file.path(IN_DIR, "nj_county_month_panel.csv"))
ia <- safe_read(file.path(IN_DIR, "ia_county_month_panel.csv"))

# ---- Aggregate county -> state for each new state --------------------------
md_state <- if (!is.null(md)) {
  md %>%
    mutate(month = as.Date(month)) %>%
    group_by(state_abb, month) %>%
    summarise(
      filings_count = sum(warrant_petitions, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    rename(month_date = month) %>%
    mutate(source = "MD_Socrata_warrant_petitions")
} else NULL

or_state <- if (!is.null(or)) {
  or %>%
    mutate(month = as.Date(month)) %>%
    group_by(state_abb, month) %>%
    summarise(filings_count = sum(filings, na.rm = TRUE), .groups = "drop") %>%
    rename(month_date = month) %>%
    mutate(source = "OR_EvictedInOregon")
} else NULL

nj_state <- if (!is.null(nj)) {
  nj %>%
    mutate(month = as.Date(month)) %>%
    group_by(state_abb, month) %>%
    summarise(filings_count = sum(filings, na.rm = TRUE), .groups = "drop") %>%
    rename(month_date = month) %>%
    mutate(source = "NJ_Courts")
} else NULL

ia_state <- if (!is.null(ia)) {
  ia %>%
    mutate(month = as.Date(month)) %>%
    group_by(state_abb, month) %>%
    summarise(filings_count = sum(filings, na.rm = TRUE), .groups = "drop") %>%
    rename(month_date = month) %>%
    mutate(source = "IA_SCA")
} else NULL

new_rows <- bind_rows(md_state, or_state, nj_state, ia_state)

if (nrow(new_rows) == 0) {
  message("No new data yet. Re-run after scripts 01-04 produce non-empty panels.")
  quit(save = "no", status = 0)
}

# ---- Merge treatment dates on new states -----------------------------------
treat <- read_csv(
  file.path(PROJECT_ROOT, "data", "raw", "sports_gambling_legalization_dates.csv"),
  show_col_types = FALSE
)
# Assumes columns state_abb, online_start_date. Adjust if different.
new_rows <- new_rows %>%
  left_join(
    treat %>% select(state_abb, treat_start = online_start_date),
    by = "state_abb"
  ) %>%
  mutate(
    treat_start = as.Date(treat_start),
    treated = as.integer(!is.na(treat_start) & month_date >= treat_start)
  )

# ---- Rbind and drop ETS rows for any state also in new_rows ---------------
# (New sources may supersede ETS for the overlap states if desired. Default:
# keep ETS where available, use new source only where ETS is missing.)

new_states <- unique(new_rows$state_abb)
message("New state coverage being added: ", paste(new_states, collapse = ", "))

overlap <- intersect(unique(ets_panel$state_abb), new_states)
if (length(overlap) > 0) {
  message("States in BOTH ETS and new sources (keeping ETS for overlap): ",
          paste(overlap, collapse = ", "))
  new_rows <- new_rows %>% filter(!state_abb %in% overlap)
}

expanded <- bind_rows(
  ets_panel,
  new_rows %>%
    select(state_abb, month_date, filings_count, treat_start, treated, source)
)

# ---- Coverage diagnostics --------------------------------------------------
coverage <- expanded %>%
  group_by(state_abb, source) %>%
  summarise(
    n_months = n(),
    first = min(month_date), last = max(month_date),
    treated_ever = max(treated, na.rm = TRUE),
    treat_start = first(treat_start),
    .groups = "drop"
  ) %>%
  arrange(desc(treated_ever), state_abb)
print(coverage, n = Inf)

# ---- Save ------------------------------------------------------------------
write_csv(expanded, file.path(OUT_DIR, "state_month_panel_expanded.csv"))
write_csv(coverage, file.path(OUT_DIR, "state_month_panel_expanded_coverage.csv"))

message("\nWrote: ", file.path(OUT_DIR, "state_month_panel_expanded.csv"))
message("Rows: ", nrow(expanded), "  States: ", length(unique(expanded$state_abb)))
