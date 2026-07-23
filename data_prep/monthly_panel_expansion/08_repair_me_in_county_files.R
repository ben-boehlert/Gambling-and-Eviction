# Propagate the Maine repair into the two county-level files that sit on analysis
# paths: combined_monthly_panel.csv (power sims + pretrends) and
# monthly_county_data_download.csv (CS power sim + diagnostics). Both still carry
# the ETS artifact for ME (2023-06..2023-12 recorded as literal zeros, series
# ending 2023-12). We replace ME's 16 county rows with the Maine Judicial Branch
# county-level FED counts and extend to the panel envelope (2025-11), keeping each
# county's renter/poverty constant. State-level rows and all other states are left
# untouched; only ME county rows change.
#
# Court county source: data/raw/monthly_expansion/me_fed_county_month_year.csv
# Originals backed up under data/raw/deprecated/.

library(tidyverse)
library(glue)

court_path  <- "data/raw/monthly_expansion/me_fed_county_month_year.csv"
combined    <- "data/raw/combined_monthly_panel.csv"
download    <- "data/raw/monthly_county_data_download.csv"
backup_dir  <- "data/raw/deprecated"
me_end      <- as.Date("2025-11-01")   # panel envelope (matches state-panel repair)
SRC         <- "me_court_fed_2026-07-23"

dir.create(backup_dir, showWarnings = FALSE, recursive = TRUE)

# Maine county name -> FIPS (odd-numbered 23001..23031)
me_fips <- c(
  Androscoggin=23001, Aroostook=23003, Cumberland=23005, Franklin=23007,
  Hancock=23009, Kennebec=23011, Knox=23013, Lincoln=23015, Oxford=23017,
  Penobscot=23019, Piscataquis=23021, Sagadahoc=23023, Somerset=23025,
  Waldo=23027, Washington=23029, York=23031
)

court <- read_csv(court_path, show_col_types = FALSE) |>
  filter(month_date >= as.Date("2016-01-01"), month_date <= me_end) |>
  mutate(fips = unname(me_fips[county]))
stopifnot(!any(is.na(court$fips)), n_distinct(court$county) == 16)

# ---- 1) combined_monthly_panel.csv ----------------------------------------
cmb <- read_csv(combined, show_col_types = FALSE, col_types = cols(.default = "c"))
if (!file.exists(file.path(backup_dir, "combined_monthly_panel_pre_me_repair_2026-07-23.csv")))
  file.copy(combined, file.path(backup_dir, "combined_monthly_panel_pre_me_repair_2026-07-23.csv"))

# per-county constants (renters, poverty, geo_name) from existing ME rows
me_const <- cmb |>
  filter(geo_level == "county", str_starts(fips, "23")) |>
  group_by(fips) |>
  summarise(geo_name = first(geo_name),
            renters  = first(renter_occupied_housing_units),
            poverty  = first(poverty_rate), .groups = "drop")
stopifnot(nrow(me_const) == 16)

me_new_combined <- court |>
  mutate(fips = as.character(fips)) |>
  left_join(me_const, by = "fips") |>
  transmute(
    geo_level = "county", geo_id = fips, geo_name, month_date = as.character(month_date),
    fips, filings_count = as.character(fed_filings), filings_avg = NA_character_,
    percent_of_historical_average = NA_character_,
    renter_occupied_housing_units = renters, poverty_rate = poverty, source = SRC,
    filings_per_1k_renters = as.character(fed_filings / as.numeric(renters) * 1000)
  )

cmb_out <- cmb |>
  filter(!(geo_level == "county" & str_starts(fips, "23"))) |>
  bind_rows(me_new_combined)

# ---- 2) monthly_county_data_download.csv ----------------------------------
dl <- read_csv(download, show_col_types = FALSE, col_types = cols(.default = "c"))
if (!file.exists(file.path(backup_dir, "monthly_county_data_download_pre_me_repair_2026-07-23.csv")))
  file.copy(download, file.path(backup_dir, "monthly_county_data_download_pre_me_repair_2026-07-23.csv"))

dl_const <- dl |>
  filter(str_starts(fips, "23")) |>
  group_by(fips) |>
  summarise(name = first(name), renters = first(renter_occupied_housing_units),
            poverty = first(poverty_rate), .groups = "drop")
stopifnot(nrow(dl_const) == 16)

me_new_download <- court |>
  mutate(fips = as.character(fips)) |>
  left_join(dl_const, by = "fips") |>
  transmute(
    fips, name,
    date = paste0(as.character(month_date), " 12:00:00"),  # match existing timestamp format
    filings_count = as.character(fed_filings),
    percent_of_historical_average = NA_character_,
    renter_occupied_housing_units = renters, poverty_rate = poverty
  )

dl_out <- dl |>
  filter(!str_starts(fips, "23")) |>
  bind_rows(me_new_download)

# ---- assertions: state sums match court totals; no fabricated state zeros --
# County-level zeros are legitimate (small counties have 0 FED filings some
# months); the artifact was all 16 counties zero at once, i.e. a zero STATE
# total. So we assert the state total matches the court total exactly and is
# strictly positive in every month.
court_state <- court |> group_by(month_date) |> summarise(court_tot = sum(fed_filings), .groups = "drop")

state_tot <- function(df, dcol) df |>
  mutate(md = as.Date(substr(.data[[dcol]], 1, 10)), fc = as.numeric(filings_count)) |>
  group_by(md) |> summarise(tot = sum(fc), .groups = "drop") |>
  left_join(court_state, by = c("md" = "month_date"))

chk_combined <- state_tot(me_new_combined, "month_date")
chk_download <- state_tot(me_new_download, "date")

stopifnot(
  all(chk_combined$tot == chk_combined$court_tot),
  all(chk_download$tot == chk_download$court_tot),
  all(chk_combined$tot > 0), all(chk_download$tot > 0),   # no fabricated state-level zeros
  # every non-ME row preserved
  nrow(cmb_out |> filter(!(geo_level=="county" & str_starts(fips,"23")))) ==
    nrow(cmb |> filter(!(geo_level=="county" & str_starts(fips,"23")))),
  nrow(dl_out |> filter(!str_starts(fips,"23"))) == nrow(dl |> filter(!str_starts(fips,"23")))
)

write_csv(cmb_out, combined)
write_csv(dl_out, download)

message(glue(
  "combined_monthly_panel: ME {nrow(cmb |> filter(geo_level=='county' & str_starts(fips,'23')))} -> ",
  "{nrow(me_new_combined)} county rows ({n_distinct(me_new_combined$month_date)} months to {me_end}).\n",
  "monthly_county_data_download: ME -> {nrow(me_new_download)} county rows.\n",
  "State-total sanity vs court: combined {nrow(chk_combined)} months OK, download {nrow(chk_download)} months OK."
))
