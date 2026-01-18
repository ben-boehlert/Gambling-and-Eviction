#!/usr/bin/env Rscript
################################################################################
# diagnose_se_inflation.R
#
# Systematic A/B testing to isolate why SE is inflated in CS-DiD power sim
# under the null (effect=0)
#
# Usage: Rscript diagnose_se_inflation.R
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
  library(did)
  library(tibble)
})

# Use same data loading as main script
DATA_FILE  <- "combined_monthly_panel.csv"
TREAT_FILE <- "state_month_panel_with_treatment.csv"
OUT_DIR    <- "diagnostic_se_inflation"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# Helper functions (copied from main script)
ym_index <- function(date) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
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
      state_abb = sapply(geo_id, function(x) {
        key <- gsub("[^a-z]", "", tolower(trimws(as.character(x))))
        name_key <- gsub("[^a-z]", "", tolower(state.name))
        m <- setNames(state.abb, name_key)
        unname(m[key])
      }),
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

cat("Loading data...\n")
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
  filter(state_abb %in% unique(treat$state_abb)) %>%
  group_by(state_abb) %>%
  mutate(treat_start_state = if (all(is.na(treat_start))) as.Date(NA) else min(treat_start, na.rm = TRUE)) %>%
  ungroup() %>%
  mutate(
    t = ym_index(month_date),
    g = ifelse(is.na(treat_start_state), 0L, ym_index(treat_start_state)),
    g = as.integer(g),
    id = as.integer(as.factor(state_abb)),
    y = log1p(pmax(as.numeric(filings_count), 0))
  )

n_states <- n_distinct(panel$state_abb)
cat(glue("Panel: {n_states} states\n"))
cat(glue("Panel rows: {nrow(panel)}\n"))

################################################################################
# Function to run one simulation and extract diagnostics
################################################################################

run_one_sim <- function(seed,
                        bstrap = TRUE,
                        biters = 199,
                        clustervars = "id",
                        na_rm = TRUE,
                        control_group = "notyettreated") {
  set.seed(seed)

  # Simple simulation: just use actual data (effect=0 is implicit)
  dat <- data.frame(
    id = panel$id,
    t = panel$t,
    g = panel$g,
    y = panel$y
  )

  tryCatch({
    est <- did::att_gt(
      yname = "y",
      tname = "t",
      idname = "id",
      gname = "g",
      xformla = ~ 1,
      data = dat,
      panel = TRUE,
      control_group = control_group,
      allow_unbalanced_panel = TRUE,
      est_method = "reg",
      bstrap = bstrap,
      biters = biters,
      cband = FALSE,
      clustervars = clustervars
    )

    agg <- did::aggte(est, type = "simple", na.rm = na_rm)

    att <- as.numeric(agg$overall.att)
    se <- as.numeric(agg$overall.se)

    # Count how many att_gt are NA
    n_attgt_total <- length(est$att)
    n_attgt_na <- sum(is.na(est$att))

    # Compute p-value
    z <- att / se
    p <- 2 * pnorm(-abs(z))

    list(
      ok = TRUE,
      att = att,
      se = se,
      z = z,
      p = p,
      n_attgt_total = n_attgt_total,
      n_attgt_na = n_attgt_na,
      error = NA_character_
    )
  }, error = function(e) {
    list(
      ok = FALSE,
      att = NA_real_,
      se = NA_real_,
      z = NA_real_,
      p = NA_real_,
      n_attgt_total = NA_integer_,
      n_attgt_na = NA_integer_,
      error = conditionMessage(e)
    )
  })
}

################################################################################
# Function to run multiple sims and compute diagnostics
################################################################################

run_diagnostic_test <- function(test_name, n_sims = 50, ...) {
  cat("\n", rep("=", 60), "\n", sep="")
  cat(glue("Test: {test_name}\n"))
  cat(rep("=", 60), "\n", sep="")

  set.seed(12345)
  seeds <- sample.int(1e8, n_sims)

  results <- lapply(seeds, function(s) run_one_sim(s, ...))

  # Extract vectors
  ok_vec <- sapply(results, function(r) r$ok)
  att_vec <- sapply(results, function(r) r$att)
  se_vec <- sapply(results, function(r) r$se)
  z_vec <- sapply(results, function(r) r$z)
  p_vec <- sapply(results, function(r) r$p)
  n_attgt_total <- sapply(results, function(r) r$n_attgt_total)
  n_attgt_na <- sapply(results, function(r) r$n_attgt_na)

  # Filter to successful
  att_ok <- att_vec[ok_vec]
  se_ok <- se_vec[ok_vec]
  z_ok <- z_vec[ok_vec]
  p_ok <- p_vec[ok_vec]

  # Compute diagnostics
  diag <- tibble(
    test_name = test_name,
    n_sims = n_sims,
    n_success = sum(ok_vec),
    n_failed = sum(!ok_vec),

    # ATT diagnostics
    mean_att = mean(att_ok, na.rm = TRUE),
    sd_att = sd(att_ok, na.rm = TRUE),

    # SE diagnostics
    mean_se = mean(se_ok, na.rm = TRUE),
    median_se = median(se_ok, na.rm = TRUE),
    q05_se = quantile(se_ok, 0.05, na.rm = TRUE),
    q95_se = quantile(se_ok, 0.95, na.rm = TRUE),

    # Z diagnostics
    mean_z = mean(z_ok, na.rm = TRUE),
    sd_z = sd(z_ok, na.rm = TRUE),
    q05_z = quantile(z_ok, 0.05, na.rm = TRUE),
    q95_z = quantile(z_ok, 0.95, na.rm = TRUE),

    # SE inflation
    se_inflation = mean_se / sd_att,

    # P-value diagnostics
    mean_p = mean(p_ok, na.rm = TRUE),
    median_p = median(p_ok, na.rm = TRUE),
    q05_p = quantile(p_ok, 0.05, na.rm = TRUE),
    q50_p = quantile(p_ok, 0.50, na.rm = TRUE),
    q95_p = quantile(p_ok, 0.95, na.rm = TRUE),
    rejection_rate = mean(p_ok < 0.05, na.rm = TRUE),

    # Missing ATT_GT
    mean_n_attgt_total = mean(n_attgt_total[ok_vec], na.rm = TRUE),
    mean_n_attgt_na = mean(n_attgt_na[ok_vec], na.rm = TRUE),
    mean_frac_attgt_na = mean(n_attgt_na[ok_vec] / n_attgt_total[ok_vec], na.rm = TRUE)
  )

  print(diag)
  cat("\n")

  return(diag)
}

################################################################################
# Run A/B tests
################################################################################

all_diagnostics <- list()

# BASELINE
all_diagnostics[[1]] <- run_diagnostic_test(
  "BASELINE (bstrap=TRUE, biters=199, clustervars=id)",
  n_sims = 100,
  bstrap = TRUE,
  biters = 199,
  clustervars = "id",
  na_rm = TRUE,
  control_group = "notyettreated"
)

# A1: No bootstrap
all_diagnostics[[2]] <- run_diagnostic_test(
  "A1: bstrap=FALSE (analytic SE)",
  n_sims = 100,
  bstrap = FALSE,
  biters = 199,
  clustervars = "id",
  na_rm = TRUE,
  control_group = "notyettreated"
)

# B1: No clustering
all_diagnostics[[3]] <- run_diagnostic_test(
  "B1: clustervars=NULL (no clustering)",
  n_sims = 100,
  bstrap = TRUE,
  biters = 199,
  clustervars = NULL,
  na_rm = TRUE,
  control_group = "notyettreated"
)

# C1: More bootstrap iterations
all_diagnostics[[4]] <- run_diagnostic_test(
  "C1: biters=999 (more bootstrap reps)",
  n_sims = 100,
  bstrap = TRUE,
  biters = 999,
  clustervars = "id",
  na_rm = TRUE,
  control_group = "notyettreated"
)

# D1: na.rm=FALSE
cat("\nAttempting D1: na.rm=FALSE...\n")
test_na_rm <- tryCatch({
  run_diagnostic_test(
    "D1: na.rm=FALSE",
    n_sims = 10,
    bstrap = TRUE,
    biters = 199,
    clustervars = "id",
    na_rm = FALSE,
    control_group = "notyettreated"
  )
}, error = function(e) {
  cat("na.rm=FALSE failed with error:\n")
  cat(conditionMessage(e), "\n")
  NULL
})

if (!is.null(test_na_rm)) {
  all_diagnostics[[5]] <- test_na_rm
}

################################################################################
# Save results
################################################################################

diagnostics_df <- bind_rows(all_diagnostics)
write_csv(diagnostics_df, file.path(OUT_DIR, "ab_test_diagnostics.csv"))

cat("\n")
cat(rep("=", 80), "\n", sep="")
cat("SUMMARY TABLE\n")
cat(rep("=", 80), "\n", sep="")
print(diagnostics_df %>% select(test_name, se_inflation, rejection_rate, mean_frac_attgt_na))

cat("\n")
cat("Results saved to:", file.path(OUT_DIR, "ab_test_diagnostics.csv"), "\n")
