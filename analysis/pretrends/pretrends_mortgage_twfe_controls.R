#!/usr/bin/env Rscript
################################################################################
# pretrends_mortgage_twfe_controls.R  (2026-10-09)
#
# TWFE event-study PRE-TRENDS for a state-month mortgage delinquency panel,
# with optional time-invariant 2019 covariates entered as covariate-by-month
# interactions (the same device the eviction template uses for Sun-Abraham: a
# time-invariant covariate is absorbed by the state FE, so it enters as X_s x
# month FE and lets the counterfactual trend differ by X).
#
#   y_st = sum_{e != -1} beta_e 1[E_st = e] + sum_k X_ks * month FE + a_s + g_t + u
#
# Event time E = months since online launch (calendar months, so a dropped COVID
# block does not shift event time). Endpoints binned at MIN_E / MAX_E;
# never-treated states sit in the reference (-1) bin. SEs clustered by state.
#
# PAP BLINDNESS: only pre-period coefficients (e <= -2) are written, printed or
# plotted. The fitted object is never saved and post-launch coefficients are
# never extracted.
#
# Env knobs (defaults = the 30-89 day, spliced-COVID, locked-covariate run):
#   PANEL_FILE      data/processed/mortgage3089_treatment_panel.csv
#   OUTCOME         log_delinquency_rate | delinquency_rate
#   COVARIATE_FILE  data/processed/state_covariates_2019.csv
#   COVARIATES      judicial_only,unemp_2019,hpi_growth_2016q4_2019q4,age65_pct
#                   (COVARIATES=none = no controls; "" reads as unset)
#   MIN_DATE        2016-01-01      MAX_DATE  2025-03-01
#   DROP_START      2020-03-01      DROP_END  2021-07-01   (COVID block, inclusive)
#   EXCLUDE_STATES  ""  (NV is always dropped via drop_pre_paspa_states())
#   MIN_E / MAX_E   -24 / 24        PRE_WINDOW  -12:-2 (joint test window)
#   OUT_DIR         output/pretrends_mortgage3089_twfe_controls
#   RUN_LABEL       spliced_controls
# Run from the project root:
#   Rscript analysis/pretrends/pretrends_mortgage_twfe_controls.R
################################################################################
suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr); library(fixest)
  library(ggplot2); library(glue)
})
theme_set(theme_minimal())
source("utils/eviction_treatment_schedule.R")  # drop_pre_paspa_states()

getenv1 <- function(k, d) { v <- Sys.getenv(k); if (nzchar(v)) v else d }
parse_list <- function(s) { s <- trimws(strsplit(s, ",")[[1]]); s[nzchar(s)] }

PANEL_FILE     <- getenv1("PANEL_FILE", "data/processed/mortgage3089_treatment_panel.csv")
OUTCOME        <- getenv1("OUTCOME", "log_delinquency_rate")
COVARIATE_FILE <- getenv1("COVARIATE_FILE", "data/processed/state_covariates_2019.csv")
COVARIATES     <- parse_list(getenv1("COVARIATES",
                    "judicial_only,unemp_2019,hpi_growth_2016q4_2019q4,age65_pct"))
if (identical(tolower(COVARIATES), "none")) COVARIATES <- character(0)  # "" reads as unset
MIN_DATE   <- as.Date(getenv1("MIN_DATE", "2016-01-01"))
MAX_DATE   <- as.Date(getenv1("MAX_DATE", "2025-03-01"))
DROP_START <- as.Date(getenv1("DROP_START", "2020-03-01"))
DROP_END   <- as.Date(getenv1("DROP_END",   "2021-07-01"))
EXCLUDE_STATES <- parse_list(getenv1("EXCLUDE_STATES", ""))
MIN_E <- as.integer(getenv1("MIN_E", "-24")); MAX_E <- as.integer(getenv1("MAX_E", "24"))
PRE_WINDOW <- eval(parse(text = getenv1("PRE_WINDOW", "-12:-2")))
OUT_DIR   <- getenv1("OUT_DIR", "output/pretrends_mortgage3089_twfe_controls")
RUN_LABEL <- getenv1("RUN_LABEL", "spliced_controls")
# UNIT_WEIGHTS (2026-10-09): "" (default, equal state weights) or "mortgaged_units"
# = ACS-2019 owner-occupied units with a mortgage (data/processed/state_mortgage_weights_2019.csv).
UNIT_WEIGHTS <- getenv1("UNIT_WEIGHTS", "")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
stopifnot(OUTCOME %in% c("log_delinquency_rate", "delinquency_rate"), max(PRE_WINDOW) <= -2)

# ----------------------------- panel ------------------------------------------
p <- read_csv(PANEL_FILE, show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date), treatment_date = as.Date(treatment_date)) %>%
  filter(month_date >= MIN_DATE, month_date <= MAX_DATE,
         !(month_date >= DROP_START & month_date <= DROP_END),
         !state_abb %in% EXCLUDE_STATES)
p <- drop_pre_paspa_states(p, "pretrends_mortgage_twfe_controls")
p <- p %>% mutate(
  y = .data[[OUTCOME]],
  e_raw = ifelse(is.na(treatment_date), NA_integer_,
                 (as.integer(format(month_date, "%Y")) * 12L + as.integer(format(month_date, "%m"))) -
                 (as.integer(format(treatment_date, "%Y")) * 12L + as.integer(format(treatment_date, "%m")))),
  e_bin = case_when(is.na(e_raw) ~ -1L, e_raw < MIN_E ~ MIN_E, e_raw > MAX_E ~ MAX_E, TRUE ~ e_raw),
  month_f = factor(month_date))
stopifnot(!any(is.na(p$y)))
if (UNIT_WEIGHTS == "mortgaged_units") {
  p <- p %>% left_join(read_csv("data/processed/state_mortgage_weights_2019.csv", show_col_types = FALSE) %>%
                         transmute(state_abb, uw = units_with_mortgage), by = "state_abb")
  stopifnot(!any(is.na(p$uw)))
} else if (nzchar(UNIT_WEIGHTS)) stop("UNIT_WEIGHTS must be \"\" or \"mortgaged_units\"") else p$uw <- 1

# ----------------------------- covariates --------------------------------------
if (length(COVARIATES) > 0) {
  cov_tbl <- read_csv(COVARIATE_FILE, show_col_types = FALSE) %>%
    select(state_abb, all_of(COVARIATES)) %>% distinct()
  p <- p %>% left_join(cov_tbl, by = "state_abb")
  miss <- p %>% distinct(state_abb, across(all_of(COVARIATES))) %>%
    filter(if_any(all_of(COVARIATES), is.na))
  if (nrow(miss) > 0) stop("Covariates missing for: ", paste(miss$state_abb, collapse = ", "))
  # z-score so the X x month FE terms are on a common scale
  p <- p %>% mutate(across(all_of(COVARIATES), ~ as.numeric(scale(.x))))
}

# ----------------------------- sample summary ----------------------------------
sw <- p %>% filter(!is.na(treatment_date)) %>% group_by(state_abb, treatment_date) %>%
  summarise(n_pre = sum(e_raw <= -2), n_pre_window = sum(e_raw %in% PRE_WINDOW),
            n_post = sum(e_raw >= 0), .groups = "drop") %>% arrange(treatment_date)
ctrl <- p %>% filter(is.na(treatment_date)) %>% distinct(state_abb) %>% pull()
summ <- tibble(run = RUN_LABEL, outcome = OUTCOME, covariates = paste(COVARIATES, collapse = "+"), unit_weights = UNIT_WEIGHTS,
               n_obs = nrow(p), n_states = n_distinct(p$state_abb), n_months = n_distinct(p$month_date),
               n_switchers = nrow(sw), n_switchers_with_pre_window = sum(sw$n_pre_window > 0),
               n_never_treated = length(ctrl), min_date = min(p$month_date), max_date = max(p$month_date),
               drop_start = DROP_START, drop_end = DROP_END)
write_csv(summ, file.path(OUT_DIR, glue("sample_summary_{RUN_LABEL}.csv")))
write_csv(sw,   file.path(OUT_DIR, glue("switchers_{RUN_LABEL}.csv")))
cat(glue("[{RUN_LABEL}] {summ$n_states} states ({summ$n_switchers} switchers, ",
         "{summ$n_switchers_with_pre_window} with months in the {min(PRE_WINDOW)}..{max(PRE_WINDOW)} window; ",
         "{summ$n_never_treated} never-treated), {summ$n_months} months, ",
         "{summ$min_date}..{summ$max_date} minus {DROP_START}..{DROP_END}; outcome {OUTCOME}; ",
         "controls: {if (length(COVARIATES)) paste(COVARIATES, collapse = ', ') else 'none'}; ",
         "weights: {if (nzchar(UNIT_WEIGHTS)) UNIT_WEIGHTS else 'equal'}\n\n"))

# ----------------------------- TWFE event study --------------------------------
rhs <- "i(e_bin, ref = -1)"
if (length(COVARIATES) > 0)
  rhs <- paste(rhs, "+", paste(sprintf("i(month_f, %s)", COVARIATES), collapse = " + "))
fml <- as.formula(paste("y ~", rhs, "| state_abb + month_f"))
m <- feols(fml, data = p, weights = ~uw, cluster = ~state_abb)

# ---- extract PRE-period coefficients only (blindness) ----
cn <- names(coef(m))
es_idx <- grep("^e_bin::-?[0-9]+$", cn)                 # event-study dummies only
es_e   <- as.integer(sub("^e_bin::", "", cn[es_idx]))
pre_idx <- es_idx[es_e <= -2]; pre_e <- es_e[es_e <= -2]
b <- coef(m)[pre_idx]; V <- vcov(m)[pre_idx, pre_idx, drop = FALSE]
G <- n_distinct(p$state_abb)
pre <- tibble(run = RUN_LABEL, e = pre_e, coef = unname(b), se = sqrt(diag(V))) %>%
  mutate(ci_lo = coef - 1.96 * se, ci_hi = coef + 1.96 * se,
         binned = e == MIN_E) %>% arrange(e)
write_csv(pre, file.path(OUT_DIR, glue("pre_coefs_{RUN_LABEL}.csv")))

joint <- function(es, label) {
  k <- which(pre_e %in% es); bb <- b[k]; VV <- V[k, k, drop = FALSE]
  W <- as.numeric(t(bb) %*% solve(VV) %*% bb); q <- length(k)
  tibble(run = RUN_LABEL, test = label, window = glue("{min(es)}..{max(es)}"), q = q,
         wald = W, p_chisq = pchisq(W, q, lower.tail = FALSE),
         F = W / q, p_F = pf(W / q, q, G - 1, lower.tail = FALSE))
}
slope <- function(es, label) {   # linear pre-trend through the pre coefficients
  k <- which(pre_e %in% es); ee <- pre_e[k]; w <- (ee - mean(ee)) / sum((ee - mean(ee))^2)
  s <- sum(w * b[k]); s_se <- sqrt(as.numeric(t(w) %*% V[k, k] %*% w))
  tibble(run = RUN_LABEL, test = label, window = glue("{min(es)}..{max(es)}"), q = length(k),
         wald = (s / s_se)^2, p_chisq = 2 * pnorm(-abs(s / s_se)), F = NA_real_, p_F = NA_real_,
         slope_per_month = s, slope_se = s_se)
}
full_pre <- pre_e[!pre$binned]
tests <- bind_rows(
  joint(PRE_WINDOW, "joint_wald_window"),
  joint(full_pre,   "joint_wald_all_unbinned_pre"),
  slope(PRE_WINDOW, "linear_slope_window"),
  slope(full_pre,   "linear_slope_all_unbinned_pre")) %>%
  mutate(n_clusters = G, mean_abs_pre_window = mean(abs(b[pre_e %in% PRE_WINDOW])),
         mean_pre_se_window = mean(sqrt(diag(V))[pre_e %in% PRE_WINDOW]))
# The joint Wald uses the inverse of a state-clustered V estimated from G clusters;
# with few identifying switchers that matrix can be near-singular and the Wald
# explodes while no coefficient is individually distinguishable from zero. Report
# the condition number alongside and a Holm-adjusted per-coefficient test that
# does not invert V.
holm_test <- function(es, label) {
  k <- which(pre_e %in% es); z <- b[k] / sqrt(diag(V)[k]); praw <- 2 * pnorm(-abs(z))
  ev <- eigen(cov2cor(V[k, k]), symmetric = TRUE, only.values = TRUE)$values
  tibble(run = RUN_LABEL, test = label, window = glue("{min(es)}..{max(es)}"), q = length(k),
         wald = NA_real_, p_chisq = min(p.adjust(praw, "holm")), F = NA_real_, p_F = NA_real_,
         max_abs_t = max(abs(z)), corr_condition_number = max(ev) / min(ev))
}
tests <- bind_rows(tests, holm_test(PRE_WINDOW, "holm_min_p_window"),
                   holm_test(full_pre, "holm_min_p_all_unbinned_pre"))
write_csv(tests, file.path(OUT_DIR, glue("pre_tests_{RUN_LABEL}.csv")))

cat(glue("[{RUN_LABEL}] pre-period coefficients (ref e = -1), state-clustered SE, G = {G}:\n"))
print(as.data.frame(pre %>% select(e, coef, se, ci_lo, ci_hi, binned) %>%
        mutate(across(where(is.numeric), ~ round(.x, 4)))), row.names = FALSE)
cat("\n"); print(as.data.frame(tests %>% select(test, window, q, wald, p_chisq, p_F,
        slope_per_month, slope_se, max_abs_t, corr_condition_number) %>%
        mutate(across(where(is.numeric), ~ signif(.x, 3)))), row.names = FALSE)

# ---- pre-period-only plot ----
g <- ggplot(pre %>% filter(!binned), aes(e, coef)) +
  geom_hline(yintercept = 0, linetype = 2) + geom_vline(xintercept = -0.5, colour = "grey60") +
  geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = 0.3, colour = "grey50") +
  geom_point() +
  labs(x = "Months relative to online launch (reference = -1; post-launch not shown)",
       y = if (OUTCOME == "log_delinquency_rate") "Coefficient (log points)" else "Coefficient (pp)",
       subtitle = glue("{RUN_LABEL}: {OUTCOME}; controls: ",
                       "{if (length(COVARIATES)) paste(COVARIATES, collapse = ', ') else 'none'}"))
ggsave(file.path(OUT_DIR, glue("pre_coefs_{RUN_LABEL}.png")), g, width = 8, height = 4.5, dpi = 150)
cat(glue("\n[{RUN_LABEL}] written to {OUT_DIR}/\n"))
