#!/usr/bin/env Rscript
# ============================================================================
# 07c_parse_me_fed_monthly15yr.R  (2026-10-19)
#
# Parse the Maine Judicial Branch "15-Year Monthly FED Filing Trends" PDF into
# state-month and county-month FED (eviction) filing counts.
#
# Source: https://www.courts.maine.gov/about/reports/fed-monthly15yr-report.pdf
#         (index: https://www.courts.maine.gov/about/reports-data.html)
# Local copy: data/raw/monthly_expansion/me_raw/fed-monthly15yr-report_ref20260918.pdf
#         SHA-256 a14620d68362c20cba36aff703b3241e591092256553218930efaaf11f415c70
#         Newest page ref date 2026-09-18 (August page).
#
# LAYOUT -- READ BEFORE RE-USING ON ANOTHER COPY. One page per calendar month,
# each a rolling 15-year window. The court updates a month's page only when that
# month closes, so the pages do NOT share a year header: in this copy Jan-Aug run
# 2012-2026 and Sep-Dec run 2011-2025. Each page's years are therefore read from
# THAT page's own header line. The pre-2026-10-19 parse read every page with one
# header, which put the not-yet-updated pages a year late; add_me_to_state_panel.R
# then patched that copy with a fixed Jun-Dec -12 month relabel. That relabel is
# specific to that copy (its boundary sat at June) and must not be applied to
# this output, whose labels are already correct.
#
# Checks (stop on failure): 12 month pages; 15 year columns per page; 16 counties
# per page; counties sum to the Statewide row and court locations sum to the
# Statewide row in every column; no duplicate month.
#
# Output: data/raw/monthly_expansion/me_fed_state_month_ref20260918.csv
#         data/raw/monthly_expansion/me_fed_county_month_ref20260918.csv
# Run from the project root:
#   Rscript data_prep/monthly_panel_expansion/07c_parse_me_fed_monthly15yr.R
# ============================================================================
suppressMessages({ library(tidyverse); library(pdftools); library(glue) })

PDF <- "data/raw/monthly_expansion/me_raw/fed-monthly15yr-report_ref20260918.pdf"
OUT_STATE  <- "data/raw/monthly_expansion/me_fed_state_month_ref20260918.csv"
OUT_COUNTY <- "data/raw/monthly_expansion/me_fed_county_month_ref20260918.csv"
SOURCE <- paste("Maine Judicial Branch 15-Year Monthly FED Filing Trends",
                "(fed-monthly15yr-report.pdf, MEJIS warehouse, newest ref date 2026-09-18,",
                "parsed per-page headers 2026-10-19)")

ME_COUNTIES <- c("York", "Cumberland", "Androscoggin", "Franklin", "Oxford", "Kennebec",
                 "Somerset", "Penobscot", "Piscataquis", "Knox", "Lincoln", "Sagadahoc",
                 "Waldo", "Hancock", "Washington", "Aroostook")

stopifnot("PDF not found" = file.exists(PDF))

# The PDF can hold one month per page, or a month can run onto a second page;
# split on the month heading instead of on pages to be safe.
txt   <- paste(pdf_text(PDF), collapse = "\n")
lines <- str_split(txt, "\n")[[1]]
heads <- which(str_detect(lines, "MONTH of [A-Za-z]+ FILINGS"))
stopifnot("expected 12 month sections" = length(heads) == 12L)

nums <- function(s) as.integer(str_extract_all(s, "-?\\d+")[[1]])

parse_section <- function(i) {
  from <- heads[i]
  to   <- if (i < length(heads)) heads[i + 1] - 1L else length(lines)
  sec  <- lines[from:to]
  mon_name <- str_match(sec[1], "MONTH of ([A-Za-z]+) FILINGS")[, 2]
  mon <- match(mon_name, month.name)
  stopifnot(!is.na(mon))

  hdr <- sec[str_detect(sec, "REGION\\s+LOCATION")]
  stopifnot("one header per section" = length(hdr) == 1L)
  years <- nums(hdr)
  stopifnot("15 consecutive header years" = length(years) == 15L, all(diff(years) == 1L))

  ref <- str_match(sec, "Ref date:\\s*(\\d{8})")[, 2]
  ref <- ref[!is.na(ref)]
  ref <- if (length(ref)) as.Date(ref[1], "%Y%m%d") else as.Date(NA)

  # Court-location rows: "<region digit> <3-letter code> <15 counts>"
  loc <- str_match(sec, "^\\s*(\\d)\\s+([A-Z]{3})\\s+((?:-?\\d+\\s+){14}-?\\d+)\\s*$")
  loc <- loc[!is.na(loc[, 1]), , drop = FALSE]
  # Named rows: county names and "Statewide"
  nm  <- str_match(sec, "^\\s*([A-Z][a-z]+)\\s+((?:-?\\d+\\s+){14}-?\\d+)\\s*$")
  nm  <- nm[!is.na(nm[, 1]), , drop = FALSE]

  long <- function(m, label_col, val_col) {
    map_dfr(seq_len(nrow(m)), function(r) {
      v <- nums(m[r, val_col]); stopifnot(length(v) == 15L)
      tibble(unit = m[r, label_col], year = years, value = v)
    })
  }
  locs <- long(loc, 3, 4)
  named <- long(nm, 2, 3)
  counties  <- named %>% filter(unit %in% ME_COUNTIES)
  statewide <- named %>% filter(unit == "Statewide")

  stopifnot(
    "16 counties per section" = n_distinct(counties$unit) == 16L,
    "one Statewide row"       = nrow(statewide) == 15L,
    "no unexpected named rows" = all(named$unit %in% c(ME_COUNTIES, "Statewide")))

  chk <- statewide %>% select(year, statewide = value) %>%
    left_join(counties %>% group_by(year) %>% summarise(cty = sum(value)), by = "year") %>%
    left_join(locs %>% group_by(year) %>% summarise(loc = sum(value)), by = "year")
  if (any(chk$cty != chk$statewide) || any(chk$loc != chk$statewide)) {
    print(chk %>% filter(cty != statewide | loc != statewide))
    stop(glue("{mon_name}: counties or locations do not sum to Statewide"))
  }

  list(state = statewide %>% transmute(year, month = mon, fed_filings = value, page_ref_date = ref),
       county = counties %>% transmute(county = unit, year, month = mon, fed_filings = value,
                                       page_ref_date = ref),
       meta = tibble(month = mon_name, first_year = min(years), last_year = max(years),
                     ref_date = ref, n_locations = n_distinct(locs$unit)))
}

parsed <- map(seq_along(heads), parse_section)
meta <- map_dfr(parsed, "meta")
print(meta, n = 12)
stopifnot("each calendar month once" = setequal(meta$month, month.name))

mk_date <- function(df) df %>% mutate(month_date = as.Date(sprintf("%d-%02d-01", year, month)))
state <- map_dfr(parsed, "state") %>% mk_date() %>%
  transmute(state_abb = "ME", year, month, month_date, fed_filings, page_ref_date,
            source = SOURCE) %>% arrange(month_date)
county <- map_dfr(parsed, "county") %>% mk_date() %>%
  transmute(state_abb = "ME", county, year, month, month_date, fed_filings, page_ref_date,
            source = SOURCE) %>% arrange(month_date, county)

stopifnot("duplicate state month" = !anyDuplicated(state$month_date),
          "duplicate county month" = !anyDuplicated(county[c("county", "month_date")]))

write_csv(state, OUT_STATE)
write_csv(county, OUT_COUNTY)
message(glue("ME parsed: {nrow(state)} state-months ",
             "{format(min(state$month_date), '%Y-%m')}..{format(max(state$month_date), '%Y-%m')}, ",
             "{nrow(county)} county-months. Wrote {OUT_STATE} and {OUT_COUNTY}."))
