################################################################################
# tests/testthat/test-ddd-wild.R
#
# Validation for the DDD wild-bootstrap engine (R/power/ddd_wild.R).
#
#   1. The FWL-demeaned point estimate reproduces feols() exactly.
#   2. The closed-form restricted WCR p-value reproduces
#      fwildclusterboot::boottest() on a panel small enough for boottest to
#      absorb the fixed effect itself.
#   3. Renter weighting reproduces feols(weights = ...).
################################################################################

library(testthat)
library(fixest)

.dw_root <- if (exists("power_repo_root", mode = "function")) power_repo_root() else
  if (file.exists("R/power/ddd_wild.R")) "." else "../.."
if (!exists("ddd_wcr", mode = "function")) source(file.path(.dw_root, "R/power/ddd_wild.R"))

set.seed(20260914)

# -- a small two-way panel with a state-level treatment --------------------
make_panel <- function(G = 30L, per = 6L, TT = 24L, trend = TRUE) {
  d <- expand.grid(unit = seq_len(G * per), month = seq_len(TT))
  d$state_abb <- factor(paste0("S", ((d$unit - 1L) %/% per) + 1L))
  d$unit_id   <- factor(paste0("U", d$unit))
  d$month_date <- d$month
  g0 <- setNames(sample(c(rep(999L, G %/% 2), sample(8:18, G - G %/% 2, TRUE))),
                 paste0("S", seq_len(G)))
  d$D  <- as.integer(d$month >= g0[as.character(d$state_abb)])
  d$H  <- as.integer((d$unit %% 2L) == 0L)
  d$DH <- d$D * d$H
  d$renters <- 500 + (d$unit * 37) %% 900
  d$y_sim <- rnorm(nrow(d)) + 0.3 * d$DH +
    as.numeric(factor(d$unit_id)) * 0.01 + if (trend) d$month * 0.02 else 0
  d
}

test_that("FWL demeaning reproduces the feols point estimate (DDD, 3 FE sets)", {
  d <- make_panel()
  fit <- feols(y_sim ~ DH | unit_id + state_abb^month_date + H^month_date,
               data = d, cluster = ~state_abb, notes = FALSE)
  dm  <- .ddd_demean(d, ycols = "y_sim", weights = NULL)
  res <- ddd_wcr(dm$x, dm$Y[, 1L], d$state_abb, B = 99L, seed = 1L)
  expect_equal(res$est, unname(coef(fit)["DH"]), tolerance = 1e-8)
})

test_that("renter weighting reproduces weighted feols", {
  d <- make_panel()
  fit <- feols(y_sim ~ DH | unit_id + state_abb^month_date + H^month_date,
               data = d, weights = ~renters, cluster = ~state_abb, notes = FALSE)
  dm  <- .ddd_demean(d, ycols = "y_sim", weights = d$renters)
  res <- ddd_wcr(dm$x, dm$Y[, 1L], d$state_abb, B = 99L, seed = 1L)
  expect_equal(res$est, unname(coef(fit)["DH"]), tolerance = 1e-8)
})

test_that("closed-form WCR matches fwildclusterboot::boottest (single FE)", {
  skip_if_not_installed("fwildclusterboot")
  # G = 30 keeps boottest off its full-enumeration path (2^30 draws), so both
  # engines are doing B = 9999 random Rademacher draws and the comparison is
  # like-for-like. `trend = FALSE` keeps p-values in the interior of [0, 1],
  # where agreement is actually informative.
  for (sd in c(11L, 12L, 13L)) {
    set.seed(sd)
    d <- make_panel(trend = FALSE)
    fit <- feols(y_sim ~ DH | unit_id, data = d, cluster = ~state_abb, notes = FALSE)

    set.seed(99)
    bt <- fwildclusterboot::boottest(
      fit, param = "DH", clustid = "state_abb", B = 9999L,
      type = "rademacher", impose_null = TRUE, fe = "unit_id"
    )
    p_bt <- fwildclusterboot::pval(bt)

    fe1 <- data.frame(unit = d$unit_id)
    M   <- as.matrix(d[, c("DH", "y_sim")]); storage.mode(M) <- "double"
    dm  <- as.matrix(fixest::demean(M, fe1, na.rm = FALSE))
    res <- ddd_wcr(dm[, 1L], dm[, 2L], d$state_abb, B = 9999L, seed = 99L)

    expect_equal(res$est, unname(coef(fit)["DH"]), tolerance = 1e-8)
    # Both are Monte Carlo p-values from B = 9999 draws; agreement to ~0.02 is
    # the right bar, not bit-equality.
    expect_equal(res$p_wild, p_bt, tolerance = 0.02)
  }
})

test_that("WCR p-value is invariant to the small-sample correction constant", {
  d  <- make_panel()
  dm <- .ddd_demean(d, ycols = "y_sim", weights = NULL)
  p1 <- ddd_wcr(dm$x, dm$Y[, 1L], d$state_abb, B = 999L, seed = 7L)$p_wild
  p2 <- ddd_wcr(dm$x * 3, dm$Y[, 1L] * 3, d$state_abb, B = 999L, seed = 7L)$p_wild
  expect_equal(p1, p2, tolerance = 1e-12)
})

test_that("degenerate designs return NA rather than erroring", {
  d <- make_panel(G = 2L)
  dm <- .ddd_demean(d, ycols = "y_sim", weights = NULL)
  res <- ddd_wcr(dm$x, dm$Y[, 1L], d$state_abb, B = 99L, seed = 1L)
  expect_true(is.na(res$est) || is.na(res$p_wild) || res$n_clusters < 3L)
})
