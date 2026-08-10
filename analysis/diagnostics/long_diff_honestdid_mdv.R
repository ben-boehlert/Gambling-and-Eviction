#!/usr/bin/env Rscript
################################################################################
# long_diff_honestdid_mdv.R
#
# Pre-trends sensitivity analysis for the HEADLINE long-difference design
# (see long_difference_creative.R): 2018-2019 baseline vs. 2024 post-window,
# COVID years (2020-2022) skipped entirely. The pretrend question is whether
# gambling-soon states were already on a differential trajectory BEFORE the
# 2018-2019 baseline — not in event time around heterogeneous treatment dates.
#
# Design:
#   - Windows: 2016, 2017, baseline (2018-2019), 2024.
#   - Outcome per (county, window): mean of log1p(monthly filings).
#   - Baseline (2018-2019) is the reference; coefficient = 0 by construction.
#   - 2016, 2017 are PLACEBO long-differences (should be ~0 under PT).
#   - 2024 is the actual long-difference of interest.
#   - Estimator: feols(y ~ i(window, ever_treated, ref="baseline") | fips + window,
#                       cluster = ~ state_abb).
#   - Sample: ≥5 ETS counties/state, drop NH+ME, balanced across all four windows
#     (≥6 monthly obs in each single-year window, ≥12 across the baseline).
#
# Two diagnostics:
#   1. HonestDiD relative magnitudes (Rambachan & Roth 2023):
#      Robust CI for the 2024 long-diff as Mbar (post-window violation as a
#      fraction of the max pre-window violation) varies over [0, 2].
#   2. Roth (2022) minimal detectable violation (MDV):
#      Linear pre-trend slope (log-units / year) the 2016+2017 placebo test
#      would have rejected at 50% / 80% power. Extrapolated forward to 2024
#      this gives the bias the pre-test could not have ruled out.
#
# Outputs:
#   output/border_diagnostic/long_difference/long_diff_honestdid_relmag.csv
#   output/border_diagnostic/long_difference/long_diff_honestdid_breakdown.csv
#   output/border_diagnostic/long_difference/long_diff_honestdid_sensitivity.png
#   output/border_diagnostic/long_difference/long_diff_mdv.csv
#   output/border_diagnostic/long_difference/long_diff_placebo_coefs.csv
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(tidyr)
  library(fixest); library(ggplot2); library(lubridate)
  library(HonestDiD); library(pretrends)
})

set.seed(20260525L)

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic",
                       "long_difference")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# --- Sample filters and window definitions ----------------------------------
DROP_STATES <- c("ME", "NH")
MIN_CTYS_PER_STATE <- 5L
MIN_MONTHS_SINGLE  <- 6L   # per single-year window
MIN_MONTHS_BASE    <- 12L  # per two-year baseline window

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

# Windows: name -> (start, end). Order matters for downstream betahat ordering.
windows <- tibble::tribble(
  ~window,        ~start,                  ~end,                    ~t_calendar,
  "w2016",        as.Date("2016-01-01"),   as.Date("2016-12-31"),   2016.5,
  "w2017",        as.Date("2017-01-01"),   as.Date("2017-12-31"),   2017.5,
  "baseline",     as.Date("2018-01-01"),   as.Date("2019-12-31"),   2019.0,
  "w2024",        as.Date("2024-01-01"),   as.Date("2024-12-31"),   2024.5
)
BASELINE_KEY <- "baseline"
PLACEBO_KEYS <- c("w2016", "w2017")
POST_KEYS    <- "w2024"
NON_REF_ORDER <- c(PLACEBO_KEYS, POST_KEYS)  # ordering of betahat

# --- Load monthly county panel ----------------------------------------------
county_raw <- read_csv(file.path(repo_root, "data", "raw",
                                  "monthly_county_data_download.csv"),
                       show_col_types = FALSE) %>%
  mutate(fips         = as.integer(fips),
         state_fips   = as.integer(floor(fips / 1000)),
         month_date   = as.Date(date),
         filings_count = as.numeric(filings_count)) %>%
  left_join(state_fips_xwalk, by = "state_fips") %>%
  filter(!is.na(state_abb), !is.na(month_date),
         !(state_abb %in% DROP_STATES))

state_treat <- read_csv(file.path(repo_root, "data", "raw",
                                   "state_month_panel_with_treatment.csv"),
                        show_col_types = FALSE) %>%
  group_by(state_abb) %>%
  summarise(treat_start = suppressWarnings(min(as.Date(treat_start),
                                                na.rm = TRUE)),
            .groups = "drop") %>%
  mutate(treat_start  = if_else(is.finite(treat_start), treat_start,
                                as.Date(NA)),
         ever_treated = !is.na(treat_start))

ok_states <- county_raw %>%
  distinct(state_abb, fips) %>%
  count(state_abb, name = "n_counties") %>%
  filter(n_counties >= MIN_CTYS_PER_STATE) %>% pull(state_abb)

# --- Build (county, window) panel of within-window means --------------------
# For each window, compute per-county mean of log1p(monthly filings) and the
# count of months observed in that window. Then enforce coverage thresholds.

county_window <- county_raw %>%
  filter(state_abb %in% ok_states) %>%
  mutate(y_m = log1p(pmax(filings_count, 0))) %>%
  # Assign each month to a window (or NA if outside all windows).
  mutate(window = case_when(
    month_date >= windows$start[1] & month_date <= windows$end[1] ~ windows$window[1],
    month_date >= windows$start[2] & month_date <= windows$end[2] ~ windows$window[2],
    month_date >= windows$start[3] & month_date <= windows$end[3] ~ windows$window[3],
    month_date >= windows$start[4] & month_date <= windows$end[4] ~ windows$window[4],
    TRUE                                                          ~ NA_character_
  )) %>%
  filter(!is.na(window)) %>%
  group_by(fips, state_abb, window) %>%
  summarise(n_months = n(),
            y        = mean(y_m, na.rm = TRUE),
            .groups  = "drop")

# Coverage gates per window.
coverage_ok <- county_window %>%
  mutate(min_req = if_else(window == BASELINE_KEY,
                           MIN_MONTHS_BASE, MIN_MONTHS_SINGLE)) %>%
  filter(n_months >= min_req) %>%
  select(fips, state_abb, window, y)

# Require balance across all four windows (each county observed in all).
all_windows <- c(BASELINE_KEY, NON_REF_ORDER)
balanced_counties <- coverage_ok %>%
  filter(window %in% all_windows) %>%
  count(fips, name = "n_w") %>%
  filter(n_w == length(all_windows)) %>%
  pull(fips)

panel <- coverage_ok %>%
  filter(fips %in% balanced_counties, window %in% all_windows) %>%
  left_join(state_treat %>% select(state_abb, ever_treated),
            by = "state_abb") %>%
  mutate(ever_treated = if_else(is.na(ever_treated), FALSE, ever_treated),
         window       = factor(window, levels = all_windows))

cat("--- Sample summary ---\n")
cat("  Counties (balanced across all 4 windows):", n_distinct(panel$fips), "\n")
cat("  States:                                  ", n_distinct(panel$state_abb), "\n")
cat("  Treated counties:    ", n_distinct(panel$fips[panel$ever_treated]), "\n")
cat("  Never-treated:       ", n_distinct(panel$fips[!panel$ever_treated]), "\n")
cat("  Treated states:    ",
    paste(sort(unique(panel$state_abb[panel$ever_treated])), collapse = " "), "\n")
cat("  Never-treated:     ",
    paste(sort(unique(panel$state_abb[!panel$ever_treated])), collapse = " "), "\n\n")

# --- Estimate joint window × ever_treated model -----------------------------
# Reference window = baseline (2018-2019). Coefficients on the three non-ref
# windows give the differential change from baseline for treated counties.

m <- feols(y ~ i(window, ever_treated, ref = BASELINE_KEY) | fips + window,
           data = panel, cluster = ~ state_abb)

cat("--- Joint window × ever_treated model ---\n")
print(summary(m))

co_names <- names(coef(m))
# fixest names: e.g. "window::w2016:ever_treated" or similar.
# Map back to window key.
extract_window_key <- function(nm) {
  m1 <- regmatches(nm, regexpr("(w2016|w2017|w2024)", nm))
  if (length(m1) == 0) NA_character_ else m1
}
co_window <- vapply(co_names, extract_window_key, character(1))
stopifnot(all(NON_REF_ORDER %in% co_window))

# Reorder so betahat is in NON_REF_ORDER: (w2016, w2017, w2024)
ix <- match(NON_REF_ORDER, co_window)
betahat   <- as.numeric(coef(m))[ix]
sigma_hat <- vcov(m)[ix, ix]
names(betahat) <- NON_REF_ORDER
rownames(sigma_hat) <- colnames(sigma_hat) <- NON_REF_ORDER

# Pre/post split (HonestDiD convention: pre then post).
numPrePeriods  <- length(PLACEBO_KEYS)
numPostPeriods <- length(POST_KEYS)

# Calendar-time centroids relative to baseline midpoint (2019.0).
t_centroid <- windows$t_calendar[match(NON_REF_ORDER, windows$window)]
t_baseline <- windows$t_calendar[match(BASELINE_KEY,  windows$window)]
tVec_rel   <- t_centroid - t_baseline  # e.g. c(-2.5, -1.5, +5.5)

placebo_tbl <- tibble(
  window    = NON_REF_ORDER,
  t_rel_yr  = tVec_rel,
  beta_log  = betahat,
  se_log    = sqrt(diag(sigma_hat)),
  beta_pct  = (exp(betahat) - 1) * 100,
  ci_lo_log = betahat - qnorm(0.975) * sqrt(diag(sigma_hat)),
  ci_hi_log = betahat + qnorm(0.975) * sqrt(diag(sigma_hat))
) %>%
  mutate(ci_lo_pct = (exp(ci_lo_log) - 1) * 100,
         ci_hi_pct = (exp(ci_hi_log) - 1) * 100,
         role      = if_else(window %in% PLACEBO_KEYS, "placebo_pre", "post"))

write_csv(placebo_tbl, file.path(out_dir, "long_diff_placebo_coefs.csv"))

cat("\n--- Placebo + post long-differences (vs 2018-2019 baseline) ---\n")
print(placebo_tbl %>%
        mutate(across(where(is.numeric), ~ round(.x, 4))))

# ============================================================================
# 1. HonestDiD relative magnitudes
# ============================================================================
# 2 pre-windows (2016, 2017) and 1 post-window (2024). Mbar bounds the
# 2024 violation relative to the max consecutive pre-window violation.

mbar_grid <- c(0, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2)

orig <- HonestDiD::constructOriginalCS(
  betahat        = betahat,
  sigma          = sigma_hat,
  numPrePeriods  = numPrePeriods,
  numPostPeriods = numPostPeriods,
  l_vec          = HonestDiD::basisVector(index = 1, size = numPostPeriods)
)
orig_lb <- as.numeric(orig$lb)[1]
orig_ub <- as.numeric(orig$ub)[1]

rm_res <- HonestDiD::createSensitivityResults_relativeMagnitudes(
  betahat        = betahat,
  sigma          = sigma_hat,
  numPrePeriods  = numPrePeriods,
  numPostPeriods = numPostPeriods,
  Mbarvec        = mbar_grid,
  l_vec          = HonestDiD::basisVector(index = 1, size = numPostPeriods)
)

relmag_tbl <- as_tibble(rm_res) %>%
  mutate(lb            = as.numeric(lb),
         ub            = as.numeric(ub),
         Mbar          = as.numeric(Mbar),
         method        = as.character(method),
         Delta         = as.character(Delta),
         rejects_zero  = (lb > 0) | (ub < 0),
         orig_lb       = orig_lb,
         orig_ub       = orig_ub,
         orig_rejects  = (orig_lb > 0) | (orig_ub < 0),
         lb_pct        = (exp(lb) - 1) * 100,
         ub_pct        = (exp(ub) - 1) * 100)

write_csv(relmag_tbl, file.path(out_dir, "long_diff_honestdid_relmag.csv"))

breakdown_tbl <- relmag_tbl %>%
  summarise(
    orig_lb        = first(orig_lb),
    orig_ub        = first(orig_ub),
    orig_lb_pct    = (exp(first(orig_lb)) - 1) * 100,
    orig_ub_pct    = (exp(first(orig_ub)) - 1) * 100,
    orig_rejects   = first(orig_rejects),
    breakdown_Mbar = {
      rj <- Mbar[rejects_zero]
      if (length(rj) == 0) NA_real_ else max(rj)
    }
  )
write_csv(breakdown_tbl, file.path(out_dir, "long_diff_honestdid_breakdown.csv"))

cat("\n--- HonestDiD relative magnitudes (2024 long-diff CI vs Mbar) ---\n")
print(breakdown_tbl %>%
        mutate(across(where(is.numeric), ~ round(.x, 4))))
cat("\nFull grid (lb/ub in log units):\n")
print(relmag_tbl %>%
        select(Mbar, lb, ub, lb_pct, ub_pct, rejects_zero) %>%
        mutate(across(where(is.numeric), ~ round(.x, 4))))

# --- Sensitivity plot --------------------------------------------------------
plot_df <- relmag_tbl %>%
  mutate(midpoint_pct = (exp((lb + ub) / 2) - 1) * 100)

p_sens <- ggplot(plot_df, aes(x = Mbar, y = midpoint_pct)) +
  geom_hline(yintercept = 0, color = "grey50", linewidth = 0.45) +
  geom_errorbar(aes(ymin = lb_pct, ymax = ub_pct),
                width = 0.06, color = "grey20", linewidth = 0.55) +
  geom_point(aes(fill = rejects_zero),
             shape = 21, color = "grey15", size = 3.0, stroke = 0.6) +
  scale_fill_manual(values = c(`TRUE` = "#b91c1c", `FALSE` = "white"),
                    guide  = "none") +
  scale_x_continuous(breaks = mbar_grid) +
  scale_y_continuous(labels = function(z) paste0(round(z), "%")) +
  labs(x = expression(bar(M)~"(2024 violation as fraction of max 2016-17 violation)"),
       y = "Robust CI for 2024 long-difference (treated vs never-legalized)") +
  theme_minimal(base_size = 13, base_family = "serif") +
  theme(
    panel.grid.minor   = element_blank(),
    panel.grid.major.x = element_blank(),
    panel.grid.major.y = element_line(color = "grey92", linewidth = 0.3),
    axis.title.x       = element_text(margin = margin(t = 8)),
    axis.title.y       = element_text(margin = margin(r = 8)),
    axis.text          = element_text(color = "grey20"),
    axis.ticks         = element_line(color = "grey40", linewidth = 0.3),
    axis.line          = element_line(color = "grey40", linewidth = 0.3),
    panel.background   = element_rect(fill = "transparent", color = NA),
    plot.background    = element_rect(fill = "transparent", color = NA),
    plot.margin        = margin(t = 8, r = 12, b = 5, l = 5, unit = "pt")
  )

ggsave(file.path(out_dir, "long_diff_honestdid_sensitivity.png"), p_sens,
       width = 8.5, height = 5.0, dpi = 300, bg = "transparent")

# ============================================================================
# 2. Roth (2022) MDV — linear pre-trend slope detectable at 50% / 80% power
# ============================================================================
# tVec is in years relative to baseline midpoint (2019.0). Slope is therefore
# in log-units per calendar year. Implied bias on the 2024 long-diff is the
# slope times the 2024 offset (+5.5 years).

mdv_for_power <- function(power) {
  tryCatch(
    pretrends::slope_for_power(
      sigma           = sigma_hat,
      targetPower     = power,
      tVec            = tVec_rel,
      referencePeriod = 0
    ),
    error = function(e) {
      cat("pretrends::slope_for_power failed at power =", power, ":",
          conditionMessage(e), "\n")
      NA_real_
    }
  )
}

mdv_50 <- mdv_for_power(0.50)
mdv_80 <- mdv_for_power(0.80)
offset_2024 <- tVec_rel[which(NON_REF_ORDER == "w2024")]

mdv_tbl <- tibble(
  power               = c(0.50, 0.80),
  mdv_slope_log       = c(mdv_50, mdv_80),
  mdv_slope_pct       = (exp(c(mdv_50, mdv_80)) - 1) * 100,
  implied_bias_2024   = c(mdv_50, mdv_80) * offset_2024,
  implied_bias_2024_pct = (exp(c(mdv_50, mdv_80) * offset_2024) - 1) * 100
)

write_csv(mdv_tbl, file.path(out_dir, "long_diff_mdv.csv"))

cat("\n--- Roth (2022) minimal detectable violation ---\n")
cat(sprintf("  Pre-window time coordinates (years from baseline): %s\n",
            paste(round(tVec_rel[NON_REF_ORDER %in% PLACEBO_KEYS], 2),
                  collapse = ", ")))
cat(sprintf("  Post-window offset (2024 vs 2018-19 baseline mid): %.2f years\n",
            offset_2024))
cat(sprintf("  50%% power: slope = %.4f log/yr (= %.2f%%/yr); implied 2024 bias = %.2f%%\n",
            mdv_50, (exp(mdv_50) - 1) * 100,
            (exp(mdv_50 * offset_2024) - 1) * 100))
cat(sprintf("  80%% power: slope = %.4f log/yr (= %.2f%%/yr); implied 2024 bias = %.2f%%\n",
            mdv_80, (exp(mdv_80) - 1) * 100,
            (exp(mdv_80 * offset_2024) - 1) * 100))

cat("\nWrote:\n")
cat("  ", file.path(out_dir, "long_diff_placebo_coefs.csv"),         "\n")
cat("  ", file.path(out_dir, "long_diff_honestdid_relmag.csv"),      "\n")
cat("  ", file.path(out_dir, "long_diff_honestdid_breakdown.csv"),   "\n")
cat("  ", file.path(out_dir, "long_diff_honestdid_sensitivity.png"), "\n")
cat("  ", file.path(out_dir, "long_diff_mdv.csv"),                   "\n")
