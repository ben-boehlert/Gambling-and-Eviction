# ============================================================================
# 02_pull_or_evictedinoregon.R
#
# Purpose: Build Oregon county-month eviction filings panel from the
#          "Evicted in Oregon" project (Portland State University).
#
# Source:  https://www.evictedinoregon.com/data-tables
#          https://evictionresearch.net/oregon/
#
# Coverage advertised: circuit-court filings, 26 counties, 2017-present,
#          updated regularly. This is ~90% of OR evictions (excludes
#          justice/municipal courts in 13 counties).
#
# HOW THIS SCRIPT WORKS:
#   The "Data Tables" page has six Tableau-driven tables. Each has a
#   "Get the Data" link at the bottom that exports to CSV. There is NO
#   published stable API or GitHub repo.
#
#   Two viable paths:
#
#   (A) MANUAL (recommended): Visit
#         https://www.evictedinoregon.com/data-tables
#       For table "Number of eviction cases filed", click the year tabs or
#       "Most Recent" tab, then click "Get the Data" at the bottom. Download
#       CSV for each year you need (2017-2025) into:
#         data/raw/monthly_expansion/or_raw/
#       Then set INPUT_MODE <- "manual" below and run this script to
#       consolidate.
#
#   (B) EMAIL REQUEST: Contact Lisa Bates / Greg Townley (evicted@pdx.edu).
#       Ask for: "monthly county-level circuit court eviction filings,
#       2016-2025, in CSV format". They share data with researchers and
#       have the underlying OJD OECI pulls already cleaned.
#
#   (C) BULK OJD RECORDS REQUEST: Email OJD Office of the State Court
#       Administrator (public.records@ojd.state.or.us). Request:
#       "Forcible entry and detainer (FED) case filings by circuit court
#       and filing date, 2016-2025, as a CSV or database export." Typical
#       turnaround 4-8 weeks. No subscription fee for public records.
#
# Author: Ben Boehlert / Claude Code
# Date:   2026-04-15
# ============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
})

PROJECT_ROOT <- here::here()
OUT_DIR <- file.path(PROJECT_ROOT, "data", "raw", "monthly_expansion")
IN_DIR  <- file.path(OUT_DIR, "or_raw")
dir.create(IN_DIR, showWarnings = FALSE, recursive = TRUE)

# ---- Mode ------------------------------------------------------------------
# "manual"   : consolidate CSVs you downloaded from evictedinoregon.com
# "pending"  : just stub the output; you haven't obtained the data yet
INPUT_MODE <- "pending"

if (INPUT_MODE == "pending") {
  message("\nOregon data NOT yet obtained.")
  message("Actions required:")
  message("  1. Email evicted@pdx.edu requesting monthly county panel, OR")
  message("  2. Download the 'Number of eviction cases filed' tables from")
  message("     https://www.evictedinoregon.com/data-tables (one per year)")
  message("     and save to: ", IN_DIR)
  message("  3. Change INPUT_MODE to 'manual' and re-run this script.")

  # Write empty schema so downstream merge doesn't crash
  empty <- tibble(
    state_abb  = character(),
    county     = character(),
    month      = as.Date(character()),
    filings    = integer()
  )
  write_csv(empty, file.path(OUT_DIR, "or_county_month_panel.csv"))
  quit(save = "no", status = 0)
}

# ---- Manual mode: consolidate downloaded CSVs ------------------------------
if (INPUT_MODE == "manual") {
  files <- list.files(IN_DIR, pattern = "\\.csv$", full.names = TRUE)
  if (length(files) == 0) {
    stop("No CSVs found in ", IN_DIR, ". Download from evictedinoregon.com first.")
  }

  # Tableau exports typically have columns like:
  #   "County", "Month Year of Event Date", "Count of Case Number"
  # Tweak the mapping below after inspecting the first file.
  raw <- map_dfr(files, ~{
    read_csv(.x, show_col_types = FALSE) %>%
      janitor::clean_names()
  })

  # Column names to be confirmed after first download — typical pattern:
  panel_or <- raw %>%
    rename(
      county = matches("^county$"),
      month  = matches("month.*year|date"),
      filings = matches("count|filings|n$")
    ) %>%
    mutate(
      month = parse_date_time(month, orders = c("my", "mdy", "Ymd", "Ym")) %>%
              floor_date("month") %>%
              as.Date(),
      state_abb = "OR",
      filings = as.integer(filings)
    ) %>%
    select(state_abb, county, month, filings) %>%
    filter(!is.na(month), !is.na(county))

  write_csv(panel_or, file.path(OUT_DIR, "or_county_month_panel.csv"))
  message("Wrote OR panel: ", nrow(panel_or), " rows, ",
          length(unique(panel_or$county)), " counties, ",
          min(panel_or$month), " to ", max(panel_or$month))
}
