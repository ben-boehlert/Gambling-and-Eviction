################################################################################
# tests/testthat/helper-mocks.R
#
# Test-support helper (auto-sourced by testthat before the test files):
#   1. Ensures the summarization/orchestration modules are loaded (the
#      foundation modules are normally loaded by tests/run_tests.R; this
#      helper only fills gaps when tests are run some other way).
#   2. Defines CLEARLY-NAMED mock implementations of the sibling-module
#      contracts (impose_effect / run_estimator from R/power/impose_effects.R
#      and R/power/run_estimators.R) so the unit tests for the OC summarizer,
#      grid runner, and validator run standalone while those modules are
#      being written by a separate agent:
#        mock_impose_effect()  — contract: panel + e, delta_imposed,
#                                y_sim_count, y_sim (+ attrs)
#        mock_run_estimator()  — contract: one "overall" analytic row with
#                                the run_estimator column set
#   The real modules are NEVER shadowed: mocks are only ever passed
#   explicitly through the impose_fn / estimator_fn test hooks.
################################################################################

.power_test_root <- local({
  d <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  root <- NULL
  for (i in seq_len(8L)) {
    if (file.exists(file.path(d, "power_simulation_cs.R"))) { root <- d; break }
    parent <- dirname(d)
    if (identical(parent, d)) break
    d <- parent
  }
  if (is.null(root)) stop("helper-mocks.R: repository root not found.")
  root
})

# Foundation modules (only if missing — e.g. test_dir() called directly).
# They use repo-root-relative paths internally, so source from the root.
if (!exists("load_blinded_panel", mode = "function")) {
  local({
    owd <- setwd(.power_test_root)   # tests-only fallback; restored below
    on.exit(setwd(owd), add = TRUE)
    source("R/power/config.R")
    source("R/power/blindness_checks.R")
    source("R/power/load_blinded_panel.R")
    source("R/power/make_pseudo_schedules.R")
  })
}

# New modules under test (idempotent; internal source-guards are satisfied
# because the foundation is already loaded).
if (!exists("summarize_oc", mode = "function")) {
  source(file.path(.power_test_root,
                   "R/power/summarize_operating_characteristics.R"))
}
if (!exists("run_scenario_grid", mode = "function")) {
  source(file.path(.power_test_root, "R/power/run_scenario_grid.R"))
}
if (!exists("validate_simulation", mode = "function")) {
  source(file.path(.power_test_root, "R/power/validate_simulation.R"))
}

power_sim_modules_present <- function() {
  file.exists(file.path(.power_test_root, "R/power/impose_effects.R")) &&
    file.exists(file.path(.power_test_root, "R/power/run_estimators.R"))
}

# ---------------------------------------------------------------------------
# MOCK impose_effect (contract stand-in; NOT the real module)
# ---------------------------------------------------------------------------
# deterministic mechanism: y_sim = outcome + delta_imposed exactly (M2-style).
# count mechanisms: Poisson augmentation of counts for treated post cells,
#   y_sim = log1p(y_sim_count); delta = 0 injects nothing (so the validator's
#   zero-delta invariant is honest), counts stay nonnegative integers, and
#   set.seed(seed) makes the same seed reproduce the injection exactly.
mock_impose_effect <- function(panel, schedule,
                               mechanism = "deterministic",
                               shape = "step", delta = 0, params = list(),
                               outcome = "y_log1p", seed = 1L) {
  set.seed(seed)
  mi <- function(d) lubridate::year(d) * 12L + (lubridate::month(d) - 1L)
  sch <- dplyr::distinct(schedule, .data$state_abb, .data$pseudo_g)
  out <- dplyr::left_join(panel, sch, by = "state_abb")
  out$e <- ifelse(is.na(out$pseudo_g), NA_real_,
                  mi(out$month_date) - mi(out$pseudo_g))
  out$delta_imposed <- ifelse(!is.na(out$e) & out$e >= 0, delta, 0)

  if (mechanism %in% c("count_pois", "count_nb", "thinning")) {
    idx <- out$delta_imposed != 0
    add <- integer(nrow(out))
    if (any(idx)) {
      mu <- pmax(out$filings_count[idx], 1) * (exp(abs(delta)) - 1)
      add[idx] <- stats::rpois(sum(idx), lambda = mu) *
        ifelse(delta >= 0, 1L, -1L)
    }
    out$y_sim_count <- pmax(out$filings_count + add, 0)
    out$y_sim <- log1p(out$y_sim_count)
  } else {
    out$y_sim_count <- out$filings_count
    out$y_sim <- out[[outcome]] + out$delta_imposed
  }

  attr(out, "mechanism") <- mechanism
  attr(out, "shape")     <- shape
  attr(out, "delta")     <- delta
  attr(out, "params")    <- params
  attr(out, "seed")      <- seed
  attr(out, "outcome")   <- outcome
  out
}

# ---------------------------------------------------------------------------
# MOCK run_estimator (contract stand-in; NOT the real module)
# ---------------------------------------------------------------------------
# A state-level 2x2 DiD with a two-sample t on state DiD contributions:
# genuine sampling variation across pseudo-assignments (so size/power checks
# are meaningful) while remaining fast and dependency-free.
mock_run_estimator <- function(panel_sim, estimator = "twfe", spec = list()) {
  t0 <- Sys.time()
  treated_states <- unique(panel_sim$state_abb[!is.na(panel_sim$e)])
  post_start <- suppressWarnings(
    min(panel_sim$month_date[!is.na(panel_sim$e) & panel_sim$e >= 0])
  )

  d_state <- panel_sim %>%
    dplyr::mutate(post = .data$month_date >= post_start) %>%
    dplyr::group_by(.data$state_abb) %>%
    dplyr::summarise(
      d = mean(.data$y_sim[.data$post]) - mean(.data$y_sim[!.data$post]),
      .groups = "drop"
    ) %>%
    dplyr::filter(is.finite(.data$d)) %>%
    dplyr::mutate(treated = .data$state_abb %in% treated_states)

  dt <- d_state$d[d_state$treated]
  dc <- d_state$d[!d_state$treated]
  att <- mean(dt) - mean(dc)
  se  <- sqrt(stats::var(dt) / length(dt) + stats::var(dc) / length(dc))
  df  <- length(dt) + length(dc) - 2L
  p   <- 2 * stats::pt(-abs(att / se), df = df)
  crit <- stats::qt(0.975, df = df)

  tibble::tibble(
    estimator = estimator, inference = "analytic", estimand = "overall",
    event_time = NA_real_, att = att, se = se, p = p,
    ci_lo = att - crit * se, ci_hi = att + crit * se,
    n_treated_clusters = length(dt), n_control_clusters = length(dc),
    converged = is.finite(att) && is.finite(se) && se > 0,
    error_msg = NA_character_,
    runtime_s = as.numeric(difftime(Sys.time(), t0, units = "secs"))
  )
}
