################################################################################
# prewindow_differential_trends.R
#
# QUESTION
#   Do states that legalized online sports betting AFTER June 2022 trend
#   differently from never-legalizing control states during the 12 months
#   2021-07 .. 2022-06?
#
#   This is a pure PRE-TREATMENT diagnostic: every state in the treated group
#   adopts strictly after the window closes, so nothing here reveals a
#   treatment effect (PAP-blindness safe).
#
# SAMPLE
#   Treated  = panel states whose online_start_date > 2022-06-01
#   Control  = panel states with NO row in the legalization schedule
#              (never-legalizers), with NV removed as always-treated via
#              PRE_PASPA_SPORTS_BETTING.
#   States already treated by 2022-06 are EXCLUDED, not used as controls.
#
# TESTS
#   T1  linear differential trend:  y_it = a_i + d_t + b*(D_i * t) + e_it
#   T2  joint event study:          y_it = a_i + d_t + sum_k g_k (D_i * 1[t=k])
#   T3  long difference: mean(last 3 months) - mean(first 3 months), T vs C
#
# INFERENCE
#   (a) state-clustered analytic SEs
#   (b) wild cluster bootstrap (Rademacher, 9999 reps) for T1
#   (c) randomization inference: reassign the treated label across states
#       (n_treated of n_states), 5000 draws, for T1 and T2
#
# POWER
#   Reports the differential trend detectable at 80% power / 5% two-sided
#   (2.80 * SE) in both log points per month and filings/1k renters per month.
#
# Working directory: project root.
################################################################################

suppressPackageStartupMessages({
  library(tidyverse); library(fixest); library(fwildclusterboot)
})
set.seed(20260918)

source("utils/eviction_treatment_schedule.R")

SCHED_FILE <- "data/raw/sports_gambling_legalization_dates.csv"
PANEL_FILE <- "data/raw/state_month_panel_with_treatment.csv"
# EXCLUDE_STATES: comma-separated abbreviations dropped from BOTH arms before
# any estimation, e.g. EXCLUDE_STATES="WA,MN". Outputs land in a suffixed dir so
# an exclusion run never overwrites the headline run.
EXCLUDE <- toupper(trimws(strsplit(Sys.getenv("EXCLUDE_STATES", ""), ",")[[1]]))
EXCLUDE <- EXCLUDE[nzchar(EXCLUDE)]
OUT_DIR    <- if (length(EXCLUDE))
  paste0("output/prewindow_trends_2021h2_ex", paste(EXCLUDE, collapse = "")) else
  "output/prewindow_trends_2021h2"
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

CUTOFF  <- as.Date("2022-06-01")   # adopters after this are "later adopters"
N_BOOT  <- 9999L
N_PERM  <- 5000L

# ---- windows: headline plus two robustness starts -----------------------------
# 2021-07 is the last month of the usual COVID drop window and the month before
# the federal CDC moratorium lapsed (2021-08-26), so the start date is a real
# design choice, not a detail. All three are reported.
WINDOWS <- list(
  `2021-07..2022-06` = c("2021-07-01", "2022-06-01"),
  `2021-08..2022-06` = c("2021-08-01", "2022-06-01"),
  `2021-10..2022-06` = c("2021-10-01", "2022-06-01"),
  # Calendar 2022 only: after the Oct-2021 step and the Feb-2022 trough have
  # passed, and the closest clean stretch to the first adoption (KS, 2022-09).
  `2022-01..2022-06` = c("2022-01-01", "2022-06-01")
)

# ---- data ---------------------------------------------------------------------
pan <- read_csv(PANEL_FILE, show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date))

sched <- load_eviction_treatment_schedule(SCHED_FILE, "online_start_date",
                                          states = EVICTION_STATE_UNIVERSE)

panel_states <- sort(unique(pan$state_abb))
# NOTE: the panel carries a column literally named `treated`. Naming the state
# vectors `treated`/`controls` lets dplyr data-masking bind the COLUMN inside
# filter()/mutate(), which silently produces an all-control sample. Hence the
# CT_ prefix -- do not rename these back.
CT_CONTROL <- eviction_control_states(panel_states, SCHED_FILE, "online_start_date",
                                      censor_end = as.Date("2026-06-01"))
assert_no_pre_paspa_controls(CT_CONTROL, context = "prewindow differential trends")

CT_TREATED <- sched %>%
  filter(state_abb %in% panel_states, !is.na(treat_start), treat_start > CUTOFF) %>%
  pull(state_abb) %>% sort()

if (length(EXCLUDE)) {
  message("Excluding by request: ", paste(EXCLUDE, collapse = " "))
  CT_TREATED <- setdiff(CT_TREATED, EXCLUDE)
  CT_CONTROL <- setdiff(CT_CONTROL, EXCLUDE)
}

stopifnot(length(intersect(CT_TREATED, CT_CONTROL)) == 0)
message("Treated (later adopters): ", paste(CT_TREATED, collapse = " "))
message("Controls (never-legalizers): ", paste(CT_CONTROL, collapse = " "))

build_sample <- function(w0, w1, balanced = TRUE) {
  d <- pan %>%
    filter(state_abb %in% .env$CT_TREATED | state_abb %in% .env$CT_CONTROL,
           month_date >= as.Date(w0), month_date <= as.Date(w1),
           !is.na(filings_per_1k_renters)) %>%
    mutate(D = as.integer(state_abb %in% .env$CT_TREATED))
  n_full <- n_distinct(d$month_date)
  if (balanced) {
    keep <- d %>% count(state_abb) %>% filter(n == n_full) %>% pull(state_abb)
    d <- filter(d, state_abb %in% keep)
  }
  d %>%
    mutate(tnum  = as.integer(factor(month_date)),          # 1..T
           tc    = tnum - mean(sort(unique(tnum))),         # centered trend
           Dt    = D * tc,
           y_log = log1p(filings_per_1k_renters),
           y_lvl = filings_per_1k_renters,
           # boottest() needs factor fixed effects and an explicit fe= argument
           state_abb = factor(state_abb),
           mfac      = factor(month_date)) %>%
    as.data.frame()
}

# ---- estimation ---------------------------------------------------------------
fit_T1 <- function(d, yvar, wts = NULL) {
  f <- as.formula(paste0(yvar, " ~ Dt | state_abb + mfac"))
  if (is.null(wts)) {
    feols(f, data = d, cluster = ~state_abb)
  } else {
    d$.w <- d[[wts]]
    feols(f, data = d, cluster = ~state_abb, weights = ~.w)
  }
}

fit_T2 <- function(d, yvar) {
  f <- as.formula(paste0(yvar, " ~ i(tnum, D, ref = 1) | state_abb + mfac"))
  feols(f, data = d, cluster = ~state_abb)
}

joint_stat <- function(m) {                    # Wald chi2 on all D-by-month terms
  k <- grep("^tnum::", names(coef(m)), value = TRUE)
  b <- coef(m)[k]; V <- vcov(m)[k, k, drop = FALSE]
  as.numeric(t(b) %*% solve(V) %*% b)
}

perm_p <- function(d, yvar, n_perm = N_PERM) {
  states <- sort(unique(as.character(d$state_abb)))
  n_t <- n_distinct(as.character(d$state_abb)[d$D == 1])
  obs1 <- abs(coef(fit_T1(d, yvar))[["Dt"]])
  obs2 <- joint_stat(fit_T2(d, yvar))
  ge1 <- 0L; ge2 <- 0L; ok <- 0L
  for (i in seq_len(n_perm)) {
    tr <- sample(states, n_t)
    dd <- d; dd$D <- as.integer(as.character(d$state_abb) %in% tr); dd$Dt <- dd$D * dd$tc
    s1 <- tryCatch(abs(coef(fit_T1(dd, yvar))[["Dt"]]), error = function(e) NA_real_)
    s2 <- tryCatch(joint_stat(fit_T2(dd, yvar)),        error = function(e) NA_real_)
    if (is.na(s1) || is.na(s2)) next
    ok <- ok + 1L; ge1 <- ge1 + (s1 >= obs1); ge2 <- ge2 + (s2 >= obs2)
  }
  c(p_linear = (ge1 + 1) / (ok + 1), p_joint = (ge2 + 1) / (ok + 1), n_draws = ok)
}

# ---- run ----------------------------------------------------------------------
rows <- list(); es_rows <- list()

for (wn in names(WINDOWS)) {
  w <- WINDOWS[[wn]]
  for (yv in c("y_log", "y_lvl")) {
    for (wt in list(NULL, "renter_occupied_housing_units")) {
      d <- build_sample(w[1], w[2])
      message(sprintf("[fit] %s | %s | wt=%s | states=%d obs=%d T=%d",
                      wn, yv, if (is.null(wt)) "none" else wt,
                      dplyr::n_distinct(d$state_abb), nrow(d),
                      dplyr::n_distinct(d$month_date)))
      m1 <- fit_T1(d, yv, wt)
      b  <- coef(m1)[["Dt"]]; se <- se(m1)[["Dt"]]

      # wild cluster bootstrap on the single linear-trend coefficient
      wcb <- tryCatch({
        bt <- boottest(m1, param = "Dt", clustid = "state_abb", B = N_BOOT,
                       type = "rademacher", fe = "state_abb")
        c(p = bt$p_val, lo = bt$conf_int[1], hi = bt$conf_int[2])
      }, error = function(e) c(p = NA, lo = NA, hi = NA))

      m2 <- fit_T2(d, yv)
      wj <- tryCatch(wald(m2, "tnum::", print = FALSE), error = function(e) NULL)

      pp <- if (is.null(wt)) perm_p(d, yv) else c(p_linear = NA, p_joint = NA, n_draws = NA)

      # long difference (unweighted, T vs C)
      T_ <- sort(unique(d$tnum)); lo3 <- head(T_, 3); hi3 <- tail(T_, 3)
      ld <- d %>% group_by(state_abb, D) %>%
        summarise(diff = mean(.data[[yv]][tnum %in% hi3]) - mean(.data[[yv]][tnum %in% lo3]),
                  .groups = "drop")
      ldt <- t.test(diff ~ D, data = ld)

      rows[[length(rows) + 1]] <- tibble(
        window = wn, outcome = yv,
        weights = if (is.null(wt)) "none" else "renters",
        n_states = n_distinct(d$state_abb),
        n_treated = n_distinct(d$state_abb[d$D == 1]),
        n_control = n_distinct(d$state_abb[d$D == 0]),
        n_obs = nrow(d),
        b_trend_per_month = b, se_cluster = se,
        p_cluster = fixest::pvalue(m1)[["Dt"]],
        p_wildboot = unname(wcb["p"]),
        ci_lo_wildboot = unname(wcb["lo"]), ci_hi_wildboot = unname(wcb["hi"]),
        p_joint_wald = if (is.null(wj) || !is.null(wt)) NA_real_ else wj$p,
        p_linear_perm = unname(pp["p_linear"]),
        p_joint_perm  = unname(pp["p_joint"]),
        mde80_trend_per_month = 2.802 * se,
        mde80_trend_over_window = 2.802 * se * (max(d$tnum) - min(d$tnum)),
        longdiff_TminusC = unname(ldt$estimate[2] - ldt$estimate[1]),
        p_longdiff = ldt$p.value
      )

      if (is.null(wt)) {
        k <- grep("^tnum::", names(coef(m2)), value = TRUE)
        es_rows[[length(es_rows) + 1]] <- tibble(
          window = wn, outcome = yv, term = k,
          period = as.integer(sub("^tnum::([0-9]+):.*$", "\\1", k)),
          estimate = unname(coef(m2)[k]), se = unname(se(m2)[k])
        )
      }
    }
  }
}

res <- bind_rows(rows)
es  <- bind_rows(es_rows)

write_csv(res, file.path(OUT_DIR, "prewindow_trend_tests.csv"))
write_csv(es,  file.path(OUT_DIR, "prewindow_event_study_coefs.csv"))
write_csv(tibble(group = c(rep("treated_later_adopter", length(CT_TREATED)),
                           rep("never_legalizer_control", length(CT_CONTROL))),
                 state_abb = c(CT_TREATED, CT_CONTROL)) %>%
            left_join(sched, by = "state_abb"),
          file.path(OUT_DIR, "prewindow_sample_states.csv"))

cat("\n================ HEADLINE (log outcome, unweighted) ================\n")
print(as.data.frame(res %>% filter(outcome == "y_log", weights == "none") %>%
  select(window, n_treated, n_control, n_obs, b_trend_per_month, se_cluster,
         p_cluster, p_wildboot, p_linear_perm, p_joint_wald, p_joint_perm,
         mde80_trend_per_month, mde80_trend_over_window)), digits = 4)

cat("\n================ FULL GRID ================\n")
print(as.data.frame(res %>% select(window, outcome, weights, b_trend_per_month,
  se_cluster, p_cluster, p_wildboot, p_joint_wald, longdiff_TminusC, p_longdiff)),
  digits = 4)

cat("\nWrote: ", OUT_DIR, "\n")

# ---- figure: event study, headline window, both outcomes ----------------------
theme_set(theme_minimal(base_size = 11))

mlab <- tibble(period = 1:12,
               month  = seq(as.Date("2021-07-01"), as.Date("2022-06-01"), by = "month"))

es_plot <- es %>%
  filter(window == "2021-07..2022-06") %>%
  select(outcome, period, estimate, se) %>%
  bind_rows(tibble(outcome = c("y_log", "y_lvl"), period = 1L,
                   estimate = 0, se = 0)) %>%          # normalized base month
  left_join(mlab, by = "period") %>%
  mutate(outcome = recode(outcome,
                          y_log = "log(1 + filings per 1k renters)",
                          y_lvl = "filings per 1k renters"))

p <- ggplot(es_plot, aes(month, estimate)) +
  geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey40") +
  geom_ribbon(aes(ymin = estimate - 1.96 * se, ymax = estimate + 1.96 * se),
              alpha = 0.15) +
  geom_line(linewidth = 0.5) +
  geom_point(size = 1.5) +
  facet_wrap(~outcome, scales = "free_y") +
  scale_x_date(date_labels = "%b\n%Y", date_breaks = "2 months") +
  labs(x = NULL,
       y = "Later adopters minus never-legalizers",
       subtitle = paste0(sprintf("Pre-treatment only: %d post-June-2022 adopters vs %d never-legalizers, ",
                                 length(CT_TREATED), length(CT_CONTROL) - 1L),
                         "base month 2021-07.\nState and month fixed effects; ",
                         "state-clustered 95% bands."))

ggsave(file.path(OUT_DIR, "prewindow_event_study.png"), p,
       width = 9, height = 4, dpi = 200)
cat("Wrote figure: ", file.path(OUT_DIR, "prewindow_event_study.png"), "\n")
