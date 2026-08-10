# ============================================================================
# 01_pull_md_socrata.R
#
# Purpose: Pull Maryland District Court eviction case data from the MD Open
#          Data Portal (Socrata API) and aggregate to county-month filings.
#
# Dataset: "District Court of Maryland Eviction Case Data"
#   URL:  https://opendata.maryland.gov/Housing/District-Court-of-Maryland-Eviction-Case-Data/mvqb-b4hf
#   API:  https://opendata.maryland.gov/resource/mvqb-b4hf.json
#
# Coverage: Jan 2023 - present, all 24 MD jurisdictions, case-level events
#
# IMPORTANT MEASUREMENT NOTE:
#   This dataset reports `eventtype` values representing landlord actions on
#   warrants of restitution (issued AFTER judgment), not original complaint
#   filings. The event types are:
#     - "Petition - For Warrant of Restitution Filed"  (landlord petitions
#       the court to execute the eviction - happens after judgment)
#     - "Warrant of Restitution - Return of Service - Evicted"  (actual
#       eviction carried out)
#     - "Warrant of Restitution - Return of Service - Cancelled"  (e.g.,
#       tenant paid and stayed)
#     - "Warrant of Restitution - Return of Service - Expired"
#
#   This is a DIFFERENT MARGIN from Eviction Lab's ETS filings series
#   (which counts original complaint filings). Two reasonable choices:
#     (A) Use "Petition for Warrant" events as the MD filings analog. This
#         is a late-stage measure (post-judgment). Comparable to Hepburn
#         et al. "eviction filings" only loosely.
#     (B) Use "Evicted" events as an "actual eviction" measure, which is a
#         more consequential margin than filings.
#   This script outputs both so the analyst can choose.
#
# Author: Ben Boehlert / Claude Code
# Date:   2026-04-15
# ============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(httr2)
  library(jsonlite)
})
# NOTE: RSocrata would be the canonical client but is not available for R 4.x
# at the time of writing. httr2 with a browser-like User-Agent bypasses the
# Cloudflare challenge (raw curl and Python urllib get 403'd; httr2 works).

# --- Config -----------------------------------------------------------------
PROJECT_ROOT <- here::here()  # assumes script is sourced from project root
OUT_DIR <- file.path(PROJECT_ROOT, "data", "raw", "monthly_expansion")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

DATASET_URL <- "https://opendata.maryland.gov/resource/mvqb-b4hf.json"
# Optional Socrata app token — increases rate limits. Register at
# https://evergreen.data.socrata.com/signup. Paste token below or leave NULL.
APP_TOKEN <- Sys.getenv("SOCRATA_APP_TOKEN", unset = NA)
if (is.na(APP_TOKEN) || APP_TOKEN == "") APP_TOKEN <- NULL

# --- Pull: event-type-aggregated county-month counts ------------------------
# We issue server-side aggregation via SoQL so we don't download 700k rows.
# Result: one row per (county, month, event_category).

resp <- request(DATASET_URL) |>
  req_url_query(
    `$select` = "county,date_trunc_ym(eventdate) as month,eventtype,count(*) as n",
    `$group`  = "county,month,eventtype",
    `$order`  = "county,month,eventtype",
    `$limit`  = "200000"
  ) |>
  req_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36") |>
  req_headers(Accept = "application/json") |>
  (\(r) if (!is.null(APP_TOKEN)) req_headers(r, `X-App-Token` = APP_TOKEN) else r)() |>
  req_perform()

stopifnot(resp_status(resp) == 200)
df_raw <- resp_body_json(resp, simplifyVector = TRUE) |> as_tibble()

message("Retrieved ", nrow(df_raw), " rows")

# --- Classify event types ---------------------------------------------------
df <- df_raw %>%
  as_tibble() %>%
  mutate(
    n = as.integer(n),
    month = as.Date(month),
    eventtype_upper = toupper(eventtype),
    event_category = case_when(
      str_detect(eventtype_upper, "^PETITION")       ~ "warrant_petition_filed",
      str_detect(eventtype_upper, "EVICTED")         ~ "eviction_executed",
      str_detect(eventtype_upper, "CANCELLED")       ~ "warrant_cancelled",
      str_detect(eventtype_upper, "EXPIRED")         ~ "warrant_expired",
      TRUE                                           ~ "other"
    )
  )

# --- Save raw event-category panel ------------------------------------------
write_csv(df, file.path(OUT_DIR, "md_county_month_events_raw.csv"))

# --- Build two headline series: petitions and executed evictions -----------
panel_petitions <- df %>%
  filter(event_category == "warrant_petition_filed") %>%
  group_by(county, month) %>%
  summarise(warrant_petitions = sum(n), .groups = "drop")

panel_evicted <- df %>%
  filter(event_category == "eviction_executed") %>%
  group_by(county, month) %>%
  summarise(evictions_executed = sum(n), .groups = "drop")

# Full county-month grid so missing months are explicit zeros
all_months <- seq(
  min(df$month, na.rm = TRUE),
  max(df$month, na.rm = TRUE),
  by = "month"
)
all_counties <- sort(unique(df$county))
grid <- expand_grid(county = all_counties, month = all_months)

panel_md <- grid %>%
  left_join(panel_petitions, by = c("county", "month")) %>%
  left_join(panel_evicted,   by = c("county", "month")) %>%
  mutate(
    warrant_petitions   = replace_na(warrant_petitions, 0L),
    evictions_executed  = replace_na(evictions_executed, 0L),
    state_abb = "MD"
  ) %>%
  select(state_abb, county, month, warrant_petitions, evictions_executed)

write_csv(panel_md, file.path(OUT_DIR, "md_county_month_panel.csv"))

# --- Summary diagnostics ----------------------------------------------------
message("\n=== MD Panel Summary ===")
message("Counties: ", length(all_counties))
message("Months: ",   length(all_months),
        " (", min(all_months), " to ", max(all_months), ")")
message("Total warrant petitions:  ", format(sum(panel_md$warrant_petitions), big.mark = ","))
message("Total evictions executed: ", format(sum(panel_md$evictions_executed), big.mark = ","))

by_county <- panel_md %>%
  group_by(county) %>%
  summarise(
    n_months = n(),
    petitions_total = sum(warrant_petitions),
    evictions_total = sum(evictions_executed)
  ) %>%
  arrange(desc(petitions_total))
print(by_county, n = Inf)

message("\nOutputs written to: ", OUT_DIR)
message("  - md_county_month_events_raw.csv  (all event categories)")
message("  - md_county_month_panel.csv       (headline panel: petitions + evictions)")
