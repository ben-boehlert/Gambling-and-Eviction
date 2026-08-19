################################################################################
# test-adaptive-mde.R
#
# Adaptive/sequential MDE search for the CS arm (R/power/adaptive_mde.R),
# built per quality_reports/plans/2026-08-19_adaptive-cs-mde-search.md after
# the 2026-08-18 shift-mode review barred synthesized CS MDEs.
#
# This file covers the PURE decision core (no estimation):
#   .amde_wilson       — Wilson score interval
#   .amde_classify     — above / below / undecided vs the power target
#   .amde_tally        — per-delta tally from partial-schema result rows
#   .amde_next_action  — the scheduler: null phase, grid-index bisection,
#                        top-up, boundary verdicts, anomaly handling
#
# Driver-level tests (mock estimator end-to-end, resume, brute-force
# equivalence) live further down and use the impose_fn/estimator_fn hooks.
################################################################################

if (!exists(".amde_next_action", mode = "function")) {
  amde_path <- file.path(.power_test_root, "R/power/adaptive_mde.R")
  if (file.exists(amde_path)) source(amde_path)
}

.AMDE_GRID <- c(0, 0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.08, 0.10, 0.15, 0.20)

# Convenience: build a tally tibble the way the scheduler consumes it.
.tly <- function(delta = numeric(0), n_done = integer(0),
                 n_used = n_done, k_reject = integer(0)) {
  tibble::tibble(delta = delta, n_done = as.integer(n_done),
                 n_used = as.integer(n_used), k_reject = as.integer(k_reject))
}

.next <- function(tally, n_reps = 250L, batch = 25L, target = 0.80) {
  .amde_next_action(tally, grid = .AMDE_GRID, n_reps = n_reps,
                    batch_size = batch, target = target)
}

# ---------------------------------------------------------------------------
# 1. Wilson interval
# ---------------------------------------------------------------------------

test_that("Wilson interval matches reference values", {
  # Reference values from the standard Wilson score formula (z = 1.959964).
  ci <- .amde_wilson(5L, 10L)
  expect_equal(ci[1], 0.2366, tolerance = 1e-3)
  expect_equal(ci[2], 0.7635, tolerance = 1e-3)

  # The county boot-arm evidence case: 2/125 must span the 2.5% gate edge.
  ci2 <- .amde_wilson(2L, 125L)
  expect_lt(ci2[1], 0.025)
  expect_gt(ci2[2], 0.025)

  # Degenerate but legal inputs.
  expect_equal(.amde_wilson(0L, 50L)[1], 0)
  expect_equal(.amde_wilson(50L, 50L)[2], 1)
  expect_true(all(is.na(.amde_wilson(0L, 0L))))
})

# ---------------------------------------------------------------------------
# 2. Classification
# ---------------------------------------------------------------------------

test_that("classification: point-estimate rule at full reps", {
  # At n = n_full the verdict is the point estimate, exactly like the
  # brute-force MDE interpolation consumes it.
  expect_identical(.amde_classify(200L, 250L, 250L, 0.80), "above")  # 0.80 >= .8
  expect_identical(.amde_classify(199L, 250L, 250L, 0.80), "below")
})

test_that("classification: early stopping needs the CI clear of the target", {
  expect_identical(.amde_classify(99L, 100L, 250L, 0.80), "above")   # lo > .8
  expect_identical(.amde_classify(0L, 30L, 250L, 0.80), "below")     # hi < .8
  expect_identical(.amde_classify(20L, 25L, 250L, 0.80), "undecided")
  expect_identical(.amde_classify(0L, 0L, 250L, 0.80), "undecided")
})

# ---------------------------------------------------------------------------
# 3. Tally from partial rows
# ---------------------------------------------------------------------------

test_that("tally counts attempted, usable, and rejected reps per delta", {
  rows <- tibble::tibble(
    estimator = "cs",
    inference = c("boot", "boot", "boot", "boot", "analytic"),
    estimand  = c("simple", "simple", "simple", "simple", "simple"),
    rep       = c(1L, 2L, 3L, 4L, 1L),
    delta     = c(0, 0, 0, 0.05, 0),
    p         = c(0.01, 0.50, NA_real_, NA_real_, 0.001),
    ci_lo     = c(NA, NA, 0.1, NA, NA),
    ci_hi     = c(NA, NA, 0.5, NA, NA),
    converged = c(TRUE, TRUE, TRUE, FALSE, TRUE)
  )
  t_boot <- .amde_tally(rows, arm = "boot", alpha = 0.05)
  # delta 0: reps 1-3 attempted; rep 3 has no p but a CI excluding 0 -> reject.
  d0 <- t_boot[t_boot$delta == 0, ]
  expect_identical(d0$n_done, 3L)
  expect_identical(d0$n_used, 3L)
  expect_identical(d0$k_reject, 2L)   # rep 1 (p=.01) + rep 3 (CI excludes 0)
  # delta 0.05: attempted but failed -> counted done, not usable.
  d5 <- t_boot[t_boot$delta == 0.05, ]
  expect_identical(d5$n_done, 1L)
  expect_identical(d5$n_used, 0L)
  expect_identical(d5$k_reject, 0L)
  # n_done counts ATTEMPTED cells (any arm's row proves the cell ran): a rep
  # whose analytic row is missing still counts as attempted-but-unusable for
  # the analytic arm (review finding B2 — an arm must never lose reps from
  # its failure denominator just because the estimator skipped that arm).
  t_an <- .amde_tally(rows, arm = "analytic", alpha = 0.05)
  d0a <- t_an[t_an$delta == 0, ]
  expect_identical(d0a$n_done, 3L)
  expect_identical(d0a$n_used, 1L)
  expect_identical(d0a$k_reject, 1L)
})

# ---------------------------------------------------------------------------
# 4. Scheduler: null phase
# ---------------------------------------------------------------------------

test_that("scheduler starts and finishes the null phase before any search", {
  a <- .next(.tly())
  expect_identical(a$type, "null_batch")
  expect_identical(a$delta, 0)
  expect_identical(a$reps, 1:25)

  a2 <- .next(.tly(delta = 0, n_done = 100L, k_reject = 5L))
  expect_identical(a2$type, "null_batch")
  expect_identical(a2$reps, 101:125)

  # Final partial batch is clipped to n_reps.
  a3 <- .next(.tly(delta = 0, n_done = 240L, k_reject = 5L))
  expect_identical(a3$reps, 241:250)
})

# ---------------------------------------------------------------------------
# 5. Scheduler: bisection on grid indices
# ---------------------------------------------------------------------------

test_that("first proposal after the null phase is the mid positive point", {
  # Upper-mid convention throughout: cand[floor(n/2) + 1]; 10 candidates -> 6th.
  a <- .next(.tly(delta = 0, n_done = 250L, k_reject = 10L))
  expect_identical(a$type, "eval_batch")
  expect_identical(a$delta, 0.06)
  expect_identical(a$reps, 1:25)
})

test_that("an undecided point keeps receiving batches before new proposals", {
  tal <- .tly(delta = c(0, 0.05), n_done = c(250L, 25L), k_reject = c(10L, 20L))
  a <- .next(tal)
  expect_identical(a$type, "eval_batch")
  expect_identical(a$delta, 0.05)
  expect_identical(a$reps, 26:50)
})

test_that("bisection moves up after a decisive below, down after above", {
  # 0.05 decisively below (0/50): candidates {.06,.08,.10,.15,.20} -> 0.10.
  tal_below <- .tly(delta = c(0, 0.05), n_done = c(250L, 50L),
                    k_reject = c(10L, 0L))
  a <- .next(tal_below)
  expect_identical(a$type, "eval_batch")
  expect_identical(a$delta, 0.10)

  # 0.05 decisively above (50/50): candidates {.01,.02,.03,.04} -> 0.03.
  tal_above <- .tly(delta = c(0, 0.05), n_done = c(250L, 50L),
                    k_reject = c(10L, 50L))
  b <- .next(tal_above)
  expect_identical(b$type, "eval_batch")
  expect_identical(b$delta, 0.03)
})

test_that("two-candidate window proposes the upper midpoint", {
  # lo = 0.05 (below), hi = 0.10 (above): candidates {.06,.08} -> 0.08.
  tal <- .tly(delta = c(0, 0.05, 0.10), n_done = c(250L, 50L, 50L),
              k_reject = c(10L, 0L, 50L))
  a <- .next(tal)
  expect_identical(a$type, "eval_batch")
  expect_identical(a$delta, 0.08)
})

# ---------------------------------------------------------------------------
# 6. Scheduler: top-up and completion
# ---------------------------------------------------------------------------

test_that("adjacent bracket points are topped up to full reps, lo first", {
  tal <- .tly(delta = c(0, 0.05, 0.06), n_done = c(250L, 50L, 60L),
              k_reject = c(10L, 0L, 60L))
  a <- .next(tal)
  expect_identical(a$type, "top_up")
  expect_identical(a$delta, 0.05)
  expect_identical(a$reps, 51:75)

  tal2 <- .tly(delta = c(0, 0.05, 0.06), n_done = c(250L, 250L, 60L),
               k_reject = c(10L, 100L, 60L))
  b <- .next(tal2)
  expect_identical(b$type, "top_up")
  expect_identical(b$delta, 0.06)

  # Both bracket points full: the FLANKING grid points (0.04 below lo, 0.08
  # above hi) must also reach full reps before completion, so the MDE
  # bootstrap CI's admissible support spans at least two grid steps per side
  # (Amendment 1 rule 2, review finding C1).
  tal3 <- .tly(delta = c(0, 0.05, 0.06), n_done = c(250L, 250L, 250L),
               k_reject = c(10L, 100L, 240L))
  d <- .next(tal3)
  expect_identical(d$type, "top_up_flank")
  expect_identical(d$delta, 0.04)
  expect_identical(d$reps, 1:25)

  tal4 <- .tly(delta = c(0, 0.04, 0.05, 0.06, 0.08),
               n_done = c(250L, 250L, 250L, 250L, 250L),
               k_reject = c(10L, 50L, 100L, 240L, 245L))
  e <- .next(tal4)
  expect_identical(e$type, "bracket_done")
  expect_identical(e$bracket, c(0.05, 0.06))
})

test_that("a topped-up point that flips reopens the search", {
  # 0.06 looked above early (60/60) but at full reps lands below target
  # (190/250 = 0.76): 0.06 becomes the lo; upward candidates are
  # {.08,.10,.15,.20} and the upper-mid convention proposes 0.15.
  tal <- .tly(delta = c(0, 0.05, 0.06), n_done = c(250L, 250L, 250L),
              k_reject = c(10L, 100L, 190L))
  a <- .next(tal)
  expect_identical(a$type, "eval_batch")
  expect_identical(a$delta, 0.15)
})

# ---------------------------------------------------------------------------
# 7. Scheduler: boundary verdicts
# ---------------------------------------------------------------------------

test_that("never_crosses requires grid max decisively below at full reps", {
  # Everything up to grid max below, but grid max early-stopped: top it up.
  tal <- .tly(delta = c(0, 0.05, 0.10, 0.20), n_done = c(250L, 50L, 50L, 60L),
              k_reject = c(10L, 0L, 0L, 0L))
  a <- .next(tal)
  expect_identical(a$type, "top_up")
  expect_identical(a$delta, 0.20)

  tal2 <- .tly(delta = c(0, 0.05, 0.10, 0.20),
               n_done = c(250L, 50L, 50L, 250L),
               k_reject = c(10L, 0L, 0L, 100L))
  b <- .next(tal2)
  expect_identical(b$type, "verdict_never_crosses")
})

test_that("at_or_below_smallest requires the smallest point at full reps", {
  tal <- .tly(delta = c(0, 0.01, 0.05), n_done = c(250L, 60L, 50L),
              k_reject = c(10L, 60L, 50L))
  a <- .next(tal)
  expect_identical(a$type, "top_up")
  expect_identical(a$delta, 0.01)

  tal2 <- .tly(delta = c(0, 0.01, 0.05), n_done = c(250L, 250L, 50L),
               k_reject = c(10L, 240L, 50L))
  b <- .next(tal2)
  expect_identical(b$type, "verdict_at_or_below_smallest")
})

# ---------------------------------------------------------------------------
# 8. Scheduler: anomaly (non-monotone classifications)
# ---------------------------------------------------------------------------

test_that("non-monotone classifications force full evaluation, then flag", {
  # 0.05 above but 0.10 below: conflicted range must be evaluated at full
  # reps (smallest under-replicated conflicted delta first) ...
  tal <- .tly(delta = c(0, 0.05, 0.10), n_done = c(250L, 60L, 60L),
              k_reject = c(10L, 60L, 0L))
  a <- .next(tal)
  expect_identical(a$type, "anomaly_top_up")
  expect_identical(a$delta, 0.05)

  # ... and once every conflicted point is at full reps and STILL
  # non-monotone, the scheduler stops with an explicit anomalous verdict.
  tal2 <- .tly(delta = c(0, 0.05, 0.10), n_done = c(250L, 250L, 250L),
               k_reject = c(10L, 250L, 0L))
  b <- .next(tal2)
  expect_identical(b$type, "done_anomalous")
})

# ===========================================================================
# Driver-level tests (mock estimator end-to-end via impose_fn/estimator_fn)
# ===========================================================================

skip_if_not(power_sim_modules_present() ||
              file.exists(file.path(.power_test_root, "R/power/run_scenario_grid.R")),
            "framework modules unavailable")

# A mock estimator with a KNOWN power curve, sharing common random numbers
# across deltas within a rep (the impose seed is reset per delta, so the
# first runif() draw is identical across deltas of a rep):
#   reject  <=>  u < pow(truth),  pow(t) = 0.06 + 0.94 * pnorm((t - .085)/.008)
# => null rejection ~6% (inside the [2.5%, 10%] gate), crossing of 0.80
# power between delta = 0.08 and delta = 0.10 (analytically at ~0.0917).
mock_estimator_known_power <- function(panel_sim, estimator = "cs",
                                       spec = list()) {
  tr <- !is.na(panel_sim$e) & panel_sim$e >= 0
  truth <- if (any(tr)) mean(panel_sim$delta_imposed[tr]) else 0
  u <- stats::runif(1)
  pow <- 0.06 + 0.94 * stats::pnorm((truth - 0.085) / 0.008)
  p <- if (u < pow) 0.001 else 0.60
  tibble::tibble(
    estimator = estimator, inference = "analytic", estimand = "overall",
    event_time = NA_real_, att = truth, se = 0.03, p = p,
    ci_lo = truth - 1.96 * 0.03, ci_hi = truth + 1.96 * 0.03,
    n_treated_clusters = 10L, n_control_clusters = 10L,
    converged = TRUE, error_msg = NA_character_, runtime_s = 0.001
  )
}

# Same contract, but null rejection ~50% — must fail the size gate.
mock_estimator_bad_size <- function(panel_sim, estimator = "cs",
                                    spec = list()) {
  out <- mock_estimator_known_power(panel_sim, estimator, spec)
  tr <- !is.na(panel_sim$e) & panel_sim$e >= 0
  truth <- if (any(tr)) mean(panel_sim$delta_imposed[tr]) else 0
  # Ambient RNG (seeded per cell by the impose step) => varies across reps.
  out$p <- if (stats::runif(1) < 0.5 + truth) 0.001 else 0.60
  out
}

.amde_cfg_path <- local({
  f <- tempfile(fileext = ".yml")
  writeLines(c(
    "level: state",
    "sample: [S2]",
    "covid: drop",
    "treat_def: online_start_date",
    "designs: [D1]",
    "mechanisms: [deterministic]",
    "shapes: [step]",
    "outcomes: [y_log1p]",
    "estimators: [cs]",
    "template: panel",
    "effect_grid: [0, 0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.08, 0.10, 0.15, 0.20]",
    "n_reps: 60",
    "alpha: [0.05]",
    "mde_boot: 50",
    "min_pre: 12",
    "min_post: 6"
  ), f)
  f
})

test_that("adaptive driver: gate passes, bracket found, matches brute force", {
  skip_if_not(file.exists(file.path(.power_test_root,
                                    "data/raw/state_month_panel_with_treatment.csv")),
              "state panel data unavailable")
  rn_a <- "_amde_e2e_adaptive"
  rn_b <- "_amde_e2e_brute"
  on.exit({
    unlink(.power_out_dir(rn_a), recursive = TRUE)
    unlink(.power_out_dir(rn_b), recursive = TRUE)
  }, add = TRUE)

  ra <- run_adaptive_mde(.amde_cfg_path, run_name = rn_a, workers = 1,
                         batch_size = 20L,
                         impose_fn = mock_impose_effect,
                         estimator_fn = mock_estimator_known_power,
                         resume = FALSE)

  gate <- ra$size_gate
  expect_true(all(gate$pass[gate$arm == "analytic"]))
  expect_identical(gate$n_done[gate$arm == "analytic"][1], 60L)

  m <- ra$mde[ra$mde$arm == "analytic", ]
  expect_identical(m$verdict, "interpolated")
  expect_identical(c(m$bracket_lo, m$bracket_hi), c(0.08, 0.10))
  expect_gt(m$mde, 0.08)
  expect_lt(m$mde, 0.10)

  # Both bracket points and delta=0 at full replication; economy elsewhere.
  rows <- readr::read_csv(
    file.path(.power_out_dir(rn_a), "partials",
              paste0(ra$grid$scenario_id[1], ".csv")),
    show_col_types = FALSE)
  n_by_delta <- rows |> dplyr::distinct(delta, rep) |> dplyr::count(delta)
  expect_identical(
    n_by_delta$n[n_by_delta$delta %in% c(0, 0.08, 0.10)], c(60L, 60L, 60L))
  expect_lt(sum(n_by_delta$n), 60L * 11L)   # visited a strict subset
  expect_false(0.01 %in% n_by_delta$delta)  # far-from-crossing points skipped

  # Brute force on the SAME config: overlapping cells bit-identical, same MDE.
  rb <- run_scenario_grid(.amde_cfg_path, resume = FALSE, workers = 1,
                          run_name = rn_b,
                          impose_fn = mock_impose_effect,
                          estimator_fn = mock_estimator_known_power)
  br <- rb$results |>
    dplyr::semi_join(rows |> dplyr::distinct(rep, delta), by = c("rep", "delta"))
  key <- c("rep", "delta")
  a_cells <- rows |> dplyr::arrange(rep, delta) |>
    dplyr::select(dplyr::all_of(c(key, "att", "se", "p", "truth")))
  b_cells <- br |> dplyr::arrange(rep, delta) |>
    dplyr::select(dplyr::all_of(c(key, "att", "se", "p", "truth")))
  expect_equal(as.data.frame(a_cells), as.data.frame(b_cells))

  mb <- rb$mde |> dplyr::filter(inference == "analytic")
  expect_equal(m$mde, mb$mde[1], tolerance = 1e-12)
})

test_that("adaptive driver: interrupted run resumes to the identical result", {
  skip_if_not(file.exists(file.path(.power_test_root,
                                    "data/raw/state_month_panel_with_treatment.csv")),
              "state panel data unavailable")
  rn_c <- "_amde_e2e_resume"
  rn_d <- "_amde_e2e_oneshot"
  on.exit({
    unlink(.power_out_dir(rn_c), recursive = TRUE)
    unlink(.power_out_dir(rn_d), recursive = TRUE)
  }, add = TRUE)

  r1 <- run_adaptive_mde(.amde_cfg_path, run_name = rn_c, workers = 1,
                         batch_size = 20L, max_actions = 4L,
                         impose_fn = mock_impose_effect,
                         estimator_fn = mock_estimator_known_power,
                         resume = FALSE)
  expect_true(is.null(r1$mde) || nrow(r1$mde) == 0L ||
                all(is.na(r1$mde$mde)))   # interrupted before completion

  r2 <- run_adaptive_mde(.amde_cfg_path, run_name = rn_c, workers = 1,
                         batch_size = 20L,
                         impose_fn = mock_impose_effect,
                         estimator_fn = mock_estimator_known_power,
                         resume = TRUE)
  r3 <- run_adaptive_mde(.amde_cfg_path, run_name = rn_d, workers = 1,
                         batch_size = 20L,
                         impose_fn = mock_impose_effect,
                         estimator_fn = mock_estimator_known_power,
                         resume = FALSE)
  expect_equal(as.data.frame(r2$mde), as.data.frame(r3$mde))

  # No duplicated cells after the resume.
  rows <- readr::read_csv(
    file.path(.power_out_dir(rn_c), "partials",
              paste0(r2$grid$scenario_id[1], ".csv")),
    show_col_types = FALSE)
  expect_identical(anyDuplicated(rows[, c("rep", "delta")]), 0L)
})

test_that("adaptive driver: a failed size gate stops before any MDE search", {
  skip_if_not(file.exists(file.path(.power_test_root,
                                    "data/raw/state_month_panel_with_treatment.csv")),
              "state panel data unavailable")
  rn_e <- "_amde_e2e_badsize"
  on.exit(unlink(.power_out_dir(rn_e), recursive = TRUE), add = TRUE)

  r <- run_adaptive_mde(.amde_cfg_path, run_name = rn_e, workers = 1,
                        batch_size = 20L,
                        impose_fn = mock_impose_effect,
                        estimator_fn = mock_estimator_bad_size,
                        resume = FALSE)
  expect_false(any(r$size_gate$pass))
  m <- r$mde
  expect_true(all(m$verdict == "size_gate_failed"))
  expect_true(all(is.na(m$mde)))

  rows <- readr::read_csv(
    file.path(.power_out_dir(rn_e), "partials",
              paste0(r$grid$scenario_id[1], ".csv")),
    show_col_types = FALSE)
  expect_identical(unique(rows$delta), 0)   # no delta > 0 ever estimated
})

# ---------------------------------------------------------------------------
# Regression: resume key formats and the zero-match data-loss guard
# (2026-08-19 03:05 incident: formatC(format="g", digits=15) left-pads to the
# digits width, so no new key matched an old-format sidecar and the resume
# rewrote a 675-cell partial with the empty match.)
# ---------------------------------------------------------------------------

test_that("cell keys are whitespace-free and match every historical format", {
  k <- .amde_key(1:2, 0.06)
  expect_false(any(grepl("[[:space:]]", k)))
  expect_identical(k, c("1,0.06", "2,0.06"))
  expect_identical(.amde_key(7L, 0), "7,0")
  expect_identical(.amde_key(226L, 0.2), "226,0.2")

  # Normalization accepts all three formats ever written to a sidecar:
  # old paste(), the padded formatC interlude, and the current key.
  legacy <- c("1,0", "2,               0", "3,            0.06")
  expect_identical(.amde_normalize_keys(legacy), c("1,0", "2,0", "3,0.06"))
})

test_that("a resume that matches zero cells refuses to discard the partial", {
  skip_if_not(file.exists(file.path(.power_test_root,
                                    "data/raw/state_month_panel_with_treatment.csv")),
              "state panel data unavailable")
  rn <- "_amde_e2e_zeromatch"
  on.exit(unlink(.power_out_dir(rn), recursive = TRUE), add = TRUE)

  r0 <- run_adaptive_mde(.amde_cfg_path, run_name = rn, workers = 1,
                         batch_size = 20L, max_actions = 2L,
                         impose_fn = mock_impose_effect,
                         estimator_fn = mock_estimator_known_power,
                         resume = FALSE)
  pdir <- file.path(.power_out_dir(rn), "partials")
  sc_file <- list.files(pdir, pattern = "done_cells$", full.names = TRUE)[1]
  # Corrupt the sidecar so no key can match.
  writeLines(c("999999,42"), sc_file)
  expect_error(
    run_adaptive_mde(.amde_cfg_path, run_name = rn, workers = 1,
                     batch_size = 20L, max_actions = 2L,
                     impose_fn = mock_impose_effect,
                     estimator_fn = mock_estimator_known_power,
                     resume = TRUE),
    "refusing"
  )
  # The partial survived untouched.
  pfile <- list.files(pdir, pattern = "csv$", full.names = TRUE)
  pfile <- pfile[!grepl("orphaned|done_cells|cs_safe_patches", pfile)][1]
  rows <- readr::read_csv(pfile, show_col_types = FALSE)
  expect_gt(nrow(rows), 0L)
})
