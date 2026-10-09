#!/usr/bin/env Rscript
################################################################################
# mortgage_pretrend_salvage_checks.R  (2026-10-09)
# Two checks on the June-2022 mortgage design (10 switchers vs 20 never-treated,
# controls as X x month FE, state-clustered, pre-period coefficients only):
#  1. Outcome swap: does the 90+ day rate show the pre-launch decline that
#     30-89 shows under never-treated-only controls (pre-launch-only TWFE and
#     Sun-Abraham)?
#  2. Recovery covariates for 30-89: add COVID-era state covariates built from
#     months before the design starts (2019-01..2022-05, every state untreated
#     in the June-2022 design through 2022-08): trough depth (mean log rate
#     2021-01..06 minus mean 2019) and the recovery to date (mean log rate
#     2022-01..05 minus trough), each z-scored and interacted with month FE.
#     Does the e -23..-6 elevation survive?
# NV out. Run from the project root: Rscript analysis/diagnostics/mortgage_pretrend_salvage_checks.R
################################################################################
suppressPackageStartupMessages({ library(dplyr); library(readr); library(fixest); library(glue) })
source("utils/eviction_treatment_schedule.R")
OUT <- "output/mortgage_pretrend_salvage_checks"; dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
COV <- c("judicial_only", "unemp_2019", "hpi_growth_2016q4_2019q4", "age65_pct")
MIN_E <- -24L; MAX_E <- 24L; WIN <- -12:-2; ELEV <- -23:-6
mi <- function(d) as.integer(format(d, "%Y")) * 12L + as.integer(format(d, "%m"))
covs <- read_csv("data/processed/state_covariates_2019.csv", show_col_types = FALSE) %>% select(state_abb, all_of(COV))
load_panel <- function(f) {
  r <- read_csv(f, show_col_types = FALSE) %>% mutate(month_date = as.Date(month_date), treatment_date = as.Date(treatment_date))
  r <- drop_pre_paspa_states(r, "salvage")
  rec <- r %>% group_by(state_abb) %>% summarise(
    pre19 = mean(log_delinquency_rate[month_date >= as.Date("2019-01-01") & month_date <= as.Date("2019-12-01")]),
    trough = mean(log_delinquency_rate[month_date >= as.Date("2021-01-01") & month_date <= as.Date("2021-06-01")]),
    early22 = mean(log_delinquency_rate[month_date >= as.Date("2022-01-01") & month_date <= as.Date("2022-05-01")]), .groups = "drop") %>%
    transmute(state_abb, trough_depth = trough - pre19, recovery_to_2205 = early22 - trough)
  r %>% filter(month_date >= as.Date("2022-06-01"), month_date <= as.Date("2025-03-01")) %>%
    mutate(never = is.na(treatment_date) | treatment_date > as.Date("2025-03-01"), y = log_delinquency_rate,
           e_raw = ifelse(never, NA_integer_, mi(month_date) - mi(treatment_date)),
           e_bin = case_when(never ~ -1L, e_raw < MIN_E ~ MIN_E, e_raw > MAX_E ~ MAX_E, TRUE ~ e_raw),
           cohort = ifelse(never, 100000L, mi(treatment_date)), month_f = factor(month_date)) %>%
    left_join(covs, by = "state_abb") %>% left_join(rec, by = "state_abb") %>%
    mutate(across(c(all_of(COV), trough_depth, recovery_to_2205), ~ as.numeric(scale(.x))))
}
summ <- function(b, V, ee, label) {
  z <- b / sqrt(diag(V)); w <- which(ee %in% WIN); el <- which(ee %in% ELEV); wel <- rep(1 / length(el), length(el))
  wt <- (ee[w] - mean(ee[w])) / sum((ee[w] - mean(ee[w]))^2); s <- sum(wt * b[w]); s_se <- sqrt(as.numeric(t(wt) %*% V[w, w] %*% wt))
  tibble(spec = label, holm_min_p_window = min(p.adjust(2 * pnorm(-abs(z[w])), "holm")), max_abs_t_window = max(abs(z[w])),
         mean_pre_m23_m6 = mean(b[el]), se_mean_m23_m6 = sqrt(as.numeric(t(wel) %*% V[el, el] %*% wel)),
         slope_window = s, slope_se = s_se, slope_p = 2 * pnorm(-abs(s / s_se)))
}
pre_from <- function(cf, V, pat = "^e_bin::") { nm <- names(cf); idx <- grep(paste0(pat, "-?[0-9]+$"), nm); ee <- as.integer(sub(pat, "", nm[idx]))
  k <- idx[ee <= -2]; list(b = cf[k], V = V[k, k], ee = ee[ee <= -2]) }
run <- function(d, xcov, label) {
  terms <- paste(sprintf("i(month_f, %s)", xcov), collapse = " + ")
  dA <- d %>% filter(never | e_raw <= -1)
  mA <- feols(as.formula(paste("y ~ i(e_bin, ref = -1) +", terms, "| state_abb + month_f")), data = dA, cluster = ~state_abb)
  a <- pre_from(coef(mA), vcov(mA))
  mB <- feols(as.formula(paste("y ~ sunab(cohort, e_bin) +", terms, "| state_abb + month_f")), data = d, cluster = ~state_abb)
  bb <- pre_from(coef(mB, agg = TRUE), vcov(mB, agg = TRUE))
  bind_rows(summ(a$b, a$V, a$ee, paste(label, "| A pre-only TWFE, never-treated")),
            summ(bb$b, bb$V, bb$ee, paste(label, "| B Sun-Abraham, never-treated")))
}
d3089 <- load_panel("data/processed/mortgage3089_treatment_panel.csv")
d90   <- load_panel("data/processed/mortgage_treatment_panel.csv")
cat("Recovery covariates (switchers vs never-treated), 30-89:\n")
print(as.data.frame(d3089 %>% distinct(state_abb, never, trough_depth, recovery_to_2205) %>% group_by(never) %>%
        summarise(n = n(), trough_depth_z = round(mean(trough_depth), 2), recovery_z = round(mean(recovery_to_2205), 2))), row.names = FALSE)
res <- bind_rows(
  run(d3089, COV, "30-89, locked 4 covariates"),
  run(d90,   COV, "90+,   locked 4 covariates"),
  run(d3089, c(COV, "trough_depth"), "30-89, + trough depth"),
  run(d3089, c(COV, "trough_depth", "recovery_to_2205"), "30-89, + trough depth + recovery to 2022-05"),
  run(d90,   c(COV, "trough_depth", "recovery_to_2205"), "90+,   + trough depth + recovery to 2022-05"))
write_csv(res, file.path(OUT, "salvage_checks.csv"))
options(width = 220)
print(as.data.frame(res %>% mutate(across(where(is.numeric), ~ signif(.x, 3)))), row.names = FALSE)
