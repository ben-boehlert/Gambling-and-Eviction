################################################################################
# test-effects.R
#
# Effect injection (R/power/impose_effects.R): zero-effect identity, count
# augmentation properties, reproducibility, expected-injection calibration,
# zero-count injectability, thinning nonnegativity, and effect-shape windows.
#
# run_tests.R sources only the foundation modules, so this file sources the
# injector itself (idempotent).
################################################################################

library(lubridate)
.re_root <- if (exists("power_repo_root", mode = "function")) power_repo_root() else "."
if (!exists("impose_effect", mode = "function")) {
  source(file.path(.re_root, "R/power/impose_effects.R"))
}

# ---- toy panel builder (untreated by construction; constant within unit) -----
build_toy_inject <- function(n_states = 6L, units_per_state = 2L,
                             n_months = 36L, base_count = 100,
                             treat_states = c("S1", "S2", "S3"),
                             treat_t = 18L) {
  states <- sprintf("S%d", seq_len(n_states))
  md <- seq(as.Date("2016-01-01"), by = "month", length.out = n_months)
  grid <- expand.grid(state_abb = states, u = seq_len(units_per_state),
                      mi = seq_len(n_months), stringsAsFactors = FALSE)
  grid$unit_id    <- paste0(grid$state_abb, "_", grid$u)
  grid$month_date <- md[grid$mi]
  grid$t          <- as.integer(grid$mi)
  grid$filings_count <- base_count
  grid$renters       <- 1000
  grid$y_log1p   <- log1p(grid$filings_count)
  grid$y_lograte <- log(grid$filings_count / grid$renters * 1000 + 0.01)
  grid$y_asinh   <- asinh(grid$filings_count)
  grid$g         <- 0
  panel <- tibble::as_tibble(grid)[, c("unit_id", "state_abb", "month_date",
                                       "t", "filings_count", "renters",
                                       "y_log1p", "y_lograte", "y_asinh", "g")]
  sched <- tibble::tibble(state_abb = treat_states, pseudo_g = md[treat_t])
  list(panel = panel, sched = sched)
}

toy <- build_toy_inject()

test_that("zero delta / null shape leaves y_sim identical to outcome (both mechanisms)", {
  for (mech in c("deterministic", "count_pois", "count_nb")) {
    # delta = 0, step shape
    inj0 <- impose_effect(toy$panel, toy$sched, mechanism = mech,
                          shape = "step", delta = 0, outcome = "y_log1p",
                          seed = 1L)
    expect_equal(inj0$y_sim, toy$panel$y_log1p, tolerance = 1e-12,
                 info = paste(mech, "delta=0"))
    # null shape, nonzero nominal delta
    injn <- impose_effect(toy$panel, toy$sched, mechanism = mech,
                          shape = "null", delta = 0.2, outcome = "y_log1p",
                          seed = 1L)
    expect_equal(injn$y_sim, toy$panel$y_log1p, tolerance = 1e-12,
                 info = paste(mech, "null shape"))
    expect_true(all(injn$delta_imposed == 0))
  }
})

test_that("count mechanisms return nonnegative integers in y_sim_count", {
  for (mech in c("count_pois", "count_nb")) {
    inj <- impose_effect(toy$panel, toy$sched, mechanism = mech,
                         shape = "step", delta = 0.15, outcome = "y_log1p",
                         seed = 7L)
    expect_true(is.integer(inj$y_sim_count))
    expect_true(all(inj$y_sim_count >= 0L))
    expect_equal(inj$y_sim_count, round(inj$y_sim_count))
  }
})

test_that("same seed reproduces identical y_sim; different seed differs (stochastic)", {
  a <- impose_effect(toy$panel, toy$sched, mechanism = "count_pois",
                     shape = "step", delta = 0.1, seed = 42L)
  b <- impose_effect(toy$panel, toy$sched, mechanism = "count_pois",
                     shape = "step", delta = 0.1, seed = 42L)
  c <- impose_effect(toy$panel, toy$sched, mechanism = "count_pois",
                     shape = "step", delta = 0.1, seed = 43L)
  expect_identical(a$y_sim, b$y_sim)
  expect_false(isTRUE(all.equal(a$y_sim, c$y_sim)))
})

test_that("E[injection] matches exp(delta) for a constant-step Poisson effect", {
  delta <- 0.10
  inj <- impose_effect(toy$panel, toy$sched, mechanism = "count_pois",
                       shape = "step", delta = delta, outcome = "y_log1p",
                       seed = 2024L)
  post <- !is.na(inj$e) & inj$e >= 0L & !is.na(inj$pseudo_g)
  ratio <- mean(inj$y_sim_count[post]) / mean(toy$panel$filings_count[post])
  expect_equal(ratio, exp(delta), tolerance = 0.03)
})

test_that("zero-count rows can still receive injections (mu floored > 0)", {
  # One unit with all-zero counts; large effect. Its post rows must sometimes
  # be positive because mu is floored at max(unit mean, 0.5) = 0.5 > 0.
  tp <- toy$panel
  zrows <- tp$unit_id == "S1_1"
  tp$filings_count[zrows] <- 0
  tp$y_log1p[zrows]   <- log1p(0)
  tp$y_lograte[zrows] <- log(0 / 1000 * 1000 + 0.01)
  tp$y_asinh[zrows]   <- asinh(0)
  inj <- impose_effect(tp, toy$sched, mechanism = "count_pois",
                       shape = "step", delta = 2, outcome = "y_log1p",
                       seed = 5L)
  zpost <- inj$unit_id == "S1_1" & !is.na(inj$e) & inj$e >= 0L
  expect_gt(sum(inj$y_sim_count[zpost]), 0L)
})

test_that("thinning never produces negative counts", {
  for (mech in c("thinning", "count_pois", "count_nb")) {
    inj <- impose_effect(toy$panel, toy$sched, mechanism = mech,
                         shape = "step", delta = -0.3, outcome = "y_log1p",
                         seed = 9L)
    expect_true(all(inj$y_sim_count >= 0L))
  }
})

test_that("effect shapes gate delta_imposed on the correct event-time windows", {
  toy1 <- build_toy_inject(treat_states = "S1", treat_t = 18L)
  base <- toy1$panel
  sd1  <- toy1$sched

  di <- function(shape, params = list()) {
    inj <- impose_effect(base, sd1, mechanism = "deterministic",
                         shape = shape, delta = 0.1, params = params,
                         outcome = "y_log1p", seed = 1L)
    inj[inj$state_abb == "S1", c("e", "delta_imposed")]
  }

  # delayed (onset = 6): zero for 0 <= e < 6, delta for e >= 6.
  d <- di("delayed")
  expect_true(all(d$delta_imposed[!is.na(d$e) & d$e >= 0 & d$e < 6] == 0))
  expect_true(all(abs(d$delta_imposed[!is.na(d$e) & d$e >= 6] - 0.1) < 1e-12))

  # temporary (dur = 12): zero for e >= 12.
  tmp <- di("temporary")
  expect_true(all(tmp$delta_imposed[!is.na(tmp$e) & tmp$e >= 12] == 0))
  expect_true(all(abs(tmp$delta_imposed[!is.na(tmp$e) & tmp$e >= 0 &
                                          tmp$e < 12] - 0.1) < 1e-12))

  # anticipation (antic = 3): nonzero at e = -1.
  an <- di("anticipation")
  expect_true(all(abs(an$delta_imposed[!is.na(an$e) & an$e == -1] - 0.1) < 1e-12))
  expect_true(all(an$delta_imposed[!is.na(an$e) & an$e == -4] == 0))
})
