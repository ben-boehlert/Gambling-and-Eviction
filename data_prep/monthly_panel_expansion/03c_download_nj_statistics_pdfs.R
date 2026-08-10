# ============================================================================
# 03c_download_nj_statistics_pdfs.R
#
# Purpose: Download NJ Courts monthly statistics PDFs that may contain
#          Special Civil / Tenancy filing counts.
#
# Targets:
#   - cman<YYMM>.pdf: Court Management Statistics
#       Most promising source for Special Civil / tenancy. These monthly
#       reports often include CMR2 "Statewide Incoming Filings Summary".
#   - gray<YYMM>.pdf: Civil Statistics
#       Lower-priority civil statistics reports, kept for comparison.
#
# Strategy:
#   1. Discover real PDF URLs from NJ Courts' search page.
#   2. Try those live URLs with curl forced to HTTP/1.1. NJ's CDN can return
#      false 403/404 responses to some command-line HTTP/2 clients.
#   3. Also try generated legacy URL patterns for annual / monthly reports.
#   4. If live URLs fail, ask the Wayback CDX API for the earliest archived
#      successful snapshot of that exact URL.
#   5. Download raw archived bytes with the "id_" replay flag.
#   6. Save a manifest so failed/missing months are auditable.
#
# Output:
#   data/raw/monthly_expansion/nj_raw/statistics_pdfs/<prefix><YYMM>.pdf
#   data/raw/monthly_expansion/nj_raw/nj_statistics_pdf_manifest.csv
#
# Usage from project root:
#   Rscript data_prep/monthly_panel_expansion/03c_download_nj_statistics_pdfs.R
#
# Optional environment overrides:
#   NJ_STATS_START_YM=2016-01
#   NJ_STATS_END_YM=2026-06
#   NJ_STATS_PREFIXES=cman,gray
#   NJ_STATS_SLEEP_S=1.5
#   NJ_STATS_OVERWRITE=1
#   NJ_STATS_DISCOVER=0
#   NJ_STATS_WAYBACK=0
#
# Notes:
#   - This is deliberately conservative: one request at a time, delay between
#     requests, skip already downloaded PDFs by default.
#   - If many Wayback lookups fail at once, re-run later; cached files are
#     skipped and the manifest will update.
# ============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(httr2)
  library(lubridate)
})

set.seed(20260603)

# --- Config -----------------------------------------------------------------

project_root <- tryCatch(here::here(), error = function(e) getwd())
out_root <- file.path(project_root, "data", "raw", "monthly_expansion", "nj_raw")
pdf_dir <- file.path(out_root, "statistics_pdfs")
dir.create(pdf_dir, showWarnings = FALSE, recursive = TRUE)

env_or <- function(name, default) {
  value <- Sys.getenv(name, unset = NA_character_)
  if (is.na(value) || value == "") default else value
}

start_ym <- ym(env_or("NJ_STATS_START_YM", "2016-01"))
end_ym <- ym(env_or("NJ_STATS_END_YM", format(floor_date(Sys.Date(), "month"), "%Y-%m")))

if (is.na(start_ym) || is.na(end_ym) || start_ym > end_ym) {
  stop("Invalid date range. Use NJ_STATS_START_YM and NJ_STATS_END_YM as YYYY-MM.")
}

report_prefixes <- env_or("NJ_STATS_PREFIXES", "cman,gray") |>
  str_split(",", simplify = TRUE) |>
  as.character() |>
  str_trim() |>
  discard(~ .x == "")

valid_prefixes <- c("cman", "gray")
bad_prefixes <- setdiff(report_prefixes, valid_prefixes)
if (length(bad_prefixes) > 0) {
  stop("Unsupported NJ_STATS_PREFIXES value(s): ", paste(bad_prefixes, collapse = ", "))
}

sleep_s <- as.numeric(env_or("NJ_STATS_SLEEP_S", "1.0"))
overwrite <- env_or("NJ_STATS_OVERWRITE", "0") %in% c("1", "true", "TRUE", "yes", "YES")

user_agent <- paste(
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
  "AppleWebKit/537.36 (KHTML, like Gecko)",
  "Chrome/120.0 Safari/537.36"
)
discover_from_search <- env_or("NJ_STATS_DISCOVER", "1") %in% c("1", "true", "TRUE", "yes", "YES")
search_pages <- as.integer(env_or("NJ_STATS_SEARCH_PAGES", "8"))
use_wayback <- env_or("NJ_STATS_WAYBACK", "1") %in% c("1", "true", "TRUE", "yes", "YES")

# --- Helpers ----------------------------------------------------------------

pause <- function() {
  Sys.sleep(sleep_s + runif(1, 0, 0.25))
}

is_pdf_raw <- function(body) {
  length(body) >= 1000 && identical(rawToChar(body[1:4]), "%PDF")
}

try_download <- function(urls, dest) {
  for (url in urls) {
    tmp <- tempfile(fileext = ".pdf")
    status <- tryCatch(
      system2(
        "curl",
        args = c(
          "-sS",
          "-L",
          "--http1.1",
          "--fail",
          "--max-time", "20",
          "-A", shQuote(user_agent),
          "-H", shQuote("Accept: application/pdf,*/*"),
          "-o", shQuote(tmp),
          shQuote(url)
        ),
        stdout = TRUE,
        stderr = TRUE
      ),
      warning = function(w) structure(1L, output = conditionMessage(w)),
      error = function(e) structure(1L, output = conditionMessage(e))
    )
    pause()

    exit_status <- attr(status, "status")
    if (is.null(exit_status)) {
      exit_status <- 0L
    }

    if (!identical(as.integer(exit_status), 0L)) {
      unlink(tmp)
      next
    }

    if (!file.exists(tmp)) {
      next
    }

    body <- readBin(tmp, what = "raw", n = file.info(tmp)$size)
    unlink(tmp)
    if (!is_pdf_raw(body)) {
      next
    }

    writeBin(body, dest)
    return(list(status = "ok", url = url, bytes = length(body)))
  }

  list(status = "not_found", url = NA_character_, bytes = NA_integer_)
}

wayback_earliest <- function(original_url) {
  resp <- tryCatch(
    request("https://web.archive.org/cdx/search/cdx") |>
      req_url_query(
        url = original_url,
        output = "json",
        limit = "1",
        filter = "statuscode:200",
        fl = "timestamp,original",
        collapse = "digest"
      ) |>
      req_user_agent(user_agent) |>
      req_timeout(45) |>
      req_error(is_error = function(resp) FALSE) |>
      req_perform(),
    error = function(e) NULL
  )
  pause()

  if (is.null(resp) || resp_status(resp) != 200) {
    return(NA_character_)
  }

  payload <- tryCatch(resp_body_json(resp), error = function(e) NULL)
  if (is.null(payload) || length(payload) < 2) {
    return(NA_character_)
  }

  timestamp <- payload[[2]][[1]]
  original <- payload[[2]][[2]]
  sprintf("https://web.archive.org/web/%sid_/%s", timestamp, original)
}

live_urls_for <- function(prefix, yymm) {
  c(
    sprintf("https://www.njcourts.gov/sites/default/files/public/statistics/%s%s.pdf", prefix, yymm),
    sprintf("https://www.njcourts.gov/sites/default/files/public/%s%s.pdf", prefix, yymm),
    sprintf("https://www.njcourts.gov/sites/default/files/%s%s.pdf", prefix, yymm)
  )
}

download_one <- function(prefix, yymm, month_date, discovered_urls = character()) {
  filename <- sprintf("%s%s.pdf", prefix, yymm)
  dest <- file.path(pdf_dir, filename)

  if (!overwrite && file.exists(dest) && file.info(dest)$size > 1000) {
    return(tibble(
      prefix = prefix,
      yymm = yymm,
      month = month_date,
      source = "cached",
      url_used = NA_character_,
      dest = dest,
      bytes = as.integer(file.info(dest)$size),
      status = "cached"
    ))
  }

  live_urls <- unique(c(discovered_urls, live_urls_for(prefix, yymm)))
  live_result <- try_download(live_urls, dest)

  if (live_result$status == "ok") {
    return(tibble(
      prefix = prefix,
      yymm = yymm,
      month = month_date,
      source = "live",
      url_used = live_result$url,
      dest = dest,
      bytes = as.integer(live_result$bytes),
      status = "ok"
    ))
  }

  if (use_wayback) {
    for (live_url in live_urls) {
      replay_url <- wayback_earliest(live_url)
      if (is.na(replay_url)) {
        next
      }

      archived_result <- try_download(replay_url, dest)
      if (archived_result$status == "ok") {
        return(tibble(
          prefix = prefix,
          yymm = yymm,
          month = month_date,
          source = "wayback",
          url_used = replay_url,
          dest = dest,
          bytes = as.integer(archived_result$bytes),
          status = "ok"
        ))
      }
    }
  }

  tibble(
    prefix = prefix,
    yymm = yymm,
    month = month_date,
    source = NA_character_,
    url_used = NA_character_,
    dest = dest,
    bytes = NA_integer_,
    status = "missing"
  )
}

fetch_search_page <- function(query, page) {
  resp <- tryCatch(
    request("https://www.njcourts.gov/search") |>
      req_url_query(search = query, page = page) |>
      req_user_agent(user_agent) |>
      req_timeout(45) |>
      req_error(is_error = function(resp) FALSE) |>
      req_perform(),
    error = function(e) NULL
  )
  pause()

  if (is.null(resp) || resp_status(resp) != 200) {
    return(character())
  }

  resp_body_string(resp)
}

extract_pdf_links <- function(html) {
  empty_links <- tibble(
    url = character(),
    file = character(),
    prefix = character(),
    yymm = character(),
    month = as.Date(character())
  )

  if (length(html) == 0 || is.na(html) || html == "") {
    return(empty_links)
  }

  hrefs <- str_extract_all(html, "href=\"[^\"]+\"")[[1]] |>
    str_remove("^href=\"") |>
    str_remove("\"$") |>
    str_replace_all("&amp;", "&")

  hrefs <- hrefs[str_detect(hrefs, regex("/(?:cman|gray)[0-9]{4}\\.pdf$", ignore_case = TRUE))]
  if (length(hrefs) == 0) {
    return(empty_links)
  }

  urls <- if_else(
    str_starts(hrefs, "https?://"),
    hrefs,
    paste0("https://www.njcourts.gov", hrefs)
  )

  tibble(url = urls) |>
    mutate(
      file = basename(url),
      prefix = str_to_lower(str_extract(file, "^[A-Za-z]+")),
      yymm = str_extract(file, "[0-9]{4}"),
      month = ym(paste0("20", str_sub(yymm, 1, 2), "-", str_sub(yymm, 3, 4)))
    ) |>
    filter(prefix %in% valid_prefixes, !is.na(month)) |>
    distinct(prefix, yymm, url, .keep_all = TRUE)
}

discover_pdf_links <- function() {
  if (!discover_from_search) {
    return(tibble(prefix = character(), yymm = character(), month = as.Date(character()), url = character()))
  }

  queries <- c(
    cman = "Court Management Statistics",
    gray = "Civil Statistics"
  )

  discovered <- list()
  idx <- 1L
  for (prefix in intersect(names(queries), report_prefixes)) {
    for (page in seq.int(0L, max(search_pages - 1L, 0L))) {
      html <- fetch_search_page(queries[[prefix]], page)
      links <- extract_pdf_links(html) |>
        filter(.data$prefix == .env$prefix)

      if (nrow(links) > 0) {
        discovered[[idx]] <- links
        idx <- idx + 1L
      }
    }
  }

  if (length(discovered) == 0) {
    return(tibble(prefix = character(), yymm = character(), month = as.Date(character()), url = character()))
  }

  bind_rows(discovered) |>
    distinct(prefix, yymm, url, .keep_all = TRUE)
}

# --- Main -------------------------------------------------------------------

months <- seq(start_ym, end_ym, by = "month")
generated_targets <- tidyr::crossing(
  prefix = report_prefixes,
  month = months
) |>
  mutate(yymm = format(month, "%y%m")) |>
  arrange(prefix, month)

discovered_targets <- discover_pdf_links()
if (nrow(discovered_targets) > 0) {
  discovered_targets <- discovered_targets |>
    filter(month >= start_ym, month <= end_ym)
}

targets <- generated_targets |>
  left_join(
    discovered_targets |>
      group_by(prefix, yymm, month) |>
      summarise(discovered_urls = list(url), .groups = "drop"),
    by = c("prefix", "yymm", "month")
  ) |>
  mutate(
    discovered_urls = map(discovered_urls, \(x) {
      if (is.null(x) || length(x) == 0 || all(is.na(x))) character() else unlist(x)
    })
  ) |>
  arrange(prefix, month)

message("Attempting NJ statistics PDFs")
message("  prefixes: ", paste(report_prefixes, collapse = ", "))
message("  range:    ", format(min(months), "%Y-%m"), " to ", format(max(months), "%Y-%m"))
message("  targets:  ", nrow(targets))
message("  discovered links: ", nrow(discovered_targets))
message("  wayback fallback: ", use_wayback)
message("  output:   ", pdf_dir)

manifest <- vector("list", nrow(targets))
for (i in seq_len(nrow(targets))) {
  target <- targets[i, ]
  label <- sprintf("%s%s", target$prefix, target$yymm)
  message(sprintf("  [%03d/%03d] %s", i, nrow(targets), label))

  manifest[[i]] <- download_one(
    prefix = target$prefix,
    yymm = target$yymm,
    month_date = target$month,
    discovered_urls = target$discovered_urls[[1]]
  )

  latest <- manifest[[i]]
  if (latest$status %in% c("ok", "cached")) {
    message(sprintf(
      "           %s (%s, %s bytes)",
      latest$status,
      latest$source,
      format(latest$bytes, big.mark = ",", scientific = FALSE)
    ))
  } else {
    message("           missing")
  }
}

manifest <- bind_rows(manifest)
manifest_path <- file.path(out_root, "nj_statistics_pdf_manifest.csv")
write_csv(manifest, manifest_path)

summary_tbl <- manifest |>
  count(prefix, status, source, name = "n") |>
  arrange(prefix, status, source)

message("\n=== NJ statistics PDF download summary ===")
print(summary_tbl, n = Inf)
message("Manifest: ", manifest_path)
message("PDFs in:  ", pdf_dir)

missing <- manifest |>
  filter(status == "missing") |>
  transmute(target = paste0(prefix, yymm)) |>
  pull(target)

if (length(missing) > 0) {
  message("Missing targets: ", paste(missing, collapse = ", "))
  message("If many are missing, Wayback may be rate-limiting. Re-run later; cached PDFs are skipped.")
}
