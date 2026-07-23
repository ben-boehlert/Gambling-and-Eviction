# ============================================================================
# 01b_download_md_statistics_pdfs.R
#
# Purpose: Download the Maryland District Court annual "Calendar Year" statistics
#          PDFs (one PDF per calendar year, each stacking 12 monthly report
#          blocks). These provide pre-2023 landlord-tenant filing counts that
#          Maryland's Socrata open-data portal does not cover, which is required
#          because MD's online-gambling treatment date is 2022-11.
#
# Source page (authoritative link list, scoped 2026-07-21):
#   https://mdcourts.gov/district/about  (section "#stats")
#
# Verified URL patterns (all under
#   https://mdcourts.gov/sites/default/files/import/district/statistics):
#   - 2005-2018 : {YYYY}/{YYYY}stats.pdf
#   - 2019      : 2019/Calendar19.pdf
#   - 2020      : 2020/Calendar20.pdf
#   - 2021-2026 : Calendar_{YYYY}.pdf
#   (Note: the courts.state.md.us mirror and the non-"import" path are tried as
#    fallbacks, then the Wayback Machine.)
#
# Strategy (mirrors 03c_download_nj_statistics_pdfs.R conventions):
#   1. Build a deterministic candidate-URL list per year.
#   2. Try each live URL with curl forced to HTTP/1.1, verifying the payload is
#      a real PDF (leading "%PDF" bytes), skipping files already downloaded.
#   3. If all live URLs fail, ask the Wayback CDX API for the earliest archived
#      200 snapshot and download the raw bytes via the "id_" replay flag.
#   4. Write a manifest so missing years are auditable.
#
# Output:
#   data/raw/monthly_expansion/md_raw/statistics_pdfs/<basename>.pdf
#   data/raw/monthly_expansion/md_raw/md_statistics_pdf_manifest.csv
#
# Usage from project root:
#   Rscript data_prep/monthly_panel_expansion/01b_download_md_statistics_pdfs.R
#
# Optional environment overrides:
#   MD_STATS_START_YEAR=2005
#   MD_STATS_END_YEAR=2026
#   MD_STATS_SLEEP_S=1.0
#   MD_STATS_OVERWRITE=1
#   MD_STATS_WAYBACK=0
# ============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(httr2)
})

set.seed(20260721)

# --- Config -----------------------------------------------------------------

project_root <- tryCatch(here::here(), error = function(e) getwd())
out_root <- file.path(project_root, "data", "raw", "monthly_expansion", "md_raw")
pdf_dir <- file.path(out_root, "statistics_pdfs")
dir.create(pdf_dir, showWarnings = FALSE, recursive = TRUE)

env_or <- function(name, default) {
  value <- Sys.getenv(name, unset = NA_character_)
  if (is.na(value) || value == "") default else value
}

start_year <- as.integer(env_or("MD_STATS_START_YEAR", "2005"))
end_year <- as.integer(env_or("MD_STATS_END_YEAR", format(Sys.Date(), "%Y")))
sleep_s <- as.numeric(env_or("MD_STATS_SLEEP_S", "1.0"))
overwrite <- env_or("MD_STATS_OVERWRITE", "0") %in% c("1", "true", "TRUE", "yes", "YES")
use_wayback <- env_or("MD_STATS_WAYBACK", "1") %in% c("1", "true", "TRUE", "yes", "YES")

user_agent <- paste(
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
  "AppleWebKit/537.36 (KHTML, like Gecko)",
  "Chrome/120.0 Safari/537.36"
)

# --- Helpers ----------------------------------------------------------------

pause <- function() {
  Sys.sleep(sleep_s + runif(1, 0, 0.25))
}

is_pdf_raw <- function(body) {
  length(body) >= 1000 && identical(rawToChar(body[1:4]), "%PDF")
}

#' Basename to save a given year's PDF under (keeps MD's own naming so the
#' file is self-documenting and matches the source URL).
md_basename <- function(year) {
  if (year <= 2018) {
    sprintf("%dstats.pdf", year)
  } else if (year == 2019) {
    "Calendar19.pdf"
  } else if (year == 2020) {
    "Calendar20.pdf"
  } else {
    sprintf("Calendar_%d.pdf", year)
  }
}

#' Ordered candidate URLs for a given year (live sources first).
md_candidate_urls <- function(year) {
  domains <- c("https://mdcourts.gov", "https://www.courts.state.md.us")
  # Relative path fragments (with and without the "import" segment).
  frags <- if (year <= 2018) {
    c(sprintf("/district/statistics/%d/%dstats.pdf", year, year))
  } else if (year == 2019) {
    c("/district/statistics/2019/Calendar19.pdf")
  } else if (year == 2020) {
    c("/district/statistics/2020/Calendar20.pdf")
  } else {
    c(
      sprintf("/district/statistics/Calendar_%d.pdf", year),
      sprintf("/district/statistics/%d/Calendar_%d.pdf", year, year)
    )
  }
  prefixes <- c("/sites/default/files/import", "/sites/default/files")
  urls <- character(0)
  for (dom in domains) {
    for (pre in prefixes) {
      urls <- c(urls, paste0(dom, pre, frags))
    }
  }
  unique(urls)
}

try_download <- function(urls, dest) {
  for (url in urls) {
    tmp <- tempfile(fileext = ".pdf")
    status <- tryCatch(
      system2(
        "curl",
        args = c(
          "-sS", "-L", "--http1.1", "--fail", "--max-time", "60",
          "-A", shQuote(user_agent),
          "-H", shQuote("Accept: application/pdf,*/*"),
          "-o", shQuote(tmp),
          shQuote(url)
        ),
        stdout = TRUE, stderr = TRUE
      ),
      warning = function(w) structure(1L, output = conditionMessage(w)),
      error = function(e) structure(1L, output = conditionMessage(e))
    )
    pause()

    exit_status <- attr(status, "status")
    if (is.null(exit_status)) exit_status <- 0L
    if (!identical(as.integer(exit_status), 0L)) {
      unlink(tmp)
      next
    }
    if (!file.exists(tmp)) next

    body <- readBin(tmp, what = "raw", n = file.info(tmp)$size)
    unlink(tmp)
    if (!is_pdf_raw(body)) next

    writeBin(body, dest)
    return(list(status = "ok", url = url, bytes = length(body)))
  }
  list(status = "not_found", url = NA_character_, bytes = NA_integer_)
}

wayback_earliest <- function(original_url) {
  resp <- tryCatch(
    request("https://web.archive.org/cdx/search/cdx") |>
      req_url_query(
        url = original_url, output = "json", limit = "1",
        filter = "statuscode:200", fl = "timestamp,original",
        collapse = "digest"
      ) |>
      req_user_agent(user_agent) |>
      req_timeout(45) |>
      req_error(is_error = function(resp) FALSE) |>
      req_perform(),
    error = function(e) NULL
  )
  pause()

  if (is.null(resp) || resp_status(resp) != 200) return(NA_character_)
  payload <- tryCatch(resp_body_json(resp), error = function(e) NULL)
  if (is.null(payload) || length(payload) < 2) return(NA_character_)

  timestamp <- payload[[2]][[1]]
  original <- payload[[2]][[2]]
  sprintf("https://web.archive.org/web/%sid_/%s", timestamp, original)
}

download_year <- function(year) {
  filename <- md_basename(year)
  dest <- file.path(pdf_dir, filename)

  if (!overwrite && file.exists(dest) && file.info(dest)$size > 1000) {
    return(tibble(
      year = year, file = filename, source = "cached",
      url_used = NA_character_, size = as.integer(file.info(dest)$size),
      status = "cached"
    ))
  }

  live_urls <- md_candidate_urls(year)
  live_result <- try_download(live_urls, dest)
  if (live_result$status == "ok") {
    return(tibble(
      year = year, file = filename, source = "live",
      url_used = live_result$url, size = as.integer(live_result$bytes),
      status = "ok"
    ))
  }

  if (use_wayback) {
    for (live_url in live_urls) {
      replay_url <- wayback_earliest(live_url)
      if (is.na(replay_url)) next
      archived_result <- try_download(replay_url, dest)
      if (archived_result$status == "ok") {
        return(tibble(
          year = year, file = filename, source = "wayback",
          url_used = replay_url, size = as.integer(archived_result$bytes),
          status = "ok"
        ))
      }
    }
  }

  tibble(
    year = year, file = filename, source = NA_character_,
    url_used = NA_character_, size = NA_integer_, status = "missing"
  )
}

# --- Main -------------------------------------------------------------------

years <- seq.int(start_year, end_year)

message("Downloading Maryland District Court statistics PDFs")
message("  years:    ", start_year, " to ", end_year)
message("  wayback:  ", use_wayback)
message("  output:   ", pdf_dir)

manifest <- vector("list", length(years))
for (i in seq_along(years)) {
  yr <- years[i]
  message(sprintf("  [%02d/%02d] %d (%s)", i, length(years), yr, md_basename(yr)))
  manifest[[i]] <- download_year(yr)
  latest <- manifest[[i]]
  if (latest$status %in% c("ok", "cached")) {
    message(sprintf(
      "           %s (%s, %s bytes)",
      latest$status, latest$source,
      format(latest$size, big.mark = ",", scientific = FALSE)
    ))
  } else {
    message("           missing")
  }
}

manifest <- bind_rows(manifest)
manifest_path <- file.path(out_root, "md_statistics_pdf_manifest.csv")
write_csv(manifest, manifest_path)

message("\n=== MD statistics PDF download summary ===")
print(count(manifest, status, source, name = "n"), n = Inf)
message("Manifest: ", manifest_path)
message("PDFs in:  ", pdf_dir)

missing <- manifest |>
  filter(status == "missing") |>
  pull(year)
if (length(missing) > 0) {
  message("Missing years: ", paste(missing, collapse = ", "))
  message("Re-run later; cached PDFs are skipped. Wayback may be rate-limiting.")
}
