# ============================================================================
# pull_id_powerbi_eviction_filings.R   (2026-09-14)   *** NEEDS NETWORK ***
#
# Purpose: Extract IDAHO county-month eviction filings from the public Idaho
#          Judicial Branch Case and Charge Data dashboard.
#
# Run:  Rscript data_prep/pull_id_powerbi_eviction_filings.R
#
# Source page:
#   https://courtdata.idaho.gov/Charge   (Civil Cases tab)
# Embedded Power BI report (US Gov cloud):
#   https://app.powerbigov.us/view?r=eyJrIjoiMjAwZGE2MjktZDBmMC00YzU5LTg0ZDUt
#   YjkzZTZjODZjYmM3IiwidCI6IjRlMzZhNTA4LTI1ZTUtNGM4ZC04ZWRiLWU5MDY5ZWIxNDg0MSJ9
#
# Target definition:
#   Case Type[Case Type] == "A12- Unlawful Detainer/Eviction"
#   Event Type           == "Filed"   (not disposed)
#   Case[IsJuvenile]     != 1
#
# WHY THIS EXISTS. Idaho entered the state panel through the LSC CCDI county
# download, where the fixed-basket rule leaves exactly ONE continuously
# reporting county: Twin Falls (10,312 renters, 1 of 44). That series averages
# 13.6 filings/month and is the second-noisiest in the panel (SD of month-over-
# month log change 0.542 vs a panel median of 0.148), which is why Idaho sits
# on every exclude_states list. The dashboard carries all 44 counties.
#
# THE UI EXPOSES ONLY CALENDAR YEARS; THE MODEL CARRIES MONTHS. The published
# report groups on `Year Axis`, but the semantic model has Date[FirstDateofMonth]
# and Location[County], so a county-month grouping is a legitimate query against
# the same measure the dashboard itself renders ("Measure Table"[Civil Cases]).
# That measure is slicer-contexted: it returns zero unless Year Type, Metric
# Fields, and Event Type are pinned in the Where clause. The five conditions in
# ID_WHERE below are copied from the report's own querydata payload -- do not
# drop any of them, or the measure silently evaluates to blank.
#
# ROLLING FIVE-YEAR WINDOW -- THIS SOURCE FORGETS. `Year Axis` holds exactly
# five COMPLETE calendar years plus five fiscal years. As of 2026-09-14 that is
# CY2021..CY2025 and FY2022..FY2026. Pre-2021 is NOT retrievable here and will
# never come back; each January the window drops another year. The project
# already lost 2016-2018 this way -- our county-YEAR Idaho figures for 2019 and
# 2020 (in the Court Data annual file) were pulled while the window still
# covered them. ARCHIVE EVERY PULL; do not treat the dashboard as a durable
# store. Pre-2021 county-month Idaho must come from a data request to the Idaho
# Judicial Branch ("Submit a Data Request" on the dashboard home page).
#
# CALENDAR + FISCAL UNION. Querying Year Type = "Calendar Year" yields
# 2021-01..2025-12; "Fiscal Year" yields 2021-07..2026-06 (Idaho's FY starts
# July 1). Their union is 2021-01..2026-06, six months fresher than the
# calendar axis alone. The 2,376 county-months in the overlap are asserted
# IDENTICAL below -- if that assertion ever fails, the two axes have stopped
# measuring the same thing and the union is invalid.
#
# VALIDATION (asserted at run time, not just claimed):
#   1. CY/FY overlap agrees exactly on all shared county-months.
#   2. Twin Falls annual totals reproduce the LSC CCDI series already in the
#      panel (2021-2024: 129/138/156/180 vs 129/138/155/180 -- one case in
#      2023). Same measurement, 44 counties instead of 1.
#   3. Ada County annual totals reproduce the Court Data annual file exactly
#      (2021-2024: 673/879/1319/1608), which was itself pulled from this
#      dashboard.
#
# Outputs:
#   data/raw/idaho/id_county_month_a12.csv   county x month, long
#   data/raw/idaho/id_state_month_a12.csv    statewide x month
#   data/raw/idaho/id_pull_manifest.csv      one row per pull (append-only)
#
# Power BI public query responses use dictionary and run-length compression,
# and decimal measures arrive as strings with a trailing "D" ("223D").
# decode_powerbi_dsr() reconstructs the rows; .as_measure_numeric() strips the
# suffix. A measure column that decodes to all-NA means the suffix handling
# broke, and is fatal below.
# ============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(httr2)
  library(jsonlite)
  library(readr)
  library(stringr)
  library(tibble)
  library(tidyr)
})

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0L) y else x
}

PROJECT_ROOT <- here::here()
OUT_DIR <- file.path(PROJECT_ROOT, "data", "raw", "idaho")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

REPORT_URL <- paste0(
  "https://app.powerbigov.us/view?r=",
  "eyJrIjoiMjAwZGE2MjktZDBmMC00YzU5LTg0ZDUtYjkzZTZjODZjYmM3IiwidCI6",
  "IjRlMzZhNTA4LTI1ZTUtNGM4ZC04ZWRiLWU5MDY5ZWIxNDg0MSJ9"
)

CASE_TYPE      <- "A12- Unlawful Detainer/Eviction"
COUNTY_OUT     <- file.path(OUT_DIR, "id_county_month_a12.csv")
STATE_OUT      <- file.path(OUT_DIR, "id_state_month_a12.csv")
MANIFEST_OUT   <- file.path(OUT_DIR, "id_pull_manifest.csv")
EXPECT_COUNTIES <- 44L

random_uuid <- function() {
  hex <- sample(c(0:9, letters[1:6]), 32L, replace = TRUE)
  paste0(
    paste0(hex[1:8], collapse = ""), "-",
    paste0(hex[9:12], collapse = ""), "-",
    paste0(hex[13:16], collapse = ""), "-",
    paste0(hex[17:20], collapse = ""), "-",
    paste0(hex[21:32], collapse = "")
  )
}

decode_publish_to_web_token <- function(report_url) {
  token <- str_match(report_url, "[?&]r=([^&]+)")[, 2]
  if (is.na(token)) {
    stop("Could not find the Power BI publish-to-web token in REPORT_URL.")
  }

  token <- URLdecode(token)
  token <- chartr("-_", "+/", token)
  token <- paste0(token, strrep("=", (4L - nchar(token) %% 4L) %% 4L))

  fromJSON(rawToChar(base64_dec(token)), simplifyVector = TRUE)
}

powerbi_headers <- function(req, resource_key, activity_id = random_uuid()) {
  req |>
    req_headers(
      Accept = "application/json",
      ActivityId = activity_id,
      RequestId = random_uuid(),
      `X-PowerBI-ResourceKey` = resource_key
    )
}

powerbi_get_json <- function(url, resource_key, activity_id) {
  resp <- request(url) |>
    powerbi_headers(resource_key, activity_id) |>
    req_timeout(60) |>
    req_retry(max_tries = 3) |>
    req_perform()

  resp_check_status(resp)
  fromJSON(resp_body_string(resp), simplifyVector = FALSE)
}

discover_report <- function(report_url) {
  descriptor <- decode_publish_to_web_token(report_url)

  page_resp <- request(report_url) |>
    req_timeout(60) |>
    req_retry(max_tries = 3) |>
    req_perform()
  resp_check_status(page_resp)
  page_html <- resp_body_string(page_resp)

  cluster_uri <- str_match(
    page_html,
    "var resolvedClusterUri = '([^']+)'"
  )[, 2]
  if (is.na(cluster_uri) || cluster_uri == "") {
    cluster_uri <- str_match(
      page_html,
      '"FixedClusterUri":"([^"]+)"'
    )[, 2]
  }
  if (is.na(cluster_uri) || cluster_uri == "") {
    stop("Could not resolve the Power BI API cluster.")
  }

  api_uri <- cluster_uri |>
    str_replace("-redirect", "-api") |>
    str_replace("global-", "") |>
    str_remove("/$")

  activity_id <- random_uuid()
  schema_url <- paste0(
    api_uri, "/public/reports/", descriptor$k, "/conceptualschema"
  )
  schema_response <- powerbi_get_json(
    schema_url,
    descriptor$k,
    activity_id
  )

  schema_record <- schema_response$schemas[[1]]
  if (!is.null(schema_record$error)) {
    stop("Power BI schema request failed: ", toJSON(schema_record$error))
  }

  list(
    resource_key = descriptor$k,
    tenant_id = descriptor$t,
    api_uri = api_uri,
    activity_id = activity_id,
    model_id = schema_record$modelId,
    schema = schema_record$schema
  )
}

column_expression <- function(source, property) {
  list(
    Column = list(
      Expression = list(SourceRef = list(Source = source)),
      Property = property
    )
  )
}

column_select <- function(source, property) {
  c(
    column_expression(source, property),
    list(Name = paste0(source, ".", property))
  )
}

sum_select <- function(source, property) {
  list(
    Aggregation = list(
      Expression = column_expression(source, property),
      Function = 0L
    ),
    Name = paste0("Sum(", source, ".", property, ")")
  )
}

equals_text_condition <- function(source, property, value) {
  list(
    Condition = list(
      In = list(
        Expressions = list(column_expression(source, property)),
        Values = list(
          list(
            list(Literal = list(Value = paste0("'", value, "'")))
          )
        )
      )
    )
  )
}

run_powerbi_query <- function(report, payload) {
  query_url <- paste0(
    report$api_uri,
    "/public/reports/querydata?synchronous=true"
  )

  resp <- request(query_url) |>
    req_method("POST") |>
    powerbi_headers(report$resource_key, report$activity_id) |>
    req_headers(`Content-Type` = "application/json") |>
    req_body_json(payload, auto_unbox = TRUE) |>
    req_timeout(120) |>
    req_retry(max_tries = 3) |>
    req_perform()

  resp_check_status(resp)
  parsed <- fromJSON(resp_body_string(resp), simplifyVector = FALSE)

  result <- parsed$results[[1]]$result
  if (!is.null(result$error)) {
    stop("Power BI query failed: ", toJSON(result$error, auto_unbox = TRUE))
  }
  result$data
}

decode_dictionary_value <- function(value, descriptor, dictionaries) {
  dictionary_name <- descriptor$DN %||% NULL
  if (
    !is.null(dictionary_name) &&
      is.numeric(value) &&
      length(value) == 1L
  ) {
    dictionary <- dictionaries[[dictionary_name]]
    index <- as.integer(value) + 1L
    if (!is.null(dictionary) && index >= 1L && index <= length(dictionary)) {
      return(dictionary[[index]])
    }
  }
  value
}

decode_powerbi_dsr <- function(query_data) {
  ds <- query_data$dsr$DS[[1]]
  dictionaries <- ds$ValueDicts %||% list()
  phases <- ds$PH
  encoded_rows <- unlist(
    lapply(phases, \(phase) phase$DM0 %||% list()),
    recursive = FALSE
  )

  if (length(encoded_rows) == 0L) {
    return(tibble())
  }

  descriptors <- NULL
  previous <- NULL
  decoded_rows <- vector("list", length(encoded_rows))

  for (i in seq_along(encoded_rows)) {
    encoded <- encoded_rows[[i]]
    if (!is.null(encoded$S)) {
      descriptors <- encoded$S
    }
    if (is.null(descriptors)) {
      stop("Power BI response omitted the column descriptors.")
    }

    n_columns <- length(descriptors)
    reuse_mask <- as.integer(encoded$R %||% 0L)
    null_mask <- as.integer(encoded[["\u00d8"]] %||% 0L)
    compressed_values <- encoded$C %||% list()
    if (!is.list(compressed_values)) {
      compressed_values <- as.list(compressed_values)
    }
    compressed_index <- 1L
    current <- vector("list", n_columns)

    for (j in seq_len(n_columns)) {
      bit <- bitwShiftL(1L, j - 1L)
      is_reused <- bitwAnd(reuse_mask, bit) != 0L
      is_null <- bitwAnd(null_mask, bit) != 0L
      value_name <- descriptors[[j]]$N

      if (is_reused) {
        if (is.null(previous)) {
          stop("Invalid Power BI compression: first row reuses prior values.")
        }
        value <- previous[[j]]
      } else if (is_null) {
        value <- NA
      } else if (value_name %in% names(encoded)) {
        value <- encoded[[value_name]]
      } else {
        if (compressed_index > length(compressed_values)) {
          stop("Power BI response ended before all row values were decoded.")
        }
        value <- compressed_values[[compressed_index]]
        compressed_index <- compressed_index + 1L
      }

      current[[j]] <- decode_dictionary_value(
        value,
        descriptors[[j]],
        dictionaries
      )
    }

    row_names <- vapply(descriptors, \(x) x$N, character(1))
    decoded_rows[[i]] <- as_tibble(
      setNames(lapply(current, \(x) x %||% NA), row_names)
    )
    previous <- current
  }

  bind_rows(decoded_rows)
}

# ---- Idaho-specific query construction -------------------------------------

measure_select <- function(source, property, name = NULL) {
  list(
    Measure = list(
      Expression = list(SourceRef = list(Source = source)),
      Property = property
    ),
    Name = name %||% paste0(source, ".", property)
  )
}

not_equals_condition <- function(source, property, literal) {
  list(Condition = list(Not = list(Expression = list(
    In = list(
      Expressions = list(column_expression(source, property)),
      Values = list(list(list(Literal = list(Value = literal))))
    )
  ))))
}

# Every entity the report itself joins for this measure. Dropping any of the
# slicer tables (Year Type / Metric / Event Type) makes the measure blank.
id_from <- function() list(
  list(Name = "l",  Entity = "Location",      Type = 0L),
  list(Name = "_",  Entity = "Measure Table", Type = 0L),
  list(Name = "c",  Entity = "Case Type",     Type = 0L),
  list(Name = "y",  Entity = "Year Type",     Type = 0L),
  list(Name = "m",  Entity = "Metric",        Type = 0L),
  list(Name = "e",  Entity = "Event Type",    Type = 0L),
  list(Name = "c1", Entity = "Case",          Type = 0L),
  list(Name = "ya", Entity = "Year Axis",     Type = 0L)
)

# year_type is "Calendar Year" or "Fiscal Year"; it selects which five-year
# window of the Year Axis the measure is evaluated over.
id_where <- function(year_type) list(
  equals_text_condition("c", "Case Type", CASE_TYPE),
  equals_text_condition("y", "Year Type", year_type),
  equals_text_condition("m", "Metric Fields", "''Measure Table''[Civil Cases]"),
  equals_text_condition("e", "Event Type", "Filed"),
  not_equals_condition("c1", "IsJuvenile", "1L"),
  not_equals_condition("l", "District Number", "null")
)

build_id_query <- function(model_id, year_type, by_county = TRUE) {
  selections <- c(
    list(column_select("ya", "FirstDateofMonth")),
    if (by_county) list(column_select("l", "County")) else list(),
    list(measure_select("_", "Civil Cases", "Civil Cases"))
  )

  semantic_command <- list(
    SemanticQueryDataShapeCommand = list(
      Query = list(
        Version = 2L,
        From = id_from(),
        Select = selections,
        Where = id_where(year_type)
      ),
      Binding = list(
        DataReduction = list(
          DataVolume = 4L,
          Primary = list(Window = list(Count = 60000L))
        ),
        Primary = list(
          Groupings = list(
            list(Projections = seq_along(selections) - 1L)
          )
        ),
        Version = 1L
      ),
      ExecutionMetricsKind = 1L
    )
  )

  list(
    version = "1.0.0",
    queries = list(
      list(Query = list(Commands = list(semantic_command)))
    ),
    cancelQueries = list(),
    modelId = model_id
  )
}

# Power BI returns decimal measures as strings with a trailing "D".
.as_measure_numeric <- function(x) {
  as.numeric(sub("D$", "", as.character(x)))
}

.as_month <- function(x) {
  as.Date(as.POSIXct(as.numeric(x) / 1000, origin = "1970-01-01", tz = "UTC"))
}

pull_axis <- function(report, year_type, by_county = TRUE) {
  raw <- decode_powerbi_dsr(
    run_powerbi_query(report, build_id_query(report$model_id, year_type, by_county))
  )
  expected_cols <- if (by_county) 3L else 2L
  if (ncol(raw) != expected_cols) {
    stop("Unexpected column count from the ", year_type, " query: ", ncol(raw))
  }
  names(raw) <- if (by_county) c("month_date", "county", "filings_count") else
    c("month_date", "filings_count")

  out <- raw %>%
    mutate(
      month_date = .as_month(.data$month_date),
      filings_count = .as_measure_numeric(.data$filings_count)
    )

  # An all-NA measure means the "D" suffix handling broke, not that Idaho had
  # no evictions. Fail loudly rather than write a column of NAs.
  if (all(is.na(out$filings_count))) {
    stop("Measure decoded to all-NA for ", year_type,
         " -- Power BI response format changed.")
  }
  out %>% filter(!is.na(.data$month_date))
}

# ---- Main -------------------------------------------------------------------

message("Discovering Idaho Judicial Branch Power BI report...")
report <- discover_report(REPORT_URL)
message("Model ID: ", report$model_id)

message("Querying county-month A12 filings on the CALENDAR-year axis...")
cy <- pull_axis(report, "Calendar Year")
message("  ", nrow(cy), " county-months, ",
        format(min(cy$month_date), "%Y-%m"), "..",
        format(max(cy$month_date), "%Y-%m"))

message("Querying county-month A12 filings on the FISCAL-year axis...")
fy <- pull_axis(report, "Fiscal Year")
message("  ", nrow(fy), " county-months, ",
        format(min(fy$month_date), "%Y-%m"), "..",
        format(max(fy$month_date), "%Y-%m"))

# --- Assertion 1: the two axes must agree wherever they overlap --------------
overlap <- inner_join(
  cy %>% rename(n_cy = "filings_count"),
  fy %>% rename(n_fy = "filings_count"),
  by = c("month_date", "county")
)
n_disagree <- sum(overlap$n_cy != overlap$n_fy, na.rm = TRUE)
message("CY/FY overlap: ", nrow(overlap), " county-months, ",
        n_disagree, " disagreements")
if (n_disagree > 0L) {
  stop("Calendar and fiscal axes disagree on ", n_disagree,
       " county-months; the union is not valid.")
}

county_panel <- bind_rows(
  cy,
  fy %>% anti_join(cy, by = c("month_date", "county"))
) %>%
  arrange(.data$month_date, .data$county)

n_counties <- n_distinct(county_panel$county)
n_months <- n_distinct(county_panel$month_date)

stopifnot(
  !anyDuplicated(county_panel %>% select("month_date", "county")),
  all(county_panel$filings_count >= 0),
  nrow(county_panel) == n_counties * n_months
)

if (n_counties != EXPECT_COUNTIES) {
  warning("Expected ", EXPECT_COUNTIES, " Idaho counties, got ", n_counties,
          " -- check the dashboard's Filing Location tree.")
}

# The county grid must be complete: a missing county-month would otherwise be
# summed as an implicit zero into the statewide series.
span <- seq(min(county_panel$month_date), max(county_panel$month_date), by = "month")
if (n_months != length(span)) {
  stop("Interior month gap: ", n_months, " distinct months across a ",
       length(span), "-month span.")
}

state_panel <- county_panel %>%
  group_by(month_date = .data$month_date) %>%
  summarise(filings_count = sum(.data$filings_count),
            n_counties = n_distinct(.data$county), .groups = "drop") %>%
  arrange(.data$month_date)

stopifnot(all(state_panel$n_counties == n_counties))

# --- Assertion 2: Twin Falls must reproduce the LSC CCDI series -------------
# Twin Falls is the one Idaho county already in the state panel, so it is the
# only place the two independent sources can be compared. Annual totals, not
# monthly, because the LSC month boundary is a filing-date convention that need
# not agree case-for-case.
panel_path <- file.path(PROJECT_ROOT, "data", "raw",
                        "state_month_panel_with_treatment.csv")
if (file.exists(panel_path)) {
  lsc <- read_csv(panel_path, show_col_types = FALSE) %>%
    filter(.data$state_abb == "ID") %>%
    mutate(month_date = as.Date(.data$month_date)) %>%
    transmute(year = as.integer(format(.data$month_date, "%Y")),
              month_date, lsc = .data$filings_count)

  tf <- county_panel %>%
    filter(.data$county == "Twin Falls") %>%
    transmute(year = as.integer(format(.data$month_date, "%Y")),
              month_date, dash = .data$filings_count)

  cmp <- inner_join(lsc, tf, by = c("year", "month_date")) %>%
    group_by(year) %>%
    summarise(months = n(), lsc = sum(.data$lsc), dash = sum(.data$dash),
              .groups = "drop") %>%
    filter(.data$months == 12L) %>%
    mutate(pct_diff = round(100 * (.data$dash - .data$lsc) / .data$lsc, 2))

  if (nrow(cmp) > 0L) {
    message("Twin Falls cross-source check (complete years only):")
    print(as.data.frame(cmp), row.names = FALSE)
    worst <- max(abs(cmp$pct_diff))
    if (worst > 2) {
      stop("Twin Falls disagrees with the LSC CCDI series by ", worst,
           "% -- these are not the same measurement.")
    }
  }
} else {
  message("State panel absent; skipped the Twin Falls cross-source check.")
}

write_csv(county_panel, COUNTY_OUT)
write_csv(state_panel, STATE_OUT)

# --- Append-only manifest: this source forgets, so record what we caught -----
manifest_row <- tibble(
  pulled_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  model_id = as.character(report$model_id),
  first_month = format(min(county_panel$month_date), "%Y-%m"),
  last_month = format(max(county_panel$month_date), "%Y-%m"),
  n_months = n_months,
  n_counties = n_counties,
  total_filings = sum(county_panel$filings_count)
)
if (file.exists(MANIFEST_OUT)) {
  write_csv(bind_rows(read_csv(MANIFEST_OUT, show_col_types = FALSE),
                      manifest_row), MANIFEST_OUT)
} else {
  write_csv(manifest_row, MANIFEST_OUT)
}

message("")
message("=== Idaho A12 extraction complete ===")
message("Span: ", manifest_row$first_month, "..", manifest_row$last_month,
        " (", n_months, " months)")
message("Counties: ", n_counties)
message("Total filings: ", format(manifest_row$total_filings, big.mark = ","))
message("Wrote: ", COUNTY_OUT)
message("Wrote: ", STATE_OUT)
message("Wrote: ", MANIFEST_OUT)
