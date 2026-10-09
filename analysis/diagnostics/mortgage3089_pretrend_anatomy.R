#!/usr/bin/env Rscript
################################################################################
# mortgage3089_pretrend_anatomy.R  (2026-10-09)
# Six diagnostics on the June-2022 30-89 day pre-launch decline (10 switchers
# vs 20 never-treated, never-treated controls only, locked 2019 covariates as
# X x month FE, state-clustered). Statistic throughout: mean pre coefficient
# over e -23..-6 (the "elevated block") from (A) the pre-launch-only TWFE and
# (B) Sun-Abraham with never-treated reference; Holm min-p over -12..-2.
#  1. Permutation placebo: the real 10 launch dates assigned to 10 random
#     never-treated states (real switchers dropped; 10 controls remain).
#  2. Logs vs levels (pp) vs 90+ for reference.
#  3. Unit weights = owner-occupied units with a mortgage (ACS 2019).
#  4. Judicial-only vs non-judicial controls.
#  5. One extra 2019 covariate at a time (FHA/VA share, income, owner-occ,
#     BA+, Black, Hispanic shares; RealtyTrac process days).
#  6. Calendar-time pre-launch gap: switchers' mean log rate minus never-treated
#     mean, pre-launch months only, by calendar month.
# Pre-launch months only; blind. NV out.
# Run from the project root: Rscript analysis/diagnostics/mortgage3089_pretrend_anatomy.R
################################################################################
suppressPackageStartupMessages({ library(dplyr); library(readr); library(fixest); library(glue); library(ggplot2) })
theme_set(theme_minimal())
source("utils/eviction_treatment_schedule.R")
OUT <- "output/mortgage3089_pretrend_anatomy"; dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
set.seed(20261009)
COV <- c("judicial_only", "unemp_2019", "hpi_growth_2016q4_2019q4", "age65_pct")
EXTRA <- c("fha_va_share_2019", "med_hh_income", "owner_occ_pct", "ba_plus_pct", "black_pct", "hispanic_pct", "rt_process_days")
MIN_E <- -24L; MAX_E <- 24L; WIN <- -12:-2; ELEV <- -23:-6; N_PERM <- 300L
mi <- function(d) as.integer(format(d, "%Y")) * 12L + as.integer(format(d, "%m"))
covs <- read_csv("data/processed/state_covariates_2019.csv", show_col_types = FALSE) %>% select(state_abb, all_of(c(COV, EXTRA)))
wts  <- read_csv("data/processed/state_mortgage_weights_2019.csv", show_col_types = FALSE)
wcol <- grep("mortgage", names(wts), value = TRUE)[1]; wts <- wts %>% transmute(state_abb, w_mort = .data[[wcol]])
load_panel <- function(f) {
  r <- read_csv(f, show_col_types = FALSE) %>% mutate(month_date = as.Date(month_date), treatment_date = as.Date(treatment_date))
  drop_pre_paspa_states(r, "anatomy") %>% filter(month_date >= as.Date("2022-06-01"), month_date <= as.Date("2025-03-01")) %>%
    mutate(never = is.na(treatment_date) | treatment_date > as.Date("2025-03-01")) %>%
    filter(never | treatment_date >= as.Date("2022-06-01")) %>%     # June-2022 design: 10 switchers + 20 never-treated
    left_join(covs, by = "state_abb") %>% left_join(wts, by = "state_abb") %>%
    mutate(across(all_of(c(COV, EXTRA)), ~ as.numeric(scale(.x))))
}
prep <- function(d, tdate_col = "treatment_date") {
  # a launch after the panel end (MO, 2025-12) is never-treated here, not a switcher
  d %>% mutate(td = if_else(.data[[tdate_col]] > as.Date("2025-03-01"), as.Date(NA), .data[[tdate_col]]), e_raw = ifelse(is.na(td), NA_integer_, mi(month_date) - mi(td)),
               e_bin = case_when(is.na(td) ~ -1L, e_raw < MIN_E ~ MIN_E, e_raw > MAX_E ~ MAX_E, TRUE ~ e_raw),
               cohort = ifelse(is.na(td), 100000L, mi(td)), month_f = factor(month_date))
}
pre_stats <- function(cf, V, pat = "^e_bin::") {
  nm <- names(cf); idx <- grep(paste0(pat, "-?[0-9]+$"), nm); ee <- as.integer(sub(pat, "", nm[idx])); k <- idx[ee <= -2]; ee <- ee[ee <= -2]
  b <- cf[k]; VV <- V[k, k]; z <- b / sqrt(diag(VV)); w <- which(ee %in% WIN); el <- which(ee %in% ELEV); wel <- rep(1 / length(el), length(el))
  wt <- (ee[w] - mean(ee[w])) / sum((ee[w] - mean(ee[w]))^2)
  c(mean_m23_m6 = mean(b[el]), se_m23_m6 = sqrt(as.numeric(t(wel) %*% VV[el, el] %*% wel)),
    holm_window = min(p.adjust(2 * pnorm(-abs(z[w])), "holm")), slope = sum(wt * b[w]))
}
fit_both <- function(d, y = "log_delinquency_rate", xcov = COV, weights = NULL, label = "") {
  d$y <- d[[y]]; terms <- if (length(xcov)) paste("+", paste(sprintf("i(month_f, %s)", xcov), collapse = " + ")) else ""
  dA <- d %>% filter(is.na(td) | e_raw <= -1)
  wA <- if (is.null(weights)) NULL else dA[[weights]]; wB <- if (is.null(weights)) NULL else d[[weights]]
  mA <- feols(as.formula(paste("y ~ i(e_bin, ref = -1)", terms, "| state_abb + month_f")), data = dA, weights = wA, cluster = ~state_abb)
  mB <- feols(as.formula(paste("y ~ sunab(cohort, e_bin)", terms, "| state_abb + month_f")), data = d, weights = wB, cluster = ~state_abb)
  a <- pre_stats(coef(mA), vcov(mA)); b <- pre_stats(coef(mB, agg = TRUE), vcov(mB, agg = TRUE))
  tibble(spec = label, n_switchers = n_distinct(d$state_abb[!is.na(d$td)]), n_controls = n_distinct(d$state_abb[is.na(d$td)]),
         A_mean = a[1], A_se = a[2], A_holm = a[3], A_slope = a[4], B_mean = b[1], B_se = b[2], B_holm = b[3], B_slope = b[4])
}
d0 <- prep(load_panel("data/processed/mortgage3089_treatment_panel.csv"))
d90 <- prep(load_panel("data/processed/mortgage_treatment_panel.csv"))
res <- list(); res[["base"]] <- fit_both(d0, label = "baseline: 30-89 log, locked covariates")
cat(glue("Baseline: A {round(res$base$A_mean,3)} ± {round(res$base$A_se,3)} | B {round(res$base$B_mean,3)} ± {round(res$base$B_se,3)}\n\n"))

# ---- 1. permutation placebo ----------------------------------------------------
real_dates <- d0 %>% filter(!is.na(td)) %>% distinct(state_abb, td) %>% pull(td)
nt <- d0 %>% filter(is.na(td)) %>% distinct(state_abb) %>% pull()
dnt <- d0 %>% filter(is.na(td))
perm <- vector("list", N_PERM)
for (i in seq_len(N_PERM)) {
  ps <- sample(nt, length(real_dates)); map <- tibble(state_abb = ps, td_perm = sample(real_dates))
  dp <- dnt %>% select(-td) %>% left_join(map, by = "state_abb") %>% prep("td_perm")
  r <- tryCatch(fit_both(dp, label = "perm"), error = function(e) NULL)
  if (!is.null(r)) perm[[i]] <- r %>% mutate(i = i)
}
perm <- bind_rows(perm); write_csv(perm, file.path(OUT, "permutation_placebo.csv"))
pA <- mean(abs(perm$A_mean) >= abs(res$base$A_mean)); pB <- mean(abs(perm$B_mean) >= abs(res$base$B_mean))
pA1 <- mean(perm$A_mean >= res$base$A_mean); pB1 <- mean(perm$B_mean >= res$base$B_mean)
cat(glue("1. PERMUTATION ({nrow(perm)} draws; real dates on 10 random never-treated states, 10 never-treated controls):\n",
         "   A: placebo SD {round(sd(perm$A_mean),3)}, two-sided p = {round(pA,3)}, one-sided {round(pA1,3)}; ",
         "B: placebo SD {round(sd(perm$B_mean),3)}, two-sided p = {round(pB,3)}, one-sided {round(pB1,3)}\n",
         "   share of placebos with B Holm < 0.05: {round(mean(perm$B_holm < 0.05),3)} (real: {signif(res$base$B_holm,2)})\n\n"))
g1 <- ggplot(perm, aes(B_mean)) + geom_histogram(bins = 30, fill = "grey70") + geom_vline(xintercept = res$base$B_mean, colour = "red") +
  labs(x = "Placebo mean pre coefficient, e -23..-6 (Sun-Abraham, never-treated ref)", y = "placebo draws", subtitle = glue("red = real switchers ({round(res$base$B_mean,3)}); two-sided p = {round(pB,3)}"))
ggsave(file.path(OUT, "permutation_placebo.png"), g1, width = 7, height = 4, dpi = 150)

# ---- 2. logs vs levels, and 90+ -------------------------------------------------
res[["levels"]] <- fit_both(d0, y = "delinquency_rate", label = "30-89 in LEVELS (pp)")
res[["log90"]]  <- fit_both(d90, label = "90+ log (reference)")
# ---- 3. mortgage-count weights --------------------------------------------------
res[["wt"]] <- fit_both(d0, weights = "w_mort", label = "30-89 log, weighted by mortgaged units 2019")
# ---- 4. judicial split ------------------------------------------------------------
jud <- read_csv("data/processed/state_covariates_2019.csv", show_col_types = FALSE) %>% select(state_abb, jud = judicial_only)
dj <- d0 %>% left_join(jud, by = "state_abb")
res[["jud_ctrl"]]    <- fit_both(dj %>% filter(!is.na(td) | jud == 1), xcov = setdiff(COV, "judicial_only"), label = "controls = judicial never-treated only")
res[["nonjud_ctrl"]] <- fit_both(dj %>% filter(!is.na(td) | jud == 0), xcov = setdiff(COV, "judicial_only"), label = "controls = non-judicial never-treated only")
res[["jud_sw"]]      <- fit_both(dj %>% filter(is.na(td) | jud == 1), label = "switchers = judicial only (9)")
# ---- 5. extra covariates one at a time --------------------------------------------
bal <- d0 %>% distinct(state_abb, td, across(all_of(EXTRA))) %>% group_by(sw = !is.na(td)) %>% summarise(across(all_of(EXTRA), mean), .groups = "drop")
smd <- (bal[bal$sw, EXTRA] - bal[!bal$sw, EXTRA]) %>% unlist()
for (x in EXTRA) res[[x]] <- fit_both(d0, xcov = c(COV, x), label = glue("+ {x} (switcher-control SMD {round(smd[x],2)})"))
res[["all_extra"]] <- fit_both(d0, xcov = c(COV, EXTRA), label = "+ all seven extras")
res[["none"]] <- fit_both(d0, xcov = character(0), label = "NO covariates")
res <- bind_rows(res); write_csv(res, file.path(OUT, "anatomy_specs.csv"))
options(width = 220)
cat("2-5. SPEC VARIANTS (June-2022, never-treated controls; A = pre-only TWFE, B = Sun-Abraham):\n")
print(as.data.frame(res %>% select(spec, n_switchers, n_controls, A_mean, A_se, A_holm, B_mean, B_se, B_holm, B_slope) %>% mutate(across(where(is.numeric), ~ signif(.x, 3)))), row.names = FALSE)

# ---- 6. calendar-time pre-launch gap ------------------------------------------------
ctrl <- d0 %>% filter(is.na(td)) %>% group_by(month_date) %>% summarise(y_ctrl = mean(log_delinquency_rate), n_ctrl = n(), .groups = "drop")
gap <- d0 %>% filter(!is.na(td), e_raw <= -1) %>% group_by(month_date) %>% summarise(y_sw = mean(log_delinquency_rate), n_sw = n(), states = paste(sort(state_abb), collapse = " "), .groups = "drop") %>%
  inner_join(ctrl, by = "month_date") %>% mutate(gap = y_sw - y_ctrl)
write_csv(gap, file.path(OUT, "calendar_time_prelaunch_gap.csv"))
cat("\n6. CALENDAR-TIME GAP (switchers' pre-launch mean log 30-89 minus never-treated mean):\n")
print(as.data.frame(gap %>% transmute(month_date, n_sw, gap = round(gap, 3))), row.names = FALSE)
g6 <- ggplot(gap, aes(month_date, gap)) + geom_hline(yintercept = 0, linetype = 2) + geom_line() + geom_point(aes(size = n_sw)) +
  labs(x = NULL, y = "Switchers (pre-launch months only) minus never-treated, log 30-89 rate", size = "switchers\nstill pre-launch")
ggsave(file.path(OUT, "calendar_time_prelaunch_gap.png"), g6, width = 8, height = 4.5, dpi = 150)
