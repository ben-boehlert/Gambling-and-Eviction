# Extend North Carolina in the two county-level files on analysis paths, using
# the NC AOC Summary Ejectment series parsed by 09b_:
#   data/raw/monthly_county_data_download.csv   (state-panel rebuild, CS power sim, diagnostics)
#   data/raw/combined_monthly_panel.csv         (power sims + pretrends)
#
# WHY. The ETS county download stops at 2023-06 for NC. NC's online sports
# betting start is 2024-03-11, so NC contributed ZERO treated observations while
# still carrying a treat_start -- it silently served as a control. Worse, under
# the fixed-basket rule added to rebuild_state_month_panel.R on 2026-08-20, no NC
# county reports in every basket-window month, so NC dropped out of the rebuilt
# state panel entirely (0 rows). This extension carries NC to 2026-06, giving it
# 28 post-treatment months.
#
# APPEND-ONLY ON THE SEAM. Existing ETS rows (2016-01..2023-06) are left exactly
# as they are; only months AFTER the current NC maximum are added. That keeps
# every existing county-download-based result bit-for-bit reproducible. The seam
# is clean on its own merits: over the 9,000 overlapping county-months the two
# sources agree exactly on 99.8%, mean difference -0.01 filings, max |difference|
# 26 (Wake County, ~1%); statewide 2023-06 is 16,165 (ETS) vs 16,130 (AOC).
#
# DENOMINATORS. renter_occupied_housing_units and poverty_rate are constant per
# county for the whole NC download (verified: 0 of 100 counties ever vary), so
# carrying them forward is exact, not an approximation. NCAOC supplies no
# denominator of its own. percent_of_historical_average / filings_avg are ETS
# derived fields with no AOC analogue and are written NA.
#
# Originals are backed up ONCE under data/raw/deprecated/.
# Idempotent: re-running appends nothing, because NC's max month has moved.
#
# Usage: Rscript data_prep/monthly_panel_expansion/09c_extend_nc_in_county_files.R

suppressMessages({ library(tidyverse); library(glue) })

sume_path  <- "data/raw/monthly_expansion/nc_sume_county_month.csv"
download   <- "data/raw/monthly_county_data_download.csv"
combined   <- "data/raw/combined_monthly_panel.csv"
backup_dir <- "data/raw/deprecated"
SRC        <- "nc_aoc_sume_2026-08-20"

dir.create(backup_dir, showWarnings = FALSE, recursive = TRUE)

sume <- read_csv(sume_path, show_col_types = FALSE,
                 col_types = cols(fips = col_character())) %>%
  mutate(month_date = as.Date(month_date))
stopifnot(n_distinct(sume$fips) == 100)

# ---- 1) monthly_county_data_download.csv -----------------------------------
bk1 <- file.path(backup_dir, "monthly_county_data_download_pre_nc_extension_2026-08-20.csv")
if (!file.exists(bk1)) { file.copy(download, bk1); message("backed up -> ", bk1) }

dl <- read_csv(download, show_col_types = FALSE, col_types = cols(.default = "c"))
dl_nc <- dl %>% filter(str_starts(fips, "37"))
nc_max <- max(as.Date(substr(dl_nc$date, 1, 10)))
message(glue("download: NC currently ends {nc_max}"))

# Per-county constants carried forward (constant across the whole NC series).
const1 <- dl_nc %>%
  group_by(fips) %>%
  summarise(name = first(name),
            renters = first(renter_occupied_housing_units),
            poverty = first(poverty_rate), .groups = "drop")
stopifnot(nrow(const1) == 100)

add1 <- sume %>%
  filter(month_date > nc_max) %>%
  left_join(const1, by = "fips") %>%
  transmute(fips, name,
            date = paste0(format(month_date, "%Y-%m-%d"), " 12:00:00"),
            filings_count = as.character(sume_filings),
            percent_of_historical_average = NA_character_,
            renter_occupied_housing_units = renters,
            poverty_rate = poverty)

# Append only; existing rows keep their exact original order and position.
dl_out <- bind_rows(dl, add1)
write_csv(dl_out, download, na = "NA")   # the download uses literal NA as its missing marker
message(glue("download: appended {nrow(add1)} NC rows ",
             "({n_distinct(add1$date)} months x {n_distinct(add1$fips)} counties)"))

# ---- 2) combined_monthly_panel.csv -----------------------------------------
bk2 <- file.path(backup_dir, "combined_monthly_panel_pre_nc_extension_2026-08-20.csv")
if (!file.exists(bk2)) { file.copy(combined, bk2); message("backed up -> ", bk2) }

cmb <- read_csv(combined, show_col_types = FALSE, col_types = cols(.default = "c"))
cmb_nc <- cmb %>% filter(geo_level == "county", str_starts(fips, "37"))
nc_max2 <- max(as.Date(cmb_nc$month_date))
message(glue("combined: NC currently ends {nc_max2}"))

const2 <- cmb_nc %>%
  group_by(fips) %>%
  summarise(geo_name = first(geo_name), geo_id = first(geo_id),
            renters = first(renter_occupied_housing_units),
            poverty = first(poverty_rate), .groups = "drop")
stopifnot(nrow(const2) == 100)

add2 <- sume %>%
  filter(month_date > nc_max2) %>%
  left_join(const2, by = "fips") %>%
  transmute(geo_level = "county", geo_id, geo_name,
            month_date = format(month_date, "%Y-%m-%d"), fips,
            filings_count = as.character(sume_filings),
            filings_avg = NA_character_,
            percent_of_historical_average = NA_character_,
            renter_occupied_housing_units = renters, poverty_rate = poverty,
            source = SRC,
            filings_per_1k_renters =
              as.character(sume_filings / as.numeric(renters) * 1000))

cmb_out <- bind_rows(cmb, add2)
write_csv(cmb_out, combined, na = "NA")
message(glue("combined: appended {nrow(add2)} NC rows"))

# ---- Verification ----------------------------------------------------------
chk <- read_csv(download, show_col_types = FALSE,
                col_types = cols(fips = col_character(), filings_count = col_double())) %>%
  filter(str_starts(fips, "37")) %>%
  mutate(m = as.Date(substr(date, 1, 10)))
stopifnot(all(count(chk, m)$n == 100))       # still 100 counties in every month
message(glue("\nVERIFY download NC: {n_distinct(chk$m)} months ",
             "{min(chk$m)} .. {max(chk$m)}, 100 counties every month"))
message(glue("VERIFY treated months (>= 2024-03-01): ",
             "{n_distinct(chk$m[chk$m >= as.Date('2024-03-01')])}"))
