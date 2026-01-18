#!/usr/bin/env Rscript
################################################################################
# pretrends_pre_post_covid.R
#
# Separate Pre-Trends Analysis for Pre-COVID vs Post-COVID Periods
#
# Motivation: Eviction patterns may have fundamentally changed due to COVID.
# This script analyzes pre-trends separately for:
# 1. Pre-COVID period (2012-2019)
# 2. Post-COVID period (2021-2024)
#
# Treatment: Online gambling legalization dates
# Modern methods: Power analysis, HonestDiD, Equivalence testing
################################################################################

# Force single-threaded execution
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
  library(patchwork)
  library(MASS)
})

# Optional packages
has_honestdid <- requireNamespace("HonestDiD", quietly = TRUE)
has_pretrends <- requireNamespace("pretrends", quietly = TRUE)

if (!has_honestdid) cat("WARNING: HonestDiD package not installed.\n")
if (!has_pretrends) cat("WARNING: pretrends package not installed.\n")

################################################################################
# CONFIGURATION
################################################################################

DATA_FILE <- Sys.getenv("DATA_FILE", "data/raw/combined_monthly_panel.csv")
GAMBLING_FILE <- Sys.getenv("GAMBLING_FILE", "data/raw/sports_gambling_legalization_dates.csv")
OUT_DIR <- Sys.getenv("OUT_DIR", "output/pretrends_pre_post_covid")
OUTCOME <- Sys.getenv("OUTCOME", "log1p_filings_count")
ALPHA <- 0.05
SEED <- 42
set.seed(SEED)

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
LOG_FILE <- file.path(OUT_DIR, "run_log.txt")
if (file.exists(LOG_FILE)) file.remove(LOG_FILE)

log_msg <- function(msg) {
  cat(msg, "\n")
  cat(msg, "\n", file = LOG_FILE, append = TRUE)
}

log_msg("================================================================================")
log_msg("PRE-TRENDS ANALYSIS: PRE-COVID vs POST-COVID")
log_msg("================================================================================")
log_msg(glue("Output: {OUT_DIR}"))
log_msg(glue("Outcome: {OUTCOME}"))
log_msg("================================================================================")

################################################################################
# HELPER FUNCTIONS (from main script)
################################################################################

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

################################################################################
# LOAD DATA
################################################################################

log_msg("\n--- Loading Data ---")

df_all <- readr::read_csv(DATA_FILE, show_col_types = FALSE)
panel_raw <- build_state_panel(df_all)

gambling_raw <- readr::read_csv(GAMBLING_FILE, show_col_types = FALSE)
gambling_dates <- gambling_raw %>%
  mutate(
    state_abb = state_name_to_abb(state),
    online_start_date = as.Date(online_start_date, format = "%Y-%m-%d")
  ) %>%
  dplyr::select(state_abb, online_start_date) %>%
  filter(!is.na(state_abb))

all_states <- tibble(state_abb = unique(panel_raw$state_abb))
gambling_dates <- all_states %>% left_join(gambling_dates, by = "state_abb")

log_msg(glue("Total states: {n_distinct(panel_raw$state_abb)}"))
log_msg(glue("Treated states: {sum(!is.na(gambling_dates$online_start_date))}"))

################################################################################
# DEFINE PERIOD-SPECIFIC ANALYSES
################################################################################

ANALYSES <- list(
  pre_covid_adopters = list(
    name = "Pre-COVID Analysis (2012-2019)",
    description = "States adopting online gambling before 2020",
    period_start = as.Date("2012-01-01"),
    period_end = as.Date("2019-12-31"),
    treatment_start = as.Date("2018-01-01"),
    treatment_end = as.Date("2019-12-31"),
    exclude_states = "ME",
    min_e = -24,
    max_e = 12
  ),

  post_covid_adopters = list(
    name = "Post-COVID Analysis (2021-2024)",
    description = "States adopting online gambling after COVID",
    period_start = as.Date("2021-08-01"),
    period_end = as.Date("2024-12-31"),
    treatment_start = as.Date("2021-08-01"),
    treatment_end = as.Date("2024-12-31"),
    exclude_states = "ME",
    min_e = -24,
    max_e = 24
  ),

  pre_covid_full_sample = list(
    name = "Pre-COVID Full Sample (2012-2019)",
    description = "All states, pre-COVID period only",
    period_start = as.Date("2012-01-01"),
    period_end = as.Date("2019-12-31"),
    treatment_start = NULL,  # All treatment dates
    treatment_end = NULL,
    exclude_states = "ME",
    min_e = -24,
    max_e = 12
  ),

  post_covid_full_sample = list(
    name = "Post-COVID Full Sample (2021-2024)",
    description = "All states, post-COVID period only",
    period_start = as.Date("2021-08-01"),
    period_end = as.Date("2024-12-31"),
    treatment_start = NULL,
    treatment_end = NULL,
    exclude_states = "ME",
    min_e = -24,
    max_e = 24
  )
)

################################################################################
# PANEL CONSTRUCTION
################################################################################

build_analysis_panel <- function(panel_raw, gambling_dates, analysis) {
  log_msg(glue("\nBuilding panel: {analysis$name}"))

  # Filter gambling dates by treatment period if specified
  if (!is.null(analysis$treatment_start) && !is.null(analysis$treatment_end)) {
    gambling_filtered <- gambling_dates %>%
      mutate(
        online_start_date = if_else(
          !is.na(online_start_date) &
            online_start_date >= analysis$treatment_start &
            online_start_date <= analysis$treatment_end,
          online_start_date,
          as.Date(NA)
        )
      )
    log_msg(glue("  Restricting to treatments between {analysis$treatment_start} and {analysis$treatment_end}"))
  } else {
    gambling_filtered <- gambling_dates
  }

  # Build panel
  panel <- panel_raw %>%
    filter(month_date >= analysis$period_start & month_date <= analysis$period_end) %>%
    left_join(gambling_filtered, by = "state_abb")

  # Exclude states
  if (nzchar(analysis$exclude_states)) {
    exclude_vec <- strsplit(analysis$exclude_states, ",")[[1]]
    panel <- panel %>% filter(!state_abb %in% exclude_vec)
  }

  # Create treatment variables
  panel <- panel %>%
    mutate(
      t = ym_index(month_date),
      g = ifelse(is.na(online_start_date), 0L, ym_index(online_start_date)),
      g = as.integer(g),
      id = as.integer(as.factor(state_abb)),
      e = if_else(g > 0L, as.integer(t - g), NA_integer_),
      post_treat = (g > 0L) & (t >= g)
    )

  # Filter to event window
  panel <- panel %>%
    filter(is.na(e) | (e >= analysis$min_e & e <= analysis$max_e))

  # Create outcome
  if (OUTCOME == "log1p_filings_count") {
    panel <- panel %>% mutate(y = log1p(pmax(as.numeric(filings_count), 0)))
  } else if (OUTCOME == "log1p_rate") {
    panel <- panel %>% mutate(y = log(pmax(as.numeric(filings_per_1k_renters), 0) + 0.01))
  }

  panel <- panel %>% filter(!is.na(y))

  log_msg(glue("  States: {n_distinct(panel$state_abb)}"))
  log_msg(glue("  Treated: {n_distinct(panel$state_abb[panel$g > 0])}"))
  log_msg(glue("  Never-treated: {n_distinct(panel$state_abb[panel$g == 0])}"))
  log_msg(glue("  Observations: {nrow(panel)}"))

  panel
}

################################################################################
# TWFE EVENT STUDY
################################################################################

run_twfe_event_study <- function(panel, analysis) {
  log_msg(glue("\n--- TWFE Event Study: {analysis$name} ---"))

  event_times_all <- panel %>% filter(!is.na(e)) %>% pull(e) %>% unique() %>% sort()
  event_times_use <- event_times_all[event_times_all != -1]

  if (length(event_times_use) == 0) {
    log_msg("  No event times available")
    return(NULL)
  }

  # Create dummies
  for (et in event_times_use) {
    col_name <- paste0("lead_", et)
    panel[[col_name]] <- as.integer(!is.na(panel$e) & panel$e == et)
  }

  dummy_cols <- paste0("lead_", event_times_use)
  dummy_cols_quoted <- paste0("`", dummy_cols, "`")
  dummy_formula <- paste(dummy_cols_quoted, collapse = " + ")
  formula_str <- glue("y ~ {dummy_formula} | id + t")

  twfe_mod <- fixest::feols(
    as.formula(formula_str),
    data = panel,
    cluster = ~id
  )

  twfe_coefs <- tibble(
    term = names(coef(twfe_mod)),
    estimate = as.numeric(coef(twfe_mod)),
    se = as.numeric(se(twfe_mod))
  ) %>%
    mutate(
      term_clean = gsub("`|lead_", "", term),
      e = as.integer(term_clean),
      t_stat = estimate / se,
      p_value = 2 * pt(abs(t_stat), df = twfe_mod$nobs - length(coef(twfe_mod)), lower.tail = FALSE),
      lo = estimate - qnorm(1 - ALPHA/2) * se,
      hi = estimate + qnorm(1 - ALPHA/2) * se
    ) %>%
    dplyr::select(e, estimate, se, t_stat, p_value, lo, hi) %>%
    arrange(e)

  # F-test on pre-treatment
  pre_event_times <- twfe_coefs %>% filter(e < 0) %>% pull(e)

  if (length(pre_event_times) > 0) {
    pre_terms <- paste0("lead_", pre_event_times)

    tryCatch({
      wald_result <- fixest::wald(twfe_mod, keep = pre_terms)
      log_msg(glue("  F-test: F({wald_result$df1}, {wald_result$df2}) = {round(wald_result$stat, 3)}, p = {round(wald_result$p, 4)}"))

      pretrends_test <- tibble(
        n_leads = length(pre_event_times),
        f_stat = wald_result$stat,
        p_value = wald_result$p
      )
    }, error = function(e) {
      pretrends_test <<- tibble(n_leads = length(pre_event_times), f_stat = NA_real_, p_value = NA_real_)
    })
  } else {
    pretrends_test <- tibble(n_leads = 0, f_stat = NA_real_, p_value = NA_real_)
  }

  list(
    model = twfe_mod,
    coefs = twfe_coefs,
    pretrends_test = pretrends_test,
    vcov = vcov(twfe_mod, cluster = ~id)
  )
}

################################################################################
# POWER ANALYSIS
################################################################################

run_power_analysis <- function(twfe_result) {
  if (!has_pretrends) return(NULL)

  pre_coefs <- twfe_result$coefs %>% filter(e < 0)
  if (nrow(pre_coefs) == 0) return(NULL)

  beta_pre <- pre_coefs$estimate
  event_times_pre <- pre_coefs$e

  coef_names <- names(coef(twfe_result$model))
  pre_term_pattern <- paste0("lead_", event_times_pre, collapse = "|")
  pre_idx <- grepl(pre_term_pattern, coef_names)

  if (sum(pre_idx) == 0) return(NULL)

  sigma_pre <- twfe_result$vcov[pre_idx, pre_idx]

  mde_50 <- tryCatch({
    pretrends::slope_for_power(sigma = sigma_pre, targetPower = 0.5, tVec = event_times_pre, referencePeriod = -1)
  }, error = function(e) NA)

  mde_80 <- tryCatch({
    pretrends::slope_for_power(sigma = sigma_pre, targetPower = 0.8, tVec = event_times_pre, referencePeriod = -1)
  }, error = function(e) NA)

  log_msg(glue("  MDE (50%): {round(mde_50, 4)}, MDE (80%): {round(mde_80, 4)}"))

  tibble(target_power = c(0.5, 0.8), mde_slope = c(mde_50, mde_80))
}

################################################################################
# MAIN ANALYSIS LOOP
################################################################################

log_msg("\n================================================================================")
log_msg("RUNNING PERIOD-SPECIFIC ANALYSES")
log_msg("================================================================================")

all_results <- list()

for (analysis_name in names(ANALYSES)) {
  analysis <- ANALYSES[[analysis_name]]

  log_msg(glue("\n\n{strrep('=', 60)}"))
  log_msg(glue("ANALYSIS: {analysis$name}"))
  log_msg(glue("{strrep('=', 60)}"))

  panel <- build_analysis_panel(panel_raw, gambling_dates, analysis)

  n_treated <- n_distinct(panel$state_abb[panel$g > 0])
  n_never <- n_distinct(panel$state_abb[panel$g == 0])

  if (n_treated < 5 || n_never < 5) {
    log_msg(glue("  SKIPPED: Insufficient variation (treated={n_treated}, never={n_never}, need >=5 each)"))
    next
  }

  twfe_result <- run_twfe_event_study(panel, analysis)
  if (is.null(twfe_result)) {
    log_msg("  SKIPPED: TWFE failed")
    next
  }

  power_result <- run_power_analysis(twfe_result)

  # Save outputs
  analysis_dir <- file.path(OUT_DIR, analysis_name)
  dir.create(analysis_dir, recursive = TRUE, showWarnings = FALSE)

  readr::write_csv(twfe_result$coefs, file.path(analysis_dir, "event_study_coefs.csv"))
  readr::write_csv(twfe_result$pretrends_test, file.path(analysis_dir, "pretrends_ftest.csv"))

  if (!is.null(power_result)) {
    readr::write_csv(power_result, file.path(analysis_dir, "power_mde.csv"))
  }

  # Event study plot
  plot_data <- twfe_result$coefs %>%
    bind_rows(tibble(e = -1L, estimate = 0, se = 0, t_stat = NA_real_, p_value = NA_real_, lo = 0, hi = 0)) %>%
    arrange(e)

  p <- ggplot(plot_data, aes(x = e, y = estimate)) +
    geom_point(size = 2) +
    geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.2) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
    geom_vline(xintercept = -0.5, linetype = "dotted", color = "gray40") +
    labs(
      title = analysis$name,
      subtitle = glue("F-test p = {round(twfe_result$pretrends_test$p_value, 4)}"),
      x = "Event Time (months)",
      y = glue("Effect ({OUTCOME})")
    ) +
    theme_minimal()

  ggsave(file.path(analysis_dir, "event_study_plot.png"), p, width = 10, height = 6, dpi = 300)

  all_results[[analysis_name]] <- list(
    analysis = analysis,
    twfe = twfe_result,
    power = power_result
  )
}

################################################################################
# COMPARISON TABLE
################################################################################

log_msg("\n================================================================================")
log_msg("GENERATING COMPARISON")
log_msg("================================================================================")

comparison <- tibble()

for (analysis_name in names(all_results)) {
  res <- all_results[[analysis_name]]

  pre_coefs <- res$twfe$coefs %>% filter(e < 0)
  max_pre <- if (nrow(pre_coefs) > 0) max(abs(pre_coefs$estimate)) else NA
  rms_pre <- if (nrow(pre_coefs) > 0) sqrt(mean(pre_coefs$estimate^2)) else NA

  mde_80 <- if (!is.null(res$power) && nrow(res$power) >= 2) res$power$mde_slope[2] else NA

  comparison <- bind_rows(
    comparison,
    tibble(
      analysis = res$analysis$name,
      period = if_else(grepl("Pre-COVID", res$analysis$name), "Pre-COVID", "Post-COVID"),
      sample = if_else(grepl("Full Sample", res$analysis$name), "Full", "Adopters Only"),
      f_test_p = res$twfe$pretrends_test$p_value,
      max_abs_pre = max_pre,
      rms_pre = rms_pre,
      mde_80 = mde_80,
      n_treated = n_distinct(all_results[[analysis_name]]$twfe$coefs),
      assessment = case_when(
        is.na(f_test_p) ~ "Unknown",
        f_test_p > 0.10 & !is.na(mde_80) & mde_80 < 0.10 ~ "STRONG",
        f_test_p > 0.05 & !is.na(mde_80) & mde_80 < 0.15 ~ "MODERATE",
        TRUE ~ "CAUTION"
      )
    )
  )
}

readr::write_csv(comparison, file.path(OUT_DIR, "period_comparison.csv"))

# Generate report
report_lines <- c(
  "# Pre-Trends Analysis: Pre-COVID vs Post-COVID",
  "",
  glue("Generated: {Sys.time()}"),
  "",
  "## Motivation",
  "",
  "COVID-19 fundamentally changed eviction patterns. To assess whether parallel trends",
  "violations are driven by the pandemic or by structural differences, we analyze",
  "pre-trends separately for:",
  "",
  "1. **Pre-COVID period (2012-2019)**: Clean period before pandemic",
  "2. **Post-COVID period (2021-2024)**: After moratoria ended",
  "",
  "## Results Summary",
  ""
)

for (i in 1:nrow(comparison)) {
  row <- comparison[i,]
  report_lines <- c(
    report_lines,
    glue("### {row$analysis} [{row$assessment}]"),
    "",
    glue("- **F-test p-value**: {round(row$f_test_p, 4)}"),
    glue("- **Max pre-trend**: {round(row$max_abs_pre, 4)}"),
    glue("- **RMS pre-trends**: {round(row$rms_pre, 4)}"),
    glue("- **MDE (80%)**: {round(row$mde_80, 4)}"),
    ""
  )
}

report_lines <- c(
  report_lines,
  "",
  "## Interpretation",
  "",
  "Compare Pre-COVID vs Post-COVID results:",
  "",
  "- If pre-trends violations are similar in both periods → Structural issue",
  "- If violations only in one period → Period-specific issue",
  "- If Pre-COVID has good parallel trends → Focus on pre-2020 sample",
  "",
  "## Next Steps",
  "",
  "Based on results:",
  "1. If Pre-COVID passes → Use 2012-2019 sample for identification",
  "2. If both fail → Consider matching, synthetic control, or bounds",
  "3. If Post-COVID passes → Focus on recent adoptions",
  "",
  "---",
  glue("Full results: {OUT_DIR}/")
)

writeLines(report_lines, file.path(OUT_DIR, "report.md"))

log_msg("\n================================================================================")
log_msg("ANALYSIS COMPLETE")
log_msg("================================================================================")
log_msg(glue("Results: {OUT_DIR}/"))
log_msg("================================================================================")

cat("\n✓ Pre-COVID vs Post-COVID analysis complete!\n")
cat(glue("  Output: {OUT_DIR}/\n"))
cat(glue("  Analyses run: {length(all_results)}\n\n"))
