# ============================================================================
# 03b_download_nj_gray_pdfs.R
#
# Purpose: Download NJ Judiciary "gray" civil statistics PDFs.
#
# What's available on njcourts.gov:
#   - Annual FY reports: gray<YY>06.pdf, FY 2004-05 through latest
#     (host rotates between two path prefixes, so we try both)
#   - Current month only: gray<YY><MM>.pdf under /public/statistics/
#     (gets overwritten each month; historical monthlies are NOT archived
#      on the live site)
#
# For historical monthly PDFs we fall back to the Wayback Machine CDX API
# (http://web.archive.org/cdx/search/cdx), which indexes every snapshot
# Archive.org ever took of each gray<YY><MM>.pdf URL. We take the earliest
# snapshot per URL and download from there.
#
# Output:
#   data/raw/monthly_expansion/nj_raw/pdfs/gray<YY><MM>.pdf   (monthly)
#   data/raw/monthly_expansion/nj_raw/pdfs/gray<YY>06_FY.pdf  (annual)
#   data/raw/monthly_expansion/nj_raw/nj_gray_manifest.csv    (what we got)
#
# Usage:
#   Rscript data_prep/monthly_panel_expansion/03b_download_nj_gray_pdfs.R
# or in R from project root:
#   source("data_prep/monthly_panel_expansion/03b_download_nj_gray_pdfs.R")
#
# These PDFs are NOT parsed here — see 03c (not yet written) for tabulizer
# extraction once we see the table structure. This script only acquires them.
#
# Author: Ben Boehlert / Claude Code
# Date:   2026-04-15
# ============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(httr2)
  library(lubridate)
})

set.seed(20260415)

# --- Config -----------------------------------------------------------------
PROJECT_ROOT <- tryCatch(here::here(), error = function(e) getwd())
OUT_ROOT <- file.path(PROJECT_ROOT, "data", "raw", "monthly_expansion", "nj_raw")
PDF_DIR  <- file.path(OUT_ROOT, "pdfs")
dir.create(PDF_DIR, showWarnings = FALSE, recursive = TRUE)

# Date range to attempt
START_YM <- ym("2016-01")
END_YM   <- floor_date(Sys.Date(), "month")

# Throttle (njcourts.gov + Wayback) — polite pause between requests
SLEEP_S <- 1.0

UA <- paste(
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
)

# --- Helpers ----------------------------------------------------------------

#' Try a list of URLs, return the first that returns HTTP 200 with a PDF body.
#' Returns a list(status, url, bytes) where status ∈ {"ok","not_found","error"}.
try_download <- function(urls, dest) {
  for (u in urls) {
    resp <- tryCatch(
      request(u) |>
        req_user_agent(UA) |>
        req_headers(Accept = "application/pdf,*/*") |>
        req_timeout(60) |>
        req_error(is_error = function(r) FALSE) |>
        req_perform(),
      error = function(e) NULL
    )
    Sys.sleep(SLEEP_S)
    if (is.null(resp)) next
    if (resp_status(resp) != 200) next

    body <- resp_body_raw(resp)
    # crude PDF signature check
    if (length(body) < 1000 || !identical(rawToChar(body[1:4]), "%PDF")) next

    writeBin(body, dest)
    return(list(status = "ok", url = u, bytes = length(body)))
  }
  list(status = "not_found", url = NA_character_, bytes = NA_integer_)
}

#' Ask Wayback CDX for earliest snapshot of a URL. Returns the replay URL or NA.
wayback_earliest <- function(original_url) {
  cdx <- "http://web.archive.org/cdx/search/cdx"
  resp <- tryCatch(
    request(cdx) |>
      req_url_query(
        url       = original_url,
        output    = "json",
        limit     = "1",
        filter    = "statuscode:200",
        fl        = "timestamp,original"
      ) |>
      req_user_agent(UA) |>
      req_timeout(30) |>
      req_error(is_error = function(r) FALSE) |>
      req_perform(),
    error = function(e) NULL
  )
  Sys.sleep(SLEEP_S)
  if (is.null(resp) || resp_status(resp) != 200) return(NA_character_)
  j <- tryCatch(resp_body_json(resp), error = function(e) NULL)
  if (is.null(j) || length(j) < 2) return(NA_character_)
  # j[[1]] is header row; j[[2]] is first data row: [timestamp, original]
  ts   <- j[[2]][[1]]
  orig <- j[[2]][[2]]
  sprintf("https://web.archive.org/web/%sid_/%s", ts, orig)
  # the "id_" flag returns the raw archived bytes (no Wayback banner injection)
}

#' Build candidate live-site URLs for a given YYMM.
live_urls_for <- function(yymm) {
  c(
    sprintf("https://www.njcourts.gov/sites/default/files/public/statistics/gray%s.pdf", yymm),
    sprintf("https://www.njcourts.gov/sites/default/files/gray%s.pdf", yymm)
  )
}

# --- Main loop --------------------------------------------------------------

months <- seq(START_YM, END_YM, by = "month")
yymms  <- format(months, "%y%m")

manifest <- tibble(
  yymm      = yymms,
  month     = months,
  kind      = if_else(str_sub(yymms, 3, 4) == "06", "annual_FY_or_monthly", "monthly"),
  source    = NA_character_,  # "live" | "wayback" | NA
  url_used  = NA_character_,
  dest      = NA_character_,
  bytes     = NA_integer_,
  status    = NA_character_
)

message(sprintf("Attempting %d months: %s - %s", length(yymms),
                format(min(months), "%Y-%m"), format(max(months), "%Y-%m")))

for (i in seq_along(yymms)) {
  yymm <- yymms[i]
  # Distinguish FY-annual (YY06) filename from ordinary monthly: same URL, but
  # we tag the saved file so the annual vs. monthly distinction is preserved.
  is_fy <- str_sub(yymm, 3, 4) == "06"
  fname <- if (is_fy) sprintf("gray%s_FY.pdf", yymm) else sprintf("gray%s.pdf", yymm)
  dest  <- file.path(PDF_DIR, fname)

  if (file.exists(dest) && file.info(dest)$size > 1000) {
    manifest$status[i] <- "cached"
    manifest$dest[i]   <- dest
    manifest$bytes[i]  <- file.info(dest)$size
    next
  }

  # 1) Try live njcourts.gov
  urls_live <- live_urls_for(yymm)
  res <- try_download(urls_live, dest)

  if (res$status == "ok") {
    manifest$source[i]   <- "live"
    manifest$url_used[i] <- res$url
    manifest$dest[i]     <- dest
    manifest$bytes[i]    <- res$bytes
    manifest$status[i]   <- "ok"
    message(sprintf("  [%s] live  OK  (%d bytes)  <- %s", yymm, res$bytes, res$url))
    next
  }

  # 2) Fall back to Wayback for each live URL variant
  wb_hit <- FALSE
  for (u in urls_live) {
    wb_url <- wayback_earliest(u)
    if (is.na(wb_url)) next
    res2 <- try_download(wb_url, dest)
    if (res2$status == "ok") {
      manifest$source[i]   <- "wayback"
      manifest$url_used[i] <- wb_url
      manifest$dest[i]     <- dest
      manifest$bytes[i]    <- res2$bytes
      manifest$status[i]   <- "ok"
      message(sprintf("  [%s] wayback OK  (%d bytes)", yymm, res2$bytes))
      wb_hit <- TRUE
      break
    }
  }
  if (!wb_hit) {
    manifest$status[i] <- "missing"
    message(sprintf("  [%s] MISSING (no live, no wayback)", yymm))
  }
}

# --- Write manifest ---------------------------------------------------------
manifest_path <- file.path(OUT_ROOT, "nj_gray_manifest.csv")
write_csv(manifest, manifest_path)

# --- Summary ----------------------------------------------------------------
n_ok      <- sum(manifest$status %in% c("ok", "cached"))
n_live    <- sum(manifest$source == "live",    na.rm = TRUE)
n_wayback <- sum(manifest$source == "wayback", na.rm = TRUE)
n_missing <- sum(manifest$status == "missing", na.rm = TRUE)

message("\n=== NJ gray PDF download summary ===")
message("Months attempted:  ", nrow(manifest))
message("  got PDF:         ", n_ok,
        " (live=", n_live, ", wayback=", n_wayback,
        ", cached=", sum(manifest$status == "cached", na.rm = TRUE), ")")
message("  missing:         ", n_missing)
message("Manifest: ", manifest_path)
message("PDFs in:  ", PDF_DIR)

if (n_missing > 0) {
  miss <- manifest %>% filter(status == "missing") %>% pull(yymm)
  message("Missing YYMMs: ", paste(miss, collapse = ", "))
  message("  (If many, the Wayback CDX may be rate-limiting. Re-run; cached files are skipped.)")
}
