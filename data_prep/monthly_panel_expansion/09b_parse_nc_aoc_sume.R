# Parse the NC AOC Civil Issue Filings workbooks into a county-month series of
# Summary Ejectment (eviction) filings.
#
# Structure of each workbook's VCAP_Issues sheet: one row per
# County x Case_Type x Issue_Code, with twelve month columns
# (July_Case_Issue_Filed .. June_Case_Issue_Filed) covering that fiscal year
# (July 1 - June 30). A "Statewide" pseudo-county row is also present and is
# dropped here (verified to equal the county sum exactly in all 132 months).
#
# EVICTION DEFINITION: Issue_Code == "SUME" summed over ALL case types.
#   Do NOT filter to CVM (Civil Magistrate) alone. CVM-only runs ~2% below ETS,
#   and the non-CVM SUME rows (CVD/CVS/M/R) fall from ~875/month in 2022 to
#   ~10/month by 2026 as cases are reclassified into CVM. That reclassification
#   cancels in the total but looks like a downward trend if you take CVM only.
#   Summed over all case types: corr 1.0000 with ETS, median monthly ratio
#   1.0000, min 0.9978 across the 90 overlapping months.
#
# Input:  data/raw/monthly_expansion/nc_aoc/fy*.xlsx        (from 09a_)
# Output: data/raw/monthly_expansion/nc_sume_county_month.csv
#           columns: fips, county, month_date, sume_filings
#
# Runtime: a few minutes (the FY24-25 and FY25-26 workbooks are 10-12 MB).
#
# Usage: Rscript data_prep/monthly_panel_expansion/09b_parse_nc_aoc_sume.R

suppressMessages({ library(tidyverse); library(readxl); library(glue) })

IN_DIR   <- "data/raw/monthly_expansion/nc_aoc"
OUT_PATH <- "data/raw/monthly_expansion/nc_sume_county_month.csv"
DOWNLOAD <- "data/raw/monthly_county_data_download.csv"

files <- sort(list.files(IN_DIR, pattern = "^fy.*\\.xlsx$", full.names = TRUE))
if (!length(files)) stop("No workbooks found. Run 09a_ first.")

month_cols <- c("July", "August", "September", "October", "November", "December",
                "January", "February", "March", "April", "May", "June")
month_num  <- c(7:12, 1:6)

parse_one <- function(path) {
  message(glue("parsing {basename(path)} ..."))
  raw <- read_excel(path, sheet = "VCAP_Issues", guess_max = 5000)
  # Fiscal year start comes from the report's own From_ field, not the filename.
  fy_start <- as.integer(format(as.Date(raw$From_[1]), "%Y"))
  raw %>%
    filter(.data$Issue_Code == "SUME", .data$County != "Statewide") %>%
    select(County, all_of(paste0(month_cols, "_Case_Issue_Filed"))) %>%
    pivot_longer(-County, names_to = "month_name", values_to = "n") %>%
    mutate(
      month_name = str_remove(month_name, "_Case_Issue_Filed"),
      mnum  = month_num[match(month_name, month_cols)],
      year  = if_else(mnum >= 7L, fy_start, fy_start + 1L),
      month_date = as.Date(sprintf("%d-%02d-01", year, mnum)),
      n = replace_na(as.numeric(n), 0)
    ) %>%
    # Sum over case types (multiple rows per county share an Issue_Code).
    group_by(county = str_to_upper(str_trim(County)), month_date) %>%
    summarise(sume_filings = sum(n), .groups = "drop")
}

sume <- map_dfr(files, parse_one)

# ---- FIPS from the ETS download's own NC county names (all 100 match) -------
xwalk <- read_csv(DOWNLOAD, show_col_types = FALSE,
                  col_types = cols(fips = col_character())) %>%
  filter(str_starts(fips, "37")) %>%
  distinct(fips, name) %>%
  mutate(county = str_to_upper(str_trim(str_remove(name, " County$"))))

out <- sume %>%
  left_join(xwalk, by = "county") %>%
  arrange(month_date, fips) %>%
  select(fips, county = name, month_date, sume_filings)

# ---- Guards ----------------------------------------------------------------
stopifnot(!any(is.na(out$fips)))
stopifnot(n_distinct(out$fips) == 100)
per_month <- count(out, month_date)
stopifnot(all(per_month$n == 100))          # all 100 counties every month
stopifnot(all(out$sume_filings >= 0))

write_csv(out, OUT_PATH)
message(glue("\nWrote {OUT_PATH}: {nrow(out)} rows, ",
             "{n_distinct(out$month_date)} months ",
             "({min(out$month_date)} .. {max(out$month_date)}), ",
             "{n_distinct(out$fips)} counties"))
