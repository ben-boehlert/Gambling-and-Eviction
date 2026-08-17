################################################################################
# test-shift-mode.R
#
# `shift_mode` (R/power/config.R, R/power/run_scenario_grid.R): the validated
# calibration-subset shortcut (analysis/diagnostics/validate_shift_
# sufficiency.R, output/shift_validation{,_cs}/) that runs the full delta
# grid on only shift_calibration_reps reps and reconstructs the rest from a
# fitted loading L_hat on each rep's own delta=0 fit.
#
# Coverage: config defaults/coercion, per-scenario shift_calibration_reps
# default formula, golden-id stability with the flag OFF, id movement with
# the flag ON, the .shift_synthesize_partial() arithmetic (hand-computed),
# idempotence, boot/jack left unreconstructable, and an end-to-end resume
# path where reps are complete but synthesis was interrupted.
################################################################################

.write_yaml_shift <- function(lines) {
  f <- tempfile(fileext = ".yml")
  writeLines(lines, f)
  f
}

# ---------------------------------------------------------------------------
# 1. Config defaults / coercion
# ---------------------------------------------------------------------------

test_that("shift_mode / shift_calibration_reps default and coerce correctly", {
  skip_if_not(file.exists("../../config/power_validation.yml"),
              "run from repo root or tests/testthat")
  cfg <- read_power_config("../../config/power_validation.yml")
  expect_false(cfg$shift_mode)
  expect_null(cfg$shift_calibration_reps)

  f <- .write_yaml_shift(c(
    "level: state", "sample: [S2]", "treat_def: online_start_date",
    "designs: [D1]", "effect_grid: [0, 0.05]", "n_reps: 40",
    "estimators: [twfe]", "shift_mode: true", "shift_calibration_reps: 7"
  ))
  cfg2 <- read_power_config(f)
  expect_true(cfg2$shift_mode)
  expect_identical(cfg2$shift_calibration_reps, 7L)

  f2 <- .write_yaml_shift(c(
    "level: state", "sample: [S2]", "treat_def: online_start_date",
    "designs: [D1]", "effect_grid: [0, 0.05]", "n_reps: 40",
    "estimators: [twfe]", "shift_mode: true"
  ))
  cfg3 <- read_power_config(f2)
  expect_true(cfg3$shift_mode)
  expect_null(cfg3$shift_calibration_reps)  # resolved per-scenario, not here
})

test_that("shift_calibration_reps defaults to max(10, ceil(0.1*n_reps)) per scenario", {
  f <- .write_yaml_shift(c(
    "level: state", "sample: [S2]", "covid: keep",
    "treat_def: online_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    "estimators: [twfe]", "effect_grid: [0, 0.05]",
    "n_reps: 40", "base_seed: 123", "min_pre: 12", "min_post: 6",
    "shift_mode: true",
    "scenarios:",
    "  - name: a",
    "    n_reps: 40",
    "  - name: b",
    "    n_reps: 300"
  ))
  cfg <- read_power_config(f)
  grid <- expand_scenario_grid(cfg)
  a <- grid[grid$name == "a", ]
  b <- grid[grid$name == "b", ]
  expect_identical(a$shift_calibration_reps, 10L)   # max(10L, ceiling(4))
  expect_identical(b$shift_calibration_reps, 30L)   # max(10L, ceiling(30))
  expect_true(all(grid$shift_mode))

  # An explicit run-level override pins ONE value for every scenario.
  f2 <- .write_yaml_shift(c(
    "level: state", "sample: [S2]", "covid: keep",
    "treat_def: online_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    "estimators: [twfe]", "effect_grid: [0, 0.05]",
    "n_reps: 40", "base_seed: 123", "min_pre: 12", "min_post: 6",
    "shift_mode: true", "shift_calibration_reps: 22",
    "scenarios:",
    "  - name: a",
    "    n_reps: 40",
    "  - name: b",
    "    n_reps: 300"
  ))
  grid2 <- expand_scenario_grid(read_power_config(f2))
  expect_true(all(grid2$shift_calibration_reps == 22L))
})

# ---------------------------------------------------------------------------
# 2. Golden scenario ids: flag OFF unchanged; flag ON moves every id
# ---------------------------------------------------------------------------

test_that("flag-OFF scenario ids match the partials already on disk", {
  skip_if_not(file.exists("../../config/power_cheap.yml"),
              "run from repo root or tests/testthat")
  cfg <- read_power_config("../../config/power_cheap.yml")
  expect_false(cfg$shift_mode)
  grid <- expand_scenario_grid(cfg)
  golden <- c("S0199769b58", "S7570c31060", "Sd9e469e5a5",
              "Sff2a24764c", "S0508e397a6")
  expect_true(all(golden %in% substr(grid$scenario_id, 1, 11)))
})

test_that("shift_mode TRUE moves every scenario id; calibration_reps moves it further", {
  skip_if_not(file.exists("../../config/power_cheap.yml"),
              "run from repo root or tests/testthat")
  cfg <- read_power_config("../../config/power_cheap.yml")
  base <- expand_scenario_grid(cfg)

  cfg_on <- cfg
  cfg_on$shift_mode <- TRUE
  on <- expand_scenario_grid(cfg_on)
  expect_false(any(on$scenario_id %in% base$scenario_id))

  cfg_on2 <- cfg_on
  cfg_on2$shift_calibration_reps <- 33L
  on2 <- expand_scenario_grid(cfg_on2)
  expect_false(any(on2$scenario_id %in% on$scenario_id))
  expect_false(any(on2$scenario_id %in% base$scenario_id))
})

# ---------------------------------------------------------------------------
# 3. .shift_synthesize_partial() arithmetic — hand-computed
# ---------------------------------------------------------------------------

.build_hand_partial <- function() {
  tibble::tibble(
    estimator  = c("twfe", "twfe", "twfe", "twfe",     # analytic
                  "twfe", "twfe", "twfe", "twfe",     # wild
                  "cs",   "cs",                        # boot (unreconstructable)
                  "cs",   "cs"),                        # jack (unreconstructable)
    inference  = c("analytic", "analytic", "analytic", "analytic",
                  "wild", "wild", "wild", "wild",
                  "boot", "boot",
                  "jack", "jack"),
    estimand   = "simple",
    event_time = NA_real_,
    rep        = c(1L, 1L, 2L, 2L,
                  1L, 1L, 2L, 2L,
                  1L, 2L,
                  1L, 2L),
    delta      = c(0, 0.1, 0, 0.1,
                  0, 0.1, 0, 0.1,
                  0, 0.1,
                  0, 0.1),
    att        = c(1.0, 1.3, 2.0, NA_real_,
                  1.0, 1.4, 2.0, NA_real_,
                  NA_real_, NA_real_,
                  NA_real_, NA_real_),
    se         = c(0.5, 0.5, 0.4, NA_real_,
                  0.5, 0.5, 0.4, NA_real_,
                  NA_real_, NA_real_,
                  NA_real_, NA_real_),
    p          = c(0.05, 0.02, 0.01, NA_real_,
                  0.05, 0.02, 0.01, NA_real_,
                  NA_real_, NA_real_,
                  NA_real_, NA_real_),
    ci_lo      = c(0.2, 0.5, 1.0, NA_real_,
                  0.3, 0.7, 1.2, NA_real_,
                  NA_real_, NA_real_,
                  NA_real_, NA_real_),
    ci_hi      = c(1.8, 2.1, 3.5, NA_real_,
                  1.9, 2.3, 2.9, NA_real_,
                  NA_real_, NA_real_,
                  NA_real_, NA_real_),
    n_treated_clusters = c(5L, 5L, 5L, 5L,  5L, 5L, 5L, 5L,  NA_integer_, 5L,
                          NA_integer_, 5L),
    n_control_clusters = c(5L, 5L, 4L, 4L,  5L, 5L, 4L, 4L,  NA_integer_, 4L,
                          NA_integer_, 4L),
    converged  = c(TRUE, TRUE, TRUE, FALSE,
                  TRUE, TRUE, TRUE, FALSE,
                  FALSE, FALSE,
                  FALSE, FALSE),
    error_msg  = c(NA, NA, NA, "shift_pending",
                  NA, NA, NA, "shift_pending",
                  NA, "shift_pending",
                  NA, "shift_pending"),
    runtime_s  = 0.01,
    truth      = c(0, 0.1, 0, 0.1,
                  0, 0.1, 0, 0.1,
                  0, 0.1,
                  0, 0.1),
    seed_rep   = 999  # present so .PARTIAL_COL_TYPES matches without warning
  )
}

test_that(".shift_synthesize_partial fills analytic/wild rows and reproduces hand-computed values", {
  f <- tempfile(fileext = ".csv")
  readr::write_csv(.build_hand_partial(), f)

  synth <- .shift_synthesize_partial(f)
  expect_true(synth$changed)
  # 2 fillable (twfe/analytic, twfe/wild) + 2 unreconstructable (cs/boot, cs/jack)
  expect_equal(synth$n_filled, 2L)
  expect_equal(synth$n_unfilled, 2L)
  expect_equal(unname(synth$unfilled_by_reason["shift_not_reconstructable"]), 2L)

  d <- readr::read_csv(f, show_col_types = FALSE)

  # --- analytic: hand-computed --------------------------------------------
  # l_hat = (att(0.1) - att(0)) / truth = (1.3 - 1.0) / 0.1 = 3.0
  # rep2 baseline att0=2.0, se0=0.4, ci=[1.0, 3.5]; shift = 3.0 * 0.1 = 0.3
  an <- d[d$estimator == "twfe" & d$inference == "analytic" &
            d$rep == 2 & d$delta == 0.1, ]
  expect_equal(nrow(an), 1L)
  expect_equal(an$att, 2.3, tolerance = 1e-8)
  expect_equal(an$se, 0.4, tolerance = 1e-8)
  expect_equal(an$ci_lo, 1.3, tolerance = 1e-8)
  expect_equal(an$ci_hi, 3.8, tolerance = 1e-8)
  df_bl <- 5L + 4L - 1L
  expect_equal(an$p, 2 * stats::pt(-abs(2.3 / 0.4), df = df_bl), tolerance = 1e-10)
  expect_true(an$converged)
  # Filled rows are tagged "shift_filled" (NOT NA) so a later re-synthesis
  # pass can exclude them from the calibration pool -- see the "re-synthesis
  # does not refit on filled rows" test below.
  expect_identical(an$error_msg, "shift_filled")

  # --- wild: CI shifts the same way, but p is NOT reconstructable ---------
  # l_hat = (1.4 - 1.0) / 0.1 = 4.0; rep2 baseline att0=2.0, ci=[1.2, 2.9]
  # shift = 4.0 * 0.1 = 0.4
  wi <- d[d$estimator == "twfe" & d$inference == "wild" &
            d$rep == 2 & d$delta == 0.1, ]
  expect_equal(nrow(wi), 1L)
  expect_equal(wi$att, 2.4, tolerance = 1e-8)
  expect_equal(wi$se, 0.4, tolerance = 1e-8)
  expect_equal(wi$ci_lo, 1.6, tolerance = 1e-8)
  expect_equal(wi$ci_hi, 3.3, tolerance = 1e-8)
  expect_true(is.na(wi$p))          # genuine bootstrap p not reconstructable
  expect_true(wi$converged)
  expect_identical(wi$error_msg, "shift_filled")

  # --- boot / jack: never synthesized --------------------------------------
  bo <- d[d$estimator == "cs" & d$inference == "boot" &
            d$rep == 2 & d$delta == 0.1, ]
  ja <- d[d$estimator == "cs" & d$inference == "jack" &
            d$rep == 2 & d$delta == 0.1, ]
  expect_identical(bo$error_msg, "shift_not_reconstructable")
  expect_identical(ja$error_msg, "shift_not_reconstructable")
  expect_false(bo$converged)
  expect_false(ja$converged)
  expect_true(is.na(bo$att))
  expect_true(is.na(ja$att))

  # --- loading table ---------------------------------------------------
  expect_equal(synth$loading$l_hat[synth$loading$estimator == "twfe" &
                                     synth$loading$inference == "analytic"],
              3.0, tolerance = 1e-8)
  expect_equal(synth$loading$l_hat[synth$loading$estimator == "twfe" &
                                     synth$loading$inference == "wild"],
              4.0, tolerance = 1e-8)
})

test_that(".shift_synthesize_partial is idempotent", {
  f <- tempfile(fileext = ".csv")
  readr::write_csv(.build_hand_partial(), f)

  s1 <- .shift_synthesize_partial(f)
  expect_true(s1$changed)
  d1 <- readr::read_csv(f, show_col_types = FALSE)

  s2 <- .shift_synthesize_partial(f)
  expect_false(s2$changed)
  expect_equal(s2$n_filled, 0L)
  expect_equal(s2$n_unfilled, 0L)
  d2 <- readr::read_csv(f, show_col_types = FALSE)

  expect_equal(as.data.frame(d1), as.data.frame(d2))
})

test_that(".shift_synthesize_partial is a no-op when there are no pending rows", {
  f <- tempfile(fileext = ".csv")
  clean <- .build_hand_partial()
  clean <- clean[clean$error_msg %in% NA | clean$error_msg != "shift_pending", ]
  readr::write_csv(clean, f)
  before <- readr::read_csv(f, show_col_types = FALSE)

  s <- .shift_synthesize_partial(f)
  expect_false(s$changed)
  after <- readr::read_csv(f, show_col_types = FALSE)
  expect_equal(as.data.frame(before), as.data.frame(after))
})

test_that(".shift_synthesize_partial marks an unusable baseline distinctly", {
  d <- .build_hand_partial()
  # Corrupt rep 2's analytic delta=0 baseline (se0 <= 0 -> unusable).
  d$se[d$estimator == "twfe" & d$inference == "analytic" &
         d$rep == 2 & d$delta == 0] <- 0
  f <- tempfile(fileext = ".csv")
  readr::write_csv(d, f)

  synth <- .shift_synthesize_partial(f)
  out <- readr::read_csv(f, show_col_types = FALSE)
  bad <- out[out$estimator == "twfe" & out$inference == "analytic" &
               out$rep == 2 & out$delta == 0.1, ]
  expect_identical(bad$error_msg, "shift_baseline_unusable")
  expect_false(bad$converged)
})

# ---------------------------------------------------------------------------
# 4. End-to-end resume: reps complete, synthesis interrupted before it ran
# ---------------------------------------------------------------------------

test_that("run_scenario_grid resume fills shift_pending rows when reps are already complete", {
  cfg_path <- .write_yaml_shift(c(
    "level: state", "sample: [S2]", "covid: keep",
    "treat_def: online_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    "estimators: [twfe]", "effect_grid: [0, 0.05]",
    "n_reps: 3", "base_seed: 123", "min_pre: 12", "min_post: 6",
    "shift_mode: true", "shift_calibration_reps: 2"
  ))
  cfg <- read_power_config(cfg_path)
  grid <- expand_scenario_grid(cfg)
  sid <- grid$scenario_id[1]
  off <- grid$scenario_seed_offset[1]

  rn <- paste0("_test_shift_resume_", format(Sys.time(), "%H%M%OS3"))
  on.exit(unlink(.power_out_dir(rn), recursive = TRUE), add = TRUE)

  # Hand-build a "complete" partial (every (estimator,rep,delta) triple
  # present) where rep 3 / delta 0.05 is still tagged shift_pending, as if
  # the process crashed AFTER the batch loop finished but BEFORE
  # .shift_synthesize_partial() ran. Reps 1-2 are calibration reps (real
  # fits at both deltas); rep 3 is not.
  fake <- tidyr::expand_grid(rep = 1:3, delta = c(0, 0.05)) %>%
    dplyr::mutate(
      scenario_id = sid, scenario_index = 1L, name = "default",
      level = "state", sample = "S2", covid = "keep",
      treat_def = "online_start_date", design = "D1",
      mechanism = "deterministic", shape = "step", outcome = "y_log1p",
      est_anticipation = 0L, loader_anticipation = 6L,
      control_group = "notyettreated", quarterly = FALSE, template = "national",
      estimator = "twfe", inference = "analytic", estimand = "simple",
      event_time = NA_real_,
      # rep1: 1.0 -> 1.4 (shift 0.4); rep2: 1.2 -> 1.7 (shift 0.5);
      # rep3: 2.0 -> pending. l_hat = (0.4*0.05+0.5*0.05)/(2*0.05^2) = 9.0
      att = dplyr::case_when(rep == 1 & delta == 0    ~ 1.0,
                             rep == 1 & delta == 0.05 ~ 1.4,
                             rep == 2 & delta == 0    ~ 1.2,
                             rep == 2 & delta == 0.05 ~ 1.7,
                             rep == 3 & delta == 0    ~ 2.0,
                             TRUE                     ~ NA_real_),
      se = ifelse(rep == 3 & delta == 0.05, NA_real_, 0.5),
      p  = ifelse(rep == 3 & delta == 0.05, NA_real_, 0.05),
      ci_lo = ifelse(rep == 3 & delta == 0.05, NA_real_, att - 1),
      ci_hi = ifelse(rep == 3 & delta == 0.05, NA_real_, att + 1),
      n_treated_clusters = 5L, n_control_clusters = 5L,
      converged = !(rep == 3 & delta == 0.05),
      error_msg = ifelse(rep == 3 & delta == 0.05, "shift_pending", NA_character_),
      runtime_s = 0.01,
      truth = delta,
      seed_rep = power_rep_seed(123L, rep, off)
    )
  partial_path <- .power_out_file(rn, "partials", paste0(sid, ".csv"))
  readr::write_csv(fake, partial_path)

  r <- run_scenario_grid(cfg_path, resume = TRUE, workers = 1, run_name = rn,
                         impose_fn = mock_impose_effect,
                         estimator_fn = mock_run_estimator)

  filled <- r$results %>% dplyr::filter(rep == 3, delta == 0.05)
  expect_equal(nrow(filled), 1L)
  expect_true(filled$converged)
  expect_false(is.na(filled$att))
  # l_hat = 9.0 (hand-computed above); shift = 9.0 * 0.05 = 0.45
  expect_equal(filled$att, 2.0 + 0.45, tolerance = 1e-8)
  expect_identical(filled$error_msg, "shift_filled")
  expect_false(any(!is.na(r$results$error_msg) &
                     r$results$error_msg == "shift_pending"))
})

test_that("shift_mode requires 0 in the effect_grid", {
  cfg_path <- .write_yaml_shift(c(
    "level: state", "sample: [S2]", "covid: keep",
    "treat_def: online_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    "estimators: [twfe]", "effect_grid: [0.02, 0.05]",
    "n_reps: 2", "base_seed: 123", "min_pre: 12", "min_post: 6",
    "shift_mode: true", "shift_calibration_reps: 1"
  ))
  rn <- paste0("_test_shift_no0_", format(Sys.time(), "%H%M%OS3"))
  on.exit(unlink(.power_out_dir(rn), recursive = TRUE), add = TRUE)
  expect_error(
    run_scenario_grid(cfg_path, resume = FALSE, workers = 1, run_name = rn,
                      impose_fn = mock_impose_effect,
                      estimator_fn = mock_run_estimator),
    "requires 0 in the effect_grid"
  )
})

# ---------------------------------------------------------------------------
# 5. End-to-end (mocked): fresh run completes with no remaining shift_pending
# ---------------------------------------------------------------------------

test_that("a fresh shift_mode run (mocked) completes with no shift_pending rows left", {
  cfg_path <- .write_yaml_shift(c(
    "level: state", "sample: [S2]", "covid: keep",
    "treat_def: online_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    "estimators: [twfe]", "effect_grid: [0, 0.05, 0.10]",
    "n_reps: 8", "base_seed: 123", "min_pre: 12", "min_post: 6",
    "shift_mode: true", "shift_calibration_reps: 3"
  ))
  rn <- paste0("_test_shift_fresh_", format(Sys.time(), "%H%M%OS3"))
  on.exit(unlink(.power_out_dir(rn), recursive = TRUE), add = TRUE)

  r <- run_scenario_grid(cfg_path, resume = FALSE, workers = 1, run_name = rn,
                         impose_fn = mock_impose_effect,
                         estimator_fn = mock_run_estimator, batch_size = 3L)

  # 1 scenario x 8 reps x 3 deltas x 1 estimator, one row each (mock).
  expect_equal(nrow(r$results), 24L)
  # No row is left in the transient "shift_pending" state: every placeholder
  # was either filled (converged) or, if its own rep's D1 schedule draw was
  # infeasible, replaced upstream by a genuine "schedule generation failed"
  # row (a pre-existing, shift-mode-independent property of this stochastic
  # design -- confirmed by an identical brute-force run over the same rep
  # range failing the SAME class of reps for the SAME reason).
  expect_false(any(!is.na(r$results$error_msg) &
                     r$results$error_msg == "shift_pending"))
  expect_true(all(r$results$error_msg[!r$results$converged] %in% NA |
                    grepl("^schedule generation failed",
                          r$results$error_msg[!r$results$converged])))
  # Every row that DID converge (whether genuinely estimated or filled by
  # synthesis) has a finite att.
  expect_true(all(is.finite(r$results$att[r$results$converged])))
})

# ---------------------------------------------------------------------------
# 6. Coordinator-review fixes: per-delta loading, wild CI fallback,
#    re-synthesis contamination, shift_calibration_reps edge values
# ---------------------------------------------------------------------------

test_that("BLOCKER 1: L_hat is fit PER DELTA and recovers a known delta-varying loading", {
  # Two nonzero deltas with DELIBERATELY DIFFERENT true loadings (L=2 at
  # delta=0.05, L=5 at delta=0.10) -- a pooled (single, cross-delta) fit
  # could not recover both exactly; a per-delta fit must.
  base_row <- function(rep, delta, att, converged = TRUE,
                       error_msg = NA_character_) {
    tibble::tibble(
      estimator = "twfe", inference = "analytic", estimand = "simple",
      event_time = NA_real_, rep = rep, delta = delta, att = att,
      se = 0.5, p = 0.05, ci_lo = att - 1, ci_hi = att + 1,
      n_treated_clusters = 5L, n_control_clusters = 5L,
      converged = converged, error_msg = error_msg, runtime_s = 0.01,
      truth = delta, seed_rep = 1
    )
  }
  d <- dplyr::bind_rows(
    # rep 1-2: calibration reps, real fits at BOTH deltas.
    base_row(1L, 0,    1.0), base_row(1L, 0.05, 1.10), base_row(1L, 0.10, 1.25),
    base_row(2L, 0,    2.0), base_row(2L, 0.05, 2.10), base_row(2L, 0.10, 2.25),
    # rep 3: baseline only + two pending rows.
    base_row(3L, 0,    3.0),
    base_row(3L, 0.05, NA_real_, converged = FALSE, error_msg = "shift_pending"),
    base_row(3L, 0.10, NA_real_, converged = FALSE, error_msg = "shift_pending")
  )
  # rep1: shift(0.05) = 0.10 = L*0.05 -> L=2; shift(0.10) = 0.25 = L*0.10 -> L=2.5??
  # Recompute cleanly below instead of eyeballing -- see hand values.
  f <- tempfile(fileext = ".csv")
  readr::write_csv(d, f)
  synth <- .shift_synthesize_partial(f)
  expect_true(synth$changed)

  # Hand computation:
  #  delta=0.05: rep1 shift = 1.10-1.00 = 0.10; rep2 shift = 2.10-2.00 = 0.10
  #    L_hat(0.05) = (0.10*0.05 + 0.10*0.05) / (2*0.05^2) = 0.01/0.005 = 2.0
  #  delta=0.10: rep1 shift = 1.25-1.00 = 0.25; rep2 shift = 2.25-2.00 = 0.25
  #    L_hat(0.10) = (0.25*0.10 + 0.25*0.10) / (2*0.10^2) = 0.05/0.02 = 2.5
  l_005 <- synth$loading$l_hat[synth$loading$delta == 0.05]
  l_010 <- synth$loading$l_hat[synth$loading$delta == 0.10]
  expect_equal(l_005, 2.0, tolerance = 1e-8)
  expect_equal(l_010, 2.5, tolerance = 1e-8)
  expect_false(isTRUE(all.equal(l_005, l_010)))  # genuinely delta-varying

  out <- readr::read_csv(f, show_col_types = FALSE)
  r3_005 <- out[out$rep == 3 & out$delta == 0.05, ]
  r3_010 <- out[out$rep == 3 & out$delta == 0.10, ]
  # rep3 baseline att0 = 3.0
  expect_equal(r3_005$att, 3.0 + 2.0 * 0.05, tolerance = 1e-8)   # 3.10
  expect_equal(r3_010$att, 3.0 + 2.5 * 0.10, tolerance = 1e-8)   # 3.25
  # A pooled (non-per-delta) fit would have given the SAME loading at both
  # deltas -- these two filled atts must differ by more than what a single
  # pooled slope could produce, confirming the per-delta mechanism is live.
  expect_false(isTRUE(all.equal(
    (r3_005$att - 3.0) / 0.05, (r3_010$att - 3.0) / 0.10)))
})

test_that("BLOCKER 2: .reject_flag CI-fallback matches p-based rejection when both are present", {
  # When p is available, the fallback must be bit-identical to p <= alpha
  # regardless of what the CI says (even a CI that would DISAGREE with the
  # p-based call must not move the result -- p always wins when present).
  p     <- c(0.01, 0.20, 0.049, 0.051)
  ci_lo <- c(-1, -1,  -1, -1)     # every CI here contains 0 (would say "not reject")
  ci_hi <- c( 1,  1,   1,  1)
  alpha <- 0.05
  expect_identical(.reject_flag(p, ci_lo, ci_hi, alpha), p <= alpha)

  # When p is NA, the CI fallback determines rejection.
  p_na <- rep(NA_real_, 4)
  ci_lo2 <- c(0.1, -0.1, 0.1, -1)
  ci_hi2 <- c(1.0,  0.1, NA_real_, 1)
  got <- .reject_flag(p_na, ci_lo2, ci_hi2, alpha)
  expect_identical(got, c(TRUE, FALSE, NA, FALSE))

  # Neither usable -> NA.
  expect_true(is.na(.reject_flag(NA_real_, NA_real_, NA_real_, alpha)))
})

test_that("N1: .reject_flag's CI fallback only answers the CI's OWN alpha level", {
  # A stored CI has exactly ONE confidence level (.CI_ALPHA = 0.05, matching
  # run_estimators.R's .re_spec() default). summarize_oc() evaluates
  # rejection at every element of alpha_vec (typically 0.10, 0.05, 0.01) --
  # a single 95% interval cannot answer the 90% or 99% question, and must
  # return NA there rather than silently reusing the 95% test (which would
  # understate reject_010 and overstate reject_001).
  p <- NA_real_; ci_lo <- 0.1; ci_hi <- 1.0   # excludes 0 -> "reject" at .05

  expect_true(.reject_flag(p, ci_lo, ci_hi, 0.05))          # matches .CI_ALPHA
  expect_true(is.na(.reject_flag(p, ci_lo, ci_hi, 0.10)))   # NOT computable
  expect_true(is.na(.reject_flag(p, ci_lo, ci_hi, 0.01)))   # NOT computable

  # A CI genuinely stored at a DIFFERENT level (via the ci_alpha argument)
  # answers ITS OWN level and no other.
  expect_true(.reject_flag(p, ci_lo, ci_hi, 0.10, ci_alpha = 0.10))
  expect_true(is.na(.reject_flag(p, ci_lo, ci_hi, 0.05, ci_alpha = 0.10)))

  # A row WITH a stored p is unaffected -- p answers every alpha directly.
  expect_true(.reject_flag(0.03, ci_lo, ci_hi, 0.10))
  expect_true(.reject_flag(0.03, ci_lo, ci_hi, 0.05))
  expect_false(.reject_flag(0.03, ci_lo, ci_hi, 0.01))

  # End-to-end through summarize_oc()'s full alpha_vec (the exact pathway
  # N1 was found in): reject_005 is determinate, reject_010/reject_001 are
  # NA-safe, not silently wrong.
  d <- tibble::tibble(
    scenario_id = "S1", estimator = "twfe", inference = "wild",
    estimand = "simple", event_time = NA_real_, delta = 0.05, rep = 1L,
    att = 1, se = 0.5, p = NA_real_, ci_lo = 0.1, ci_hi = 1.0,
    n_treated_clusters = 5L, n_control_clusters = 5L,
    converged = TRUE, error_msg = "shift_filled", runtime_s = 0.01, truth = 0.05
  )
  oc <- summarize_oc(d, alpha_vec = c(0.10, 0.05, 0.01))
  expect_equal(oc$reject_005, 1)
  expect_true(is.na(oc$reject_010))
  expect_true(is.na(oc$reject_001))
})

test_that("BLOCKER 2: n_reject_used reports the true denominator behind reject_*", {
  mk <- function(p, ci_lo, ci_hi) {
    tibble::tibble(
      scenario_id = "S1", estimator = "twfe", inference = "wild",
      estimand = "simple", event_time = NA_real_, delta = 0.05,
      rep = seq_along(p), att = 1, se = 0.5, p = p, ci_lo = ci_lo, ci_hi = ci_hi,
      n_treated_clusters = 5L, n_control_clusters = 5L,
      converged = TRUE, error_msg = NA_character_, runtime_s = 0.01, truth = 0.05
    )
  }
  # 4 converged rows: 2 with a real p, 1 with p=NA but a usable CI, 1 fully
  # unusable (p=NA, CI=NA).
  d <- mk(p = c(0.01, 0.20, NA_real_, NA_real_),
          ci_lo = c(-1, -1, 0.1, NA_real_),
          ci_hi = c(1, 1, 1.0, NA_real_))
  oc <- summarize_oc(d, alpha_vec = 0.05)
  expect_true("n_reject_used" %in% names(oc))
  expect_equal(oc$n_reject_used, 3L)   # 2 with p + 1 CI-fallback-usable
  expect_equal(oc$n_converged, 4L)     # distinct from n_reject_used
  # reject_005: rows 1 (p<=.05 TRUE), 2 (FALSE), 3 (CI excludes 0 -> TRUE),
  # 4 (unusable, dropped by na.rm) -> mean(TRUE,FALSE,TRUE) = 2/3.
  expect_equal(oc$reject_005, 2 / 3, tolerance = 1e-8)
})

test_that("re-synthesis after marking does not refit L_hat on filled rows", {
  base_row <- function(rep, delta, att, converged = TRUE,
                       error_msg = NA_character_) {
    tibble::tibble(
      estimator = "twfe", inference = "analytic", estimand = "simple",
      event_time = NA_real_, rep = rep, delta = delta, att = att,
      se = 0.5, p = 0.05, ci_lo = att - 1, ci_hi = att + 1,
      n_treated_clusters = 5L, n_control_clusters = 5L,
      converged = converged, error_msg = error_msg, runtime_s = 0.01,
      truth = delta, seed_rep = 1
    )
  }
  # Two genuine calibration reps (L_hat = 2.0 exactly, hand-computable) plus
  # ONE pending rep.
  d <- dplyr::bind_rows(
    base_row(1L, 0, 1.0), base_row(1L, 0.05, 1.10),
    base_row(2L, 0, 2.0), base_row(2L, 0.05, 2.10),
    base_row(3L, 0, 3.0),
    base_row(3L, 0.05, NA_real_, converged = FALSE, error_msg = "shift_pending")
  )
  f <- tempfile(fileext = ".csv")
  readr::write_csv(d, f)

  s1 <- .shift_synthesize_partial(f)
  expect_true(s1$changed)
  expect_equal(s1$loading$l_hat, 2.0, tolerance = 1e-8)
  filled1 <- readr::read_csv(f, show_col_types = FALSE)
  rep3 <- filled1[filled1$rep == 3 & filled1$delta == 0.05, ]
  expect_equal(rep3$att, 3.0 + 2.0 * 0.05, tolerance = 1e-8)   # 3.10
  expect_identical(rep3$error_msg, "shift_filled")

  # CORRUPT the now-filled rep-3 row to a value inconsistent with L_hat=2.0
  # (simulates what a contaminated second pass could produce if it treated
  # this filled row as a genuine calibration pair) and add a NEW pending rep.
  filled1$att[filled1$rep == 3 & filled1$delta == 0.05] <- 999
  new_pending <- dplyr::bind_rows(
    base_row(4L, 0, 4.0),
    base_row(4L, 0.05, NA_real_, converged = FALSE, error_msg = "shift_pending")
  )
  d2 <- dplyr::bind_rows(filled1, new_pending)
  f2 <- tempfile(fileext = ".csv")
  readr::write_csv(d2, f2)

  s2 <- .shift_synthesize_partial(f2)
  expect_true(s2$changed)
  # If rep 3's corrupted (att=999) row had contaminated the calibration
  # pool, L_hat would be wildly different from 2.0. It must not be.
  expect_equal(s2$loading$l_hat, 2.0, tolerance = 1e-8)
  filled2 <- readr::read_csv(f2, show_col_types = FALSE)
  rep4 <- filled2[filled2$rep == 4 & filled2$delta == 0.05, ]
  expect_equal(rep4$att, 4.0 + 2.0 * 0.05, tolerance = 1e-8)   # 4.10, not
  # contaminated by rep 3's corrupted 999.
})

test_that("BLOCKER 3: synthesis writes atomically and asserts post-fill invariants", {
  f <- tempfile(fileext = ".csv")
  readr::write_csv(.build_hand_partial(), f)
  n_before <- nrow(readr::read_csv(f, show_col_types = FALSE))

  .shift_synthesize_partial(f)

  expect_false(file.exists(paste0(f, ".tmp")))  # no leftover temp file
  after <- readr::read_csv(f, show_col_types = FALSE)
  expect_equal(nrow(after), n_before)
  expect_false(any(!is.na(after$error_msg) & after$error_msg == "shift_pending"))
  expect_true(file.exists(paste0(f, ".shift_loading.csv")))
  loading_sidecar <- readr::read_csv(paste0(f, ".shift_loading.csv"),
                                     show_col_types = FALSE)
  expect_true(all(c("estimator", "inference", "estimand", "delta", "l_hat",
                    "n_calib_pairs") %in% names(loading_sidecar)))
})

test_that("N3: a failed atomic rename errors loudly and leaves the previous partial untouched", {
  f <- tempfile(fileext = ".csv")
  readr::write_csv(.build_hand_partial(), f)
  before <- readBin(f, "raw", file.info(f)$size)

  # Force file.rename(tmp_path, partial_path) to fail (simulating e.g. a
  # cross-filesystem rename or a permissions error) by shadowing
  # file.rename() in globalenv() -- the environment .shift_synthesize_
  # partial() itself was defined in (this framework is source()'d flat,
  # never installed as a package, so unqualified calls inside it resolve
  # through globalenv() before reaching base::file.rename). This exercises
  # the exact failure mode the N3 return-value check exists to catch,
  # without depending on a platform-specific filesystem trick.
  assign("file.rename", function(from, to) FALSE, envir = globalenv())
  on.exit(rm("file.rename", envir = globalenv()), add = TRUE)

  expect_error(.shift_synthesize_partial(f),
              "atomic rename of the synthesized partial failed")

  # The previous partial must be BYTE-IDENTICAL to before the call: the
  # write went to a .tmp sibling, never to `f` itself, so a failed rename
  # can only ever leave `f` exactly as it was.
  after <- readBin(f, "raw", file.info(f)$size)
  expect_identical(before, after)
  # on.exit() inside .shift_synthesize_partial() must have removed the
  # orphaned .tmp file despite the error (see BLOCKER 3 -- N3's second
  # requirement: no leftover full-size .tmp beside a multi-GB partial).
  expect_false(file.exists(paste0(f, ".tmp")))
})

test_that("shift_calibration_reps edge values are rejected", {
  cfg_lo <- .write_yaml_shift(c(
    "level: state", "sample: [S2]", "covid: keep",
    "treat_def: online_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    "estimators: [twfe]", "effect_grid: [0, 0.05]",
    "n_reps: 5", "base_seed: 123", "min_pre: 12", "min_post: 6",
    "shift_mode: true", "shift_calibration_reps: 1"
  ))
  rn1 <- paste0("_test_shift_edge_lo_", format(Sys.time(), "%H%M%OS3"))
  on.exit(unlink(.power_out_dir(rn1), recursive = TRUE), add = TRUE)
  expect_error(
    run_scenario_grid(cfg_lo, resume = FALSE, workers = 1, run_name = rn1,
                      impose_fn = mock_impose_effect,
                      estimator_fn = mock_run_estimator),
    "must be >= 2"
  )

  cfg_hi <- .write_yaml_shift(c(
    "level: state", "sample: [S2]", "covid: keep",
    "treat_def: online_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    "estimators: [twfe]", "effect_grid: [0, 0.05]",
    "n_reps: 5", "base_seed: 123", "min_pre: 12", "min_post: 6",
    "shift_mode: true", "shift_calibration_reps: 5"
  ))
  rn2 <- paste0("_test_shift_edge_hi_", format(Sys.time(), "%H%M%OS3"))
  on.exit(unlink(.power_out_dir(rn2), recursive = TRUE), add = TRUE)
  expect_error(
    run_scenario_grid(cfg_hi, resume = FALSE, workers = 1, run_name = rn2,
                      impose_fn = mock_impose_effect,
                      estimator_fn = mock_run_estimator),
    "must be < the scenario's max rep count"
  )
})

test_that("n_reps_override rescales shift_calibration_reps", {
  cfg_path <- .write_yaml_shift(c(
    "level: state", "sample: [S2]", "covid: keep",
    "treat_def: online_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    "estimators: [twfe]", "effect_grid: [0, 0.05]",
    "n_reps: 500", "base_seed: 123", "min_pre: 12", "min_post: 6",
    "shift_mode: true"   # default calibration_reps = max(10, ceil(50)) = 50
  ))
  cfg <- read_power_config(cfg_path)
  grid <- expand_scenario_grid(cfg)
  expect_equal(grid$shift_calibration_reps[1], 50L)

  rn <- paste0("_test_shift_override_", format(Sys.time(), "%H%M%OS3"))
  on.exit(unlink(.power_out_dir(rn), recursive = TRUE), add = TRUE)
  # A smoke override to n_reps = 4: the stale calibration count of 50 would
  # violate "< max rep count" and previously left every rep uncalibrated
  # relative to a huge denominator -- it must be rescaled, not carried over.
  r <- run_scenario_grid(cfg_path, resume = FALSE, workers = 1, run_name = rn,
                         impose_fn = mock_impose_effect,
                         estimator_fn = mock_run_estimator,
                         n_reps_override = 4L, batch_size = 4L)
  expect_true(all(r$results$rep <= 4L))
  expect_false(any(!is.na(r$results$error_msg) &
                     r$results$error_msg == "shift_pending"))
})
