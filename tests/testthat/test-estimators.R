################################################################################
# test-estimators.R
#
# Estimator runners (R/power/run_estimators.R): known-effect recovery on a clean
# toy panel (twfe / did2s / cs), a small null-size smoke test (twfe), failure
# logging on a degenerate panel, and exact output-schema conformance.
#
# run_tests.R sources only the foundation modules, so this file sources the
# injector and the runners (idempotent).
################################################################################

library(lubridate)
.re_root <- if (exists("power_repo_root", mode = "function")) power_repo_root() else "."
if (!exists("impose_effect", mode = "function")) {
  source(file.path(.re_root, "R/power/impose_effects.R"))
}
if (!exists("run_estimator", mode = "function")) {
  source(file.path(.re_root, "R/power/run_estimators.R"))
}

# ---- toy panel with unit + month FE and seeded noise -------------------------
build_toy_est <- function(seed, n_states = 10L, units_per_state = 3L,
                          n_months = 48L,
                          treat = c(S02 = 18L, S04 = 26L, S06 = 34L),
                          noise_sd = 0.15) {
  set.seed(seed)
  states <- sprintf("S%02d", seq_len(n_states))
  md <- seq(as.Date("2016-01-01"), by = "month", length.out = n_months)
  grid <- expand.grid(state_abb = states, u = seq_len(units_per_state),
                      mi = seq_len(n_months), stringsAsFactors = FALSE)
  grid$unit_id    <- paste0(grid$state_abb, "_", grid$u)
  grid$month_date <- md[grid$mi]
  grid$t          <- as.integer(grid$mi)

  units <- unique(grid$unit_id)
  ufe <- setNames(stats::rnorm(length(units)), units)
  tfe <- setNames(stats::rnorm(n_months, 0, 0.3), as.character(seq_len(n_months)))
  grid$y_log1p <- 2 + ufe[grid$unit_id] + tfe[as.character(grid$mi)] +
    stats::rnorm(nrow(grid), 0, noise_sd)

  grid$filings_count <- pmax(round(expm1(grid$y_log1p)), 0)
  grid$renters       <- 1000
  grid$y_lograte <- log(grid$filings_count / grid$renters * 1000 + 0.01)
  grid$y_asinh   <- asinh(grid$filings_count)
  grid$g         <- 0
  panel <- tibble::as_tibble(grid)[, c("unit_id", "state_abb", "month_date",
                                       "t", "filings_count", "renters",
                                       "y_log1p", "y_lograte", "y_asinh", "g")]
  sched <- tibble::tibble(state_abb = names(treat),
                          pseudo_g  = md[as.integer(treat)])
  list(panel = panel, sched = sched)
}

TRUTH <- 0.20

test_that("twfe and did2s recover a known constant effect (deterministic)", {
  toy <- build_toy_est(seed = 100L)
  inj <- impose_effect(toy$panel, toy$sched, mechanism = "deterministic",
                       shape = "step", delta = TRUTH, outcome = "y_log1p",
                       seed = 1L)

  tw <- run_estimator(inj, "twfe")
  r  <- tw[tw$inference == "analytic" & tw$estimand == "simple", ]
  expect_true(r$converged)
  expect_lt(abs(r$att - TRUTH), 3 * r$se)

  d2 <- run_estimator(inj, "did2s")
  rd <- d2[d2$estimand == "simple", ]
  expect_true(rd$converged)
  expect_lt(abs(rd$att - TRUTH), 3 * rd$se)
})

test_that("cs recovers a known constant effect on a staggered toy panel", {
  toy <- build_toy_est(seed = 101L)
  inj <- impose_effect(toy$panel, toy$sched, mechanism = "deterministic",
                       shape = "step", delta = TRUTH, outcome = "y_log1p",
                       seed = 1L)
  cs <- run_estimator(inj, "cs")
  rs <- cs[cs$inference == "analytic" & cs$estimand == "simple", ]
  expect_true(rs$converged)
  expect_lt(abs(rs$att - TRUTH), max(3 * rs$se, 0.03))
  # dynamic + event-window rows are present.
  expect_true(any(cs$estimand == "dynamic"))
  expect_true(any(cs$estimand == "event_0_12"))
  # a genuine bootstrap SE arm is present.
  expect_true(any(cs$inference == "boot_t"))
})

test_that("null-size smoke: twfe rejection rate is not grossly inflated", {
  n_rep <- 30L
  pvals <- numeric(n_rep)
  for (i in seq_len(n_rep)) {
    toy <- build_toy_est(seed = 2000L + i)
    inj <- impose_effect(toy$panel, toy$sched, mechanism = "deterministic",
                         shape = "step", delta = 0, outcome = "y_log1p",
                         seed = 1L)
    tw <- run_estimator(inj, "twfe")
    r  <- tw[tw$inference == "analytic" & tw$estimand == "simple", ]
    pvals[i] <- r$p
  }
  rej <- mean(pvals < 0.05, na.rm = TRUE)
  expect_lt(rej, 0.25)
})

test_that("degenerate panel (no controls for cs) is logged, not thrown", {
  # All states treated at the same date: CS has no valid comparison group.
  toy <- build_toy_est(seed = 300L,
                       treat = setNames(rep(24L, 10L), sprintf("S%02d", 1:10)))
  inj <- impose_effect(toy$panel, toy$sched, mechanism = "deterministic",
                       shape = "step", delta = TRUTH, outcome = "y_log1p",
                       seed = 1L)
  res <- expect_no_error(run_estimator(inj, "cs"))
  expect_gt(nrow(res), 0L)
  expect_true(any(!res$converged))
})

test_that("returned columns match the fixed schema exactly", {
  toy <- build_toy_est(seed = 400L)
  inj <- impose_effect(toy$panel, toy$sched, mechanism = "deterministic",
                       shape = "step", delta = TRUTH, outcome = "y_log1p",
                       seed = 1L)
  for (est in c("twfe", "did2s", "sunab", "cs", "ldam")) {
    res <- run_estimator(inj, est)
    expect_identical(names(res), .RE_SCHEMA, info = est)
  }
})

test_that("bjs (didimputation) recovers a known constant effect", {
  skip_if_not_installed("didimputation")
  toy <- build_toy_est(seed = 103L)
  inj <- impose_effect(toy$panel, toy$sched, mechanism = "deterministic",
                       shape = "step", delta = TRUTH, outcome = "y_log1p",
                       seed = 1L)
  bj <- run_estimator(inj, "bjs")
  rb <- bj[bj$estimand == "simple", ]
  expect_true(rb$converged)
  expect_lt(abs(rb$att - TRUTH), max(3 * rb$se, 0.03))
  expect_identical(names(bj), .RE_SCHEMA)
  expect_identical(rb$inference, "analytic")
  expect_true(rb$n_treated_clusters == 3L && rb$n_control_clusters == 7L)
})

test_that("bjs failure is logged, not thrown (all states treated same date)", {
  skip_if_not_installed("didimputation")
  toy <- build_toy_est(seed = 301L,
                       treat = setNames(rep(24L, 10L), sprintf("S%02d", 1:10)))
  inj <- impose_effect(toy$panel, toy$sched, mechanism = "deterministic",
                       shape = "step", delta = TRUTH, outcome = "y_log1p",
                       seed = 1L)
  res <- expect_no_error(run_estimator(inj, "bjs"))
  expect_gt(nrow(res), 0L)
})

test_that("longdiff recovers a known constant effect on the toy panel", {
  # Cohort-specific long differences (Ben's design, audited 2026-08-03):
  # baseline mean over g-30..g-7, post mean over g..g+11, cohort-calendar
  # control differencing, equal-treated aggregation, delete-one-state
  # jackknife. On the 48-month toy, S02 (g=18) lacks 50% baseline coverage
  # and must be dropped; S04 (g=26) and S06 (g=34) are supported.
  toy <- build_toy_est(seed = 104L)
  inj <- impose_effect(toy$panel, toy$sched, mechanism = "deterministic",
                       shape = "step", delta = TRUTH, outcome = "y_log1p",
                       seed = 1L)
  ld <- run_estimator(inj, "longdiff")
  rs <- ld[ld$estimand == "simple", ]
  expect_true(rs$converged)
  expect_identical(rs$inference, "jack")
  expect_identical(rs$n_treated_clusters, 2L)
  expect_identical(rs$n_control_clusters, 7L)
  expect_lt(abs(rs$att - TRUTH), max(3 * rs$se, 0.05))
  expect_identical(names(ld), .RE_SCHEMA)
})

test_that("longdiff failure is logged, not thrown (no never-treated controls)", {
  toy <- build_toy_est(seed = 302L,
                       treat = setNames(rep(30L, 10L), sprintf("S%02d", 1:10)))
  inj <- impose_effect(toy$panel, toy$sched, mechanism = "deterministic",
                       shape = "step", delta = TRUTH, outcome = "y_log1p",
                       seed = 1L)
  res <- expect_no_error(run_estimator(inj, "longdiff"))
  expect_gt(nrow(res), 0L)
  expect_true(any(!res$converged))
})

test_that("ldam recovers a known constant effect and returns both arms", {
  toy <- build_toy_est(seed = 104L)
  inj <- impose_effect(toy$panel, toy$sched, mechanism = "deterministic",
                       shape = "step", delta = TRUTH, outcome = "y_log1p",
                       seed = 1L)
  ld <- run_estimator(inj, "ldam")
  expect_identical(names(ld), .RE_SCHEMA)
  ra <- ld[ld$inference == "analytic" & ld$estimand == "simple", ]
  rj <- ld[ld$inference == "jack" & ld$estimand == "simple", ]
  expect_true(ra$converged)
  expect_true(rj$converged)
  # same profiled point estimate on both rows; jack only changes the SE.
  expect_identical(ra$att, rj$att)
  expect_true(is.finite(ra$se) && ra$se > 0)
  # Recovery is judged against the jack arm: the analytic SE conditions on
  # theta-hat inside the lag adjustment and understates the sampling spread
  # on this unit-FE toy (sampling SD ~0.08 across seeds vs analytic SE
  # ~0.02) — which is what the blinded size gate exists to measure, not a
  # unit-test failure. The jack arm resamples the full profiled NLS.
  expect_lt(abs(rj$att - TRUTH), max(3 * rj$se, 0.03))
})

test_that("ldam failure is logged, not thrown (treatment constant after lag)", {
  # Every state treated from month 1: A_it = 1 on every row that has a lag,
  # so the treatment indicator is constant and theta is unidentified.
  toy <- build_toy_est(seed = 301L,
                       treat = setNames(rep(1L, 10L), sprintf("S%02d", 1:10)))
  inj <- impose_effect(toy$panel, toy$sched, mechanism = "deterministic",
                       shape = "step", delta = TRUTH, outcome = "y_log1p",
                       seed = 1L)
  res <- expect_no_error(run_estimator(inj, "ldam"))
  expect_identical(names(res), .RE_SCHEMA)
  expect_true(all(!res$converged))
  expect_true(all(!is.na(res$error_msg)))
})

# ---- LP-DiD cell weighting (corrected 2026-08-24) ----------------------------
# Frisch-Waugh-Lovell: a cell-FE regression of dy on D contributes each cell's
# own DiD beta_c with weight  w_c * N_c * Var_c(D). The three schemes therefore
# target three different convex combinations. This fixture makes the three
# targets numerically distinct by varying the treated share across cells, and
# is noiseless so each cell's DiD is exactly its assigned beta.
.lpdid_w_fixture <- function() {
  mk <- function(cell, n_tr, n_ct, b) {
    data.frame(cell = cell, D = c(rep(1L, n_tr), rep(0L, n_ct)), b = b,
               stringsAsFactors = FALSE)
  }
  d <- rbind(mk("c1", 1L, 20L, 1), mk("c2", 6L,  6L, 2),
             mk("c3", 2L, 10L, 3), mk("c4", 4L,  4L, 4))
  d$dy   <- d$b * d$D
  d$cell <- factor(d$cell)
  d
}

test_that(".re_lpdid_weights: each scheme hits its closed-form estimand", {
  d <- .lpdid_w_fixture()
  agg <- stats::aggregate(cbind(N = rep(1, nrow(d)), Ntr = d$D) ~ cell + b, d, sum)
  p   <- agg$Ntr / agg$N
  target_vwatt    <- weighted.mean(agg$b, agg$N * p * (1 - p))
  target_cellsize <- weighted.mean(agg$b, agg$N)
  target_ewatt    <- weighted.mean(agg$b, agg$Ntr)

  # the fixture must actually discriminate, else the test proves nothing
  expect_gt(abs(target_ewatt - target_cellsize), 0.1)
  expect_gt(abs(target_ewatt - target_vwatt), 0.05)

  fit <- function(scheme) {
    d$rw <- .re_lpdid_weights(d$D, d$cell, scheme)
    as.numeric(stats::coef(fixest::feols(dy ~ D | cell, data = d,
                                         weights = ~rw, warn = FALSE,
                                         notes = FALSE))["D"])
  }
  expect_equal(fit("ewatt"),    target_ewatt,    tolerance = 1e-10)
  expect_equal(fit("cellsize"), target_cellsize, tolerance = 1e-10)
  expect_equal(fit("vwatt"),    target_vwatt,    tolerance = 1e-10)
})

test_that(".re_lpdid_weights: vwatt is unweighted OLS, and ewatt is not cellsize", {
  d <- .lpdid_w_fixture()
  ols <- as.numeric(stats::coef(fixest::feols(dy ~ D | cell, data = d,
                                              warn = FALSE, notes = FALSE))["D"])
  d$rw <- .re_lpdid_weights(d$D, d$cell, "vwatt")
  wls <- as.numeric(stats::coef(fixest::feols(dy ~ D | cell, data = d,
                                              weights = ~rw, warn = FALSE,
                                              notes = FALSE))["D"])
  expect_equal(wls, ols, tolerance = 1e-12)
  expect_false(isTRUE(all.equal(.re_lpdid_weights(d$D, d$cell, "ewatt"),
                                .re_lpdid_weights(d$D, d$cell, "cellsize"))))
})

test_that("lpdid honors lpdid_weights and lpdid_pmd end to end", {
  # Low noise and six cohorts: with a HOMOGENEOUS delta every weighting scheme
  # targets the same number, so this test checks that the knobs are wired and
  # that each scheme is unbiased -- NOT that they differ materially. They can
  # only differ materially under cohort heterogeneity, which is what the
  # closed-form .re_lpdid_weights tests above cover.
  toy <- build_toy_est(seed = 321L, n_states = 16L, n_months = 60L,
                       treat = c(S02 = 20L, S04 = 24L, S06 = 28L,
                                 S08 = 32L, S10 = 36L, S12 = 40L),
                       noise_sd = 0.02)
  inj <- impose_effect(toy$panel, toy$sched, mechanism = "deterministic",
                       shape = "step", delta = TRUTH, outcome = "y_log1p",
                       seed = 7L)
  run1 <- function(sp) {
    r <- run_estimator(inj, estimator = "lpdid", spec = sp)
    r$att[r$inference == "analytic"][1]
  }
  a_ewatt    <- run1(list(lpdid_weights = "ewatt"))
  a_cellsize <- run1(list(lpdid_weights = "cellsize"))
  a_vwatt    <- run1(list(lpdid_weights = "vwatt"))
  a_pmd1     <- run1(list(lpdid_weights = "ewatt", lpdid_pmd = 1L))

  for (a in list(a_ewatt, a_cellsize, a_vwatt, a_pmd1)) {
    expect_true(is.finite(a))
    expect_equal(a, TRUTH, tolerance = 0.02)
  }
  # the knobs are live: each names a distinct estimator, not an alias
  expect_false(isTRUE(all.equal(a_ewatt, a_cellsize)))
  expect_false(isTRUE(all.equal(a_ewatt, a_vwatt)))
  expect_false(isTRUE(all.equal(a_ewatt, a_pmd1)))

  # the default is the corrected EWATT scheme, not the pre-2026-08-24 one
  expect_equal(run1(list()), a_ewatt, tolerance = 1e-12)
})

test_that("event_clean compares mature outcomes with a shared pre-launch baseline", {
  toy <- build_toy_est(seed = 812L, n_states = 12L, n_months = 60L,
                       treat = c(S02 = 26L, S04 = 32L), noise_sd = 0.005)
  toy$sched$pseudo_launch <- as.Date(c("2017-08-01", "2018-02-01"))

  # A launched state whose maturity event is beyond the panel must be dirty,
  # not a control for the two supported cohorts.
  toy$sched <- dplyr::bind_rows(
    toy$sched,
    tibble::tibble(state_abb = "S06", pseudo_g = as.Date("2025-01-01"),
                   pseudo_launch = as.Date("2017-06-01")))

  inj <- impose_effect(toy$panel, toy$sched, mechanism = "deterministic",
                       shape = "step", delta = TRUTH, outcome = "y_log1p",
                       seed = 8L)

  # Put a large transitory movement in every legal-to-maturity interval. The
  # clean estimator should ignore it in the baseline; legacy event anchoring
  # deliberately uses it and therefore targets a different contrast.
  launch <- setNames(toy$sched$pseudo_launch, toy$sched$state_abb)
  event  <- setNames(toy$sched$pseudo_g, toy$sched$state_abb)
  in_buildup <- !is.na(launch[inj$state_abb]) &
    inj$month_date >= launch[inj$state_abb] &
    inj$month_date < event[inj$state_abb]
  inj$y_sim[in_buildup] <- inj$y_sim[in_buildup] + 0.70
  inj$y_sim[inj$state_abb == "S06" &
              inj$month_date >= launch[["S06"]]] <-
    inj$y_sim[inj$state_abb == "S06" &
                inj$month_date >= launch[["S06"]]] + 5

  fit1 <- function(anchor) {
    r <- run_estimator(
      inj, estimator = "lpdid",
      spec = list(lpdid_anchor = anchor, lpdid_hmin = 0L,
                  lpdid_post = 0L, lpdid_pmd = 3L,
                  lpdid_weights = "ewatt"))
    r$att[r$inference == "analytic"][1]
  }
  clean <- fit1("event_clean")
  legacy <- fit1("event")

  expect_true(is.finite(clean))
  expect_equal(clean, TRUTH, tolerance = 0.03)
  expect_gt(abs(clean - legacy), 0.40)
})

test_that("lpdid analytic CI uses stack-contributing clusters, not panel-wide states", {
  toy <- build_toy_est(seed = 909L, n_states = 8L, units_per_state = 1L,
                       n_months = 40L, treat = c(S02 = 20L), noise_sd = 0.01)
  inj <- impose_effect(toy$panel, toy$sched, mechanism = "deterministic",
                       shape = "step", delta = TRUTH, outcome = "y_log1p",
                       seed = 9L)

  # S08 is present in the simulated panel -- so it counts toward the
  # panel-wide state total -- but its series ends before month 20, the only
  # cohort's mature outcome month, so every one of its rows is NA at the one
  # (t, h) cell this spec identifies and it contributes zero rows to the
  # stacked LP-DiD regression.
  inj <- inj[!(inj$state_abb == "S08" & inj$t > 10L), ]

  r <- run_estimator(inj, estimator = "lpdid",
                     spec = list(lpdid_hmin = 0L, lpdid_post = 0L,
                                 lpdid_pmd = 3L, lpdid_weights = "ewatt"))
  row <- r[r$inference == "analytic" & r$estimand == "simple", ]
  expect_true(row$converged)

  # 7 of the 8 panel states reach feols(): the S02 switcher plus the 6
  # full-length controls (S01, S03, S04, S05, S06, S07); S08 is excluded.
  # The analytic CI half-width must use df = 7 - 1 = 6, not the panel-wide
  # df = 8 - 1 = 7 that cl$n_total would imply.
  n_contributing <- 7L
  half_width <- row$ci_hi - row$att
  expected_half_width <- stats::qt(1 - 0.05 / 2, df = n_contributing - 1L) *
    row$se
  wrong_half_width <- stats::qt(1 - 0.05 / 2, df = 8L - 1L) * row$se

  expect_equal(half_width, expected_half_width, tolerance = 1e-8)
  expect_false(isTRUE(all.equal(half_width, wrong_half_width)))
})

# ---- LP-DiD <-> Callaway & Sant'Anna numerical equivalence -------------------
# Dube, Girardi, Jorda & Taylor (2023) footnote 23: in a baseline setting
# without covariates, with binary absorbing treatment, and using only
# not-yet-treated observations as controls, REWEIGHTED LP-DiD with FIRST-LAG
# differencing is numerically equivalent to CS at every post-treatment horizon
# h >= 0. This test is the repo's check on both halves of that sentence: it
# should hold for lpdid_weights = "ewatt" + lpdid_pmd = 1, and should NOT hold
# for the pre-2026-08-24 "cellsize" weights or for pre-mean differencing.
#
# NOTE the CS call passes g as DOUBLE. did::att_gt recodes never-treated to
# Inf, and an INTEGER g column truncates that to NA, silently dropping every
# never-treated unit -- the same trap that inflated the 2026-08-20 pretrends
# headline. .re_cs() does as.numeric(g_int) for exactly this reason.
test_that("reweighted first-lag LP-DiD reproduces CS at each horizon", {
  skip_if_not_installed("did")
  toy <- build_toy_est(seed = 55L, n_states = 16L, n_months = 60L,
                       treat = c(S02 = 20L, S04 = 24L, S06 = 28L,
                                 S08 = 32L, S10 = 36L, S12 = 40L),
                       noise_sd = 0.30)
  inj <- impose_effect(toy$panel, toy$sched, mechanism = "deterministic",
                       shape = "step", delta = TRUTH, outcome = "y_log1p",
                       seed = 3L)

  est <- .re_prep(inj)
  dat <- data.frame(id = est$id, t = est$t, g = as.numeric(est$g_int),
                    y = est$y_sim)
  cs <- suppressWarnings(suppressMessages(
    did::att_gt(yname = "y", tname = "t", idname = "id", gname = "g",
                data = dat, control_group = "notyettreated",
                est_method = "reg", bstrap = FALSE, cband = FALSE,
                base_period = "varying", allow_unbalanced_panel = TRUE,
                clustervars = NULL)))
  dyn <- suppressWarnings(suppressMessages(
    did::aggte(cs, type = "dynamic", na.rm = TRUE)))
  hs <- 0:8
  cs_att <- dyn$att.egt[match(hs, dyn$egt)]
  expect_true(all(is.finite(cs_att)))

  arm <- function(w, pmd) {
    vapply(hs, function(h) {
      r <- run_estimator(inj, estimator = "lpdid",
                         spec = list(lpdid_pmd = pmd, lpdid_weights = w,
                                     lpdid_hmin = h, lpdid_post = h))
      r$att[r$inference == "analytic"][1]
    }, numeric(1))
  }

  # the equivalence, to machine precision
  expect_equal(arm("ewatt", 1L), cs_att, tolerance = 1e-10)

  # and it is a real constraint: the other three arms are materially different
  expect_gt(max(abs(arm("cellsize", 1L) - cs_att)), 1e-3)  # pre-fix weights
  expect_gt(max(abs(arm("vwatt",    1L) - cs_att)), 1e-4)  # variance-weighted
  expect_gt(max(abs(arm("ewatt",    3L) - cs_att)), 1e-3)  # pre-mean-differenced
})

test_that("lpdid wild: fwl engine reproduces the legacy dummy-expansion engine", {
  # 8 states => 2^8 = 256 < B = 999, so boottest() fully enumerates the
  # Rademacher draws: both engines are deterministic and see the SAME draw
  # set — any p-value gap is algebra, not simulation noise. delta = 0 keeps
  # the p-values interior (multiples of 1/256) instead of piling up at ~0.
  toy <- build_toy_est(seed = 555L, n_states = 8L)
  inj <- impose_effect(toy$panel, toy$sched, mechanism = "deterministic",
                       shape = "step", delta = 0, outcome = "y_log1p",
                       seed = 3L)
  for (w in c("ewatt", "vwatt")) {
    new <- run_estimator(inj, "lpdid",
                         spec = list(lpdid_weights = w, lpdid_wild = TRUE))
    old <- run_estimator(inj, "lpdid",
                         spec = list(lpdid_weights = w, lpdid_wild = TRUE,
                                     lpdid_wild_engine = "dummy"))
    nw <- new[new$inference == "wild", ]
    ow <- old[old$inference == "wild", ]
    expect_true(nw$converged, label = paste0(w, ": fwl wild converged"))
    expect_true(ow$converged, label = paste0(w, ": dummy wild converged"))
    # the wild arm reports the analytic point estimate in both engines
    expect_equal(nw$att, new$att[new$inference == "analytic"][1],
                 tolerance = 1e-10)
    expect_equal(nw$att, ow$att, tolerance = 1e-10)
    # engine equivalence: same p-value and CI on the enumerated draw set
    expect_equal(nw$p, ow$p, tolerance = 1e-8)
    expect_equal(c(nw$ci_lo, nw$ci_hi), c(ow$ci_lo, ow$ci_hi),
                 tolerance = 1e-6)
  }
})
