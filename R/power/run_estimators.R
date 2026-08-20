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
#   lpdid  Local-projections DiD (Dube, Girardi, Jorda & Taylor 2023), hand-
#          rolled on fixest following the authors' R example. Long-differences
#          from a pre-mean baseline, clean-control condition, EWATT reweighting.
#          Computes lags on TRUE CALENDAR MONTHS from month_date (never the
#          consecutive index), so a covid: drop panel behaves as in the real
#          data: comparisons never straddle the gap, and switchers whose
#          baseline falls in the gap are excluded, not silently bridged.
#          spec knobs: lpdid_pmd (baseline months, default 3), lpdid_post
#          (pooled horizon window 0..H, default 12), lpdid_wild (wild cluster
#          bootstrap arm, default FALSE in simulation - WLS forces boottest to
#          dummy-expand the stacked time-cell factor, which is memory-unsafe
#          on county panels; see .re_lpdid).
#
# INFERENCE ARMS (CS):
#   analytic  : analytic influence-function SE, t(df = n_clusters - 1)
#   boot_t    : GENUINE multiplier-bootstrap SE (did returns overall.se from
#               getSE()->mboot when bstrap = TRUE) combined with a t critical
#               value. This is the legacy "t-on-bootstrap-SE" arm.
#   boot      : GENUINE multiplier-bootstrap p-value and critical value.
#   jack      : CV3 cluster jackknife (Karim, Nielsen, MacKinnon & Webb 2026).
#               OFF by default (spec$cs_jack); costs H+1 att_gt fits.
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

#' Install the CS segfault guard
#'
#' `did::att_gt(est_method = "reg", allow_unbalanced_panel = TRUE)` dispatches
#' to `DRDID:::reg_did_rc()`, which calls `fastglm()` on the design matrix of
#' each (g,t) cell. On a non-identifiable cell that matrix has zero rows and
#' fastglm's C++ `colMax_dense()` aborts the R process outright -- not an R
#' condition, so the `tryCatch` around `fit_att()` below cannot see it. Under
#' furrr the worker simply dies ("MultisessionFuture interrupted") and the
#' scenario is lost. Measured 2026-08-17: ~1 rep in 4 on the state D1 design.
#'
#' `patches/reg_did_rc_safe.R` is the repo's signature-identical replacement
#' that returns a structured NA for empty cells.
#'
#' TWO bindings must be replaced, not one. `did/NAMESPACE` has
#' `importFrom(DRDID, reg_did_rc)`, and R copies the *value* of that binding
#' into `did`'s imports frame when `did` is loaded. Under the framework default
#' `cs_faster_mode = TRUE`, `compute.att_gt2()` calls `reg_did_rc()` UNQUALIFIED
#' and so resolves through that frame -- patching only the DRDID namespace
#' leaves the hot path on the original unless `did` happens to be loaded
#' afterwards. Verified 2026-08-17: with `did` loaded first, a DRDID-only
#' install leaves `did`'s imports binding unpatched while still reporting
#' success. (The non-faster path calls `DRDID::reg_did_rc()`, which resolves at
#' call time and is always covered -- which is why the repo's interactive
#' diagnostics, all `faster_mode = FALSE`, never exposed this.)
#'
#' The return value is an assertion on the binding `did` will actually call,
#' not on what we attempted, so an install that cannot reach the hot path
#' reports FALSE rather than a false success.
#'
#' Idempotent, and safe to call in every parallel worker (each worker is a
#' separate R process with its own namespaces).
#'
#' @param enable Install the guard? FALSE is a no-op returning FALSE, so the
#'   caller can pass a config flag straight through.
#' @param root Repository root holding `patches/`.
#' @return TRUE if the guard is in force on the call path `did` uses.
#' @export
install_cs_safe_patches <- function(enable = TRUE, root = NULL) {
  if (!isTRUE(enable)) return(FALSE)
  # This module is standalone-sourceable, so config.R may not be loaded; fall
  # back to the working directory (the framework's documented repo-root rule).
  if (is.null(root)) {
    root <- if (exists("power_repo_root", mode = "function")) {
      power_repo_root()
    } else getwd()
  }
  if (isTRUE(getOption("power.cs_safe_patches_installed"))) return(TRUE)
  if (!requireNamespace("DRDID", quietly = TRUE)) {
    warning("cs_safe_patches requested but DRDID is not installed; ",
            "CS runs remain segfault-prone.", call. = FALSE)
    return(FALSE)
  }

  patch <- file.path(root, "patches", "reg_did_rc_safe.R")
  if (!file.exists(patch)) {
    warning("cs_safe_patches requested but ", patch, " not found; ",
            "CS runs remain segfault-prone.", call. = FALSE)
    return(FALSE)
  }

  env <- new.env(parent = globalenv())
  sys.source(patch, envir = env)
  if (!exists("reg_did_rc_safe", envir = env, mode = "function")) {
    warning("reg_did_rc_safe() not defined by ", patch, call. = FALSE)
    return(FALSE)
  }
  safe_fn <- get("reg_did_rc_safe", envir = env, mode = "function")

  # Refuse to install a replacement whose arguments differ from the internal
  # it shadows: att_gt() calls it positionally, so a signature drift after a
  # DRDID upgrade would silently mis-bind arguments rather than error.
  target <- get("reg_did_rc", envir = asNamespace("DRDID"), mode = "function")
  if (!identical(names(formals(target)), names(formals(safe_fn)))) {
    warning("reg_did_rc_safe() signature does not match DRDID:::reg_did_rc(); ",
            "refusing to install the guard.", call. = FALSE)
    return(FALSE)
  }

  # The patch's free symbols (wboot_reg_rc, mboot.did on the boot path) live in
  # DRDID's namespace; sourcing put the closure under globalenv, where they
  # would not resolve and where the estimator's internals would be exposed to
  # name capture from the caller's globalenv.
  environment(safe_fn) <- asNamespace("DRDID")

  utils::assignInNamespace("reg_did_rc", safe_fn, ns = "DRDID")

  # Load `did` (if it is not already) so its imports frame exists, then replace
  # the imported copy too. Ordering is deliberate: a `did` loaded AFTER the
  # DRDID assignment copies the patched value and this second step is a no-op;
  # a `did` already loaded needs it.
  if (requireNamespace("did", quietly = TRUE)) {
    imports <- parent.env(asNamespace("did"))
    if (exists("reg_did_rc", envir = imports, inherits = FALSE)) {
      if (bindingIsLocked("reg_did_rc", imports)) {
        unlockBinding("reg_did_rc", imports)
        on.exit(try(lockBinding("reg_did_rc", imports), silent = TRUE),
                add = TRUE)
      }
      assign("reg_did_rc", safe_fn, envir = imports)
    }
  }

  # Assert on the binding did::att_gt() will actually reach, in both the
  # faster (imports frame) and non-faster (DRDID namespace) paths.
  installed <- .cs_guard_active(safe_fn)
  if (!installed) {
    warning("cs_safe_patches: guard could not be bound on did's call path; ",
            "CS runs remain segfault-prone.", call. = FALSE)
    return(FALSE)
  }
  options(power.cs_safe_patches_installed = TRUE)
  TRUE
}

# TRUE iff every binding did::att_gt() can reach for reg_did_rc is `safe_fn`.
# Compares bodies rather than closures because environment<- above makes
# identity comparison on the function object itself fragile.
#' @keywords internal
.cs_guard_active <- function(safe_fn) {
  same <- function(e) {
    f <- tryCatch(get("reg_did_rc", envir = e, mode = "function",
                      inherits = FALSE), error = function(err) NULL)
    !is.null(f) && identical(body(f), body(safe_fn))
  }
  if (!same(asNamespace("DRDID"))) return(FALSE)
  if (isNamespaceLoaded("did")) {
    imports <- parent.env(asNamespace("did"))
    if (exists("reg_did_rc", envir = imports, inherits = FALSE) &&
        !same(imports)) {
      return(FALSE)
    }
  }
  TRUE
}

# Merge caller spec over documented defaults.
.re_spec <- function(spec) {
  defaults <- list(control_group = "notyettreated", est_method = "reg",
                   base_period = "varying", anticipation = 0L, biters = 199L,
                   cluster = "state_abb", alpha = 0.05,
                   cs_jack = FALSE, cs_faster_mode = TRUE)
  out <- utils::modifyList(defaults, spec %||% list())
  # modifyList() DELETES any key the caller passes as NULL rather than leaving
  # the default in place. A dropped knob then reaches its estimator as a
  # missing argument -- e.g. faster_mode = NULL errors inside att_gt() -- so
  # restore every default the caller nulled out.
  dropped <- setdiff(names(defaults), names(out))
  if (length(dropped) > 0L) out[dropped] <- defaults[dropped]
  out
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
#' @param estimator One of "cs", "twfe", "did2s", "sunab", "lpdid".
#' @param spec Named list overriding the documented defaults (control_group,
#'   est_method, base_period, anticipation, biters, cluster, alpha).
#' @return A tibble with columns \code{.RE_SCHEMA}, one row per
#'   (inference x estimand). Never throws.
#' @export
run_estimator <- function(panel_sim,
                          estimator = c("cs", "twfe", "did2s", "sunab",
                                        "lpdid", "bjs", "longdiff"),
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
    bjs   = .re_bjs(est, sp, cl, df_cluster),
    sunab = .re_sunab(est, sp, cl, df_cluster),
    # lpdid needs month_date and pseudo_g, which .re_prep discards: its lags
    # must run on calendar months so they cannot bridge a covid: drop gap.
    lpdid = .re_lpdid(panel_sim, sp, cl, df_cluster),
    # longdiff likewise works on calendar months and pseudo_g directly.
    longdiff = .re_longdiff(panel_sim, sp, cl)
  )
}

# --------------------- Cohort-specific long differences -----------------------
#
# Ben's design (audited 2026-08-03, quality_reports/
# cohort_specific_long_difference_code_review.md), simplified to the framework
# contract for power simulation:
#   * per treated state with pseudo date g: baseline mean of y over calendar
#     months g-30..g-7 (24 months, preserving a 6-month anticipation gap),
#     post mean over g..g+11 (h1, the "simple" estimand), g+12..g+23 (h2) and
#     g+24..g+35 (h3) as dynamic rows at event_time 18 / 30;
#   * cohort-specific calendar transformation of controls: each NEVER-pseudo-
#     treated state's long difference is computed on the SAME calendar windows
#     as the cohort, then averaged; ATT_i = dY_i - mean(dY_controls,i);
#   * coverage rule: a state contributes to a cohort-window only if >=
#     ld_min_frac (default 0.5) of the window's calendar months are observed
#     (the spliced window and panel edges both truncate windows);
#   * equal-treated-state aggregation: ATT(h) = mean over supported treated;
#   * inference: delete-one-STATE jackknife over every contributing state
#     (treated and controls), p from t(df = n_contributing - 1). Labeled
#     inference = "jack" -- it is not an analytic cluster SE.
#
# Splice note: unlike lpdid, a long difference here MAY span a covid: drop
# gap (a post-gap cohort's baseline reaches into the pre-gap era). That is
# deliberate -- the design bets that differencing against controls on the
# same calendar windows removes the common shift; the state-specific shift
# component remains, and the power gates measure exactly that exposure.

.re_longdiff <- function(panel_sim, sp, cl) {
  t0 <- Sys.time()
  bw      <- as.integer(sp$ld_baseline %||% c(-30L, -7L))
  windows <- list(h1 = c(0L, 11L), h2 = c(12L, 23L), h3 = c(24L, 35L))
  minfrac <- as.numeric(sp$ld_min_frac %||% 0.5)

  fail <- function(msg) {
    .re_row("longdiff", "jack", "simple",
            n_treated_clusters = cl$n_treated,
            n_control_clusters = cl$n_control, converged = FALSE,
            error_msg = msg,
            runtime_s = as.numeric(difftime(Sys.time(), t0, units = "secs")))
  }
  if (!all(c("pseudo_g", "month_date", "y_sim") %in% names(panel_sim))) {
    return(fail("longdiff: panel_sim lacks pseudo_g/month_date/y_sim"))
  }

  # County-to-state collapse (a no-op on the state panel).
  s <- panel_sim %>%
    group_by(.data$state_abb, .data$month_date) %>%
    summarise(y = mean(.data$y_sim), .groups = "drop")
  sched <- panel_sim %>%
    filter(!is.na(.data$pseudo_g)) %>%
    distinct(.data$state_abb, .data$pseudo_g)
  controls <- setdiff(unique(s$state_abb), sched$state_abb)
  if (nrow(sched) == 0L) return(fail("longdiff: no pseudo-treated states"))
  if (length(controls) == 0L) {
    return(fail("longdiff: no never-pseudo-treated control states"))
  }

  # Long difference for one state on one cohort's calendar windows; NA when
  # either window fails the coverage rule. Memoized into per-window matrices
  # D[state, cohort] so the delete-one-state jackknife is pure re-averaging
  # (the naive recompute-per-deletion version cost 2.7 s/cell; this is ~20x).
  # Integer month indices: lubridate `%m+% months()` costs milliseconds per
  # call, which dominated the naive version; plain integer arithmetic is free.
  mi <- function(d) lubridate::year(d) * 12L + (lubridate::month(d) - 1L)
  s$m_idx <- mi(s$month_date)
  g_idx   <- mi(sched$pseudo_g)
  state_months <- split(s$m_idx, s$state_abb)
  state_y      <- split(s$y, s$state_abb)
  ld_one <- function(st, gi, w) {
    m <- state_months[[st]]
    bi <- m >= gi + bw[1] & m <= gi + bw[2]
    pi <- m >= gi + w[1] & m <= gi + w[2]
    if (sum(bi) < minfrac * (bw[2] - bw[1] + 1L) ||
        sum(pi) < minfrac * (w[2] - w[1] + 1L)) return(NA_real_)
    mean(state_y[[st]][pi]) - mean(state_y[[st]][bi])
  }

  all_states <- unique(s$state_abb)
  ld_matrix <- function(w) {
    vapply(seq_len(nrow(sched)), function(i) {
      vapply(all_states, ld_one, numeric(1), gi = g_idx[i], w = w)
    }, numeric(length(all_states))) |>
      matrix(nrow = length(all_states),
             dimnames = list(all_states, sched$state_abb))
  }

  # ATT(h) from the memoized matrix, given the retained state set.
  att_from <- function(D, keep_states) {
    per_cohort <- vapply(colnames(D), function(tst) {
      if (!tst %in% keep_states) return(NA_real_)
      dy_t <- D[tst, tst]
      if (is.na(dy_t)) return(NA_real_)
      cc <- intersect(controls, keep_states)
      dy_c <- D[cc, tst]
      dy_c <- dy_c[!is.na(dy_c)]
      if (length(dy_c) == 0L) return(NA_real_)
      dy_t - mean(dy_c)
    }, numeric(1))
    if (all(is.na(per_cohort))) return(list(att = NA_real_, n_t = 0L))
    list(att = mean(per_cohort, na.rm = TRUE),
         n_t = sum(!is.na(per_cohort)))
  }

  rows <- list()
  for (h in names(windows)) {
    w <- windows[[h]]
    D <- ld_matrix(w)
    full <- att_from(D, all_states)
    est_label <- if (h == "h1") "simple" else "dynamic"
    etime <- switch(h, h1 = NA_real_, h2 = 18, h3 = 30)
    if (full$n_t == 0L || !is.finite(full$att)) {
      if (h == "h1") {
        rows[[h]] <- fail("longdiff: no supported treated state at h1")
      }
      next
    }
    # Contributing states at this horizon: supported treated + controls with
    # a usable long difference for at least one supported cohort.
    contrib_t <- colnames(D)[!is.na(D[cbind(colnames(D), colnames(D))])]
    contrib_c <- controls[rowSums(!is.na(D[controls, contrib_t,
                                           drop = FALSE])) > 0L]
    contrib <- c(contrib_t, contrib_c)
    jk <- vapply(contrib, function(st) {
      att_from(D, setdiff(all_states, st))$att
    }, numeric(1))
    jk <- jk[is.finite(jk)]
    n_jk <- length(jk)
    se <- if (n_jk >= 2L) {
      sqrt((n_jk - 1) / n_jk * sum((jk - mean(jk))^2))
    } else NA_real_
    df <- max(1L, n_jk - 1L)
    z  <- stats::qt(1 - sp$alpha / 2, df = df)
    ok <- is.finite(full$att) && is.finite(se) && se > 0
    rows[[h]] <- .re_row(
      "longdiff", "jack", est_label, event_time = etime,
      att = full$att, se = se,
      p = if (ok) 2 * stats::pt(-abs(full$att / se), df = df) else NA_real_,
      ci_lo = if (ok) full$att - z * se else NA_real_,
      ci_hi = if (ok) full$att + z * se else NA_real_,
      n_treated_clusters = full$n_t,
      n_control_clusters = length(contrib_c),
      converged = ok,
      error_msg = if (ok) NA_character_ else "longdiff: jackknife SE unusable",
      runtime_s = as.numeric(difftime(Sys.time(), t0, units = "secs")))
  }
  if (length(rows) == 0L) return(fail("longdiff: no horizon produced rows"))
  dplyr::bind_rows(rows)
}

# ------------------------------ CS (E1) ---------------------------------------

# CV3 cluster-jackknife SE for the CSDID simple aggregate.
#
# Karim, Nielsen, MacKinnon & Webb (2026), "Improved Inference for CSDID Using
# the Cluster Jackknife", eq. (20):
#
#     CV3(ATT) = sqrt( (H-1)/H * sum_h ( ATT^(h) - ATT )^2 )
#
# where ATT^(h) re-runs the WHOLE CSDID procedure with cluster h deleted.
#
# WHY NOT THE AUTHORS' didjack PACKAGE: didjack::didjack() calls
# did::aggte(gt_sub, type = type) WITHOUT na.rm = TRUE. Our design has 30-43%
# non-identifiable (g,t) cells (singleton cohorts x per-state coverage
# windows), so every jackknife replicate errors with "Missing values at att_gt
# found" and the whole call dies on the FIRST replicate. Verified reproducible
# on three independent D1 state draws (2026-08-11). didjack also re-evaluates
# the original att_gt `data` argument via parent.frame(), which is fragile
# inside a runner. This implementation therefore recomputes eq. (20) directly,
# with na.rm = TRUE so the jackknife aggregate matches the analytic arm's
# estimand exactly. Cross-validated against didjack on a fully-identified
# panel: see tests/test_cs_cv3.R.
#
# FAILED REPLICATES: a delete-one fit that errors is EXCLUDED and counted, not
# silently treated as zero deviation. Dropping replicates biases CV3 downward
# (the omitted clusters are typically the influential ones), so the count is
# surfaced in error_msg as a "note:" and reps < H should be treated as a
# quality flag, not a clean result.
#
# SINGLETON-COHORT CAVEAT (paper Section 4, second caveat): when every treated
# cohort holds one state, deleting a treated cluster removes that cohort's
# ATT(g,t) terms entirely, so ATT^(h) differs from ATT partly through a change
# in aggregation COMPOSITION rather than sampling noise. Whether CV3 is
# well-calibrated under that regime is exactly the open empirical question this
# arm exists to answer. `n_treated_dropped` records how many replicates deleted
# a treated cluster.
#' @keywords internal
.re_cs_cv3 <- function(dat, fit_on, att_full, alpha) {
  clusters <- sort(unique(dat$state_abb))
  H <- length(clusters)
  treated_clusters <- unique(dat$state_abb[dat$g > 0L])

  atts <- rep(NA_real_, H)
  for (h in seq_len(H)) {
    sub <- dat[dat$state_abb != clusters[h], , drop = FALSE]
    a <- tryCatch(suppressMessages(suppressWarnings(fit_on(sub))),
                  error = function(e) NULL)
    if (is.null(a)) next
    ag <- tryCatch(suppressMessages(suppressWarnings(
      did::aggte(a, type = "simple", na.rm = TRUE))), error = function(e) NULL)
    if (!is.null(ag)) atts[h] <- as.numeric(ag$overall.att)
  }

  ok   <- is.finite(atts)
  reps <- sum(ok)
  if (reps < 2L) {
    return(list(ok = FALSE, msg = sprintf(
      "cv3: only %d/%d usable jackknife replicates", reps, H)))
  }

  df    <- reps - 1L
  cv3se <- sqrt((df / reps) * sum((atts[ok] - att_full)^2))
  if (!is.finite(cv3se) || cv3se <= 0) {
    return(list(ok = FALSE, msg = "cv3: non-finite or zero jackknife SE"))
  }

  crit <- stats::qt(1 - alpha / 2, df = df)
  note <- if (reps < H) {
    sprintf("note: cv3 used %d/%d replicates (%d failed)", reps, H, H - reps)
  } else NA_character_

  list(ok = TRUE, se = cv3se, df = df,
       p = 2 * stats::pt(-abs(att_full / cv3se), df = df),
       ci_lo = att_full - crit * cv3se, ci_hi = att_full + crit * cv3se,
       reps = reps, n_failed = H - reps,
       n_treated_dropped = sum(ok & clusters %in% treated_clusters),
       atts = atts, clusters = clusters, msg = note)
}

.re_cs <- function(est, sp, cl, df_cluster) {
  dat <- as.data.frame(data.frame(
    # g MUST be double: att_gt sets never-treated g==0 to Inf in place, and an
    # integer column truncates that to NA, silently dropping every never-
    # treated state (the real cause of CS's "not enough control units"
    # failures under faster_mode=TRUE). Verified 2026-08-20.
    id = est$id, t = est$t, g = as.numeric(est$g_int), y = est$y_sim,
    state_abb = est$state_abb, stringsAsFactors = FALSE
  ))
  z <- stats::qt(1 - sp$alpha / 2, df = max(1L, df_cluster))

  # fit_att_on() takes the estimation frame explicitly so the CV3 jackknife can
  # re-fit on delete-one-cluster subsets with an otherwise identical spec.
  fit_att_on <- function(d, bstrap) {
    did::att_gt(
      yname = "y", tname = "t", idname = "id", gname = "g",
      xformla = ~1, data = d, panel = TRUE,
      allow_unbalanced_panel = TRUE, faster_mode = sp$cs_faster_mode,
      clustervars = "state_abb", est_method = sp$est_method,
      base_period = sp$base_period, anticipation = sp$anticipation,
      control_group = sp$control_group, bstrap = bstrap,
      biters = sp$biters, cband = FALSE, print_details = FALSE
    )
  }
  fit_att <- function(bstrap) fit_att_on(dat, bstrap)

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
                   runtime_s = as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  }

  simple <- tryCatch(suppressMessages(suppressWarnings(
    did::aggte(ana, type = "simple", na.rm = TRUE))), error = function(e) NULL)
  dyn <- tryCatch(suppressMessages(suppressWarnings(
    did::aggte(ana, type = "dynamic", na.rm = TRUE))), error = function(e) NULL)
  win <- tryCatch(suppressMessages(suppressWarnings(
    did::aggte(ana, type = "dynamic", min_e = 0L, max_e = 12L, na.rm = TRUE))),
    error = function(e) NULL)
  rt_ana <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

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

  # --- CV3 cluster jackknife (opt-in; costs H+1 att_gt fits) -----------------
  if (isTRUE(sp$cs_jack) && !is.null(simple) &&
      is.finite(as.numeric(simple$overall.att))) {
    t_j <- Sys.time()
    jk <- tryCatch(
      .re_cs_cv3(dat, function(d) fit_att_on(d, FALSE),
                 as.numeric(simple$overall.att), sp$alpha),
      error = function(e) list(ok = FALSE, msg = conditionMessage(e)))
    rt_j <- as.numeric(difftime(Sys.time(), t_j, units = "secs"))
    att_s <- as.numeric(simple$overall.att)

    rows[[length(rows) + 1L]] <- if (isTRUE(jk$ok)) {
      .re_row("cs", "jack", "simple", att = att_s, se = jk$se, p = jk$p,
              ci_lo = jk$ci_lo, ci_hi = jk$ci_hi,
              n_treated_clusters = cl$n_treated,
              n_control_clusters = cl$n_control, converged = TRUE,
              error_msg = jk$msg, runtime_s = rt_j)
    } else {
      .re_row("cs", "jack", "simple", att = att_s,
              n_treated_clusters = cl$n_treated,
              n_control_clusters = cl$n_control, converged = FALSE,
              error_msg = jk$msg, runtime_s = rt_j)
    }
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
      runtime_s = as.numeric(difftime(Sys.time(), t1, units = "secs")))
    return(bind_rows(rows))
  }

  bsimple <- tryCatch(suppressMessages(suppressWarnings(
    did::aggte(bt, type = "simple", na.rm = TRUE))), error = function(e) NULL)
  rt_boot <- as.numeric(difftime(Sys.time(), t1, units = "secs"))

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
  rt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

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
  rt1 <- as.numeric(difftime(Sys.time(), t1, units = "secs"))

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
  rt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

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

# ------------------------------ BJS (didimputation) ---------------------------

# Borusyak-Jaravel-Spiess imputation estimator. Added 2026-08-19 for the
# post-COVID maturation power run: on a clean (splice-free) window the
# imputation family's global-parallel-trends assumption is at its most
# defensible, and the 2026-05-21 county calibration already "rescued"
# didimputation there (14% / 0.73 / 1.1x). Mirrors .re_did2s's conventions:
# single analytic arm, p from t(df = n_clusters - 1), failures logged never
# thrown. didimputation's never-treated convention is gname = NA (any finite
# gname is read as a cohort, and g_int = 0 would be "treated since before the
# panel"), so g_int == 0 maps to NA_integer_ here.
.re_bjs <- function(est, sp, cl, df_cluster) {
  dat <- as.data.frame(est)
  dat$first_treat <- ifelse(dat$g_int == 0L, NA_integer_, dat$g_int)
  z <- stats::qt(1 - sp$alpha / 2, df = max(1L, df_cluster))

  t0 <- Sys.time()
  fit <- tryCatch(
    suppressMessages(suppressWarnings(
      didimputation::did_imputation(data = dat, yname = "y_sim",
                                    gname = "first_treat", tname = "t",
                                    idname = "id",
                                    cluster_var = "state_abb"))),
    error = function(e) structure(NA, err = conditionMessage(e)))
  rt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  if (isTRUE(is.na(fit)) && !is.null(attr(fit, "err"))) {
    return(.re_row("bjs", "analytic", "simple",
                   n_treated_clusters = cl$n_treated,
                   n_control_clusters = cl$n_control, converged = FALSE,
                   error_msg = attr(fit, "err"), runtime_s = rt))
  }

  cf <- tryCatch(as.numeric(fit$estimate[1]), error = function(e) NA_real_)
  se <- tryCatch(as.numeric(fit$std.error[1]), error = function(e) NA_real_)
  ok <- is.finite(cf) && is.finite(se) && se > 0

  .re_row("bjs", "analytic", "simple", att = cf, se = se,
          p = .re_tp(cf, se, df_cluster),
          ci_lo = if (ok) cf - z * se else NA_real_,
          ci_hi = if (ok) cf + z * se else NA_real_,
          n_treated_clusters = cl$n_treated, n_control_clusters = cl$n_control,
          converged = ok,
          error_msg = if (ok) NA_character_ else "bjs SE not identified",
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
  rt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

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

# ------------------------------ LP-DiD (E5) -----------------------------------
#
# Dube, Girardi, Jorda & Taylor (2023, NBER w31184), pooled EWATT:
#
#   D_h y_it = y_{i,t+h} - mean(y_{i,t-PMD..t-1})        h = 0..lpdid_post
#   sample:    switchers at t  +  units untreated through t+h (clean controls)
#   feols(dy ~ D_treat | cell, weights = 1/Var_cell(D-resid), cluster = state)
#
# where cell = (base period t) x (horizon h). Reweighting converts the OLS
# variance-weighted estimand into the equally-weighted ATT (paper section 3.3).
#
# CALENDAR-MONTH LAGS: all leads/lags index true calendar months built from
# month_date. On a covid: drop panel the gap months are simply absent, so any
# comparison whose window touches them produces NA and drops out — switchers
# whose pseudo-treatment lands in or just after the gap are structurally
# excluded, exactly as in the real-data application
# (analysis/main/lpdid_statepanel.R). A consecutive index would instead
# silently difference across the gap.
#
# WILD ARM (spec$lpdid_wild, default FALSE): boottest() does not support WLS
# with absorbed fixed effects, so the wild arm dummy-expands the stacked
# time-cell factor (~1-2k levels on the state panel; memory-unsafe on county
# panels — the same failure mode as the fe-expansion OOM of Della job
# 12223288). Enable only for state-level runs.
#' @keywords internal
.re_lpdid <- function(panel_sim, sp, cl, df_cluster) {
  pmd  <- as.integer(sp$lpdid_pmd  %||% 3L)
  hmax <- as.integer(sp$lpdid_post %||% 12L)
  wild <- isTRUE(sp$lpdid_wild)
  z <- stats::qt(1 - sp$alpha / 2, df = max(1L, df_cluster))

  t0 <- Sys.time()
  stack <- tryCatch(suppressMessages(suppressWarnings({
    m_of <- function(dd) as.integer(format(dd, "%Y")) * 12L +
      as.integer(format(dd, "%m"))
    d <- panel_sim
    d$m <- m_of(d$month_date)
    units <- sort(unique(as.character(d$unit_id)))
    m_min <- min(d$m)
    M <- max(d$m) - m_min + 1L

    # Y[unit, calendar month]; absent months (covid gap, coverage) stay NA.
    Y <- matrix(NA_real_, length(units), M)
    Y[cbind(match(as.character(d$unit_id), units), d$m - m_min + 1L)] <- d$y_sim

    gtab <- d[!duplicated(d$unit_id),
              c("unit_id", "state_abb", "pseudo_g"), drop = FALSE]
    ord  <- match(units, as.character(gtab$unit_id))
    st   <- as.character(gtab$state_abb)[ord]
    gm   <- ifelse(is.na(gtab$pseudo_g[ord]), NA_integer_,
                   m_of(gtab$pseudo_g[ord]) - m_min + 1L)

    # Baseline per base period: mean of the PMD months ending at t-1; NA if
    # any of them is absent (no na.rm — that is the gap guard).
    B <- matrix(NA_real_, length(units), M)
    for (tt in (pmd + 1L):M) {
      B[, tt] <- rowMeans(Y[, (tt - pmd):(tt - 1L), drop = FALSE])
    }

    out <- vector("list", (hmax + 1L) * M)
    k <- 0L
    for (h in 0:hmax) {
      for (tt in (pmd + 1L):(M - h)) {
        far <- tt + h
        dy  <- Y[, far] - B[, tt]
        sw  <- !is.na(gm) & gm == tt
        ctl <- is.na(gm) | gm > far
        keep <- (sw | ctl) & is.finite(dy)
        if (!any(keep & sw) || !any(keep & ctl)) next
        k <- k + 1L
        out[[k]] <- data.frame(
          state_abb = st[keep], D_treat = as.integer(sw[keep]),
          dy = dy[keep], cell = paste0(tt, "_", h),
          stringsAsFactors = FALSE)
      }
    }
    if (k == 0L) NULL else do.call(rbind, out[seq_len(k)])
  })), error = function(e) structure(NA, err = conditionMessage(e)))

  if (is.null(stack) || (isTRUE(is.na(stack[1])) && !is.null(attr(stack, "err")))) {
    msg <- if (is.null(stack)) "no identified (t, h) cells (all switchers lost to gap/edges)"
           else attr(stack, "err")
    return(.re_row("lpdid", "analytic", "simple",
                   n_treated_clusters = cl$n_treated,
                   n_control_clusters = cl$n_control, converged = FALSE,
                   error_msg = msg,
                   runtime_s = as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  }

  res <- tryCatch(suppressMessages(suppressWarnings({
    stack$cell <- factor(stack$cell)
    aux <- fixest::feols(D_treat ~ 1 | cell, data = stack,
                         warn = FALSE, notes = FALSE)
    w  <- as.numeric(stats::residuals(aux))^2
    wt <- as.numeric(tapply(w, stack$cell, mean)[as.character(stack$cell)])
    stack$rw <- as.numeric(ifelse(is.finite(wt) & wt > 0, 1 / wt, NA_real_))
    stack <- stack[is.finite(stack$rw), , drop = FALSE]
    fit <- fixest::feols(dy ~ D_treat | cell, data = stack, weights = ~rw,
                         cluster = ~state_abb, warn = FALSE, notes = FALSE)
    list(fit = fit,
         att = as.numeric(stats::coef(fit)["D_treat"]),
         se  = as.numeric(fixest::se(fit)["D_treat"]),
         n_sw = sum(stack$D_treat))
  })), error = function(e) structure(NA, err = conditionMessage(e)))
  rt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  if (isTRUE(is.na(res[1])) && !is.null(attr(res, "err"))) {
    return(.re_row("lpdid", "analytic", "simple",
                   n_treated_clusters = cl$n_treated,
                   n_control_clusters = cl$n_control, converged = FALSE,
                   error_msg = attr(res, "err"), runtime_s = rt))
  }

  att <- res$att; se <- res$se
  ok <- is.finite(att) && is.finite(se) && se > 0
  rows <- list(.re_row(
    "lpdid", "analytic", "simple", att = att, se = se,
    p = .re_tp(att, se, df_cluster),
    ci_lo = if (ok) att - z * se else NA_real_,
    ci_hi = if (ok) att + z * se else NA_real_,
    n_treated_clusters = cl$n_treated, n_control_clusters = cl$n_control,
    converged = ok,
    error_msg = if (ok) NA_character_ else "lpdid att/se not identified",
    runtime_s = rt))

  if (wild && ok) {
    t1 <- Sys.time()
    wb <- tryCatch(
      suppressMessages(suppressWarnings(
        fwildclusterboot::boottest(res$fit, param = "D_treat",
                                   clustid = ~state_abb, B = 999L,
                                   type = "rademacher"))),
      error = function(e) structure(NA, err = conditionMessage(e)))
    rt1 <- as.numeric(difftime(Sys.time(), t1, units = "secs"))
    if (isTRUE(is.na(wb)) && !is.null(attr(wb, "err"))) {
      rows[[2L]] <- .re_row(
        "lpdid", "wild", "simple", att = att,
        n_treated_clusters = cl$n_treated, n_control_clusters = cl$n_control,
        converged = FALSE, error_msg = attr(wb, "err"), runtime_s = rt1)
    } else {
      p_w  <- tryCatch(as.numeric(fwildclusterboot::pval(wb)),
                       error = function(e) NA_real_)
      ci_w <- tryCatch(as.numeric(stats::confint(wb)),
                       error = function(e) c(NA_real_, NA_real_))
      rows[[2L]] <- .re_row(
        "lpdid", "wild", "simple", att = att, se = se, p = p_w,
        ci_lo = ci_w[1], ci_hi = ci_w[2],
        n_treated_clusters = cl$n_treated, n_control_clusters = cl$n_control,
        converged = is.finite(p_w), runtime_s = rt1)
    }
  }

  bind_rows(rows)
}
