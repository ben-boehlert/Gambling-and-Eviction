#!/usr/bin/env Rscript

# diff_county_court_issued_2025_update.R
# Compare:
#   (1) county_court-issued_2000_2023_ben_update_5_12.csv  (old)
#   (2) county_court-issued_2000_2025_updated.xlsm         (new)
#
# Focus: what's added in the 2025 update (new county-years and/or backfilled county-years),
# plus schema changes and (optionally) revised values on overlapping county-years.
#
# ---- Run examples ----
# Terminal:
#   Rscript diff_county_court_issued_2025_update.R
#
# With custom inputs:
#   Rscript diff_county_court_issued_2025_update.R --old path/to/old.csv --new path/to/new.xlsm --outdir diff_outputs
#
# If the .xlsm has multiple sheets, you can force one:
#   Rscript diff_county_court_issued_2025_update.R --sheet "SheetName"
#
# Outputs are written to --outdir (default: ./diff_outputs).

suppressPackageStartupMessages({
  library(tidyverse)
  library(readxl)
  library(janitor)
})

# ---------------------------
# Simple arg parsing (no extra deps)
# ---------------------------
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NA_character_) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) return(default)
  args[[i + 1]]
}

path_new <- get_arg("--new", "/mnt/data/county_court-issued_2000_2025_updated.xlsm")
path_old <- get_arg("--old", "/mnt/data/county_court-issued_2000_2023_ben_update_5_12.csv")
sheet_in <- get_arg("--sheet", NA_character_)
out_dir  <- get_arg("--outdir", "diff_outputs")

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

cat("\n--- Inputs ---\n")
cat("Old (csv): ", path_old, "\n", sep = "")
cat("New (xlsm): ", path_new, "\n", sep = "")
cat("Out dir:   ", normalizePath(out_dir), "\n", sep = "")
if (!file.exists(path_old)) stop("Old file not found: ", path_old)
if (!file.exists(path_new)) stop("New file not found: ", path_new)

# ---------------------------
# Helpers
# ---------------------------
normalize_keys <- function(df) {
  nm <- names(df)

  # If there's a 5-digit fips column, parse state/county from it.
  if (!("fips_state" %in% nm && "fips_county" %in% nm)) {
    fips_candidates <- intersect(nm, c("fips", "county_fips", "geoid", "geoid_fips", "fips_code"))
    if (length(fips_candidates) >= 1) {
      fcol <- fips_candidates[[1]]
      df <- df %>%
        mutate(
          fips = str_pad(as.character(.data[[fcol]]), 5, pad = "0"),
          fips_state = suppressWarnings(as.integer(str_sub(fips, 1, 2))),
          fips_county = suppressWarnings(as.integer(str_sub(fips, 3, 5)))
        )
      nm <- names(df)
    }
  }

  # Try common alternatives for state/county fips and year
  if (!("fips_state" %in% nm)) {
    cand <- intersect(nm, c("state_fips", "st_fips", "statefp", "statefp10", "state_fip"))
    if (length(cand) >= 1) df <- df %>% rename(fips_state = all_of(cand[[1]]))
  }
  if (!("fips_county" %in% nm)) {
    cand <- intersect(nm, c("county_fips", "cnty_fips", "countyfp", "countyfp10"))
    if (length(cand) >= 1) df <- df %>% rename(fips_county = all_of(cand[[1]]))
  }
  if (!("year" %in% nm)) {
    cand <- intersect(nm, c("yr", "year_int"))
    if (length(cand) >= 1) df <- df %>% rename(year = all_of(cand[[1]]))
  }

  df
}

fix_types <- function(df) {
  df %>%
    mutate(
      across(any_of(c("state", "county")), as.character),
      across(any_of(c("fips_state", "fips_county", "year")),
             ~ suppressWarnings(as.integer(.x))),
      fips = if_else(
        !is.na(fips_state) & !is.na(fips_county),
        str_pad(as.character(fips_state), 2, pad = "0") %>%
          str_c(str_pad(as.character(fips_county), 3, pad = "0")),
        NA_character_
      )
    )
}

pick_sheet <- function(path, required = c("fips_state", "fips_county", "year")) {
  sheets <- readxl::excel_sheets(path)
  hits <- purrr::map_lgl(sheets, function(sh) {
    df <- suppressWarnings(readxl::read_excel(path, sheet = sh, n_max = 200)) %>%
      janitor::clean_names()
    all(required %in% names(normalize_keys(df)))
  })
  if (any(hits)) return(sheets[which(hits)[1]])
  sheets[[1]]
}

safe_write <- function(df, filename) {
  readr::write_csv(df, file.path(out_dir, filename))
}

# ---------------------------
# Load data
# ---------------------------
old <- readr::read_csv(path_old, show_col_types = FALSE) %>%
  janitor::clean_names() %>%
  normalize_keys() %>%
  fix_types()

sheet_use <- sheet_in
if (is.na(sheet_use) || sheet_use == "") {
  sheet_use <- pick_sheet(path_new)
}
cat("Using xlsm sheet: ", sheet_use, "\n", sep = "")

new <- readxl::read_excel(path_new, sheet = sheet_use) %>%
  janitor::clean_names() %>%
  normalize_keys() %>%
  fix_types()

keys <- c("fips_state", "fips_county", "year")
missing_old <- setdiff(keys, names(old))
missing_new <- setdiff(keys, names(new))
if (length(missing_old) > 0) stop("Old is missing key columns after normalization: ", paste(missing_old, collapse = ", "))
if (length(missing_new) > 0) stop("New is missing key columns after normalization: ", paste(missing_new, collapse = ", "))

cat("\n--- Basic sizes ---\n")
cat("Old rows: ", nrow(old), " | distinct county-years: ", nrow(distinct(old, across(all_of(keys)))), "\n", sep = "")
cat("New rows: ", nrow(new), " | distinct county-years: ", nrow(distinct(new, across(all_of(keys)))), "\n", sep = "")

# ============================================================
# 1) Schema differences
# ============================================================
cols_only_in_2025 <- setdiff(names(new), names(old))
cols_only_in_2023 <- setdiff(names(old), names(new))

schema_only_2025 <- tibble(column = sort(cols_only_in_2025))
schema_only_2023 <- tibble(column = sort(cols_only_in_2023))

safe_write(schema_only_2025, "schema_only_in_2025.csv")
safe_write(schema_only_2023, "schema_only_in_2023.csv")

cat("\n--- Schema ---\n")
cat("Columns only in 2025 file: ", nrow(schema_only_2025), "\n", sep = "")
cat("Columns only in 2023 file: ", nrow(schema_only_2023), "\n", sep = "")

# ============================================================
# 2) Added / dropped county-years
# ============================================================
new_keys <- new %>% distinct(across(all_of(keys)))
old_keys <- old %>% distinct(across(all_of(keys)))

added_keys   <- anti_join(new_keys, old_keys, by = keys)
dropped_keys <- anti_join(old_keys, new_keys, by = keys)

added_keys_by_year <- added_keys %>% count(year, sort = FALSE) %>% arrange(year)

added_keys_by_period <- added_keys %>%
  mutate(period = case_when(
    is.na(year) ~ "missing_year",
    year >= 2024L ~ "new_years_2024_2025",
    TRUE ~ "backfill_<=2023"
  )) %>%
  count(period) %>%
  arrange(desc(n))

safe_write(added_keys, "added_county_year_keys.csv")
safe_write(dropped_keys, "dropped_county_year_keys.csv")
safe_write(added_keys_by_year, "added_keys_by_year.csv")
safe_write(added_keys_by_period, "added_keys_by_period.csv")

cat("\n--- County-year coverage changes ---\n")
cat("Added county-years in 2025 file (not in 2023 file): ", nrow(added_keys), "\n", sep = "")
cat("Dropped county-years (in 2023 file but missing in 2025 file): ", nrow(dropped_keys), "\n", sep = "")
print(added_keys_by_period)

# Pull the actual new rows from the 2025 file
added_rows <- new %>% semi_join(added_keys, by = keys)
safe_write(added_rows, "added_rows_full_2025file.csv")

added_rows_2024_2025 <- added_rows %>% filter(!is.na(year) & year >= 2024L)
added_rows_backfill  <- added_rows %>% filter(!is.na(year) & year <= 2023L)

safe_write(added_rows_2024_2025, "added_rows_2024_2025.csv")
safe_write(added_rows_backfill, "added_rows_backfill_2000_2023.csv")

# ============================================================
# 3) Duplicate audit
# ============================================================
dup_audit <- function(df, label) {
  df %>%
    count(across(all_of(keys))) %>%
    filter(n > 1) %>%
    summarise(
      dataset = label,
      n_county_years_with_dupes = n(),
      max_rows_within_county_year = max(n),
      total_extra_rows = sum(n - 1),
      .groups = "drop"
    )
}

dup_summary <- bind_rows(
  dup_audit(old, "old_2000_2023"),
  dup_audit(new, "new_2000_2025")
)

safe_write(dup_summary, "duplicate_audit_summary.csv")

cat("\n--- Duplicate audit (by county-year keys) ---\n")
print(dup_summary)

old_dup_keys <- old %>% count(across(all_of(keys))) %>% filter(n > 1) %>% arrange(desc(n))
new_dup_keys <- new %>% count(across(all_of(keys))) %>% filter(n > 1) %>% arrange(desc(n))
safe_write(old_dup_keys, "duplicate_keys_old.csv")
safe_write(new_dup_keys, "duplicate_keys_new.csv")

# ============================================================
# 4) Value changes on overlapping county-years
#    (a) unique-only: compare only where each dataset has exactly 1 row per county-year
#    (b) aggregated: aggregate duplicates by summing numeric cols; taking first non-numeric
# ============================================================
common_cols <- intersect(names(old), names(new))
measure_cols <- setdiff(common_cols, keys)

# ---- (a) unique-only ----
old_unique <- old %>%
  add_count(across(all_of(keys)), name = "n_key") %>%
  filter(n_key == 1) %>%
  select(-n_key)

new_unique <- new %>%
  add_count(across(all_of(keys)), name = "n_key") %>%
  filter(n_key == 1) %>%
  select(-n_key)

paired_unique <- inner_join(
  old_unique %>% select(all_of(keys), all_of(measure_cols)),
  new_unique %>% select(all_of(keys), all_of(measure_cols)),
  by = keys,
  suffix = c("_old", "_new")
)

changed_cells_unique <- purrr::map_dfr(measure_cols, function(v) {
  x <- paired_unique[[paste0(v, "_old")]]
  y <- paired_unique[[paste0(v, "_new")]]
  is_num <- is.numeric(x) && is.numeric(y)

  changed <- if (is_num) {
    xor(is.na(x), is.na(y)) | (!is.na(x) & !is.na(y) & !dplyr::near(x, y))
  } else {
    xor(is.na(x), is.na(y)) | (!is.na(x) & !is.na(y) & (as.character(x) != as.character(y)))
  }

  tibble(
    fips_state = paired_unique$fips_state,
    fips_county = paired_unique$fips_county,
    year = paired_unique$year,
    var = v,
    old = as.character(x),
    new = as.character(y)
  ) %>% filter(changed)
})

changed_summary_unique <- changed_cells_unique %>% count(var, sort = TRUE)
safe_write(changed_cells_unique, "changed_cells_unique_only.csv")
safe_write(changed_summary_unique, "changed_cells_unique_only_summary.csv")

cat("\n--- Value changes (unique-only county-years) ---\n")
cat("Overlapping county-years eligible for unique-only compare: ", nrow(paired_unique), "\n", sep = "")
cat("Changed cells (unique-only): ", nrow(changed_cells_unique), "\n", sep = "")
if (nrow(changed_summary_unique) > 0) print(head(changed_summary_unique, 15))

# ---- (b) aggregated compare ----
aggregate_by_key <- function(df) {
  num_cols <- df %>% select(where(is.numeric)) %>% names()
  num_sum <- setdiff(num_cols, keys)

  df %>%
    group_by(across(all_of(keys))) %>%
    summarise(
      across(all_of(num_sum), ~ sum(.x, na.rm = TRUE)),
      across(where(~ !is.numeric(.x)), ~ dplyr::first(.x)),
      .groups = "drop"
    )
}

old_agg <- aggregate_by_key(old)
new_agg <- aggregate_by_key(new)

common_cols_agg <- intersect(names(old_agg), names(new_agg))
measure_cols_agg <- setdiff(common_cols_agg, keys)

paired_agg <- inner_join(
  old_agg %>% select(all_of(keys), all_of(measure_cols_agg)),
  new_agg %>% select(all_of(keys), all_of(measure_cols_agg)),
  by = keys,
  suffix = c("_old", "_new")
)

changed_cells_agg <- purrr::map_dfr(measure_cols_agg, function(v) {
  x <- paired_agg[[paste0(v, "_old")]]
  y <- paired_agg[[paste0(v, "_new")]]
  is_num <- is.numeric(x) && is.numeric(y)

  changed <- if (is_num) {
    xor(is.na(x), is.na(y)) | (!is.na(x) & !is.na(y) & !dplyr::near(x, y))
  } else {
    xor(is.na(x), is.na(y)) | (!is.na(x) & !is.na(y) & (as.character(x) != as.character(y)))
  }

  tibble(
    fips_state = paired_agg$fips_state,
    fips_county = paired_agg$fips_county,
    year = paired_agg$year,
    var = v,
    old = as.character(x),
    new = as.character(y)
  ) %>% filter(changed)
})

changed_summary_agg <- changed_cells_agg %>% count(var, sort = TRUE)
safe_write(changed_cells_agg, "changed_cells_aggregated.csv")
safe_write(changed_summary_agg, "changed_cells_aggregated_summary.csv")

cat("\n--- Value changes (aggregated county-years) ---\n")
cat("Overlapping county-years eligible for aggregated compare: ", nrow(paired_agg), "\n", sep = "")
cat("Changed cells (aggregated): ", nrow(changed_cells_agg), "\n", sep = "")
if (nrow(changed_summary_agg) > 0) print(head(changed_summary_agg, 15))

# ============================================================
# 5) Headline metrics
# ============================================================
added_headlines <- tibble(
  metric = c(
    "added_county_years_total",
    "added_county_years_2024_2025",
    "added_county_years_backfill_<=2023",
    "dropped_county_years_total",
    "columns_only_in_2025",
    "columns_only_in_2023"
  ),
  value = c(
    nrow(added_keys),
    nrow(distinct(added_rows_2024_2025, across(all_of(keys)))),
    nrow(distinct(added_rows_backfill, across(all_of(keys)))),
    nrow(dropped_keys),
    nrow(schema_only_2025),
    nrow(schema_only_2023)
  )
)

safe_write(added_headlines, "headline_metrics.csv")

cat("\n--- Headline metrics ---\n")
print(added_headlines)

cat("\nDone. Outputs written to: ", normalizePath(out_dir), "\n", sep = "")
