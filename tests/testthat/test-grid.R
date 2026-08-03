################################################################################
# test-grid.R
#
# Scenario-grid mechanics: config expansion counts, deterministic scenario
# ids and seeds, resume-skips-complete-partials, and serial == parallel
# results. Uses the clearly-named mocks from helper-mocks.R (the sibling
# modules impose_effects.R / run_estimators.R may not exist yet) via the
# impose_fn / estimator_fn test hooks — the real modules are never shadowed.
################################################################################

library(lubridate)

# ---- Inline configs written to temp files -----------------------------------

.write_yaml <- function(lines) {
  f <- tempfile(fileext = ".yml")
  writeLines(lines, f)
  f
}

.cfg_blocks_path <- .write_yaml(c(
  "level: state",
  "sample: [S2]",
  "covid: keep",
  "treat_def: online_start_date",
  "designs: [D1]",
  "mechanisms: [deterministic]",
  "shapes: [step]",
  "estimators: [twfe]",
  "effect_grid: [0, 0.05]",
  "n_reps: 2",
  "base_seed: 123",
  "min_pre: 12",
  "min_post: 6",
  "scenarios:",
  "  - name: a",
  "    sample: [S2, S3]",
  "    shapes: [step, ramp]",
  "  - name: b"
))

.cfg_flat_path <- .write_yaml(c(
  "level: state",
  "sample: [S2]",
  "covid: keep",
  "treat_def: online_start_date",
  "designs: [D1]",
  "mechanisms: [deterministic]",
  "shapes: [step]",
  "estimators: [twfe]",
  "effect_grid: [0, 0.05]",
  "n_reps: 2",
  "base_seed: 123",
  "min_pre: 12",
  "min_post: 6",
  "mde_boot: 20"
))

test_that("config expansion produces the expected scenario count and defaults", {
  cfg <- read_power_config(.cfg_blocks_path)
  grid <- expand_scenario_grid(cfg)
  # Block a: 2 samples x 2 shapes = 4; block b: inherits defaults = 1.
  expect_equal(nrow(grid), 5L)
  expect_equal(sum(grid$name == "a"), 4L)
  expect_equal(sum(grid$name == "b"), 1L)
  # Block b inherits every top-level default.
  b <- grid[grid$name == "b", ]
  expect_equal(b$sample, "S2")
  expect_equal(b$shape, "step")
  expect_equal(b$design, "D1")
  expect_equal(b$mechanism, "deterministic")
  expect_equal(b$outcome, "y_log1p")
  expect_equal(b$control_group, "notyettreated")
  expect_false(b$quarterly)
  expect_equal(b$estimators[[1]], "twfe")
  expect_equal(b$effect_grid[[1]], c(0, 0.05))
  expect_equal(b$n_reps, 2L)
})

test_that("scenario ids are deterministic and unique", {
  cfg <- read_power_config(.cfg_blocks_path)
  g1 <- expand_scenario_grid(cfg)
  g2 <- expand_scenario_grid(cfg)
  expect_identical(g1$scenario_id, g2$scenario_id)
  expect_equal(anyDuplicated(g1$scenario_id), 0L)
  # Content-addressed: "S" + 10 hex digits + slug (never a positional index).
  expect_true(all(grepl("^S[0-9a-f]{10}_", g1$scenario_id)))
})

# Reordering the scenarios list must leave every scenario's id AND seed
# offset untouched — that is what makes `resume` sound across config edits.
.cfg_blocks_reordered_path <- .write_yaml(c(
  "level: state",
  "sample: [S2]",
  "covid: keep",
  "treat_def: online_start_date",
  "designs: [D1]",
  "mechanisms: [deterministic]",
  "shapes: [step]",
  "estimators: [twfe]",
  "effect_grid: [0, 0.05]",
  "n_reps: 2",
  "base_seed: 123",
  "min_pre: 12",
  "min_post: 6",
  "scenarios:",
  "  - name: b",
  "  - name: a",
  "    sample: [S2, S3]",
  "    shapes: [step, ramp]"
))

test_that("scenario ids and seeds are invariant to config ordering", {
  g1 <- expand_scenario_grid(read_power_config(.cfg_blocks_path))
  g2 <- expand_scenario_grid(read_power_config(.cfg_blocks_reordered_path))

  key <- function(g) {
    o <- order(g$scenario_id)
    g[o, c("scenario_id", "scenario_seed_offset", "name", "sample", "shape")]
  }
  expect_equal(as.data.frame(key(g1)), as.data.frame(key(g2)))

  # Positions did move — so this is a real reorder, not a no-op config.
  expect_false(identical(g1$scenario_id, g2$scenario_id))
})

test_that("scenario id changes when a hashed input changes", {
  cfg  <- read_power_config(.cfg_blocks_path)
  base <- expand_scenario_grid(cfg)

  cfg_reps <- cfg; cfg_reps$n_reps <- 7L
  cfg_seed <- cfg; cfg_seed$base_seed <- 999L
  cfg_grid <- cfg; cfg_grid$effect_grid <- c(0, 0.05, 0.10)

  for (alt in list(cfg_reps, cfg_seed, cfg_grid)) {
    expect_false(any(expand_scenario_grid(alt)$scenario_id %in%
                       base$scenario_id))
  }
})

test_that("seed offsets stay inside the collision-free band", {
  g <- expand_scenario_grid(read_power_config(.cfg_blocks_path))
  expect_true(all(g$scenario_seed_offset >= 0L))
  expect_true(all(g$scenario_seed_offset < 10007L))
  expect_type(g$scenario_seed_offset, "integer")
})

test_that(".select_scenarios resolves indices, ids, and block names", {
  g <- expand_scenario_grid(read_power_config(.cfg_blocks_path))

  expect_equal(nrow(.select_scenarios(g, NULL)), nrow(g))
  expect_equal(.select_scenarios(g, 2L)$scenario_id, g$scenario_id[2])
  expect_equal(nrow(.select_scenarios(g, c(1L, 3L))), 2L)
  # A block name selects every scenario the block expands to.
  expect_equal(nrow(.select_scenarios(g, "a")), 4L)
  expect_equal(nrow(.select_scenarios(g, "b")), 1L)
  expect_equal(.select_scenarios(g, g$scenario_id[3])$scenario_id,
               g$scenario_id[3])

  expect_error(.select_scenarios(g, 99L), "out of range")
  expect_error(.select_scenarios(g, "nope"), "no scenario matches")
  expect_error(.select_scenarios(g, integer(0)), "empty")
})

test_that("per-rep seeds are deterministic and distinct across reps/scenarios", {
  expect_identical(power_rep_seed(100, 2, 3), 100L + 10007L * 2L + 101L * 3L)
  expect_identical(power_rep_seed(100, 2, 3), power_rep_seed(100, 2, 3))
  seeds <- as.vector(outer(1:50, 1:20,
                           function(r, s) power_rep_seed(20260723, r, s)))
  expect_equal(anyDuplicated(seeds), 0L)
})

# ---- Runner tests (mock modules, tiny flat config) --------------------------

.run_cols_equal <- function(r1, r2) {
  key_cols <- c("scenario_id", "rep", "delta", "estimator", "estimand",
                "att", "se", "p", "truth", "seed_rep")
  a <- r1$results[, key_cols] %>% dplyr::arrange(rep, delta)
  b <- r2$results[, key_cols] %>% dplyr::arrange(rep, delta)
  expect_equal(as.data.frame(a), as.data.frame(b))
}

test_that("run_scenario_grid runs end-to-end with mocks and writes outputs", {
  rn <- paste0("_test_grid_serial_", format(Sys.time(), "%H%M%S"))
  on.exit(unlink(.power_out_dir(rn), recursive = TRUE), add = TRUE)

  r1 <- run_scenario_grid(.cfg_flat_path, resume = FALSE, workers = 1,
                          run_name = rn,
                          impose_fn = mock_impose_effect,
                          estimator_fn = mock_run_estimator,
                          batch_size = 1L)
  # 1 scenario x 2 reps x 2 deltas x 1 estimator, one overall row each.
  expect_equal(nrow(r1$results), 4L)
  expect_true(all(r1$results$converged))
  # Deterministic step injection: truth equals the nominal delta exactly.
  expect_equal(sort(unique(r1$results$truth)), c(0, 0.05))
  expect_equal(r1$results$truth[r1$results$delta == 0.05], c(0.05, 0.05))
  # Output files land under output_blinded_power/<run>/.
  for (f in c("results_raw.csv.gz", "oc_summary.csv", "mde_table.csv",
              "pretrend_summary.csv", "failures.csv", "scenario_truths.csv",
              "run_metadata.json")) {
    expect_true(file.exists(file.path(r1$out_dir, f)), info = f)
  }
  # OC table has one row per delta with the full rep count.
  expect_equal(nrow(r1$oc), 2L)
  expect_equal(unique(r1$oc$n_reps), 2L)
})

test_that("serial (workers = 1) and parallel (workers = 2) results are identical", {
  rn1 <- paste0("_test_grid_s_", format(Sys.time(), "%H%M%S"))
  rn2 <- paste0("_test_grid_p_", format(Sys.time(), "%H%M%S"))
  on.exit({
    unlink(.power_out_dir(rn1), recursive = TRUE)
    unlink(.power_out_dir(rn2), recursive = TRUE)
  }, add = TRUE)

  r1 <- run_scenario_grid(.cfg_flat_path, resume = FALSE, workers = 1,
                          run_name = rn1, impose_fn = mock_impose_effect,
                          estimator_fn = mock_run_estimator)
  r2 <- run_scenario_grid(.cfg_flat_path, resume = FALSE, workers = 2,
                          run_name = rn2, impose_fn = mock_impose_effect,
                          estimator_fn = mock_run_estimator)
  # Per-rep seeds are set explicitly inside the rep worker, so parallel
  # scheduling cannot change the draws.
  .run_cols_equal(r1, r2)
})

test_that("resume = TRUE skips scenarios whose partial is complete", {
  cfg <- read_power_config(.cfg_flat_path)
  grid <- expand_scenario_grid(cfg)
  sid <- grid$scenario_id[1]
  rn <- paste0("_test_grid_resume_", format(Sys.time(), "%H%M%S"))
  on.exit(unlink(.power_out_dir(rn), recursive = TRUE), add = TRUE)

  # Fake COMPLETE partial: all expected estimator x rep x delta combos
  # present, with a sentinel att value that the mocks could never produce.
  fake <- tidyr::expand_grid(rep = 1:2, delta = c(0, 0.05)) %>%
    dplyr::mutate(
      scenario_id = sid, scenario_index = 1L, name = "default",
      level = "state", sample = "S2", covid = "keep",
      treat_def = "online_start_date", design = "D1",
      mechanism = "deterministic", shape = "step", outcome = "y_log1p",
      est_anticipation = 0L, loader_anticipation = 6L,
      control_group = "notyettreated", quarterly = FALSE,
      estimator = "twfe", inference = "analytic", estimand = "overall",
      event_time = NA_real_, att = 999, se = 1, p = 0.5,
      ci_lo = 998, ci_hi = 1000, n_treated_clusters = 5L,
      n_control_clusters = 5L, converged = TRUE, error_msg = NA_character_,
      runtime_s = 0.01, truth = delta,
      seed_rep = power_rep_seed(123, rep, 1L)
    )
  partial_path <- .power_out_file(rn, "partials", paste0(sid, ".csv"))
  readr::write_csv(fake, partial_path)

  r <- run_scenario_grid(.cfg_flat_path, resume = TRUE, workers = 1,
                         run_name = rn, impose_fn = mock_impose_effect,
                         estimator_fn = mock_run_estimator)
  # The scenario was NOT recomputed: the sentinel rows survive.
  expect_equal(nrow(r$results), 4L)
  expect_true(all(r$results$att == 999))

  # With resume = FALSE the same partial is overwritten by real mock runs.
  r_fresh <- run_scenario_grid(.cfg_flat_path, resume = FALSE, workers = 1,
                               run_name = rn, impose_fn = mock_impose_effect,
                               estimator_fn = mock_run_estimator)
  expect_false(any(r_fresh$results$att == 999))
})

# ---- Subset runs (the SLURM-array workflow) ---------------------------------

# Multi-scenario but S2-only: sample S3 has no feasible D1 template placement
# on the real blinded panel, so .cfg_blocks_path cannot actually be RUN (it
# exists to exercise expansion arithmetic only). Blocks here differ on `shape`,
# which varies the scenario without changing the panel.
.cfg_subset_path <- .write_yaml(c(
  "level: state",
  "sample: [S2]",
  "covid: keep",
  "treat_def: online_start_date",
  "designs: [D1]",
  "mechanisms: [deterministic]",
  "shapes: [step]",
  "estimators: [twfe]",
  "effect_grid: [0, 0.05]",
  "n_reps: 2",
  "base_seed: 123",
  "min_pre: 12",
  "min_post: 6",
  "mde_boot: 20",
  "scenarios:",
  "  - name: a",
  "    shapes: [step, ramp]",
  "  - name: b"
))

test_that("a subset run writes only partials, and a later full run aggregates", {
  rn <- paste0("_test_grid_subset_", format(Sys.time(), "%H%M%S"))
  on.exit(unlink(.power_out_dir(rn), recursive = TRUE), add = TRUE)

  grid <- expand_scenario_grid(read_power_config(.cfg_subset_path))
  expect_equal(nrow(grid), 3L)
  run_level <- c("results_raw.csv.gz", "oc_summary.csv", "mde_table.csv",
                 "pretrend_summary.csv", "failures.csv",
                 "scenario_truths.csv", "run_metadata.json")

  # Each "array task" runs one scenario by index.
  for (i in seq_len(nrow(grid))) {
    ri <- run_scenario_grid(.cfg_subset_path, resume = TRUE, workers = 1,
                            run_name = rn, scenarios = i,
                            impose_fn = mock_impose_effect,
                            estimator_fn = mock_run_estimator)
    expect_equal(nrow(ri$grid), 1L)
    expect_null(ri$results)   # subset runs do not summarize
    expect_true(file.exists(
      .power_out_file(rn, "partials", paste0(grid$scenario_id[i], ".csv"))))
  }

  # No run-level file was written by any task, so they cannot have raced.
  for (f in run_level) {
    expect_false(file.exists(file.path(.power_out_dir(rn), f)), info = f)
  }

  # The epilogue pass finds every partial complete and only summarizes.
  agg <- run_scenario_grid(.cfg_subset_path, resume = TRUE, workers = 1,
                           run_name = rn,
                           impose_fn = mock_impose_effect,
                           estimator_fn = mock_run_estimator)
  for (f in run_level) {
    expect_true(file.exists(file.path(agg$out_dir, f)), info = f)
  }
  # 3 scenarios x 2 reps x 2 deltas x 1 estimator.
  expect_equal(nrow(agg$results), 12L)
  expect_equal(dplyr::n_distinct(agg$results$scenario_id), 3L)
})

test_that("subset selection by block name matches selection by index", {
  rn <- paste0("_test_grid_subsetname_", format(Sys.time(), "%H%M%S"))
  on.exit(unlink(.power_out_dir(rn), recursive = TRUE), add = TRUE)

  grid <- expand_scenario_grid(read_power_config(.cfg_subset_path))
  b_idx <- which(grid$name == "b")

  r <- run_scenario_grid(.cfg_subset_path, resume = FALSE, workers = 1,
                         run_name = rn, scenarios = "b",
                         impose_fn = mock_impose_effect,
                         estimator_fn = mock_run_estimator)
  expect_equal(r$grid$scenario_id, grid$scenario_id[b_idx])
})
