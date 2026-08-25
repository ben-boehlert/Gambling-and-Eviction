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
#' seed_rep = base_seed + 10007 * rep + 101 * scenario_offset. 10007 and 101
#' are coprime, so seeds are distinct across (rep, scenario) for any grid of
#' realistic size (a collision needs |rep difference| to be a multiple of 101
#' AND |scenario offset difference| to be a multiple of 10007 — impossible
#' because offsets are reduced mod 10007, so |difference| <= 10006).
#'
#' `scenario_offset` is derived from the scenario's CONTENT hash
#' (\code{.scenario_seed_offset}), not its position in the config. Results
#' therefore depend only on what a scenario is, never on where it sits in the
#' scenarios list — reordering or inserting blocks leaves every other
#' scenario's draws bit-identical.
#'
#' @export
power_rep_seed <- function(base_seed, rep, scenario_offset) {
  as.integer(base_seed) + 10007L * as.integer(rep) +
    101L * as.integer(scenario_offset)
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
  quarterly = "quarterly",
  # Time aggregation: "month" (default) / "quarter" / "year". Supersedes the
  # legacy boolean `quarterly`, which is kept in sync for id stability.
  time_agg = "time_agg", time_aggs = "time_agg",
  complete_periods_only = "complete_periods_only",
  # Cohort-template source for pseudo-schedules (make_pseudo_schedule §8):
  # "national" (full real schedule) or "panel" (restricted to panel states).
  template = "template", templates = "template"
)

.scenario_slug <- function(g) {
  s <- paste(g$name, g$level, g$sample, g$covid, g$design, g$mechanism,
             g$shape, g$outcome, paste0("a", g$est_anticipation), sep = "-")
  s <- paste0(s,
              ifelse(g$quarterly, "-q", ""),
              ifelse(g$time_agg == "year", "-yr", ""),
              ifelse(g$complete_periods_only, "-cp", ""),
              ifelse(g$control_group == "nevertreated", "-nt", ""),
              ifelse(g$template == "panel", "-tpanel", ""))
  tolower(gsub("[^A-Za-z0-9_-]", "", s))
}

# --- Content-addressed scenario identity -----------------------------------
#
# scenario_id must depend on WHAT a scenario is, never on WHERE it sits in the
# config. A positional id (the previous "S%03d_" scheme) meant inserting or
# reordering one block renamed every downstream partial, so `resume` re-ran
# scenarios whose inputs had not changed at all. The hash below closes that,
# and also covers the axes the slug omits (treat_def, loader_anticipation) and
# the execution settings that change a partial's contents (estimators, effect
# grid, replication counts, support minima, base seed). Same id <=> same
# inputs <=> the partial on disk is reusable.

# Canonicalise one identity field to a stable string. Doubles go through
# "%.10g" so 0.05 has one representation on every platform; named vectors keep
# their names so estimator_reps = c(cs = 250) never collides with c(twfe = 250).
.canon_atom <- function(v) {
  if (is.null(v) || length(v) == 0L) return("NULL")
  nm <- names(v)
  s <- if (is.double(v)) sprintf("%.10g", v) else as.character(v)
  if (!is.null(nm)) s <- paste(nm, s, sep = "=")
  paste(s, collapse = ",")
}

.canon_est_reps <- function(er) {
  if (is.null(er) || length(er) == 0L) return(NULL)
  er <- unlist(er)
  stats::setNames(as.integer(er[order(names(er))]), sort(names(er)))
}

#' Canonical identity string for one scenario row
#'
#' `v` is an identity-schema version: bump it if the set of hashed fields
#' changes, so stale partials from an older scheme are never silently adopted.
#' @keywords internal
.scenario_identity_string <- function(g, i, base_seed) {
  id <- list(
    v                   = 2L,
    name                = g$name[i],
    level               = g$level[i],
    sample              = g$sample[i],
    covid               = g$covid[i],
    treat_def           = g$treat_def[i],
    design              = g$design[i],
    mechanism           = g$mechanism[i],
    shape               = g$shape[i],
    outcome             = g$outcome[i],
    est_anticipation    = as.integer(g$est_anticipation[i]),
    loader_anticipation = as.integer(g$loader_anticipation[i]),
    control_group       = g$control_group[i],
    quarterly           = as.logical(g$quarterly[i]),
    estimators          = sort(as.character(unlist(g$estimators[[i]]))),
    # `template` is hashed CONDITIONALLY (only when != "national") rather than
    # via a v-bump: template = "national" is bit-identical to pre-axis
    # behavior, so existing national partials (e.g. the completed primary
    # state scenarios) must keep their ids; panel-template scenarios get
    # distinct ids. Do NOT change this to unconditional without a v-bump.
    effect_grid         = sort(as.numeric(unlist(g$effect_grid[[i]]))),
    n_reps              = as.integer(g$n_reps[i]),
    estimator_reps      = .canon_est_reps(g$estimator_reps[[i]]),
    min_pre             = as.integer(g$min_pre[i]),
    min_post            = as.integer(g$min_post[i]),
    base_seed           = as.integer(base_seed)
  )
  if (!identical(as.character(g$template[i]), "national")) {
    id$template <- as.character(g$template[i])
  }
  # `cs_safe_patches` is hashed CONDITIONALLY, on the same principle as
  # `template` above: FALSE reproduces pre-flag behavior bit-for-bit, so every
  # existing partial must keep its id. TRUE changes what CS returns on cells
  # that previously aborted the process (structured NA instead of a crash), so
  # those runs must land in their own scenario ids and can never be pooled
  # with unpatched partials by the resume/aggregate path.
  #
  # ...but ONLY for scenarios that actually run CS. The guard replaces a DRDID
  # internal reachable solely through did::att_gt(), so a twfe/did2s block is
  # provably unaffected by it. Hashing the flag there would move those ids the
  # moment the flag is switched on in power_primary.yml, silently orphaning the
  # completed county twfe/did2s partials (~28-30h) and making `resume` re-run
  # work the guard cannot change.
  if (isTRUE(g$cs_safe_patches[i]) &&
      "cs" %in% as.character(unlist(g$estimators[[i]]))) {
    id$cs_safe_patches <- TRUE
  }
  # Same treatment for cs_faster_mode: hashed only when it departs from the
  # historical default (TRUE) and only for scenarios that run CS. It is a
  # direct att_gt() argument, so it changes the CS estimate itself -- results
  # computed under the two settings must never share a partial.
  if (!isTRUE(g$cs_faster_mode[i]) &&
      "cs" %in% as.character(unlist(g$estimators[[i]]))) {
    id$cs_faster_mode <- FALSE
  }
  # `time_agg` is hashed CONDITIONALLY, and only for "year": "month" is the
  # pre-axis default and "quarter" is already fully encoded by the legacy
  # `quarterly = TRUE` field hashed above, so both keep their existing ids.
  if (identical(as.character(g$time_agg[i]), "year")) {
    id$time_agg <- "year"
  }
  # `complete_periods_only` likewise: FALSE reproduces pre-rule behavior.
  if (isTRUE(g$complete_periods_only[i])) {
    id$complete_periods_only <- TRUE
  }
  # `exclude_states` is hashed CONDITIONALLY (only when non-empty): an empty
  # exclusion reproduces pre-axis behavior bit-for-bit, so every existing
  # partial keeps its id; a non-empty exclusion changes the panel (and hence
  # the template, controls, and every estimate) and must land in its own id.
  if (length(g$exclude_states[[i]]) > 0L) {
    id$exclude_states <- sort(as.character(g$exclude_states[[i]]))
  }
  # `lpdid_wild` is hashed CONDITIONALLY, same principle and estimator gating
  # as cs_faster_mode: TRUE adds a genuine bootstrap inference arm to every
  # lpdid fit (extra rows in the partial), so wild and non-wild runs must
  # never share a partial — but a scenario with no lpdid is provably
  # unaffected and must keep its id.
  if (isTRUE(g$lpdid_wild[i]) &&
      "lpdid" %in% as.character(unlist(g$estimators[[i]]))) {
    id$lpdid_wild <- TRUE
  }
  # `lpdid_anchor` uses an inverted compatibility rule. Historical partials
  # used "event" and omitted this key. New runs default to "event_clean", so
  # that value MUST be hashed; explicit legacy "event" stays unhashed and can
  # reproduce old ids. Other anchors are also hashed. lpdid_hmin/lpdid_post
  # retain their historical conditional rules.
  #
  # NOTE the anchor is a no-op on schedules with no separate launch date, so a
  # run that sets it there gets a NEW id for a bit-identical result. That is
  # the safe direction of the trade (a redundant re-run, never a silent pool
  # of two different estimands), and it matches how `template` is handled.
  if ("lpdid" %in% as.character(unlist(g$estimators[[i]]))) {
    anch <- as.character(g$lpdid_anchor[i] %||% "event_clean")
    if (length(anch) != 1L || is.na(anch)) anch <- "event_clean"
    if (!identical(anch, "event")) id$lpdid_anchor <- anch
    hmn <- suppressWarnings(as.integer(g$lpdid_hmin[i] %||% 0L))
    if (length(hmn) != 1L || is.na(hmn)) hmn <- 0L
    if (hmn != 0L) id$lpdid_hmin <- hmn
    hmx <- suppressWarnings(as.integer(g$lpdid_post[i] %||% 12L))
    if (length(hmx) != 1L || is.na(hmx)) hmx <- 12L
    if (hmx != 12L) id$lpdid_post <- hmx
    # `lpdid_pmd` follows the usual rule: 3 was the hard-wired historical
    # value, so it stays unhashed and existing partials keep their ids.
    pmd <- suppressWarnings(as.integer(g$lpdid_pmd[i] %||% 3L))
    if (length(pmd) != 1L || is.na(pmd)) pmd <- 3L
    if (pmd != 3L) id$lpdid_pmd <- pmd
    # `lpdid_weights` INVERTS the rule, deliberately. Every other conditional
    # knob hashes its NON-default value because the default reproduces
    # historical behavior. Here the default itself changed: before 2026-08-24
    # this framework ran the "cellsize" weights (see the estimand block in
    # run_estimators.R). Hashing the new default instead means a post-fix run
    # lands on a NEW scenario id and can never silently pool with a pre-fix
    # partial, while `lpdid_weights: cellsize` still reproduces the old id
    # bit-for-bit for paired comparison. Same safe direction as `template`:
    # a redundant re-run, never a silent pool of two different estimands.
    wsc <- as.character(g$lpdid_weights[i] %||% "ewatt")
    if (length(wsc) != 1L || is.na(wsc)) wsc <- "ewatt"
    if (!identical(wsc, "cellsize")) id$lpdid_weights <- wsc
  }
  # `shift_mode` is hashed CONDITIONALLY, same principle as `template` /
  # `cs_safe_patches` above: FALSE reproduces pre-flag behavior bit-for-bit,
  # so every existing partial must keep its id. TRUE changes what a
  # non-calibration rep computes (delta=0 fully estimated; delta>0 shifted
  # from that rep's own delta=0 fit instead of independently estimated), so
  # those runs must land in their own scenario ids. Unlike cs_safe_patches /
  # cs_faster_mode, this is NOT gated on estimator: shift mode changes the
  # rep loop for EVERY estimator in the scenario, not one estimator's
  # internals.
  if (isTRUE(g$shift_mode[i])) {
    id$shift_mode <- TRUE
    id$shift_calibration_reps <- as.integer(g$shift_calibration_reps[i])
  }
  paste(paste0(names(id), ":", vapply(id, .canon_atom, character(1))),
        collapse = "|")
}

# sha1 of the raw identity string (serialize = FALSE hashes the bytes, so the
# digest does not depend on R's serialization version — the local machine and
# Della's R/4.4.2 must agree).
.scenario_hash <- function(g, i, base_seed) {
  digest::digest(.scenario_identity_string(g, i, base_seed),
                 algo = "sha1", serialize = FALSE)
}

# Seed offset from the hash. 7 hex digits max: 0xFFFFFFF = 268435455 fits in a
# 32-bit int (8 would overflow to NA). Reduced mod 10007 to keep
# power_rep_seed()'s collision argument intact.
.scenario_seed_offset <- function(hash_hex) {
  as.integer(strtoi(substr(hash_hex, 1L, 7L), 16L) %% 10007L)
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
    quarterly           = cfg$quarterly %||% FALSE,
    time_agg            = cfg$time_agg %||% "month",
    complete_periods_only = cfg$complete_periods_only %||% FALSE,
    template            = cfg$template %||% "national"
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
    # Run-level only (no per-block override): the guard is a property of the
    # R process, installed once per worker, so it cannot vary scenario to
    # scenario within a run.
    g$cs_safe_patches <- isTRUE(cfg$cs_safe_patches)
    # Per-fit att_gt() argument, so a block MAY override it. `%||%` keeps an
    # explicit FALSE (only NULL falls through to the run-level value).
    g$cs_faster_mode <- isTRUE(blk$cs_faster_mode %||% cfg$cs_faster_mode %||%
                                 TRUE)
    # Per-fit boottest arm for LP-DiD; block may override, same principle.
    g$lpdid_wild <- isTRUE(blk$lpdid_wild %||% cfg$lpdid_wild %||% FALSE)
    # LP-DiD cell anchor and pooled-horizon floor; block may override.
    g$lpdid_anchor <- as.character(blk$lpdid_anchor %||% cfg$lpdid_anchor %||%
                                     "event_clean")
    g$lpdid_hmin <- as.integer(blk$lpdid_hmin %||% cfg$lpdid_hmin %||% 0L)
    g$lpdid_post <- as.integer(blk$lpdid_post %||% cfg$lpdid_post %||% 12L)
    # LP-DiD base-period width and cell weighting; block may override.
    g$lpdid_pmd <- as.integer(blk$lpdid_pmd %||% cfg$lpdid_pmd %||% 3L)
    g$lpdid_weights <- as.character(blk$lpdid_weights %||% cfg$lpdid_weights %||%
                                      "ewatt")
    # States dropped from the panel BEFORE schedule/template derivation —
    # neither treated-template members nor controls (dose-tercile
    # subdesigns, 2026-08-19). Block may override the run level.
    g$exclude_states <- rep(list(sort(unique(as.character(unlist(
      blk$exclude_states %||% cfg$exclude_states %||% character(0)
    ))))), nrow(g))
    rows[[b]] <- g
  }

  grid <- bind_rows(rows) %>%
    mutate(
      est_anticipation    = as.integer(.data$est_anticipation),
      loader_anticipation = as.integer(.data$loader_anticipation),
      # Reconcile the legacy boolean with the axis: a config that sets only
      # `quarterly: true` still yields time_agg = "quarter", and `quarterly`
      # is then always derived from time_agg so the two can never disagree
      # (and a quarterly scenario keeps the id it had before this axis).
      time_agg            = ifelse(.data$time_agg == "month" &
                                     as.logical(.data$quarterly),
                                   "quarter", as.character(.data$time_agg)),
      quarterly           = .data$time_agg == "quarter",
      complete_periods_only = as.logical(.data$complete_periods_only),
      # Run-level only (no per-block override), same rationale as
      # cs_safe_patches: shift mode changes the rep-loop MECHANICS
      # uniformly across every scenario in a run, not something that varies
      # scenario to scenario. shift_calibration_reps defaults to 10% of
      # EACH scenario's own n_reps (min 10, design doc shift-mode addendum)
      # unless the config pins one value for every scenario in the run.
      shift_mode = isTRUE(cfg$shift_mode),
      shift_calibration_reps = if (!is.null(cfg$shift_calibration_reps)) {
        as.integer(cfg$shift_calibration_reps)
      } else {
        as.integer(pmax(10L, ceiling(0.1 * .data$n_reps)))
      }
    )
  # scenario_index is the deterministic position in the expanded grid. It is
  # used ONLY to address scenarios for dispatch (e.g. a SLURM array task id).
  # It never enters a filename or a seed — see .scenario_hash().
  grid$scenario_index <- seq_len(nrow(grid))

  .assign_scenario_ids(grid, cfg$base_seed)
}

#' Attach content-addressed ids to an expanded grid
#'
#' Recomputed whenever anything hashed changes (notably after
#' \code{n_reps_override}), so the invariant "same scenario_id <=> same
#' inputs" holds for every code path that writes a partial. Leaves
#' \code{scenario_index} untouched.
#' @keywords internal
.assign_scenario_ids <- function(grid, base_seed) {
  hashes <- vapply(seq_len(nrow(grid)),
                   function(i) .scenario_hash(grid, i, base_seed),
                   character(1))
  grid$scenario_hash        <- hashes
  grid$scenario_seed_offset <- vapply(hashes, .scenario_seed_offset,
                                      integer(1), USE.NAMES = FALSE)
  grid$scenario_id <- paste0("S", substr(hashes, 1L, 10L), "_",
                             .scenario_slug(grid))

  if (anyDuplicated(grid$scenario_id)) {
    dup <- unique(grid$scenario_id[duplicated(grid$scenario_id)])
    stop("expand_scenario_grid: duplicate scenario identities — two blocks ",
         "expand to the same scenario. Remove the redundant block(s): ",
         paste(dup, collapse = ", "), call. = FALSE)
  }
  # Distinct scenarios sharing a seed offset is not a correctness bug (it just
  # means common random numbers across those scenarios), but it is never
  # intended, so surface it.
  if (anyDuplicated(grid$scenario_seed_offset)) {
    warning("expand_scenario_grid: seed-offset collision mod 10007; ",
            "affected scenarios share replication seeds.", call. = FALSE)
  }
  grid
}

#' Resolve the `scenarios` argument to a subset of the expanded grid
#' @keywords internal
.select_scenarios <- function(grid, scenarios) {
  if (is.null(scenarios)) return(grid)
  if (length(scenarios) == 0L) {
    stop("run_scenario_grid: `scenarios` is empty.", call. = FALSE)
  }

  if (is.numeric(scenarios)) {
    idx <- as.integer(scenarios)
    bad <- idx[is.na(idx) | idx < 1L | idx > nrow(grid)]
    if (length(bad)) {
      stop(sprintf(paste0("run_scenario_grid: scenario index out of range: ",
                          "%s (grid has %d scenarios)."),
                   paste(bad, collapse = ", "), nrow(grid)), call. = FALSE)
    }
    return(grid[sort(unique(idx)), , drop = FALSE])
  }

  sel <- as.character(scenarios)
  unmatched <- setdiff(sel, c(grid$scenario_id, grid$name))
  if (length(unmatched)) {
    stop(sprintf(paste0("run_scenario_grid: no scenario matches %s. ",
                        "Known block names: %s."),
                 paste(shQuote(unmatched), collapse = ", "),
                 paste(unique(grid$name), collapse = ", ")), call. = FALSE)
  }
  grid[grid$scenario_id %in% sel | grid$name %in% sel, , drop = FALSE]
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
# Shift-mode synthesis
#
# Validated 2026-08-17 (analysis/diagnostics/validate_shift_sufficiency.R,
# output/shift_validation{,_cs}/): every estimator in this framework is
# (to a tight tolerance) linear in the outcome, so a rep's delta=0 fit plus
# a fitted loading L_hat reproduces the whole effect grid. Deterministic
# injection: discrepancy EXACTLY 0 (L_hat == 1 to floating precision).
# count_nb mechanism: CS analytic mean discrepancy <= 0.003 power points,
# L_hat in [1.07, 1.23] (NOT 1 -- a deterministic-injection loading would
# miss this real-mechanism factor, which is exactly why L_hat is fit on the
# CALIBRATION reps' real data rather than assumed).
#
# CALIBRATION-SUBSET DESIGN: run_one_rep() (below) runs the full delta grid
# for reps 1..shift_calibration_reps and, for every other rep, runs the
# estimator ONLY at delta = 0, emitting error_msg == "shift_pending"
# placeholder rows (same schema, NA estimates) at delta > 0. This function
# is called ONCE per scenario, after every rep has been computed, and fills
# those placeholders in place on the scenario's partial CSV.
# ---------------------------------------------------------------------------

# Explicit types for a scenario partial's known columns (the run_estimator()
# / annotate_row() schema plus truth/rep/delta/seed_rep). Guards every
# read_csv() of a partial against readr's type-guessing going wrong when the
# ~1000-row sample readr uses to infer a column's type happens to be all
# failure rows for that scenario -- observed, not hypothetical: D1 on
# county/S2 failed 50/50 reps (2026-08-10), which would leave att/se/p/ci_lo/
# ci_hi guessed as logical (all-NA) and every downstream numeric comparison
# silently vacuous. Unlisted columns fall back to col_guess() so this does
# not need updating when annotate_row() gains a new scenario-metadata column.
.PARTIAL_COL_TYPES <- readr::cols(
  estimator = readr::col_character(), inference = readr::col_character(),
  estimand = readr::col_character(), event_time = readr::col_double(),
  att = readr::col_double(), se = readr::col_double(), p = readr::col_double(),
  ci_lo = readr::col_double(), ci_hi = readr::col_double(),
  n_treated_clusters = readr::col_integer(),
  n_control_clusters = readr::col_integer(),
  converged = readr::col_logical(), error_msg = readr::col_character(),
  runtime_s = readr::col_double(), truth = readr::col_double(),
  rep = readr::col_integer(), delta = readr::col_double(),
  seed_rep = readr::col_double(),
  .default = readr::col_guess()
)

# Inference arms whose p/CI can be honestly reconstructed from the columns
# already stored in a per-rep row (mirrors validate_shift_sufficiency.R's
# TSTAT_INFERENCE / CI_SHIFT_INFERENCE dispatch, unified into one set since
# both get the SAME shifted CI here -- see .shift_synthesize_partial()).
# CS's "boot" (genuine multiplier-bootstrap p, did:::mboot on a fresh draw)
# and "jack" (CV3 delete-one-cluster jackknife, df = reps - 1) are NOT in
# this set: neither quantity is a function of (att0, se0, ci_lo0, ci_hi0),
# so they can never be synthesized from a shift.
.SHIFT_RECONSTRUCTABLE_INFERENCE <- c("analytic", "boot_t", "wild")

# Two-sided t p-value. Deliberately NOT a call to run_estimators.R's
# .re_tp() -- run_scenario_grid.R must not assume that module has been
# sourced (test hooks can supply impose_fn/estimator_fn mocks and skip it
# entirely; see .ensure_sim_functions()). Identical formula, kept
# self-contained here.
#' @keywords internal
.shift_tp <- function(att, se, df) {
  ifelse(is.finite(att) & is.finite(se) & se > 0 & df > 0,
        2 * stats::pt(-abs(att / se), df = df), NA_real_)
}

#' Synthesize shift-mode placeholder rows on a scenario's partial (in place)
#'
#' Fits a through-origin loading L_hat per (estimator, inference, estimand,
#' delta) -- PER DELTA, not pooled across the grid. The loading is NOT
#' delta-invariant under a stochastic mechanism: measured on
#' output/shift_validation_cs/loading_by_delta.csv (2026-08-1x), CS/analytic
#' under count_nb ranges 1.4328 (delta=0.02, ramp) down to 1.2065
#' (delta=0.10, ramp), a 16% drift; the deterministic mechanism is exactly
#' 1.000 at every delta, confirming the drift is a MECHANISM artifact (Poisson/
#' NB count augmentation is not exactly linear in delta on the log1p scale),
#' not estimator nonlinearity. A single pooled L_hat is a truth^2-weighted
#' slope across the whole grid -- on a grid with large deltas present, it is
#' dominated by exactly the range where the loading is smallest, then applied
#' at the small-delta MDE crossing where the loading is largest, biasing
#' synthesized power down and the MDE up. Fitting per delta removes this at
#' zero statistical cost: calibration reps run the FULL grid by construction,
#' so there are shift_calibration_reps calibration pairs at EVERY delta, not
#' just the ones near the MDE.
#'
#' For a fixed (estimator, inference, estimand, delta), L_hat is pooled over
#' every row with THAT delta AND converged == TRUE (which, by construction,
#' are exactly the calibration reps' real estimates at that delta -- a
#' "shift_pending" row is never converged, and a previously-filled row is
#' excluded explicitly, see IDEMPOTENCE below) paired against THAT ROW'S OWN
#' rep's delta = 0 baseline (same estimator/inference/estimand/event_time):
#'
#'   L_hat(delta) = sum_{calib reps at this delta} (att - att0) * truth
#'                  / sum_{calib reps at this delta} truth^2
#'
#' truth is identical across calibration reps at a fixed delta under
#' "step"/constant shapes (varies under "ramp"/"delayed" by event time within
#' a rep, not across reps), so this is very close to a plain mean of the
#' observed shift divided by truth at that delta; the truth^2-weighted form
#' is used for consistency with the single-delta identity and with
#' analysis/diagnostics/validate_shift_sufficiency.R's per-delta diagnostic
#' (loading_by_delta.csv).
#'
#' Every row still tagged error_msg == "shift_pending" is then filled from
#' its own rep's delta = 0 baseline, using THAT ROW'S delta to look up
#' L_hat(delta):
#'
#'   att = att0 + L_hat(delta) * truth;  se = se0
#'   ci_lo = ci_lo0 + L_hat(delta) * truth;  ci_hi = ci_hi0 + L_hat(delta) * truth
#'
#' For analytic/boot_t, this CI shift is algebraically IDENTICAL to
#' recomputing att -/+ z * se with run_estimators.R's own z
#' (= qt(1 - alpha/2, df)): since ci_hi0 == att0 + z * se0 by construction,
#' ci_hi0 + shift == (att0 + shift) + z * se0. For "wild", that identity does
#' NOT hold -- run_estimators.R stores an INVERTED, generally ASYMMETRIC
#' bootstrap CI for the wild arm (fwildclusterboot::boottest() +
#' stats::confint()), and the wild row's `se` column is the ANALYTIC fixest
#' SE, not a quantity satisfying ci_hi0 == att0 + z*se0. The wild CI shift is
#' correct anyway, for a DIFFERENT and more general reason: any confidence
#' interval for a location parameter is translation-equivariant under a
#' constant shift of the outcome -- shifting y by a constant delta shifts
#' EVERY quantile of the induced test-statistic distribution, and hence the
#' whole (possibly asymmetric) inverted CI, by exactly that constant,
#' regardless of the CI's shape. Confirmed to floating precision by
#' validate_shift_sufficiency.R's self-check 1 on both the symmetric
#' (analytic/boot_t) and asymmetric (wild) arms.
#'
#' p is recomputed via a two-sided t-test at df = max(1L, n_treated0 +
#' n_control0 - 1) for analytic/boot_t (matching run_estimators.R's
#' .re_tp() exactly), EXCEPT for "wild": a wild row's p is a genuine
#' fwildclusterboot bootstrap p-value from a fresh draw, which is not a
#' function of (att0, se0) and so cannot be honestly recomputed by a shift
#' -- it stays NA_real_, matching validate_shift_sufficiency.R's
#' CI_SHIFT_INFERENCE convention. Downstream, summarize_operating_
#' characteristics.R's .reject_flag() falls back to CI-membership rejection
#' when p is NA but the CI is finite, so a synthesized wild row's power
#' contribution is NOT silently dropped (as it would be under a bare
#' `p <= alpha`) -- see that function's docstring for the translation-
#' equivariance argument that makes the fallback valid.
#'
#' "boot" / "jack" (and any other non-whitelisted inference string) rows are
#' left with error_msg = "shift_not_reconstructable" and are never touched
#' otherwise. Rows whose own delta = 0 baseline did not converge, or whose
#' (estimator, inference, estimand, delta) cell has no fittable L_hat (no
#' calibration pairs at that delta, or truth is identically 0), get a
#' specific unfilled reason instead.
#'
#' IDEMPOTENCE / RE-SYNTHESIS SAFETY: a successfully filled row is tagged
#' error_msg = "shift_filled" (NOT NA) precisely so it can be EXCLUDED from
#' the calibration pool on any subsequent call -- a filled row satisfies
#' `delta > 0 & converged` exactly like a genuine calibration row, so without
#' this exclusion a second synthesis pass (e.g. after a partial resume) would
#' refit L_hat partly on rows that already have the FIRST pass's L_hat baked
#' into their att, contaminating the estimate. This function therefore only
#' ever operates on rows with error_msg EXACTLY equal to "shift_pending";
#' every other row (already filled, already marked unreconstructable/
#' unusable, or a genuine estimator row -- error_msg NA) is untouched, so
#' re-running this on an already-synthesized partial is a true no-op.
#'
#' ATOMICITY: writes to a `.tmp` sibling and `file.rename()`s it into place
#' (atomic on POSIX filesystems) rather than truncating partial_path
#' in-place -- a scenario's partial can represent 50-63h of compute (Della
#' job 12114571 lost exactly this way to an OOM mid-write), so a crash
#' between opening the file and finishing the write must never leave a
#' truncated or empty partial on disk. A loading sidecar
#' (`<partial>.shift_loading.csv`) is written alongside it, recording the
#' fitted L_hat(delta) per (estimator, inference, estimand, delta) -- the
#' provenance a SLURM array (subset) task needs, since it returns before
#' run_metadata.json is written (mirrors the cs_safe_patches sidecar).
#'
#' @param partial_path Path to the scenario's partial CSV (read + atomically
#'   rewritten; a no-op when there is nothing to synthesize).
#' @return Invisibly, a list: n_filled, n_unfilled, unfilled_by_reason
#'   (named integer vector), loading (tibble: estimator, inference,
#'   estimand, delta, l_hat, n_calib_pairs), changed (FALSE when there were
#'   no "shift_pending" rows at all -- the common case on every subsequent
#'   call).
#' @keywords internal
.shift_synthesize_partial <- function(partial_path) {
  d <- readr::read_csv(partial_path, col_types = .PARTIAL_COL_TYPES,
                       show_col_types = FALSE, progress = FALSE)
  d$converged  <- !is.na(d$converged) & as.logical(d$converged)
  d$error_msg  <- as.character(d$error_msg)
  d$event_time <- as.numeric(d$event_time)
  d$.rid       <- seq_len(nrow(d))
  n0 <- nrow(d)

  is_pending <- !is.na(d$error_msg) & d$error_msg == "shift_pending"
  if (!any(is_pending)) {
    return(invisible(list(n_filled = 0L, n_unfilled = 0L,
                          unfilled_by_reason = integer(0), loading = NULL,
                          changed = FALSE)))
  }

  base_keys <- c("estimator", "inference", "estimand", "event_time", "rep")
  baseline <- d %>%
    dplyr::filter(.data$delta == 0) %>%
    dplyr::distinct(dplyr::across(dplyr::all_of(base_keys)),
                    .keep_all = TRUE) %>%
    dplyr::select(dplyr::all_of(base_keys), att0 = "att", se0 = "se",
                  ci_lo0 = "ci_lo", ci_hi0 = "ci_hi",
                  converged0 = "converged",
                  n_treated_clusters0 = "n_treated_clusters",
                  n_control_clusters0 = "n_control_clusters")

  # Calibration pairs: real (converged) delta>0 rows, EXPLICITLY EXCLUDING
  # any row already tagged "shift_filled" by a prior synthesis pass (see
  # IDEMPOTENCE above), joined to their own rep's delta=0 baseline. Keyed on
  # `error_msg != "shift_filled"` rather than `is.na(error_msg)` on purpose:
  # a converged row can legitimately carry an informational (non-NA)
  # error_msg note that is NOT a synthesis artifact (today: .re_cs_cv3's
  # "note: cv3 used X/Y replicates" on a converged "jack" row) -- excluding
  # those from calibration too would be silently over-broad, and while jack
  # is not itself a reconstructable inference arm today (so no live bug),
  # keying on the specific tag makes the intent explicit for any future
  # note-emitting arm. NA-truth guard mirrors validate_shift_sufficiency.R
  # FIX 4 (defensive; truth should never be NA here since impose_effect()
  # always runs, even for shift_pending rows).
  calib <- d %>%
    dplyr::filter(.data$delta > 0, .data$converged,
                 is.na(.data$error_msg) | .data$error_msg != "shift_filled",
                 !is.na(.data$truth)) %>%
    dplyr::inner_join(baseline, by = base_keys, na_matches = "na") %>%
    dplyr::filter(!is.na(.data$converged0), .data$converged0,
                 is.finite(.data$att0), is.finite(.data$se0))

  # BLOCKER 1 fix: L_hat fit PER DELTA (not pooled across the grid) -- see
  # docstring. `delta` here is the calibration row's OWN delta (> 0); the
  # join key below includes it so a pending row is matched to the loading
  # fitted at ITS OWN delta.
  loading <- calib %>%
    dplyr::group_by(.data$estimator, .data$inference, .data$estimand,
                    .data$delta) %>%
    dplyr::summarise(
      l_hat = if (sum(.data$truth^2, na.rm = TRUE) > 0) {
        sum((.data$att - .data$att0) * .data$truth, na.rm = TRUE) /
          sum(.data$truth^2, na.rm = TRUE)
      } else NA_real_,
      n_calib_pairs = dplyr::n(),
      .groups = "drop"
    )

  pend <- d %>%
    dplyr::filter(.data$.rid %in% d$.rid[is_pending]) %>%
    dplyr::left_join(baseline, by = base_keys, na_matches = "na") %>%
    dplyr::left_join(loading,
                     by = c("estimator", "inference", "estimand", "delta")) %>%
    dplyr::mutate(
      reconstructable = .data$inference %in% .SHIFT_RECONSTRUCTABLE_INFERENCE,
      baseline_ok = !is.na(.data$converged0) & .data$converged0 &
        is.finite(.data$att0) & is.finite(.data$se0) & .data$se0 > 0 &
        is.finite(.data$ci_lo0) & is.finite(.data$ci_hi0) &
        !is.na(.data$n_treated_clusters0) & !is.na(.data$n_control_clusters0),
      truth_ok = !is.na(.data$truth),
      lhat_ok  = !is.na(.data$l_hat),
      fillable = .data$reconstructable & .data$baseline_ok &
        .data$truth_ok & .data$lhat_ok,
      fail_reason = dplyr::case_when(
        !.data$reconstructable ~ "shift_not_reconstructable",
        !.data$baseline_ok     ~ "shift_baseline_unusable",
        !.data$truth_ok        ~ "shift_truth_unavailable",
        !.data$lhat_ok         ~ "shift_l_hat_unavailable",
        TRUE                   ~ NA_character_
      ),
      df_bl     = pmax(1L, .data$n_treated_clusters0 +
                         .data$n_control_clusters0 - 1L),
      shift     = .data$l_hat * .data$truth,
      att_new   = .data$att0 + .data$shift,
      se_new    = .data$se0,
      ci_lo_new = .data$ci_lo0 + .data$shift,
      ci_hi_new = .data$ci_hi0 + .data$shift,
      p_new     = dplyr::if_else(
        .data$inference == "wild", NA_real_,
        .shift_tp(.data$att_new, .data$se_new, .data$df_bl))
    )

  fill_idx   <- pend$.rid[pend$fillable]
  unfill_idx <- pend$.rid[!pend$fillable]

  d$att[fill_idx]       <- pend$att_new[pend$fillable]
  d$se[fill_idx]        <- pend$se_new[pend$fillable]
  d$p[fill_idx]         <- pend$p_new[pend$fillable]
  d$ci_lo[fill_idx]     <- pend$ci_lo_new[pend$fillable]
  d$ci_hi[fill_idx]     <- pend$ci_hi_new[pend$fillable]
  d$converged[fill_idx] <- TRUE
  # "shift_filled", not NA -- see IDEMPOTENCE above; this is the tag that
  # keeps a re-synthesis pass from refitting L_hat on rows this pass filled.
  d$error_msg[fill_idx] <- "shift_filled"
  d$error_msg[unfill_idx] <- pend$fail_reason[!pend$fillable]

  # Post-fill invariants: BLOCKER 3's atomic write is pointless if what we
  # write is already wrong. Row count must be exactly preserved (this
  # function only ever mutates cell values, never adds/removes rows), and
  # no row may still read "shift_pending" -- every pending row above was
  # routed to either a fill or one of the fail_reason tags.
  stopifnot(
    "row count changed during synthesis" = nrow(d) == n0,
    "shift_pending rows remain after synthesis" =
      !any(!is.na(d$error_msg) & d$error_msg == "shift_pending")
  )

  d$.rid <- NULL

  # Atomic write: stream to a .tmp sibling, then rename into place
  # (POSIX rename() is atomic) -- see ATOMICITY above. A crash mid-write
  # leaves only the .tmp file corrupted; partial_path itself is untouched
  # until the rename succeeds. on.exit() removes a lingering .tmp on ANY
  # exit path from here on (normal return, error, or a failed rename that
  # already threw below) so a full-size .tmp is never orphaned beside a
  # multi-GB partial.
  tmp_path <- paste0(partial_path, ".tmp")
  on.exit(if (file.exists(tmp_path)) unlink(tmp_path), add = TRUE)
  readr::write_csv(d, tmp_path)

  # Loading sidecar written BEFORE the rename, not after: if the process
  # dies between the two, a partial that already reflects the fill (because
  # the rename below succeeded) must never be left with no synthesis
  # provenance at all -- and a partial that does NOT yet reflect the fill
  # (rename not yet reached) simply gets a sidecar one step ahead of it,
  # which is harmless (the NEXT synthesis call, finding no "shift_pending"
  # rows, is a no-op that regenerates nothing -- but the sidecar already
  # correctly describes the fill that a completed rename would produce).
  # The alternative order (sidecar after rename) has a real gap: a death
  # between the two leaves a synthesized partial (no pending rows, so a
  # later call short-circuits at `if (!any(is_pending)) return(...)`
  # BEFORE ever recomputing `loading`) whose provenance sidecar is silently
  # never regenerated.
  readr::write_csv(loading, paste0(partial_path, ".shift_loading.csv"))

  # file.rename() returns FALSE (with a warning) rather than throwing on
  # failure -- e.g. cross-filesystem rename, permissions, disk full on a
  # journaled write of the rename itself. An unchecked FALSE here would let
  # this function report n_filled > 0 and the caller log success while
  # partial_path on disk is STILL the pre-synthesis (or, worse, a mid-
  # previous-write) version -- silent data loss on a scenario that can
  # represent 50-63h of compute. Fail loud instead.
  stopifnot(
    "atomic rename of the synthesized partial failed" =
      file.rename(tmp_path, partial_path)
  )

  reason_tbl <- pend %>% dplyr::filter(!.data$fillable) %>%
    dplyr::count(.data$fail_reason)
  unfilled_by_reason <- stats::setNames(reason_tbl$n, reason_tbl$fail_reason)

  invisible(list(
    n_filled = length(fill_idx), n_unfilled = length(unfill_idx),
    unfilled_by_reason = unfilled_by_reason, loading = loading,
    changed = TRUE
  ))
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
#' @param scenarios Optional subset to run. Numeric = positions in the
#'   expanded grid (1-based, as reported by \code{expand_scenario_grid()});
#'   character = scenario_id or block \code{name} (a name selects every
#'   scenario that block expands to). NULL (default) runs the whole grid.
#'   When a subset is given the run writes ONLY per-scenario partials and
#'   skips the run-level summaries, so concurrent workers (e.g. SLURM array
#'   tasks) cannot race on the same output files. Re-run once with
#'   scenarios = NULL afterwards to aggregate: every partial is complete, so
#'   that pass only summarizes and writes.
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
                              batch_size = 25L, scenarios = NULL) {
  t_start <- Sys.time()
  cfg  <- read_power_config(config_path)
  fns  <- .ensure_sim_functions(impose_fn, estimator_fn)
  grid <- expand_scenario_grid(cfg)

  n_all  <- nrow(grid)
  subset_run <- !is.null(scenarios)
  grid <- .select_scenarios(grid, scenarios)

  if (!is.null(n_reps_override)) {
    grid$n_reps <- as.integer(n_reps_override)
    grid$estimator_reps <- rep(list(NULL), nrow(grid))
    # shift_calibration_reps does NOT automatically track n_reps once it has
    # been baked into the grid -- without this, a smoke override (small
    # n_reps_override) leaves a shift_mode scenario's calibration count at
    # whatever it was computed against the ORIGINAL (large) n_reps, e.g. 10
    # after an override to n_reps_override = 3: every rep becomes a
    # "calibration" rep (rep <= 10 is always true) and synthesis is silently
    # never exercised, defeating the purpose of a shift-mode smoke test.
    # Recompute via the SAME per-scenario default formula
    # (expand_scenario_grid()'s max(10L, ceiling(0.1*n_reps))) against the
    # NEW n_reps, then clamp into the valid [2, n_reps - 1] band (an
    # explicit run-level pin is intentionally NOT preserved across an
    # override -- it was sized for the original n_reps too).
    if (any(grid$shift_mode)) {
      resc <- as.integer(pmax(10L, ceiling(0.1 * grid$n_reps)))
      resc <- pmin(pmax(resc, 2L), grid$n_reps - 1L)
      grid$shift_calibration_reps <- ifelse(grid$shift_mode, resc,
                                            grid$shift_calibration_reps)
    }
    # n_reps is hashed, so the ids must follow the override — otherwise a
    # 3-rep smoke run would write to the same partial as a 500-rep run.
    grid <- .assign_scenario_ids(grid, cfg$base_seed)
  }

  run_name <- run_name %||% cfg$run_name %||%
    paste0("run_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  out_dir      <- .power_out_dir(run_name)
  partials_dir <- .power_out_dir(run_name, "partials")

  # Default workers: availableCores() returns 2 under `Rscript --vanilla`
  # (its environment hints are stripped), which silently collapsed the shell
  # runners to a single worker. parallel::detectCores() reads the hardware
  # directly, so take the max of the two before subtracting the headroom.
  # Inside a SLURM allocation the cgroup limit is authoritative:
  # parallel::detectCores() reports the WHOLE node (96+ on Della), so the
  # fallback below would oversubscribe an 8-cpu array task by ~12x and thrash.
  # SLURM_CPUS_PER_TASK is the only trustworthy number when it is set.
  if (is.null(workers)) {
    slurm_cpus <- suppressWarnings(
      as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", ""))
    )
    workers <- if (!is.na(slurm_cpus) && slurm_cpus > 0L) {
      slurm_cpus
    } else {
      # Outside SLURM: availableCores() returns 2 under `Rscript --vanilla`
      # (its environment hints are stripped), so fall back to the hardware.
      max(1L, max(future::availableCores(), parallel::detectCores(), 1L,
                  na.rm = TRUE) - 2L)
    }
  }
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

  # Install the CS segfault guard in the parent too: serial runs (workers = 1)
  # never enter the furrr path, and the parent evaluates estimators directly.
  if (isTRUE(cfg$cs_safe_patches)) {
    ok <- install_cs_safe_patches(TRUE, root = cfg$repo_root %||% power_repo_root())
    cat(sprintf("[%s] cs_safe_patches: reg_did_rc guard %s\n", .ts(),
                if (ok) "ACTIVE on did's call path"
                else "NOT ACTIVE (see warning above)"))
    # Only fatal when this grid actually runs CS. A twfe/did2s-only array task
    # is unaffected by the guard and must not be blocked by, say, a node
    # without DRDID installed.
    grid_has_cs <- any(vapply(grid$estimators,
                              function(e) "cs" %in% as.character(unlist(e)),
                              logical(1)))
    if (!ok && grid_has_cs) {
      stop("cs_safe_patches: TRUE but the guard is not active on did's call ",
           "path; refusing to run a CS grid that will abort mid-scenario.",
           call. = FALSE)
    }
  }

  cat(sprintf("[%s] run_scenario_grid: %d of %d scenario(s), workers = %d, run = %s\n",
              .ts(), nrow(grid), n_all, workers, run_name))
  if (subset_run) {
    cat(sprintf("[%s]   subset: %s\n", .ts(),
                paste(grid$scenario_index, collapse = ", ")))
    cat(sprintf(paste0("[%s]   partials only — run again with no subset to ",
                       "write the run-level summaries.\n"), .ts()))
  }

  panel_cache <- new.env(parent = emptyenv())
  get_panel <- function(sc) {
    key <- paste(sc$level, sc$sample, sc$covid, sc$treat_def,
                 sc$loader_anticipation, sc$quarterly, sc$time_agg,
                 sc$complete_periods_only, sep = "|")
    if (!exists(key, envir = panel_cache)) {
      assign(key,
             load_blinded_panel(
               level = sc$level, treat_def = sc$treat_def,
               anticipation = sc$loader_anticipation, sample = sc$sample,
               covid = sc$covid, quarterly = sc$quarterly,
               time_agg = sc$time_agg %||% "month",
               complete_periods_only =
                 isTRUE(sc$complete_periods_only %||% FALSE),
               config = cfg
             ),
             envir = panel_cache)
    }
    p <- get(key, envir = panel_cache)
    # Scenario-level exclusion AFTER the cache (the cache key stays panel-
    # level): excluded states vanish before schedule/template derivation.
    ex <- as.character(unlist(sc$exclude_states %||% character(0)))
    if (length(ex) > 0L) p <- p[!p$state_abb %in% ex, , drop = FALSE]
    p
  }

  for (i in seq_len(nrow(grid))) {
    sc <- as.list(grid[i, ])
    # De-listify list-columns picked up by the single-row subset.
    sc$estimators     <- unlist(sc$estimators)
    sc$effect_grid    <- unlist(sc$effect_grid)
    sc$estimator_reps <- sc$estimator_reps[[1]]
    sc$exclude_states <- as.character(unlist(sc$exclude_states %||%
                                               character(0)))

    est_reps <- .estimator_rep_counts(sc$estimators, sc$n_reps,
                                      sc$estimator_reps)
    max_reps <- max(est_reps)
    n_expected <- sum(est_reps) * length(sc$effect_grid)
    if (isTRUE(sc$shift_mode)) {
      if (!any(sc$effect_grid == 0)) {
        stop("run_scenario_grid: shift_mode requires 0 in the effect_grid ",
             "(scenario ", sc$scenario_id, ") -- the delta=0 fit is the ",
             "shift baseline for every rep.", call. = FALSE)
      }
      # shift_calibration_reps < 2 pays for every delta=0 fit and yields NA
      # loadings for every (estimator, inference, estimand, delta) group (a
      # through-origin slope needs at least 2 points to be anything but
      # exact-fit-through-one-point noise) -- reject rather than silently
      # producing an all-unfilled partial. >= max_reps means EVERY rep is a
      # calibration rep, i.e. shift mode provides zero compute savings for
      # this scenario -- also almost certainly a misconfiguration.
      if (sc$shift_calibration_reps < 2L) {
        stop("run_scenario_grid: shift_calibration_reps must be >= 2 ",
             "(scenario ", sc$scenario_id, ", got ",
             sc$shift_calibration_reps, ") -- a through-origin loading ",
             "needs at least 2 calibration pairs per delta.", call. = FALSE)
      }
      if (sc$shift_calibration_reps >= max_reps) {
        stop("run_scenario_grid: shift_calibration_reps must be < the ",
             "scenario's max rep count (scenario ", sc$scenario_id, ", got ",
             sc$shift_calibration_reps, " >= ", max_reps, ") -- every rep ",
             "would be a calibration rep, so shift mode saves nothing.",
             call. = FALSE)
      }
    }
    partial <- file.path(partials_dir, paste0(sc$scenario_id, ".csv"))
    # Batch checkpoint sidecar (2026-08-11): lists rep ids whose rows are
    # fully appended to the partial. Appended AFTER each batch's CSV append
    # succeeds, so a crash can tear at most the trailing (unlisted) batch.
    # Motivation: crashes (OOM on Della job 12114571; macOS lazyLoadDBfetch
    # bus errors) were losing entire multi-hour scenarios because the partial
    # was only written at scenario END.
    ckpt <- paste0(partial, ".done_reps")

    # Provenance sidecar for the CS guard. Deliberately NOT a column on the
    # result rows: adding one would change the flag-OFF results schema and
    # break append-on-resume against the partials already on disk. Subset
    # (SLURM array) runs return before run_metadata.json is written, so
    # without this the only on-disk record that the guard was active is an
    # opaque hash prefix -- for a flag that changes what CS returns on the
    # cells that would otherwise have killed the process.
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

    done_reps <- integer(0)
    if (resume && file.exists(partial)) {
      done <- tryCatch(
        readr::read_csv(partial, col_types = .PARTIAL_COL_TYPES,
                        show_col_types = FALSE, progress = FALSE),
        error = function(e) NULL
      )
      complete <- !is.null(done) && nrow(done) > 0L &&
        dplyr::n_distinct(paste(done$estimator, done$rep, done$delta)) >=
          n_expected
      if (complete) {
        # Shift-mode scenario whose reps are ALL present but whose
        # end-of-scenario synthesis was interrupted (e.g. a crash between
        # the batch loop finishing and .shift_synthesize_partial() running):
        # every rep is done, so fall through to synthesis-only instead of
        # skipping outright -- skipping would strand the "shift_pending"
        # rows forever (they already satisfy the completeness check above).
        n_pending <- if (isTRUE(sc$shift_mode)) {
          sum(!is.na(done$error_msg) & done$error_msg == "shift_pending")
        } else 0L
        if (n_pending == 0L) {
          cat(sprintf(
            "[%s] %s: partial complete (%d rows) — skipping (resume)\n",
            .ts(), sc$scenario_id, nrow(done)))
          if (file.exists(ckpt)) unlink(ckpt)
          next
        }
        cat(sprintf(paste0(
          "[%s] %s: partial complete but %d shift_pending row(s) remain — ",
          "running synthesis only (no reps to recompute)\n"),
          .ts(), sc$scenario_id, n_pending))
        done_reps <- seq_len(max_reps)
        if (file.exists(ckpt)) unlink(ckpt)
      } else if (!is.null(done) && file.exists(ckpt)) {
        # Batch-level resume: keep only reps recorded as fully written
        # (drops any torn trailing batch), rewrite the partial clean, and
        # compute the remaining reps below.
        done_reps <- sort(unique(as.integer(readLines(ckpt))))
        done <- done[done$rep %in% done_reps, , drop = FALSE]
        readr::write_csv(done, partial)
        cat(sprintf(
          "[%s] %s: resuming from checkpoint — %d of %d reps already done\n",
          .ts(), sc$scenario_id, length(done_reps), max_reps))
      } else {
        # Incomplete partial with no checkpoint sidecar (pre-checkpoint
        # scheme, or unreadable): start the scenario clean to avoid
        # duplicate rows from appends. The shift-loading sidecar (if any --
        # left over from an earlier completed-and-synthesized run of this
        # SAME scenario_id) describes L_hat fitted on data that is about to
        # be discarded; a stale one surviving into a fresh run would
        # misrepresent the new run's provenance.
        unlink(partial)
        unlink(paste0(partial, ".shift_loading.csv"))
        if (file.exists(ckpt)) unlink(ckpt)
      }
    } else if (file.exists(partial)) {
      unlink(partial)
      unlink(paste0(partial, ".shift_loading.csv"))
      if (file.exists(ckpt)) unlink(ckpt)
    }

    cat(sprintf(
      "[%s] %s START (%d reps x %d deltas x {%s}; design %s, %s/%s/%s%s)\n",
      .ts(), sc$scenario_id, max_reps, length(sc$effect_grid),
      paste(sc$estimators, collapse = ","), sc$design, sc$level, sc$sample,
      sc$mechanism,
      if (isTRUE(sc$shift_mode)) {
        sprintf("; shift_mode ON (calibration_reps=%d/%d)",
               sc$shift_calibration_reps, max_reps)
      } else ""))

    panel <- get_panel(sc)

    # Captured as a plain string so future exports it to parallel workers.
    power_root <- power_repo_root()
    # Likewise captured as a plain logical: the worker closure below reads it
    # to install the CS segfault guard in its own process.
    cs_safe_patches <- isTRUE(sc$cs_safe_patches)

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
      # Each worker is a separate R process with its own namespaces, so the CS
      # segfault guard must be installed per worker, not just in the parent.
      # Outside the sentinel block above: a worker reused across reps still
      # needs the check, which install_cs_safe_patches() short-circuits once
      # installed. Guarded so the flag-OFF path is byte-for-byte the old code
      # -- an unconditional call would introduce a new abort into a flag-OFF
      # run if the symbol were ever missing (e.g. a mocked estimator_fn in a
      # session where the sentinel above already exists).
      if (isTRUE(cs_safe_patches)) {
        install_cs_safe_patches(TRUE, root = power_root)
      }
      # Serial == parallel invariant: furrr(seed = TRUE) switches workers to
      # the L'Ecuyer-CMRG RNG kind, under which set.seed(seed_rep) inside
      # make_pseudo_schedule()/impose_effect() would yield different draws
      # than a serial run. Pin the kind so the explicit per-rep seeds produce
      # identical streams either way (furrr restores RNG state afterwards).
      suppressWarnings(RNGkind("Mersenne-Twister", "Inversion", "Rejection"))
      seed_rep <- power_rep_seed(cfg$base_seed, rep, sc$scenario_seed_offset)
      annotate_row <- function(res, delta) {
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
        res$time_agg         <- sc$time_agg
        res$complete_periods_only <- sc$complete_periods_only
        res$template         <- sc$template
        res$rep              <- rep
        res$delta            <- delta
        res$seed_rep         <- seed_rep
        res
      }
      # A rep whose pseudo-schedule cannot be placed yields failure rows for
      # every expected estimator x delta combo instead of aborting the whole
      # scenario (2026-08-10: one infeasible draw must not kill a 30h task;
      # the partial stays complete so resume/aggregate still work).
      sched <- tryCatch(
        make_pseudo_schedule(
          design = sc$design, panel = panel, real_schedule = real_schedule,
          treat_def = sc$treat_def, min_pre = sc$min_pre,
          min_post = sc$min_post, seed = seed_rep, template = sc$template
        ),
        error = function(e) e)
      # HYBRID CONTROL CODING (2026-08-20): under a redated treat_def
      # (maturation/ramp75), each pseudo EVENT date corresponds to a template
      # cohort whose real launch preceded it by a known lag. D1 places the
      # template as anchor + cohort OFFSETS (make_pseudo_schedules.R
      # place_template), so calendar dates shift but cohort RANK and SPACING
      # are preserved -- the lag must therefore be attached by rank, not by
      # date (a date match fails for every shifted placement). Estimators can
      # then gate CONTROL eligibility on live gambling (pseudo_launch) rather
      # than market maturity (mirrors lpdid_statepanel.R hybrid coding).
      if (!inherits(sched, "condition") &&
          !sc$treat_def %in% c("online_start_date", "first_start_date") &&
          all(c("online_start_date", sc$treat_def, "state")
              %in% names(real_schedule))) {
        rs <- real_schedule
        rs$._ev <- as.Date(rs[[sc$treat_def]])
        rs$._on <- as.Date(rs$online_start_date)
        rs$._ab <- c(state.abb, "DC")[match(rs$state,
                                            c(state.name,
                                              "District of Columbia"))]
        rs <- rs[!is.na(rs$._ev) & !is.na(rs$._on), , drop = FALSE]
        if (identical(sc$template, "panel")) {
          rs <- rs[rs$._ab %in% unique(panel$state_abb), , drop = FALSE]
        }
        if (nrow(rs) > 0L) {
          rs$._lag <- as.integer(round(as.numeric(
            difftime(rs$._ev, rs$._on, units = "days")) / 30.44))
          coh <- stats::aggregate(._lag ~ ._ev, data = rs, FUN = stats::median)
          coh <- coh[order(coh$._ev), , drop = FALSE]
          pd  <- sort(unique(as.Date(sched$pseudo_g)))
          spacing_ok <- length(pd) == nrow(coh) &&
            isTRUE(all(diff(.month_index(pd)) ==
                         diff(.month_index(coh$._ev))))
          lag_vec <- if (spacing_ok) as.integer(coh$._lag) else
            rep(as.integer(stats::median(coh$._lag)), length(pd))
          lag_by_date <- stats::setNames(pmax(lag_vec, 0L), as.character(pd))
          sched$pseudo_launch <- as.Date(sched$pseudo_g) %m-%
            months(lag_by_date[as.character(as.Date(sched$pseudo_g))])
          attr(sched, "launch_lag_rank_matched") <- spacing_ok
        }
      }
      if (inherits(sched, "condition")) {
        msg <- paste0("schedule generation failed: ", conditionMessage(sched))
        out <- list()
        for (delta in sc$effect_grid) {
          for (est in sc$estimators) {
            if (rep > est_reps[[est]]) next
            res <- .estimator_failure_row(est, msg)
            res$truth <- NA_real_
            out[[length(out) + 1L]] <- annotate_row(res, delta)
          }
        }
        return(bind_rows(out))
      }
      # spec is identical across deltas/estimators within a rep (only `est`
      # varies its contents downstream via run_estimator()'s own dispatch);
      # built once so both the brute-force and shift-mode branches share it.
      .mk_spec <- function() {
        list(anticipation   = sc$est_anticipation,
             control_group  = sc$control_group,
             outcome        = sc$outcome,
             # Defensive: .re_spec() uses modifyList(), which DELETES a key
             # whose value is NULL -- that would pass faster_mode = NULL
             # into att_gt(). Never NULL for a grid built by
             # expand_scenario_grid(), but a resumed or hand-built grid
             # lacking the column must fall back to the historical default
             # rather than error.
             cs_faster_mode = isTRUE(sc$cs_faster_mode %||% TRUE),
             lpdid_wild     = isTRUE(sc$lpdid_wild %||% FALSE),
             lpdid_anchor   = as.character(sc$lpdid_anchor %||% "event_clean"),
             lpdid_hmin     = as.integer(sc$lpdid_hmin %||% 0L),
             lpdid_post     = as.integer(sc$lpdid_post %||% 12L),
             lpdid_pmd      = as.integer(sc$lpdid_pmd %||% 3L),
             lpdid_weights  = as.character(sc$lpdid_weights %||% "ewatt"))
      }

      out <- list()

      if (!isTRUE(sc$shift_mode)) {
        # ---- Brute force (flag OFF): byte-for-byte the pre-shift-mode code.
        for (delta in sc$effect_grid) {
          sim <- fns$impose(panel, sched, mechanism = sc$mechanism,
                            shape = sc$shape, delta = delta, params = list(),
                            outcome = sc$outcome, seed = seed_rep + 1L)
          truths <- .compute_truths(sim, sched, sc$shape)
          for (est in sc$estimators) {
            if (rep > est_reps[[est]]) next
            res <- tryCatch(
              fns$estimate(sim, estimator = est, spec = .mk_spec()),
              error = function(e) .estimator_failure_row(est,
                                                         conditionMessage(e))
            )
            res <- .attach_truth(res, truths)
            out[[length(out) + 1L]] <- annotate_row(res, delta)
          }
        }
        return(bind_rows(out))
      }

      # ---- Shift mode (flag ON): delta=0 ALWAYS fully estimated (every rep
      # needs its own baseline fit + acts as the placeholder template).
      # delta>0 is fully estimated only for calibration reps
      # (rep <= shift_calibration_reps); every other rep gets a cheap
      # impose_effect() (for .compute_truths()) plus placeholder rows
      # shaped exactly like that rep's OWN delta=0 result (so CS's variable
      # dynamic-event-time row count is mirrored correctly -- (g,t) cell
      # identifiability depends on panel/schedule support, not on delta).
      # .shift_synthesize_partial() fills these in at scenario end.
      is_calibration_rep <- rep <= sc$shift_calibration_reps
      zero_idx <- which(sc$effect_grid == 0)[1]  # existence asserted above
      delta_order <- c(sc$effect_grid[zero_idx], sc$effect_grid[-zero_idx])
      templates <- list()  # per estimator: raw fns$estimate() output at delta=0

      for (delta in delta_order) {
        run_full <- delta == 0 || is_calibration_rep
        sim <- fns$impose(panel, sched, mechanism = sc$mechanism,
                          shape = sc$shape, delta = delta, params = list(),
                          outcome = sc$outcome, seed = seed_rep + 1L)
        truths <- .compute_truths(sim, sched, sc$shape)
        for (est in sc$estimators) {
          if (rep > est_reps[[est]]) next
          if (run_full) {
            res <- tryCatch(
              fns$estimate(sim, estimator = est, spec = .mk_spec()),
              error = function(e) .estimator_failure_row(est,
                                                         conditionMessage(e))
            )
            if (delta == 0) templates[[est]] <- res
            res <- .attach_truth(res, truths)
            out[[length(out) + 1L]] <- annotate_row(res, delta)
          } else {
            tmpl <- templates[[est]]
            if (is.null(tmpl) || nrow(tmpl) == 0L) {
              # delta=0 produced no rows for this estimator (should not
              # happen -- defensive): a single generic placeholder still
              # keeps the (estimator, rep, delta) triple present.
              ph <- .estimator_failure_row(est, "shift_pending")
            } else {
              ph <- tmpl
              ph$att <- NA_real_;  ph$se    <- NA_real_
              ph$p   <- NA_real_;  ph$ci_lo <- NA_real_; ph$ci_hi <- NA_real_
              ph$converged  <- FALSE
              ph$error_msg  <- "shift_pending"
              ph$runtime_s  <- NA_real_
            }
            ph <- .attach_truth(ph, truths)
            out[[length(out) + 1L]] <- annotate_row(ph, delta)
          }
        }
      }
      bind_rows(out)
    }

    reps_todo <- setdiff(seq_len(max_reps), done_reps)
    batches <- if (length(reps_todo)) {
      split(reps_todo, ceiling(seq_along(reps_todo) / batch_size))
    } else list()
    for (bi in seq_along(batches)) {
      rows_bi <- map_reps(batches[[bi]], run_one_rep)
      # Append this batch, THEN record its reps in the sidecar — a crash
      # between the two leaves a torn batch that resume drops and redoes.
      readr::write_csv(rows_bi, partial, append = file.exists(partial))
      write(batches[[bi]], ckpt, ncolumns = 1L, append = TRUE)
      cat(sprintf("[%s]   %s batch %d/%d (reps %d-%d): %d rows\n",
                  .ts(), sc$scenario_id, bi, length(batches),
                  min(batches[[bi]]), max(batches[[bi]]),
                  nrow(rows_bi)))
    }
    sc_res <- readr::read_csv(partial, col_types = .PARTIAL_COL_TYPES,
                              show_col_types = FALSE, progress = FALSE)

    if (isTRUE(sc$shift_mode)) {
      synth <- .shift_synthesize_partial(partial)
      if (isTRUE(synth$changed)) {
        cat(sprintf(paste0(
          "[%s] %s: shift synthesis — calibration_reps=%d, filled=%d, ",
          "unfilled=%d\n"),
          .ts(), sc$scenario_id, sc$shift_calibration_reps,
          synth$n_filled, synth$n_unfilled))
        if (!is.null(synth$loading) && nrow(synth$loading) > 0L) {
          for (r in seq_len(nrow(synth$loading))) {
            Lr <- synth$loading[r, ]
            cat(sprintf("[%s]   L_hat[%s/%s/%s] = %s (n_calib_pairs=%d)\n",
                        .ts(), Lr$estimator, Lr$inference, Lr$estimand,
                        if (is.na(Lr$l_hat)) "NA" else sprintf("%.6f", Lr$l_hat),
                        Lr$n_calib_pairs))
          }
        }
        if (length(synth$unfilled_by_reason) > 0L) {
          for (rn in names(synth$unfilled_by_reason)) {
            cat(sprintf("[%s]   unfilled[%s] = %d row(s)\n",
                        .ts(), rn, synth$unfilled_by_reason[[rn]]))
          }
        }
      }
    }

    if (file.exists(ckpt)) unlink(ckpt)
    cat(sprintf("[%s] %s END (%d rows -> %s)\n",
                .ts(), sc$scenario_id, nrow(sc_res), basename(partial)))
  }

  # A subset run is one worker among several (typically a SLURM array task).
  # Every scenario's partial is already on disk; stopping here means the
  # concurrent tasks never race to write the shared run-level files.
  if (subset_run) {
    cat(sprintf("[%s] DONE (subset): %d scenario partial(s) in %s\n",
                .ts(), nrow(grid), partials_dir))
    return(invisible(list(results = NULL, oc = NULL, mde = NULL,
                          pretrends = NULL, grid = grid, out_dir = out_dir)))
  }

  # ---- Stack from partials (single code path for fresh + resumed rows) ----
  partial_files <- file.path(partials_dir, paste0(grid$scenario_id, ".csv"))
  partial_files <- partial_files[file.exists(partial_files)]
  results <- purrr::map_dfr(partial_files, function(f) {
    readr::read_csv(f, col_types = .PARTIAL_COL_TYPES, show_col_types = FALSE,
                    progress = FALSE) %>%
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
