################################################################################
# R/power/run_estimators.R
#
# Estimator runners for the blinded power-simulation framework
# (POWER_SIMULATION_DESIGN.md §5). Each runner takes an injected panel
# (output of impose_effect(): unit_id, state_abb, t, month_date, y_sim, e,
# pseudo_g) and returns a tidy, fixed-schema tibble of results — one row per
# (estimator x inference method x estimand). Every estimator call is wrapped in
# tryCatch; failures are logged as converged = FALSE rows, never thrown.
#
#   cs     Callaway-Sant'Anna (did::att_gt + aggte)
#   twfe   Two-way fixed effects (fixest::feols) + wild cluster bootstrap
#   did2s  Gardner two-stage (did2s::did2s)
#   sunab  Sun-Abraham (fixest::sunab), diagnostic
#
# INFERENCE ARMS (CS):
#   analytic  : analytic influence-function SE, t(df = n_clusters - 1)
#   boot_t    : GENUINE multiplier-bootstrap SE (did returns overall.se from
#               getSE()->mboot when bstrap = TRUE) combined with a t critical
#               value. This is the legacy "t-on-bootstrap-SE" arm.
#   boot      : GENUINE multiplier-bootstrap p-value and critical value.
#
# did 2.3.0 note (audit F2): for the *simple* aggregate, aggte() does NOT expose
# a dedicated bootstrap critical value / p-value field (unlike the dynamic /
# group / calendar aggregates, which carry crit.val.egt). It DOES return a
# genuine bootstrap SE in overall.se (== did:::mboot(inf.func, dp)$se). The
# "boot" arm therefore reconstructs the genuine bootstrap critical value and
# p-value by calling did:::mboot() on the EXPOSED simple-aggregate influence
# function (aggte$inf.function$simple.att) with the exposed aggte$DIDparams.
# This uses the package's own bootstrap machinery and matches overall.se
# exactly. If did:::mboot is unavailable or errors, the "boot" arm is omitted
# and only "boot_t" is recorded.
#
# Working directory assumed to be the repository root.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
  library(lubridate)
})

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

# Canonical, exact output schema (types enforced by .re_row()).
.RE_SCHEMA <- c("estimator", "inference", "estimand", "event_time", "att", "se",
                "p", "ci_lo", "ci_hi", "n_treated_clusters",
                "n_control_clusters", "converged", "error_msg", "runtime_s")

#' Build one schema-conformant result row
#' @keywords internal
.re_row <- function(estimator, inference, estimand, event_time = NA_integer_,
                    att = NA_real_, se = NA_real_, p = NA_real_,
                    ci_lo = NA_real_, ci_hi = NA_real_,
                    n_treated_clusters = NA_integer_,
                    n_control_clusters = NA_integer_,
                    converged = FALSE, error_msg = NA_character_,
                    runtime_s = NA_real_) {
  tibble(
    estimator          = as.character(estimator),
    inference          = as.character(inference),
    estimand           = as.character(estimand),
    event_time         = as.integer(event_time),
    att                = as.numeric(att),
    se                 = as.numeric(se),
    p                  = as.numeric(p),
    ci_lo              = as.numeric(ci_lo),
    ci_hi              = as.numeric(ci_hi),
    n_treated_clusters = as.integer(n_treated_clusters),
    n_control_clusters = as.integer(n_control_clusters),
    converged          = as.logical(converged),
    error_msg          = as.character(error_msg),
    runtime_s          = as.numeric(runtime_s)
  )
}

# Two-sided t p-value; NA-safe.
.re_tp <- function(att, se, df) {
  if (is.finite(att) && is.finite(se) && se > 0 && df > 0) {
    2 * stats::pt(-abs(att / se), df = df)
  } else NA_real_
}

# Merge caller spec over documented defaults.
.re_spec <- function(spec) {
  utils::modifyList(
    list(control_group = "notyettreated", est_method = "reg",
         base_period = "varying", anticipation = 0L, biters = 199L,
         cluster = "state_abb", alpha = 0.05),
    spec %||% list()
  )
}

# Prepare the common estimation frame: consecutive-1..T time index (did
# large-integer guard), integer id, integer cohort index g_int, and post.
# g_int maps pseudo_g into the same consecutive index space as t: the position
# of the first observed month at/after pseudo_g (0 for never pseudo-treated).
#' @keywords internal
.re_prep <- function(panel_sim) {
  stopifnot(all(c("unit_id", "state_abb", "t", "month_date", "y_sim") %in%
                  names(panel_sim)))
  months <- sort(unique(panel_sim$month_date))
  t_c    <- match(panel_sim$month_date, months)          # 1..T consecutive

  pg <- if ("pseudo_g" %in% names(panel_sim)) panel_sim$pseudo_g else
    rep(as.Date(NA), nrow(panel_sim))
  g_int <- vapply(seq_len(nrow(panel_sim)), function(i) {
    if (is.na(pg[i])) return(0L)
    w <- which(months >= pg[i])
    if (length(w) == 0L) 0L else as.integer(w[1])
  }, integer(1))

  if ("e" %in% names(panel_sim)) {
    post <- as.integer(!is.na(panel_sim$e) & panel_sim$e >= 0L & !is.na(pg))
  } else {
    post <- as.integer(g_int > 0L & t_c >= g_int)
  }

  tibble(
    unit_id   = as.character(panel_sim$unit_id),
    state_abb = as.character(panel_sim$state_abb),
    id        = as.integer(as.factor(panel_sim$unit_id)),
    t         = as.integer(t_c),
    g_int     = g_int,
    post      = post,
    y_sim     = as.numeric(panel_sim$y_sim)
  )
}

# Cluster counts: distinct treated vs never-pseudo-treated states.
#' @keywords internal
.re_clusters <- function(est) {
  treated_states <- unique(est$state_abb[est$g_int > 0L])
  all_states     <- unique(est$state_abb)
  list(n_treated = length(treated_states),
       n_control = length(setdiff(all_states, treated_states)),
       n_total   = length(all_states))
}

#' Dispatch a single estimator on an injected panel
#'
#' @param panel_sim Output of \code{impose_effect()} (see file header for the
#'   required columns; \code{pseudo_g} and \code{e} are joined by the injector).
#' @param estimator One of "cs", "twfe", "did2s", "sunab".
#' @param spec Named list overriding the documented defaults (control_group,
#'   est_method, base_period, anticipation, biters, cluster, alpha).
#' @return A tibble with columns \code{.RE_SCHEMA}, one row per
#'   (inference x estimand). Never throws.
#' @export
run_estimator <- function(panel_sim,
                          estimator = c("cs", "twfe", "did2s", "sunab"),
                          spec = list()) {
  estimator <- match.arg(estimator)
  sp  <- .re_spec(spec)
  est <- tryCatch(.re_prep(panel_sim), error = function(e) NULL)
  if (is.null(est)) {
    return(.re_row(estimator, "analytic", "simple", converged = FALSE,
                   error_msg = "panel preparation failed"))
  }
  cl  <- .re_clusters(est)
  df_cluster <- cl$n_total - 1L

  switch(
    estimator,
    cs    = .re_cs(est, sp, cl, df_cluster),
    twfe  = .re_twfe(est, sp, cl, df_cluster),
    did2s = .re_did2s(est, sp, cl, df_cluster),
    sunab = .re_sunab(est, sp, cl, df_cluster)
  )
}

# ------------------------------ CS (E1) ---------------------------------------

.re_cs <- function(est, sp, cl, df_cluster) {
  dat <- as.data.frame(data.frame(
    id = est$id, t = est$t, g = est$g_int, y = est$y_sim,
    state_abb = est$state_abb, stringsAsFactors = FALSE
  ))
  z <- stats::qt(1 - sp$alpha / 2, df = max(1L, df_cluster))

  fit_att <- function(bstrap) {
    did::att_gt(
      yname = "y", tname = "t", idname = "id", gname = "g",
      xformla = ~1, data = dat, panel = TRUE,
      allow_unbalanced_panel = TRUE, faster_mode = TRUE,
      clustervars = "state_abb", est_method = sp$est_method,
      base_period = sp$base_period, anticipation = sp$anticipation,
      control_group = sp$control_group, bstrap = bstrap,
      biters = sp$biters, cband = FALSE, print_details = FALSE
    )
  }

  rows <- list()

  # --- Analytic run: simple + dynamic + event-window average ------------------
  t0 <- Sys.time()
  ana <- tryCatch(
    suppressMessages(suppressWarnings(fit_att(FALSE))),
    error = function(e) structure(NA, err = conditionMessage(e)))
  if (isTRUE(is.na(ana)) && !is.null(attr(ana, "err"))) {
    return(.re_row("cs", "analytic", "simple",
                   n_treated_clusters = cl$n_treated,
                   n_control_clusters = cl$n_control, converged = FALSE,
                   error_msg = attr(ana, "err"),
                   runtime_s = as.numeric(difftime(Sys.time(), t0, "secs"))))
  }

  simple <- tryCatch(suppressMessages(suppressWarnings(
    did::aggte(ana, type = "simple", na.rm = TRUE))), error = function(e) NULL)
  dyn <- tryCatch(suppressMessages(suppressWarnings(
    did::aggte(ana, type = "dynamic", na.rm = TRUE))), error = function(e) NULL)
  win <- tryCatch(suppressMessages(suppressWarnings(
    did::aggte(ana, type = "dynamic", min_e = 0L, max_e = 12L, na.rm = TRUE))),
    error = function(e) NULL)
  rt_ana <- as.numeric(difftime(Sys.time(), t0, "secs"))

  if (!is.null(simple)) {
    att <- as.numeric(simple$overall.att); se <- as.numeric(simple$overall.se)
    p <- .re_tp(att, se, df_cluster)
    rows[[length(rows) + 1L]] <- .re_row(
      "cs", "analytic", "simple", att = att, se = se, p = p,
      ci_lo = att - z * se, ci_hi = att + z * se,
      n_treated_clusters = cl$n_treated, n_control_clusters = cl$n_control,
      converged = is.finite(att) && is.finite(se), runtime_s = rt_ana)
  } else {
    rows[[length(rows) + 1L]] <- .re_row(
      "cs", "analytic", "simple", n_treated_clusters = cl$n_treated,
      n_control_clusters = cl$n_control, converged = FALSE,
      error_msg = "aggte(simple) failed", runtime_s = rt_ana)
  }

  if (!is.null(dyn)) {
    for (k in seq_along(dyn$egt)) {
      att <- as.numeric(dyn$att.egt[k]); se <- as.numeric(dyn$se.egt[k])
      rows[[length(rows) + 1L]] <- .re_row(
        "cs", "analytic", "dynamic", event_time = as.integer(dyn$egt[k]),
        att = att, se = se, p = .re_tp(att, se, df_cluster),
        ci_lo = att - z * se, ci_hi = att + z * se,
        n_treated_clusters = cl$n_treated, n_control_clusters = cl$n_control,
        converged = is.finite(att) && is.finite(se), runtime_s = rt_ana)
    }
  }

  if (!is.null(win)) {
    att <- as.numeric(win$overall.att); se <- as.numeric(win$overall.se)
    rows[[length(rows) + 1L]] <- .re_row(
      "cs", "analytic", "event_0_12", att = att, se = se,
      p = .re_tp(att, se, df_cluster),
      ci_lo = att - z * se, ci_hi = att + z * se,
      n_treated_clusters = cl$n_treated, n_control_clusters = cl$n_control,
      converged = is.finite(att) && is.finite(se), runtime_s = rt_ana)
  }

  # --- Bootstrap run: boot_t (always) + genuine boot (reconstructed) ----------
  t1 <- Sys.time()
  bt <- tryCatch(suppressMessages(suppressWarnings(fit_att(TRUE))),
                 error = function(e) structure(NA, err = conditionMessage(e)))
  if (isTRUE(is.na(bt)) && !is.null(attr(bt, "err"))) {
    rows[[length(rows) + 1L]] <- .re_row(
      "cs", "boot_t", "simple", n_treated_clusters = cl$n_treated,
      n_control_clusters = cl$n_control, converged = FALSE,
      error_msg = attr(bt, "err"),
      runtime_s = as.numeric(difftime(Sys.time(), t1, "secs")))
    return(bind_rows(rows))
  }

  bsimple <- tryCatch(suppressMessages(suppressWarnings(
    did::aggte(bt, type = "simple", na.rm = TRUE))), error = function(e) NULL)
  rt_boot <- as.numeric(difftime(Sys.time(), t1, "secs"))

  if (!is.null(bsimple)) {
    att   <- as.numeric(bsimple$overall.att)
    se_b  <- as.numeric(bsimple$overall.se)   # genuine bootstrap SE
    # boot_t: t-on-bootstrap-SE (legacy).
    rows[[length(rows) + 1L]] <- .re_row(
      "cs", "boot_t", "simple", att = att, se = se_b,
      p = .re_tp(att, se_b, df_cluster),
      ci_lo = att - z * se_b, ci_hi = att + z * se_b,
      n_treated_clusters = cl$n_treated, n_control_clusters = cl$n_control,
      converged = is.finite(att) && is.finite(se_b), runtime_s = rt_boot)

    # boot: genuine multiplier-bootstrap crit.val + p-value via did:::mboot on
    # the exposed simple-aggregate influence function.
    gb <- tryCatch({
      inf <- as.matrix(bsimple$inf.function$simple.att)
      dp  <- bsimple$DIDparams
      bo  <- did:::mboot(inf, dp)
      crit <- as.numeric(bo$crit.val)
      se_g <- as.numeric(bo$se)
      bSig <- se_g * sqrt(cl$n_total)
      bT   <- abs(as.numeric(bo$bres) / bSig)
      bT   <- bT[is.finite(bT)]
      p_g  <- if (length(bT) > 0L && is.finite(se_g) && se_g > 0)
        mean(bT >= abs(att / se_g)) else NA_real_
      list(crit = crit, se = se_g, p = p_g)
    }, error = function(e) NULL)

    if (!is.null(gb) && is.finite(gb$crit) && is.finite(gb$se)) {
      rows[[length(rows) + 1L]] <- .re_row(
        "cs", "boot", "simple", att = att, se = gb$se, p = gb$p,
        ci_lo = att - gb$crit * gb$se, ci_hi = att + gb$crit * gb$se,
        n_treated_clusters = cl$n_treated, n_control_clusters = cl$n_control,
        converged = TRUE, runtime_s = rt_boot)
    }
  } else {
    rows[[length(rows) + 1L]] <- .re_row(
      "cs", "boot_t", "simple", n_treated_clusters = cl$n_treated,
      n_control_clusters = cl$n_control, converged = FALSE,
      error_msg = "aggte(simple, bstrap) failed", runtime_s = rt_boot)
  }

  bind_rows(rows)
}

# ------------------------------ TWFE (E2) -------------------------------------

.re_twfe <- function(est, sp, cl, df_cluster) {
  dat <- as.data.frame(est)
  z <- stats::qt(1 - sp$alpha / 2, df = max(1L, df_cluster))
  rows <- list()

  # NOTE: the unit fixed effect uses the integer `id` column, not the
  # character `unit_id`. fwildclusterboot::boottest.fixest() internally
  # re-evaluates the fixed-effect formula (`id + t`), which throws
  # "non-numeric argument to binary operator" if the FE term is a character
  # vector (e.g. state abbreviations). feols() itself tolerates either type
  # and gives an identical point estimate; only boottest requires numeric FEs.
  t0 <- Sys.time()
  fit <- tryCatch(
    suppressMessages(suppressWarnings(
      fixest::feols(y_sim ~ post | id + t, data = dat,
                    cluster = ~state_abb, warn = FALSE, notes = FALSE))),
    error = function(e) structure(NA, err = conditionMessage(e)))
  rt <- as.numeric(difftime(Sys.time(), t0, "secs"))

  if (isTRUE(is.na(fit)) && !is.null(attr(fit, "err"))) {
    return(.re_row("twfe", "analytic", "simple",
                   n_treated_clusters = cl$n_treated,
                   n_control_clusters = cl$n_control, converged = FALSE,
                   error_msg = attr(fit, "err"), runtime_s = rt))
  }

  cf <- tryCatch(as.numeric(stats::coef(fit)["post"]), error = function(e) NA_real_)
  se <- tryCatch(as.numeric(fixest::se(fit)["post"]), error = function(e) NA_real_)
  ok <- is.finite(cf) && is.finite(se) && se > 0
  rows[[1L]] <- .re_row(
    "twfe", "analytic", "simple", att = cf, se = se,
    p = .re_tp(cf, se, df_cluster),
    ci_lo = if (ok) cf - z * se else NA_real_,
    ci_hi = if (ok) cf + z * se else NA_real_,
    n_treated_clusters = cl$n_treated, n_control_clusters = cl$n_control,
    converged = ok, error_msg = if (ok) NA_character_ else "post not identified",
    runtime_s = rt)

  # Wild cluster bootstrap (Rademacher, WCR).
  # boottest() cannot handle fixed-effect levels that feols() dropped
  # internally (singletons/collinearity; its error message prescribes
  # excluding them before estimation). Refit on the reduced sample for the
  # wild arm only — the analytic arm keeps the original fit, whose
  # coefficient is identical since the removed FE levels contribute nothing.
  fit_wb <- fit
  fr <- tryCatch(fit$fixef_removed, error = function(e) NULL)
  if (!is.null(fr) && any(lengths(fr) > 0L)) {
    dat_wb <- dat
    for (fe in names(fr)) {
      if (length(fr[[fe]]) > 0L && fe %in% names(dat_wb)) {
        dat_wb <- dat_wb[!(as.character(dat_wb[[fe]]) %in%
                             as.character(fr[[fe]])), , drop = FALSE]
      }
    }
    fit_wb <- tryCatch(
      suppressMessages(suppressWarnings(
        fixest::feols(y_sim ~ post | id + t, data = dat_wb,
                      cluster = ~state_abb, warn = FALSE, notes = FALSE))),
      error = function(e) fit)
  }
  t1 <- Sys.time()
  # `fe = "id"` absorbs the unit fixed effect instead of dummy-expanding it.
  # Without it, boottest() materializes a dense n x n_units design matrix:
  # ~1.8 GB peak per county-panel call, which OOM-killed 8-worker/16G array
  # tasks (Della job 12223288, 2026-08-10). With absorption: ~0.6 GB peak,
  # 5x faster, numerically identical p-value.
  wb <- tryCatch(
    suppressMessages(suppressWarnings(
      fwildclusterboot::boottest(fit_wb, param = "post", clustid = ~state_abb,
                                 B = 999L, type = "rademacher", fe = "id"))),
    error = function(e) structure(NA, err = conditionMessage(e)))
  rt1 <- as.numeric(difftime(Sys.time(), t1, "secs"))

  if (isTRUE(is.na(wb)) && !is.null(attr(wb, "err"))) {
    rows[[2L]] <- .re_row(
      "twfe", "wild", "simple", att = cf,
      n_treated_clusters = cl$n_treated, n_control_clusters = cl$n_control,
      converged = FALSE, error_msg = attr(wb, "err"), runtime_s = rt1)
  } else {
    # NOTE: fwildclusterboot does not export a `confint` function of its own —
    # it only registers an S3 method confint.boottest, dispatched through the
    # base generic. fwildclusterboot::confint(wb) throws "not an exported
    # object" and was silently swallowed by tryCatch; stats::confint(wb)
    # dispatches correctly once the namespace is loaded.
    p_w  <- tryCatch(as.numeric(fwildclusterboot::pval(wb)), error = function(e) NA_real_)
    ci_w <- tryCatch(as.numeric(stats::confint(wb)), error = function(e) c(NA_real_, NA_real_))
    rows[[2L]] <- .re_row(
      "twfe", "wild", "simple", att = cf, se = se, p = p_w,
      ci_lo = ci_w[1], ci_hi = ci_w[2],
      n_treated_clusters = cl$n_treated, n_control_clusters = cl$n_control,
      converged = is.finite(p_w), runtime_s = rt1)
  }

  bind_rows(rows)
}

# ------------------------------ did2s (E3) ------------------------------------

.re_did2s <- function(est, sp, cl, df_cluster) {
  dat <- as.data.frame(est)
  z <- stats::qt(1 - sp$alpha / 2, df = max(1L, df_cluster))

  t0 <- Sys.time()
  fit <- tryCatch(
    suppressMessages(suppressWarnings(
      did2s::did2s(data = dat, yname = "y_sim",
                   first_stage = ~ 0 | unit_id + t,
                   second_stage = ~ post, treatment = "post",
                   cluster_var = "state_abb"))),
    error = function(e) structure(NA, err = conditionMessage(e)))
  rt <- as.numeric(difftime(Sys.time(), t0, "secs"))

  if (isTRUE(is.na(fit)) && !is.null(attr(fit, "err"))) {
    return(.re_row("did2s", "analytic", "simple",
                   n_treated_clusters = cl$n_treated,
                   n_control_clusters = cl$n_control, converged = FALSE,
                   error_msg = attr(fit, "err"), runtime_s = rt))
  }

  cf <- tryCatch(as.numeric(stats::coef(fit)[1]), error = function(e) NA_real_)
  se <- tryCatch({
    v <- stats::vcov(fit); as.numeric(sqrt(diag(v))[1])
  }, error = function(e) NA_real_)
  ok <- is.finite(cf) && is.finite(se) && se > 0

  .re_row("did2s", "analytic", "simple", att = cf, se = se,
          p = .re_tp(cf, se, df_cluster),
          ci_lo = if (ok) cf - z * se else NA_real_,
          ci_hi = if (ok) cf + z * se else NA_real_,
          n_treated_clusters = cl$n_treated, n_control_clusters = cl$n_control,
          converged = ok,
          error_msg = if (ok) NA_character_ else "did2s SE not identified",
          runtime_s = rt)
}

# ------------------------------ Sun-Abraham (E4) ------------------------------

.re_sunab <- function(est, sp, cl, df_cluster) {
  # Never pseudo-treated coded as g_int = 0 (reference cohort, as in the
  # pretrends template's sunab(g, t) usage).
  dat <- as.data.frame(est)
  z <- stats::qt(1 - sp$alpha / 2, df = max(1L, df_cluster))

  t0 <- Sys.time()
  res <- tryCatch(
    suppressMessages(suppressWarnings({
      fit <- fixest::feols(y_sim ~ sunab(g_int, t) | unit_id + t, data = dat,
                           cluster = ~state_abb, warn = FALSE, notes = FALSE)
      agg <- summary(fit, agg = "att")
      list(att = as.numeric(stats::coef(agg)[1]),
           se  = as.numeric(fixest::se(agg)[1]))
    })),
    error = function(e) structure(NA, err = conditionMessage(e)))
  rt <- as.numeric(difftime(Sys.time(), t0, "secs"))

  if (isTRUE(is.na(res[1])) && !is.null(attr(res, "err"))) {
    return(.re_row("sunab", "analytic", "simple",
                   n_treated_clusters = cl$n_treated,
                   n_control_clusters = cl$n_control, converged = FALSE,
                   error_msg = attr(res, "err"), runtime_s = rt))
  }

  att <- res$att; se <- res$se
  ok <- is.finite(att) && is.finite(se) && se > 0
  .re_row("sunab", "analytic", "simple", att = att, se = se,
          p = .re_tp(att, se, df_cluster),
          ci_lo = if (ok) att - z * se else NA_real_,
          ci_hi = if (ok) att + z * se else NA_real_,
          n_treated_clusters = cl$n_treated, n_control_clusters = cl$n_control,
          converged = ok,
          error_msg = if (ok) NA_character_ else "sunab att not identified",
          runtime_s = rt)
}
