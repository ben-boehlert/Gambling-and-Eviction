# ============================================================================
# 04_pull_ia_email_request.R
#
# Purpose: Ingest Iowa monthly county-level FED (forcible entry and detainer)
#          filings once received from Iowa State Court Administration (SCA).
#
# Source:  No public API. Data obtained via written request to:
#            Iowa State Court Administration
#            Email: sca@iowacourts.gov
#          Draft request text is in IA_DATA_REQUEST.md in this folder.
#
# Coverage (expected): All 99 counties, monthly, 2013-present, FED case type.
#          Iowa is a unified state court system, so SCA can produce the full
#          state panel from one extract.
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
IN_DIR  <- file.path(OUT_DIR, "ia_raw")
dir.create(IN_DIR, showWarnings = FALSE, recursive = TRUE)

INPUT_MODE <- "pending"  # flip to "received" after SCA responds

if (INPUT_MODE == "pending") {
  message("\nIA data NOT yet obtained.")
  message("Action: email sca@iowacourts.gov with the request text in")
  message("  data_prep/monthly_panel_expansion/IA_DATA_REQUEST.md")
  message("Typical turnaround: 2-6 weeks. Fee usually zero for aggregated counts.")

  empty <- tibble(
    state_abb = character(),
    county    = character(),
    month     = as.Date(character()),
    filings   = integer()
  )
  write_csv(empty, file.path(OUT_DIR, "ia_county_month_panel.csv"))
  quit(save = "no", status = 0)
}

if (INPUT_MODE == "received") {
  f <- list.files(IN_DIR, pattern = "\\.csv$|\\.xlsx$", full.names = TRUE)
  stopifnot(length(f) >= 1)
  raw <- if (grepl("\\.xlsx$", f[1])) readxl::read_excel(f[1]) else read_csv(f[1], show_col_types = FALSE)
  raw <- janitor::clean_names(raw)

  # Expected columns after cleaning: county, filing_month (or year+month), n
  panel_ia <- raw %>%
    # Adjust renames once we see the real file
    rename(
      county  = matches("^county$"),
      month   = matches("month|date"),
      filings = matches("count|filings|cases|n$")
    ) %>%
    mutate(
      month     = as.Date(floor_date(ymd(month), "month")),
      state_abb = "IA",
      filings   = as.integer(filings)
    ) %>%
    select(state_abb, county, month, filings) %>%
    filter(!is.na(month), !is.na(county))

  write_csv(panel_ia, file.path(OUT_DIR, "ia_county_month_panel.csv"))
  message("Wrote IA panel: ", nrow(panel_ia), " rows")
}
