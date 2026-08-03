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
.sign_error_rate <- function(att, p, truth, alpha) {
  sig <- !is.na(p) & p <= alpha & !is.na(truth) & truth != 0 & !is.na(att)
  if (!any(sig)) return(NA_real_)
  mean(sign(att[sig]) != sign(truth[sig]))
}

#' Type-M exaggeration ratio E[|att/truth|] among significant reps
#' @keywords internal
.exaggeration_ratio <- function(att, p, truth, alpha) {
  sig <- !is.na(p) & p <= alpha & !is.na(truth) & truth != 0 & !is.na(att)
  if (!any(sig)) return(NA_real_)
  mean(abs(att[sig] / truth[sig]))
}

#' Share of converged reps that are significant, correct-signed, and <= 2x truth
#' (Gelman & Carlin 2014 "believability" via BHNS). NA when truth == 0.
#' @keywords internal
.believable_share <- function(att, p, truth, alpha) {
  ok <- !is.na(truth) & truth != 0 & !is.na(att)
  if (!any(ok)) return(NA_real_)
  believable <- !is.na(p) & p <= alpha & sign(att) == sign(truth) &
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

  # Rejection-rate columns, one per alpha (computed over converged reps).
  rejects <- purrr::reduce(
    sort(alpha_vec, decreasing = TRUE),
    .init = base %>% select(all_of(keys)),
    function(acc, a) {
      rj <- conv %>%
        group_by(across(all_of(keys))) %>%
        summarise(!!.reject_col(a) := mean(.data$p <= a, na.rm = TRUE),
                  .groups = "drop")
      left_join(acc, rj, by = keys)
    }
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
      sign_error_rate = .sign_error_rate(.data$att, .data$p, .data$truth,
                                         sig_alpha),
      false_positive_rate = if (all(.data$truth == 0, na.rm = TRUE)) {
        mean(.data$p <= sig_alpha, na.rm = TRUE)
      } else NA_real_,
      exaggeration_ratio = .exaggeration_ratio(.data$att, .data$p, .data$truth,
                                               sig_alpha),
      believable_share = .believable_share(.data$att, .data$p, .data$truth,
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

  out <- base %>%
    left_join(rejects, by = keys) %>%
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
                        boot_seed = 20260723L) {
  rc <- .reject_col(alpha)
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
        w <- g %>%
          mutate(sig = .data$converged & !is.na(.data$p) &
                   .data$p <= alpha) %>%
          select(all_of(c("rep", "delta", "sig"))) %>%
          tidyr::pivot_wider(names_from = "delta", values_from = "sig",
                             values_fn = function(x) any(x))
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
