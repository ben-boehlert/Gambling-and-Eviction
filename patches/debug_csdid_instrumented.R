#!/usr/bin/env Rscript
################################################################################
# debug_csdid_instrumented.R
#
# Instrumented debug script to catch empty matrix issue BEFORE segfault
# Instruments did/DRDID/fastglm calls to detect and report problematic (g,t) cells
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
})

cat("=================================================================\n")
cat("CS-DiD Instrumented Debug - Empty Matrix Detection\n")
cat("=================================================================\n\n")

# 1. Load and prepare data (same as debug_csdid.R)
# -------------------------------------------------

fips_to_state_abb <- function(state_fips) {
  lookup <- c(
    `1`="AL", `2`="AK", `4`="AZ", `5`="AR", `6`="CA", `8`="CO", `9`="CT",
    `10`="DE", `11`="DC", `12`="FL", `13`="GA", `15`="HI", `16`="ID",
    `17`="IL", `18`="IN", `19`="IA", `20`="KS", `21`="KY", `22`="LA",
    `23`="ME", `24`="MD", `25`="MA", `26`="MI", `27`="MN", `28`="MS",
    `29`="MO", `30`="MT", `31`="NE", `32`="NV", `33`="NH", `34`="NJ",
    `35`="NM", `36`="NY", `37`="NC", `38`="ND", `39`="OH", `40`="OK",
    `41`="OR", `42`="PA", `44`="RI", `45`="SC", `46`="SD", `47`="TN",
    `48`="TX", `49`="UT", `50`="VT", `51`="VA", `53`="WA", `54`="WV",
    `55`="WI", `56`="WY"
  )
  unname(lookup[as.character(as.integer(state_fips))])
}

state_name_to_abb <- function(state_name) {
  state_name <- trimws(state_name)
  m <- setNames(state.abb, state.name)
  m2 <- c(m, "District of Columbia" = "DC")
  unname(m2[state_name])
}

state_abbr_from_geoid <- function(geo_id) {
  x <- tolower(trimws(as.character(geo_id)))
  key <- gsub("[^a-z]", "", x)
  name_key <- gsub("[^a-z]", "", tolower(state.name))
  m <- setNames(state.abb, name_key)
  unname(m[key])
}

ym_index <- function(date) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
}

build_state_panel <- function(df) {
  county_state <- df %>%
    filter(geo_level == "county") %>%
    mutate(
      fips_num = suppressWarnings(as.integer(fips)),
      state_fips = as.integer(floor(fips_num / 1000)),
      state_abb = fips_to_state_abb(state_fips),
      month_date = as.Date(month_date),
      filings_count = as.numeric(filings_count),
      renter_occupied_housing_units = as.numeric(renter_occupied_housing_units)
    ) %>%
    filter(!is.na(state_abb), !is.na(month_date)) %>%
    group_by(state_abb, month_date) %>%
    summarise(
      filings_count = sum(filings_count, na.rm = TRUE),
      renter_occupied_housing_units = sum(renter_occupied_housing_units, na.rm = TRUE),
      .groups = "drop"
    )

  county_states <- unique(county_state$state_abb)

  state_fallback <- df %>%
    filter(geo_level == "state") %>%
    transmute(
      state_abb = state_abbr_from_geoid(geo_id),
      month_date = as.Date(month_date),
      filings_count = as.numeric(filings_count),
      renter_occupied_housing_units = as.numeric(renter_occupied_housing_units)
    ) %>%
    filter(!is.na(state_abb), !is.na(month_date)) %>%
    filter(!(state_abb %in% county_states))

  bind_rows(county_state, state_fallback) %>%
    arrange(state_abb, month_date)
}

cat("Loading data...\n")
df_all <- readr::read_csv("data/raw/combined_monthly_panel.csv", show_col_types = FALSE)
gambling_raw <- readr::read_csv("data/raw/sports_gambling_legalization_dates.csv", show_col_types = FALSE)

panel_raw <- build_state_panel(df_all)

gambling_dates <- gambling_raw %>%
  mutate(
    state_abb = state_name_to_abb(state),
    online_start_date = as.Date(online_start_date, format = "%Y-%m-%d")
  ) %>%
  select(state_abb, online_start_date) %>%
  filter(!is.na(state_abb))

panel <- panel_raw %>%
  left_join(gambling_dates, by = "state_abb") %>%
  filter(state_abb != "ME") %>%
  mutate(
    t = ym_index(month_date),
    g = ifelse(is.na(online_start_date), 0L, ym_index(online_start_date)),
    g = as.integer(g),
    e = if_else(g > 0L, as.integer(t - g), NA_integer_),
    y = log1p(pmax(as.numeric(filings_count), 0))
  ) %>%
  filter(is.na(e) | (e >= -12 & e <= 24)) %>%
  filter(!is.na(y))

panel_cs <- panel %>%
  mutate(
    gname = if_else(g > 0, as.integer(g), 0L),
    year = as.integer(t),
    id = as.integer(as.factor(state_abb))
  ) %>%
  select(id, state_abb, year, gname, y) %>%
  filter(!is.na(y), !is.na(gname), !is.na(year))

cat(glue("\nPanel prepared: {nrow(panel_cs)} obs, {n_distinct(panel_cs$id)} units, {n_distinct(panel_cs$year)} periods\n"))
cat(glue("Treatment groups: {paste(sort(unique(panel_cs$gname[panel_cs$gname > 0])), collapse=', ')}\n\n"))

# 2. Compute support diagnostics for EVERY (g,t) combination
# -----------------------------------------------------------

cat("=================================================================\n")
cat("STEP 1: Computing support diagnostics for all (g,t) cells\n")
cat("=================================================================\n\n")

compute_support_diagnostics <- function(data, g_val, t_val) {
  # Replicate CS-DiD comparison logic

  treated_units <- unique(data$id[data$gname == g_val])
  control_units <- unique(data$id[data$gname == 0])

  # Pre-treatment period (typically one period before g)
  pre_t <- g_val - 1

  # Treated units at pre and post
  n_treat_pre <- nrow(data[data$id %in% treated_units & data$year == pre_t & !is.na(data$y), ])
  n_treat_post <- nrow(data[data$id %in% treated_units & data$year == t_val & !is.na(data$y), ])

  # Control units at pre and post
  n_control_pre <- nrow(data[data$id %in% control_units & data$year == pre_t & !is.na(data$y), ])
  n_control_post <- nrow(data[data$id %in% control_units & data$year == t_val & !is.na(data$y), ])

  # Total observations that would be used for this (g,t)
  n_total <- n_treat_pre + n_treat_post + n_control_pre + n_control_post

  # Check identifiability
  identifiable <- (n_treat_pre > 0) & (n_treat_post > 0) & (n_control_pre > 0) & (n_control_post > 0)

  reason <- if (!identifiable) {
    parts <- c()
    if (n_treat_pre == 0) parts <- c(parts, "n_treat_pre=0")
    if (n_treat_post == 0) parts <- c(parts, "n_treat_post=0")
    if (n_control_pre == 0) parts <- c(parts, "n_control_pre=0")
    if (n_control_post == 0) parts <- c(parts, "n_control_post=0")
    paste(parts, collapse=", ")
  } else {
    NA_character_
  }

  data.frame(
    g = g_val,
    t = t_val,
    n_treat_pre = n_treat_pre,
    n_treat_post = n_treat_post,
    n_control_pre = n_control_pre,
    n_control_post = n_control_post,
    n_total = n_total,
    identifiable = identifiable,
    reason = reason,
    stringsAsFactors = FALSE
  )
}

# Get all treatment groups and times
g_vals <- sort(unique(panel_cs$gname[panel_cs$gname > 0]))
t_vals <- sort(unique(panel_cs$year))

# Compute diagnostics for all (g,t) where t >= g
support_table <- do.call(rbind, lapply(g_vals, function(g_val) {
  do.call(rbind, lapply(t_vals[t_vals >= g_val], function(t_val) {
    compute_support_diagnostics(panel_cs, g_val, t_val)
  }))
}))

cat("Support table for all ATT(g,t) comparisons:\n\n")
print(support_table)

# Count problems
n_problematic <- sum(!support_table$identifiable)
cat(glue("\n\nSUMMARY: {n_problematic} out of {nrow(support_table)} (g,t) cells are NOT IDENTIFIABLE\n\n"))

if (n_problematic > 0) {
  cat("Problematic cells:\n")
  print(support_table[!support_table$identifiable, ])
  cat("\n")
}

# Save diagnostics
dir.create("output/csdid_debug", showWarnings = FALSE, recursive = TRUE)
write.csv(support_table, "output/csdid_debug/support_diagnostics_full.csv", row.names = FALSE)
cat("Support diagnostics saved to: output/csdid_debug/support_diagnostics_full.csv\n\n")

# 3. Instrument fastglm to detect empty model matrices
# -----------------------------------------------------

cat("=================================================================\n")
cat("STEP 2: Installing fastglm guard to detect empty matrices\n")
cat("=================================================================\n\n")

if (!requireNamespace("fastglm", quietly = TRUE)) {
  cat("fastglm package not installed. Skipping guard installation.\n")
} else {
  library(fastglm)

  # Create a wrapped version of fastglm that checks for empty/degenerate input
  original_fastglm <- fastglm::fastglm

  fastglm_guarded <- function(x, y, family = gaussian(), ...) {
    # Check for empty or degenerate design matrix
    if (is.matrix(x)) {
      if (nrow(x) == 0) {
        stop(glue::glue(
          "GUARD TRIGGERED: fastglm called with EMPTY design matrix (0 rows).\n",
          "This indicates a (g,t) cell with no observations.\n",
          "Stack trace will show which (g,t) caused this."
        ))
      }
      if (ncol(x) == 0) {
        stop(glue::glue(
          "GUARD TRIGGERED: fastglm called with design matrix with 0 columns.\n"
        ))
      }
      if (any(!is.finite(x))) {
        warning("fastglm called with non-finite values in design matrix")
      }
    }

    if (length(y) == 0) {
      stop(glue::glue(
        "GUARD TRIGGERED: fastglm called with EMPTY outcome vector (length 0).\n"
      ))
    }

    if (is.matrix(x) && nrow(x) != length(y)) {
      stop(glue::glue(
        "GUARD TRIGGERED: fastglm called with mismatched dimensions: nrow(x)={nrow(x)}, length(y)={length(y)}\n"
      ))
    }

    # If checks pass, call original function
    original_fastglm(x = x, y = y, family = family, ...)
  }

  # Replace in namespace (this is hacky but works for debugging)
  assignInNamespace("fastglm", fastglm_guarded, ns = "fastglm")
  cat("fastglm guard installed. Any empty matrix calls will now trigger an informative error.\n\n")
}

# 4. Attempt CS-DiD estimation with instrumentation
# --------------------------------------------------

cat("=================================================================\n")
cat("STEP 3: Attempting CS-DiD estimation with guards in place\n")
cat("=================================================================\n\n")

if (!requireNamespace("did", quietly = TRUE)) {
  cat("did package not installed. Cannot proceed with CS-DiD.\n")
  quit(status = 1)
}

library(did)

cat("Calling did::att_gt() with full panel...\n\n")

tryCatch({
  att_result <- did::att_gt(
    yname = "y",
    tname = "year",
    idname = "id",
    gname = "gname",
    data = as.data.frame(panel_cs),
    control_group = "nevertreated",
    clustervars = "id",
    est_method = "reg",
    base_period = "universal",
    anticipation = 0,
    bstrap = FALSE,
    cband = FALSE,
    panel = FALSE,
    print_details = TRUE  # Enable to see progress
  )

  cat("\n=================================================================\n")
  cat("SUCCESS: CS-DiD completed without error!\n")
  cat("=================================================================\n\n")

  cat("Summary:\n")
  print(summary(att_result))

  # Check if any ATTs are NA
  na_count <- sum(is.na(att_result$att))
  cat(glue("\n\nATTs with NA: {na_count} out of {length(att_result$att)}\n"))

  if (na_count > 0) {
    cat("\nCells with NA ATT:\n")
    na_cells <- data.frame(
      group = att_result$group[is.na(att_result$att)],
      time = att_result$t[is.na(att_result$att)]
    )
    print(na_cells)
  }

}, error = function(e) {
  cat("\n=================================================================\n")
  cat("ERROR CAUGHT:\n")
  cat("=================================================================\n")
  cat(conditionMessage(e), "\n\n")

  cat("Stack trace:\n")
  print(sys.calls())

  cat("\n\nThis error occurred during CS-DiD estimation.\n")
  cat("Check the support_diagnostics table above to see which (g,t) cells have zero observations.\n")
})

cat("\n=================================================================\n")
cat("INSTRUMENTED DEBUG COMPLETE\n")
cat("=================================================================\n")
