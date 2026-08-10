# ============================================================================
# 03_pull_nj_courts.R
#
# Purpose: Build New Jersey vicinage/county-month landlord-tenant filings
#          panel from NJ Courts' Special Civil Part dashboards.
#
# Source:  NJ Courts Landlord/Tenant Dashboard (Tableau)
#          https://www.njcourts.gov/  (navigate to Public -> Statistics ->
#          Special Civil Part / Landlord-Tenant dashboard)
#
# Coverage: 15 vicinages (≈ counties; some multi-county). NJ publishes
#          monthly Special Civil Part LT filings in a Tableau dashboard
#          plus historical monthly PDFs back to ~2010.
#
# HOW THIS SCRIPT WORKS:
#   NJ Courts does NOT expose an open API. Three realistic paths:
#
#   (A) TABLEAU DOWNLOAD (easiest, recent data only): On the public
#       Landlord/Tenant dashboard, use Tableau's "Download -> Crosstab"
#       or "Data" button to get CSV of monthly vicinage filings. Save to:
#         data/raw/monthly_expansion/nj_raw/
#
#   (B) OPRA REQUEST (best for historical 2016-2025): File an OPRA
#       (Open Public Records Act) request with the NJ Administrative
#       Office of the Courts:
#         https://www.njcourts.gov/public/opra
#       Request text:
#         "Pursuant to OPRA, I request a machine-readable dataset of
#          Special Civil Part Landlord/Tenant case filings, monthly,
#          by vicinage, from January 2016 through the present. Preferred
#          format: CSV. Please include case type, filing date, vicinage,
#          and disposition code. I am willing to accept aggregated counts
#          by vicinage-month if case-level data is not available."
#       Fee: usually waived for aggregate counts. Turnaround 2-6 weeks.
#
#   (C) SCRAPE MONTHLY PDFs: NJ Courts publishes monthly "Special Civil
#       Part Statewide Landlord/Tenant" PDF reports. Historical PDFs
#       archived by vicinage. Scrape with tabulizer. Tedious but free.
#
# Vicinage -> county crosswalk (15 vicinages; some cover multiple counties):
#   1  Atlantic/Cape May          6  Essex              11 Mercer
#   2  Bergen                     7  Hudson             12 Middlesex
#   3  Burlington                 8  Hunterdon/Somerset/Warren
#   4  Camden                     9  Monmouth           13 Morris/Sussex
#   5  Cumberland/Gloucester/     10 Ocean              14 Passaic
#      Salem                                           15 Union
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
IN_DIR  <- file.path(OUT_DIR, "nj_raw")
dir.create(IN_DIR, showWarnings = FALSE, recursive = TRUE)

INPUT_MODE <- "pending"  # "pending" | "tableau" | "opra"

if (INPUT_MODE == "pending") {
  message("\nNJ data NOT yet obtained.")
  message("Actions required:")
  message("  1. [Recommended] File OPRA request with NJ AOC for monthly")
  message("     vicinage-level LT filings 2016-present. See prompt in")
  message("     script header.")
  message("  2. OR: Download Tableau crosstab from the public NJ Courts")
  message("     Landlord/Tenant dashboard; save to ", IN_DIR)
  message("  3. Change INPUT_MODE and re-run.")

  empty <- tibble(
    state_abb = character(),
    vicinage  = character(),
    county    = character(),
    month     = as.Date(character()),
    filings   = integer()
  )
  write_csv(empty, file.path(OUT_DIR, "nj_county_month_panel.csv"))
  quit(save = "no", status = 0)
}

# ---- Vicinage -> county crosswalk -----------------------------------------
vicinage_xwalk <- tribble(
  ~vicinage, ~counties_covered,
  "1",  "Atlantic,Cape May",
  "2",  "Bergen",
  "3",  "Burlington",
  "4",  "Camden",
  "5",  "Cumberland,Gloucester,Salem",
  "6",  "Essex",
  "7",  "Hudson",
  "8",  "Hunterdon,Somerset,Warren",
  "9",  "Monmouth",
  "10", "Ocean",
  "11", "Mercer",
  "12", "Middlesex",
  "13", "Morris,Sussex",
  "14", "Passaic",
  "15", "Union"
)
write_csv(vicinage_xwalk, file.path(OUT_DIR, "nj_vicinage_county_xwalk.csv"))

if (INPUT_MODE == "tableau") {
  # Tableau crosstab typically exports as wide CSV with columns per month.
  # Reshape to long. Replace file name after downloading.
  f <- list.files(IN_DIR, pattern = "\\.csv$", full.names = TRUE)
  stopifnot(length(f) >= 1)
  raw <- read_csv(f[1], show_col_types = FALSE)
  # TODO after inspecting: pivot_longer columns matching month patterns
  stop("Implement reshape after inspecting Tableau crosstab format.")
}

if (INPUT_MODE == "opra") {
  # OPRA response is typically already in the right shape. Adjust below.
  f <- list.files(IN_DIR, pattern = "\\.csv$|\\.xlsx$", full.names = TRUE)
  stopifnot(length(f) >= 1)
  # Read, clean, pivot, write. Schema depends on what AOC delivers.
  stop("Implement reshape after OPRA response received.")
}
