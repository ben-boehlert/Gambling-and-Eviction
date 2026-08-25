################################################################################
# cv_predictability.R
#
# Cross-validated predictability machinery shared by the adoption-predictability
# diagnostics. Extracted from adoption_predictability_prepaspa.R on 2026-08-21 so
# that the political/institutional block comparison uses the IDENTICAL estimator,
# fold scheme and permutation null as the macro/eviction blocks -- otherwise the
# block comparison is confounded by the evaluation method.
#
# Expects a data frame carrying: ever (logical), months (numeric, NA if never),
# surv_time (numeric), plus numeric predictor columns. Factors must be expanded
# to numeric dummies by the caller.
#
# Requires: tidyverse, survival. Tuning constants K / R_MAIN / R_NULL / PERM are
# defined here and may be overridden by the caller BEFORE sourcing.
################################################################################

suppressPackageStartupMessages({
  library(tidyverse)
  library(survival)
})

# ============================================================ CV machinery ====
# WHY NOT LEAVE-ONE-OUT: with a weak predictor, LOO makes the training base rate
# move against the held-out outcome (drop an adopter -> the remaining sample has
# a lower adoption rate -> the held-out adopter gets a LOWER fitted probability).
# That intercept shift alone perfectly inverts the ranking, so LOO AUC collapses
# toward 0 instead of 0.5 under the null. Verified directly on mort_slope: 51
# distinct fitted probabilities, coefficient -0.007, AUC exactly 0.
# Stratified K-fold holds the base rate fixed in every training fold and removes
# the artifact. Every metric is still compared to a permutation null computed
# through the identical CV loop.

K       <- 5
R_MAIN  <- 200    # CV repeats for the reported estimate
R_NULL  <- 4      # CV repeats inside each permutation draw
PERM    <- 1000

auc <- function(y, p) {
  if (n_distinct(y) < 2) return(NA_real_)
  r <- rank(p); n1 <- sum(y == 1); n0 <- sum(y == 0)
  (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

# stratified fold assignment: each fold gets the same mix of 1s and 0s
strat_folds <- function(y, k) {
  f <- integer(length(y))
  for (lev in unique(y)) {
    idx <- which(y == lev)
    f[sample(idx)] <- rep_len(seq_len(k), length(idx))
  }
  f
}

cv_binary <- function(X, y, reps) {
  a <- numeric(reps); b <- numeric(reps)
  for (r in seq_len(reps)) {
    fold <- strat_folds(y, K); p <- numeric(length(y))
    for (kk in seq_len(K)) {
      tr <- fold != kk; te <- !tr
      fit <- suppressWarnings(glm.fit(X[tr, , drop = FALSE], y[tr], family = binomial()))
      cf  <- fit$coefficients; cf[is.na(cf)] <- 0
      p[te] <- 1 / (1 + exp(-drop(X[te, , drop = FALSE] %*% cf)))
    }
    a[r] <- auc(y, p); b[r] <- mean((p - y)^2)
  }
  c(auc = mean(a, na.rm = TRUE), brier = mean(b))
}

cv_ols_r2 <- function(X, y, reps) {
  v <- numeric(reps)
  for (r in seq_len(reps)) {
    fold <- sample(rep_len(seq_len(K), length(y))); yh <- numeric(length(y))
    for (kk in seq_len(K)) {
      tr <- fold != kk; te <- !tr
      bb <- tryCatch(qr.solve(X[tr, , drop = FALSE], y[tr]), error = function(e) NULL)
      yh[te] <- if (is.null(bb)) mean(y[tr]) else drop(X[te, , drop = FALSE] %*% bb)
    }
    v[r] <- 1 - sum((y - yh)^2) / sum((y - mean(y))^2)
  }
  mean(v)
}

cindex <- function(time, event, lp) {
  as.numeric(survival::concordance(Surv(time, event) ~ lp, reverse = TRUE)$concordance)
}

cv_cox_c <- function(X, time, event, reps) {
  v <- numeric(reps)
  for (r in seq_len(reps)) {
    fold <- strat_folds(event, K); lp <- numeric(length(time))
    for (kk in seq_len(K)) {
      tr <- fold != kk; te <- !tr
      fit <- tryCatch(coxph(Surv(time[tr], event[tr]) ~ X[tr, , drop = FALSE]),
                      error = function(e) NULL)
      cf <- if (is.null(fit)) rep(0, ncol(X)) else replace(coef(fit), is.na(coef(fit)), 0)
      lp[te] <- drop(X[te, , drop = FALSE] %*% cf)
    }
    v[r] <- cindex(time, event, lp)
  }
  mean(v, na.rm = TRUE)
}

# --------------------------------------------------------- one full analysis --
evaluate <- function(dat, vars, label, window) {
  d  <- dat %>% drop_na(all_of(vars))
  Xz <- scale(as.matrix(d[, vars, drop = FALSE]))
  X  <- cbind(1, Xz)
  res <- list()

  # ---------- (1) EVER adopt: CV AUC + Brier vs permutation null
  y <- as.numeric(d$ever)
  if (n_distinct(y) == 2) {
    obs  <- cv_binary(X, y, R_MAIN)
    ins  <- suppressWarnings(fitted(glm(y ~ Xz, family = binomial())))
    base <- mean(y)
    nul  <- replicate(PERM, cv_binary(X, sample(y), R_NULL))
    res$ever <- tibble(
      window = window, model = label, outcome = "ever adopt online",
      n = nrow(d), events = sum(y), n_pred = length(vars),
      insample_auc = auc(y, ins), cv_auc = obs["auc"],
      cv_auc_null_mean = mean(nul["auc", ]),
      p_auc = mean(nul["auc", ] >= obs["auc"] - 1e-12),
      cv_brier = obs["brier"], brier_intercept_only = mean((base - y)^2),
      brier_skill = 1 - obs["brier"] / mean((base - y)^2),
      p_brier = mean(nul["brier", ] <= obs["brier"] + 1e-12))
  }

  # ---------- (2) TIMING among adopters: out-of-sample R^2
  da <- d %>% filter(ever)
  if (nrow(da) > length(vars) + 3) {
    Xa <- cbind(1, scale(as.matrix(da[, vars, drop = FALSE])))
    ya <- da$months
    obs <- cv_ols_r2(Xa, ya, R_MAIN)
    nul <- replicate(PERM, cv_ols_r2(Xa, sample(ya), R_NULL))
    res$timing <- tibble(
      window = window, model = label, outcome = "months to adoption (adopters)",
      n = nrow(da), events = nrow(da), n_pred = length(vars),
      insample_r2 = summary(lm(ya ~ scale(as.matrix(da[, vars, drop = FALSE]))))$r.squared,
      cv_r2 = obs, cv_r2_null_mean = mean(nul),
      p_r2 = mean(nul >= obs - 1e-12), sd_outcome = sd(ya))
  }

  # ---------- (3) TIMING with censoring: CV Cox concordance
  ev <- as.numeric(d$ever)
  obs <- cv_cox_c(Xz, d$surv_time, ev, max(50, R_MAIN %/% 4))
  # BUGFIX 2026-08-21: this previously re-ran cv_cox_c on the UNPERMUTED data,
  # so the "null" was just fold-assignment noise around the observed value --
  # obs and null mean coincided by construction and every Cox p-value came out
  # near 0.5 regardless of signal. The null must break the link between X and
  # the outcome, so permute the design rows against the (time, event) pairs.
  nul <- replicate(PERM %/% 4, {
    idx <- sample(nrow(Xz))
    cv_cox_c(Xz[idx, , drop = FALSE], d$surv_time, ev, 1)
  })
  res$cox <- tibble(
    window = window, model = label, outcome = "adoption hazard (Cox, censored)",
    n = nrow(d), events = sum(ev), n_pred = length(vars),
    cv_cindex = obs, cindex_null_mean = mean(nul),
    p_cindex = mean(nul >= obs - 1e-12))

  res
}

