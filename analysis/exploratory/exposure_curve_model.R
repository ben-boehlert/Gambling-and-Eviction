#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# Smooth predicted-exposure curves for sports betting market development.
#
# Replaces threshold rules ("treated once handle crosses 50% of its max") with
# a continuous, model-based exposure index: the share of a state's long-run
# market intensity that is expected to be in place at each event month, given
# only the state's legalization cohort — never its own realized handle.
#
#   log(H_st / pop_st) = alpha_s + gamma_{month-of-year}
#                        + f(event month) + (cohort year) x g(event month)
#                        + COVID shutdown dummies + e_st
#
# f is a natural cubic spline in event age (df = 4). The cohort interaction is
# deliberately parsimonious: cohort year enters linearly, interacted with a
# 2-df spline in event age. So cohorts are allowed to differ in the SHAPE of
# their ramp, not in level (level is absorbed by the state fixed effect), and
# the cohort trend is disciplined enough to extrapolate to event ages that
# recent cohorts have not yet reached.
#
# Identification note (age-period-cohort). Within a state, calendar time and
# event age differ by a constant, so with state fixed effects they are exactly
# collinear: the model is identified only up to a linear trend in event age.
# We therefore include calendar MONTH-OF-YEAR effects (seasonality) but NOT
# calendar-year effects, and the COVID shutdown enters as explicit month
# dummies. The consequence is that the common event-age spline absorbs the
# NATIONAL secular growth in betting alongside each state's own ramp, which
# inflates exposure at high event ages. We bound this by anchoring the secular
# trend on the never-online states (NV, MS, MT, SD, NE), whose markets were
# already established throughout the sample and whose per-adult handle growth
# is therefore a ramp-free estimate of the national trend. The anchored index
# is reported alongside the unadjusted one.
#
# Exposure index: I(a, c) = exp( f(a,c) - f(A*, c) ), A* = 48 months.
# The state and seasonal terms cancel in the difference, so I is a pure
# share-of-long-run-intensity, comparable across states of any size.
#
# Leave-one-state-out: the index assigned to state s is predicted from a model
# fit WITHOUT state s, so New Jersey's own trajectory never determines New
# Jersey's exposure measure.
#
# Usage: Rscript analysis/exploratory/exposure_curve_model.R
# Inputs:  data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv
#          data/raw/sports_gambling_legalization_dates.csv
#          data/processed/state_adult_population_monthly.csv
#            (build via analysis/exploratory/build_state_population.R)
# Outputs: data/processed/gambling_exposure_index.csv  <- merge-ready
#          output/exposure_curve/*
# ─────────────────────────────────────────────────────────────────────────────

library(tidyverse)
library(splines)
library(fixest)

theme_set(theme_minimal())

OUT_DIR   <- "output/exposure_curve"
INDEX_OUT <- "data/processed/gambling_exposure_index.csv"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

DF_MAIN    <- 4          # spline df for the common event-age curve
DF_COHORT  <- 2          # spline df for the cohort interaction (parsimony)
A_STAR     <- 48         # event month defining "long-run market intensity"
COHORT_REF <- 2021       # centering year for cohort
COVID_MO   <- seq(as.Date("2020-03-01"), as.Date("2020-07-01"), by = "month")

# ── Data ─────────────────────────────────────────────────────────────────────
handle <- read_csv("data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv",
                   show_col_types = FALSE) %>%
  filter(!is.na(Handle), Handle > 0) %>%
  select(State, month_date, Handle)

dates <- read_csv("data/raw/sports_gambling_legalization_dates.csv",
                  show_col_types = FALSE) %>%
  select(State = state, online_start_date, retail_start_date)

pop <- read_csv("data/processed/state_adult_population_monthly.csv",
                show_col_types = FALSE)

dat <- handle %>%
  inner_join(dates, by = "State") %>%
  filter(!is.na(online_start_date)) %>%
  inner_join(pop, by = c("State", "month_date")) %>%
  mutate(
    a        = interval(online_start_date, month_date) %/% months(1),
    cohort   = year(online_start_date),
    cohort_c = cohort - COHORT_REF,
    moy      = factor(month(month_date)),
    covid    = factor(if_else(month_date %in% COVID_MO,
                              format(month_date, "%Y-%m"), "none")),
    retail_first = !is.na(retail_start_date) & retail_start_date < online_start_date,
    y        = log(Handle / pop18)
  ) %>%
  filter(a >= 0) %>%
  arrange(State, month_date)

dropped <- setdiff(unique(handle$State), unique(dat$State))
cat(sprintf("Estimation sample: %d states, %d state-months, event age 0-%d\n",
            n_distinct(dat$State), nrow(dat), max(dat$a)))
cat(sprintf("Dropped (no online launch date): %s\n", paste(dropped, collapse = ", ")))

# ── Secular-trend anchor from never-online states ────────────────────────────
# These states never launched online betting, so their per-adult handle growth
# over calendar time contains no online ramp. Their trend identifies the
# linear direction that the APC collinearity leaves undetermined above.
anchor_dat <- handle %>%
  filter(State %in% dropped) %>%
  inner_join(pop, by = c("State", "month_date")) %>%
  mutate(y = log(Handle / pop18),
         t_yr = as.numeric(month_date - as.Date("2018-06-01")) / 365.25,
         moy = factor(month(month_date)),
         covid = factor(if_else(month_date %in% COVID_MO,
                                format(month_date, "%Y-%m"), "none")))

fit_anchor    <- feols(y ~ t_yr | State + moy + covid, data = anchor_dat, cluster = ~State)
fit_anchor_nv <- feols(y ~ t_yr | moy + covid,
                       data = anchor_dat %>% filter(State == "Nevada"), vcov = "HC1")
G_HAT <- unname(coef(fit_anchor)["t_yr"])

cat(sprintf("Secular trend anchor: %.1f%% per year (never-online states: %s)\n",
            100 * G_HAT, paste(dropped, collapse = ", ")))
cat(sprintf("  Nevada only: %.1f%% per year\n", 100 * coef(fit_anchor_nv)["t_yr"]))

A_MAX <- max(dat$a)

# ── Fixed spline bases ───────────────────────────────────────────────────────
# Built ONCE on the full support so that every leave-one-out refit and every
# out-of-sample prediction uses identical knots. Recomputing ns() inside each
# subsample would silently move the knots and make curves incomparable.
kn_main   <- quantile(dat$a, probs = seq(0, 1, length.out = DF_MAIN + 1)[-c(1, DF_MAIN + 1)])
kn_cohort <- quantile(dat$a, probs = seq(0, 1, length.out = DF_COHORT + 1)[-c(1, DF_COHORT + 1)])
BOUND     <- c(0, A_MAX)

basis_main   <- function(a) ns(a, knots = kn_main,   Boundary.knots = BOUND)
basis_cohort <- function(a) ns(a, knots = kn_cohort, Boundary.knots = BOUND)

Bnames <- paste0("B", seq_len(DF_MAIN))
Cnames <- paste0("CX", seq_len(DF_COHORT))

attach_basis <- function(d) {
  B <- basis_main(d$a);   colnames(B) <- Bnames
  C <- basis_cohort(d$a); colnames(C) <- Cnames
  bind_cols(d, as_tibble(B), as_tibble(C * d$cohort_c))
}

dat <- attach_basis(dat)

FML <- as.formula(sprintf("y ~ %s + %s | State + moy + covid",
                          paste(Bnames, collapse = " + "),
                          paste(Cnames, collapse = " + ")))

fit_full <- feols(FML, data = dat, cluster = ~State)

# ── Exposure index from a fitted model ───────────────────────────────────────
# I(a,c) = exp( f(a,c) - f(A*,c) ); state and seasonal terms cancel.
contrast_row <- function(a, cohort_c) {
  c(as.numeric(basis_main(a) - basis_main(A_STAR)),
    cohort_c * as.numeric(basis_cohort(a) - basis_cohort(A_STAR)))
}

# `g` removes a secular trend of g log points per year. Because calendar time
# and event age are collinear within state, subtracting a national trend from
# the outcome is exactly equivalent to subtracting g*a/12 from f(a) — so the
# anchored index needs no refit, just this shift.
exposure <- function(model, a, cohort_c, se = FALSE, g = 0) {
  b <- coef(model)[c(Bnames, Cnames)]
  L <- t(vapply(seq_along(a), function(i) contrast_row(a[i], cohort_c[i]),
                numeric(DF_MAIN + DF_COHORT)))
  lin <- as.numeric(L %*% b) - g * (a - A_STAR) / 12
  if (!se) return(exp(lin))
  V <- vcov(model)[c(Bnames, Cnames), c(Bnames, Cnames)]
  sd <- sqrt(pmax(0, rowSums((L %*% V) * L)))
  tibble(index = exp(lin), lo = exp(lin - 1.96 * sd), hi = exp(lin + 1.96 * sd))
}

# ── Leave-one-state-out index ────────────────────────────────────────────────
states <- sort(unique(dat$State))
loo <- map_dfr(states, function(s) {
  m <- feols(FML, data = dat %>% filter(State != s), cluster = ~State)
  d <- dat %>% filter(State == s)
  d %>% transmute(State, month_date, event_month = a, cohort,
                  exposure_loo          = exposure(m, a, cohort_c),
                  exposure_loo_anchored = exposure(m, a, cohort_c, g = G_HAT))
})

index_tbl <- dat %>%
  transmute(State, month_date, event_month = a, cohort, online_start_date,
            handle_per_adult = Handle / pop18,
            exposure_full          = exposure(fit_full, a, cohort_c),
            exposure_full_anchored = exposure(fit_full, a, cohort_c, g = G_HAT)) %>%
  left_join(loo, by = c("State", "month_date", "event_month", "cohort"))

write_csv(index_tbl, INDEX_OUT)

# ── Cohort curves ────────────────────────────────────────────────────────────
cohort_years <- sort(unique(dat$cohort))
obs_max <- dat %>% group_by(cohort) %>% summarise(a_obs_max = max(a), n_states = n_distinct(State))

grid <- expand_grid(cohort = cohort_years, a = 0:A_STAR) %>%
  mutate(cohort_c = cohort - COHORT_REF) %>%
  bind_cols(exposure(fit_full, .$a, .$cohort_c, se = TRUE)) %>%
  mutate(index_anchored = exposure(fit_full, a, cohort_c, g = G_HAT)) %>%
  left_join(obs_max, by = "cohort") %>%
  mutate(extrapolated = a > a_obs_max)

milestones <- grid %>%
  filter(a %in% c(6, 12, 24, 36)) %>%
  transmute(cohort, n_states, a,
            pct = sprintf("%.0f%% [%.0f, %.0f]", 100 * index, 100 * lo, 100 * hi),
            anch = sprintf("%.0f%%", 100 * index_anchored),
            extrapolated) %>%
  pivot_wider(names_from = a, values_from = c(pct, anch, extrapolated),
              names_glue = "m{a}_{.value}")

# ── Specification checks ─────────────────────────────────────────────────────
# (1) Is linear-in-cohort adequate, or do binned cohorts fit materially better?
dat_bin <- dat %>%
  mutate(cbin = cut(cohort, breaks = c(2017, 2019, 2021, 2025),
                    labels = c("2018-19", "2020-21", "2022-24")))
Bc <- basis_cohort(dat_bin$a); colnames(Bc) <- paste0("Craw", seq_len(DF_COHORT))
dat_bin <- bind_cols(dat_bin, as_tibble(Bc))
fml_bin <- as.formula(sprintf("y ~ %s + %s | State + moy + covid",
                              paste(Bnames, collapse = " + "),
                              paste(sprintf("cbin:%s", paste0("Craw", seq_len(DF_COHORT))),
                                    collapse = " + ")))
fit_bin <- feols(fml_bin, data = dat_bin, cluster = ~State)

# (2) Retail-first states may ramp differently (pre-existing customer base)
dat_rf <- dat %>% mutate(across(all_of(Cnames), ~ .x, .names = "keep_{.col}"))
Cr <- basis_cohort(dat_rf$a); colnames(Cr) <- paste0("RF", seq_len(DF_COHORT))
dat_rf <- bind_cols(dat_rf, as_tibble(Cr * as.numeric(dat_rf$retail_first)))
fml_rf <- as.formula(sprintf("y ~ %s + %s + %s | State + moy + covid",
                             paste(Bnames, collapse = " + "),
                             paste(Cnames, collapse = " + "),
                             paste(paste0("RF", seq_len(DF_COHORT)), collapse = " + ")))
fit_rf <- feols(fml_rf, data = dat_rf, cluster = ~State)

# (3) Population-weighted
fit_wt <- feols(FML, data = dat, cluster = ~State, weights = ~pop18)

# ── Report ───────────────────────────────────────────────────────────────────
sink(file.path(OUT_DIR, "exposure_curve_report.txt"), split = TRUE)

cat("\n=== MODEL ===\n")
print(etable(fit_full, fit_bin, fit_rf, fit_wt,
             headers = c("main", "cohort-binned", "retail-first", "pop-weighted"),
             fitstat = ~ n + r2 + wr2))

cat("\n=== PREDICTED EXPOSURE: share of long-run (48-month) market intensity ===\n")
cat("95% CIs from state-clustered vcov of the spline coefficients.\n")
cat("'*' marks event ages this cohort has not yet reached (extrapolated).\n\n")
ms <- milestones %>%
  transmute(cohort, n_states,
            `6mo`  = paste0(m6_pct,  if_else(m6_extrapolated,  "*", "")),
            `12mo` = paste0(m12_pct, if_else(m12_extrapolated, "*", "")),
            `24mo` = paste0(m24_pct, if_else(m24_extrapolated, "*", "")),
            `36mo` = paste0(m36_pct, if_else(m36_extrapolated, "*", "")))
print(as.data.frame(ms), row.names = FALSE)

cat(sprintf("\n--- Same, net of the %.1f%%/yr national secular trend (anchored) ---\n",
            100 * G_HAT))
ms_a <- milestones %>%
  transmute(cohort, n_states, `6mo` = m6_anch, `12mo` = m12_anch,
            `24mo` = m24_anch, `36mo` = m36_anch)
print(as.data.frame(ms_a), row.names = FALSE)

cat("\n--- Robustness: long-run defined at month 24 instead of 48 ---\n")
cat("The 48-month denominator is not observed for the 2023-25 cohorts, so their\n")
cat("index levels rely on extrapolation. Renormalizing on month 24, which every\n")
cat("cohort through 2024 has reached, is a ratio of the curve above and needs no\n")
cat("refit. If the cohort ordering survives, it is not an extrapolation artifact.\n\n")
den24 <- grid %>% filter(a == 24) %>% select(cohort, d24 = index)
ms24 <- grid %>%
  filter(a %in% c(6, 12, 24)) %>%
  left_join(den24, by = "cohort") %>%
  transmute(cohort, a, pct = sprintf("%.0f%%", 100 * index / d24)) %>%
  pivot_wider(names_from = a, values_from = pct, names_glue = "m{a}")
print(as.data.frame(ms24), row.names = FALSE)

cat("\n=== LEAVE-ONE-OUT vs FULL-SAMPLE INDEX ===\n")
diag <- index_tbl %>%
  summarise(
    mean_abs_diff = mean(abs(exposure_loo - exposure_full)),
    max_abs_diff  = max(abs(exposure_loo - exposure_full)),
    cor           = cor(exposure_loo, exposure_full)
  )
print(as.data.frame(diag), row.names = FALSE)
cat("\n  Largest LOO shifts (states whose own data most influenced the curve):\n")
index_tbl %>%
  group_by(State) %>%
  summarise(max_shift = max(abs(exposure_loo - exposure_full)), .groups = "drop") %>%
  arrange(desc(max_shift)) %>% head(6) %>% as.data.frame() %>% print(row.names = FALSE)

cat("\n=== EXPOSURE AT SELECTED EVENT AGES, BY STATE (leave-one-out) ===\n")
index_tbl %>%
  filter(event_month %in% c(12, 24)) %>%
  select(State, cohort, event_month, exposure_loo) %>%
  pivot_wider(names_from = event_month, values_from = exposure_loo,
              names_prefix = "mo") %>%
  arrange(cohort, State) %>%
  mutate(across(starts_with("mo"), ~ round(100 * .x))) %>%
  as.data.frame() %>% print(row.names = FALSE)

sink()

write_csv(grid, file.path(OUT_DIR, "cohort_exposure_curves.csv"))
write_csv(ms,   file.path(OUT_DIR, "cohort_milestones.csv"))

# ── Figures ──────────────────────────────────────────────────────────────────
p1 <- ggplot(grid, aes(a, index, colour = factor(cohort))) +
  geom_ribbon(aes(ymin = lo, ymax = hi, fill = factor(cohort)),
              alpha = 0.10, colour = NA) +
  geom_line(aes(linetype = extrapolated), linewidth = 0.8) +
  geom_hline(yintercept = 1, linetype = "dotted") +
  scale_y_continuous(labels = scales::percent) +
  scale_linetype_manual(values = c("solid", "22"), guide = "none") +
  labs(x = "Months since online legalization",
       y = "Predicted share of long-run market intensity",
       colour = "Legalization\ncohort", fill = "Legalization\ncohort",
       subtitle = str_wrap(sprintf("Long-run = month %d. Dashed segments extrapolate beyond the event ages a cohort has reached.", A_STAR), 95))
ggsave(file.path(OUT_DIR, "cohort_exposure_curves.png"), p1, width = 8, height = 5, dpi = 150)

p1b <- grid %>%
  select(a, cohort, unadjusted = index, anchored = index_anchored) %>%
  pivot_longer(c(unadjusted, anchored), names_to = "spec", values_to = "index") %>%
  ggplot(aes(a, index, colour = factor(cohort))) +
  geom_line(linewidth = 0.8) +
  geom_hline(yintercept = 1, linetype = "dotted") +
  facet_wrap(~ spec) +
  scale_y_continuous(labels = scales::percent) +
  labs(x = "Months since online legalization",
       y = "Predicted share of long-run market intensity",
       colour = "Legalization\ncohort",
       subtitle = str_wrap(sprintf("'anchored' nets out a %.1f%%/yr national secular trend estimated on never-online states, the linear direction the age-period-cohort collinearity leaves undetermined", 100 * G_HAT), 100))
ggsave(file.path(OUT_DIR, "cohort_curves_anchored.png"), p1b, width = 9, height = 4.5, dpi = 150)

p2 <- ggplot(index_tbl, aes(event_month, exposure_loo, group = State,
                            colour = factor(cohort))) +
  geom_line(alpha = 0.8) +
  scale_y_continuous(labels = scales::percent) +
  labs(x = "Months since online legalization",
       y = "Leave-one-out exposure index",
       colour = "Legalization\ncohort",
       subtitle = "Each state's index is predicted from a model fit without that state")
ggsave(file.path(OUT_DIR, "state_exposure_loo.png"), p2, width = 8, height = 5, dpi = 150)

# Fit check: does the smooth curve track realized within-state handle?
resid_chk <- dat %>%
  mutate(fitted = predict(fit_full), resid = y - fitted) %>%
  group_by(a_bin = pmin(a %/% 6 * 6, 60)) %>%
  summarise(mean_resid = mean(resid), sd_resid = sd(resid), n = n(), .groups = "drop")
p3 <- ggplot(resid_chk, aes(a_bin, mean_resid)) +
  geom_col(fill = "grey40") +
  geom_hline(yintercept = 0) +
  labs(x = "Event month (6-month bins)", y = "Mean residual, log handle per adult",
       subtitle = "Systematic drift here would mean the spline is missing curvature in event age")
ggsave(file.path(OUT_DIR, "residuals_by_event_age.png"), p3, width = 8, height = 4, dpi = 150)

cat(sprintf("\nWrote index to %s and diagnostics to %s/\n", INDEX_OUT, OUT_DIR))
