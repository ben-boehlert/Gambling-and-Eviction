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

# ---------------------------------------------------------------------------
# lpdid_wild plumbing (2026-08-19): config key -> grid column -> spec, hashed
# into the scenario id ONLY when TRUE and only for lpdid-bearing scenarios
# (same conditional-hash principle as cs_safe_patches / cs_faster_mode).
# ---------------------------------------------------------------------------

test_that("lpdid_wild defaults FALSE and leaves every id unchanged", {
  base <- .write_yaml(c(
    "level: state", "sample: [S2]", "covid: keep",
    "treat_def: online_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    "estimators: [twfe, lpdid]", "effect_grid: [0, 0.05]",
    "n_reps: 2", "base_seed: 123", "min_pre: 12", "min_post: 6"
  ))
  flag <- .write_yaml(c(
    "level: state", "sample: [S2]", "covid: keep",
    "treat_def: online_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    "estimators: [twfe, lpdid]", "effect_grid: [0, 0.05]",
    "n_reps: 2", "base_seed: 123", "min_pre: 12", "min_post: 6",
    "lpdid_wild: true"
  ))
  g0 <- expand_scenario_grid(read_power_config(base))
  g1 <- expand_scenario_grid(read_power_config(flag))
  expect_false(isTRUE(g0$lpdid_wild[1]))
  expect_true(isTRUE(g1$lpdid_wild[1]))
  # TRUE moves the id of an lpdid-bearing scenario ...
  expect_false(identical(g0$scenario_id, g1$scenario_id))

  # ... but never moves a scenario with no lpdid.
  base_no <- .write_yaml(c(
    "level: state", "sample: [S2]", "covid: keep",
    "treat_def: online_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    "estimators: [twfe, did2s]", "effect_grid: [0, 0.05]",
    "n_reps: 2", "base_seed: 123", "min_pre: 12", "min_post: 6"
  ))
  flag_no <- .write_yaml(c(
    "level: state", "sample: [S2]", "covid: keep",
    "treat_def: online_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    "estimators: [twfe, did2s]", "effect_grid: [0, 0.05]",
    "n_reps: 2", "base_seed: 123", "min_pre: 12", "min_post: 6",
    "lpdid_wild: true"
  ))
  expect_identical(
    expand_scenario_grid(read_power_config(base_no))$scenario_id,
    expand_scenario_grid(read_power_config(flag_no))$scenario_id)
})

test_that("lpdid_wild reaches the estimator spec through run_one_rep", {
  seen <- new.env(parent = emptyenv()); seen$vals <- logical(0)
  spy_estimator <- function(panel_sim, estimator = "lpdid", spec = list()) {
    seen$vals <- c(seen$vals, isTRUE(spec$lpdid_wild))
    mock_run_estimator(panel_sim, estimator, spec)
  }
  cfgp <- .write_yaml(c(
    "level: state", "sample: [S2]", "covid: keep",
    "treat_def: online_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    "estimators: [lpdid]", "effect_grid: [0]",
    "n_reps: 1", "base_seed: 123", "min_pre: 12", "min_post: 6",
    "lpdid_wild: true"
  ))
  rn <- "_test_lpdid_wild_spec"
  on.exit(unlink(.power_out_dir(rn), recursive = TRUE), add = TRUE)
  run_scenario_grid(cfgp, resume = FALSE, workers = 1, run_name = rn,
                    impose_fn = mock_impose_effect,
                    estimator_fn = spy_estimator)
  expect_true(length(seen$vals) > 0L && all(seen$vals))
})

test_that("event_clean is the hashed LP-DiD default and legacy event is reproducible", {
  mk <- function(extra = character(), estimators = "[lpdid]") .write_yaml(c(
    "level: state", "sample: [S2]", "covid: keep",
    "treat_def: ramp75_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    paste0("estimators: ", estimators), "effect_grid: [0]",
    "n_reps: 1", "base_seed: 123", "min_pre: 12", "min_post: 6",
    extra
  ))

  g_default <- expand_scenario_grid(read_power_config(mk()))
  g_clean <- expand_scenario_grid(read_power_config(
    mk("lpdid_anchor: event_clean")))
  g_legacy <- expand_scenario_grid(read_power_config(
    mk("lpdid_anchor: event")))

  expect_identical(g_default$lpdid_anchor, "event_clean")
  expect_identical(g_default$scenario_id, g_clean$scenario_id)
  expect_false(identical(g_clean$scenario_id, g_legacy$scenario_id))

  # An LP-only setting never changes the identity of a scenario without LP.
  no_lp_default <- expand_scenario_grid(read_power_config(
    mk(estimators = "[twfe]")))
  no_lp_legacy <- expand_scenario_grid(read_power_config(
    mk("lpdid_anchor: event", estimators = "[twfe]")))
  expect_identical(no_lp_default$scenario_id, no_lp_legacy$scenario_id)
})

# ---------------------------------------------------------------------------
# exclude_states scenario axis (2026-08-19, dose-tercile subdesigns): states
# listed are dropped from the panel BEFORE schedule/template derivation, so
# they are neither treated-template members nor controls. Hashed into the
# scenario id only when non-empty.
# ---------------------------------------------------------------------------

test_that("exclude_states: empty leaves ids unchanged, non-empty moves them", {
  base <- .write_yaml(c(
    "level: state", "sample: [S2]", "covid: keep",
    "treat_def: online_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    "estimators: [twfe]", "effect_grid: [0, 0.05]",
    "n_reps: 2", "base_seed: 123", "min_pre: 12", "min_post: 6"
  ))
  ex <- .write_yaml(c(
    "level: state", "sample: [S2]", "covid: keep",
    "treat_def: online_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    "estimators: [twfe]", "effect_grid: [0, 0.05]",
    "n_reps: 2", "base_seed: 123", "min_pre: 12", "min_post: 6",
    "exclude_states: [TX, UT]"
  ))
  g0 <- expand_scenario_grid(read_power_config(base))
  g1 <- expand_scenario_grid(read_power_config(ex))
  expect_identical(g0$exclude_states[[1]], character(0))
  expect_identical(g1$exclude_states[[1]], c("TX", "UT"))
  expect_false(identical(g0$scenario_id, g1$scenario_id))
})

test_that("exclude_states drops the states from the simulated panel", {
  # Excluding a never-treated state must reduce the mock estimator's control
  # cluster count by one, leaving treated clusters untouched.
  mk <- function(extra = character(0)) .write_yaml(c(
    "level: state", "sample: [S2]", "covid: keep",
    "treat_def: online_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    "estimators: [twfe]", "effect_grid: [0]",
    "n_reps: 2", "base_seed: 123", "min_pre: 12", "min_post: 6", extra
  ))
  rn0 <- "_test_exstates_base"; rn1 <- "_test_exstates_drop"
  on.exit({
    unlink(.power_out_dir(rn0), recursive = TRUE)
    unlink(.power_out_dir(rn1), recursive = TRUE)
  }, add = TRUE)
  r0 <- run_scenario_grid(mk(), resume = FALSE, workers = 1, run_name = rn0,
                          impose_fn = mock_impose_effect,
                          estimator_fn = mock_run_estimator)
  # TX is never-treated in the real schedule and present in the state panel.
  r1 <- run_scenario_grid(mk("exclude_states: [TX]"), resume = FALSE,
                          workers = 1, run_name = rn1,
                          impose_fn = mock_impose_effect,
                          estimator_fn = mock_run_estimator)
  n0 <- r0$results$n_control_clusters[1]
  n1 <- r1$results$n_control_clusters[1]
  expect_identical(n1, n0 - 1L)
  expect_identical(r1$results$n_treated_clusters[1],
                   r0$results$n_treated_clusters[1])
})

# ---------------------------------------------------------------------------
# time_agg / complete_periods_only axes (2026-08-19): id stability for month
# and quarter, new ids for year and for the complete-periods rule.
# ---------------------------------------------------------------------------

test_that("time_agg id stability: month/quarter keep ids, year moves them", {
  mk <- function(extra = character(0)) .write_yaml(c(
    "level: state", "sample: [S2]", "covid: drop",
    "treat_def: online_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    "estimators: [twfe]", "effect_grid: [0, 0.05]",
    "n_reps: 2", "base_seed: 123", "min_pre: 12", "min_post: 6", extra
  ))
  g_month  <- expand_scenario_grid(read_power_config(mk()))
  g_explicit_month <- expand_scenario_grid(read_power_config(mk('time_agg: month')))
  g_legacy <- expand_scenario_grid(read_power_config(mk("quarterly: true")))
  g_quart  <- expand_scenario_grid(read_power_config(mk('time_agg: quarter')))
  g_year   <- expand_scenario_grid(read_power_config(mk('time_agg: year')))

  # Explicitly naming the default must not move an id.
  expect_identical(g_month$scenario_id, g_explicit_month$scenario_id)
  # The legacy boolean and the new axis describe the SAME design -> same id.
  expect_identical(g_legacy$scenario_id, g_quart$scenario_id)
  expect_true(g_quart$quarterly[1])
  expect_identical(g_quart$time_agg[1], "quarter")
  # Year is a genuinely new design.
  expect_false(identical(g_month$scenario_id, g_year$scenario_id))
  expect_false(g_year$quarterly[1])

  # complete_periods_only is hashed only when TRUE.
  g_cp <- expand_scenario_grid(read_power_config(mk("complete_periods_only: true")))
  expect_false(identical(g_month$scenario_id, g_cp$scenario_id))
  expect_identical(
    expand_scenario_grid(read_power_config(mk("complete_periods_only: false")))$scenario_id,
    g_month$scenario_id)
})

test_that("time_agg='year' reaches the loader and shrinks the simulated panel", {
  seen <- new.env(parent = emptyenv()); seen$n_periods <- integer(0)
  spy_impose <- function(panel, schedule, ...) {
    seen$n_periods <- c(seen$n_periods, dplyr::n_distinct(panel$month_date))
    mock_impose_effect(panel, schedule, ...)
  }
  # S2 + panel template: D1 x S3 is structurally infeasible (design doc §8
  # addendum), which would fail every rep before the injector is ever called.
  mk <- function(extra) .write_yaml(c(
    "level: state", "sample: [S2]", "covid: keep",
    "treat_def: online_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    "template: panel",
    "estimators: [twfe]", "effect_grid: [0]",
    "n_reps: 1", "base_seed: 123", "min_pre: 12", "min_post: 6", extra
  ))
  rn <- "_test_timeagg_year"
  on.exit(unlink(.power_out_dir(rn), recursive = TRUE), add = TRUE)
  run_scenario_grid(mk('time_agg: year'), resume = FALSE, workers = 1,
                    run_name = rn, impose_fn = spy_impose,
                    estimator_fn = mock_run_estimator)
  # A 2016..2025 annual panel has ~10 periods, far fewer than ~100 months.
  expect_true(length(seen$n_periods) > 0L)
  expect_lt(max(seen$n_periods), 15L)
})


test_that("lpdid_unit_weights: none leaves ids unchanged, renters moves them and reaches the spec", {
  mk <- function(extra = character(0)) .write_yaml(c(
    "level: state", "sample: [S2]", "covid: keep",
    "treat_def: online_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    "estimators: [twfe, lpdid]", "effect_grid: [0]",
    "n_reps: 1", "base_seed: 123", "min_pre: 12", "min_post: 6", extra))
  g0 <- expand_scenario_grid(read_power_config(mk()))
  gn <- expand_scenario_grid(read_power_config(mk("lpdid_unit_weights: none")))
  gr <- expand_scenario_grid(read_power_config(mk("lpdid_unit_weights: renters")))
  expect_identical(g0$lpdid_unit_weights[1], "none")
  expect_identical(g0$scenario_id, gn$scenario_id)
  expect_false(identical(g0$scenario_id, gr$scenario_id))

  seen <- new.env(parent = emptyenv()); seen$vals <- character(0)
  spy_estimator <- function(panel_sim, estimator = "lpdid", spec = list()) {
    seen$vals <- c(seen$vals, as.character(spec$lpdid_unit_weights %||% "<missing>"))
    mock_run_estimator(panel_sim, estimator, spec)
  }
  rn <- "_test_lpdid_unit_weights_spec"
  on.exit(unlink(.power_out_dir(rn), recursive = TRUE), add = TRUE)
  run_scenario_grid(mk("lpdid_unit_weights: renters"), resume = FALSE, workers = 1,
                    run_name = rn, impose_fn = mock_impose_effect,
                    estimator_fn = spy_estimator)
  expect_true(length(seen$vals) > 0L && all(seen$vals == "renters"))
})

test_that("inclusion-rule knobs: defaults keep ids, presence/min_horizons/buffer move them", {
  mk <- function(extra = character(0)) .write_yaml(c(
    "level: state", "sample: [S2]", "covid: keep",
    "treat_def: online_start_date", "designs: [D1]",
    "mechanisms: [deterministic]", "shapes: [step]",
    "estimators: [twfe, lpdid]", "effect_grid: [0]",
    "n_reps: 1", "base_seed: 123", "min_pre: 12", "min_post: 6", extra))
  g0 <- expand_scenario_grid(read_power_config(mk()))
  gd <- expand_scenario_grid(read_power_config(mk(c("eligibility: span", "splice_buffer_months: 0"))))
  gp <- expand_scenario_grid(read_power_config(mk("eligibility: presence")))
  gk <- expand_scenario_grid(read_power_config(mk("min_horizons: 7")))
  gb <- expand_scenario_grid(read_power_config(mk("splice_buffer_months: 3")))
  expect_identical(g0$scenario_id, gd$scenario_id)
  expect_false(identical(g0$scenario_id, gp$scenario_id))
  expect_false(identical(g0$scenario_id, gk$scenario_id))
  expect_false(identical(g0$scenario_id, gb$scenario_id))
  expect_identical(g0$eligibility[1], "span"); expect_true(is.na(g0$min_horizons[1]))
  expect_equal(g0$splice_buffer_months[1], 0L)
})
