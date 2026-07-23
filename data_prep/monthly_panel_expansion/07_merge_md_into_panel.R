# Merge Maryland into the state-month panel.
#
# Source: MD District Court monthly Landlord/Tenant filings, parsed from the
# Judiciary's annual statistics PDFs by 01b/01c. This supersedes the Socrata
# extract in 01_pull_md_socrata.R on both coverage (2005+ vs 2023+) and margin
# (filings at complaint vs post-judgment warrants of restitution).
#
# MD's 24 reporting jurisdictions are the entire state, so the renter
# denominator is the statewide total rather than a covered-county subset.
#
# Input : data/raw/monthly_expansion/md_lt_county_month.csv
# Output: data/raw/state_month_panel_with_treatment.csv (MD rows appended)
#         original preserved under data/raw/deprecated/

library(tidyverse)
library(glue)

panel_path  <- "data/raw/state_month_panel_with_treatment.csv"
md_path     <- "data/raw/monthly_expansion/md_lt_county_month.csv"
treat_path  <- "data/raw/sports_gambling_legalization_dates.csv"
backup_dir  <- "data/raw/deprecated"

# ACS 2019 5-year B25003_003 (renter-occupied housing units), Maryland, summed
# over its 24 county-equivalents. NOTE: the panel's existing denominators equal
# the covered-county sums carried in the ETS/LSC county file, whose exact ACS
# vintage could not be reproduced here (NH's 151,523 sits ~350 above ACS 2022
# and ~450 above ACS 2015). This value is therefore a documented approximation.
# It is a per-state constant, so it cancels in any log specification with state
# fixed effects; it matters only for level comparisons of filings_per_1k_renters.
MD_RENTERS <- 730055L

panel <- read_csv(panel_path, show_col_types = FALSE)
md_cty <- read_csv(md_path, show_col_types = FALSE)
treat <- read_csv(treat_path, show_col_types = FALSE)

stopifnot(!"MD" %in% panel$state_abb)

md_treat_start <- treat |>
  filter(state == "Maryland") |>
  pull(online_start_date) |>
  as.Date()
stopifnot(length(md_treat_start) == 1, !is.na(md_treat_start))

# Every month must carry all 24 jurisdictions, otherwise the state total for
# that month is a partial sum masquerading as a complete one.
coverage <- md_cty |> count(month_date, name = "n_juris")
incomplete <- coverage |> filter(n_juris != 24)
if (nrow(incomplete) > 0) {
  print(incomplete)
  stop("Some MD months lack all 24 jurisdictions; aggregation would understate them.")
}

# Trim to the panel's existing extent. MD runs 2005-01 to 2026-05; months
# outside the panel window are left in the county file rather than creating
# a stretch or terminal month that only MD occupies.
panel_start <- min(panel$month_date)
panel_end   <- max(panel$month_date)

md_state <- md_cty |>
  group_by(month_date) |>
  summarise(filings_count = sum(lt_filed), .groups = "drop") |>
  filter(month_date >= panel_start, month_date <= panel_end) |>
  transmute(
    state_abb = "MD",
    month_date,
    filings_count,
    renter_occupied_housing_units = MD_RENTERS,
    filings_per_1k_renters = filings_count / MD_RENTERS * 1000,
    treat_start = md_treat_start,
    treated = month_date >= md_treat_start
  )

dir.create(backup_dir, showWarnings = FALSE, recursive = TRUE)
backup_path <- file.path(backup_dir, "state_month_panel_with_treatment_pre_md_merge_2026-07-23.csv")
if (!file.exists(backup_path)) file.copy(panel_path, backup_path)

panel_out <- bind_rows(panel, md_state) |> arrange(state_abb, month_date)

# --- assertions -------------------------------------------------------------
expected_md <- length(seq(max(panel_start, min(md_cty$month_date)),
                          min(panel_end, max(md_cty$month_date)), by = "month"))
stopifnot(
  !anyDuplicated(paste(panel_out$state_abb, panel_out$month_date)),
  !any(is.na(panel_out$filings_count)),
  nrow(md_state) == expected_md,
  all(md_state$filings_count > 0),
  # every pre-existing state untouched
  nrow(panel_out |> filter(state_abb != "MD")) == nrow(panel),
  identical(
    as.data.frame(panel |> arrange(state_abb, month_date)),
    as.data.frame(panel_out |> filter(state_abb != "MD"))
  )
)

write_csv(panel_out, panel_path)

pre_n  <- sum(md_state$month_date < md_treat_start)
post_n <- sum(md_state$month_date >= md_treat_start)
message(glue(
  "MD merged: {nrow(md_state)} months ({format(min(md_state$month_date))} to ",
  "{format(max(md_state$month_date))}); {pre_n} pre-treatment, {post_n} post ",
  "(treat_start {format(md_treat_start)}). Panel now {n_distinct(panel_out$state_abb)} states, ",
  "{nrow(panel_out)} rows. Backup: {backup_path}"
))
