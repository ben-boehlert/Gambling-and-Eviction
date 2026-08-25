################################################################################
# R/power/adaptive_mde.R
#
# Adaptive/sequential MDE search for the CS arm of the blinded power framework.
#
# WHY THIS EXISTS: the 2026-08-18 review of shift mode
# (quality_reports/sufficient_statistics_shift_mode_code_review.md) barred
# synthesized CS MDEs for the stochastic count_nb mechanism and prescribed
# "brute-force estimation or an adaptive/sequential grid that concentrates
# full simulations near the power crossing." This module is that adaptive
# grid: every recorded row is a GENUINE estimate (no loading, no synthesis);
# adaptivity only chooses WHICH (rep, delta) cells of the brute-force lattice
# get estimated, and in what order.
#
# CELL-EQUIVALENCE INVARIANT: a cell is estimated with exactly the brute-force
# call sequence of run_scenario_grid.R (schedule drawn under set.seed(seed_rep),
# injection re-seeded at seed_rep + 1, then run_estimator) — so every cell this
# module produces is bit-identical to the same cell of a brute-force run of the
# same config. Verified by tests and by the state-level comparison gate.
#
# Prespecified rules (quality_reports/plans/2026-08-19_adaptive-cs-mde-search.md):
#   * candidate deltas = the config grid only; the grid's range is never reduced
#   * delta = 0 always gets the full n_reps first (the size gate)
#   * size gate: per-arm delta=0 rejection at alpha .05 within [2.5%, 10%]
#     (design doc section 14); no arm passing => no MDE search, failure report
#   * classification vs the power target: point estimate at full reps; before
#     that, only a Wilson 95% CI clear of the target stops a point early
#   * final bracket points are ALWAYS topped up to full n_reps before the MDE
#     is interpolated (early stopping picks deltas, never reduces replication
#     at the decision points)
#   * boundary verdicts (never_crosses / at_or_below_smallest) require the
#     boundary grid point at full n_reps
#   * non-monotone classifications force full evaluation of the conflicted
#     range and an explicit anomalous verdict — never silent reconciliation
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
  library(rlang)
})

if (!exists("power_paths", mode = "function")) source("R/power/config.R")

# ---------------------------------------------------------------------------
# Pure decision core
# ---------------------------------------------------------------------------

#' Wilson score interval for a binomial proportion
#' @param k Successes. @param n Trials. @param conf Confidence level.
#' @return c(lo, hi); c(NA, NA) when n == 0.
#' @keywords internal
.amde_wilson <- function(k, n, conf = 0.95) {
  if (is.na(k) || is.na(n) || n <= 0L) return(c(NA_real_, NA_real_))
  z  <- stats::qnorm(1 - (1 - conf) / 2)
  ph <- k / n
  den <- 1 + z^2 / n
  ctr <- (ph + z^2 / (2 * n)) / den
  hw  <- z * sqrt(ph * (1 - ph) / n + z^2 / (4 * n^2)) / den
  c(max(0, ctr - hw), min(1, ctr + hw))
}

#' Classify an evaluated grid point against the power target
#'
#' At full replication (n >= n_full) the verdict is the POINT ESTIMATE —
#' exactly the quantity the brute-force MDE interpolation consumes. Before
#' that, only a Wilson CI wholly clear of the target classifies early;
#' anything else is "undecided" and receives another batch.
#' @keywords internal
.amde_classify <- function(k, n, n_full, target, conf = 0.95) {
  if (is.na(n) || n <= 0L) return("undecided")
  ph <- k / n
  if (n >= n_full) return(if (ph >= target) "above" else "below")
  ci <- .amde_wilson(k, n, conf)
  if (ci[1] > target) return("above")
  if (ci[2] < target) return("below")
  "undecided"
}

#' Per-delta tally of attempted / usable / rejecting reps for one arm
#'
#' `rows` uses the run_scenario_grid partial schema. Only the pooled estimand
#' ("simple"/"overall") is tallied — the MDE is defined on it. Rejection uses
#' the same p-with-CI-fallback rule as summarize_oc() (.reject_flag()).
#' @keywords internal
.amde_tally <- function(rows, arm, alpha = 0.05) {
  if (!exists(".reject_flag", mode = "function")) {
    source(file.path(power_repo_root(),
                     "R/power/summarize_operating_characteristics.R"))
  }
  # n_done counts ATTEMPTED cells: any row for a (rep, delta) — any arm,
  # any estimand, or a failure row — proves the cell ran. An arm-filtered
  # count would silently drop a rep from the arm's failure denominator
  # whenever the estimator emitted some arms but not this one (run_estimators
  # has three such paths for CS), understating failure AND stalling the
  # scheduler's rep allocation (review findings B2 / D1).
  attempted <- rows %>%
    group_by(.data$delta) %>%
    summarise(n_done = dplyr::n_distinct(.data$rep), .groups = "drop")
  armed <- rows %>%
    filter(!is.na(.data$inference), .data$inference == arm,
           .data$estimand %in% c("simple", "overall")) %>%
    mutate(
      converged = !is.na(.data$converged) & .data$converged,
      rej = .reject_flag(.data$p, .data$ci_lo, .data$ci_hi, alpha)
    ) %>%
    group_by(.data$delta) %>%
    summarise(
      n_used   = sum(.data$converged & !is.na(.data$rej)),
      k_reject = sum(.data$converged & !is.na(.data$rej) & .data$rej),
      .groups = "drop"
    )
  out <- attempted %>%
    left_join(armed, by = "delta") %>%
    mutate(n_used   = dplyr::coalesce(.data$n_used, 0L),
           k_reject = dplyr::coalesce(.data$k_reject, 0L)) %>%
    mutate(across(c("n_done", "n_used", "k_reject"), as.integer))
  # Load-bearing invariant (one usable simple row per rep x arm): if an
  # estimator ever emitted duplicates, every rate downstream would silently
  # exceed its denominator.
  stopifnot("tally: n_used exceeds n_done" = all(out$n_used <= out$n_done))
  out
}

#' Next scheduling action for the adaptive search (pure function)
#'
#' @param tally Tibble (delta, n_done, n_used, k_reject) for the driving arm.
#' @param grid Full config effect grid (must contain 0).
#' @param n_reps Full replication count per delta.
#' @param batch_size Reps allocated per action.
#' @param target Power target (0.80).
#' @param conf Wilson confidence for early stopping.
#' @return list(type, delta, reps, ...) — types: null_batch, eval_batch,
#'   top_up, bracket_done (with $bracket), verdict_never_crosses,
#'   verdict_at_or_below_smallest, anomaly_top_up, done_anomalous, cell_failed.
#' @keywords internal
.amde_next_action <- function(tally, grid, n_reps, batch_size = 25L,
                              target = 0.80, conf = 0.95) {
  grid <- sort(unique(as.numeric(grid)))
  stopifnot("effect grid must contain 0" = any(grid == 0))
  P <- grid[grid > 0]

  row_for <- function(d) tally[!is.na(tally$delta) & tally$delta == d, ]
  n_done_at <- function(d) {
    r <- row_for(d); if (nrow(r) == 0L) 0L else r$n_done[1]
  }
  batch_at <- function(d, type) {
    nd <- n_done_at(d)
    list(type = type, delta = d,
         reps = seq.int(nd + 1L, min(nd + batch_size, n_reps)))
  }

  # ---- Null phase: delta = 0 must reach full n_reps before any search.
  if (n_done_at(0) < n_reps) return(batch_at(0, "null_batch"))

  # ---- Classify every evaluated positive point.
  ev <- tally[!is.na(tally$delta) & tally$delta > 0 & tally$n_done > 0L, ]
  cls <- character(0)
  if (nrow(ev) > 0L) {
    cls <- vapply(seq_len(nrow(ev)), function(i) {
      full <- ev$n_done[i] >= n_reps
      if (full && ev$n_used[i] == 0L) return("failed")
      .amde_classify(ev$k_reject[i], ev$n_used[i],
                     n_full = if (full) ev$n_used[i] else n_reps,
                     target = target, conf = conf)
    }, character(1))
    names(cls) <- as.character(ev$delta)
  }

  if (any(cls == "failed")) {
    return(list(type = "cell_failed",
                delta = ev$delta[which(cls == "failed")[1]], reps = integer(0)))
  }

  # ---- An undecided point is finished before anything new is proposed.
  und <- ev$delta[cls == "undecided"]
  if (length(und) > 0L) return(batch_at(min(und), "eval_batch"))

  below <- ev$delta[cls == "below"]
  above <- ev$delta[cls == "above"]

  # ---- Anomaly: any "above" at a smaller delta than a "below" is a
  # non-monotone power curve reading. Evaluate the whole conflicted range at
  # full reps; if it persists, stop with an explicit anomalous verdict.
  if (length(above) > 0L && length(below) > 0L && min(above) < max(below)) {
    conflicted <- ev$delta[ev$delta >= min(above) & ev$delta <= max(below)]
    short <- conflicted[vapply(conflicted, n_done_at, integer(1)) < n_reps]
    if (length(short) > 0L) return(batch_at(min(short), "anomaly_top_up"))
    return(list(type = "done_anomalous", delta = NA_real_, reps = integer(0)))
  }

  lo <- if (length(below) > 0L) max(below) else NA_real_
  hi <- if (length(above) > 0L) min(above) else NA_real_

  # ---- Bisection: propose the upper-mid unevaluated grid point strictly
  # inside the unresolved index window (idx_lo, idx_hi).
  idx_lo <- if (is.na(lo)) 0L else match(lo, P)
  idx_hi <- if (is.na(hi)) length(P) + 1L else match(hi, P)
  window <- if (idx_hi - idx_lo >= 2L) {
    seq.int(idx_lo + 1L, idx_hi - 1L)
  } else integer(0)
  cand_idx <- setdiff(window, match(ev$delta, P))
  cand_idx <- cand_idx[cand_idx >= 1L & cand_idx <= length(P)]
  if (length(cand_idx) > 0L) {
    pick <- P[cand_idx[floor(length(cand_idx) / 2) + 1L]]
    return(batch_at(pick, "eval_batch"))
  }

  # ---- No candidates left. Boundary verdicts need the boundary point full.
  if (is.na(hi)) {
    gmax <- P[length(P)]                       # here lo == grid max
    if (n_done_at(gmax) < n_reps) return(batch_at(gmax, "top_up"))
    return(list(type = "verdict_never_crosses", delta = gmax,
                reps = integer(0)))
  }
  if (is.na(lo)) {
    gmin <- P[1]                               # here hi == smallest positive
    if (n_done_at(gmin) < n_reps) return(batch_at(gmin, "top_up"))
    return(list(type = "verdict_at_or_below_smallest", delta = gmin,
                reps = integer(0)))
  }

  # ---- Adjacent bracket: top up lo, then hi, then the FLANKING grid points
  # (one below lo, one above hi, where they exist). Flanks at full reps give
  # the MDE bootstrap CI admissible support of at least two grid steps per
  # side of the crossing instead of confining every draw to [lo, hi]
  # (Amendment 1 rule 2; review finding C1). A flank whose full-rep
  # classification breaks monotonicity is caught by the anomaly branch on
  # the next call — never silently reconciled.
  if (n_done_at(lo) < n_reps) return(batch_at(lo, "top_up"))
  if (n_done_at(hi) < n_reps) return(batch_at(hi, "top_up"))
  il <- match(lo, P); ih <- match(hi, P)
  flanks <- c(if (il > 1L) P[il - 1L], if (ih < length(P)) P[ih + 1L])
  for (f in flanks) {
    if (n_done_at(f) < n_reps) return(batch_at(f, "top_up_flank"))
  }
  list(type = "bracket_done", delta = NA_real_, reps = integer(0),
       bracket = c(lo, hi))
}

# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

# Canonical text key for one (rep, delta) cell. sprintf("%.15g") is a
# shortest-15-significant-digit rendering with NO padding — formatC(format =
# "g", digits = 15) left-pads to the digits width, which on 2026-08-19 made
# every new key mismatch an old-format sidecar and cost a 675-cell partial.
# A key computed from a CSV-round-tripped delta matches the key written at
# estimation time; exact float equality elsewhere is protected by
# .amde_snap_delta below.
.amde_key <- function(rep, delta) {
  paste(rep, sprintf("%.15g", delta), sep = ",")
}

# Sidecar keys have existed in three renderings (paste(), padded formatC,
# sprintf); stripping whitespace makes them all comparable.
.amde_normalize_keys <- function(keys) gsub("[[:space:]]+", "", keys)

# Snap CSV-round-tripped deltas onto the config grid (tolerance 1e-9). A
# single silent float mismatch would otherwise stall the scheduler into
# re-running cells forever (review finding D7).
.amde_snap_delta <- function(x, grid) {
  grid <- sort(unique(as.numeric(grid)))
  i <- vapply(x, function(v) which.min(abs(grid - v)), integer(1))
  snapped <- grid[i]
  off <- abs(snapped - x) > 1e-9
  snapped[off] <- x[off]
  snapped
}

# Inference arms each estimator is EXPECTED to emit (review finding B3): the
# size-gate table must enumerate these and mark an arm with no usable rows
# as an explicit failure, never silently omit it.
.amde_expected_arms <- function(estimator, cs_jack = FALSE) {
  switch(estimator,
         cs    = c("analytic", "boot", "boot_t", if (isTRUE(cs_jack)) "jack"),
         twfe  = c("analytic", "wild"),
         lpdid = c("analytic", "wild"),
         did2s = "analytic",
         bjs   = "analytic",
         longdiff = "jack",
         character(0))
}

.AMDE_TERMINAL <- c("bracket_done", "verdict_never_crosses",
                    "verdict_at_or_below_smallest", "done_anomalous",
                    "cell_failed", "scheduler_stalled")

.AMDE_VERDICT <- c(
  bracket_done                 = "interpolated",
  verdict_never_crosses        = "never_crosses_target",
  verdict_at_or_below_smallest = "at_or_below_smallest_grid_point",
  done_anomalous               = "anomalous_curve",
  cell_failed                  = "estimation_failed",
  scheduler_stalled            = "scheduler_stalled"
)

#' Adaptive/sequential MDE search over a power config
#'
#' Runs the scenario's delta = 0 cell for the full n_reps first (the size
#' gate), applies the design-doc section 14 size gate per inference arm of the
#' scenario's PRIMARY estimator (the first listed), and only for arms inside
#' `gate_interval` runs the grid-index bisection search for the
#' `power_target` crossing. Every estimated cell is genuine (brute-force call
#' sequence); results append to a per-scenario partial with a
#' `.done_cells` sidecar for crash-safe resume, and a per-scenario
#' `adaptive_state_<id>.json` records phase, tallies, bracket, and the next
#' action after every step.
#'
#' @param config_path YAML config (same schema as run_scenario_grid).
#' @param run_name Output subdirectory under output_blinded_power/.
#' @param workers Parallel workers (NULL = same default as run_scenario_grid).
#' @param scenarios Optional subset (positions, ids, or block names).
#' @param n_reps_override Override replication counts (smoke tests).
#' @param batch_size Reps allocated per scheduling action.
#' @param power_target Target power for the MDE (0.80).
#' @param gate_alpha Significance level for the size gate and power curve.
#' @param gate_interval Permitted null-rejection interval (design section 14).
#' @param arm_priority Order in which surviving arms drive the search.
#' @param impose_fn,estimator_fn Test hooks (mock implementations).
#' @param resume Reuse an existing partial + sidecar (default TRUE).
#' @param max_actions Stop after this many executed batches (testing/resume).
#' @return Invisibly: list(size_gate, mde, grid, out_dir, exhausted).
#' @export
run_adaptive_mde <- function(config_path, run_name = NULL, workers = NULL,
                             scenarios = NULL, n_reps_override = NULL,
                             batch_size = 25L, power_target = 0.80,
                             gate_alpha = 0.05,
                             gate_interval = c(0.025, 0.10),
                             arm_priority = c("boot", "boot_t", "analytic"),
                             impose_fn = NULL, estimator_fn = NULL,
                             resume = TRUE, max_actions = Inf) {
  t_start <- Sys.time()
  root <- power_repo_root()
  if (!exists("run_scenario_grid", mode = "function")) {
    source(file.path(root, "R/power/run_scenario_grid.R"))
  }
  if (!exists("summarize_oc", mode = "function")) {
    source(file.path(root, "R/power/summarize_operating_characteristics.R"))
  }

  cfg  <- read_power_config(config_path)
  fns  <- .ensure_sim_functions(impose_fn, estimator_fn)
  grid <- expand_scenario_grid(cfg)
  grid <- .select_scenarios(grid, scenarios)
  if (!is.null(n_reps_override)) {
    grid$n_reps <- as.integer(n_reps_override)
    grid$estimator_reps <- rep(list(NULL), nrow(grid))
    grid <- .assign_scenario_ids(grid, cfg$base_seed)
  }
  # Adaptive search IS full estimation: a shift-mode config here would be a
  # category error (and would collide with this module's honesty guarantees).
  stopifnot("run_adaptive_mde requires shift_mode: false" =
              !any(as.logical(grid$shift_mode)))

  run_name     <- run_name %||% cfg$run_name %||%
    paste0("amde_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  out_dir      <- .power_out_dir(run_name)
  partials_dir <- .power_out_dir(run_name, "partials")

  if (is.null(workers)) {
    slurm_cpus <- suppressWarnings(
      as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "")))
    workers <- if (!is.na(slurm_cpus) && slurm_cpus > 0L) slurm_cpus else {
      max(1L, max(future::availableCores(), parallel::detectCores(), 1L,
                  na.rm = TRUE) - 2L)
    }
  }
  workers <- as.integer(workers)
  if (workers > 1L) {
    future::plan(future::multisession, workers = workers)
    on.exit(future::plan(future::sequential), add = TRUE)
  }
  map_cells <- function(reps, f) {
    if (workers > 1L) {
      furrr::future_map_dfr(
        reps, f,
        .options = furrr::furrr_options(seed = TRUE,
                                        packages = .grid_worker_packages))
    } else purrr::map_dfr(reps, f)
  }

  real_schedule <- guarded_read_csv(cfg$schedule)

  if (isTRUE(cfg$cs_safe_patches)) {
    ok <- install_cs_safe_patches(TRUE, root = cfg$repo_root %||% root)
    cat(sprintf("[%s] cs_safe_patches: reg_did_rc guard %s\n", .ts(),
                if (ok) "ACTIVE on did's call path"
                else "NOT ACTIVE (see warning above)"))
    grid_has_cs <- any(vapply(grid$estimators,
                              function(e) "cs" %in% as.character(unlist(e)),
                              logical(1)))
    if (!ok && grid_has_cs) {
      stop("cs_safe_patches: TRUE but the guard is not active; refusing to ",
           "run a CS adaptive search that will abort mid-scenario.",
           call. = FALSE)
    }
  }

  cat(sprintf("[%s] run_adaptive_mde: %d scenario(s), workers = %d, run = %s\n",
              .ts(), nrow(grid), workers, run_name))

  panel_cache <- new.env(parent = emptyenv())
  get_panel <- function(sc) {
    key <- paste(sc$level, sc$sample, sc$covid, sc$treat_def,
                 sc$loader_anticipation, sc$quarterly, sep = "|")
    if (!exists(key, envir = panel_cache)) {
      assign(key, load_blinded_panel(
        level = sc$level, treat_def = sc$treat_def,
        anticipation = sc$loader_anticipation, sample = sc$sample,
        covid = sc$covid, quarterly = sc$quarterly, config = cfg
      ), envir = panel_cache)
    }
    get(key, envir = panel_cache)
  }

  budget <- new.env(parent = emptyenv())
  budget$left <- max_actions

  gate_all <- list(); mde_all <- list(); exhausted <- FALSE

  for (i in seq_len(nrow(grid))) {
    sc <- as.list(grid[i, ])
    sc$estimators     <- unlist(sc$estimators)
    sc$effect_grid    <- sort(unique(as.numeric(unlist(sc$effect_grid))))
    sc$estimator_reps <- sc$estimator_reps[[1]]
    res_i <- .amde_run_scenario(
      sc, cfg, fns, real_schedule, get_panel, partials_dir, map_cells,
      batch_size = as.integer(batch_size), power_target = power_target,
      gate_alpha = gate_alpha, gate_interval = gate_interval,
      arm_priority = arm_priority, resume = resume, budget = budget
    )
    gate_all[[i]] <- res_i$size_gate
    mde_all[[i]]  <- res_i$mde
    if (isTRUE(res_i$exhausted)) { exhausted <- TRUE; break }
  }

  size_gate <- dplyr::bind_rows(gate_all)
  mde       <- dplyr::bind_rows(mde_all)
  if (nrow(size_gate) > 0L) {
    readr::write_csv(size_gate, .power_out_file(run_name, "size_gate.csv"))
  }
  if (nrow(mde) > 0L) {
    readr::write_csv(mde, .power_out_file(run_name, "mde_adaptive.csv"))
  }
  # Run-level OC table over every visited cell (power per delta at ACHIEVED
  # reps — early-stopped deltas appear with their n_reps < the full count).
  if (!exhausted) {
    partial_files <- file.path(partials_dir, paste0(grid$scenario_id, ".csv"))
    partial_files <- partial_files[file.exists(partial_files)]
    if (length(partial_files) > 0L) {
      all_rows <- purrr::map_dfr(partial_files, function(f) {
        readr::read_csv(f, col_types = .PARTIAL_COL_TYPES,
                        show_col_types = FALSE, progress = FALSE)
      })
      if (nrow(all_rows) > 0L) {
        oc <- summarize_oc(all_rows, alpha_vec = gate_alpha,
                           sig_alpha = gate_alpha)
        readr::write_csv(oc, .power_out_file(run_name, "oc_summary.csv"))
      }
    }
  }
  if (!exhausted) {
    git_rev <- tryCatch(
      system2("git", c("-C", shQuote(root), "rev-parse", "HEAD"),
              stdout = TRUE, stderr = FALSE)[1],
      error = function(e) NA_character_)
    meta <- list(
      module = "run_adaptive_mde", config_path = as.character(config_path),
      config = cfg[setdiff(names(cfg), "repo_root")], run_name = run_name,
      base_seed = cfg$base_seed, workers = workers,
      batch_size = as.integer(batch_size), power_target = power_target,
      gate_alpha = gate_alpha, gate_interval = gate_interval,
      arm_priority = arm_priority,
      scenario_ids = grid$scenario_id,
      started_at  = format(t_start, "%Y-%m-%d %H:%M:%S %Z"),
      finished_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
      runtime_min = as.numeric(difftime(Sys.time(), t_start, units = "mins")),
      git_rev = git_rev, r_version = R.version.string,
      blindness = "all data via load_blinded_panel() (blindness enforced there)"
    )
    jsonlite::write_json(meta, .power_out_file(run_name, "run_metadata.json"),
                         auto_unbox = TRUE, pretty = TRUE, null = "null",
                         force = TRUE)
  }
  cat(sprintf("[%s] run_adaptive_mde %s: %s\n", .ts(), run_name,
              if (exhausted) "PAUSED (action budget exhausted; state saved)"
              else "DONE"))
  invisible(list(size_gate = size_gate, mde = mde, grid = grid,
                 out_dir = out_dir, exhausted = exhausted))
}

#' One scenario of the adaptive search (internal)
#' @keywords internal
.amde_run_scenario <- function(sc, cfg, fns, real_schedule, get_panel,
                               partials_dir, map_cells, batch_size,
                               power_target, gate_alpha, gate_interval,
                               arm_priority, resume, budget) {
  est_reps  <- .estimator_rep_counts(sc$estimators, sc$n_reps,
                                     sc$estimator_reps)
  n_reps    <- max(est_reps)
  primary   <- sc$estimators[1]
  partial   <- file.path(partials_dir, paste0(sc$scenario_id, ".csv"))
  cells_sc  <- paste0(partial, ".done_cells")
  state_pth <- file.path(dirname(partials_dir),
                         paste0("adaptive_state_", sc$scenario_id, ".json"))

  if (isTRUE(sc$cs_safe_patches)) {
    writeLines(
      c("cs_safe_patches: TRUE",
        paste0("patch: patches/reg_did_rc_safe.R over DRDID:::reg_did_rc",
               " (+ did imports frame)"),
        paste0("scenario_id: ", sc$scenario_id),
        paste0("estimators: ",
               paste(sort(as.character(sc$estimators)), collapse = ","))),
      paste0(partial, ".cs_safe_patches"))
  }

  # ---- Resume: keep only rows whose (rep, delta) cell the sidecar records
  # as fully appended; anything else is a torn batch and is redone.
  rows <- NULL
  if (resume && file.exists(partial) && file.exists(cells_sc)) {
    done_keys <- .amde_normalize_keys(unique(readLines(cells_sc)))
    old <- tryCatch(
      readr::read_csv(partial, col_types = .PARTIAL_COL_TYPES,
                      show_col_types = FALSE, progress = FALSE),
      error = function(e) NULL)
    if (!is.null(old) && nrow(old) > 0L) {
      old$delta <- .amde_snap_delta(old$delta, sc$effect_grid)
      keep <- .amde_normalize_keys(.amde_key(old$rep, old$delta)) %in%
        done_keys
      # Data-loss guard (2026-08-19 incident): a non-empty partial whose keys
      # match NOTHING in a non-empty sidecar means the matching itself is
      # broken — rewriting the partial with the empty match would destroy
      # every completed cell. Fail loudly instead.
      if (!any(keep) && length(done_keys) > 0L) {
        stop("run_adaptive_mde resume: sidecar and partial share no cell ",
             "keys for ", sc$scenario_id, " — refusing to discard a ",
             "non-empty partial. Inspect ", cells_sc, " before rerunning.",
             call. = FALSE)
      }
      rows <- old[keep, , drop = FALSE]
      readr::write_csv(rows, partial)
      writeLines(unique(.amde_key(rows$rep, rows$delta)), cells_sc)
      cat(sprintf("[%s] %s: resuming — %d completed cells found\n",
                  .ts(), sc$scenario_id,
                  nrow(unique(rows[, c("rep", "delta")]))))
    }
  }
  if (is.null(rows)) {
    # A partial that cannot be resumed (no/unreadable sidecar, or a fresh
    # resume = FALSE run) is ORPHANED, not deleted — a stray sidecar loss
    # must never destroy tens of hours of CS fits (review finding D6).
    if (file.exists(partial)) {
      file.rename(partial, paste0(partial, ".orphaned"))
      cat(sprintf("[%s] %s: existing partial moved to .orphaned\n",
                  .ts(), sc$scenario_id))
    }
    unlink(c(cells_sc, state_pth))
    rows <- tibble::tibble()
  }

  panel <- get_panel(sc)
  power_root <- power_repo_root()
  cs_safe_patches <- isTRUE(sc$cs_safe_patches)

  # ---- One (rep, delta) cell: exactly run_scenario_grid's brute-force call
  # sequence restricted to a single delta, so cells are bit-identical to a
  # brute-force run of the same config (the equivalence gate depends on it).
  cell_fn_for <- function(delta) {
    force(delta)
    function(rep) {
      if (!exists(".ie_event_time", mode = "function") ||
          !exists(".re_prep", mode = "function")) {
        for (mod in c("config.R", "blindness_checks.R",
                      "make_pseudo_schedules.R", "impose_effects.R",
                      "run_estimators.R")) {
          source(file.path(power_root, "R", "power", mod))
        }
      }
      if (isTRUE(cs_safe_patches)) {
        install_cs_safe_patches(TRUE, root = power_root)
      }
      suppressWarnings(RNGkind("Mersenne-Twister", "Inversion", "Rejection"))
      seed_rep <- power_rep_seed(cfg$base_seed, rep, sc$scenario_seed_offset)
      annotate_row <- function(res) {
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
        res$template         <- sc$template
        res$rep              <- rep
        res$delta            <- delta
        res$seed_rep         <- seed_rep
        res
      }
      sched <- tryCatch(
        make_pseudo_schedule(
          design = sc$design, panel = panel, real_schedule = real_schedule,
          treat_def = sc$treat_def, min_pre = sc$min_pre,
          min_post = sc$min_post, seed = seed_rep, template = sc$template),
        error = function(e) e)
      if (inherits(sched, "condition")) {
        msg <- paste0("schedule generation failed: ", conditionMessage(sched))
        out <- list()
        for (est in sc$estimators) {
          if (rep > est_reps[[est]]) next
          res <- .estimator_failure_row(est, msg)
          res$truth <- NA_real_
          out[[length(out) + 1L]] <- annotate_row(res)
        }
        return(dplyr::bind_rows(out))
      }
      sim <- fns$impose(panel, sched, mechanism = sc$mechanism,
                        shape = sc$shape, delta = delta, params = list(),
                        outcome = sc$outcome, seed = seed_rep + 1L)
      truths <- .compute_truths(sim, sched, sc$shape)
      spec <- list(anticipation   = sc$est_anticipation,
                   control_group  = sc$control_group,
                   outcome        = sc$outcome,
                   cs_faster_mode = isTRUE(sc$cs_faster_mode %||% TRUE),
                   lpdid_wild     = isTRUE(sc$lpdid_wild %||% FALSE),
                   lpdid_anchor   = as.character(sc$lpdid_anchor %||% "event_clean"),
                   lpdid_hmin     = as.integer(sc$lpdid_hmin %||% 0L),
                   lpdid_post     = as.integer(sc$lpdid_post %||% 12L),
                   lpdid_pmd      = as.integer(sc$lpdid_pmd %||% 3L),
                   lpdid_weights  = as.character(sc$lpdid_weights %||% "ewatt"))
      out <- list()
      for (est in sc$estimators) {
        if (rep > est_reps[[est]]) next
        res <- tryCatch(
          fns$estimate(sim, estimator = est, spec = spec),
          error = function(e) .estimator_failure_row(est, conditionMessage(e)))
        res <- .attach_truth(res, truths)
        out[[length(out) + 1L]] <- annotate_row(res)
      }
      dplyr::bind_rows(out)
    }
  }

  run_cells <- function(delta, reps) {
    # Duplicate-cell guard (review finding D1): a scheduler defect must fail
    # loudly, never append duplicate rows that would silently re-weight the
    # power curve.
    if (nrow(rows) > 0L) {
      clash <- .amde_key(rows$rep, rows$delta) %in% .amde_key(reps, delta)
      stopifnot("run_cells: proposed cells already exist in the partial" =
                  !any(clash))
    }
    new_rows <- map_cells(reps, cell_fn_for(delta))
    stopifnot("run_cells: a batch produced zero rows" = nrow(new_rows) > 0L)
    readr::write_csv(new_rows, partial, append = file.exists(partial))
    write(.amde_key(reps, delta), cells_sc, ncolumns = 1L, append = TRUE)
    rows <<- dplyr::bind_rows(rows, new_rows)
    cat(sprintf("[%s]   %s delta=%.3g reps %d-%d: %d rows\n",
                .ts(), sc$scenario_id, delta, min(reps), max(reps),
                nrow(new_rows)))
  }

  rows_primary <- function() {
    if (nrow(rows) == 0L) return(rows)
    rows[!is.na(rows$estimator) & rows$estimator == primary, , drop = FALSE]
  }

  state <- list(scenario_id = sc$scenario_id, phase = "null",
                n_reps = n_reps, batch_size = batch_size,
                power_target = power_target, gate_alpha = gate_alpha,
                gate_interval = gate_interval, arms = list())
  save_state <- function(...) {
    upd <- list(...)
    for (nm in names(upd)) state[[nm]] <<- upd[[nm]]
    state$updated_at <<- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
    jsonlite::write_json(state, state_pth, auto_unbox = TRUE, pretty = TRUE,
                         null = "null", force = TRUE)
  }

  spend_action <- function() {
    if (budget$left <= 0) return(FALSE)
    budget$left <- budget$left - 1
    TRUE
  }

  # ---- Phase 1: delta = 0 to full n_reps (cell counts, arm-agnostic).
  repeat {
    rp <- rows_primary()
    n0 <- if (nrow(rp) == 0L) 0L else {
      length(unique(rp$rep[rp$delta == 0]))
    }
    if (n0 >= n_reps) break
    reps <- seq.int(n0 + 1L, min(n0 + batch_size, n_reps))
    save_state(phase = "null",
               next_action = list(type = "null_batch", delta = 0,
                                  reps = range(reps)))
    if (!spend_action()) {
      return(list(size_gate = tibble::tibble(), mde = tibble::tibble(),
                  exhausted = TRUE))
    }
    run_cells(0, reps)
  }

  # ---- Phase 2: size gate per observed arm of the primary estimator.
  rp <- rows_primary()
  obs0 <- rp[rp$delta == 0 & !is.na(rp$inference) &
               rp$estimand %in% c("simple", "overall") &
               !is.na(rp$converged) & rp$converged, , drop = FALSE]
  observed_arms <- unique(obs0$inference)
  # Enumerate the arms the estimator is EXPECTED to emit plus anything
  # actually observed; an arm with no usable rows appears as an explicit
  # failure (review finding B3), never a silent absence.
  gate_arms <- union(.amde_expected_arms(primary), observed_arms)
  gate <- purrr::map_dfr(gate_arms, function(arm) {
    tal <- .amde_tally(rp, arm, gate_alpha)
    d0 <- tal[tal$delta == 0, ]
    n_done <- if (nrow(d0) > 0L) d0$n_done[1] else 0L
    n_used <- if (nrow(d0) > 0L) d0$n_used[1] else 0L
    k      <- if (nrow(d0) > 0L) d0$k_reject[1] else 0L
    rate <- if (n_used > 0L) k / n_used else NA_real_
    ci <- .amde_wilson(k, n_used)
    fr <- if (n_done > 0L) 1 - n_used / n_done else NA_real_
    # Size criterion of design section 14 PLUS its failure-rate criterion
    # (Amendment 1 rule 3; review finding B1). The other section-14 criteria
    # (coverage, bias, fragility) are NOT implemented here.
    size_ok <- !is.na(rate) &&
      rate >= gate_interval[1] && rate <= gate_interval[2]
    fail_ok <- !is.na(fr) && fr <= 0.05
    tibble::tibble(
      scenario_id = sc$scenario_id, estimator = primary, arm = arm,
      n_done = n_done, n_used = n_used, k_reject = k,
      reject_rate = rate, wilson_lo = ci[1], wilson_hi = ci[2],
      failure_rate = fr,
      gate_lo = gate_interval[1], gate_hi = gate_interval[2],
      pass = size_ok && fail_ok,
      reason = dplyr::case_when(
        n_used == 0L               ~ "no_usable_rows",
        !fail_ok                   ~ "failure_rate_gt_5pct",
        rate < gate_interval[1]    ~ "size_below_gate",
        rate > gate_interval[2]    ~ "size_above_gate",
        TRUE                       ~ "pass"
      )
    )
  })
  surviving <- gate$arm[gate$pass]
  surviving <- c(intersect(arm_priority, surviving),
                 setdiff(surviving, arm_priority))
  save_state(phase = "gate",
             arms = stats::setNames(
               lapply(gate$arm, function(a) {
                 list(gate_pass = gate$pass[gate$arm == a],
                      reject_rate = gate$reject_rate[gate$arm == a])
               }), gate$arm),
             surviving = as.list(surviving))

  if (length(surviving) == 0L) {
    mde <- tibble::tibble(
      scenario_id = sc$scenario_id, estimator = primary,
      arm = gate$arm, verdict = "size_gate_failed",
      mde = NA_real_, mde_ci_lo = NA_real_, mde_ci_hi = NA_real_,
      n_boot_finite = NA_integer_,
      bracket_lo = NA_real_, bracket_hi = NA_real_,
      power_lo = NA_real_, power_hi = NA_real_,
      n_used_lo = NA_integer_, n_used_hi = NA_integer_,
      full_deltas = NA_character_, ci_note = NA_character_,
      search_terminal = NA_character_, anomaly = FALSE
    )
    save_state(phase = "done_gate_failed")
    return(list(size_gate = gate, mde = mde, exhausted = FALSE))
  }

  # ---- Phase 3: bisection search, driven by each surviving arm in turn.
  # Hard iteration cap per arm (review finding D1): a scheduler defect must
  # surface as an explicit scheduler_stalled verdict, never an unbounded
  # compute burn. The cap is far above any legitimate path (every grid point
  # fully replicated twice over).
  max_iter <- 4L * ceiling(n_reps / batch_size) * length(sc$effect_grid)
  terminals <- list()
  for (arm in surviving) {
    iter <- 0L
    repeat {
      iter <- iter + 1L
      if (iter > max_iter) {
        cat(sprintf(paste0("[%s] %s: arm %s exceeded the scheduler ",
                           "iteration cap (%d) — flagging stalled\n"),
                    .ts(), sc$scenario_id, arm, max_iter))
        terminals[[arm]] <- list(type = "scheduler_stalled",
                                 delta = NA_real_, reps = integer(0))
        break
      }
      tal <- .amde_tally(rows_primary(), arm, gate_alpha)
      act <- .amde_next_action(tal, grid = sc$effect_grid, n_reps = n_reps,
                               batch_size = batch_size, target = power_target)
      save_state(phase = paste0("search_", arm),
                 tally = stats::setNames(
                   split(tal[, c("n_done", "n_used", "k_reject")],
                         seq_len(nrow(tal))),
                   as.character(tal$delta)),
                 next_action = list(type = act$type, delta = act$delta,
                                    reps = if (length(act$reps)) range(act$reps)
                                           else NULL))
      if (act$type %in% .AMDE_TERMINAL) {
        terminals[[arm]] <- act
        break
      }
      if (!spend_action()) {
        return(list(size_gate = gate, mde = tibble::tibble(),
                    exhausted = TRUE))
      }
      run_cells(act$delta, act$reps)
    }
  }

  # ---- Phase 4: MDE per arm from FULL-replication deltas only.
  mde <- purrr::map_dfr(gate$arm, function(arm) {
    base_row <- tibble::tibble(
      scenario_id = sc$scenario_id, estimator = primary, arm = arm,
      verdict = "size_gate_failed", mde = NA_real_,
      mde_ci_lo = NA_real_, mde_ci_hi = NA_real_, n_boot_finite = NA_integer_,
      bracket_lo = NA_real_, bracket_hi = NA_real_,
      power_lo = NA_real_, power_hi = NA_real_,
      n_used_lo = NA_integer_, n_used_hi = NA_integer_,
      full_deltas = NA_character_, ci_note = NA_character_,
      search_terminal = NA_character_, anomaly = FALSE
    )
    if (!arm %in% surviving) return(base_row)
    act <- terminals[[arm]]
    tal <- .amde_tally(rows_primary(), arm, gate_alpha)
    full_deltas <- tal$delta[tal$n_done >= n_reps]
    rp <- rows_primary()
    sub <- rp[!is.na(rp$inference) & rp$inference == arm &
                rp$estimand %in% c("simple", "overall") &
                rp$delta %in% full_deltas, , drop = FALSE]
    oc <- summarize_oc(sub, alpha_vec = gate_alpha, sig_alpha = gate_alpha)
    mtb <- compute_mde(oc, power_target = power_target, alpha = gate_alpha,
                       results = sub,
                       n_boot = as.integer(cfg$mde_boot %||% 200L))
    mrow <- mtb[!is.na(mtb$inference) & mtb$inference == arm, , drop = FALSE]
    base_row$verdict <- if (act$type == "bracket_done") {
      mrow$mde_reason[1]
    } else .AMDE_VERDICT[[act$type]]
    base_row$mde <- if (act$type %in%
                          c("bracket_done",
                            "verdict_at_or_below_smallest")) {
      mrow$mde[1]
    } else NA_real_
    # The bootstrap CI is only meaningful for a completed bracket: any other
    # terminal leaves it NA by construction, not by luck (review finding C4).
    if (act$type == "bracket_done") {
      base_row$mde_ci_lo    <- mrow$mde_ci_lo[1] %||% NA_real_
      base_row$mde_ci_hi    <- mrow$mde_ci_hi[1] %||% NA_real_
      base_row$n_boot_finite <- as.integer(mrow$n_boot_finite[1] %||%
                                             NA_integer_)
      base_row$bracket_lo <- act$bracket[1]
      base_row$bracket_hi <- act$bracket[2]
      t_lo <- tal[tal$delta == act$bracket[1], ]
      t_hi <- tal[tal$delta == act$bracket[2], ]
      base_row$power_lo  <- t_lo$k_reject[1] / t_lo$n_used[1]
      base_row$power_hi  <- t_hi$k_reject[1] / t_hi$n_used[1]
      base_row$n_used_lo <- t_lo$n_used[1]
      base_row$n_used_hi <- t_hi$n_used[1]
      # Honesty label (review finding C1): the CI conditions on the crossing
      # lying inside the evaluated full-rep window; draws crossing outside
      # it return NA and are dropped from the percentile CI.
      base_row$ci_note <- sprintf(
        "conditional on crossing within evaluated window [%g, %g]",
        min(full_deltas[full_deltas > 0]), max(full_deltas))
    }
    base_row$full_deltas <- paste(sort(full_deltas), collapse = ";")
    base_row$search_terminal <- act$type
    base_row$anomaly <- act$type == "done_anomalous"
    base_row
  })

  save_state(phase = "done",
             terminals = lapply(terminals, function(a) a$type))
  list(size_gate = gate, mde = mde, exhausted = FALSE)
}
