################################################################################
# R/power/run_scenario_grid.R
#
# Scenario-grid orchestration for the blinded power-simulation framework
# (POWER_SIMULATION_DESIGN.md §11 execution, §16 module contract):
#
#   expand_scenario_grid(cfg)  — deterministic scenario table from a YAML config
#   power_rep_seed(...)        — deterministic per-rep seed
#   run_scenario_grid(config_path, resume, workers, ...) — batched, parallel,
#       resumable execution; writes results + OC summaries + metadata under
#       output_blinded_power/ only.
#
# Depends on the foundation modules (config, blindness_checks,
# load_blinded_panel, make_pseudo_schedules) and on
# summarize_operating_characteristics.R. The effect-injection and estimator
# modules (R/power/impose_effects.R, R/power/run_estimators.R) are sourced
# LAZILY at run time via .ensure_sim_functions(); unit tests may inject mock
# implementations through the impose_fn / estimator_fn arguments instead.
#
# Pinned sibling contracts coded against:
#   impose_effect(panel, schedule, mechanism, shape, delta, params = list(),
#                 outcome, seed) -> panel + columns e, delta_imposed,
#                 y_sim_count, y_sim (+ attrs).
#   run_estimator(panel_sim, estimator = c("cs","twfe","did2s","sunab"),
#                 spec = list()) -> tibble(estimator, inference, estimand,
#                 event_time, att, se, p, ci_lo, ci_hi, n_treated_clusters,
#                 n_control_clusters, converged, error_msg, runtime_s).
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(rlang)
  library(lubridate)
})

if (!exists("power_paths", mode = "function")) source("R/power/config.R")
if (!exists("assert_blinded", mode = "function")) source("R/power/blindness_checks.R")
if (!exists("load_blinded_panel", mode = "function")) source("R/power/load_blinded_panel.R")
if (!exists("make_pseudo_schedule", mode = "function")) source("R/power/make_pseudo_schedules.R")
if (!exists("summarize_oc", mode = "function")) {
  source("R/power/summarize_operating_characteristics.R")
}

# ---------------------------------------------------------------------------
# Output-path helpers: all writes resolve against the REPO-ROOT
# output_blinded_power/ regardless of the current working directory (testthat
# runs with wd = tests/testthat), via blinded_output_path()'s escape guard.
# ---------------------------------------------------------------------------

.power_out_root <- function() {
  file.path(power_repo_root(), power_paths()$output_root)
}

#' Guarded file path under output_blinded_power/ (parent dirs created)
#' @keywords internal
.power_out_file <- function(...) {
  blinded_output_path(..., root = .power_out_root(), create = TRUE)
}

#' Guarded directory path under output_blinded_power/ (dir created)
#' @keywords internal
.power_out_dir <- function(...) {
  d <- blinded_output_path(..., root = .power_out_root(), create = FALSE)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

# ---------------------------------------------------------------------------
# Lazy access to the sibling simulation modules
# ---------------------------------------------------------------------------

#' Resolve the effect-injection and estimator functions
#'
#' Test hooks first (explicit function arguments), then functions already
#' defined in the session, then a lazy source of the sibling modules. Errors
#' with a clear message when the modules have not been written yet.
#' @keywords internal
.ensure_sim_functions <- function(impose_fn = NULL, estimator_fn = NULL) {
  root <- power_repo_root()
  lazy_get <- function(fn_name, file_rel) {
    if (!exists(fn_name, mode = "function")) {
      f <- file.path(root, file_rel)
      if (!file.exists(f)) {
        stop(file_rel, " not found — the module defining ", fn_name, "() has ",
             "not been written yet. Either wait for it, or pass a mock via ",
             "the impose_fn / estimator_fn arguments.", call. = FALSE)
      }
      source(f)
    }
    get(fn_name, mode = "function")
  }
  if (is.null(impose_fn))    impose_fn    <- lazy_get("impose_effect", "R/power/impose_effects.R")
  if (is.null(estimator_fn)) estimator_fn <- lazy_get("run_estimator", "R/power/run_estimators.R")
  list(impose = impose_fn, estimate = estimator_fn)
}

# ---------------------------------------------------------------------------
# Seeds
# ---------------------------------------------------------------------------

#' Deterministic per-replication seed
#'
#' seed_rep = base_seed + 10007 * rep + 101 * scenario_index. 10007 and 101
#' are coprime, so seeds are distinct across (rep, scenario) for any grid of
#' realistic size (a collision needs |rep difference| to be a multiple of 101
#' AND |scenario difference| = 10007/101 * that — impossible below 10007
#' scenarios).
#'
#' @export
power_rep_seed <- function(base_seed, rep, scenario_index) {
  as.integer(base_seed) + 10007L * as.integer(rep) +
    101L * as.integer(scenario_index)
}

# ---------------------------------------------------------------------------
# Scenario expansion
# ---------------------------------------------------------------------------

# Crossed scenario axes with their config-level defaults. Names on the left
# are canonical; blocks may use the singular or plural key (see .axis_key_map).
.axis_key_map <- c(
  level = "level",
  sample = "sample", samples = "sample",
  covid = "covid",
  treat_def = "treat_def",
  design = "design", designs = "design",
  mechanism = "mechanism", mechanisms = "mechanism",
  shape = "shape", shapes = "shape",
  outcome = "outcome", outcomes = "outcome",
  # Estimator-side anticipation (CS `anticipation` argument, design §5 E1);
  # distinct from the loader's blindness-exclusion window below.
  est_anticipation = "est_anticipation", anticipation = "est_anticipation",
  # Loader-side anticipation-exclusion window A (protocol §4).
  loader_anticipation = "loader_anticipation",
  control_group = "control_group",
  quarterly = "quarterly"
)

.scenario_slug <- function(g) {
  s <- paste(g$name, g$level, g$sample, g$covid, g$design, g$mechanism,
             g$shape, g$outcome, paste0("a", g$est_anticipation), sep = "-")
  s <- paste0(s,
              ifelse(g$quarterly, "-q", ""),
              ifelse(g$control_group == "nevertreated", "-nt", ""))
  tolower(gsub("[^A-Za-z0-9_-]", "", s))
}

#' Expand a power config into a deterministic scenario table
#'
#' Supports two config styles:
#'   (a) an explicit \code{scenarios:} list of blocks — each block is a named
#'       scenario family whose own (possibly list-valued) axes are crossed,
#'       with unstated axes inherited from the top level. This is the intended
#'       style for power_primary.yml / power_sensitivity.yml (finite,
#'       deliberate candidate set rather than a full cartesian product).
#'   (b) a flat config with top-level axes only (power_validation.yml) —
#'       treated as a single block.
#'
#' Per-block execution settings (estimators, effect_grid, n_reps,
#' estimator_reps, min_pre, min_post) are NOT crossed; they are carried as
#' list-columns.
#'
#' scenario_id = zero-padded expansion index + slug; deterministic for a
#' given config file.
#'
#' @param cfg Parsed config from \code{read_power_config()}.
#' @return Tibble, one row per scenario.
#' @export
expand_scenario_grid <- function(cfg) {
  axis_defaults <- list(
    level               = cfg$level %||% "state",
    sample              = cfg$sample,
    covid               = cfg$covid %||% "drop",
    treat_def           = cfg$treat_def,
    design              = cfg$designs,
    mechanism           = cfg$mechanisms %||% "deterministic",
    shape               = cfg$shapes %||% "step",
    outcome             = cfg$outcomes %||% "y_log1p",
    est_anticipation    = cfg$est_anticipation %||% 0L,
    loader_anticipation = cfg$anticipation_months %||% 6L,
    control_group       = cfg$control_group %||% "notyettreated",
    quarterly           = cfg$quarterly %||% FALSE
  )

  blocks <- cfg$scenarios
  if (is.null(blocks)) blocks <- list(list(name = "default"))

  rows <- vector("list", length(blocks))
  for (b in seq_along(blocks)) {
    blk <- blocks[[b]]
    ax <- axis_defaults
    for (k in names(blk)) {
      if (k %in% names(.axis_key_map)) ax[[.axis_key_map[[k]]]] <- blk[[k]]
    }
    ax <- lapply(ax, unlist)

    g <- tibble::as_tibble(
      expand.grid(ax, stringsAsFactors = FALSE, KEEP.OUT.ATTRS = FALSE)
    )
    g$name <- blk$name %||% paste0("block", b)
    g$estimators  <- rep(list(unlist(blk$estimators %||% cfg$estimators)),
                         nrow(g))
    g$effect_grid <- rep(list(as.numeric(unlist(blk$effect_grid %||%
                                                  cfg$effect_grid))), nrow(g))
    g$n_reps   <- as.integer(blk$n_reps %||% cfg$n_reps)
    g$estimator_reps <- rep(list(blk$estimator_reps %||% cfg$estimator_reps),
                            nrow(g))
    g$min_pre  <- as.integer(blk$min_pre %||% cfg$min_pre %||% 12L)
    g$min_post <- as.integer(blk$min_post %||% cfg$min_post %||% 6L)
    rows[[b]] <- g
  }

  grid <- bind_rows(rows) %>%
    mutate(
      est_anticipation    = as.integer(.data$est_anticipation),
      loader_anticipation = as.integer(.data$loader_anticipation),
      quarterly           = as.logical(.data$quarterly)
    )
  grid$scenario_index <- seq_len(nrow(grid))
  grid$scenario_id    <- sprintf("S%03d_%s", grid$scenario_index,
                                 .scenario_slug(grid))
  grid
}

#' Per-estimator replication counts for a scenario
#' @keywords internal
.estimator_rep_counts <- function(estimators, n_reps, estimator_reps = NULL) {
  er <- stats::setNames(rep(as.integer(n_reps), length(estimators)), estimators)
  if (!is.null(estimator_reps)) {
    for (nm in intersect(names(estimator_reps), estimators)) {
      er[[nm]] <- as.integer(estimator_reps[[nm]])
    }
  }
  er
}

# ---------------------------------------------------------------------------
# Truth computation (design doc §1: truth is computed from the injection
# metadata every replication, never assumed equal to the nominal grid value)
# ---------------------------------------------------------------------------

#' Compute simulated truths per estimand from an injected panel
#'
#' Conventions (documented per design §1):
#'  - truth_overall: equal-weighted mean of delta_imposed over treated rows
#'    with e >= 0. For shape == "anticipation" the effect starts at
#'    e = -onset (default onset 3, design §9), so those anticipation rows
#'    (e >= -onset) are INCLUDED in truth_overall — the imposed effect is real
#'    in those cells and a correctly-anticipation-specified estimator targets
#'    them.
#'  - truth_event_0_12: mean of delta_imposed over treated rows with
#'    0 <= e <= 12.
#'  - truth_dynamic: mean of delta_imposed at each treated event time.
#' @keywords internal
.compute_truths <- function(sim, schedule, shape, params = list()) {
  onset <- if (identical(shape, "anticipation")) {
    as.integer(params$onset %||% 3L)
  } else 0L
  treated <- sim$state_abb %in% unique(schedule$state_abb) & !is.na(sim$e)

  ov  <- treated & sim$e >= -onset
  e12 <- treated & sim$e >= 0 & sim$e <= 12
  dyn <- sim[treated, c("e", "delta_imposed")] %>%
    group_by(.data$e) %>%
    summarise(truth = mean(.data$delta_imposed), .groups = "drop")

  list(
    overall    = if (any(ov)) mean(sim$delta_imposed[ov]) else NA_real_,
    event_0_12 = if (any(e12)) mean(sim$delta_imposed[e12]) else NA_real_,
    dynamic    = dyn
  )
}

#' Attach the estimand-appropriate truth to estimator result rows
#'
#' The overall aggregation is labeled "simple" by run_estimators.R (matching
#' CS aggte(type = "simple")); "overall" is accepted as a synonym.
#' @keywords internal
.attach_truth <- function(res, truths) {
  res$truth <- dplyr::case_when(
    res$estimand %in% c("overall", "simple") ~ truths$overall,
    res$estimand == "event_0_12"             ~ truths$event_0_12,
    TRUE                                     ~ NA_real_
  )
  dynr <- res$estimand == "dynamic" & !is.na(res$event_time)
  if (any(dynr)) {
    m <- match(res$event_time[dynr], truths$dynamic$e)
    res$truth[dynr] <- truths$dynamic$truth[m]
  }
  res
}

#' Contract-conforming failure row for an estimator that threw
#' @keywords internal
.estimator_failure_row <- function(estimator, msg) {
  tibble::tibble(
    estimator = estimator, inference = NA_character_, estimand = "overall",
    event_time = NA_real_, att = NA_real_, se = NA_real_, p = NA_real_,
    ci_lo = NA_real_, ci_hi = NA_real_,
    n_treated_clusters = NA_integer_, n_control_clusters = NA_integer_,
    converged = FALSE, error_msg = as.character(msg), runtime_s = NA_real_
  )
}

# ---------------------------------------------------------------------------
# Main runner
# ---------------------------------------------------------------------------

.grid_worker_packages <- c("dplyr", "tibble", "tidyr", "purrr", "lubridate",
                           "rlang", "stats")

.ts <- function() format(Sys.time(), "%Y-%m-%d %H:%M:%S")

#' Run the full scenario grid from a YAML config
#'
#' Expands the scenario grid, then for each scenario: loads the blinded panel
#' once (cached by panel-relevant keys), and for each replication draws a
#' pseudo-schedule (seed = seed_rep), injects the effect for every grid delta
#' (seed = seed_rep + 1), runs every estimator, computes the simulated truth
#' per estimand from delta_imposed, and appends contract rows. Replications
#' run in parallel via furrr (L'Ecuyer streams; serial when workers = 1) in
#' batches with timestamped progress lines. Partial results are written per
#' scenario to <out>/partials/<scenario_id>.csv; with resume = TRUE, scenarios
#' whose partial is complete (all expected estimator x rep x delta combos
#' present) are skipped.
#'
#' Outputs (all under output_blinded_power/<run_name>/): results_raw.csv.gz,
#' oc_summary.csv, mde_table.csv, pretrend_summary.csv, failures.csv,
#' scenario_truths.csv, run_metadata.json, partials/.
#'
#' @param config_path Path to the YAML scenario config.
#' @param resume Skip scenarios with complete partials (default TRUE).
#' @param workers Parallel workers (default: max(1, availableCores() - 2)).
#' @param run_name Output subdirectory name (default: config run_name or a
#'   timestamped name; pass a stable name to enable resume across sessions).
#' @param n_reps_override Override every scenario's replication counts (used
#'   by smoke tests, e.g. n_reps_override = 3).
#' @param impose_fn,estimator_fn Test hooks: mock implementations of the
#'   sibling-module contracts. Default NULL = source the real modules lazily.
#' @param batch_size Replications per progress batch (default 25).
#' @return Invisibly, list(results, oc, mde, pretrends, grid, out_dir).
#' @export
run_scenario_grid <- function(config_path, resume = TRUE, workers = NULL,
                              run_name = NULL, n_reps_override = NULL,
                              impose_fn = NULL, estimator_fn = NULL,
                              batch_size = 25L) {
  t_start <- Sys.time()
  cfg  <- read_power_config(config_path)
  fns  <- .ensure_sim_functions(impose_fn, estimator_fn)
  grid <- expand_scenario_grid(cfg)

  if (!is.null(n_reps_override)) {
    grid$n_reps <- as.integer(n_reps_override)
    grid$estimator_reps <- rep(list(NULL), nrow(grid))
  }

  run_name <- run_name %||% cfg$run_name %||%
    paste0("run_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  out_dir      <- .power_out_dir(run_name)
  partials_dir <- .power_out_dir(run_name, "partials")

  # Default workers: availableCores() returns 2 under `Rscript --vanilla`
  # (its environment hints are stripped), which silently collapsed the shell
  # runners to a single worker. parallel::detectCores() reads the hardware
  # directly, so take the max of the two before subtracting the headroom.
  workers <- workers %||%
    max(1L, max(future::availableCores(), parallel::detectCores(), 1L,
                na.rm = TRUE) - 2L)
  workers <- as.integer(workers)
  if (workers > 1L) {
    future::plan(future::multisession, workers = workers)
    on.exit(future::plan(future::sequential), add = TRUE)
  }
  map_reps <- function(x, f) {
    if (workers > 1L) {
      furrr::future_map_dfr(
        x, f,
        .options = furrr::furrr_options(seed = TRUE,
                                        packages = .grid_worker_packages)
      )
    } else {
      purrr::map_dfr(x, f)
    }
  }

  real_schedule <- guarded_read_csv(cfg$schedule)
  alpha_vec <- as.numeric(unlist(cfg$alpha %||% c(0.10, 0.05, 0.01)))

  cat(sprintf("[%s] run_scenario_grid: %d scenario(s), workers = %d, run = %s\n",
              .ts(), nrow(grid), workers, run_name))

  panel_cache <- new.env(parent = emptyenv())
  get_panel <- function(sc) {
    key <- paste(sc$level, sc$sample, sc$covid, sc$treat_def,
                 sc$loader_anticipation, sc$quarterly, sep = "|")
    if (!exists(key, envir = panel_cache)) {
      assign(key,
             load_blinded_panel(
               level = sc$level, treat_def = sc$treat_def,
               anticipation = sc$loader_anticipation, sample = sc$sample,
               covid = sc$covid, quarterly = sc$quarterly, config = cfg
             ),
             envir = panel_cache)
    }
    get(key, envir = panel_cache)
  }

  for (i in seq_len(nrow(grid))) {
    sc <- as.list(grid[i, ])
    # De-listify list-columns picked up by the single-row subset.
    sc$estimators     <- unlist(sc$estimators)
    sc$effect_grid    <- unlist(sc$effect_grid)
    sc$estimator_reps <- sc$estimator_reps[[1]]

    est_reps <- .estimator_rep_counts(sc$estimators, sc$n_reps,
                                      sc$estimator_reps)
    max_reps <- max(est_reps)
    n_expected <- sum(est_reps) * length(sc$effect_grid)
    partial <- file.path(partials_dir, paste0(sc$scenario_id, ".csv"))

    if (resume && file.exists(partial)) {
      done <- tryCatch(
        readr::read_csv(partial, show_col_types = FALSE, progress = FALSE),
        error = function(e) NULL
      )
      if (!is.null(done) && nrow(done) > 0L &&
          dplyr::n_distinct(paste(done$estimator, done$rep, done$delta)) >=
            n_expected) {
        cat(sprintf("[%s] %s: partial complete (%d rows) — skipping (resume)\n",
                    .ts(), sc$scenario_id, nrow(done)))
        next
      }
    }

    cat(sprintf(
      "[%s] %s START (%d reps x %d deltas x {%s}; design %s, %s/%s/%s)\n",
      .ts(), sc$scenario_id, max_reps, length(sc$effect_grid),
      paste(sc$estimators, collapse = ","), sc$design, sc$level, sc$sample,
      sc$mechanism))

    panel <- get_panel(sc)

    # Captured as a plain string so future exports it to parallel workers.
    power_root <- power_repo_root()

    run_one_rep <- function(rep) {
      # Parallel workers receive the functions this lambda references
      # DIRECTLY (make_pseudo_schedule, impose_effect via fns, ...), but not
      # those functions' own internal helpers (.ie_event_time, .re_prep, ...):
      # future's globals walker does not recurse into second-level globals of
      # exported closures. Re-source the framework modules once per worker
      # (sentinel-guarded; each module is standalone-sourceable). Harmless
      # under mocks and in serial runs, where the sentinel already exists.
      if (!exists(".ie_event_time", mode = "function") ||
          !exists(".re_prep", mode = "function")) {
        for (mod in c("config.R", "blindness_checks.R",
                      "make_pseudo_schedules.R", "impose_effects.R",
                      "run_estimators.R")) {
          source(file.path(power_root, "R", "power", mod))
        }
      }
      # Serial == parallel invariant: furrr(seed = TRUE) switches workers to
      # the L'Ecuyer-CMRG RNG kind, under which set.seed(seed_rep) inside
      # make_pseudo_schedule()/impose_effect() would yield different draws
      # than a serial run. Pin the kind so the explicit per-rep seeds produce
      # identical streams either way (furrr restores RNG state afterwards).
      suppressWarnings(RNGkind("Mersenne-Twister", "Inversion", "Rejection"))
      seed_rep <- power_rep_seed(cfg$base_seed, rep, sc$scenario_index)
      sched <- make_pseudo_schedule(
        design = sc$design, panel = panel, real_schedule = real_schedule,
        treat_def = sc$treat_def, min_pre = sc$min_pre,
        min_post = sc$min_post, seed = seed_rep
      )
      out <- list()
      for (delta in sc$effect_grid) {
        sim <- fns$impose(panel, sched, mechanism = sc$mechanism,
                          shape = sc$shape, delta = delta, params = list(),
                          outcome = sc$outcome, seed = seed_rep + 1L)
        truths <- .compute_truths(sim, sched, sc$shape)
        for (est in sc$estimators) {
          if (rep > est_reps[[est]]) next
          spec <- list(anticipation  = sc$est_anticipation,
                       control_group = sc$control_group,
                       outcome       = sc$outcome)
          res <- tryCatch(
            fns$estimate(sim, estimator = est, spec = spec),
            error = function(e) .estimator_failure_row(est,
                                                       conditionMessage(e))
          )
          res <- .attach_truth(res, truths)
          res$scenario_id      <- sc$scenario_id
          res$scenario_index   <- sc$scenario_index
          res$name             <- sc$name
          res$level            <- sc$level
          res$sample           <- sc$sample
          res$covid            <- sc$covid
          res$treat_def        <- sc$treat_def
          res$design           <- sc$design
          res$mechanism        <- sc$mechanism
          res$shape            <- sc$shape
          res$outcome          <- sc$outcome
          res$est_anticipation <- sc$est_anticipation
          res$loader_anticipation <- sc$loader_anticipation
          res$control_group    <- sc$control_group
          res$quarterly        <- sc$quarterly
          res$rep              <- rep
          res$delta            <- delta
          res$seed_rep         <- seed_rep
          out[[length(out) + 1L]] <- res
        }
      }
      bind_rows(out)
    }

    batches <- split(seq_len(max_reps),
                     ceiling(seq_len(max_reps) / batch_size))
    sc_rows <- vector("list", length(batches))
    for (bi in seq_along(batches)) {
      sc_rows[[bi]] <- map_reps(batches[[bi]], run_one_rep)
      cat(sprintf("[%s]   %s batch %d/%d (reps %d-%d): %d rows\n",
                  .ts(), sc$scenario_id, bi, length(batches),
                  min(batches[[bi]]), max(batches[[bi]]),
                  nrow(sc_rows[[bi]])))
    }
    sc_res <- bind_rows(sc_rows)
    readr::write_csv(sc_res, partial)
    cat(sprintf("[%s] %s END (%d rows -> %s)\n",
                .ts(), sc$scenario_id, nrow(sc_res), basename(partial)))
  }

  # ---- Stack from partials (single code path for fresh + resumed rows) ----
  partial_files <- file.path(partials_dir, paste0(grid$scenario_id, ".csv"))
  partial_files <- partial_files[file.exists(partial_files)]
  results <- purrr::map_dfr(partial_files, function(f) {
    readr::read_csv(f, show_col_types = FALSE, progress = FALSE) %>%
      mutate(
        converged  = as.logical(.data$converged),
        error_msg  = as.character(.data$error_msg),
        event_time = as.numeric(.data$event_time)
      )
  })
  if (nrow(results) == 0L) {
    stop("run_scenario_grid: no results were produced.", call. = FALSE)
  }

  cat(sprintf("[%s] summarizing %d result rows\n", .ts(), nrow(results)))
  oc  <- summarize_oc(results, alpha_vec = alpha_vec)
  mde <- compute_mde(oc, power_target = 0.80, alpha = 0.05,
                     results = results,
                     n_boot = as.integer(cfg$mde_boot %||% 200L))
  pre <- pretrend_summary(results)

  failures <- results %>% filter(!.data$converged)
  truth_meta <- results %>%
    filter(.data$estimand %in% c("overall", "simple")) %>%
    group_by(.data$scenario_id, .data$name, .data$mechanism, .data$shape,
             .data$delta) %>%
    summarise(
      n_reps = dplyr::n_distinct(.data$rep),
      mean_truth = mean(.data$truth, na.rm = TRUE),
      sd_truth   = stats::sd(.data$truth),
      min_truth  = min(.data$truth, na.rm = TRUE),
      max_truth  = max(.data$truth, na.rm = TRUE),
      .groups = "drop"
    )

  readr::write_csv(results, .power_out_file(run_name, "results_raw.csv.gz"))
  readr::write_csv(oc,       .power_out_file(run_name, "oc_summary.csv"))
  readr::write_csv(mde,      .power_out_file(run_name, "mde_table.csv"))
  readr::write_csv(pre,      .power_out_file(run_name, "pretrend_summary.csv"))
  readr::write_csv(failures, .power_out_file(run_name, "failures.csv"))
  readr::write_csv(truth_meta,
                   .power_out_file(run_name, "scenario_truths.csv"))

  git_rev <- tryCatch(
    system2("git", c("-C", shQuote(power_repo_root()), "rev-parse", "HEAD"),
            stdout = TRUE, stderr = FALSE)[1],
    error = function(e) NA_character_
  )
  meta <- list(
    config_path   = as.character(config_path),
    config        = cfg[setdiff(names(cfg), "repo_root")],
    run_name      = run_name,
    base_seed     = cfg$base_seed,
    workers       = workers,
    n_scenarios   = nrow(grid),
    scenario_ids  = grid$scenario_id,
    started_at    = format(t_start, "%Y-%m-%d %H:%M:%S %Z"),
    finished_at   = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    runtime_min   = as.numeric(difftime(Sys.time(), t_start, units = "mins")),
    git_rev       = git_rev,
    r_version     = R.version.string,
    session_info  = utils::capture.output(utils::sessionInfo()),
    blindness     = "all data via load_blinded_panel(); assert_blinded passed"
  )
  jsonlite::write_json(meta, .power_out_file(run_name, "run_metadata.json"),
                       auto_unbox = TRUE, pretty = TRUE, null = "null",
                       force = TRUE)

  cat(sprintf("[%s] DONE: %d rows, %d failure rows -> %s\n",
              .ts(), nrow(results), nrow(failures), out_dir))
  invisible(list(results = results, oc = oc, mde = mde, pretrends = pre,
                 grid = grid, out_dir = out_dir))
}
