# ============================================================================
# 01c_parse_md_statistics_pdfs.R
#
# Purpose: Parse the Maryland District Court annual statistics PDFs (downloaded
#          by 01b_download_md_statistics_pdfs.R) into tidy county-month
#          landlord-tenant panels.
#
# The annual PDFs stack monthly report blocks of several report types. Two are
# relevant here (layouts verified against 2005, 2018, 2019, 2020, 2022 PDFs):
#
#   (A) "Civil Case Activity Report" (2005 - Jun 2019)
#       The first three numeric columns after the county are the aggregate
#       "Landlord-Tenant Cases" block: Filed / Defendant Appeared / Dismissed.
#       Starting Jul 2019 this block is REMOVED from the Civil report.
#
#   (B) "Landlord/Tenant Case Activity Report" (Jul 2019 onward)
#       A dedicated 11-column detailed report. The first three columns are the
#       "Failure to Pay Rent Cases" Filed / Defendant Appeared / Dismissed,
#       followed by Tenant Holding Over, Breach of Lease, Levy in Distress,
#       Wrongful Detainer, Grantor in Possession, Warrant of Restitution,
#       Evictions, Rent Escrows.
#
# PRIMARY series (continuous 2005-2026): the landlord-tenant Filed / Defendant
# Appeared / Dismissed aggregate. Because no single report type spans the whole
# period, it is sourced from report (A) through Jun 2019 and from the first
# three columns of report (B) thereafter. The two are the same underlying
# series: MD's 2018 Grand Total LT Filed = 56,479/mo transitions to Jul 2019
# Grand Total FTPR Filed = 57,730/mo -- essentially seamless. The exact source
# per row is recorded in `source_report` so the transition is fully auditable.
#
# SECONDARY series (Jul 2019 onward): the detailed report (B) breakdown.
#
# County handling: sub-court-location rows are summed to the county level. Only
# Worcester is split (Snow Hill + Ocean City) in the later schema. County names
# are title-case and matched to the existing MD panel (e.g., "St. Mary's" ->
# "Saint Mary's", "Baltimore County" -> "Baltimore", Baltimore City distinct).
#
# Inputs:
#   data/raw/monthly_expansion/md_raw/statistics_pdfs/*.pdf
#
# Outputs:
#   data/raw/monthly_expansion/md_lt_county_month.csv           (PRIMARY)
#     cols: county, year, month, month_date, lt_filed,
#           lt_defendant_appeared, lt_dismissed, source_report
#   data/raw/monthly_expansion/md_lt_detail_county_month.csv    (SECONDARY)
#     cols: county, year, month, month_date, failure_to_pay_rent_filed,
#           ftpr_defendant_appeared, ftpr_dismissed, tenant_holding_over_filed,
#           breach_of_lease_filed, levy_in_distress, wrongful_detainer,
#           grantor_in_possession, warrant_of_restitution, evictions,
#           rent_escrows, source_report
#
# Usage from project root:
#   Rscript data_prep/monthly_panel_expansion/01c_parse_md_statistics_pdfs.R
# ============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
})

if (!requireNamespace("pdftools", quietly = TRUE)) {
  stop(
    "Package 'pdftools' is required but not installed.\n",
    "Install it once with: install.packages('pdftools')"
  )
}

# --- Config -----------------------------------------------------------------

project_root <- tryCatch(here::here(), error = function(e) getwd())
pdf_dir <- file.path(
  project_root, "data", "raw", "monthly_expansion", "md_raw", "statistics_pdfs"
)
out_dir <- file.path(project_root, "data", "raw", "monthly_expansion")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

primary_path <- file.path(out_dir, "md_lt_county_month.csv")
detail_path <- file.path(out_dir, "md_lt_detail_county_month.csv")

MD_JURISDICTIONS <- c(
  "Allegany", "Anne Arundel", "Baltimore", "Baltimore City", "Calvert",
  "Caroline", "Carroll", "Cecil", "Charles", "Dorchester", "Frederick",
  "Garrett", "Harford", "Howard", "Kent", "Montgomery", "Prince George's",
  "Queen Anne's", "Saint Mary's", "Somerset", "Talbot", "Washington",
  "Wicomico", "Worcester"
)
N_JURISDICTIONS <- length(MD_JURISDICTIONS)

MONTHS <- c(
  "January", "February", "March", "April", "May", "June", "July", "August",
  "September", "October", "November", "December"
)

# --- Helpers ----------------------------------------------------------------

#' Map a raw court-location name to its canonical Maryland county.
#' Sub-court locations (Snow Hill, Ocean City) collapse to their parent county.
#' @param x character vector of raw location names
#' @return character vector of canonical county names
canonical_county <- function(x) {
  # Strip footnote markers (MD attaches trailing asterisks, e.g.
  # "Anne Arundel****") and collapse whitespace before matching.
  x <- str_squish(str_remove_all(x, "[*]"))
  dplyr::case_when(
    x %in% c("Baltimore City") ~ "Baltimore City",
    x %in% c("Baltimore County", "Baltimore") ~ "Baltimore",
    # "Worchester" is MD's own recurring misspelling of Worcester (2009-2012).
    x %in% c("Snow Hill", "Ocean City", "Worcester", "Worchester") ~ "Worcester",
    x %in% c("St. Mary's", "St Mary's", "St.Mary's", "Saint Mary's") ~ "Saint Mary's",
    x %in% c("Prince George's", "Prince Georges", "Prince George") ~ "Prince George's",
    x %in% c("Queen Anne's", "Queen Annes", "Queen Anne") ~ "Queen Anne's",
    x %in% c("Anne Arundel") ~ "Anne Arundel",
    TRUE ~ x
  )
}

#' Extract (month name, year) from a page's text.
#' @param page_text single character string (one PDF page)
#' @return list(month = int or NA, year = int or NA)
parse_period <- function(page_text) {
  m <- str_match(
    page_text,
    "(January|February|March|April|May|June|July|August|September|October|November|December)\\s+(20[0-9]{2})"
  )
  if (is.na(m[1, 1])) return(list(month = NA_integer_, year = NA_integer_))
  list(
    month = match(m[1, 2], MONTHS),
    year = as.integer(m[1, 3])
  )
}

#' Parse the county data rows on a report page.
#' A data row begins with a district code like "1-0", "10-2". Total District
#' and Grand Total rows lack that prefix and are excluded automatically.
#' @param page_text single character string (one PDF page)
#' @return tibble with county_raw and a list-column `nums` of integer values
parse_data_rows <- function(page_text) {
  lines <- str_split(page_text, "\n")[[1]]
  data_lines <- lines[str_detect(lines, "^\\s*[0-9]{1,2}-[0-9]\\s")]
  if (length(data_lines) == 0) {
    return(tibble(county_raw = character(), nums = list()))
  }
  tibble(line = data_lines) |>
    mutate(
      rest = str_remove(.data$line, "^\\s*[0-9]{1,2}-[0-9]"),
      county_raw = str_squish(str_extract(.data$rest, "^[^0-9]+")),
      nums = map(.data$rest, ~ {
        tok <- str_extract_all(.x, "[0-9][0-9,]*")[[1]]
        as.integer(str_remove_all(tok, ","))
      })
    ) |>
    select(county_raw, nums)
}

# --- Load PDFs --------------------------------------------------------------

pdf_files <- list.files(pdf_dir, pattern = "\\.pdf$", full.names = TRUE)
if (length(pdf_files) == 0) {
  stop(
    "No PDFs found in ", pdf_dir, ".\n",
    "Run 01b_download_md_statistics_pdfs.R first."
  )
}
message("Found ", length(pdf_files), " PDF(s) in ", pdf_dir)

# Accumulators
primary_rows <- list()
detail_rows <- list()
issues <- character(0)

CIVIL_TITLE <- "CIVIL CASE ACTIVITY REPORT"
LT_TITLE <- "LANDLORD/ ?TENANT CASE ACTIVITY REPORT"

for (pf in sort(pdf_files)) {
  message("Parsing ", basename(pf))
  pages <- tryCatch(pdftools::pdf_text(pf), error = function(e) {
    issues <<- c(issues, sprintf("%s: pdf_text failed (%s)", basename(pf), conditionMessage(e)))
    character(0)
  })

  for (pg in seq_along(pages)) {
    page_text <- pages[[pg]]
    is_lt_detail <- str_detect(page_text, regex(LT_TITLE, ignore_case = TRUE))
    is_civil <- str_detect(page_text, regex(CIVIL_TITLE, ignore_case = TRUE))
    has_lt_block <- str_detect(page_text, "Landlord-Tenant Cases")

    # Only two page kinds carry the series we want.
    if (!is_lt_detail && !(is_civil && has_lt_block)) next

    period <- parse_period(page_text)
    if (is.na(period$month) || is.na(period$year)) {
      issues <<- c(issues, sprintf("%s p%d: could not parse month/year", basename(pf), pg))
      next
    }
    month_date <- make_date(period$year, period$month, 1L)

    rows <- parse_data_rows(page_text)
    if (nrow(rows) == 0) {
      issues <<- c(issues, sprintf("%s p%d (%s): no data rows found", basename(pf), pg, month_date))
      next
    }

    if (is_lt_detail) {
      # Detailed Landlord/Tenant report (11 columns expected).
      # PRIMARY: needs only the first three columns (FTPR Filed / Appeared /
      # Dismissed), which are reliably present even when a downstream column is
      # blank in the source text. DETAIL: requires the full 11 columns.
      prim_ok <- rows |> filter(lengths(nums) >= 3L)
      if (nrow(prim_ok) == 0) next

      prim_ok <- prim_ok |>
        mutate(
          county = canonical_county(county_raw),
          lt_filed = map_int(nums, 1L),
          lt_defendant_appeared = map_int(nums, 2L),
          lt_dismissed = map_int(nums, 3L)
        )

      unmapped <- setdiff(unique(prim_ok$county), MD_JURISDICTIONS)
      if (length(unmapped) > 0) {
        issues <<- c(issues, sprintf(
          "%s p%d (%s): unmapped county name(s): %s",
          basename(pf), pg, month_date, paste(unmapped, collapse = "; ")
        ))
      }

      primary_rows[[length(primary_rows) + 1L]] <- prim_ok |>
        transmute(
          county, year = period$year, month = period$month, month_date,
          lt_filed, lt_defendant_appeared, lt_dismissed,
          source_report = "landlord_tenant_ftpr"
        )

      # Detailed breakdown: only rows with the full 11-column layout.
      bad_ncol <- rows |> mutate(nc = lengths(nums)) |> filter(nc != 11L)
      if (nrow(bad_ncol) > 0) {
        issues <<- c(issues, sprintf(
          "%s p%d (%s): %d L/T row(s) with != 11 cols (detail only; primary kept): %s",
          basename(pf), pg, month_date, nrow(bad_ncol),
          paste(bad_ncol$county_raw, lengths(bad_ncol$nums), sep = "=", collapse = ", ")
        ))
      }
      det_ok <- rows |> filter(lengths(nums) == 11L)
      if (nrow(det_ok) > 0) {
        detail_rows[[length(detail_rows) + 1L]] <- det_ok |>
          mutate(
            county = canonical_county(county_raw),
            failure_to_pay_rent_filed = map_int(nums, 1L),
            ftpr_defendant_appeared   = map_int(nums, 2L),
            ftpr_dismissed            = map_int(nums, 3L),
            tenant_holding_over_filed = map_int(nums, 4L),
            breach_of_lease_filed     = map_int(nums, 5L),
            levy_in_distress          = map_int(nums, 6L),
            wrongful_detainer         = map_int(nums, 7L),
            grantor_in_possession     = map_int(nums, 8L),
            warrant_of_restitution    = map_int(nums, 9L),
            evictions                 = map_int(nums, 10L),
            rent_escrows              = map_int(nums, 11L)
          ) |>
          transmute(
            county, year = period$year, month = period$month, month_date,
            failure_to_pay_rent_filed, ftpr_defendant_appeared, ftpr_dismissed,
            tenant_holding_over_filed, breach_of_lease_filed, levy_in_distress,
            wrongful_detainer, grantor_in_possession, warrant_of_restitution,
            evictions, rent_escrows,
            source_report = "landlord_tenant_detail"
          )
      }
    } else {
      # Civil Case Activity Report with the Landlord-Tenant block (first 3 cols).
      bad_ncol <- rows |> mutate(nc = lengths(nums)) |> filter(nc < 3L)
      if (nrow(bad_ncol) > 0) {
        issues <<- c(issues, sprintf(
          "%s p%d (%s): %d civil row(s) with < 3 numeric cols: %s",
          basename(pf), pg, month_date, nrow(bad_ncol),
          paste(bad_ncol$county_raw, collapse = ", ")
        ))
      }
      ok <- rows |> filter(lengths(nums) >= 3L)
      if (nrow(ok) == 0) next

      parsed <- ok |>
        mutate(
          county = canonical_county(county_raw),
          lt_filed = map_int(nums, 1L),
          lt_defendant_appeared = map_int(nums, 2L),
          lt_dismissed = map_int(nums, 3L)
        )

      unmapped <- setdiff(unique(parsed$county), MD_JURISDICTIONS)
      if (length(unmapped) > 0) {
        issues <<- c(issues, sprintf(
          "%s p%d (%s): unmapped county name(s): %s",
          basename(pf), pg, month_date, paste(unmapped, collapse = "; ")
        ))
      }

      primary_rows[[length(primary_rows) + 1L]] <- parsed |>
        transmute(
          county, year = period$year, month = period$month, month_date,
          lt_filed, lt_defendant_appeared, lt_dismissed,
          source_report = "civil_case_activity"
        )
    }
  }
}

# --- Aggregate sub-rows to county level -------------------------------------

primary <- bind_rows(primary_rows) |>
  filter(county %in% MD_JURISDICTIONS) |>
  group_by(county, year, month, month_date, source_report) |>
  summarise(
    lt_filed = sum(lt_filed),
    lt_defendant_appeared = sum(lt_defendant_appeared),
    lt_dismissed = sum(lt_dismissed),
    .groups = "drop"
  ) |>
  arrange(month_date, county)

detail <- bind_rows(detail_rows) |>
  filter(county %in% MD_JURISDICTIONS) |>
  group_by(county, year, month, month_date, source_report) |>
  summarise(across(
    c(failure_to_pay_rent_filed, ftpr_defendant_appeared, ftpr_dismissed,
      tenant_holding_over_filed, breach_of_lease_filed, levy_in_distress,
      wrongful_detainer, grantor_in_possession, warrant_of_restitution,
      evictions, rent_escrows),
    sum
  ), .groups = "drop") |>
  relocate(source_report, .after = last_col()) |>
  arrange(month_date, county)

# --- Validation -------------------------------------------------------------

message("\n=== Validation ===")

# Jurisdiction completeness per month (primary series).
completeness <- primary |>
  group_by(month_date) |>
  summarise(n_juris = n_distinct(county), .groups = "drop")
incomplete <- completeness |> filter(n_juris != N_JURISDICTIONS)
if (nrow(incomplete) > 0) {
  message(sprintf(
    "%d month(s) do NOT have all %d jurisdictions:",
    nrow(incomplete), N_JURISDICTIONS
  ))
  incomplete |>
    mutate(missing = map_chr(month_date, ~ paste(
      setdiff(MD_JURISDICTIONS, primary$county[primary$month_date == .x]),
      collapse = ", "
    ))) |>
    (\(d) walk2(d$month_date, d$missing, ~ message(sprintf("   %s: missing %s", .x, .y))))()
} else {
  message(sprintf("All %d months have the full %d jurisdictions.", nrow(completeness), N_JURISDICTIONS))
}

# Parser issues collected along the way.
if (length(issues) > 0) {
  message("\nParser issues (", length(issues), "):")
  walk(issues, ~ message("   ", .x))
} else {
  message("No parser issues recorded.")
}

# Statewide annual totals (auditable magnitude check).
annual_totals <- primary |>
  group_by(year) |>
  summarise(
    lt_filed = sum(lt_filed),
    n_months = n_distinct(month_date),
    .groups = "drop"
  )
message("\nStatewide annual LT filed totals:")
print(annual_totals, n = Inf)

# --- Hard assertions --------------------------------------------------------

stopifnot(
  "primary: no rows parsed" = nrow(primary) > 0,
  "primary: duplicate county x month_date" =
    !anyDuplicated(paste(primary$county, primary$month_date)),
  "primary: NA in lt_filed" = !any(is.na(primary$lt_filed)),
  "primary: NA in lt_defendant_appeared" = !any(is.na(primary$lt_defendant_appeared)),
  "primary: NA in lt_dismissed" = !any(is.na(primary$lt_dismissed)),
  "primary: negative lt_filed" = all(primary$lt_filed >= 0),
  "detail: duplicate county x month_date" =
    (nrow(detail) == 0) || !anyDuplicated(paste(detail$county, detail$month_date)),
  "detail: NA in failure_to_pay_rent_filed" =
    (nrow(detail) == 0) || !any(is.na(detail$failure_to_pay_rent_filed))
)

# --- Write ------------------------------------------------------------------

write_csv(primary, primary_path)
write_csv(detail, detail_path)

message("\n=== Done ===")
message("PRIMARY   -> ", primary_path,
        "  (", nrow(primary), " rows, ",
        format(min(primary$month_date)), " to ", format(max(primary$month_date)), ")")
message("SECONDARY -> ", detail_path,
        "  (", nrow(detail), " rows",
        if (nrow(detail) > 0) paste0(", ", format(min(detail$month_date)), " to ", format(max(detail$month_date))) else "",
        ")")
