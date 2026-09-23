################################################################################
# R/power/ddd_wild.R
#
# Restricted wild cluster bootstrap (WCR, Rademacher) for the DDD.
#
# WHY NOT boottest. `fwildclusterboot::boottest()` absorbs at most one fixed
# effect via `fe=`; the DDD carries three (unit_id, state x month, H x month),
# and dummy-expanding state x month is ~4,800 columns per bootstrap draw. So we
# do the absorption ONCE per simulated panel with `fixest::demean()` and run the
# bootstrap on the resulting one-regressor FWL model, where every quantity the
# bootstrap needs collapses to two scalars per cluster. B = 999 then costs
# essentially nothing, which is what makes a power simulation affordable.
#
# THE ALGEBRA (one regressor after demeaning; x = DH, y = outcome):
#   q      = x'x                  q_g = x_g'x_g        s_g = x_g'y_g
#   beta   = sum(s_g) / q
#   u_g    = s_g - beta * q_g                      (cluster score)
#   V      = c * sum(u_g^2) / q^2                  t = beta / sqrt(V)
# Under H0: beta = 0 the restricted residuals are y itself, so for Rademacher
# draw w:
#   beta*  = sum(w_g s_g) / q      u*_g = w_g s_g - beta* q_g
#   t*     = beta* / sqrt(c * sum(u*_g^2) / q^2)
#   p      = mean(|t*| >= |t|)
# The finite-sample correction c multiplies t and every t* identically, so the
# WCR p-value is INVARIANT to it -- we never have to match fixest's ssc().
#
# KNOWN APPROXIMATION. The fixed effects are partialled out once and held fixed
# across bootstrap draws rather than re-estimated. This is exactly what
# boottest's own `fe=` path does; `tests/testthat/test-ddd-wild.R` checks the
# two agree on a panel small enough for boottest to handle.
#
# Working directory is assumed to be the repository root.
################################################################################

suppressPackageStartupMessages({
  library(fixest)
})

#' Partial fixed effects out of the DDD design (FWL)
#'
#' @param d Panel with y_sim, DH, unit_id, state_abb, month_date and, when
#'   weighting, `renters`.
#' @param ycols Character vector of outcome columns to demean together.
#' @param weights Optional numeric weight vector (length nrow(d)).
#' @return List with `x` (demeaned DH, weighted) and `Y` (matrix of demeaned,
#'   weighted outcomes), or NULL when the design collapses.
#' @keywords internal
.ddd_demean <- function(d, ycols = "y_sim", weights = NULL) {
  fe <- data.frame(
    unit   = d$unit_id,
    stmo   = paste0(d$state_abb, "_", d$month_date),
    hmo    = paste0(d$H, "_", d$month_date),
    stringsAsFactors = TRUE
  )
  M <- as.matrix(d[, c("DH", ycols), drop = FALSE])
  storage.mode(M) <- "double"

  # nthreads = 1: this runs inside mclapply workers, and a forked child that
  # inherits fixest's OpenMP pool segfaults on macOS. Parallelism is across
  # reps, so single-threaded demeaning is also the right allocation.
  dm <- try(fixest::demean(M, fe, weights = weights, na.rm = FALSE,
                           nthreads = 1L),
            silent = TRUE)
  if (inherits(dm, "try-error")) return(NULL)
  dm <- as.matrix(dm)

  sw <- if (is.null(weights)) 1 else sqrt(weights)
  x  <- dm[, 1L] * sw
  Y  <- dm[, -1L, drop = FALSE] * sw
  if (!any(is.finite(x)) || sum(x^2, na.rm = TRUE) <= 0) return(NULL)
  list(x = x, Y = Y)
}

#' Restricted wild cluster bootstrap on an FWL-demeaned one-regressor model
#'
#' @param x Demeaned (and weighted) regressor.
#' @param y Demeaned (and weighted) outcome.
#' @param cluster Cluster id, same length as x.
#' @param B Bootstrap draws.
#' @param alpha Nominal level.
#' @param seed Optional integer seed for the Rademacher draws.
#' @param ci Compute the wild CI by test inversion (required for recentering).
#' @return List: est, se_crve, t, p_wild, reject_wild, reject_analytic,
#'   ci_lo, ci_hi, n_clusters.
#' @export
ddd_wcr <- function(x, y, cluster, B = 999L, alpha = 0.05, seed = NULL,
                    ci = TRUE) {
  ok <- is.finite(x) & is.finite(y)
  x <- x[ok]; y <- y[ok]; cluster <- cluster[ok]
  g  <- as.integer(factor(cluster))
  G  <- max(g)
  N  <- length(x)
  if (G < 3L || N < 5L) {
    return(list(est = NA_real_, se_crve = NA_real_, t = NA_real_,
                p_wild = NA_real_, reject_wild = NA_integer_,
                reject_analytic = NA_integer_,
                ci_lo = NA_real_, ci_hi = NA_real_, n_clusters = G))
  }

  q   <- sum(x * x)
  q_g <- as.numeric(rowsum(x * x, g))
  s_g <- as.numeric(rowsum(x * y, g))
  est <- sum(s_g) / q

  u_g <- s_g - est * q_g
  # Cluster correction G/(G-1). This is NOT identical to fixest's default ssc
  # (which also carries (N-1)/(N-K) with K counting absorbed FE parameters), so
  # `se_crve` is close to but not bit-identical with feols()'s clustered SE --
  # use the feols path in `.ddd_fit()` when an exactly comparable analytic SE
  # matters. The WCR p-value below is INVARIANT to this constant (see header),
  # so the wild arm is unaffected either way.
  c_ss    <- G / (G - 1)
  V       <- c_ss * sum(u_g^2) / q^2
  se_crve <- sqrt(V)
  tstat   <- est / se_crve

  if (!is.null(seed)) set.seed(seed)
  W  <- matrix(sample(c(-1, 1), G * B, replace = TRUE), nrow = G, ncol = B)

  # colSums(W * s_g), not crossprod(): R on macOS links Accelerate, and a
  # forked mclapply child that inherits an initialised BLAS thread pool
  # segfaults on the first BLAS call. Plain vectorised arithmetic is fork-safe
  # and, at these dimensions (G x B with G ~ 30), no slower.
  # WCR test of H0: beta = b0 with the null imposed. Restricted residuals are
  # y - b0*x, so cluster scores become s0_g = s_g - b0*q_g; the ORIGINAL
  # statistic t(b0) = (beta - b0)/se uses the UNRESTRICTED residuals and so
  # reuses se_crve. The same W is reused at every b0, which is what makes the
  # inverted test below coherent.
  .p_at <- function(b0) {
    s0    <- s_g - b0 * q_g
    bstar <- b0 + colSums(W * s0) / q
    Ustar <- W * s0 - outer(q_g, bstar - b0)
    Vstar <- c_ss * colSums(Ustar^2) / q^2
    tstar <- (bstar - b0) / sqrt(Vstar)
    t0    <- (est - b0) / se_crve
    fin   <- is.finite(tstar)
    if (!any(fin) || !is.finite(t0)) return(NA_real_)
    (1 + sum(abs(tstar[fin]) >= abs(t0))) / (1 + sum(fin))
  }

  p_wild <- .p_at(0)

  # Wild CI by test inversion. Stored so a run can be RECENTERED post hoc --
  # rejection of the cell family's own delta = 0 mean rather than of 0 -- which
  # is the number this project pre-registers (FINDINGS.md section 2). Without
  # it a positive placement bias flatters both size and MDE.
  ci_lo <- NA_real_; ci_hi <- NA_real_
  if (isTRUE(ci) && is.finite(est) && is.finite(se_crve) && se_crve > 0) {
    half <- function(dir) {
      lo <- est; hi <- est + dir * 8 * se_crve
      ph <- .p_at(hi)
      if (!is.finite(ph) || ph >= alpha) return(hi)
      for (i in seq_len(30L)) {
        mid <- (lo + hi) / 2
        if (isTRUE(.p_at(mid) >= alpha)) lo <- mid else hi <- mid
      }
      (lo + hi) / 2
    }
    ci_lo <- half(-1); ci_hi <- half(+1)
  }

  list(est = est, se_crve = se_crve, t = tstat,
       p_wild = p_wild,
       reject_wild     = as.integer(p_wild < alpha),
       reject_analytic = as.integer(2 * stats::pt(-abs(tstat), df = G - 1L) < alpha),
       ci_lo = ci_lo, ci_hi = ci_hi,
       n_clusters = G)
}

#' Fit the DDD with both analytic and wild inference
#'
#' @param d Panel with y_sim, D, DH, H, unit_id, state_abb, month_date, renters.
#' @param B Bootstrap draws.
#' @param alpha Nominal level.
#' @param weight_by "none" (county-equal, legacy) or "renters".
#' @param seed Optional seed for the bootstrap draws.
#' @return Two-row tibble (ddd, did_twfe) with est, se, reject (analytic),
#'   reject_wild, p_wild.
#' @export
ddd_fit_wild <- function(d, B = 999L, alpha = 0.05,
                         weight_by = c("none", "renters"), seed = NULL) {
  weight_by <- match.arg(weight_by)
  w <- if (weight_by == "renters") {
    ww <- as.numeric(d$renters); ww[!is.finite(ww) | ww <= 0] <- NA_real_; ww
  } else NULL

  keep <- if (is.null(w)) rep(TRUE, nrow(d)) else is.finite(w)
  dd   <- d[keep, , drop = FALSE]
  ww   <- if (is.null(w)) NULL else w[keep]

  na_row <- function(est) tibble::tibble(
    estimator = est, est = NA_real_, se = NA_real_, reject = NA_integer_,
    reject_wild = NA_integer_, p_wild = NA_real_,
    ci_lo = NA_real_, ci_hi = NA_real_,
    n_clusters = dplyr::n_distinct(dd$state_abb))

  dm <- .ddd_demean(dd, ycols = "y_sim", weights = ww)
  if (is.null(dm)) return(dplyr::bind_rows(na_row("ddd"), na_row("did_twfe")))

  a <- ddd_wcr(dm$x, dm$Y[, 1L], dd$state_abb, B = B, alpha = alpha, seed = seed)
  ddd_row <- tibble::tibble(
    estimator = "ddd", est = a$est, se = a$se_crve, reject = a$reject_analytic,
    reject_wild = a$reject_wild, p_wild = a$p_wild,
    ci_lo = a$ci_lo, ci_hi = a$ci_hi, n_clusters = a$n_clusters)

  # Comparison TWFE DiD: unit + month FE, treatment D. Same wild machinery.
  fe2 <- data.frame(unit = dd$unit_id, mo = dd$month_date, stringsAsFactors = TRUE)
  M2  <- as.matrix(dd[, c("D", "y_sim")]); storage.mode(M2) <- "double"
  d2  <- try(fixest::demean(M2, fe2, weights = ww, na.rm = FALSE,
                            nthreads = 1L), silent = TRUE)
  did_row <- if (inherits(d2, "try-error")) na_row("did_twfe") else {
    d2 <- as.matrix(d2); sw <- if (is.null(ww)) 1 else sqrt(ww)
    b <- ddd_wcr(d2[, 1L] * sw, d2[, 2L] * sw, dd$state_abb,
                 B = B, alpha = alpha, seed = seed)
    tibble::tibble(estimator = "did_twfe", est = b$est, se = b$se_crve,
                   reject = b$reject_analytic, reject_wild = b$reject_wild,
                   p_wild = b$p_wild, ci_lo = b$ci_lo, ci_hi = b$ci_hi,
                   n_clusters = b$n_clusters)
  }

  dplyr::bind_rows(ddd_row, did_row)
}
