# Repair Maine in the state-month panel using the Maine Judicial Branch source.
#
# The ETS-derived ME series stops receiving data after May 2023 but records the
# missing months (2023-06 .. 2023-12) as literal zeros rather than NA, which made
# ME look like a state whose evictions collapsed to zero -- a data artifact, the
# same defect repaired for NH. Unlike NH, the Maine Judicial Branch "15-Year
# Monthly FED Filing Trends" source does NOT match the ETS panel exactly on
# overlapping months: the two agree on early-in-year months but diverge (by up to
# ~200 filings) on later months, because the ETS pull captured a staler MEJIS
# vintage than the 2026-refreshed court report. Splicing would therefore create a
# within-year seam. Per user decision (2026-07-23) we instead REPLACE Maine's
# entire series with the single, internally-consistent court-source vintage
# (county sums reconcile to the printed statewide totals on all 180 cells).
#
# Full replace over [2016-01, panel_max]; ME is a never-treated control
# (treat_start = NA), so treated stays FALSE throughout.
#
# Input : data/raw/monthly_expansion/me_fed_state_month_courtsource.csv
# Output: data/raw/state_month_panel_with_treatment.csv (ME rows replaced/extended)
#         original preserved under data/raw/deprecated/

library(tidyverse)
library(glue)

panel_path <- "data/raw/state_month_panel_with_treatment.csv"
court_path <- "data/raw/monthly_expansion/me_fed_state_month_courtsource.csv"
backup_dir <- "data/raw/deprecated"

panel <- read_csv(panel_path, show_col_types = FALSE)
court <- read_csv(court_path, show_col_types = FALSE)

me_before <- panel |> filter(state_abb == "ME")
stopifnot(nrow(me_before) > 0, n_distinct(me_before$renter_occupied_housing_units) == 1)

renters  <- unique(me_before$renter_occupied_housing_units)
treat_st <- unique(me_before$treat_start)          # NA for a never-treated state
stopifnot(length(treat_st) == 1, all(is.na(treat_st)))

# ME series is bounded below at its original start (2016-01, per user's
# "2016 -> panel max" decision) and above at the panel envelope so the repair
# does not create a terminal month that only one state occupies.
me_start  <- min(me_before$month_date)
panel_end <- max(panel$month_date)

dir.create(backup_dir, showWarnings = FALSE, recursive = TRUE)
backup_path <- file.path(backup_dir, "state_month_panel_with_treatment_pre_me_repair_2026-07-23.csv")
if (!file.exists(backup_path)) file.copy(panel_path, backup_path)

# Overlap diagnostic (logged, NOT a gate): full replacement is deliberate, but we
# record how far the discarded ETS vintage diverged from the court source so the
# decision is auditable.
overlap <- me_before |>
  inner_join(court, by = "month_date") |>
  filter(filings_count > 0)
diffs <- overlap$filings_count - overlap$fed_filings
message(glue(
  "ME overlap diagnostic ({nrow(overlap)} non-zero months): ",
  "exact matches {sum(diffs == 0)}/{length(diffs)}, ",
  "mean|diff| {round(mean(abs(diffs)), 1)}, max|diff| {max(abs(diffs))}, ",
  "corr {round(cor(overlap$filings_count, overlap$fed_filings), 3)}."
))

me_repaired <- court |>
  filter(month_date >= me_start, month_date <= panel_end) |>
  transmute(
    state_abb,
    month_date,
    filings_count = fed_filings,
    renter_occupied_housing_units = renters,
    filings_per_1k_renters = fed_filings / renters * 1000,
    treat_start = treat_st,
    treated = FALSE                       # never-treated control
  ) |>
  arrange(month_date)

panel_out <- panel |>
  filter(state_abb != "ME") |>
  bind_rows(me_repaired) |>
  arrange(state_abb, month_date)

# --- assertions -------------------------------------------------------------
stopifnot(
  !anyDuplicated(paste(panel_out$state_abb, panel_out$month_date)),
  !any(is.na(panel_out$filings_count)),
  # every other state untouched
  nrow(panel_out |> filter(state_abb != "ME")) == nrow(panel |> filter(state_abb != "ME")),
  # no fabricated zeros anywhere in the repaired ME series
  !any(me_repaired$filings_count == 0),
  # ME never-treated
  all(me_repaired$treated == FALSE)
)

write_csv(panel_out, panel_path)

message(glue(
  "ME repaired (full replace): {nrow(me_before)} -> {nrow(me_repaired)} months ",
  "({format(min(me_repaired$month_date))} to {format(max(me_repaired$month_date))}). ",
  "Zeros removed: {sum(me_before$filings_count == 0)}. ",
  "Months added past old end: {sum(me_repaired$month_date > max(me_before$month_date))}. ",
  "Backup: {backup_path}"
))
