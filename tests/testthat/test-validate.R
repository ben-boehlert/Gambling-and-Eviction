################################################################################
# test-validate.R
#
# validate_simulation() mechanics with the contract mocks (report + results
# written to a guarded path, checks tibble returned), plus a real-module
# smoke test that is skipped while R/power/impose_effects.R /
# run_estimators.R are still being written by the sibling agent.
################################################################################

test_that("validate_simulation runs with mocks and writes report + results", {
  out_dir <- .power_out_dir("_test_validation")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  v <- validate_simulation(n_reps = 4L, seed = 999,
                           out_dir = out_dir,
                           effect_grid = c(0, 0.10, 0.20),
                           impose_fn = mock_impose_effect,
                           estimator_fn = mock_run_estimator)

  expect_type(v$pass, "logical")
  expect_s3_class(v$checks, "tbl_df")
  expect_true(all(c("check", "pass", "detail") %in% names(v$checks)))
  expect_true(all(c("assert_blinded_on_loaded_panel",
                    "forbidden_path_guard_blocks_output",
                    "zero_delta_leaves_outcomes_identical",
                    "count_augmentation_nonnegative_integer",
                    "same_seed_identical_injection",
                    "size_at_null_within_bounds",
                    "power_monotone_nondecreasing",
                    "mde_finite_if_power_crosses_80") %in% v$checks$check))
  expect_true(file.exists(file.path(out_dir, "validation_report.md")))
  expect_true(file.exists(file.path(out_dir, "validation_results.csv")))
  # 4 reps x 3 grid points, one overall row each.
  expect_equal(nrow(v$results), 12L)
  expect_equal(nrow(v$power_curve), 3L)
  # The mock injection honors the blindness/injection invariants, so those
  # specific checks must pass regardless of the (noisy, 4-rep) power checks.
  inv <- v$checks[v$checks$check %in%
                    c("assert_blinded_on_loaded_panel",
                      "forbidden_path_guard_blocks_output",
                      "zero_delta_leaves_outcomes_identical",
                      "count_augmentation_nonnegative_integer",
                      "same_seed_identical_injection",
                      "pseudo_treatment_constant_within_state"), ]
  expect_true(all(inv$pass))
})

test_that("validate_simulation rejects an out_dir outside output_blinded_power", {
  expect_error(
    validate_simulation(n_reps = 1L, out_dir = tempfile("elsewhere_"),
                        impose_fn = mock_impose_effect,
                        estimator_fn = mock_run_estimator),
    "Blindness violation"
  )
})

test_that("validate_simulation runs against the real sibling modules", {
  skip_if(!power_sim_modules_present(),
          "R/power/impose_effects.R / run_estimators.R not written yet")
  out_dir <- .power_out_dir("_test_validation_real")
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)
  v <- validate_simulation(n_reps = 3L, seed = 20260723,
                           out_dir = out_dir,
                           effect_grid = c(0, 0.10))
  expect_type(v$pass, "logical")
  expect_true(file.exists(file.path(out_dir, "validation_report.md")))
})
