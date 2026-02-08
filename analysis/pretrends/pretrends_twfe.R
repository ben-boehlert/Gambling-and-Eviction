#!/usr/bin/env Rscript
################################################################################
# pretrends_twfe.R
#
# TWFE event-study for pre-trends testing
# Simple, reliable alternative to CS-DiD when bootstrap SEs are problematic
#
# Uses identical env vars + panel build as other scripts in this project
################################################################################

# Force single-threaded to prevent conflicts/crashes
Sys.setenv(
  OMP_NUM_THREADS = "1",
  OPENBLAS_NUM_THREADS = "1",
  MKL_NUM_THREADS = "1",
  VECLIB_MAXIMUM_THREADS = "1",
  NUMEXPR_NUM_THREADS = "1"
)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
  library(tibble)
  library(ggplot2)
  library(fixest)
  library(fastDummies)
})

# ----------------------------- helpers ----------------------------------------

getenv1 <- function(key, default = "") {
  v <- Sys.getenv(key, unset = default)
  if (!nzchar(v)) default else v
}

parse_bool <- function(x, default = FALSE) {
  if (!nzchar(x)) return(default)
  x <- toupper(trimws(x))
  x %in% c("1","TRUE","T","YES","Y")
}

parse_num <- function(x, default = NA_real_) {
  if (!nzchar(x)) return(default)
  suppressWarnings(as.numeric(x))
}

parse_int <- function(x, default = NA_integer_) {
  if (!nzchar(x)) return(default)
  suppressWarnings(as.integer(x))
}

ym_index <- function(date) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
}

log_line <- function(path, msg) cat(msg, "\n", file = path, append = TRUE)

safe_write_csv <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(df, path)
}

parse_state_list <- function(x) {
  if (!nzchar(x)) return(character())
  parts <- strsplit(x, ",", fixed = TRUE)[[1]]
  trimws(parts)
}

# ----------------------------- config -----------------------------------------

# Core files
DATA_FILE  <- getenv1("DATA_FILE",  "combined_monthly_panel.csv")
TREAT_FILE <- getenv1("TREAT_FILE", "state_month_panel_with_treatment.csv")
OUT_DIR    <- getenv1("OUT_DIR",    "pretrends_twfe_out")

# Outcome specification
OUTCOME  <- getenv1("OUTCOME", "log1p_filings_count")
RATE_EPS <- parse_num(getenv1("RATE_EPS", "0.01"), 0.01)

# General settings
ALPHA <- parse_num(getenv1("ALPHA", "0.05"), 0.05)
SEED  <- parse_int(getenv1("SEED", "123"), 123L)
MIN_STATES_PER_MONTH <- parse_int(getenv1("MIN_STATES_PER_MONTH", "5"), 5L)
if (!is.finite(MIN_STATES_PER_MONTH) || MIN_STATES_PER_MONTH < 2L) MIN_STATES_PER_MONTH <- 2L

# Filtering
EXCLUDE_STATES_VEC <- parse_state_list(getenv1("EXCLUDE_STATES", ""))
MAX_DATE <- as.Date(getenv1("MAX_DATE", ""))
DROP_START <- as.Date(getenv1("DROP_START", ""))
DROP_END   <- as.Date(getenv1("DROP_END", ""))

# Event window
MIN_E <- parse_int(getenv1("MIN_E", "-24"), -24L)
MAX_E <- parse_int(getenv1("MAX_E", "24"), 24L)
BALANCE_E <- parse_int(getenv1("BALANCE_E", ""), NA_integer_)

# TWFE settings
BINNED_ENDPOINTS <- parse_bool(getenv1("BINNED_ENDPOINTS", "FALSE"), FALSE)

# Set seed
if (is.finite(SEED)) set.seed(SEED)

# Initialize log
RUN_LOG <- file.path(OUT_DIR, "run_pretrends_twfe.log")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
if (file.exists(RUN_LOG)) file.remove(RUN_LOG)

# ----------------------------- header -----------------------------------------

header <- glue("
=== TWFE PRE-TRENDS DIAGNOSTICS ===
WD: {getwd()}
R: {R.version.string}
DATA_FILE: {DATA_FILE}
TREAT_FILE: {TREAT_FILE}
OUT_DIR: {OUT_DIR}
OUTCOME: {OUTCOME}  RATE_EPS={RATE_EPS}
ALPHA: {ALPHA}  SEED: {SEED}
FILTERS: EXCLUDE_STATES={ifelse(length(EXCLUDE_STATES_VEC) > 0, paste(EXCLUDE_STATES_VEC, collapse=','), 'none')}  MAX_DATE={ifelse(is.na(MAX_DATE), 'none', as.character(MAX_DATE))}
DROP (analysis panel): {ifelse(is.na(DROP_START) || is.na(DROP_END), 'none', glue('{DROP_START} to {DROP_END}'))}
MIN_STATES_PER_MONTH (diagnostic threshold): {MIN_STATES_PER_MONTH}
Event window: MIN_E={MIN_E}, MAX_E={MAX_E}, BALANCE_E={ifelse(is.na(BALANCE_E), 'none', BALANCE_E)}
BINNED_ENDPOINTS: {BINNED_ENDPOINTS}
===========================
")

cat(header)
log_line(RUN_LOG, header)

# ----------------------------- fail-fast checks -------------------------------

if (!file.exists(DATA_FILE)) {
  msg <- glue("ERROR: DATA_FILE not found: {DATA_FILE}")
  log_line(RUN_LOG, msg)
  stop(msg)
}

if (!file.exists(TREAT_FILE)) {
  msg <- glue("ERROR: TREAT_FILE not found: {TREAT_FILE}")
  log_line(RUN_LOG, msg)
  stop(msg)
}

log_line(RUN_LOG, "Fail-fast checks passed.")
cat("Fail-fast checks passed.\n")

# ----------------------------- panel construction helpers ----------------------

state_abbr_from_geoid <- function(geo_id) {
  x <- tolower(trimws(as.character(geo_id)))
  key <- gsub("[^a-z]", "", x)
  name_key <- gsub("[^a-z]", "", tolower(state.name))
  m <- setNames(state.abb, name_key)
  unname(m[key])
}

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
    ) %>%
    mutate(
      filings_per_1k_renters = if_else(
        is.finite(renter_occupied_housing_units) & renter_occupied_housing_units > 0,
        1000 * filings_count / renter_occupied_housing_units,
        as.numeric(NA)
      )
    )

  county_states <- unique(county_state$state_abb)

  state_fallback <- df %>%
    filter(geo_level == "state") %>%
    transmute(
      state_abb = state_abbr_from_geoid(geo_id),
      month_date = as.Date(month_date),
      filings_count = as.numeric(filings_count),
      renter_occupied_housing_units = as.numeric(renter_occupied_housing_units),
      filings_per_1k_renters = as.numeric(filings_per_1k_renters)
    ) %>%
    filter(!is.na(state_abb), !is.na(month_date)) %>%
    filter(!(state_abb %in% county_states))

  bind_rows(county_state, state_fallback) %>%
    arrange(state_abb, month_date)
}

in_window <- function(d, start, end) {
  if (is.na(start) || is.na(end)) return(rep(FALSE, length(d)))
  (d >= start) & (d < end)
}

# ----------------------------- load data --------------------------------------

log_line(RUN_LOG, "Loading data...")
df_all <- readr::read_csv(DATA_FILE, show_col_types = FALSE)
panel_raw <- build_state_panel(df_all)

treat <- readr::read_csv(TREAT_FILE, show_col_types = FALSE) %>%
  transmute(
    state_abb = as.character(state_abb),
    month_date = as.Date(month_date),
    treat_start = as.Date(treat_start),
    treated = as.logical(treated)
  ) %>%
  arrange(state_abb, month_date)

panel <- panel_raw %>%
  left_join(treat, by = c("state_abb","month_date")) %>%
  filter(state_abb %in% unique(treat$state_abb))

if (length(EXCLUDE_STATES_VEC) > 0) panel <- panel %>% filter(!state_abb %in% EXCLUDE_STATES_VEC)
if (is.finite(MAX_DATE)) panel <- panel %>% filter(month_date <= MAX_DATE)

if (!is.na(DROP_START) && !is.na(DROP_END)) {
  panel <- panel %>% filter(!in_window(month_date, DROP_START, DROP_END))
}

# One adoption date per state
panel <- panel %>%
  group_by(state_abb) %>%
  mutate(treat_start_state = if (all(is.na(treat_start))) as.Date(NA) else min(treat_start, na.rm = TRUE)) %>%
  ungroup()

panel <- panel %>%
  mutate(
    t = ym_index(month_date),
    g = ifelse(is.na(treat_start_state), 0L, ym_index(treat_start_state)),
    g = as.integer(g),
    id = as.integer(as.factor(state_abb)),
    e = if_else(g > 0L, as.integer(t - g), NA_integer_),
    post_treat = (g > 0L) & (t >= g)
  )

# Construct outcome variable
if (OUTCOME == "log1p_filings_count") {
  panel <- panel %>% mutate(y = log1p(pmax(as.numeric(filings_count), 0)))
} else if (OUTCOME == "log1p_rate") {
  panel <- panel %>% mutate(y = log(pmax(as.numeric(filings_per_1k_renters), 0) + RATE_EPS))
} else {
  stop(glue("Unknown OUTCOME: {OUTCOME}"))
}

set.seed(SEED)

# Balance event time if specified
if (is.finite(BALANCE_E)) {
  panel <- panel %>% filter(is.na(e) | (e >= BALANCE_E & e <= MAX_E))
}

# Filter to event window
panel <- panel %>% filter(is.na(e) | (e >= MIN_E & e <= MAX_E))

# Remove rows with missing outcome
panel <- panel %>% filter(!is.na(y))

log_line(RUN_LOG, glue("Panel constructed: {nrow(panel)} rows"))

# ----------------------------- panel summary ----------------------------------

panel_summary <- tibble(
  n_states = n_distinct(panel$id),
  n_months = n_distinct(panel$t),
  n_rows = nrow(panel),
  min_date = as.character(min(panel$month_date, na.rm = TRUE)),
  max_date = as.character(max(panel$month_date, na.rm = TRUE)),
  n_never_treated = n_distinct(panel$id[panel$g == 0]),
  n_switchers = n_distinct(panel$id[panel$g > 0])
)

safe_write_csv(panel_summary, file.path(OUT_DIR, "panel_summary.csv"))
log_line(RUN_LOG, glue("Panel summary: {panel_summary$n_states} states, {panel_summary$n_months} months, {panel_summary$n_rows} rows"))
log_line(RUN_LOG, glue("  Never-treated: {panel_summary$n_never_treated}, Switchers: {panel_summary$n_switchers}"))

# ----------------------------- cohort diagnostics -----------------------------

cohort_sizes <- panel %>%
  filter(g > 0) %>%
  group_by(g) %>%
  summarize(
    n_units = n_distinct(id),
    first_period = min(t, na.rm = TRUE),
    n_pre_periods = sum(e < 0, na.rm = TRUE) / n_distinct(id),
    .groups = "drop"
  ) %>%
  arrange(g)

safe_write_csv(cohort_sizes, file.path(OUT_DIR, "cohort_sizes.csv"))
log_line(RUN_LOG, glue("Cohort sizes written: {nrow(cohort_sizes)} cohorts"))

# ----------------------------- support diagnostics ----------------------------

untreated_support_by_month <- panel %>%
  group_by(month_date, t) %>%
  summarise(
    n_total = n_distinct(id),
    n_untreated = n_distinct(id[g == 0]),
    n_treated = n_distinct(id[g > 0]),
    n_post_treat = n_distinct(id[post_treat]),
    .groups = "drop"
  ) %>%
  arrange(month_date)

safe_write_csv(untreated_support_by_month, file.path(OUT_DIR, "untreated_support_by_month.csv"))

support_by_event_time <- panel %>%
  filter(!is.na(e)) %>%
  group_by(e) %>%
  summarise(
    n_obs = n(),
    n_states_treated = n_distinct(id),
    n_control_states = n_distinct(id[g == 0]),
    .groups = "drop"
  ) %>%
  arrange(e)

safe_write_csv(support_by_event_time, file.path(OUT_DIR, "support_by_event_time.csv"))
log_line(RUN_LOG, "Support diagnostics written.")

# ----------------------------- TWFE event study -------------------------------

log_line(RUN_LOG, "Running TWFE event-study regression...")
cat("Running TWFE event-study regression...\n")

# Create event-time dummies for the full panel
# For never-treated units (g==0), all event-time dummies will be zero
# For treated units, create indicators for each event time

# Get unique event times from treated units
event_times_all <- panel %>% filter(!is.na(e)) %>% pull(e) %>% unique() %>% sort()
event_times_use <- event_times_all[event_times_all != -1]  # Omit reference period

if (length(event_times_use) == 0) {
  log_line(RUN_LOG, "ERROR: No event times available")
  stop("No event times available")
}

log_line(RUN_LOG, glue("Using saturated specification (no binned endpoints)"))
log_line(RUN_LOG, glue("Event times: {paste(event_times_use, collapse=', ')}"))

# Create event-time dummies manually for full panel
# For each event time, create indicator: 1 if unit i at time t has e==event_time, 0 otherwise
for (et in event_times_use) {
  col_name <- paste0("lead_", et)
  panel[[col_name]] <- as.integer(!is.na(panel$e) & panel$e == et)
}

# Build formula
# Need backticks around variables with negative numbers
dummy_cols <- paste0("lead_", event_times_use)
dummy_cols_quoted <- paste0("`", dummy_cols, "`")
dummy_formula <- paste(dummy_cols_quoted, collapse = " + ")
formula_str <- glue("y ~ {dummy_formula} | id + t")

log_line(RUN_LOG, glue("TWFE formula: {formula_str}"))
log_line(RUN_LOG, glue("Number of coefficients: {length(event_times_use)}"))

# Run TWFE regression with clustered SEs
twfe_mod <- fixest::feols(
  as.formula(formula_str),
  data = panel,  # Use full panel including control units
  cluster = ~id
)

# Extract coefficients
twfe_coefs <- tibble(
  term = names(coef(twfe_mod)),
  estimate = as.numeric(coef(twfe_mod)),
  se = as.numeric(se(twfe_mod)),
  t_stat = estimate / se,
  p_value = 2 * pt(abs(t_stat), df = twfe_mod$nobs - length(coef(twfe_mod)), lower.tail = FALSE)
)

# Extract event times from term names
# Remove backticks and "lead_" prefix to get event time
twfe_coefs <- twfe_coefs %>%
  mutate(
    term_clean = gsub("`", "", term),          # Remove backticks
    term_clean = gsub("lead_", "", term_clean), # Remove prefix
    e = as.integer(term_clean),                 # Convert to integer
    lo = estimate - qnorm(1 - ALPHA/2) * se,
    hi = estimate + qnorm(1 - ALPHA/2) * se
  ) %>%
  select(e, estimate, se, t_stat, p_value, lo, hi) %>%
  arrange(e)

safe_write_csv(twfe_coefs, file.path(OUT_DIR, "twfe_event_study.csv"))
log_line(RUN_LOG, glue("TWFE event study written: {nrow(twfe_coefs)} coefficients"))
cat(glue("TWFE event study written: {nrow(twfe_coefs)} coefficients\n"))

# ----------------------------- pre-trends joint test --------------------------

log_line(RUN_LOG, "Computing TWFE pre-trends joint F-test...")
cat("Computing TWFE pre-trends joint F-test...\n")

# Get pre-treatment coefficients (e < 0)
pre_event_times <- twfe_coefs %>%
  filter(e < 0) %>%
  pull(e)

if (length(pre_event_times) == 0) {
  log_line(RUN_LOG, "WARNING: No pre-treatment coefficients to test")
  cat("WARNING: No pre-treatment coefficients to test\n")

  pretrends_test <- tibble(
    ok = FALSE,
    method = "F-test on pre-treatment coefficients",
    n_leads = 0,
    f_stat = NA_real_,
    df1 = NA_integer_,
    df2 = NA_integer_,
    p_value = NA_real_
  )
} else {
  # Get pre-treatment coefficient names
  pre_terms <- paste0("lead_", pre_event_times)

  # Build joint test hypothesis
  # H0: all pre-treatment coefficients are zero
  # Using fixest::wald() for joint test

  tryCatch({
    wald_result <- fixest::wald(twfe_mod, keep = pre_terms)

    pretrends_test <- tibble(
      ok = TRUE,
      method = "F-test on pre-treatment coefficients",
      n_leads = length(pre_event_times),
      f_stat = wald_result$stat,
      df1 = wald_result$df1,
      df2 = wald_result$df2,
      p_value = wald_result$p
    )

    log_line(RUN_LOG, glue("Pre-trends F-test: F({wald_result$df1}, {wald_result$df2}) = {round(wald_result$stat, 3)}, p = {round(wald_result$p, 4)}"))
    cat(glue("Pre-trends F-test: F({wald_result$df1}, {wald_result$df2}) = {round(wald_result$stat, 3)}, p = {round(wald_result$p, 4)}\n"))

    if (wald_result$p < ALPHA) {
      log_line(RUN_LOG, glue("  REJECT null of parallel trends at α={ALPHA}"))
      cat(glue("  ⚠ REJECT null of parallel trends at α={ALPHA}\n"))
    } else {
      log_line(RUN_LOG, glue("  FAIL TO REJECT null of parallel trends at α={ALPHA}"))
      cat(glue("  ✓ FAIL TO REJECT null of parallel trends at α={ALPHA}\n"))
    }
  }, error = function(e) {
    log_line(RUN_LOG, glue("ERROR computing joint F-test: {e$message}"))
    cat(glue("ERROR computing joint F-test: {e$message}\n"))

    pretrends_test <<- tibble(
      ok = FALSE,
      method = "F-test on pre-treatment coefficients",
      n_leads = length(pre_event_times),
      f_stat = NA_real_,
      df1 = NA_integer_,
      df2 = NA_integer_,
      p_value = NA_real_
    )
  })
}

safe_write_csv(pretrends_test, file.path(OUT_DIR, "twfe_pretrends_joint_test.csv"))

# ----------------------------- event study plot -------------------------------

log_line(RUN_LOG, "Creating TWFE event-study plot...")
cat("Creating TWFE event-study plot...\n")

# Add reference period (e = -1) with estimate = 0
plot_data <- twfe_coefs %>%
  bind_rows(
    tibble(
      e = -1L,
      estimate = 0,
      se = 0,
      t_stat = NA_real_,
      p_value = NA_real_,
      lo = 0,
      hi = 0
    )
  ) %>%
  arrange(e)

p <- ggplot(plot_data, aes(x = e, y = estimate)) +
  geom_point(size = 2) +
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.2) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
  geom_vline(xintercept = -0.5, linetype = "dotted", color = "gray40") +
  labs(
    title = "TWFE Event Study",
    subtitle = glue("Pre-trends test: F({pretrends_test$df1}, {pretrends_test$df2}) = {round(pretrends_test$f_stat, 2)}, p = {round(pretrends_test$p_value, 3)}"),
    x = "Event Time (months relative to treatment)",
    y = glue("Treatment Effect ({OUTCOME})")
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 10)
  )

ggsave(
  file.path(OUT_DIR, "twfe_event_study.png"),
  plot = p,
  width = 10,
  height = 6,
  dpi = 300
)

log_line(RUN_LOG, "TWFE event-study plot saved.")

# ----------------------------- diagnostic summary -----------------------------

diagnostic_summary <- tibble(
  test = "TWFE event study",
  completed = TRUE,
  n_coefficients = nrow(twfe_coefs),
  n_pre_periods = sum(twfe_coefs$e < 0),
  pre_trends_test_p = pretrends_test$p_value,
  reject_parallel_trends = ifelse(is.na(pretrends_test$p_value), NA, pretrends_test$p_value < ALPHA)
)

safe_write_csv(diagnostic_summary, file.path(OUT_DIR, "diagnostic_summary.csv"))

# ----------------------------- completion -------------------------------------

log_line(RUN_LOG, "=========================== ")
log_line(RUN_LOG, "DIAGNOSTICS COMPLETE")
log_line(RUN_LOG, glue("Outputs written to: {OUT_DIR}"))

cat("=========================== \n")
cat("DIAGNOSTICS COMPLETE\n")
cat(glue("Outputs written to: {OUT_DIR}\n"))
cat("\n")
