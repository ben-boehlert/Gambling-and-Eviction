#!/usr/bin/env Rscript
################################################################################
# mortgage3089_pretrend_state_seasonal_fe.R  (2026-10-09)
# Does state-specific seasonality drive the 30-89 day pre-trend? Every
# pipeline already carries month-by-year FE (common seasonality). Here the
# same pre-trend regressions are refit with state x month-of-year FE added
# (state_abb^moy), which lets each state have its own seasonal profile.
# Specs: staggered TWFE (all states compared) and the never-treated-only
# pre-launch TWFE, on the spliced and June-2022 windows; controls as X x month FE.
# Pre-period coefficients only. NV out.
# Run from the project root: Rscript analysis/diagnostics/mortgage3089_pretrend_state_seasonal_fe.R
################################################################################
suppressPackageStartupMessages({ library(dplyr); library(readr); library(fixest); library(glue) })
source("utils/eviction_treatment_schedule.R")
OUT <- "output/mortgage3089_pretrend_state_seasonal_fe"; dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
COV <- c("judicial_only", "unemp_2019", "hpi_growth_2016q4_2019q4", "age65_pct")
MIN_E <- -24L; MAX_E <- 24L; WIN <- -12:-2; ELEV <- -23:-6
mi <- function(d) as.integer(format(d, "%Y")) * 12L + as.integer(format(d, "%m"))
raw <- read_csv("data/processed/mortgage3089_treatment_panel.csv", show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date), treatment_date = as.Date(treatment_date))
raw <- drop_pre_paspa_states(raw, "mortgage3089_pretrend_state_seasonal_fe") %>%
  left_join(read_csv("data/processed/state_covariates_2019.csv", show_col_types = FALSE) %>% select(state_abb, all_of(COV)), by = "state_abb") %>%
  mutate(across(all_of(COV), ~ as.numeric(scale(.x))), moy = as.integer(format(month_date, "%m")))
cov_terms <- paste(sprintf("i(month_f, %s)", COV), collapse = " + ")
build <- function(min_date, max_date, drop_start, drop_end) raw %>%
  filter(month_date >= min_date, month_date <= max_date, !(month_date >= drop_start & month_date <= drop_end)) %>%
  mutate(never = is.na(treatment_date) | treatment_date > max_date, y = log_delinquency_rate,
         e_raw = ifelse(never, NA_integer_, mi(month_date) - mi(treatment_date)),
         e_bin = case_when(never ~ -1L, e_raw < MIN_E ~ MIN_E, e_raw > MAX_E ~ MAX_E, TRUE ~ e_raw), month_f = factor(month_date))
summ <- function(m, label, fe, sample) {
  cn <- names(coef(m)); idx <- grep("^e_bin::-?[0-9]+$", cn); ee <- as.integer(sub("^e_bin::", "", cn[idx]))
  k <- idx[ee <= -2]; ee <- ee[ee <= -2]; b <- coef(m)[k]; V <- vcov(m)[k, k]; z <- b / sqrt(diag(V))
  w <- which(ee %in% WIN); el <- which(ee %in% ELEV); wel <- rep(1 / length(el), length(el))
  wt <- (ee[w] - mean(ee[w])) / sum((ee[w] - mean(ee[w]))^2); s <- sum(wt * b[w]); s_se <- sqrt(as.numeric(t(wt) %*% V[w, w] %*% wt))
  tibble(window = label, sample = sample, fixed_effects = fe, n_obs = nobs(m),
         holm_min_p_window = min(p.adjust(2 * pnorm(-abs(z[w])), "holm")), max_abs_t_window = max(abs(z[w])),
         mean_pre_m23_m6 = mean(b[el]), se_mean_m23_m6 = sqrt(as.numeric(t(wel) %*% V[el, el] %*% wel)),
         slope_window = s, slope_se = s_se, slope_p = 2 * pnorm(-abs(s / s_se)))
}
res <- list()
for (w in list(list("spliced", "2016-01-01", "2025-03-01", "2020-03-01", "2021-07-01"),
               list("start202206", "2022-06-01", "2025-03-01", "2020-03-01", "2022-05-31"))) {
  d <- build(as.Date(w[[2]]), as.Date(w[[3]]), as.Date(w[[4]]), as.Date(w[[5]])); dA <- d %>% filter(never | e_raw <= -1)
  for (fe in c("state + month", "state x month-of-year + month")) {
    fe_str <- if (fe == "state + month") "| state_abb + month_f" else "| state_abb^moy + month_f"
    f <- as.formula(paste("y ~ i(e_bin, ref = -1) +", cov_terms, fe_str))
    res[[length(res) + 1]] <- summ(feols(f, data = d,  cluster = ~state_abb), w[[1]], fe, "staggered (all states)")
    res[[length(res) + 1]] <- summ(feols(f, data = dA, cluster = ~state_abb), w[[1]], fe, "never-treated only, pre-launch months")
  }
}
res <- bind_rows(res); write_csv(res, file.path(OUT, "state_seasonal_fe.csv"))
options(width = 200)
print(as.data.frame(res %>% mutate(across(where(is.numeric), ~ signif(.x, 3)))), row.names = FALSE)
