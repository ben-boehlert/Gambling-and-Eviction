#!/usr/bin/env Rscript
################################################################################
# mortgage3089_pretrend_clean_controls.R  (2026-10-09)
# The 30-89 day pre-trend with NEVER-TREATED CONTROLS ONLY, two ways, same
# controls (2019 covariates as X x month FE), state-clustered SE, NV out:
#  (A) pre-launch-only TWFE: treated states contribute ONLY their pre-launch
#      months (e <= -1; e < MIN_E binned); never-treated states (untreated
#      through the sample end, incl. MO) contribute every month. No post-launch
#      observation enters the regression, so already-treated states can never
#      act as controls and the run is blind by construction.
#  (B) Sun-Abraham (fixest::sunab), never-treated as the reference cohort,
#      full sample; only the aggregated pre-period coefficients are extracted.
# Grids: spliced (2016-01..2025-03 minus 2020-03..2021-07), pre-COVID only,
# June-2022 start. Reports Holm min-p and max |t| over -12..-2, the mean pre
# coefficient over e -23..-6 and the linear slope over -12..-2.
# Run from the project root: Rscript analysis/diagnostics/mortgage3089_pretrend_clean_controls.R
################################################################################
suppressPackageStartupMessages({ library(dplyr); library(readr); library(fixest); library(glue); library(ggplot2) })
theme_set(theme_minimal())
source("utils/eviction_treatment_schedule.R")
# PANEL_FILE env (2026-10-09): defaults to the 30-89 panel; the 90+ panel
# (data/processed/mortgage_treatment_panel.csv) writes to a "_90plus" output dir.
PANEL_FILE <- Sys.getenv("PANEL_FILE", "data/processed/mortgage3089_treatment_panel.csv")
UNIT_WEIGHTS <- Sys.getenv("UNIT_WEIGHTS", "")   # "" or "mortgaged_units" (ACS 2019 units with a mortgage)
OUT <- paste0(if (grepl("3089", PANEL_FILE)) "output/mortgage3089_pretrend_clean_controls" else "output/mortgage3089_pretrend_clean_controls_90plus",
              if (UNIT_WEIGHTS == "mortgaged_units") "_wmort" else "")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
COV <- c("judicial_only", "unemp_2019", "hpi_growth_2016q4_2019q4", "age65_pct")
MIN_E <- -24L; MAX_E <- 24L; WIN <- -12:-2; ELEV <- -23:-6
mi <- function(d) as.integer(format(d, "%Y")) * 12L + as.integer(format(d, "%m"))
raw <- read_csv(PANEL_FILE, show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date), treatment_date = as.Date(treatment_date))
raw <- drop_pre_paspa_states(raw, "mortgage3089_pretrend_clean_controls") %>%
  left_join(read_csv("data/processed/state_covariates_2019.csv", show_col_types = FALSE) %>%
              select(state_abb, all_of(COV)), by = "state_abb") %>%
  mutate(across(all_of(COV), ~ as.numeric(scale(.x)))) %>%
  left_join(read_csv("data/processed/state_mortgage_weights_2019.csv", show_col_types = FALSE) %>%
              transmute(state_abb, uw = units_with_mortgage), by = "state_abb")
if (UNIT_WEIGHTS != "mortgaged_units") raw$uw <- 1 else stopifnot(!any(is.na(raw$uw)))
cov_terms <- paste(sprintf("i(month_f, %s)", COV), collapse = " + ")

build <- function(min_date, max_date, drop_start, drop_end) {
  raw %>% filter(month_date >= min_date, month_date <= max_date,
                 !(month_date >= drop_start & month_date <= drop_end)) %>%
    mutate(never = is.na(treatment_date) | treatment_date > max_date,   # MO (2025-12) is never-treated here
           y = log_delinquency_rate,
           e_raw = ifelse(never, NA_integer_, mi(month_date) - mi(treatment_date)),
           e_bin = case_when(never ~ -1L, e_raw < MIN_E ~ MIN_E, e_raw > MAX_E ~ MAX_E, TRUE ~ e_raw),
           cohort = ifelse(never, 100000L, mi(treatment_date)),
           month_f = factor(month_date))
}
summarise_pre <- function(b, V, ee, label, est, n_sw, n_never) {
  z <- b / sqrt(diag(V)); w_i <- which(ee %in% WIN); el <- which(ee %in% ELEV)
  wt <- (ee[w_i] - mean(ee[w_i])) / sum((ee[w_i] - mean(ee[w_i]))^2); wel <- rep(1 / length(el), length(el))
  s <- sum(wt * b[w_i]); s_se <- sqrt(as.numeric(t(wt) %*% V[w_i, w_i] %*% wt))
  list(tests = tibble(run = label, estimator = est, n_switchers_pre = n_sw, n_never_treated = n_never,
         holm_min_p_window = min(p.adjust(2 * pnorm(-abs(z[w_i])), "holm")), max_abs_t_window = max(abs(z[w_i])),
         mean_pre_m23_m6 = mean(b[el]), se_mean_m23_m6 = sqrt(as.numeric(t(wel) %*% V[el, el] %*% wel)),
         slope_window = s, slope_se = s_se, slope_p = 2 * pnorm(-abs(s / s_se))),
       coefs = tibble(run = label, estimator = est, e = ee, coef = unname(b), se = sqrt(diag(V))))
}
run_one <- function(label, min_date, max_date, drop_start, drop_end) {
  d <- build(as.Date(min_date), as.Date(max_date), as.Date(drop_start), as.Date(drop_end))
  n_never <- sum(d %>% distinct(state_abb, never) %>% pull(never))
  # (A) pre-launch-only TWFE with never-treated controls
  dA <- d %>% filter(never | e_raw <= -1)
  n_swA <- dA %>% filter(!never, e_raw <= -2) %>% distinct(state_abb) %>% nrow()
  mA <- feols(as.formula(paste("y ~ i(e_bin, ref = -1) +", cov_terms, "| state_abb + month_f")), data = dA, weights = ~uw, cluster = ~state_abb)
  cn <- names(coef(mA)); idx <- grep("^e_bin::-?[0-9]+$", cn); ee <- as.integer(sub("^e_bin::", "", cn[idx]))
  k <- idx[ee <= -2]; ee <- ee[ee <= -2]
  rA <- summarise_pre(coef(mA)[k], vcov(mA)[k, k], ee, label, "A_preonly_TWFE_never_treated", n_swA, n_never)
  # (B) Sun-Abraham, never-treated reference, full sample; pre coefficients only
  n_swB <- d %>% filter(!never, e_raw <= -2) %>% distinct(state_abb) %>% nrow()
  mB <- feols(as.formula(paste("y ~ sunab(cohort, e_bin) +", cov_terms, "| state_abb + month_f")), data = d, weights = ~uw, cluster = ~state_abb)
  ag <- aggregate(mB, agg = "ATT", full = FALSE)   # placeholder to force aggregation machinery
  cB <- coef(mB, agg = TRUE); VB <- vcov(mB, agg = TRUE)
  nm <- names(cB); idxB <- grep("^e_bin::-?[0-9]+$", nm); eeB <- as.integer(sub("^e_bin::", "", nm[idxB]))
  kB <- idxB[eeB <= -2]; eeB <- eeB[eeB <= -2]
  rB <- summarise_pre(cB[kB], VB[kB, kB], eeB, label, "B_SunAbraham_never_treated", n_swB, n_never)
  cat(glue("{label}: A Holm {signif(rA$tests$holm_min_p_window,2)}, mean(-23..-6) {round(rA$tests$mean_pre_m23_m6,3)} ± {round(rA$tests$se_mean_m23_m6,3)}, slope {round(100*rA$tests$slope_window,2)}%/mo p {signif(rA$tests$slope_p,2)} [{n_swA} sw, {n_never} never]  |  B Holm {signif(rB$tests$holm_min_p_window,2)}, mean {round(rB$tests$mean_pre_m23_m6,3)} ± {round(rB$tests$se_mean_m23_m6,3)}, slope {round(100*rB$tests$slope_window,2)}%/mo p {signif(rB$tests$slope_p,2)}\n\n"))
  list(tests = bind_rows(rA$tests, rB$tests), coefs = bind_rows(rA$coefs, rB$coefs))
}
res <- list(
  run_one("spliced",     "2016-01-01", "2025-03-01", "2020-03-01", "2021-07-01"),
  run_one("precovid",    "2016-01-01", "2020-02-01", "2020-03-01", "2021-07-01"),
  run_one("start202206", "2022-06-01", "2025-03-01", "2020-03-01", "2022-05-31"))
tests <- bind_rows(lapply(res, `[[`, "tests")); coefs <- bind_rows(lapply(res, `[[`, "coefs"))
write_csv(tests, file.path(OUT, "pre_tests.csv")); write_csv(coefs, file.path(OUT, "pre_coefs.csv"))
options(width = 200)
print(as.data.frame(tests %>% mutate(across(where(is.numeric), ~ signif(.x, 3)))), row.names = FALSE)
g <- ggplot(coefs %>% filter(e > MIN_E), aes(e, coef, colour = estimator)) + geom_hline(yintercept = 0, linetype = 2) +
  geom_errorbar(aes(ymin = coef - 1.96 * se, ymax = coef + 1.96 * se), width = .3, alpha = .5, position = position_dodge(.5)) +
  geom_point(size = 1, position = position_dodge(.5)) + facet_wrap(~run, ncol = 1) +
  labs(x = "Months relative to online launch (ref = -1; post-launch not shown)", y = "Pre-period coefficient (log points)", colour = NULL) +
  theme(legend.position = "bottom")
ggsave(file.path(OUT, "pre_coefs_clean_controls.png"), g, width = 8, height = 9, dpi = 150)
