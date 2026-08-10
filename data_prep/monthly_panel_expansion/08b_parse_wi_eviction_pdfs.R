# ============================================================================
# 08b_parse_wi_eviction_pdfs.R
#
# Purpose: Parse Wisconsin's DOA eviction PDFs (downloaded by 08a) into a tidy
#          county-month panel, and VALIDATE it against two independent checks:
#            (1) internal  : each monthly PDF's own TOTAL row == sum of counties
#            (2) external  : monthly counts summed to the year == the separately
#                            published FULL-YEAR PDF, county by county
#          The two PDF families are produced independently by DOA, so agreement
#          is strong evidence the extraction is faithful.
#
# Monthly PDF layout (2 pages, verified 2019-2025): a wide matrix, one row per
# county, 24 interleaved integers = {Filed, Judgement} x 12 months in calendar
# order. A trailing TOTAL row carries the statewide sum. 2025 is a partial year
# (Jan-Oct), so the parser counts integers rather than assuming 24, and asserts
# every county in a file shares the same month count.
#
# Full-year PDF layout (3 pages): one row per "<County> County", columns
# Population / Filings / Judgements / %-ratio / two population ratios. Only the
# first three integer fields (Population, Filings, Judgements) are taken; the
# decimal ratio columns are stripped first so they cannot leak digits.
#
# Margins: "Filed" is the complaint-stage filing count (comparable to the
# ETS/LSC filings margin used across the panel) and is the PRIMARY series.
# "Judgement" is a downstream margin kept only as a secondary column.
#
# Provenance: Wisconsin Circuit Court Access (WCCA / CCAP) via DOA. Source page
# caveat: "CCAP provides no warranties as to the accuracy or timeliness of the
# information."
#
# Inputs:
#   data/raw/monthly_expansion/wi_raw/pdfs/*.pdf
#
# Outputs:
#   data/raw/monthly_expansion/wi_lt_county_month.csv   (PRIMARY panel)
#     cols: county, year, month, month_date, filed, judgement, source_file
#   data/raw/monthly_expansion/wi_annual_county.csv     (full-year, for audit)
#     cols: county, year, filings_annual, judgements_annual, population, source_file
#   data/raw/monthly_expansion/wi_validation_report.csv (reconciliation results)
#
# Usage from project root:
#   Rscript data_prep/monthly_panel_expansion/08b_parse_wi_eviction_pdfs.R
# ============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
})

if (!requireNamespace("pdftools", quietly = TRUE)) {
  stop("Package 'pdftools' is required. Install with: install.packages('pdftools')")
}

# --- Config -----------------------------------------------------------------

project_root <- tryCatch(here::here(), error = function(e) getwd())
pdf_dir <- file.path(project_root, "data", "raw", "monthly_expansion", "wi_raw", "pdfs")
out_dir <- file.path(project_root, "data", "raw", "monthly_expansion")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

month_path      <- file.path(out_dir, "wi_lt_county_month.csv")
annual_path     <- file.path(out_dir, "wi_annual_county.csv")
validation_path <- file.path(out_dir, "wi_validation_report.csv")

# Canonical Wisconsin counties (72), verified against the 2019 monthly PDF roster.
WI_COUNTIES <- c(
  "Adams", "Ashland", "Barron", "Bayfield", "Brown", "Buffalo", "Burnett",
  "Calumet", "Chippewa", "Clark", "Columbia", "Crawford", "Dane", "Dodge",
  "Door", "Douglas", "Dunn", "Eau Claire", "Florence", "Fond du Lac", "Forest",
  "Grant", "Green", "Green Lake", "Iowa", "Iron", "Jackson", "Jefferson",
  "Juneau", "Kenosha", "Kewaunee", "La Crosse", "Lafayette", "Langlade",
  "Lincoln", "Manitowoc", "Marathon", "Marinette", "Marquette", "Menominee",
  "Milwaukee", "Monroe", "Oconto", "Oneida", "Outagamie", "Ozaukee", "Pepin",
  "Pierce", "Polk", "Portage", "Price", "Racine", "Richland", "Rock", "Rusk",
  "Sauk", "Sawyer", "Shawano", "Sheboygan", "St. Croix", "Taylor",
  "Trempealeau", "Vernon", "Vilas", "Walworth", "Washburn", "Washington",
  "Waukesha", "Waupaca", "Waushara", "Winnebago", "Wood"
)
N_COUNTIES <- length(WI_COUNTIES)

# --- Helpers ----------------------------------------------------------------

#' Integer tokens on a line, commas stripped ("1,118" -> 1118).
extract_ints <- function(s) {
  tok <- str_extract_all(s, "[0-9][0-9,]*")[[1]]
  as.integer(str_remove_all(tok, ","))
}

#' Canonicalize a raw county label to the WI_COUNTIES spelling.
#' Handles the "<County> County" suffix used in the full-year PDFs and the
#' "Saint Croix" / "St Croix" variants.
canonical_county <- function(x) {
  x <- str_squish(str_remove(x, "\\bCounty\\b"))
  case_when(
    x %in% c("St Croix", "St.Croix", "Saint Croix") ~ "St. Croix",
    TRUE ~ x
  )
}

# --- Monthly parser ---------------------------------------------------------

#' Parse one monthly PDF into a long county-month tibble plus its TOTAL row.
#' @return list(panel = tibble(county, month, filed, judgement), total = named)
parse_monthly_pdf <- function(pdf_path, year) {
  pages <- pdftools::pdf_text(pdf_path)
  lines <- unlist(lapply(pages, function(p) str_split(p, "\n")[[1]]))
  lines <- str_trim(lines, side = "right")

  # A data row starts with a county-like label (letters, spaces, dots) followed
  # by whitespace and a digit. Header rows ("Filed", "Judgement", month names)
  # carry no leading integer block of length >= 2 after a county-style prefix.
  county_rows <- tibble(line = lines) |>
    mutate(
      label = str_squish(str_extract(line, "^[A-Za-z][A-Za-z. ]+?(?=\\s{2,}|\\s+[0-9])")),
      nums = map(line, extract_ints)
    ) |>
    filter(!is.na(label), lengths(nums) >= 2)

  # Separate the TOTAL row from the county rows.
  total_row <- county_rows |> filter(str_to_upper(label) == "TOTAL")
  county_rows <- county_rows |> filter(label %in% WI_COUNTIES)

  # Every county must carry the same, even, number of integers.
  ncols <- unique(lengths(county_rows$nums))
  if (length(ncols) != 1) {
    stop(sprintf(
      "%s: counties disagree on integer count (%s)",
      basename(pdf_path), paste(sort(ncols), collapse = ", ")
    ))
  }
  if (ncols %% 2 != 0) {
    stop(sprintf("%s: odd integer count (%d) — Filed/Judgement not paired",
                 basename(pdf_path), ncols))
  }
  n_months <- ncols %/% 2L

  panel <- county_rows |>
    transmute(county = label, nums) |>
    mutate(
      pair = map(nums, function(v) {
        tibble(
          month = seq_len(n_months),
          filed = v[seq(1, by = 2, length.out = n_months)],
          judgement = v[seq(2, by = 2, length.out = n_months)]
        )
      })
    ) |>
    select(county, pair) |>
    unnest(pair) |>
    mutate(year = year, month_date = make_date(year, month, 1L)) |>
    select(county, year, month, month_date, filed, judgement)

  total <- NULL
  if (nrow(total_row) == 1 && length(total_row$nums[[1]]) == ncols) {
    v <- total_row$nums[[1]]
    total <- tibble(
      month = seq_len(n_months),
      total_filed = v[seq(1, by = 2, length.out = n_months)],
      total_judgement = v[seq(2, by = 2, length.out = n_months)]
    )
  }
  list(panel = panel, total = total, n_months = n_months)
}

# --- Full-year parser -------------------------------------------------------

#' Parse one full-year PDF into county annual Population / Filings / Judgements.
parse_full_year_pdf <- function(pdf_path, year) {
  pages <- pdftools::pdf_text(pdf_path)
  lines <- unlist(lapply(pages, function(p) str_split(p, "\n")[[1]]))
  lines <- str_trim(lines)

  # Keep only "<Name> County ..." data rows; drop the "State Total" row (handled
  # separately) and any header/footnote lines.
  keep <- str_detect(lines, "^[A-Za-z][A-Za-z. ]*County\\b")
  data_lines <- lines[keep]

  parse_row <- function(ln) {
    label <- canonical_county(str_extract(ln, "^[A-Za-z][A-Za-z. ]*County"))
    rest <- str_remove(ln, "^[A-Za-z][A-Za-z. ]*County")
    # Strip decimal/percentage columns first so they cannot leak stray integers.
    rest <- str_remove_all(rest, "[0-9][0-9,]*\\.[0-9]+%?")
    ints <- extract_ints(rest)  # -> Population, Filings, Judgements
    tibble(
      county = label,
      population = if (length(ints) >= 1) ints[1] else NA_integer_,
      filings_annual = if (length(ints) >= 2) ints[2] else NA_integer_,
      judgements_annual = if (length(ints) >= 3) ints[3] else NA_integer_
    )
  }

  annual <- map_dfr(data_lines, parse_row) |>
    filter(county %in% WI_COUNTIES) |>
    mutate(year = year, source_file = basename(pdf_path)) |>
    select(county, year, filings_annual, judgements_annual, population, source_file)

  # State Total row, for an internal full-year check.
  st_line <- lines[str_detect(lines, "^State Total")]
  state_total <- NA_integer_
  if (length(st_line) >= 1) {
    rest <- str_remove_all(st_line[1], "[0-9][0-9,]*\\.[0-9]+%?")
    ints <- extract_ints(rest)  # Population, Filings, Judgements
    if (length(ints) >= 2) state_total <- ints[2]
  }
  attr(annual, "state_total_filings") <- state_total
  annual
}

# --- Discover files ---------------------------------------------------------

manifest_path <- file.path(project_root, "data", "raw", "monthly_expansion",
                           "wi_raw", "wi_eviction_pdf_manifest.csv")
if (!file.exists(manifest_path)) {
  stop("Manifest not found: ", manifest_path, "\nRun 08a_download_wi_eviction_pdfs.R first.")
}
manifest <- read_csv(manifest_path, show_col_types = FALSE) |>
  filter(status %in% c("ok", "cached"))

monthly_files <- manifest |> filter(kind == "monthly")
full_year_files <- manifest |> filter(kind == "full_year")

message("Parsing ", nrow(monthly_files), " monthly and ",
        nrow(full_year_files), " full-year WI PDFs")

# --- Parse monthly ----------------------------------------------------------

panel_list <- list()
total_checks <- list()
for (i in seq_len(nrow(monthly_files))) {
  yr <- monthly_files$year[i]
  pf <- file.path(pdf_dir, monthly_files$file[i])
  message(sprintf("  monthly  %d (%s)", yr, basename(pf)))
  parsed <- parse_monthly_pdf(pf, yr)

  # completeness: all 72 counties present.
  n_here <- n_distinct(parsed$panel$county)
  if (n_here != N_COUNTIES) {
    missing <- setdiff(WI_COUNTIES, unique(parsed$panel$county))
    stop(sprintf("%d monthly: %d/%d counties (missing: %s)",
                 yr, n_here, N_COUNTIES, paste(missing, collapse = ", ")))
  }

  # internal TOTAL-row check.
  if (!is.null(parsed$total)) {
    county_sum <- parsed$panel |>
      group_by(month) |>
      summarise(filed = sum(filed), judgement = sum(judgement), .groups = "drop")
    chk <- parsed$total |>
      left_join(county_sum, by = "month") |>
      mutate(
        filed_ok = total_filed == filed,
        judgement_ok = total_judgement == judgement
      )
    total_checks[[length(total_checks) + 1L]] <- chk |>
      mutate(year = yr) |>
      select(year, month, total_filed, filed, filed_ok,
             total_judgement, judgement, judgement_ok)
  }

  panel_list[[length(panel_list) + 1L]] <- parsed$panel |>
    mutate(source_file = basename(pf))
}

panel <- bind_rows(panel_list) |> arrange(month_date, county)

# --- Parse full-year --------------------------------------------------------

annual_list <- list()
state_total_checks <- list()
for (i in seq_len(nrow(full_year_files))) {
  yr <- full_year_files$year[i]
  pf <- file.path(pdf_dir, full_year_files$file[i])
  message(sprintf("  fullyear %d (%s)", yr, basename(pf)))
  a <- parse_full_year_pdf(pf, yr)
  if (n_distinct(a$county) != N_COUNTIES) {
    missing <- setdiff(WI_COUNTIES, unique(a$county))
    warning(sprintf("%d full-year: %d/%d counties (missing: %s)",
                    yr, n_distinct(a$county), N_COUNTIES, paste(missing, collapse = ", ")))
  }
  st <- attr(a, "state_total_filings")
  state_total_checks[[length(state_total_checks) + 1L]] <- tibble(
    year = yr,
    state_total_filings = st,
    county_sum_filings = sum(a$filings_annual, na.rm = TRUE),
    ok = !is.na(st) && st == sum(a$filings_annual, na.rm = TRUE)
  )
  annual_list[[length(annual_list) + 1L]] <- a
}
annual <- bind_rows(annual_list) |> arrange(year, county)

# --- External reconciliation: monthly-summed == full-year -------------------

monthly_annual <- panel |>
  group_by(county, year) |>
  summarise(
    filed_from_monthly = sum(filed),
    judgement_from_monthly = sum(judgement),
    n_months = n_distinct(month),
    .groups = "drop"
  )

recon <- monthly_annual |>
  inner_join(
    annual |> select(county, year, filings_annual, judgements_annual),
    by = c("county", "year")
  ) |>
  mutate(
    filed_diff = filed_from_monthly - filings_annual,
    judgement_diff = judgement_from_monthly - judgements_annual,
    filed_match = filed_diff == 0,
    judgement_match = judgement_diff == 0
  )

# --- Report -----------------------------------------------------------------

message("\n================ VALIDATION ================")

message("\n[1] Coverage")
cov <- panel |>
  group_by(year) |>
  summarise(n_months = n_distinct(month), n_counties = n_distinct(county),
            rows = n(), .groups = "drop")
print(cov, n = Inf)

message("\n[2] Internal TOTAL-row check (monthly PDF's own total vs sum of counties)")
if (length(total_checks) > 0) {
  tc <- bind_rows(total_checks)
  tc_summary <- tc |>
    group_by(year) |>
    summarise(months = n(),
              filed_mismatches = sum(!filed_ok),
              judgement_mismatches = sum(!judgement_ok), .groups = "drop")
  print(tc_summary, n = Inf)
  if (any(!tc$filed_ok) || any(!tc$judgement_ok)) {
    message("   TOTAL-row mismatches:")
    print(tc |> filter(!filed_ok | !judgement_ok), n = Inf)
  }
} else {
  message("   (no TOTAL rows detected in any monthly PDF)")
}

message("\n[3] Full-year State Total vs sum of county filings")
stc <- bind_rows(state_total_checks)
print(stc, n = Inf)

message("\n[4] External reconciliation: monthly summed to year vs FULL-YEAR PDF")
recon_summary <- recon |>
  group_by(year) |>
  summarise(
    counties = n(),
    n_months = max(n_months),
    filed_mismatches = sum(!filed_match),
    judgement_mismatches = sum(!judgement_match),
    total_filed_diff = sum(abs(filed_diff)),
    .groups = "drop"
  )
print(recon_summary, n = Inf)
if (any(!recon$filed_match)) {
  message("   Filed reconciliation mismatches (county x year):")
  print(recon |> filter(!filed_match) |>
          select(county, year, filed_from_monthly, filings_annual, filed_diff, n_months),
        n = Inf)
}

# Persist the full reconciliation table for auditing.
write_csv(recon, validation_path)

# --- Hard assertions --------------------------------------------------------

# Partial-year files (e.g. 2025) may legitimately cover fewer months than the
# full-year PDF; only require reconciliation where month coverage is complete.
recon_complete <- recon |> filter(n_months == 12)

stopifnot(
  "panel: no rows" = nrow(panel) > 0,
  "panel: duplicate county x month_date" =
    !anyDuplicated(paste(panel$county, panel$month_date)),
  "panel: NA in filed" = !any(is.na(panel$filed)),
  "panel: NA in judgement" = !any(is.na(panel$judgement)),
  "panel: negative filed" = all(panel$filed >= 0),
  "panel: not all 72 counties in every month" =
    all((panel |> count(month_date) |> pull(n)) == N_COUNTIES),
  "reconciliation: complete-year filed mismatch vs full-year PDF" =
    all(recon_complete$filed_match),
  "reconciliation: complete-year judgement mismatch vs full-year PDF" =
    all(recon_complete$judgement_match)
)

# Internal TOTAL rows, where present, must reconcile exactly.
if (length(total_checks) > 0) {
  tc <- bind_rows(total_checks)
  stopifnot(
    "monthly TOTAL row disagrees with sum of counties (filed)" = all(tc$filed_ok),
    "monthly TOTAL row disagrees with sum of counties (judgement)" = all(tc$judgement_ok)
  )
}

# --- Write ------------------------------------------------------------------

panel_out <- panel |>
  select(county, year, month, month_date, filed, judgement, source_file)
write_csv(panel_out, month_path)
write_csv(annual |> select(county, year, filings_annual, judgements_annual,
                           population, source_file), annual_path)

message("\n================ DONE ================")
message("County-month panel -> ", month_path)
message("  ", nrow(panel_out), " rows, ",
        format(min(panel_out$month_date)), " to ", format(max(panel_out$month_date)),
        ", ", N_COUNTIES, " counties")
message("Annual (audit)     -> ", annual_path, "  (", nrow(annual), " county-years)")
message("Reconciliation     -> ", validation_path)
message("\nAll validation checks passed.")
