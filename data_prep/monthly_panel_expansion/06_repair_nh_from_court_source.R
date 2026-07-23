# Repair New Hampshire in the state-month panel using the NH Judicial Branch source.
#
# The ETS-derived NH series stops receiving data after June 2023 but records the
# missing months as literal zeros rather than NA, which produced a spurious ~-57%
# NH treatment effect. The NH Judicial Branch publishes the authoritative monthly
# Landlord Tenant Writ filing counts; its Jan-Jun 2023 values match the panel
# exactly, confirming the two are the same series, so the later months can be
# backfilled without mixing definitions.
#
# Input : data/raw/monthly_expansion/nh_lt_state_month_courtsource.csv
# Output: data/raw/state_month_panel_with_treatment.csv (NH rows corrected/extended)
#         original preserved under data/raw/deprecated/

library(tidyverse)
library(glue)

panel_path <- "data/raw/state_month_panel_with_treatment.csv"
court_path <- "data/raw/monthly_expansion/nh_lt_state_month_courtsource.csv"
backup_dir <- "data/raw/deprecated"

# The panel's max month; NH is not extended past it so the repair does not create
# a terminal month that only one state occupies.
panel <- read_csv(panel_path, show_col_types = FALSE)
court <- read_csv(court_path, show_col_types = FALSE)

panel_end <- max(panel$month_date)
nh_before <- panel |> filter(state_abb == "NH")

stopifnot(nrow(nh_before) > 0, n_distinct(nh_before$renter_occupied_housing_units) == 1)

renters   <- unique(nh_before$renter_occupied_housing_units)
treat_st  <- unique(nh_before$treat_start)
stopifnot(length(treat_st) == 1)

dir.create(backup_dir, showWarnings = FALSE, recursive = TRUE)
backup_path <- file.path(backup_dir, "state_month_panel_with_treatment_pre_nh_repair_2026-07-23.csv")
if (!file.exists(backup_path)) file.copy(panel_path, backup_path)

# Overlap check: every month present in both sources must already agree, otherwise
# the two series are not the same measure and backfilling would be invalid.
overlap <- nh_before |>
  inner_join(court, by = c("month_date")) |>
  filter(filings_count > 0)

mismatches <- overlap |> filter(filings_count != lt_writ_filings)
if (nrow(mismatches) > 0) {
  print(mismatches |> select(month_date, panel = filings_count, court = lt_writ_filings))
  stop("Panel and court source disagree on overlapping non-zero months; aborting repair.")
}
message(glue("Overlap check passed: {nrow(overlap)} non-zero months agree exactly."))

nh_repaired <- court |>
  filter(month_date <= panel_end) |>
  transmute(
    state_abb,
    month_date,
    filings_count = lt_writ_filings,
    renter_occupied_housing_units = renters,
    filings_per_1k_renters = lt_writ_filings / renters * 1000,
    treat_start = treat_st,
    treated = month_date >= treat_st
  )

# Keep NH months that predate the court source, replace/extend everything from
# the court source's first month onward.
nh_kept <- nh_before |> filter(month_date < min(nh_repaired$month_date))

nh_new <- bind_rows(nh_kept, nh_repaired) |> arrange(month_date)

panel_out <- panel |>
  filter(state_abb != "NH") |>
  bind_rows(nh_new) |>
  arrange(state_abb, month_date)

# --- assertions -------------------------------------------------------------
stopifnot(
  !anyDuplicated(paste(panel_out$state_abb, panel_out$month_date)),
  !any(is.na(panel_out$filings_count)),
  # every other state untouched
  nrow(panel_out |> filter(state_abb != "NH")) == nrow(panel |> filter(state_abb != "NH")),
  # no fabricated zeros remain in the treated NH window
  !any(nh_new$filings_count == 0 & nh_new$month_date >= as.Date("2023-07-01"))
)

write_csv(panel_out, panel_path)

message(glue(
  "NH repaired: {nrow(nh_before)} -> {nrow(nh_new)} months ",
  "({format(min(nh_new$month_date))} to {format(max(nh_new$month_date))}). ",
  "Zeros replaced: {sum(nh_before$filings_count == 0)}. ",
  "Backup: {backup_path}"
))
