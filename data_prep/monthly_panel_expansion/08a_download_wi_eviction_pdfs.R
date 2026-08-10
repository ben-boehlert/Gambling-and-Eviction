# ============================================================================
# 08a_download_wi_eviction_pdfs.R
#
# Purpose: Download Wisconsin's county-level eviction PDFs from the DOA
#          "Wisconsin Eviction Data Project" page. Two report kinds per year:
#            - MONTHLY   : county x (12 months x {Filed, Judgement}) wide matrix
#            - FULL_YEAR : county annual Filings / Judgements / population
#          Coverage 2019-2025. The two kinds are published independently, which
#          08b uses as an external reconciliation check.
#
# Source page (authoritative link list, scoped 2026-07-23):
#   https://doa.wi.gov/Pages/Wisconsin-Eviction-Data-Project.aspx
#
# Data provenance (from the page's methodology note): DOA pulls the counts from
# the Wisconsin Circuit Court Access (WCCA) REST service, i.e. the Consolidated
# Court Automation Programs (CCAP) circuit-court records. Complaint-stage
# "Filed" counts are comparable to the ETS/LSC filings margin used elsewhere in
# the panel; "Judgement" is a downstream margin kept only as a secondary series.
#
# The DOA filenames are irregular (no clean pattern), so the exact basename and
# URL for each (year, kind) are listed explicitly below. One page-level typo is
# corrected: the 2023 "full year" link points at the 2023 monthly file; the real
# 2023 full-year document is "2023 Full Year UPDATED.pdf" (verified 200, 2026-07-23).
#
# Strategy (mirrors 01b_download_md_statistics_pdfs.R):
#   1. Deterministic (year, kind) -> URL table.
#   2. curl over HTTP/1.1, verify "%PDF" magic bytes, skip cached files.
#   3. Wayback CDX fallback (earliest 200 snapshot, id_ raw replay) if a live
#      URL fails.
#   4. Write an auditable manifest.
#
# Output:
#   data/raw/monthly_expansion/wi_raw/pdfs/<basename>.pdf
#   data/raw/monthly_expansion/wi_raw/wi_eviction_pdf_manifest.csv
#
# Usage from project root:
#   Rscript data_prep/monthly_panel_expansion/08a_download_wi_eviction_pdfs.R
#
# Optional environment overrides:
#   WI_PDF_SLEEP_S=1.0
#   WI_PDF_OVERWRITE=1
#   WI_PDF_WAYBACK=0
# ============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(httr2)
})

set.seed(20260723)

# --- Config -----------------------------------------------------------------

project_root <- tryCatch(here::here(), error = function(e) getwd())
out_root <- file.path(project_root, "data", "raw", "monthly_expansion", "wi_raw")
pdf_dir <- file.path(out_root, "pdfs")
dir.create(pdf_dir, showWarnings = FALSE, recursive = TRUE)

env_or <- function(name, default) {
  value <- Sys.getenv(name, unset = NA_character_)
  if (is.na(value) || value == "") default else value
}

sleep_s <- as.numeric(env_or("WI_PDF_SLEEP_S", "1.0"))
overwrite <- env_or("WI_PDF_OVERWRITE", "0") %in% c("1", "true", "TRUE", "yes", "YES")
use_wayback <- env_or("WI_PDF_WAYBACK", "1") %in% c("1", "true", "TRUE", "yes", "YES")

user_agent <- paste(
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
  "AppleWebKit/537.36 (KHTML, like Gecko)",
  "Chrome/120.0 Safari/537.36"
)

base_url <- "https://doa.wi.gov/Documents/"

# (year, kind, local basename, source URL). URL fragments are pre-encoded.
WI_SOURCES <- tribble(
  ~year, ~kind,        ~file,                          ~url_frag,
  2019L, "monthly",    "2019-monthly.pdf",             "2019-monthly.pdf",
  2019L, "full_year",  "2019-full-year.pdf",           "2019-full-year.pdf",
  2020L, "monthly",    "2020-monthly.pdf",             "2020-monthly.pdf",
  2020L, "full_year",  "2020-full-year.pdf",           "2020-full-year.pdf",
  2021L, "monthly",    "2021-monthly-FINAL.pdf",       "2021-monthly-FINAL.pdf",
  2021L, "full_year",  "2021-full-year-FINAL.pdf",     "2021-full-year-FINAL.pdf",
  2022L, "monthly",    "2022-monthly-January23.pdf",   "2022-monthly-January23.pdf",
  2022L, "full_year",  "2022-full-year-Jan23.pdf",     "2022-full-year-Jan23.pdf",
  2023L, "monthly",    "2023-Monthly-UPDATED.pdf",     "2023%20Monthly%20UPDATED.pdf",
  # Page typo corrected: DOA's 2023 "full year" link points at the monthly file.
  2023L, "full_year",  "2023-Full-Year-UPDATED.pdf",   "2023%20Full%20Year%20UPDATED.pdf",
  2024L, "monthly",    "2024-monthly-december.pdf",    "2024-monthly-december.pdf",
  2024L, "full_year",  "2024-full-year-december.pdf",  "2024-full-year-december.pdf",
  2025L, "monthly",    "2025-monthly-july.pdf",        "2025-monthly-july.pdf",
  2025L, "full_year",  "2025-full-year-july.pdf",      "2025-full-year-july.pdf"
) |>
  mutate(url = paste0(base_url, url_frag))

# --- Helpers ----------------------------------------------------------------

pause <- function() Sys.sleep(sleep_s + runif(1, 0, 0.25))

is_pdf_raw <- function(body) {
  length(body) >= 1000 && identical(rawToChar(body[1:4]), "%PDF")
}

try_download <- function(url, dest) {
  tmp <- tempfile(fileext = ".pdf")
  status <- tryCatch(
    system2(
      "curl",
      args = c(
        "-sS", "-L", "--http1.1", "--fail", "--max-time", "60",
        "-A", shQuote(user_agent),
        "-H", shQuote("Accept: application/pdf,*/*"),
        "-o", shQuote(tmp), shQuote(url)
      ),
      stdout = TRUE, stderr = TRUE
    ),
    warning = function(w) structure(1L, output = conditionMessage(w)),
    error = function(e) structure(1L, output = conditionMessage(e))
  )
  pause()

  exit_status <- attr(status, "status")
  if (is.null(exit_status)) exit_status <- 0L
  if (!identical(as.integer(exit_status), 0L) || !file.exists(tmp)) {
    unlink(tmp)
    return(list(ok = FALSE, bytes = NA_integer_))
  }
  body <- readBin(tmp, what = "raw", n = file.info(tmp)$size)
  unlink(tmp)
  if (!is_pdf_raw(body)) return(list(ok = FALSE, bytes = NA_integer_))
  writeBin(body, dest)
  list(ok = TRUE, bytes = length(body))
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
  sprintf("https://web.archive.org/web/%sid_/%s", payload[[2]][[1]], payload[[2]][[2]])
}

download_one <- function(year, kind, file, url) {
  dest <- file.path(pdf_dir, file)
  if (!overwrite && file.exists(dest) && file.info(dest)$size > 1000) {
    return(tibble(
      year = year, kind = kind, file = file, source = "cached",
      url_used = NA_character_, size = as.integer(file.info(dest)$size),
      status = "cached"
    ))
  }
  live <- try_download(url, dest)
  if (live$ok) {
    return(tibble(
      year = year, kind = kind, file = file, source = "live",
      url_used = url, size = as.integer(live$bytes), status = "ok"
    ))
  }
  if (use_wayback) {
    replay <- wayback_earliest(url)
    if (!is.na(replay)) {
      arch <- try_download(replay, dest)
      if (arch$ok) {
        return(tibble(
          year = year, kind = kind, file = file, source = "wayback",
          url_used = replay, size = as.integer(arch$bytes), status = "ok"
        ))
      }
    }
  }
  tibble(
    year = year, kind = kind, file = file, source = NA_character_,
    url_used = NA_character_, size = NA_integer_, status = "missing"
  )
}

# --- Main -------------------------------------------------------------------

message("Downloading Wisconsin DOA eviction PDFs")
message("  wayback:  ", use_wayback)
message("  output:   ", pdf_dir)

manifest <- pmap_dfr(
  list(WI_SOURCES$year, WI_SOURCES$kind, WI_SOURCES$file, WI_SOURCES$url),
  function(year, kind, file, url) {
    message(sprintf("  %d %-9s (%s)", year, kind, file))
    res <- download_one(year, kind, file, url)
    msg <- if (res$status %in% c("ok", "cached")) {
      sprintf("           %s (%s, %s bytes)", res$status, res$source,
              format(res$size, big.mark = ",", scientific = FALSE))
    } else {
      "           MISSING"
    }
    message(msg)
    res
  }
)

manifest_path <- file.path(out_root, "wi_eviction_pdf_manifest.csv")
write_csv(manifest, manifest_path)

message("\n=== WI eviction PDF download summary ===")
print(count(manifest, kind, status, source, name = "n"), n = Inf)
message("Manifest: ", manifest_path)

missing <- manifest |> filter(status == "missing")
if (nrow(missing) > 0) {
  message("MISSING: ", paste(missing$file, collapse = ", "))
  message("Re-run later; cached PDFs are skipped. Wayback may be rate-limiting.")
}
