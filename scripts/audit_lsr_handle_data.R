#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

handle_file <- Sys.getenv(
  "HANDLE_FILE",
  "data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv"
)

required_columns <- c(
  "State", "Month", "month_date", "Handle", "Revenue", "Hold", "Taxes"
)

fail <- function(...) {
  stop(sprintf(...), call. = FALSE)
}

if (!file.exists(handle_file)) {
  fail("Handle file not found: %s", handle_file)
}

handle <- read_csv(handle_file, show_col_types = FALSE)

missing_columns <- setdiff(required_columns, names(handle))
if (length(missing_columns) > 0L) {
  fail("Missing required columns: %s", paste(missing_columns, collapse = ", "))
}

handle <- handle %>%
  mutate(
    month_date = as.Date(month_date),
    month_index = as.integer(format(month_date, "%Y")) * 12L +
      as.integer(format(month_date, "%m"))
  )

if (anyNA(handle$State) || any(trimws(handle$State) == "")) {
  fail("State contains missing or blank values")
}
if (anyNA(handle$month_date)) {
  fail("month_date contains invalid or missing dates")
}

duplicate_keys <- handle %>%
  count(State, month_date, name = "n") %>%
  filter(n > 1L)
if (nrow(duplicate_keys) > 0L) {
  fail("Found %d duplicated State x month_date keys", nrow(duplicate_keys))
}

if (anyNA(handle$Handle)) {
  fail("Handle contains %d missing values", sum(is.na(handle$Handle)))
}
if (any(handle$Handle < 0, na.rm = TRUE)) {
  fail("Handle contains negative values")
}

month_label_mismatches <- handle %>%
  filter(Month != format(month_date, "%B %Y"))
if (nrow(month_label_mismatches) > 0L) {
  fail("Found %d Month/month_date label mismatches", nrow(month_label_mismatches))
}

calendar_gaps <- handle %>%
  arrange(State, month_date) %>%
  group_by(State) %>%
  mutate(month_step = month_index - lag(month_index)) %>%
  ungroup() %>%
  filter(!is.na(month_step), month_step != 1L)
if (nrow(calendar_gaps) > 0L) {
  fail("Found %d within-state calendar gaps", nrow(calendar_gaps))
}

positive_handle_missing_hold <- handle %>%
  filter(Handle > 0, is.na(Hold))
if (nrow(positive_handle_missing_hold) > 0L) {
  fail(
    "Found %d positive-Handle rows with missing Hold",
    nrow(positive_handle_missing_hold)
  )
}

hold_mismatches <- handle %>%
  filter(Handle > 0, !is.na(Revenue), !is.na(Hold)) %>%
  mutate(hold_error = abs(Hold - Revenue / Handle)) %>%
  filter(hold_error > 0.00051)
if (nrow(hold_mismatches) > 0L) {
  fail(
    "Found %d rows where Hold is inconsistent with Revenue / Handle",
    nrow(hold_mismatches)
  )
}

cat(sprintf("PASS: %s\n", handle_file))
cat(sprintf("  Rows: %s\n", format(nrow(handle), big.mark = ",")))
cat(sprintf("  States: %d\n", n_distinct(handle$State)))
cat(sprintf(
  "  Coverage: %s to %s\n",
  min(handle$month_date),
  max(handle$month_date)
))
cat(sprintf("  Duplicate keys: %d\n", nrow(duplicate_keys)))
cat(sprintf("  Calendar gaps: %d\n", nrow(calendar_gaps)))
cat(sprintf("  Missing Handle: %d\n", sum(is.na(handle$Handle))))
cat(sprintf("  Lifetime Handle: $%s\n", format(
  sum(handle$Handle, na.rm = TRUE),
  big.mark = ",",
  scientific = FALSE,
  trim = TRUE
)))
