#!/usr/bin/env Rscript
################################################################################
# intra_cluster_correlation.R
#
# Computes the empirical within-state-month residual correlation (rho) after
# absorbing county FE + month FE. Used to verify the back-of-envelope claim
# that rho ≈ 0 in this data — the key parameter governing why disaggregation
# delivered 5× SE shrinkage in Sim D.
#
# rho is identified as:
#   rho = Var(state-month mean of post-FE residual) / Var(post-FE residual)
# or equivalently (ANOVA decomposition):
#   rho = SS_between_state_month / SS_total
#
# Reports rho for:
#   1. All-county panel (Sim D pool)
#   2. Border-county panel (Sim C pool)
#
# Each uses the SAME residual pool the corresponding power sim uses:
#   untreated obs (never-treated + pre-period of treated), post FE absorption.
#
# Output:
#   output/border_diagnostic/intra_cluster_correlation.csv
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(fixest)
  library(tibble)
})

set.seed(20260521L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic")

`%||%` <- function(a, b) if (!is.null(a)) a else b

ym_index <- function(date) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
}

state_fips_xwalk <- tibble::tribble(
  ~state_fips, ~state_abb,
   1,"AL", 2,"AK", 4,"AZ", 5,"AR", 6,"CA", 8,"CO", 9,"CT",
  10,"DE",11,"DC",12,"FL",13,"GA",15,"HI",16,"ID",
  17,"IL",18,"IN",19,"IA",20,"KS",21,"KY",22,"LA",
  23,"ME",24,"MD",25,"MA",26,"MI",27,"MN",28,"MS",
  29,"MO",30,"MT",31,"NE",32,"NV",33,"NH",34,"NJ",
  35,"NM",36,"NY",37,"NC",38,"ND",39,"OH",40,"OK",
  41,"OR",42,"PA",44,"RI",45,"SC",46,"SD",47,"TN",
  48,"TX",49,"UT",50,"VT",51,"VA",53,"WA",54,"WV",
  55,"WI",56,"WY"
)

COVID_START <- as.Date("2020-03-01")
COVID_END   <- as.Date("2022-03-31")

# ----------------------------- helpers ---------------------------------------

# Compute rho given a panel data frame with columns: y (outcome), unit_id,
# t (month integer), state_abb, untreated_obs (logical flag).
compute_rho <- function(panel, label) {
  # Restrict to untreated obs (matches the residual pool used in the power sim).
  d <- panel %>%
    filter(untreated_obs, is.finite(y), !is.na(unit_id), !is.na(t))

  # Manually demean y by unit and month FE (iterated within-transform).
  # This avoids fixest's singleton-dropping issue and gives residuals aligned
  # one-to-one with d.
  d$y_demeaned <- d$y
  for (iter in 1:20) {
    prev <- d$y_demeaned
    d <- d %>%
      group_by(unit_id) %>%
      mutate(y_demeaned = y_demeaned - mean(y_demeaned, na.rm = TRUE)) %>%
      group_by(t) %>%
      mutate(y_demeaned = y_demeaned - mean(y_demeaned, na.rm = TRUE)) %>%
      ungroup()
    if (max(abs(d$y_demeaned - prev), na.rm = TRUE) < 1e-8) break
  }
  d$resid <- d$y_demeaned

  # ANOVA: SS_between_state_month / SS_total.
  agg <- d %>%
    group_by(state_abb, t) %>%
    summarise(
      n_units = n(),
      mean_resid = mean(resid, na.rm = TRUE),
      .groups = "drop"
    )

  ss_total   <- sum((d$resid - mean(d$resid, na.rm = TRUE))^2, na.rm = TRUE)
  # Weight by n_units so that the between-group sum-of-squares is correctly
  # scaled (each state-month contributes proportional to its observations).
  ss_between <- sum(agg$n_units *
                    (agg$mean_resid - mean(d$resid, na.rm = TRUE))^2,
                    na.rm = TRUE)
  ss_within  <- ss_total - ss_between

  rho_hat <- ss_between / ss_total

  # Alternative estimator: average within-state-month pairwise correlation,
  # via the variance-components form:
  #   rho = Var(state-month mean) / Var(residual)
  # using equal-weighted state-month means.
  agg_eq <- d %>%
    group_by(state_abb, t) %>%
    summarise(mean_resid = mean(resid, na.rm = TRUE),
              .groups = "drop")
  rho_alt <- var(agg_eq$mean_resid, na.rm = TRUE) /
             var(d$resid, na.rm = TRUE)

  # SD breakdown.
  sd_resid          <- sd(d$resid, na.rm = TRUE)
  sd_state_month    <- sd(agg_eq$mean_resid, na.rm = TRUE)

  # Counties per state-month — the N_st in the cluster-mean variance formula.
  n_per_sm <- agg$n_units
  n_st_mean   <- mean(n_per_sm)
  n_st_median <- median(n_per_sm)

  list(
    label = label,
    n_obs = nrow(d),
    n_state_months = nrow(agg),
    n_units = n_distinct(d$unit_id),
    n_states = n_distinct(d$state_abb),
    sd_resid = sd_resid,
    sd_state_month_mean = sd_state_month,
    rho_anova = rho_hat,
    rho_var_ratio = rho_alt,
    n_st_mean = n_st_mean,
    n_st_median = n_st_median,
    ss_total = ss_total,
    ss_between = ss_between,
    ss_within = ss_within,
    share_var_state_month = ss_between / ss_total,
    share_var_county_idio = ss_within / ss_total
  )
}

# ----------------------------- ALL-COUNTY PANEL (Sim D) -----------------------

p_county_raw <- file.path(repo_root, "data", "raw",
                          "monthly_county_data_download.csv")
p_state_tr   <- file.path(repo_root, "data", "raw",
                          "state_month_panel_with_treatment.csv")

county_raw <- read_csv(p_county_raw, show_col_types = FALSE) %>%
  mutate(
    fips        = as.integer(fips),
    state_fips  = as.integer(floor(fips / 1000)),
    month_date  = as.Date(date),
    filings_count = as.numeric(filings_count)
  ) %>%
  left_join(state_fips_xwalk, by = "state_fips") %>%
  filter(!is.na(state_abb), !is.na(month_date))

state_treat_one <- read_csv(p_state_tr, show_col_types = FALSE) %>%
  group_by(state_abb) %>%
  summarise(treat_start = suppressWarnings(min(as.Date(treat_start),
                                                na.rm = TRUE)),
            .groups = "drop") %>%
  mutate(treat_start = if_else(is.finite(treat_start), treat_start,
                               as.Date(NA)))

all_county <- county_raw %>%
  left_join(state_treat_one, by = "state_abb") %>%
  filter(state_abb != "ME") %>%
  filter(month_date < COVID_START | month_date > COVID_END) %>%
  mutate(
    t = ym_index(month_date),
    g = if_else(!is.na(treat_start), ym_index(treat_start), 0L),
    unit_id = as.integer(fips),
    state_abb = as.character(state_abb),
    untreated_obs = (g == 0L) | (t < g),
    y = log1p(pmax(filings_count, 0))
  ) %>%
  filter(is.finite(y), !is.na(unit_id), !is.na(t))

# ----------------------------- BORDER-COUNTY PANEL (Sim C) --------------------

p_border <- file.path(repo_root, "data", "processed",
                      "county_month_border_panel.csv")

border_county <- read_csv(p_border, show_col_types = FALSE) %>%
  mutate(
    month_date  = as.Date(month_date),
    treat_start = as.Date(treat_start),
    filings_count = as.numeric(filings_count)
  ) %>%
  filter(state_abb != "ME") %>%
  filter(month_date < COVID_START | month_date > COVID_END) %>%
  mutate(
    t = ym_index(month_date),
    g = if_else(!is.na(treat_start), ym_index(treat_start), 0L),
    unit_id = as.integer(fips),
    state_abb = as.character(state_abb),
    untreated_obs = (g == 0L) | (t < g),
    y = log1p(pmax(filings_count, 0))
  ) %>%
  filter(is.finite(y), !is.na(unit_id), !is.na(t))

# ----------------------------- compute & write --------------------------------

res_all    <- compute_rho(all_county,    "all_county_pool")
res_border <- compute_rho(border_county, "border_county_pool")

results <- bind_rows(as_tibble(res_all), as_tibble(res_border))

cat("\n=== INTRA-CLUSTER CORRELATION (post county-FE + month-FE) ===\n\n")
print(results %>%
        select(label, n_obs, n_state_months, n_units, n_states,
               sd_resid, sd_state_month_mean,
               rho_anova, rho_var_ratio,
               n_st_mean, share_var_state_month, share_var_county_idio) %>%
        mutate(across(where(is.numeric), ~ signif(.x, 4))))

write_csv(results, file.path(out_dir, "intra_cluster_correlation.csv"))
cat("\nWrote:", file.path(out_dir, "intra_cluster_correlation.csv"), "\n")

# ----------------------------- back-out vs predicted --------------------------

# Compare to the implied rho from the power-sim SE ratio:
#   SE_ratio² ≈ (σ²_county / σ²_state) × [ρ + (1-ρ)/N]
# Plugging in: SE_D / SE_A = 0.0042 / 0.0216 ≈ 0.194
# Implied (with σ_county/σ_state ≈ 1, N=40): ρ ≈ 0.013

cat("\nBack-of-envelope check:\n")
cat("  Observed SE shrinkage Sim D / Sim A: 0.0042 / 0.0216 = 0.194\n")
cat("  Implied rho (with sigma_ratio = 1, N = 40):",
    signif((0.194^2 - 1/40) / (1 - 1/40), 3), "\n")
cat("  Direct ANOVA rho on Sim D pool:",
    signif(res_all$rho_anova, 3), "\n")
cat("  Direct var-ratio rho on Sim D pool:",
    signif(res_all$rho_var_ratio, 3), "\n")
