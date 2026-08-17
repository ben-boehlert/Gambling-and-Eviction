################################################################################
# R/power/config.R
#
# Configuration loading and canonical path definitions for the blinded
# power-simulation framework. Governed by
# docs/methodology/POWER_SIMULATION_BLINDNESS_PROTOCOL.md (§4 cutoffs) and
# POWER_SIMULATION_DESIGN.md (§16 module contract).
#
# All paths are relative to the repository root (the working directory is
# assumed to be the repo root; no setwd() is ever used).
################################################################################

suppressPackageStartupMessages({
  library(rlang)
})

#' Locate the repository root
#'
#' Walks up from \code{start} until it finds the directory containing
#' \code{power_simulation_cs.R}. Makes the framework robust to the working
#' directory (e.g. testthat sets it to tests/testthat).
#'
#' @param start Directory to start from (default: getwd()).
#' @return Absolute path to the repository root.
#' @export
power_repo_root <- function(start = getwd()) {
  d <- normalizePath(start, winslash = "/", mustWork = FALSE)
  for (i in seq_len(12L)) {
    if (file.exists(file.path(d, "power_simulation_cs.R"))) return(d)
    parent <- dirname(d)
    if (identical(parent, d)) break
    d <- parent
  }
  stop("Could not locate repository root (power_simulation_cs.R) from: ",
       start, call. = FALSE)
}

# Resolve a possibly-relative path against the repo root.
.power_abspath <- function(p, root = power_repo_root()) {
  if (grepl("^(/|[A-Za-z]:)", p)) p else file.path(root, p)
}

#' Canonical data + output paths for the blinded framework
#'
#' Central definition of the (only) data files the framework may read and the
#' single output root it may write to. Everything else is off-limits per the
#' blindness protocol.
#'
#' @return Named list of relative paths.
#' @export
power_paths <- function() {
  list(
    repo_marker  = "power_simulation_cs.R",
    county_panel = "data/raw/monthly_county_data_download.csv",
    state_panel  = "data/raw/state_month_panel_with_treatment.csv",
    schedule     = "data/raw/sports_gambling_legalization_dates.csv",
    output_root  = "output_blinded_power/"
  )
}

#' Read and validate a power-simulation YAML config
#'
#' Loads a scenario config with \code{yaml::read_yaml}, fills the documented
#' protocol defaults (anticipation window, cutoffs, COVID window, base seed,
#' data paths), validates that the required scenario axes are present, and
#' returns a named list with dates coerced to \code{Date}.
#'
#' Documented defaults (POWER_SIMULATION_BLINDNESS_PROTOCOL.md §4):
#'   anticipation_months = 6, universal_cutoff = "2018-05-31",
#'   covid_drop = c("2020-03-01", "2021-07-31"), base_seed = 20260723,
#'   panel_floor = "2016-01-01" (see below), plus the canonical data/output
#'   paths from \code{power_paths()}.
#'
#' \code{panel_floor}: the raw \code{state_month_panel_with_treatment.csv}
#' includes 4 states with legacy data reaching back to 2012-01, while the rest
#' of the panel (and the county panel) starts 2016-01 (design doc §7's
#' documented ETS panel start; audit F12). Mixing 8 extra years of unbalanced
#' pre-history into just those states would silently change every calibration
#' sample's composition (S1 would gain ~50 extra months for 4 states only) and
#' was observed to inflate TWFE's null rejection rate in the BHNS-style
#' validation. \code{load_blinded_panel()} applies this floor uniformly to
#' both county and state panels before any sample/cutoff logic, so every
#' sample matches its documented month count.
#'
#' @param path Path to the YAML config (default: config/power_validation.yml).
#' @return Named list of resolved config values.
#' @export
read_power_config <- function(path = NULL) {
  root <- power_repo_root()
  if (is.null(path)) path <- file.path(root, "config/power_validation.yml")
  if (!file.exists(path)) path <- .power_abspath(path, root)
  if (!file.exists(path)) {
    stop("Power config not found: ", path, call. = FALSE)
  }

  raw <- yaml::read_yaml(path)
  if (is.null(raw)) raw <- list()

  paths <- power_paths()
  defaults <- list(
    anticipation_months = 6L,
    universal_cutoff    = "2018-05-31",
    covid_drop          = c("2020-03-01", "2021-07-31"),
    panel_floor         = "2016-01-01",
    base_seed           = 20260723L,
    # CS segfault guard, OFF by default so existing runs stay bit-identical.
    # TRUE installs patches/reg_did_rc_safe.R over DRDID:::reg_did_rc, which
    # returns a structured NA for empty design matrices instead of aborting
    # the R process. Without it, did::att_gt() -> run_DRDID() segfaults on
    # roughly 1 rep in 4 of this design (2026-08-17), killing the worker and
    # the whole scenario; the abort is C-level, so no tryCatch can catch it.
    # Hashed into the scenario id ONLY when TRUE (see .scenario_identity_string)
    # so patched and unpatched partials can never be silently mixed.
    cs_safe_patches     = FALSE,
    # `faster_mode` argument to did::att_gt(). TRUE preserves the framework's
    # historical default. On the D1 state design TRUE fails outright --
    # att_gt() returns "singular matrix due to not enough control units. Try
    # changing faster_mode=FALSE" on 100% of probed reps (2026-08-17), the same
    # failure a prior session hit on 2026-08-11 and worked around locally in
    # analysis/diagnostics/cs_cv3_calibration_state.R without ever updating the
    # framework. FALSE is the slower path; measure before budgeting cluster
    # time. Hashed into the scenario id only when non-default AND the scenario
    # runs CS (see .scenario_identity_string).
    cs_faster_mode      = TRUE,
    # Shift-mode shortcut (validated 2026-08-17: analysis/diagnostics/
    # validate_shift_sufficiency.R — every estimator here is linear in the
    # outcome, so a rep's delta=0 fit plus a fitted loading L_hat reproduces
    # the whole effect grid to <=0.003 power points under count_nb).
    # OFF by default so an existing run's behavior is bit-for-bit unchanged.
    # See run_scenario_grid.R's calibration-subset implementation.
    shift_mode              = FALSE,
    # NULL = compute per-scenario as max(10L, ceiling(0.1 * n_reps)) in
    # expand_scenario_grid() (each block may have its own n_reps). An
    # explicit value here pins the SAME calibration count for every scenario
    # in the run instead.
    shift_calibration_reps  = NULL,
    county_panel        = paths$county_panel,
    state_panel         = paths$state_panel,
    schedule            = paths$schedule,
    output_root         = paths$output_root
  )

  cfg <- utils::modifyList(defaults, raw)

  required <- c("level", "sample", "treat_def", "designs",
                "effect_grid", "n_reps", "estimators")
  missing_fields <- setdiff(required, names(cfg))
  if (length(missing_fields) > 0L) {
    stop("Power config '", path, "' missing required field(s): ",
         paste(missing_fields, collapse = ", "), call. = FALSE)
  }

  # Coerce documented date fields.
  cfg$universal_cutoff <- as.Date(cfg$universal_cutoff)
  cfg$panel_floor      <- as.Date(cfg$panel_floor)
  cfg$covid_drop       <- as.Date(unlist(cfg$covid_drop))
  if (length(cfg$covid_drop) != 2L || any(is.na(cfg$covid_drop))) {
    stop("covid_drop must be two parseable dates (start, end).", call. = FALSE)
  }
  cfg$anticipation_months <- as.integer(cfg$anticipation_months)
  cfg$base_seed           <- as.integer(cfg$base_seed)

  cfg$cs_safe_patches <- isTRUE(as.logical(cfg$cs_safe_patches))
  # NULL/NA must fall back to the documented default (TRUE), not to FALSE, so a
  # config that omits the key keeps historical behavior.
  cfg$cs_faster_mode <- if (is.null(cfg$cs_faster_mode) ||
                            is.na(as.logical(cfg$cs_faster_mode))) {
    TRUE
  } else as.logical(cfg$cs_faster_mode)

  cfg$shift_mode <- isTRUE(as.logical(cfg$shift_mode %||% FALSE))
  # Left NULL when unset — the per-scenario 10%-of-n_reps default is computed
  # in expand_scenario_grid() (needs each block's own n_reps, not just the
  # top-level default). An explicit value here is a fixed override applied
  # to every scenario in the run.
  cfg$shift_calibration_reps <- if (is.null(cfg$shift_calibration_reps)) {
    NULL
  } else {
    as.integer(cfg$shift_calibration_reps)
  }

  # Resolve data paths against the repo root so the loader is wd-independent.
  cfg$county_panel <- .power_abspath(cfg$county_panel, root)
  cfg$state_panel  <- .power_abspath(cfg$state_panel, root)
  cfg$schedule     <- .power_abspath(cfg$schedule, root)
  cfg$repo_root    <- root

  cfg
}
