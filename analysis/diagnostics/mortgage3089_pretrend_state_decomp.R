#!/usr/bin/env Rscript
################################################################################
# mortgage3089_pretrend_state_decomp.R  (2026-10-09)
# Which switchers drive the 30-89 day TWFE pre-trend on the spliced window
# (pretrends_mortgage3089_twfe_controls, spliced_controls)?
#  (a) leave-one-switcher-out: refit the same TWFE (controls as X x month FE),
#      report the -12..-2 Holm min-p, the mean pre coefficient over e -23..-6
#      (the "elevated" block) and the linear slope over -12..-2;
#      plus block drops: all pre-COVID launchers / all post-COVID launchers.
#  (b) per-switcher raw pre-launch path: log rate minus the never-treated mean
#      by calendar month, re-centred at e = -1; mean over e -23..-6 and -5..-2.
# Pre-launch months only; nothing post-launch is read. NV out.
# Run from the project root: Rscript analysis/diagnostics/mortgage3089_pretrend_state_decomp.R
################################################################################
suppressPackageStartupMessages({ library(dplyr); library(readr); library(tidyr); library(fixest); library(glue) })
source("utils/eviction_treatment_schedule.R")
OUT <- "output/mortgage3089_pretrend_state_decomp"; dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
COV <- c("judicial_only", "unemp_2019", "hpi_growth_2016q4_2019q4", "age65_pct")
MIN_E <- -24L; MAX_E <- 24L; WIN <- -12:-2; ELEV <- -23:-6; LATE <- -5:-2

mi <- function(d) as.integer(format(d, "%Y")) * 12L + as.integer(format(d, "%m"))
p <- read_csv("data/processed/mortgage3089_treatment_panel.csv", show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date), treatment_date = as.Date(treatment_date)) %>%
  filter(month_date >= as.Date("2016-01-01"), month_date <= as.Date("2025-03-01"),
         !(month_date >= as.Date("2020-03-01") & month_date <= as.Date("2021-07-01")))
p <- drop_pre_paspa_states(p, "mortgage3089_pretrend_state_decomp") %>%
  mutate(y = log_delinquency_rate,
         e_raw = ifelse(is.na(treatment_date), NA_integer_, mi(month_date) - mi(treatment_date)),
         e_bin = case_when(is.na(e_raw) ~ -1L, e_raw < MIN_E ~ MIN_E, e_raw > MAX_E ~ MAX_E, TRUE ~ e_raw),
         month_f = factor(month_date)) %>%
  left_join(read_csv("data/processed/state_covariates_2019.csv", show_col_types = FALSE) %>%
              select(state_abb, all_of(COV)), by = "state_abb") %>%
  mutate(across(all_of(COV), ~ as.numeric(scale(.x))))
stopifnot(!anyNA(p[COV]))
fml <- as.formula(paste("y ~ i(e_bin, ref = -1) +", paste(sprintf("i(month_f, %s)", COV), collapse = " + "),
                        "| state_abb + month_f"))

fit_pre <- function(d, label) {
  m <- feols(fml, data = d, cluster = ~state_abb)
  cn <- names(coef(m)); idx <- grep("^e_bin::-?[0-9]+$", cn); ee <- as.integer(sub("^e_bin::", "", cn[idx]))
  k <- idx[ee <= -2]; ee <- ee[ee <= -2]; b <- coef(m)[k]; V <- vcov(m)[k, k]
  z <- b / sqrt(diag(V)); w_i <- which(ee %in% WIN)
  wt <- (ee[w_i] - mean(ee[w_i])) / sum((ee[w_i] - mean(ee[w_i]))^2)
  s <- sum(wt * b[w_i]); s_se <- sqrt(as.numeric(t(wt) %*% V[w_i, w_i] %*% wt))
  el <- which(ee %in% ELEV); wel <- rep(1 / length(el), length(el))
  tibble(drop = label, n_states = n_distinct(d$state_abb),
         n_sw_window = d %>% filter(e_raw %in% WIN) %>% distinct(state_abb) %>% nrow(),
         holm_min_p_window = min(p.adjust(2 * pnorm(-abs(z[w_i])), "holm")),
         max_abs_t_window = max(abs(z[w_i])),
         mean_pre_m23_m6 = mean(b[el]), se_mean_m23_m6 = sqrt(as.numeric(t(wel) %*% V[el, el] %*% wel)),
         mean_pre_m5_m2 = mean(b[ee %in% LATE]),
         slope_window = s, slope_se = s_se, slope_p = 2 * pnorm(-abs(s / s_se)))
}

sw <- p %>% filter(!is.na(treatment_date)) %>% distinct(state_abb, treatment_date) %>% arrange(treatment_date)
sw_pre <- sw %>% filter(state_abb %in% (p %>% filter(e_raw <= -2) %>% distinct(state_abb) %>% pull()))
cat(glue("Baseline + {nrow(sw_pre)} leave-one-out refits ...\n"))
base <- fit_pre(p, "none")
loo <- bind_rows(lapply(sw_pre$state_abb, function(s) fit_pre(filter(p, state_abb != s), s)))
pre_covid_l  <- sw$state_abb[sw$treatment_date <  as.Date("2020-03-01")]
post_covid_l <- sw$state_abb[sw$treatment_date >= as.Date("2021-08-01")]
blocks <- bind_rows(
  fit_pre(filter(p, !state_abb %in% pre_covid_l),  "ALL pre-COVID launchers (NJ..NH)"),
  fit_pre(filter(p, !state_abb %in% post_covid_l), "ALL post-COVID launchers (AZ..NC)"))
loo_all <- bind_rows(base, loo, blocks) %>%
  mutate(d_mean_m23_m6 = mean_pre_m23_m6 - base$mean_pre_m23_m6,
         d_slope = slope_window - base$slope_window) %>%
  left_join(sw, by = c("drop" = "state_abb"))
write_csv(loo_all, file.path(OUT, "leave_one_out.csv"))

# (b) per-switcher raw pre-launch path vs never-treated mean
ctrl_mean <- p %>% filter(is.na(treatment_date)) %>% group_by(month_date) %>% summarise(y_ctrl = mean(y), .groups = "drop")
path <- p %>% filter(!is.na(treatment_date), e_raw <= -1, e_raw >= -24) %>%
  left_join(ctrl_mean, by = "month_date") %>% mutate(gap = y - y_ctrl) %>%
  group_by(state_abb, treatment_date) %>%
  mutate(gap_rel = gap - gap[e_raw == -1][1]) %>%
  summarise(n_pre = n(), has_m1 = any(e_raw == -1),
            mean_rel_m23_m6 = mean(gap_rel[e_raw %in% ELEV]), mean_rel_m5_m2 = mean(gap_rel[e_raw %in% LATE]),
            n_m23_m6 = sum(e_raw %in% ELEV), n_m5_m2 = sum(e_raw %in% LATE),
            level_gap_m1 = gap[e_raw == -1][1], .groups = "drop") %>%
  mutate(era = ifelse(treatment_date < as.Date("2020-03-01"), "pre-COVID launch",
                      ifelse(treatment_date < as.Date("2021-08-01"), "launched inside gap", "post-COVID launch"))) %>%
  arrange(treatment_date)
write_csv(path, file.path(OUT, "per_state_pre_path.csv"))

options(width = 220)
cat("\n(a) Leave-one-switcher-out (spliced window, controls). Baseline first; sorted by change in the -23..-6 mean:\n")
print(as.data.frame(loo_all %>% select(drop, treatment_date, n_sw_window, holm_min_p_window, max_abs_t_window,
        mean_pre_m23_m6, se_mean_m23_m6, mean_pre_m5_m2, slope_window, slope_p, d_mean_m23_m6) %>%
        mutate(across(where(is.numeric), ~ signif(.x, 3))) %>%
        arrange(drop != "none", !grepl("^ALL", drop), d_mean_m23_m6)), row.names = FALSE)
cat("\n(b) Per-switcher pre-launch path relative to never-treated mean, re-centred at e = -1 (log points):\n")
print(as.data.frame(path %>% mutate(across(where(is.numeric), ~ signif(.x, 3)))), row.names = FALSE)
cat(glue("\nwritten to {OUT}/\n"))
