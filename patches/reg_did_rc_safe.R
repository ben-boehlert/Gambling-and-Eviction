################################################################################
# reg_did_rc_safe.R
#
# Patched version of DRDID::reg_did_rc() with guards against empty matrices
#
# SOURCE: DRDID package (https://github.com/pedrohcgs/DRDID)
# AUTHOR: Pedro H. C. Sant'Anna and Jun Zhao
# LICENSE: GPL-3 (same as DRDID)
#
# MODIFICATIONS:
# - Added guards before fastglm calls to check for empty design matrices
# - Returns structured NA result when cells are empty instead of crashing
# - Provides clear error messages about which cell is empty
#
# ATTRIBUTION:
# This is a derived work from DRDID::reg_did_rc
# Original: https://github.com/pedrohcgs/DRDID/blob/master/R/reg_did_rc.R
# Modifications by: Claude (Anthropic)
# Date: 2026-01-19
################################################################################

#' @import stats
#' @keywords internal
reg_did_rc_safe <-function(y, post, D, covariates, i.weights = NULL,
                      boot = FALSE, boot.type = "weighted", nboot = NULL,
                      inffunc = FALSE){
  #-----------------------------------------------------------------------------
  # D as vector
  D <- as.vector(D)
  # post as vector
  post <- as.vector(post)
  # Sample size
  n <- length(D)
  # outcome of interested
  y <- as.vector(y)
  # Covariate vector
  if(is.null(covariates)){
    int.cov <- as.matrix(rep(1,n))
  } else{
    int.cov <- as.matrix(covariates)
  }

  # Weights
  if(is.null(i.weights)) {
    i.weights <- as.vector(rep(1, n))
  } else if(min(i.weights) < 0) stop("i.weights must be non-negative")
  # Normalize weights
  i.weights <- i.weights/mean(i.weights)

  #-----------------------------------------------------------------------------
  # GUARD 1: Check for empty control pre-treatment cell
  #-----------------------------------------------------------------------------
  pre_filter <- (D == 0) & (post == 0)
  n_control_pre <- sum(pre_filter)

  if (n_control_pre == 0) {
    warning("SUPPORT ISSUE: No control units in pre-treatment period (n_control_pre=0). ",
            "Cannot estimate outcome regression. Returning ATT=NA.")
    return(structure(
      list(
        ATT = NA_real_,
        se = NA_real_,
        uci = NA_real_,
        lci = NA_real_,
        boots = NULL,
        att.inf.func = if (inffunc) rep(0, n) else NULL,
        call.param = match.call(),
        argu = list(panel = FALSE, boot = boot, boot.type = ifelse(boot, boot.type, "not_used"),
                    nboot = nboot, type = "or"),
        support_issue = "n_control_pre=0",
        n_cells = list(n_control_pre = 0, n_control_post = NA, n_treat_pre = NA, n_treat_post = NA)
      ),
      class = "drdid"
    ))
  }

  #-----------------------------------------------------------------------------
  # GUARD 2: Check for empty control post-treatment cell
  #-----------------------------------------------------------------------------
  post_filter <- (D == 0) & (post == 1)
  n_control_post <- sum(post_filter)

  if (n_control_post == 0) {
    warning("SUPPORT ISSUE: No control units in post-treatment period (n_control_post=0). ",
            "Cannot estimate outcome regression. Returning ATT=NA.")
    return(structure(
      list(
        ATT = NA_real_,
        se = NA_real_,
        uci = NA_real_,
        lci = NA_real_,
        boots = NULL,
        att.inf.func = if (inffunc) rep(0, n) else NULL,
        call.param = match.call(),
        argu = list(panel = FALSE, boot = boot, boot.type = ifelse(boot, boot.type, "not_used"),
                    nboot = nboot, type = "or"),
        support_issue = "n_control_post=0",
        n_cells = list(n_control_pre = n_control_pre, n_control_post = 0, n_treat_pre = NA, n_treat_post = NA)
      ),
      class = "drdid"
    ))
  }

  #-----------------------------------------------------------------------------
  # GUARD 3: Check for empty treated cells (less critical but still important)
  #-----------------------------------------------------------------------------
  n_treat_pre <- sum((D == 1) & (post == 0))
  n_treat_post <- sum((D == 1) & (post == 1))

  if (n_treat_pre == 0) {
    warning("SUPPORT ISSUE: No treated units in pre-treatment period (n_treat_pre=0). ",
            "Cannot compute ATT. Returning ATT=NA.")
    return(structure(
      list(
        ATT = NA_real_,
        se = NA_real_,
        uci = NA_real_,
        lci = NA_real_,
        boots = NULL,
        att.inf.func = if (inffunc) rep(0, n) else NULL,
        call.param = match.call(),
        argu = list(panel = FALSE, boot = boot, boot.type = ifelse(boot, boot.type, "not_used"),
                    nboot = nboot, type = "or"),
        support_issue = "n_treat_pre=0",
        n_cells = list(n_control_pre = n_control_pre, n_control_post = n_control_post, n_treat_pre = 0, n_treat_post = n_treat_post)
      ),
      class = "drdid"
    ))
  }

  if (n_treat_post == 0) {
    warning("SUPPORT ISSUE: No treated units in post-treatment period (n_treat_post=0). ",
            "Cannot compute ATT. Returning ATT=NA.")
    return(structure(
      list(
        ATT = NA_real_,
        se = NA_real_,
        uci = NA_real_,
        lci = NA_real_,
        boots = NULL,
        att.inf.func = if (inffunc) rep(0, n) else NULL,
        call.param = match.call(),
        argu = list(panel = FALSE, boot = boot, boot.type = ifelse(boot, boot.type, "not_used"),
                    nboot = nboot, type = "or"),
        support_issue = "n_treat_post=0",
        n_cells = list(n_control_pre = n_control_pre, n_control_post = n_control_post, n_treat_pre = n_treat_pre, n_treat_post = 0)
      ),
      class = "drdid"
    ))
  }

  #-----------------------------------------------------------------------------
  # GUARD 4: Check for degenerate design matrices (zero columns)
  #-----------------------------------------------------------------------------
  if (ncol(int.cov) == 0) {
    stop("Design matrix has zero columns. This should not happen.")
  }

  #-----------------------------------------------------------------------------
  #Compute the Outcome regression for the control group at the pre-treatment period, using ols.
  #-----------------------------------------------------------------------------
  reg.coeff.pre <- stats::coef(fastglm::fastglm(
                        x = int.cov[pre_filter, , drop = FALSE],
                        y = y[pre_filter],
                        weights = i.weights[pre_filter],
                        family = gaussian(link = "identity")
  ))
  if(anyNA(reg.coeff.pre)){
    stop("Outcome regression model coefficients have NA components. \n Multicollinearity of covariates is probably the reason for it.")
  }
  out.y.pre <-   as.vector(tcrossprod(reg.coeff.pre, int.cov))

  #-----------------------------------------------------------------------------
  #Compute the Outcome regression for the control group at the post-treatment period, using ols.
  #-----------------------------------------------------------------------------
  reg.coeff.post <- stats::coef(fastglm::fastglm(
                          x = int.cov[post_filter, , drop = FALSE],
                          y = y[post_filter],
                          weights = i.weights[post_filter],
                          family = gaussian(link = "identity")
  ))
  if(anyNA(reg.coeff.post)){
    stop("Outcome regression model coefficients have NA components. \n Multicollinearity (or lack of variation) of covariates is probably the reason for it.")
  }
  out.y.post <-   as.vector(tcrossprod(reg.coeff.post, int.cov))

  #-----------------------------------------------------------------------------
  #Compute the OR DiD estimators
  # First, the weights
  w.treat.pre <- i.weights * D * (1 - post)
  w.treat.post <- i.weights * D * post
  w.cont <- i.weights * D

  reg.att.treat.pre <- w.treat.pre * y
  reg.att.treat.post <- w.treat.post * y
  reg.att.cont <- w.cont * (out.y.post - out.y.pre)

  eta.treat.pre <- mean(reg.att.treat.pre) / mean(w.treat.pre)
  eta.treat.post <- mean(reg.att.treat.post) / mean(w.treat.post)
  eta.cont <- mean(reg.att.cont) / mean(w.cont)

  reg.att <- (eta.treat.post - eta.treat.pre) - eta.cont

  #-----------------------------------------------------------------------------
  #get the influence function to compute standard error
  #-----------------------------------------------------------------------------
  # First, the influence function of the nuisance functions
  # Asymptotic linear representation of OLS parameters in pre-period
  weights.ols.pre <- i.weights * (1 - D) * (1 - post)
  wols.x.pre <- weights.ols.pre * int.cov
  wols.eX.pre <- weights.ols.pre * (y - out.y.pre) * int.cov
  XpX_pre <- crossprod(wols.x.pre, int.cov)/n
  # Check if XpX is invertible
  if ( base::rcond(XpX_pre) < .Machine$double.eps) {
    stop("The regression design matrix for pre-treatment is singular. Consider removing some covariates.")
  }
  XpX.inv.pre <- solve(XpX_pre)
  asy.lin.rep.ols.pre <-  wols.eX.pre %*% XpX.inv.pre

  # Asymptotic linear representation of OLS parameters in post-period
  weights.ols.post <- i.weights * (1 - D) * post
  wols.x.post <- weights.ols.post * int.cov
  wols.eX.post <- weights.ols.post * (y - out.y.post) * int.cov
  XpX_post <- crossprod(wols.x.post, int.cov)/n
  # Check if XpX is invertible
  if ( base::rcond(XpX_post) < .Machine$double.eps) {
    stop("The regression design matrix for post-treatment is singular. Consider removing some covariates.")
  }
  XpX.inv.post <- solve(XpX_post)
  asy.lin.rep.ols.post <-  wols.eX.post %*% XpX.inv.post

  #-----------------------------------------------------------------------------
  # Now, the influence function of the "treat" component
  # Leading term of the influence function
  inf.treat.pre <- (reg.att.treat.pre - w.treat.pre * eta.treat.pre) / mean(w.treat.pre)
  inf.treat.post <- (reg.att.treat.post - w.treat.post * eta.treat.post) / mean(w.treat.post)
  inf.treat <- inf.treat.post - inf.treat.pre

  #-----------------------------------------------------------------------------
  # Now, get the influence function of control component
  # Leading term of the influence function: no estimation effect
  inf.cont.1 <- (reg.att.cont - w.cont * eta.cont)
  # Estimation effect from beta hat (OLS using only controls)
  # Derivative matrix (k x 1 vector)
  M1 <- base::colMeans(w.cont * int.cov)
  # Now get the influence function related to the estimation effect related to beta's in post-treatment
  inf.cont.2.post <- asy.lin.rep.ols.post %*% M1
  # Now get the influence function related to the estimation effect related to beta's in pre-treatment
  inf.cont.2.pre <- asy.lin.rep.ols.pre %*% M1
  # Influence function for the control component
  inf.control <- (inf.cont.1 + inf.cont.2.post - inf.cont.2.pre) / mean(w.cont)

  #-----------------------------------------------------------------------------
  #get the influence function of the DR estimator (put all pieces together)
  reg.att.inf.func <- (inf.treat - inf.control)

  #-----------------------------------------------------------------------------
  if (boot == FALSE) {
    # Estimate of standard error
    se.reg.att <- stats::sd(reg.att.inf.func)*sqrt(n-1)/(n)
    # Estimate of upper boudary of 95% CI
    uci <- reg.att + 1.96 * se.reg.att
    # Estimate of lower doundary of 95% CI
    lci <- reg.att - 1.96 * se.reg.att
    #Create this null vector so we can export the bootstrap draws too.
    reg.boot <- NULL
  }

  if (boot == TRUE) {
    if (is.null(nboot)) nboot <- 999
    if(boot.type == "multiplier"){
      # do multiplier bootstrap
      reg.boot <- mboot.did(reg.att.inf.func, nboot)
      # get bootstrap std errors based on IQR
      se.reg.att <- stats::IQR(reg.boot) / (stats::qnorm(0.75) - stats::qnorm(0.25))
      # get symmtric critival values
      cv <- stats::quantile(abs(reg.boot/se.reg.att), probs = 0.95)
      # Estimate of upper boudary of 95% CI
      uci <- reg.att + cv * se.reg.att
      # Estimate of lower doundary of 95% CI
      lci <- reg.att - cv * se.reg.att
    } else {
      # do weighted bootstrap
      reg.boot <- unlist(lapply(1:nboot, wboot_reg_rc,
                                n = n, y = y, post = post,
                                D = D, int.cov = int.cov, i.weights = i.weights))
      # get bootstrap std errors based on IQR
      se.reg.att <- stats::IQR(reg.boot) / (stats::qnorm(0.75) - stats::qnorm(0.25))
      # get symmtric critival values
      cv <- stats::quantile(abs(reg.boot - reg.att)/se.reg.att, probs = 0.95)
      # Estimate of upper boudary of 95% CI
      uci <- reg.att + cv * se.reg.att
      # Estimate of lower doundary of 95% CI
      lci <- reg.att - cv * se.reg.att
    }
  }

  # return results
  return(structure(
    list(ATT = reg.att,
         se = se.reg.att,
         uci = uci,
         lci = lci,
         boots = reg.boot,
         att.inf.func = if (inffunc) reg.att.inf.func else NULL,
         call.param = match.call(),
         argu = list(panel = FALSE,
                     boot = boot,
                     boot.type = ifelse(boot, boot.type, "not_used"),
                     nboot = nboot,
                     type = "or"),
         support_issue = NULL,
         n_cells = list(n_control_pre = n_control_pre, n_control_post = n_control_post,
                       n_treat_pre = n_treat_pre, n_treat_post = n_treat_post)
    ),
    class = "drdid"
  ))
}
