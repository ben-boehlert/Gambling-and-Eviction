#!/usr/bin/env Rscript
################################################################################
# mortgage3089_pretrend_restart_month.R  (2026-10-09)
# Does the 30-89 day TWFE pre-trend (pretrends_mortgage3089_twfe_controls)
# depend on the month the post-COVID sample restarts? Same TWFE (controls as
# X x month FE, state-clustered, endpoints binned at +/-24, ref e = -1), two grids:
#   spliced  : 2016-01..2020-02 kept, gap ends at RESTART - 1 (RESTART varies)
#   postonly : sample is RESTART..2025-03 only
# Reports the -12..-2 Holm min-p, mean pre coef over e -23..-6, slope -12..-2,
# and how many switchers contribute months to the -12..-2 window.
# Pre-period coefficients only. NV out.
# Run from the project root: Rscript analysis/diagnostics/mortgage3089_pretrend_restart_month.R
################################################################################
suppressPackageStartupMessages({ library(dplyr); library(readr); library(fixest); library(glue); library(ggplot2) })
theme_set(theme_minimal())
source("utils/eviction_treatment_schedule.R")
OUT <- "output/mortgage3089_pretrend_restart_month"; dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
COV <- c("judicial_only", "unemp_2019", "hpi_growth_2016q4_2019q4", "age65_pct")
MIN_E <- -24L; MAX_E <- 24L; WIN <- -12:-2; ELEV <- -23:-6
RESTARTS <- as.Date(c("2021-08-01", "2021-11-01", "2022-02-01", "2022-06-01", "2022-09-01",
                      "2022-12-01", "2023-03-01", "2023-06-01"))
mi <- function(d) as.integer(format(d, "%Y")) * 12L + as.integer(format(d, "%m"))
raw <- read_csv("data/processed/mortgage3089_treatment_panel.csv", show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date), treatment_date = as.Date(treatment_date)) %>%
  filter(month_date >= as.Date("2016-01-01"), month_date <= as.Date("2025-03-01"))
raw <- drop_pre_paspa_states(raw, "mortgage3089_pretrend_restart_month") %>%
  mutate(y = log_delinquency_rate,
         e_raw = ifelse(is.na(treatment_date), NA_integer_, mi(month_date) - mi(treatment_date)),
         e_bin = case_when(is.na(e_raw) ~ -1L, e_raw < MIN_E ~ MIN_E, e_raw > MAX_E ~ MAX_E, TRUE ~ e_raw)) %>%
  left_join(read_csv("data/processed/state_covariates_2019.csv", show_col_types = FALSE) %>%
              select(state_abb, all_of(COV)), by = "state_abb") %>%
  mutate(across(all_of(COV), ~ as.numeric(scale(.x))))
fml <- as.formula(paste("y ~ i(e_bin, ref = -1) +", paste(sprintf("i(month_f, %s)", COV), collapse = " + "),
                        "| state_abb + month_f"))
fit_pre <- function(d) {
  d$month_f <- factor(d$month_date)
  m <- feols(fml, data = d, cluster = ~state_abb)
  cn <- names(coef(m)); idx <- grep("^e_bin::-?[0-9]+$", cn); ee <- as.integer(sub("^e_bin::", "", cn[idx]))
  k <- idx[ee <= -2]; ee <- ee[ee <= -2]; b <- coef(m)[k]; V <- vcov(m)[k, k]
  z <- b / sqrt(diag(V)); w_i <- which(ee %in% WIN)
  wt <- (ee[w_i] - mean(ee[w_i])) / sum((ee[w_i] - mean(ee[w_i]))^2)
  s <- sum(wt * b[w_i]); s_se <- sqrt(as.numeric(t(wt) %*% V[w_i, w_i] %*% wt))
  el <- which(ee %in% ELEV); wel <- rep(1 / length(el), length(el))
  list(summary = tibble(n_obs = nrow(d), n_months = n_distinct(d$month_date),
         n_sw_window = d %>% filter(e_raw %in% WIN) %>% distinct(state_abb) %>% nrow(),
         n_sw_window_postcovid = d %>% filter(e_raw %in% WIN, treatment_date >= as.Date("2021-08-01")) %>% distinct(state_abb) %>% nrow(),
         holm_min_p_window = min(p.adjust(2 * pnorm(-abs(z[w_i])), "holm")), max_abs_t_window = max(abs(z[w_i])),
         mean_pre_m23_m6 = mean(b[el]), se_mean_m23_m6 = sqrt(as.numeric(t(wel) %*% V[el, el] %*% wel)),
         slope_window = s, slope_se = s_se, slope_p = 2 * pnorm(-abs(s / s_se))),
       coefs = tibble(e = ee, coef = unname(b), se = sqrt(diag(V))))
}
res <- list(); coefs <- list()
for (r in RESTARTS) { r <- as.Date(r)
  for (design in c("spliced", "postonly")) {
    d <- if (design == "spliced") raw %>% filter(month_date <= as.Date("2020-02-01") | month_date >= r) else raw %>% filter(month_date >= r)
    f <- fit_pre(d); lab <- glue("{design}_{format(r, '%Y-%m')}")
    res[[lab]] <- f$summary %>% mutate(design = design, restart = r, .before = 1)
    coefs[[lab]] <- f$coefs %>% mutate(design = design, restart = r)
    cat(glue("{lab}: Holm {signif(f$summary$holm_min_p_window,2)}, mean(-23..-6) {round(f$summary$mean_pre_m23_m6,3)}, slope {round(100*f$summary$slope_window,2)}%/mo (p {signif(f$summary$slope_p,2)}), {f$summary$n_sw_window} switchers in window ({f$summary$n_sw_window_postcovid} post-COVID)\n\n"))
  }
}
res <- bind_rows(res); coefs <- bind_rows(coefs)
write_csv(res, file.path(OUT, "restart_month_sweep.csv")); write_csv(coefs, file.path(OUT, "restart_month_pre_coefs.csv"))
g <- ggplot(coefs %>% filter(e > MIN_E), aes(e, coef, colour = format(restart, "%Y-%m"))) +
  geom_hline(yintercept = 0, linetype = 2) + geom_line() + geom_point(size = .8) + facet_wrap(~design, ncol = 1) +
  labs(x = "Months relative to online launch (ref = -1; post-launch not shown)", y = "Pre-period coefficient (log points)", colour = "post-COVID restart")
ggsave(file.path(OUT, "restart_month_pre_coefs.png"), g, width = 8, height = 7, dpi = 150)
options(width = 200)
print(as.data.frame(res %>% select(design, restart, n_sw_window, n_sw_window_postcovid, holm_min_p_window, max_abs_t_window, mean_pre_m23_m6, se_mean_m23_m6, slope_window, slope_p) %>% mutate(across(where(is.numeric), ~ signif(.x, 3)))), row.names = FALSE)
