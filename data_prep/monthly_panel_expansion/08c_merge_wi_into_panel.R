# Merge Wisconsin into the state-month panel AS A CONTROL (never-treated).
#
# Source: WI DOA "Eviction Data Project" county-month filings (CCAP/WCCA),
# scraped and validated by 08a/08b. Complete 72-county coverage, reconciled to
# the independently published full-year PDFs to the unit (see 08b).
#
# This REPLACES a pre-existing Wisconsin series that was already in the panel
# from the ETS/LSC merge. That series was unusable as a control:
#   - coded TREATED with treat_start 2021-11-01 (WI's RETAIL sportsbook date),
#     contradicting the online-legalization treatment definition used for the
#     headline. WI never legalized statewide ONLINE betting, so under that
#     definition it is a never-treated control (online_start_date is blank in
#     sports_gambling_legalization_dates.csv).
#   - renter_occupied_housing_units == 0 for 96 of 133 months (2012-2020), so
#     filings_per_1k_renters was undefined (NA) for 72% of the series.
#   - filings diverged from the complete court count by up to +/-100% outside
#     ~2020, i.e. it covered a shifting subset, not the whole state.
# The old rows are deprecated (not deleted) under data/raw/deprecated/.
#
# WI's 72 counties are the entire state, so the renter denominator is the
# statewide total, held constant at the ACS 2019 5-year value (B25003_003 =
# 777,217), mirroring the Maryland merge (07). It is a per-state constant and
# cancels in any log specification with state fixed effects; it matters only for
# level comparisons of filings_per_1k_renters.
#
# Missing months are OMITTED, never zero-filled: DOA's latest 2024 file covers
# Jan-Nov (no December) and 2025 covers Jan-Oct. Fabricating zeros for absent
# months is exactly the bug that produced NH's spurious -57% effect (see 06).
#
# Input : data/raw/monthly_expansion/wi_lt_county_month.csv
# Output: data/raw/state_month_panel_with_treatment.csv (WI rows replaced)
#         old WI rows + full panel preserved under data/raw/deprecated/

library(tidyverse)
library(glue)

panel_path <- "data/raw/state_month_panel_with_treatment.csv"
wi_path    <- "data/raw/monthly_expansion/wi_lt_county_month.csv"
backup_dir <- "data/raw/deprecated"

N_WI_COUNTIES <- 72L
# ACS 2019 5-year, B25003_003 (renter-occupied housing units), Wisconsin.
# Documented approximation, consistent with the panel's existing WI values
# (775,184-782,738) and with the MD merge convention.
WI_RENTERS <- 777217L

panel <- read_csv(panel_path, show_col_types = FALSE)
wi_cty <- read_csv(wi_path, show_col_types = FALSE)

# --- Coverage guard: every retained month must carry all 72 counties ---------
coverage <- wi_cty |> count(month_date, name = "n_counties")
incomplete <- coverage |> filter(n_counties != N_WI_COUNTIES)
if (nrow(incomplete) > 0) {
  print(incomplete)
  stop("Some WI months lack all 72 counties; aggregation would understate them.")
}

panel_start <- min(panel$month_date)
panel_end   <- max(panel$month_date)

wi_state <- wi_cty |>
  group_by(month_date) |>
  summarise(filings_count = sum(filed), .groups = "drop") |>
  filter(month_date >= panel_start, month_date <= panel_end) |>
  arrange(month_date) |>
  transmute(
    state_abb = "WI",
    month_date,
    filings_count,
    renter_occupied_housing_units = WI_RENTERS,
    filings_per_1k_renters = filings_count / WI_RENTERS * 1000,
    treat_start = as.Date(NA),   # never-treated control
    treated = FALSE
  )

# --- Deprecate the old ETS-derived WI rows and back up the panel -------------
dir.create(backup_dir, showWarnings = FALSE, recursive = TRUE)
old_wi <- panel |> filter(state_abb == "WI")
old_wi_path <- file.path(backup_dir, "wi_ets_rows_pre_courtsource_2026-07-23.csv")
if (nrow(old_wi) > 0 && !file.exists(old_wi_path)) write_csv(old_wi, old_wi_path)
backup_path <- file.path(backup_dir, "state_month_panel_with_treatment_pre_wi_merge_2026-07-23.csv")
if (!file.exists(backup_path)) file.copy(panel_path, backup_path)

panel_other <- panel |> filter(state_abb != "WI")
panel_out <- bind_rows(panel_other, wi_state) |> arrange(state_abb, month_date)

# --- assertions -------------------------------------------------------------
# Expected WI months = observed county-file months within the panel window
# (this naturally excludes 2024-12, which is absent from the source).
expected_wi_months <- wi_cty |>
  distinct(month_date) |>
  filter(month_date >= panel_start, month_date <= panel_end) |>
  nrow()

stopifnot(
  "duplicate state x month after merge" =
    !anyDuplicated(paste(panel_out$state_abb, panel_out$month_date)),
  "NA filings introduced" = !any(is.na(panel_out$filings_count)),
  "WI row count != expected observed months" = nrow(wi_state) == expected_wi_months,
  "WI has a zero/negative filings month" = all(wi_state$filings_count > 0),
  "WI not coded as control" =
    all(!wi_state$treated) && all(is.na(wi_state$treat_start)),
  "WI 2024-12 should be absent, not zero-filled" =
    !as.Date("2024-12-01") %in% wi_state$month_date,
  # every pre-existing NON-WI state must be byte-identical
  "a non-WI state changed" =
    identical(
      as.data.frame(panel |> filter(state_abb != "WI") |> arrange(state_abb, month_date)),
      as.data.frame(panel_out |> filter(state_abb != "WI"))
    )
)

write_csv(panel_out, panel_path)

message(glue(
  "WI replaced as CONTROL: {nrow(wi_state)} months ",
  "({format(min(wi_state$month_date))} to {format(max(wi_state$month_date))}), ",
  "never-treated. Old ETS WI ({nrow(old_wi)} rows) deprecated -> {old_wi_path}. ",
  "Panel now {n_distinct(panel_out$state_abb)} states, {nrow(panel_out)} rows. ",
  "Backup: {backup_path}"
))
