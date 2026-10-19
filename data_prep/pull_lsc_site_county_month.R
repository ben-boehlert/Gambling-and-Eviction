#!/usr/bin/env Rscript
# ============================================================================
# pull_lsc_site_county_month.R  (2026-09-17)
#
# Pull the LSC Civil Court Data Initiative county-month eviction series from the
# LIVE SITE rather than the bulk CSV download.
#
# WHY. The bulk "monthly_county_data_download.csv" LSC serves ends 2025-09 for
# EVERY state (verified on the 2026-09-17 pull), while the per-state dashboards
# at civilcourtdata.lsc.gov run to 2026-06. The dashboard is a Gatsby static
# site: each county page ships its full monthly series as JSON at
#   https://civilcourtdata.lsc.gov/page-data/data/eviction/<state>/<county>/page-data.json
# with the SAME fields as the bulk file (filings_count,
# percent_of_historical_average). The county pages are enumerated from
# /sitemap.xml. 1,461 counties, ~1 minute.
#
# TWO DIFFERENCES FROM THE BULK FILE, both handled here:
#   1. The site emits a row for EVERY county-month, zeros included; the bulk
#      file omits zero rows. A zero on the site means "nothing reported", not
#      zero filings (29,111 of the 29,130 site-only historical keys on
#      2026-09-17 were zeros). Zero rows are DROPPED so the output has the bulk
#      file's semantics and the fixed-basket rule sees the same thing.
#   2. The site carries LSC's current revisions; the bulk file is a vintage.
#      This script writes the site as-is. Deciding what to do with revised
#      history is append_lsc_site_months.R's job, not this one's.
#
# Output: data/raw/monthly_expansion/lsc_site/lsc_site_county_month_<YYYY-MM-DD>.csv
#         (bulk-file layout: fips,name,date,filings_count,
#          percent_of_historical_average,renter_occupied_housing_units,
#          poverty_rate, plus state_short and slug)
# Cache : data/raw/monthly_expansion/lsc_site/pages_<YYYY-MM-DD>/  (raw JSON;
#         re-runs on the same day reuse it)
# Run from the project root:  Rscript data_prep/pull_lsc_site_county_month.R
# ============================================================================
suppressMessages({ library(tidyverse); library(jsonlite); library(curl) })

STAMP   <- format(Sys.Date(), "%Y-%m-%d")
BASE    <- "https://civilcourtdata.lsc.gov"
OUT_DIR <- "data/raw/monthly_expansion/lsc_site"
CACHE   <- file.path(OUT_DIR, paste0("pages_", STAMP))
dir.create(CACHE, recursive = TRUE, showWarnings = FALSE)

# ---- 1. County page list from the sitemap -----------------------------------
sm <- readLines(curl(paste0(BASE, "/sitemap.xml")), warn = FALSE)
paths <- str_extract_all(paste(sm, collapse = "\n"),
                         "https://civilcourtdata\\.lsc\\.gov/data/eviction/[a-z-]+/[a-z0-9-]+/")[[1]] %>%
  unique() %>% str_remove(fixed(paste0(BASE, "/data/eviction/"))) %>% str_remove("/$")
cat(sprintf("[%s] sitemap lists %d county pages\n", STAMP, length(paths)))
stopifnot(length(paths) > 1000)

# ---- 2. Fetch page-data JSON (cached) ---------------------------------------
fetch_one <- function(p) {
  f <- file.path(CACHE, paste0(str_replace(p, "/", "__"), ".json"))
  if (file.exists(f) && file.size(f) > 0) return(f)
  url <- sprintf("%s/page-data/data/eviction/%s/page-data.json", BASE, p)
  ok <- tryCatch({ curl_download(url, f, quiet = TRUE); TRUE },
                 error = function(e) { if (file.exists(f)) file.remove(f); FALSE })
  if (!ok) NA_character_ else f
}
files <- character(length(paths))
pb <- 0L
for (i in seq_along(paths)) {
  files[i] <- fetch_one(paths[i])
  if (i %% 200L == 0L) cat(sprintf("  fetched %d / %d\n", i, length(paths)))
}
failed <- paths[is.na(files)]
if (length(failed)) {
  cat("FAILED (", length(failed), "):", paste(head(failed, 20), collapse = " "), "\n")
}
stopifnot("more than 1% of county pages failed" = length(failed) < 0.01 * length(paths))

# ---- 3. Parse ---------------------------------------------------------------
parse_one <- function(f, p) {
  d <- fromJSON(f, simplifyVector = TRUE)$result$data
  m <- d$monthly$nodes
  if (is.null(m) || !nrow(m)) return(NULL)
  cty <- d$county
  tibble(fips = sprintf("%05d", as.integer(m$fips)),
         name = as.character(m$name),
         date = as.character(m$date),
         filings_count = suppressWarnings(as.numeric(m$filings_count)),
         percent_of_historical_average =
           suppressWarnings(as.numeric(m$percent_of_historical_average)),
         renter_occupied_housing_units =
           suppressWarnings(as.numeric(cty$renter_occupied_housing_units %||% NA)),
         poverty_rate = suppressWarnings(as.numeric(cty$poverty_rate %||% NA)),
         state_short = as.character(cty$state_short %||% NA),
         slug = p)
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
site <- map2_dfr(files[!is.na(files)], paths[!is.na(files)], parse_one)
n_zero <- sum(site$filings_count == 0, na.rm = TRUE)
site <- site %>% filter(!is.na(filings_count), filings_count > 0)
cat(sprintf("parsed %d county-month rows after dropping %d zero rows; %d counties; %s .. %s\n",
            nrow(site), n_zero, n_distinct(site$fips),
            min(as.Date(site$date)), max(as.Date(site$date))))
stopifnot(!anyDuplicated(site[, c("fips", "date")]))

out <- file.path(OUT_DIR, paste0("lsc_site_county_month_", STAMP, ".csv"))
write_csv(site, out)
cat("wrote", out, "\n")
