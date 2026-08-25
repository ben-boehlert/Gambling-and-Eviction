# Download the NC AOC "Civil Issue Filings/Order Results" workbooks, one per
# fiscal year. These are the source behind ETS's North Carolina series: summing
# Issue_Code == "SUME" (Summary Ejectment) across case types reproduces the ETS
# NC county-month counts at corr 1.0000 (median monthly ratio 1.0000) over the
# 90 overlapping months 2016-01..2023-06.
#
# Why we need them: the ETS county download stops at 2023-06 for NC, which is
# BEFORE NC's online sports betting start (2024-03-11). NC therefore contributes
# zero treated observations, and under the fixed-basket rule it drops out of the
# rebuilt state panel entirely. These workbooks carry NC through 2026-06.
#
# Publication page (source of the URLs below; VersionId query strings are stable
# S3 object versions and change only when NCAOC republishes a year):
#   https://www.nccourts.gov/documents/publications/civil-issue-filingsorder-results
#
# Note: nccourts.gov returns 403 to a default user agent, so we set a browser UA.
#
# Output: data/raw/monthly_expansion/nc_aoc/fyYY-YY.xlsx  (~60 MB total)
# Skips any file already present, so re-running is cheap.
#
# Usage: Rscript data_prep/monthly_panel_expansion/09a_download_nc_aoc_civil_issue_reports.R

suppressMessages({ library(tidyverse); library(glue); library(curl) })

OUT_DIR <- "data/raw/monthly_expansion/nc_aoc"
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

BASE <- "https://www.nccourts.gov/assets/documents/publications/"
UA   <- paste("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
              "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15")

reports <- tribble(
  ~fy,        ~file,
  "fy15-16",  "vcap_issue_filings_order_results_fy15-16.xlsx?VersionId=VbjZlqqGc0Coy1z9UDa_DbqO4Ko8Ykux",
  "fy16-17",  "vcap_issue_filings_order_results_fy16-17.xlsx?VersionId=NgnMyYJnPSEtUWmE5.2etPmE48C0JapS",
  "fy17-18",  "vcap_issue_filings_order_results_fy17-18.xlsx?VersionId=Ldp2bq9wOr0FgGi8QcO8v56G5OlHaMKY",
  "fy18-19",  "vcap_issue_filings_order_results_fy18-19.xlsx?VersionId=I78.bN1pliHiGiGoWY_FiVmJ_CJRV3.x",
  "fy19-20",  "vcap_issue_filings_order_results_fy19-20.xlsx?VersionId=Ig9iPSASTukSnlmTFWmdtfFSxqM4Mmnq",
  "fy20-21",  "vcap_issue_filings_order_results_fy20-21.xlsx?VersionId=WylMPal_RKIB.dJWwVj9C8PW2ni.mAdc",
  "fy21-22",  "vcap_issue_filings_order_results_fy21-22.xlsx?VersionId=MCFj58urHVly8Nea9a0cVEI_YNNfd6wD",
  "fy22-23",  "vcap_issue_filings_order_results_fy22-23_0.xlsx?VersionId=KeWdrdYsXGqEJkhjwdes3vvxvwweEHSh",
  "fy23-24",  "vcap_issue_filings_order_results_fy23-24.xlsx?VersionId=JQFMavxZds.ElmbZokyHIRzmI5UnE4uV",
  "fy24-25",  "vcap_issue_filings_order_results_fy24-25_0.xlsx?VersionId=BdjQMSANSFahxhtFfv8aitJKP5hL3iWL",
  "fy25-26",  "vcap_issue_filings_order_results_fy25-26.xlsx?VersionId=ECyNSUpQuDwSu2JeptNrhWTRFdfbn6sK"
)

h <- new_handle()
handle_setheaders(h, "User-Agent" = UA)

for (i in seq_len(nrow(reports))) {
  dest <- file.path(OUT_DIR, glue("{reports$fy[i]}.xlsx"))
  if (file.exists(dest) && file.size(dest) > 1e6) {
    message(glue("skip {reports$fy[i]} (already present)")); next
  }
  url <- paste0(BASE, reports$file[i])
  message(glue("downloading {reports$fy[i]} ..."))
  curl_download(url, dest, handle = h)
  message(glue("  {reports$fy[i]}: {round(file.size(dest)/1e6, 1)} MB"))
}

message("\nDone. Workbooks in ", OUT_DIR)
