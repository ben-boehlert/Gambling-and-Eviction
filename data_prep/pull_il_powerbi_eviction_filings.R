# ============================================================================
# pull_il_powerbi_eviction_filings.R
#
# Purpose: Extract Illinois county-quarter eviction filings from the public
#          Illinois Courts Power BI dashboard.
#
# Source dashboard (2022-2025):
# https://app.powerbigov.us/view?r=eyJrIjoiMThmYmQxZTEtYWQxMi00NDliLTliNTEtYTQ4MzYzZDJjZTNkIiwidCI6ImRjNjQxZWU0LTViNWQtNDlhMC04ZmY0LTdhYWZjNjExOGE0MiJ9
#
# Target definition:
#   CASE_CATEGORY == "EVICTION"
#   CASE_STATUS   == "New Filed"
#
# Outputs:
#   data/raw/illinois/il_county_quarter_eviction_filings.csv
#   data/raw/illinois/il_state_quarter_eviction_filings.csv
#
# Notes:
# - The dashboard is Illinois, not Michigan.
# - The official 2018-2021 companion dashboard does not report EVICTION as a
#   distinct case category, so this script does not append a non-comparable
#   pre-2022 proxy.
# - Power BI's public query response uses dictionary and run-length
#   compression. decode_powerbi_dsr() reconstructs the returned rows.
# ============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(httr2)
  library(jsonlite)
  library(readr)
  library(stringr)
  library(tibble)
})

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0L) y else x
}

PROJECT_ROOT <- here::here()
OUT_DIR <- file.path(PROJECT_ROOT, "data", "raw", "illinois")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

REPORT_URL <- paste0(
  "https://app.powerbigov.us/view?r=",
  "eyJrIjoiMThmYmQxZTEtYWQxMi00NDliLTliNTEtYTQ4MzYzZDJjZTNkIiwidCI6",
  "ImRjNjQxZWU0LTViNWQtNDlhMC04ZmY0LTdhYWZjNjExOGE0MiJ9"
)

COUNTY_OUT <- file.path(OUT_DIR, "il_county_quarter_eviction_filings.csv")
STATE_OUT <- file.path(OUT_DIR, "il_state_quarter_eviction_filings.csv")

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

build_eviction_query <- function(model_id, entity = "vw_QCCS_All") {
  selected_columns <- c("YEAR", "QUARTER", "CIRCUIT", "COUNTY")
  selections <- lapply(selected_columns, \(x) column_select("v", x))
  selections[[length(selections) + 1L]] <- sum_select("v", "CASES")

  semantic_command <- list(
    SemanticQueryDataShapeCommand = list(
      Query = list(
        Version = 2L,
        From = list(
          list(Name = "v", Entity = entity, Type = 0L)
        ),
        Select = selections,
        Where = list(
          equals_text_condition("v", "CASE_STATUS", "New Filed"),
          equals_text_condition("v", "CASE_CATEGORY", "EVICTION")
        )
      ),
      Binding = list(
        DataReduction = list(
          DataVolume = 6L,
          Primary = list(Window = list(Count = 5000L))
        ),
        Primary = list(
          Groupings = list(
            list(Projections = 0:4)
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

validate_source_schema <- function(report) {
  entities <- report$schema$Entities
  entity_index <- which(vapply(
    entities,
    \(x) identical(x$Name, "vw_QCCS_All"),
    logical(1)
  ))
  if (length(entity_index) != 1L) {
    stop("Expected exactly one vw_QCCS_All entity in the report schema.")
  }

  fields <- vapply(
    entities[[entity_index]]$Properties,
    \(x) x$Name,
    character(1)
  )
  required_fields <- c(
    "COUNTY", "YEAR", "CIRCUIT", "QUARTER",
    "CASE_STATUS", "CASE_CATEGORY", "CASES"
  )
  missing_fields <- setdiff(required_fields, fields)
  if (length(missing_fields) > 0L) {
    stop(
      "The Power BI schema changed; missing fields: ",
      paste(missing_fields, collapse = ", ")
    )
  }
}

build_county_fips_crosswalk <- function(project_root) {
  crosswalk_path <- file.path(
    project_root,
    "data",
    "raw",
    "county_court-issued_2000_2023_ben_update_5_12.csv"
  )
  if (!file.exists(crosswalk_path)) {
    stop("County FIPS crosswalk not found: ", crosswalk_path)
  }

  read_csv(
    crosswalk_path,
    col_select = c(state, county, fips_county),
    show_col_types = FALSE
  ) |>
    filter(state == "Illinois") |>
    distinct(county, fips_county) |>
    mutate(
      county_key = county |>
        str_remove(regex(" County$", ignore_case = TRUE)) |>
        str_to_upper() |>
        str_replace_all("[^A-Z0-9]", ""),
      county_name = str_remove(county, regex(" County$", ignore_case = TRUE)),
      county_fips = sprintf("%05d", as.integer(fips_county))
    ) |>
    select(county_key, county_name, county_fips)
}

message("Discovering Illinois Courts Power BI report...")
report <- discover_report(REPORT_URL)
validate_source_schema(report)

message("Querying county-quarter EVICTION / New Filed counts...")
query_payload <- build_eviction_query(report$model_id)
query_data <- run_powerbi_query(report, query_payload)
raw_panel <- decode_powerbi_dsr(query_data)

if (ncol(raw_panel) != 5L) {
  stop("Expected five columns from Power BI; received ", ncol(raw_panel), ".")
}
names(raw_panel) <- c(
  "year", "quarter", "circuit", "county_key", "filings_count"
)

county_crosswalk <- build_county_fips_crosswalk(PROJECT_ROOT)

county_panel <- raw_panel |>
  transmute(
    year = as.integer(year),
    quarter = as.integer(quarter),
    circuit = as.integer(circuit),
    county_key = county_key |>
      as.character() |>
      str_to_upper() |>
      str_replace_all("[^A-Z0-9]", ""),
    filings_count = as.integer(filings_count)
  ) |>
  left_join(county_crosswalk, by = "county_key")

unmatched_counties <- county_panel |>
  filter(is.na(county_fips)) |>
  distinct(county_key) |>
  pull(county_key)
if (length(unmatched_counties) > 0L) {
  stop(
    "Unmatched Illinois counties: ",
    paste(unmatched_counties, collapse = ", ")
  )
}

county_panel <- county_panel |>
  mutate(
    state_abb = "IL",
    state_fips = "17",
    quarter_start = as.Date(sprintf(
      "%04d-%02d-01",
      year,
      (quarter - 1L) * 3L + 1L
    )),
    case_category = "EVICTION",
    case_status = "New Filed",
    data_status = case_when(
      county_name == "Kankakee" & year == 2025L ~ "unavailable",
      county_name == "Kankakee" &
        year == 2024L &
        quarter %in% c(3L, 4L) ~ "projected",
      county_name == "Cook" & year == 2023L ~ "reported_system_transition",
      TRUE ~ "reported"
    ),
    source_note = case_when(
      data_status == "unavailable" ~ paste(
        "Illinois Courts states that 2025 Kankakee County data are",
        "unavailable; source zeros are coded NA."
      ),
      data_status == "projected" ~ paste(
        "Illinois Courts states that 2024 Q3-Q4 Kankakee County",
        "statistics are projections based on historical quarterly totals."
      ),
      data_status == "reported_system_transition" ~ paste(
        "Illinois Courts notes 2023 Cook County filing and closing",
        "variances during a case-management-system transition."
      ),
      TRUE ~ NA_character_
    ),
    filings_count = if_else(
      data_status == "unavailable",
      NA_integer_,
      filings_count
    ),
    source = "Illinois Courts Power BI"
  ) |>
  select(
    state_abb,
    state_fips,
    county_fips,
    county = county_name,
    circuit,
    quarter_start,
    year,
    quarter,
    filings_count,
    case_category,
    case_status,
    data_status,
    source_note,
    source
  ) |>
  arrange(year, quarter, county_fips)

duplicate_keys <- county_panel |>
  count(county_fips, year, quarter) |>
  filter(n != 1L)
if (nrow(duplicate_keys) > 0L) {
  stop("Duplicate county-year-quarter keys found in extracted data.")
}
unexpected_missing <- is.na(county_panel$filings_count) &
  county_panel$data_status != "unavailable"
if (
  any(unexpected_missing) ||
    any(county_panel$filings_count < 0L, na.rm = TRUE)
) {
  stop("Eviction filing counts contain unexpected missing or negative values.")
}

expected_grid <- expand.grid(
  county_fips = unique(county_panel$county_fips),
  year = unique(county_panel$year),
  quarter = 1:4,
  stringsAsFactors = FALSE
)
missing_keys <- anti_join(
  expected_grid,
  county_panel,
  by = c("county_fips", "year", "quarter")
)
if (nrow(missing_keys) > 0L) {
  stop("The extracted county-quarter panel has ", nrow(missing_keys), " gaps.")
}

state_panel <- county_panel |>
  group_by(
    state_abb,
    state_fips,
    quarter_start,
    year,
    quarter,
    case_category,
    case_status,
    source
  ) |>
  summarise(
    n_counties_reporting = sum(!is.na(filings_count)),
    n_counties_expected = n_distinct(county_fips),
    n_counties_projected = sum(data_status == "projected"),
    coverage_complete = n_counties_reporting == n_counties_expected,
    filings_count = sum(filings_count, na.rm = TRUE),
    .groups = "drop"
  ) |>
  arrange(year, quarter)

write_csv(county_panel, COUNTY_OUT)
write_csv(state_panel, STATE_OUT)

latest_total <- state_panel |>
  slice_max(quarter_start, n = 1, with_ties = FALSE) |>
  pull(filings_count)
latest_reporting <- state_panel |>
  slice_max(quarter_start, n = 1, with_ties = FALSE) |>
  transmute(label = paste0(n_counties_reporting, "/", n_counties_expected)) |>
  pull(label)

message("")
message("=== Illinois eviction filing extraction complete ===")
message("Model ID: ", report$model_id)
message("Coverage: ", min(county_panel$quarter_start), " to ",
        max(county_panel$quarter_start))
message("Counties: ", n_distinct(county_panel$county_fips))
message("County-quarter rows: ", nrow(county_panel))
message(
  "Latest statewide reported total: ",
  format(latest_total, big.mark = ","),
  " (", latest_reporting, " counties)"
)
message("Wrote: ", COUNTY_OUT)
message("Wrote: ", STATE_OUT)
