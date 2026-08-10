# ============================================================================
# pull_mi_powerbi_eviction_filings.R
#
# Purpose: Extract Michigan county-year landlord/tenant new filings from the
#          public Michigan Courts Interactive Court Data Dashboard.
#
# Source page:
# https://www.courts.michigan.gov/publications/statistics-and-reports/interactive-court-data-dashboard/
#
# Embedded Power BI report:
# https://app.powerbigov.us/view?r=eyJrIjoiZDc4MTcyNWMtNDNkYi00NWNhLTg3ZDktYjI3YzllMmRlOGUxIiwidCI6IjI5NWU5M2Y4LTM4NGItNDk3Yy04ZGNhLWYyYjlhODYzYmVmZCJ9
#
# Target definition:
#   CASE_TYPE_CODE == "LT"          (Landlord/Tenant Summary Proceedings)
#   ACTION_NAME    == "New Filings"
#
# Outputs:
#   data/raw/michigan/mi_county_year_landlord_tenant_filings.csv
#   data/raw/michigan/mi_state_year_landlord_tenant_filings.csv
#
# Important:
# - The dashboard's QTR_END_DATE field contains one observation per calendar
#   year (December 31), not monthly dates. This script therefore produces an
#   annual panel and refuses to describe it as monthly data.
# - Missing county-year combinations are retained as NA and are not assumed to
#   be zero.
# - Power BI public query responses use dictionary and run-length compression.
#   decode_powerbi_dsr() reconstructs the returned rows.
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
OUT_DIR <- file.path(PROJECT_ROOT, "data", "raw", "michigan")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

REPORT_URL <- paste0(
  "https://app.powerbigov.us/view?r=",
  "eyJrIjoiZDc4MTcyNWMtNDNkYi00NWNhLTg3ZDktYjI3YzllMmRlOGUxIiwidCI6",
  "IjI5NWU5M2Y4LTM4NGItNDk3Yy04ZGNhLWYyYjlhODYzYmVmZCJ9"
)

COUNTY_OUT <- file.path(
  OUT_DIR,
  "mi_county_year_landlord_tenant_filings.csv"
)
STATE_OUT <- file.path(
  OUT_DIR,
  "mi_state_year_landlord_tenant_filings.csv"
)

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

build_eviction_query <- function(
  model_id,
  entity = "CASELOAD_DATA_FILTERED"
) {
  selections <- list(
    column_select("c", "QTR_END_DATE"),
    column_select("c", "COURT_COUNTY"),
    sum_select("c", "QUANTITY")
  )

  semantic_command <- list(
    SemanticQueryDataShapeCommand = list(
      Query = list(
        Version = 2L,
        From = list(
          list(Name = "c", Entity = entity, Type = 0L)
        ),
        Select = selections,
        Where = list(
          equals_text_condition("c", "CASE_TYPE_CODE", "LT"),
          equals_text_condition("c", "ACTION_NAME", "New Filings")
        )
      ),
      Binding = list(
        DataReduction = list(
          DataVolume = 6L,
          Primary = list(Window = list(Count = 5000L))
        ),
        Primary = list(
          Groupings = list(
            list(Projections = 0:2)
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
    \(x) identical(x$Name, "CASELOAD_DATA_FILTERED"),
    logical(1)
  ))
  if (length(entity_index) != 1L) {
    stop("Expected exactly one CASELOAD_DATA_FILTERED entity.")
  }

  fields <- vapply(
    entities[[entity_index]]$Properties,
    \(x) x$Name,
    character(1)
  )
  required_fields <- c(
    "QTR_END_DATE", "COURT_COUNTY", "CASE_TYPE_CODE",
    "ACTION_NAME", "QUANTITY"
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
    filter(state == "Michigan") |>
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

as_powerbi_date <- function(x) {
  numeric_x <- suppressWarnings(as.numeric(x))
  if (all(!is.na(numeric_x))) {
    return(as.Date(as.POSIXct(numeric_x / 1000, origin = "1970-01-01", tz = "UTC")))
  }
  as.Date(as.character(x))
}

message("Discovering Michigan Courts Power BI report...")
report <- discover_report(REPORT_URL)
validate_source_schema(report)

message("Querying county-year LT / New Filings counts...")
query_payload <- build_eviction_query(report$model_id)
query_data <- run_powerbi_query(report, query_payload)
raw_panel <- decode_powerbi_dsr(query_data)

if (ncol(raw_panel) != 3L) {
  stop("Expected three columns from Power BI; received ", ncol(raw_panel), ".")
}
names(raw_panel) <- c("period_end", "county_key", "filings_count")

county_crosswalk <- build_county_fips_crosswalk(PROJECT_ROOT)

observed_panel <- raw_panel |>
  transmute(
    period_end = as_powerbi_date(period_end),
    year = as.integer(format(period_end, "%Y")),
    county_key = county_key |>
      as.character() |>
      str_to_upper() |>
      str_replace_all("[^A-Z0-9]", ""),
    filings_count = as.integer(filings_count)
  ) |>
  left_join(county_crosswalk, by = "county_key")

unmatched_counties <- observed_panel |>
  filter(is.na(county_fips)) |>
  distinct(county_key) |>
  pull(county_key)
if (length(unmatched_counties) > 0L) {
  stop(
    "Unmatched Michigan counties: ",
    paste(unmatched_counties, collapse = ", ")
  )
}

if (any(format(observed_panel$period_end, "%m-%d") != "12-31")) {
  stop(
    "The source now contains non-annual dates. Review the report before ",
    "changing the output frequency."
  )
}

duplicate_keys <- observed_panel |>
  count(county_fips, year) |>
  filter(n != 1L)
if (nrow(duplicate_keys) > 0L) {
  stop("Duplicate county-year keys found in extracted data.")
}
if (
  any(is.na(observed_panel$filings_count)) ||
    any(observed_panel$filings_count < 0L)
) {
  stop("Observed filing counts contain missing or negative values.")
}

county_panel <- expand_grid(
  county_fips = county_crosswalk$county_fips,
  year = seq(min(observed_panel$year), max(observed_panel$year))
) |>
  left_join(
    county_crosswalk |>
      select(county_fips, county = county_name),
    by = "county_fips"
  ) |>
  left_join(
    observed_panel |>
      select(county_fips, year, period_end, filings_count),
    by = c("county_fips", "year")
  ) |>
  mutate(
    state_abb = "MI",
    state_fips = "26",
    period_end = coalesce(period_end, as.Date(sprintf("%04d-12-31", year))),
    case_type_code = "LT",
    case_type_name = "Landlord/Tenant Summary Proceedings",
    action_name = "New Filings",
    data_status = if_else(
      is.na(filings_count),
      "not_returned_by_source",
      "reported"
    ),
    source = "Michigan Courts Interactive Court Data Dashboard"
  ) |>
  select(
    state_abb,
    state_fips,
    county_fips,
    county,
    period_end,
    year,
    filings_count,
    case_type_code,
    case_type_name,
    action_name,
    data_status,
    source
  ) |>
  arrange(year, county_fips)

state_panel <- county_panel |>
  group_by(
    state_abb,
    state_fips,
    period_end,
    year,
    case_type_code,
    case_type_name,
    action_name,
    source
  ) |>
  summarise(
    n_counties_reporting = sum(!is.na(filings_count)),
    n_counties_expected = n_distinct(county_fips),
    coverage_complete = n_counties_reporting == n_counties_expected,
    reported_county_sum = sum(filings_count, na.rm = TRUE),
    filings_count = if_else(
      coverage_complete,
      reported_county_sum,
      NA_integer_
    ),
    .groups = "drop"
  ) |>
  arrange(year)

write_csv(county_panel, COUNTY_OUT)
write_csv(state_panel, STATE_OUT)

message("")
message("=== Michigan landlord/tenant extraction complete ===")
message("Model ID: ", report$model_id)
message("Source frequency: annual (December 31 observations)")
message(
  "Coverage: ",
  min(county_panel$year),
  " to ",
  max(county_panel$year)
)
message("Counties expected: ", n_distinct(county_panel$county_fips))
message("County-year rows: ", nrow(county_panel))
message(
  "County-years returned: ",
  sum(county_panel$data_status == "reported"),
  "/",
  nrow(county_panel)
)
message("Wrote: ", COUNTY_OUT)
message("Wrote: ", STATE_OUT)
