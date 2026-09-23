################################################################################
# R/power/summarize_operating_characteristics.R
#
# Operating-characteristic summarization for the blinded power-simulation
# framework (POWER_SIMULATION_DESIGN.md §12, §16 module contract):
#
#   summarize_oc(results, alpha_vec)  — the §12 per-cell OC table
#   compute_mde(oc_table, ...)        — BHNS-style local-linear MDE interpolation
#                                       with optional bootstrap CI over reps
#   pretrend_summary(results)         — Holm-adjusted joint pre-trend rejection
#                                       shares over e in [-12, -1]
#
# `results` is the stacked run_estimator() output (one row per estimand x
# inference method x rep x delta) with added columns:
#   scenario_id, rep, delta (nominal grid value), truth (simulated truth for
#   that estimand/rep, computed from the injection metadata), plus scenario
#   metadata columns (level, sample, design, mechanism, shape, ...).
#
# All inputs here are simulated operating characteristics on untreated data
# with imposed known effects — explicitly allowed under the blindness protocol
# (POWER_SIMULATION_BLINDNESS_PROTOCOL.md §8).
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(rlang)
})

if (!exists("power_paths", mode = "function")) source("R/power/config.R")

#' Canonical rejection-rate column name for a significance level
#' @keywords internal
.reject_col <- function(alpha) sprintf("reject_%03d", as.integer(round(alpha * 100)))

# The confidence level baked into every stored CI in this framework.
# run_estimators.R's .re_spec() default is alpha = 0.05, and every inference
# arm (analytic z*se, bootstrap crit, wild boottest/confint) builds its CI
# at that single level -- nothing in the framework currently varies it per
# scenario. A stored CI therefore answers ONE rejection question ("is 0
# outside the 95% interval?"), not a family of them.
.CI_ALPHA <- 0.05

# .CI_ALPHA is a hand-maintained duplicate of run_estimators.R's .re_spec()
# default `alpha`, which is the level every stored ci_lo/ci_hi is actually
# built at. If the two ever drift -- e.g. alpha becomes a scenario axis -- the
# CI fallback would silently answer at the wrong level rather than return NA,
# which is the failure mode .reject_flag()'s level gate exists to prevent. Fail
# loudly at source time instead. Guarded on existence because this module is
# standalone-sourceable and run_estimators.R may not be loaded.
if (exists(".re_spec", mode = "function")) {
  local({
    spec_alpha <- .re_spec(list())$alpha
    if (!isTRUE(all.equal(spec_alpha, .CI_ALPHA))) {
      stop("summarize_operating_characteristics.R: .CI_ALPHA (", .CI_ALPHA,
           ") disagrees with run_estimators.R's .re_spec() alpha (",
           spec_alpha, "). Stored CIs are built at the latter; update ",
           ".CI_ALPHA or add a ci_alpha column to the result rows.",
           call. = FALSE)
    }
  })
}

#' Rejection indicator with a CI-membership fallback when p is unavailable
#'
#' `p <= alpha` when `p` is finite; otherwise, if `ci_lo`/`ci_hi` are BOTH
#' finite AND `alpha` matches the CI's own level (`ci_alpha`, default
#' \code{.CI_ALPHA}), falls back to CI-exclusion-of-zero
#' (`!(ci_lo <= 0 & 0 <= ci_hi)`); NA when neither is usable OR when
#' `alpha != ci_alpha`.
#'
#' The `alpha != ci_alpha` branch matters because \code{summarize_oc()} calls
#' this once per element of \code{alpha_vec} (typically
#' \code{c(0.10, 0.05, 0.01)}), but a stored CI has exactly ONE level
#' (\code{.CI_ALPHA} = 0.05) -- a single 95% interval cannot answer the 90%
#' or 99% rejection question. Silently reusing the 95% membership test at
#' those other levels would understate reject_010 and overstate reject_001;
#' NA is the CORRECT answer here (genuinely unknowable from a single-level
#' stored CI), not a gap to paper over. A row WITH a stored p is unaffected
#' by any of this -- alpha_vec's other levels are all directly computable
#' from p, which is level-independent.
#'
#' This exists because shift-mode-synthesized "wild" rows
#' (R/power/run_scenario_grid.R's .shift_synthesize_partial()) can have a
#' shifted CI but no honestly-reconstructable p (a wild p is a genuine
#' bootstrap quantity from a fresh draw, not a function of the stored
#' columns). Without this fallback, every summary statistic below that keys
#' off `p` silently drops those rows from ITS OWN numerator while
#' `n_reps`/`n_converged` still count them -- undercounting power,
#' deflating .believable_share() by roughly the non-calibration-rep share,
#' and giving compute_mde()'s point estimate (na.rm = TRUE on `p`) and its
#' bootstrap CI incompatible rejection rules.
#'
#' The fallback is not specific to shift mode or to "wild": it applies
#' whenever a row has a finite CI but a missing p (also possible today from
#' \code{.re_cs}'s "boot" arm when the bootstrap p is undefined but crit/se
#' are finite). It is exactly valid (at alpha == ci_alpha) for any CI that
#' is translation-equivariant under a location shift of the estimated
#' parameter -- true of every CI this framework computes, symmetric
#' (analytic/boot_t: att +/- z*se) or not (wild: an inverted, generally
#' asymmetric bootstrap CI).
#'
#' A row WITH a stored p is handled bit-identically to before this fallback
#' existed -- this branch is never reached for it.
#' @keywords internal
.reject_flag <- function(p, ci_lo, ci_hi, alpha, ci_alpha = .CI_ALPHA) {
  dplyr::case_when(
    !is.na(p) ~ p <= alpha,
    is.finite(ci_lo) & is.finite(ci_hi) &
      abs(alpha - ci_alpha) < 1e-9 ~ !(ci_lo <= 0 & 0 <= ci_hi),
    TRUE ~ NA
  )
}

# Cell keys: event_time is included when present so that "dynamic" estimand
# rows summarize per event time while overall/event_0_12 rows (event_time NA)
# collapse to a single cell — a strict superset of the §12 cell definition.
.oc_keys <- function(results) {
  intersect(c("scenario_id", "estimator", "inference", "estimand",
              "event_time", "delta"), names(results))
}

# Scenario metadata columns carried through to the OC table (one value per
# scenario_id by construction).
.oc_meta_cols <- c("scenario_index", "name", "level", "sample", "covid",
                   "treat_def", "design", "mechanism", "shape", "outcome",
                   "est_anticipation", "loader_anticipation", "control_group",
                   "quarterly")

#' Type-S error rate among significant replications (NA when truth == 0)
#' @keywords internal
.sign_error_rate <- function(att, p, ci_lo, ci_hi, truth, alpha) {
  rej <- .reject_flag(p, ci_lo, ci_hi, alpha)
  sig <- !is.na(rej) & rej & !is.na(truth) & truth != 0 & !is.na(att)
  if (!any(sig)) return(NA_real_)
  mean(sign(att[sig]) != sign(truth[sig]))
}

#' Type-M exaggeration ratio E[|att/truth|] among significant reps
#' @keywords internal
.exaggeration_ratio <- function(att, p, ci_lo, ci_hi, truth, alpha) {
  rej <- .reject_flag(p, ci_lo, ci_hi, alpha)
  sig <- !is.na(rej) & rej & !is.na(truth) & truth != 0 & !is.na(att)
  if (!any(sig)) return(NA_real_)
  mean(abs(att[sig] / truth[sig]))
}

#' Share of converged reps that are significant, correct-signed, and <= 2x truth
#' (Gelman & Carlin 2014 "believability" via BHNS). NA when truth == 0.
#' @keywords internal
.believable_share <- function(att, p, ci_lo, ci_hi, truth, alpha) {
  ok <- !is.na(truth) & truth != 0 & !is.na(att)
  if (!any(ok)) return(NA_real_)
  rej <- .reject_flag(p, ci_lo, ci_hi, alpha)
  believable <- !is.na(rej) & rej & sign(att) == sign(truth) &
    abs(att) <= 2 * abs(truth)
  mean(believable[ok])
}

#' Summarize operating characteristics per simulation cell
#'
#' One output row per (scenario_id, estimator, inference, estimand
#' [, event_time], delta). Rejection rates, bias/RMSE/MAE, CI coverage and
#' width, Type-S/Type-M metrics, believability share, failure rates, runtime,
#' cluster counts, and the SE calibration ratio (design doc §12).
#'
#' Failure rows (converged == FALSE or NA) are counted in n_reps and
#' failure_rate but excluded from every estimate-based metric.
#'
#' Truth == 0 cells (nulls): sign_error_rate / exaggeration_ratio /
#' believable_share are NA; false_positive_rate records the share significant
#' at sig_alpha instead.
#'
#' @param results Stacked run_estimator rows (see file header).
#' @param alpha_vec Significance levels for rejection-rate columns.
#' @param sig_alpha Level defining "significant" for Type-S/M metrics.
#' @return A tibble, one row per cell.
#' @export
summarize_oc <- function(results, alpha_vec = c(0.10, 0.05, 0.01),
                         sig_alpha = 0.05) {
  required <- c("scenario_id", "estimator", "inference", "estimand", "delta",
                "rep", "att", "se", "p", "ci_lo", "ci_hi", "converged", "truth")
  missing_cols <- setdiff(required, names(results))
  if (length(missing_cols) > 0L) {
    stop("summarize_oc: results is missing column(s): ",
         paste(missing_cols, collapse = ", "), call. = FALSE)
  }

  results <- results %>%
    mutate(converged = !is.na(.data$converged) & .data$converged)
  keys <- .oc_keys(results)

  base <- results %>%
    group_by(across(all_of(keys))) %>%
    summarise(
      n_reps       = dplyr::n(),
      n_converged  = sum(.data$converged),
      failure_rate = mean(!.data$converged),
      .groups = "drop"
    )

  conv <- results %>% filter(.data$converged)

  # Rejection-rate columns, one per alpha (computed over converged reps, via
  # .reject_flag()'s p-with-CI-fallback rule).
  rejects <- purrr::reduce(
    sort(alpha_vec, decreasing = TRUE),
    .init = base %>% select(all_of(keys)),
    function(acc, a) {
      rj <- conv %>%
        group_by(across(all_of(keys))) %>%
        summarise(
          !!.reject_col(a) := mean(
            .reject_flag(.data$p, .data$ci_lo, .data$ci_hi, a), na.rm = TRUE),
          .groups = "drop")
      left_join(acc, rj, by = keys)
    }
  )

  # n_reject_used: how many converged rows actually contributed to the
  # rejection-rate columns above (a finite p, OR -- lacking that -- a finite
  # CI to fall back on). Distinct from n_converged, which counts every
  # converged row regardless of whether a rejection could be determined.
  # Alpha-independent (a row's usability under .reject_flag() does not
  # depend on the threshold, only on which of p/CI is finite), so this is
  # computed once, not per alpha_vec entry.
  n_used <- conv %>%
    group_by(across(all_of(keys))) %>%
    summarise(
      n_reject_used = sum(is.finite(.data$p) |
                            (is.finite(.data$ci_lo) & is.finite(.data$ci_hi))),
      .groups = "drop"
    )

  est <- conv %>%
    group_by(across(all_of(keys))) %>%
    summarise(
      mean_truth    = mean(.data$truth),
      bias          = mean(.data$att - .data$truth),
      rmse          = sqrt(mean((.data$att - .data$truth)^2)),
      mae           = stats::median(abs(.data$att - .data$truth)),
      coverage      = mean(.data$ci_lo <= .data$truth &
                             .data$truth <= .data$ci_hi),
      mean_ci_width = mean(.data$ci_hi - .data$ci_lo),
      sign_error_rate = .sign_error_rate(.data$att, .data$p, .data$ci_lo,
                                         .data$ci_hi, .data$truth, sig_alpha),
      false_positive_rate = if (all(.data$truth == 0, na.rm = TRUE)) {
        mean(.reject_flag(.data$p, .data$ci_lo, .data$ci_hi, sig_alpha),
             na.rm = TRUE)
      } else NA_real_,
      exaggeration_ratio = .exaggeration_ratio(.data$att, .data$p,
                                               .data$ci_lo, .data$ci_hi,
                                               .data$truth, sig_alpha),
      believable_share = .believable_share(.data$att, .data$p, .data$ci_lo,
                                           .data$ci_hi, .data$truth,
                                           sig_alpha),
      mean_runtime_s = mean(.data$runtime_s, na.rm = TRUE),
      med_runtime_s  = stats::median(.data$runtime_s, na.rm = TRUE),
      mean_n_treated_clusters = mean(.data$n_treated_clusters, na.rm = TRUE),
      mean_n_control_clusters = mean(.data$n_control_clusters, na.rm = TRUE),
      sd_att  = stats::sd(.data$att),
      mean_se = mean(.data$se, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(se_sd_ratio = .data$mean_se / .data$sd_att)

  # ---- Recentered null (2026-08-28, nullbias memo §fix) ---------------------
  # The blinded placement machinery is non-exchangeable (common support 7
  # states vs 21 cohort slots), so the delta = 0 sampling distribution of att
  # is NOT centered at 0 (e.g. +0.042 vwatt shift12). Testing against 0
  # therefore overstates size (analytic) and flatters power at positive
  # deltas. Fix: recenter on the cell family's own empirical delta = 0 mean
  # (`null_center`), and call a rep rejected when that center falls OUTSIDE
  # the rep's stored CI — exact at the CI's own level (.CI_ALPHA) for every
  # translation-equivariant CI in this framework (see .reject_flag docs),
  # analytic and wild alike. Columns are additive; raw reject_* unchanged.
  fam_keys <- setdiff(keys, "delta")
  centers <- conv %>%
    filter(.data$delta == 0) %>%
    group_by(across(all_of(fam_keys))) %>%
    summarise(null_center = mean(.data$att, na.rm = TRUE), .groups = "drop")

  rc <- conv %>%
    left_join(centers, by = fam_keys) %>%
    group_by(across(all_of(keys))) %>%
    summarise(
      !!sprintf("reject_rc_%03d", as.integer(round(.CI_ALPHA * 100))) := mean(
        ifelse(is.finite(.data$null_center) & is.finite(.data$ci_lo) &
                 is.finite(.data$ci_hi),
               !(.data$ci_lo <= .data$null_center &
                   .data$null_center <= .data$ci_hi),
               NA),
        na.rm = TRUE),
      .groups = "drop")

  out <- base %>%
    left_join(n_used, by = keys) %>%
    left_join(rejects, by = keys) %>%
    left_join(rc, by = keys) %>%
    left_join(centers, by = fam_keys) %>%
    left_join(est, by = keys)

  # Attach scenario metadata (constant within scenario_id).
  mc <- intersect(.oc_meta_cols, names(results))
  if (length(mc) > 0L) {
    meta <- results %>%
      distinct(across(all_of(c("scenario_id", mc)))) %>%
      group_by(.data$scenario_id) %>%
      slice(1) %>%
      ungroup()
    out <- left_join(out, meta, by = "scenario_id")
  }

  out %>% arrange(across(all_of(keys)))
}

#' Local-linear MDE interpolation on a single power curve (BHNS-style)
#'
#' Finds the first pair of adjacent grid points bracketing the target power
#' (rejection rate) and interpolates linearly between them.
#'
#' @param delta Numeric grid values.
#' @param power Rejection rates at each grid value.
#' @param target Target power.
#' @return list(mde, reason) — reason is one of "interpolated",
#'   "at_or_below_smallest_grid_point", "never_crosses_target", "no_data".
#' @keywords internal
.mde_from_curve <- function(delta, power, target) {
  ok <- !is.na(delta) & !is.na(power)
  delta <- delta[ok]
  power <- power[ok]
  if (length(delta) < 1L) return(list(mde = NA_real_, reason = "no_data"))
  o <- order(delta)
  delta <- delta[o]
  power <- power[o]
  if (power[1] >= target) {
    return(list(mde = delta[1], reason = "at_or_below_smallest_grid_point"))
  }
  for (i in seq_len(length(delta) - 1L)) {
    if (power[i] < target && power[i + 1] >= target) {
      mde <- delta[i] + (delta[i + 1] - delta[i]) *
        (target - power[i]) / (power[i + 1] - power[i])
      return(list(mde = mde, reason = "interpolated"))
    }
  }
  list(mde = NA_real_, reason = "never_crosses_target")
}

#' Compute minimum detectable effects from an OC table
#'
#' Per (scenario_id, estimator, inference, estimand) — dynamic-estimand rows
#' are excluded (an MDE per event time is not a meaningful design summary;
#' pre-trend behavior is summarized by \code{pretrend_summary()} instead).
#' Interpolates the power curve at \code{power_target} (and at 0.90 for the
#' companion mde_90 column) between the two grid points bracketing the target
#' (design doc §12, BHNS-style). Returns NA with a reason when the curve never
#' crosses.
#'
#' Optional bootstrap CI: pass the raw \code{results} and \code{n_boot > 0}.
#' Within each cell, replication IDs are resampled with replacement (jointly
#' across grid points, preserving the common-random-numbers structure of the
#' per-rep seeds), the power curve and MDE recomputed per draw, and the
#' percentile CI reported over finite draws.
#'
#' @param oc_table Output of \code{summarize_oc()}.
#' @param power_target Target power for the headline MDE (default 0.80).
#' @param alpha Significance level whose rejection column defines the curve.
#' @param results Optional raw results for the bootstrap CI (default NULL).
#' @param n_boot Bootstrap draws (default 200; ignored unless results given).
#' @param boot_conf CI level (default 0.95).
#' @param boot_seed Seed for the bootstrap resampling.
#' @return Tibble with mde, mde_reason, mde_90, mde_90_reason (and
#'   mde_ci_lo / mde_ci_hi / n_boot_finite when bootstrapping).
#' @export
compute_mde <- function(oc_table, power_target = 0.80, alpha = 0.05,
                        results = NULL, n_boot = 200, boot_conf = 0.95,
                        boot_seed = 20260723L, recenter = FALSE) {
  # recenter = TRUE (2026-08-28): interpolate the RECENTERED power curve
  # (reject_rc_* — rejection of the cell family's own empirical delta = 0
  # mean, see summarize_oc) instead of the raw curve. Only available at the
  # stored-CI level (.CI_ALPHA). The bootstrap CI recomputes the null center
  # per draw from the resampled delta = 0 reps.
  rc <- if (recenter) {
    if (abs(alpha - .CI_ALPHA) > 1e-9) {
      stop("compute_mde: recentered curves exist only at alpha = ", .CI_ALPHA,
           " (the stored-CI level).", call. = FALSE)
    }
    sprintf("reject_rc_%03d", as.integer(round(.CI_ALPHA * 100)))
  } else .reject_col(alpha)
  if (!rc %in% names(oc_table)) {
    stop("compute_mde: oc_table has no rejection column '", rc,
         "' — run summarize_oc with alpha_vec including ", alpha, ".",
         call. = FALSE)
  }
  keys <- c("scenario_id", "estimator", "inference", "estimand")
  cells <- oc_table %>%
    filter(.data$estimand != "dynamic") %>%
    group_by(across(all_of(keys))) %>%
    group_split()

  out <- purrr::map_dfr(cells, function(g) {
    m80 <- .mde_from_curve(g$delta, g[[rc]], power_target)
    m90 <- .mde_from_curve(g$delta, g[[rc]], 0.90)
    bind_cols(
      g[1, keys],
      tibble::tibble(
        alpha = alpha, power_target = power_target,
        mde = m80$mde, mde_reason = m80$reason,
        mde_90 = m90$mde, mde_90_reason = m90$reason
      )
    )
  })

  if (!is.null(results) && n_boot > 0L) {
    res <- results %>%
      filter(.data$estimand != "dynamic") %>%
      mutate(converged = !is.na(.data$converged) & .data$converged)
    ci <- res %>%
      group_by(across(all_of(keys))) %>%
      group_split() %>%
      purrr::map_dfr(function(g) {
        if (recenter) {
          # Recentered bootstrap: resample reps jointly across the grid,
          # recompute the null center from the resampled delta = 0 atts, then
          # per-delta power = share of resampled reps whose stored CI
          # EXCLUDES that center.
          gg <- g %>% filter(.data$converged,
                             is.finite(.data$ci_lo), is.finite(.data$ci_hi))
          wide <- function(col) {
            gg %>% select(all_of(c("rep", "delta", col))) %>%
              tidyr::pivot_wider(names_from = "delta", values_from = all_of(col),
                                 values_fn = mean) %>% arrange(.data$rep)
          }
          w_lo <- wide("ci_lo"); w_hi <- wide("ci_hi"); w_at <- wide("att")
          dnames <- setdiff(names(w_lo), "rep")
          lo <- as.matrix(w_lo[, dnames, drop = FALSE])
          hi <- as.matrix(w_hi[, dnames, drop = FALSE])
          at <- as.matrix(w_at[, dnames, drop = FALSE])
          deltas <- as.numeric(dnames)
          z <- which(abs(deltas) < 1e-12)
          if (!length(z) || nrow(lo) < 2L) {
            return(bind_cols(g[1, keys],
                             tibble::tibble(mde_ci_lo = NA_real_,
                                            mde_ci_hi = NA_real_,
                                            n_boot_finite = 0L)))
          }
          set.seed(boot_seed)
          draws <- vapply(seq_len(n_boot), function(b) {
            idx <- sample.int(nrow(lo), replace = TRUE)
            b0  <- mean(at[idx, z], na.rm = TRUE)
            pw  <- colMeans(!(lo[idx, , drop = FALSE] <= b0 &
                                b0 <= hi[idx, , drop = FALSE]), na.rm = TRUE)
            .mde_from_curve(deltas, pw, power_target)$mde
          }, numeric(1))
          fin <- draws[is.finite(draws)]
          pr <- c((1 - boot_conf) / 2, 1 - (1 - boot_conf) / 2)
          est_ci <- if (length(fin) >= n_boot / 2) {
            unname(stats::quantile(fin, pr))
          } else c(NA_real_, NA_real_)
          return(bind_cols(g[1, keys],
                           tibble::tibble(mde_ci_lo = est_ci[1],
                                          mde_ci_hi = est_ci[2],
                                          n_boot_finite = length(fin))))
        }
        w <- g %>%
          # Same rule as summarize_oc()'s reject_* columns: DROP non-
          # converged rows (rather than coercing them to FALSE) so the
          # bootstrap and the point MDE (read from oc_table, itself built by
          # summarize_oc()) use an IDENTICAL definition of "usable". This
          # matters for shift mode: cs/boot and cs/jack are ~90%
          # non-converged at delta > 0 by design (never synthesized, see
          # run_scenario_grid.R), so coercing them to "not rejected" would
          # deflate this bootstrap curve ~10x relative to the point
          # estimate's denominator, which excludes them entirely --
          # producing an mde next to an incompatible mde_ci. A row that IS
          # converged but has neither a usable p nor a usable CI (or whose
          # CI is at the wrong alpha, see .reject_flag()) is also dropped
          # (values_fn below), not coerced -- matching summarize_oc()'s
          # na.rm = TRUE on the same quantity.
          filter(.data$converged) %>%
          mutate(sig = .reject_flag(.data$p, .data$ci_lo, .data$ci_hi, alpha)) %>%
          select(all_of(c("rep", "delta", "sig"))) %>%
          tidyr::pivot_wider(
            names_from = "delta", values_from = "sig",
            values_fn = function(x) if (all(is.na(x))) NA else any(x, na.rm = TRUE))
        mat <- as.matrix(w[, setdiff(names(w), "rep"), drop = FALSE])
        deltas <- as.numeric(colnames(mat))
        set.seed(boot_seed)
        draws <- vapply(seq_len(n_boot), function(b) {
          idx <- sample.int(nrow(mat), replace = TRUE)
          pw <- colMeans(mat[idx, , drop = FALSE], na.rm = TRUE)
          .mde_from_curve(deltas, pw, power_target)$mde
        }, numeric(1))
        fin <- draws[is.finite(draws)]
        pr <- c((1 - boot_conf) / 2, 1 - (1 - boot_conf) / 2)
        # Require a majority of finite draws for a meaningful percentile CI.
        est_ci <- if (length(fin) >= n_boot / 2) {
          unname(stats::quantile(fin, pr))
        } else c(NA_real_, NA_real_)
        bind_cols(
          g[1, keys],
          tibble::tibble(mde_ci_lo = est_ci[1], mde_ci_hi = est_ci[2],
                         n_boot_finite = length(fin))
        )
      })
    out <- left_join(out, ci, by = keys)
  }

  out
}

#' Size-adjusted MDE: power at a critical value calibrated to the simulated null
#'
#' 2026-08-29. The wild cluster bootstrap under-rejects with few treated
#' clusters (MacKinnon, Nielsen & Webb 2023, §5.3: the bootstrap-statistic
#' dispersion grows with |tau|), so rejection at the nominal cutoff understates
#' the power an exact-size test would have. Brewer, Crossley & Joyce (2018)
#' fix: calibrate the cutoff to the simulated delta = 0 distribution, then
#' compute power/MDE at the calibrated cutoff (Davidson & MacKinnon 1998
#' size-power logic).
#'
#' Per-rep evidence statistic, computable identically for analytic and wild
#' rows from the stored CI alone:
#'   s(c) = |mid - c| / halfwidth,  mid = (ci_lo + ci_hi)/2,
#'                                  halfwidth = (ci_hi - ci_lo)/2,
#' so s(c) > 1 reproduces the stored-CI rejection of center c exactly — the
#' calibrated rule nests reject_rc_* at crit = 1. Per cell, the critical value
#' is the empirical (1 - alpha) quantile (type = 1) of s under delta = 0;
#' power at each grid point is the share of reps with s > crit; the MDE
#' interpolates that curve via .mde_from_curve(). `recenter = TRUE` (default;
#' the PAP-relevant variant) tests against the cell family's own empirical
#' delta = 0 mean — the recentered null of summarize_oc() — rather than 0.
#' `size_at_crit` reports the achieved delta = 0 rejection (= alpha up to
#' quantile discreteness) as a built-in verification.
#'
#' The bootstrap CI resamples replication IDs jointly across the grid
#' (preserving common random numbers) and recomputes BOTH the center and the
#' calibrated cutoff per draw, so calibration noise from the finite delta = 0
#' sample is inside the CI. NB with a 300-rep MDE grid the within-run cutoff
#' rests on 300 null draws and is noisy (ewatt probe: within-run crit 0.82 vs
#' 0.92 from the 1,000-rep gate — a 1.4pp MDE difference). Pass the paired
#' gate run's rows as `null_results` to pool its delta = 0 draws into the
#' calibration: the gate and MDE scenarios share every setting except the
#' delta grid, so their delta = 0 draws are iid from the SAME null
#' distribution (independent seeds), and pooling is exact — matched on
#' (estimator, inference, estimand), scenario_id deliberately ignored. Do NOT
#' pool across specs (different design/weights/panel = different null).
#'
#' @param results Stacked run_estimator rows (raw partials / results_raw).
#' @param power_target Target power for the headline MDE (default 0.80).
#' @param alpha Target size of the calibrated test (default 0.05).
#' @param recenter Test against the empirical delta = 0 mean (TRUE, default)
#'   or against 0 (FALSE — the raw Davidson–MacKinnon variant).
#' @param n_boot Bootstrap draws for the MDE CI (default 200; 0 disables).
#' @param boot_conf CI level (default 0.95).
#' @param boot_seed Seed for the bootstrap resampling.
#' @param null_results Optional extra rows whose delta = 0 draws augment the
#'   calibration set (typically the same spec's gate run). Same-spec only.
#' @return Tibble per (scenario_id, estimator, inference, estimand):
#'   null_center, sizeadj_crit, size_at_crit, n_null_draws, mde, mde_reason,
#'   mde_90, mde_90_reason, mde_ci_lo, mde_ci_hi, n_boot_finite.
#' @export
compute_mde_sizeadj <- function(results, power_target = 0.80, alpha = 0.05,
                                recenter = TRUE, n_boot = 200,
                                boot_conf = 0.95, boot_seed = 20260723L,
                                null_results = NULL) {
  keys <- c("scenario_id", "estimator", "inference", "estimand")
  res <- results %>%
    filter(.data$estimand != "dynamic") %>%
    mutate(converged = !is.na(.data$converged) & .data$converged) %>%
    # Same usability rule as the recentered branch of compute_mde(): converged
    # rows with a finite, non-degenerate stored CI. p is never consulted.
    filter(.data$converged, is.finite(.data$ci_lo), is.finite(.data$ci_hi),
           .data$ci_hi > .data$ci_lo)

  s_stat <- function(lo, hi, center) {
    s <- abs((lo + hi) / 2 - center) / ((hi - lo) / 2)
    s[!is.finite(s)] <- NA_real_
    s
  }

  # External calibration draws (delta = 0 only), matched on the cell keys
  # minus scenario_id — the paired gate run has a different scenario id but
  # the identical null DGP.
  ext <- if (!is.null(null_results)) {
    null_results %>%
      filter(.data$estimand != "dynamic", abs(.data$delta) < 1e-12) %>%
      mutate(converged = !is.na(.data$converged) & .data$converged) %>%
      filter(.data$converged, is.finite(.data$ci_lo), is.finite(.data$ci_hi),
             .data$ci_hi > .data$ci_lo) %>%
      select(all_of(c("estimator", "inference", "estimand",
                      "att", "ci_lo", "ci_hi")))
  } else NULL

  res %>%
    group_by(across(all_of(keys))) %>%
    group_split() %>%
    purrr::map_dfr(function(g) {
      wide <- function(col) {
        g %>% select(all_of(c("rep", "delta", col))) %>%
          tidyr::pivot_wider(names_from = "delta",
                             values_from = all_of(col),
                             values_fn = mean) %>%
          arrange(.data$rep)
      }
      w_lo <- wide("ci_lo"); w_hi <- wide("ci_hi"); w_at <- wide("att")
      dnames <- setdiff(names(w_lo), "rep")
      lo <- as.matrix(w_lo[, dnames, drop = FALSE])
      hi <- as.matrix(w_hi[, dnames, drop = FALSE])
      at <- as.matrix(w_at[, dnames, drop = FALSE])
      deltas <- as.numeric(dnames)
      z <- which(abs(deltas) < 1e-12)[1]

      base_row <- bind_cols(
        g[1, keys],
        tibble::tibble(alpha = alpha, power_target = power_target,
                       recentered = recenter))
      na_row <- function(reason) bind_cols(base_row, tibble::tibble(
        null_center = NA_real_, sizeadj_crit = NA_real_,
        size_at_crit = NA_real_, n_null_draws = 0L,
        mde = NA_real_, mde_reason = reason,
        mde_90 = NA_real_, mde_90_reason = reason,
        mde_ci_lo = NA_real_, mde_ci_hi = NA_real_, n_boot_finite = 0L))

      if (is.na(z) || nrow(lo) < 2L) return(na_row("no_delta0_reps"))

      # Calibration pool: the cell's own delta = 0 draws plus (optionally) the
      # matched external null draws.
      e <- if (!is.null(ext)) {
        ext %>% filter(.data$estimator == g$estimator[1],
                       .data$inference == g$inference[1],
                       .data$estimand  == g$estimand[1])
      } else NULL
      pool <- function(idx, idx2) {
        list(att   = c(at[idx, z], if (!is.null(e)) e$att[idx2]),
             ci_lo = c(lo[idx, z], if (!is.null(e)) e$ci_lo[idx2]),
             ci_hi = c(hi[idx, z], if (!is.null(e)) e$ci_hi[idx2]))
      }
      calib <- function(p) {
        center <- if (recenter) mean(p$att, na.rm = TRUE) else 0
        s0 <- s_stat(p$ci_lo, p$ci_hi, center)
        s0 <- s0[is.finite(s0)]
        # 1/alpha null draws is the bare minimum to place the (1 - alpha)
        # quantile at all; below that the cutoff is meaningless.
        if (length(s0) < ceiling(1 / alpha)) return(NULL)
        list(center = center,
             crit = unname(stats::quantile(s0, 1 - alpha, type = 1)),
             s0 = s0)
      }

      full_idx  <- seq_len(nrow(lo))
      full_idx2 <- if (!is.null(e)) seq_len(nrow(e)) else integer(0)
      cal <- calib(pool(full_idx, full_idx2))
      if (is.null(cal)) return(na_row("too_few_delta0_reps"))

      s   <- s_stat(lo, hi, cal$center)
      pw  <- colMeans(s > cal$crit, na.rm = TRUE)
      m80 <- .mde_from_curve(deltas, pw, power_target)
      m90 <- .mde_from_curve(deltas, pw, 0.90)

      ci_vals <- c(NA_real_, NA_real_); nfin <- 0L
      if (n_boot > 0L) {
        set.seed(boot_seed)
        draws <- vapply(seq_len(n_boot), function(b) {
          idx  <- sample.int(nrow(lo), replace = TRUE)
          idx2 <- if (!is.null(e) && nrow(e) > 0L) {
            sample.int(nrow(e), replace = TRUE)
          } else integer(0)
          calb <- calib(pool(idx, idx2))
          if (is.null(calb)) return(NA_real_)
          sb <- s_stat(lo[idx, , drop = FALSE], hi[idx, , drop = FALSE],
                       calb$center)
          .mde_from_curve(deltas, colMeans(sb > calb$crit, na.rm = TRUE),
                          power_target)$mde
        }, numeric(1))
        fin  <- draws[is.finite(draws)]
        nfin <- length(fin)
        pr <- c((1 - boot_conf) / 2, 1 - (1 - boot_conf) / 2)
        if (nfin >= n_boot / 2) ci_vals <- unname(stats::quantile(fin, pr))
      }

      bind_cols(base_row, tibble::tibble(
        null_center = cal$center, sizeadj_crit = cal$crit,
        size_at_crit = mean(cal$s0 > cal$crit),
        n_null_draws = length(cal$s0),
        mde = m80$mde, mde_reason = m80$reason,
        mde_90 = m90$mde, mde_90_reason = m90$reason,
        mde_ci_lo = ci_vals[1], mde_ci_hi = ci_vals[2],
        n_boot_finite = nfin))
    })
}

#' Holm-adjusted joint pre-trend rejection shares
#'
#' For dynamic-estimand rows with event_time in \code{event_window}
#' (default e in [-12, -1]): within each replication, the pointwise pre-period
#' p-values are Holm-adjusted and the joint test rejects when any adjusted
#' p <= alpha — matching the pipeline's Holm-over-pointwise convention
#' (design doc §12). Reported per (scenario_id, estimator, inference, delta).
#'
#' @param results Stacked run_estimator rows (must include dynamic rows).
#' @param event_window Inclusive pre-period event-time window.
#' @param alpha Joint-test level.
#' @return Tibble: cell keys, n_reps, mean_n_pre_periods,
#'   pretrend_reject_rate. Zero rows when no dynamic pre-period rows exist.
#' @export
pretrend_summary <- function(results, event_window = c(-12L, -1L),
                             alpha = 0.05) {
  keys <- c("scenario_id", "estimator", "inference", "delta")
  empty <- tibble::tibble(
    scenario_id = character(0), estimator = character(0),
    inference = character(0), delta = numeric(0), n_reps = integer(0),
    mean_n_pre_periods = numeric(0), pretrend_reject_rate = numeric(0)
  )
  if (!"event_time" %in% names(results)) return(empty)

  pre <- results %>%
    mutate(converged = !is.na(.data$converged) & .data$converged) %>%
    filter(.data$estimand == "dynamic", .data$converged,
           !is.na(.data$event_time),
           .data$event_time >= event_window[1],
           .data$event_time <= event_window[2],
           !is.na(.data$p))
  if (nrow(pre) == 0L) return(empty)

  pre %>%
    group_by(across(all_of(c(keys, "rep")))) %>%
    summarise(
      joint_reject = any(stats::p.adjust(.data$p, method = "holm") <= alpha),
      n_pre = dplyr::n(),
      .groups = "drop"
    ) %>%
    group_by(across(all_of(keys))) %>%
    summarise(
      n_reps = dplyr::n(),
      mean_n_pre_periods = mean(.data$n_pre),
      pretrend_reject_rate = mean(.data$joint_reject),
      .groups = "drop"
    )
}
