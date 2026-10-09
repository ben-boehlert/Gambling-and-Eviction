#!/usr/bin/env Rscript
################################################################################
# mortgage_pretrend_linear_slope.R  (2026-10-09)
# One-number pre-trend: a linear slope on event time over switchers' pre-launch
# months, against never-treated states, with state + month FE and the locked
# 2019 covariates as X x month FE:
#     y_st = beta * e_st * 1[switcher, e <= -1] + X_s x month FE + a_s + g_t + u
# Only pre-launch months of switchers enter (post-launch never read), event
# time censored below at -24 (earlier months get e = -24, i.e. the trend is
# fitted over the last 24 pre-launch months). beta is log points per month of
# differential movement; reported per month, per year, and as the implied
# bias of the design's horizon-6..18 ATT if the trend continued unchanged
# (mean over h of beta * (h + 1), reference month e = -1). A quadratic term
# and a 12-month window (e >= -12) are reported as sensitivity.
# Grid: outcome (30-89, 90+) x window (spliced, June-2022) x weights (equal,
# mortgaged units). NV out. State-clustered SE.
# Run from the project root: Rscript analysis/diagnostics/mortgage_pretrend_linear_slope.R
################################################################################
suppressPackageStartupMessages({ library(dplyr); library(readr); library(fixest); library(glue) })
source("utils/eviction_treatment_schedule.R")
OUT <- "output/mortgage_pretrend_linear_slope"; dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
COV <- c("judicial_only", "unemp_2019", "hpi_growth_2016q4_2019q4", "age65_pct"); H <- 6:18; MIN_E <- -24L
mi <- function(d) as.integer(format(d, "%Y")) * 12L + as.integer(format(d, "%m"))
covs <- read_csv("data/processed/state_covariates_2019.csv", show_col_types = FALSE) %>% select(state_abb, all_of(COV))
wts  <- read_csv("data/processed/state_mortgage_weights_2019.csv", show_col_types = FALSE) %>% transmute(state_abb, w_mort = units_with_mortgage)
build <- function(f, min_date, max_date, drop_start, drop_end) {
  r <- read_csv(f, show_col_types = FALSE) %>% mutate(month_date = as.Date(month_date), treatment_date = as.Date(treatment_date))
  drop_pre_paspa_states(r, "slope") %>% filter(month_date >= min_date, month_date <= max_date, !(month_date >= drop_start & month_date <= drop_end)) %>%
    mutate(never = is.na(treatment_date) | treatment_date > max_date, y = log_delinquency_rate,
           e_raw = ifelse(never, NA_integer_, mi(month_date) - mi(treatment_date))) %>%
    filter(never | e_raw <= -1) %>%                                   # pre-launch months only; no post-launch data enters
    mutate(e_tr = ifelse(never, 0, pmax(e_raw, MIN_E) + 1),            # 0 at the reference month e = -1; -23 at e <= -24
           month_f = factor(month_date)) %>%
    left_join(covs, by = "state_abb") %>% left_join(wts, by = "state_abb") %>% mutate(across(all_of(COV), ~ as.numeric(scale(.x))), w_eq = 1)
}
fit <- function(d, wcol, label, win = MIN_E) {
  d <- d %>% filter(never | e_raw >= win) %>% mutate(e_tr = ifelse(never, 0, e_raw + 1), e_tr2 = e_tr^2)
  terms <- paste(sprintf("i(month_f, %s)", COV), collapse = " + ")
  m1 <- feols(as.formula(paste("y ~ e_tr +", terms, "| state_abb + month_f")), data = d, weights = d[[wcol]], cluster = ~state_abb)
  m2 <- feols(as.formula(paste("y ~ e_tr + e_tr2 +", terms, "| state_abb + month_f")), data = d, weights = d[[wcol]], cluster = ~state_abb)
  b <- unname(coef(m1)["e_tr"]); se <- unname(se(m1)["e_tr"])
  tibble(spec = label, pre_window = glue("{win}..-1"), n_switchers = n_distinct(d$state_abb[!d$never]), n_controls = n_distinct(d$state_abb[d$never]), n_clusters = n_distinct(d$state_abb),
         slope_per_month = b, se = se, p = 2 * pnorm(-abs(b / se)), slope_per_year = 12 * b,
         ci_lo_year = 12 * (b - 1.96 * se), ci_hi_year = 12 * (b + 1.96 * se),
         implied_bias_h6_18 = b * mean(H + 1), implied_bias_ci_lo = (b - 1.96 * se) * mean(H + 1), implied_bias_ci_hi = (b + 1.96 * se) * mean(H + 1),
         quad_linear = unname(coef(m2)["e_tr"]), quad_sq = unname(coef(m2)["e_tr2"]), quad_sq_p = unname(pvalue(m2)["e_tr2"]))
}
grid <- list(list("30-89", "data/processed/mortgage3089_treatment_panel.csv"), list("90+", "data/processed/mortgage_treatment_panel.csv"))
res <- list()
for (o in grid) for (w in list(list("spliced", "2016-01-01", "2025-03-01", "2020-03-01", "2021-07-01"), list("June-2022", "2022-06-01", "2025-03-01", "2020-03-01", "2022-05-31"))) {
  d <- build(o[[2]], as.Date(w[[2]]), as.Date(w[[3]]), as.Date(w[[4]]), as.Date(w[[5]]))
  for (wc in c("w_eq", "w_mort")) {
    lab <- glue("{o[[1]]} | {w[[1]]} | {ifelse(wc == 'w_eq', 'equal weights', 'mortgaged-unit weights')}")
    res[[length(res) + 1]] <- fit(d, wc, lab, -24L); res[[length(res) + 1]] <- fit(d, wc, lab, -12L)
  }
}
res <- bind_rows(res); write_csv(res, file.path(OUT, "linear_pretrend_slopes.csv"))
options(width = 230)
cat("Linear pre-trend slope (switchers' pre-launch months vs never-treated; log points):\n")
print(as.data.frame(res %>% transmute(spec, pre_window, n_sw = n_switchers, n_ctrl = n_controls,
        slope_pct_per_month = round(100 * slope_per_month, 2), se_pct = round(100 * se, 2), p = signif(p, 2),
        per_year_pct = round(100 * slope_per_year, 1), year_ci = glue("[{round(100*ci_lo_year,1)}, {round(100*ci_hi_year,1)}]"),
        implied_bias_h6_18_pct = round(100 * implied_bias_h6_18, 1), bias_ci = glue("[{round(100*implied_bias_ci_lo,1)}, {round(100*implied_bias_ci_hi,1)}]"),
        quad_sq_p = signif(quad_sq_p, 2))), row.names = FALSE)
