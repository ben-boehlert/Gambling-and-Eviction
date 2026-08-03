################################################################################
# test-oc.R
#
# Operating-characteristic summarization: summarize_oc() metrics on a
# hand-constructed results tibble with known answers; compute_mde()
# interpolation on a hand-made power curve; truth == 0 cells produce
# false-positive rates (not sign errors); failure rows excluded from
# estimates but counted in failure_rate; pretrend_summary() Holm convention.
################################################################################

# ---- Hand-constructed results ----------------------------------------------
# Cell A: delta = 0.05, truth = 0.05, 10 reps: 8 converged + 2 failures.
.att_a <- c(0.06, -0.06, 0.07, 0.03, 0.05, 0.05, 0.06, 0.04)
.p_a   <- c(0.005, 0.005, 0.02, 0.03, 0.04, 0.04, 0.08, 0.60)

.mk_row <- function(rep, delta, truth, att, se, p, converged,
                    runtime = 1, estimand = "overall", event_time = NA_real_,
                    estimator = "twfe", inference = "analytic",
                    scenario_id = "SC1") {
  tibble::tibble(
    scenario_id = scenario_id, estimator = estimator, inference = inference,
    estimand = estimand, event_time = event_time, delta = delta, rep = rep,
    att = att, se = se, p = p,
    ci_lo = att - 0.02, ci_hi = att + 0.02,
    n_treated_clusters = 10L, n_control_clusters = 12L,
    converged = converged,
    error_msg = if (converged) NA_character_ else "boom",
    runtime_s = runtime, truth = truth
  )
}

.cell_a <- dplyr::bind_rows(
  purrr::map_dfr(1:8, function(r) {
    .mk_row(r, delta = 0.05, truth = 0.05, att = .att_a[r], se = 0.02,
            p = .p_a[r], converged = TRUE, runtime = r)
  }),
  purrr::map_dfr(9:10, function(r) {
    .mk_row(r, delta = 0.05, truth = 0.05, att = NA_real_, se = NA_real_,
            p = NA_real_, converged = FALSE, runtime = NA_real_)
  })
)

# Cell B: delta = 0, truth = 0 (null cell), 5 converged reps.
.att_b <- c(0.03, -0.01, 0.02, -0.04, 0.00)
.p_b   <- c(0.01, 0.20, 0.30, 0.04, 0.90)
.cell_b <- purrr::map_dfr(1:5, function(r) {
  .mk_row(r, delta = 0, truth = 0, att = .att_b[r], se = 0.02, p = .p_b[r],
          converged = TRUE)
})

.results_hand <- dplyr::bind_rows(.cell_a, .cell_b)

test_that("summarize_oc reproduces hand-computed metrics (effect cell)", {
  oc <- summarize_oc(.results_hand, alpha_vec = c(0.10, 0.05, 0.01))
  a <- oc %>% dplyr::filter(delta == 0.05)
  expect_equal(nrow(a), 1L)

  expect_equal(a$n_reps, 10L)
  expect_equal(a$n_converged, 8L)
  expect_equal(a$failure_rate, 0.2)

  expect_equal(a$reject_010, 7 / 8)
  expect_equal(a$reject_005, 6 / 8)
  expect_equal(a$reject_001, 2 / 8)

  expect_equal(a$bias, mean(.att_a) - 0.05)          # = -0.0125
  expect_equal(a$bias, -0.0125)
  expect_equal(a$rmse, sqrt(mean((.att_a - 0.05)^2)))
  expect_equal(a$rmse, sqrt(0.00165))
  expect_equal(a$mae, 0.01)

  expect_equal(a$coverage, 7 / 8)
  expect_equal(a$mean_ci_width, 0.04)

  # Type-S among the 6 significant reps: only rep 2 (att = -0.06) wrong-signed.
  expect_equal(a$sign_error_rate, 1 / 6)
  # Type-M: mean(|att| / 0.05) over the 6 significant reps.
  expect_equal(a$exaggeration_ratio,
               mean(abs(.att_a[.p_a <= 0.05]) / 0.05))
  expect_equal(a$exaggeration_ratio, (1.2 + 1.2 + 1.4 + 0.6 + 1 + 1) / 6)
  # Believable: significant, correct sign, |att| <= 2 * truth = 0.10
  # (reps 1, 3, 4, 5, 6), as a share of the 8 converged reps.
  expect_equal(a$believable_share, 5 / 8)
  expect_true(is.na(a$false_positive_rate))

  expect_equal(a$mean_runtime_s, mean(1:8))
  expect_equal(a$med_runtime_s, 4.5)
  expect_equal(a$mean_n_treated_clusters, 10)
  expect_equal(a$mean_n_control_clusters, 12)

  expect_equal(a$sd_att, sd(.att_a))
  expect_equal(a$mean_se, 0.02)
  expect_equal(a$se_sd_ratio, 0.02 / sd(.att_a))
})

test_that("truth == 0 cells produce false-positive rates, not sign errors", {
  oc <- summarize_oc(.results_hand)
  b <- oc %>% dplyr::filter(delta == 0)
  expect_equal(nrow(b), 1L)
  expect_true(is.na(b$sign_error_rate))
  expect_true(is.na(b$exaggeration_ratio))
  expect_true(is.na(b$believable_share))
  expect_equal(b$false_positive_rate, 2 / 5)   # p <= .05: reps 1 and 4
  expect_equal(b$false_positive_rate, b$reject_005)
  expect_equal(b$coverage, 3 / 5)              # CIs of reps 2, 3, 5 cover 0
})

test_that("failure rows are excluded from estimates but drive failure_rate", {
  oc_with  <- summarize_oc(.results_hand)
  oc_without <- summarize_oc(dplyr::filter(.results_hand, converged))
  a_with  <- oc_with %>% dplyr::filter(delta == 0.05)
  a_without <- oc_without %>% dplyr::filter(delta == 0.05)
  # Identical estimates either way...
  for (col in c("bias", "rmse", "mae", "coverage", "reject_005", "sd_att")) {
    expect_equal(a_with[[col]], a_without[[col]], info = col)
  }
  # ...but failures counted only when present.
  expect_equal(a_with$failure_rate, 0.2)
  expect_equal(a_without$failure_rate, 0)
  expect_equal(a_without$n_reps, 8L)
})

test_that("compute_mde interpolates the hand-made power curve correctly", {
  oc <- tibble::tibble(
    scenario_id = "X", estimator = "twfe", inference = "analytic",
    estimand = "overall",
    delta = c(0, 0.02, 0.04, 0.06),
    reject_005 = c(0.05, 0.30, 0.60, 0.90)
  )
  m <- compute_mde(oc, power_target = 0.80, alpha = 0.05)
  expect_equal(nrow(m), 1L)
  # 0.04 + 0.02 * (0.80 - 0.60) / (0.90 - 0.60) = 0.0533...
  expect_equal(m$mde, 0.04 + 0.02 * (0.80 - 0.60) / (0.90 - 0.60))
  expect_equal(m$mde, 0.05333333, tolerance = 1e-6)
  expect_equal(m$mde_reason, "interpolated")
  # mde_90 lands exactly on the last grid point.
  expect_equal(m$mde_90, 0.06)
})

test_that("compute_mde returns NA with a reason when power never crosses", {
  oc <- tibble::tibble(
    scenario_id = "X", estimator = "twfe", inference = "analytic",
    estimand = "overall",
    delta = c(0, 0.02, 0.04, 0.06),
    reject_005 = c(0.05, 0.10, 0.20, 0.30)
  )
  m <- compute_mde(oc, power_target = 0.80, alpha = 0.05)
  expect_true(is.na(m$mde))
  expect_equal(m$mde_reason, "never_crosses_target")
  expect_true(is.na(m$mde_90))
})

test_that("compute_mde bootstrap CI over reps returns a sane interval", {
  # 10 reps, per-rep significance patterns giving power {0, 0.6, 0.9}.
  reps <- 1:10
  res <- purrr::map_dfr(reps, function(r) {
    tibble::tibble(
      scenario_id = "X", estimator = "twfe", inference = "analytic",
      estimand = "overall", event_time = NA_real_,
      delta = c(0, 0.04, 0.06), rep = r,
      att = c(0, 0.04, 0.06), se = 0.02,
      p = c(0.5, ifelse(r <= 6, 0.01, 0.5), ifelse(r <= 9, 0.01, 0.5)),
      ci_lo = -1, ci_hi = 1, n_treated_clusters = 5L,
      n_control_clusters = 5L, converged = TRUE,
      error_msg = NA_character_, runtime_s = 0.1,
      truth = c(0, 0.04, 0.06)
    )
  })
  oc <- summarize_oc(res)
  m <- compute_mde(oc, power_target = 0.80, alpha = 0.05,
                   results = res, n_boot = 100, boot_seed = 42)
  expect_equal(m$mde, 0.04 + 0.02 * (0.80 - 0.60) / (0.90 - 0.60))
  expect_true(all(c("mde_ci_lo", "mde_ci_hi", "n_boot_finite") %in% names(m)))
  expect_true(is.finite(m$mde_ci_lo) && is.finite(m$mde_ci_hi))
  expect_lte(m$mde_ci_lo, m$mde_ci_hi)
  expect_gte(m$mde_ci_lo, 0)
  expect_lte(m$mde_ci_hi, 0.06)
})

test_that("pretrend_summary applies the Holm-over-pointwise convention", {
  mk_dyn <- function(rep, ev, p) {
    tibble::tibble(
      scenario_id = "X", estimator = "cs", inference = "analytic",
      estimand = "dynamic", event_time = ev, delta = 0, rep = rep,
      att = 0, se = 0.02, p = p, ci_lo = -1, ci_hi = 1,
      n_treated_clusters = 5L, n_control_clusters = 5L, converged = TRUE,
      error_msg = NA_character_, runtime_s = 0.1, truth = 0
    )
  }
  res <- dplyr::bind_rows(
    mk_dyn(1, c(-3, -2, -1), c(0.01, 0.50, 0.90)),  # Holm min = .03 -> reject
    mk_dyn(2, c(-3, -2, -1), c(0.04, 0.50, 0.90)),  # Holm min = .12 -> no
    mk_dyn(1, 0, 0.001),                            # post row: ignored
    # overall rows must also be ignored:
    .mk_row(1, delta = 0, truth = 0, att = 0, se = 0.02, p = 0.001,
            converged = TRUE, scenario_id = "X", estimator = "cs")
  )
  ps <- pretrend_summary(res, event_window = c(-12L, -1L), alpha = 0.05)
  expect_equal(nrow(ps), 1L)
  expect_equal(ps$n_reps, 2L)
  expect_equal(ps$mean_n_pre_periods, 3)
  expect_equal(ps$pretrend_reject_rate, 0.5)
})

test_that("pretrend_summary returns an empty tibble when nothing is dynamic", {
  ps <- pretrend_summary(.results_hand)
  expect_equal(nrow(ps), 0L)
  expect_true(all(c("pretrend_reject_rate", "n_reps") %in% names(ps)))
})
