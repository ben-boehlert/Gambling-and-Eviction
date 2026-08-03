################################################################################
# R/power/validate_simulation.R
#
# BHNS-style validation of the simulation engine on REAL blinded data
# (POWER_SIMULATION_DESIGN.md §13), plus the §17 invariant re-checks.
#
# Simplified Black-Hollingsworth-Nunes-Simon reproduction:
#   - S1 strict-universal blinded panel (state level, anticipation = 0; S1
#     ends 2018-04, so the COVID filter is irrelevant — "keep").
#   - Common-date pseudo-treatment: half the states are randomly assigned a
#     single common pseudo date chosen so that >= 12 pre months and >= 6 post
#     months exist within S1. (Common-date assignment is used ONLY here,
#     never as a primary design — design §8.)
#   - Effect injection over a small grid with count-based Poisson
#     augmentation (the hypothesized effect direction is an INCREASE, so we
#     augment rather than thin — design §9 note on the BHNS mechanism).
#   - TWFE re-estimation; power = rejection frequency.
#
# Verifies: (a) size at delta = 0 within loose exact-binomial bounds,
# (b) power monotone nondecreasing in delta (one inversion within MC noise
# allowed), (c) a finite interpolated MDE whenever power crosses 0.80.
#
# Writes validation_report.md + validation_results.csv under
# output_blinded_power/validation/ (via the guarded output-path helper only).
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
if (!exists(".ensure_sim_functions", mode = "function")) {
  source("R/power/run_scenario_grid.R")
}

#' Record one validation check
#' @keywords internal
.val_check <- function(check, pass, detail = "") {
  tibble::tibble(check = check, pass = isTRUE(pass),
                 detail = as.character(detail))
}

#' Validate the simulation engine against the BHNS template (design §13)
#'
#' @param config Power config list (default: read_power_config()).
#' @param n_reps Replications per effect-grid point (default 25, quick tier).
#' @param seed Base seed; per-rep seeds follow the project convention
#'   seed + 10007 * rep.
#' @param out_dir Output directory; must resolve under output_blinded_power/
#'   (default: output_blinded_power/validation/).
#' @param effect_grid Proportional-effect grid (default c(0, .05, .10, .20)).
#' @param min_pre,min_post Support required around the common pseudo date.
#' @param impose_fn,estimator_fn Test hooks (mock implementations of the
#'   sibling-module contracts); default NULL = lazily source the real
#'   R/power/impose_effects.R and R/power/run_estimators.R, with a clear
#'   error if they have not been written yet.
#' @return list(pass = TRUE/FALSE, checks = tibble, power_curve, mde,
#'   results, out_dir).
#' @export
validate_simulation <- function(config = read_power_config(),
                                n_reps = 25L,
                                seed = 20260723L,
                                out_dir = NULL,
                                effect_grid = c(0, 0.05, 0.10, 0.20),
                                min_pre = 12L, min_post = 6L,
                                impose_fn = NULL, estimator_fn = NULL) {
  t0 <- Sys.time()
  n_reps <- as.integer(n_reps)
  fns <- .ensure_sim_functions(impose_fn, estimator_fn)
  if (is.null(out_dir)) out_dir <- .power_out_dir("validation")

  # Guard up front: out_dir must resolve under output_blinded_power/.
  .norm <- function(p) sub("/+$", "",
                           normalizePath(p, winslash = "/", mustWork = FALSE))
  root_n <- .norm(.power_out_root())
  out_n  <- .norm(out_dir)
  if (!identical(out_n, root_n) &&
      !startsWith(paste0(out_n, "/"), paste0(root_n, "/"))) {
    stop("Blindness violation: validate_simulation out_dir must resolve ",
         "under ", power_paths()$output_root, " — got: ", out_dir,
         call. = FALSE)
  }

  cat(sprintf("[%s] validate_simulation: n_reps = %d per grid point %s\n",
              format(Sys.time(), "%H:%M:%S"), n_reps,
              paste0("{", paste(effect_grid, collapse = ", "), "}")))

  # ---- Panel: S1 strict-universal, state level, anticipation 0 ------------
  panel <- load_blinded_panel(level = "state", treat_def = "online_start_date",
                              anticipation = 0L, sample = "S1",
                              covid = "keep", config = config)
  # Design §7 defines S1 as 2016-01 .. 2018-04. The loader caps only the
  # upper end (universal cutoff), and the state panel reaches back before
  # 2016 for some states, which makes the raw S1 unbalanced with long
  # heterogeneous pre-periods. Apply the documented lower bound here
  # (dropping additional untreated months is always blindness-safe).
  s1_start <- as.Date(config$s1_start %||% "2016-01-01")
  panel <- panel %>% filter(.data$month_date >= s1_start)
  checks <- list()

  # ---- §17 invariant re-checks --------------------------------------------
  sched_csv <- .load_gambling_schedule(config$schedule, "online_start_date")
  checks[["assert_blinded"]] <- tryCatch({
    assert_blinded(panel, sched_csv, anticipation_months = 0L,
                   universal_cutoff = config$universal_cutoff)
    .val_check("assert_blinded_on_loaded_panel", TRUE,
               sprintf("%d rows, %d states, %s..%s", nrow(panel),
                       dplyr::n_distinct(panel$state_abb),
                       min(panel$month_date), max(panel$month_date)))
  }, error = function(e) {
    .val_check("assert_blinded_on_loaded_panel", FALSE, conditionMessage(e))
  })

  checks[["forbidden_guard"]] <- tryCatch({
    r <- tryCatch(assert_no_forbidden_paths("output/anything.csv"),
                  error = function(e) "blocked")
    .val_check("forbidden_path_guard_blocks_output",
               identical(r, "blocked"),
               "assert_no_forbidden_paths('output/...') must error")
  }, error = function(e) {
    .val_check("forbidden_path_guard_blocks_output", FALSE,
               conditionMessage(e))
  })

  # ---- Common pseudo date with >= min_pre pre and >= min_post post months --
  months_avail <- sort(unique(panel$month_date))
  n_m <- length(months_avail)
  elig_idx <- seq_len(n_m)
  elig_idx <- elig_idx[elig_idx >= (min_pre + 1L) &
                         elig_idx <= (n_m - min_post + 1L)]
  if (length(elig_idx) == 0L) {
    stop("validate_simulation: S1 panel (", n_m, " months) cannot support ",
         "min_pre = ", min_pre, " and min_post = ", min_post, ".",
         call. = FALSE)
  }
  set.seed(seed)
  common_date <- months_avail[sample(elig_idx, 1L)]

  states <- sort(unique(panel$state_abb))
  n_half <- floor(length(states) / 2)

  # ---- One-off injection invariants (checked before the main loop) --------
  sched_probe <- tibble::tibble(
    state_abb = sort(states)[seq_len(n_half)], pseudo_g = common_date
  )
  probe0 <- tryCatch(
    fns$impose(panel, sched_probe, mechanism = "count_pois", shape = "step",
               delta = 0, params = list(), outcome = "y_log1p", seed = seed),
    error = function(e) e
  )
  probe1 <- tryCatch(
    fns$impose(panel, sched_probe, mechanism = "count_pois", shape = "step",
               delta = 0.10, params = list(), outcome = "y_log1p",
               seed = seed),
    error = function(e) e
  )
  probe1b <- tryCatch(
    fns$impose(panel, sched_probe, mechanism = "count_pois", shape = "step",
               delta = 0.10, params = list(), outcome = "y_log1p",
               seed = seed),
    error = function(e) e
  )

  if (inherits(probe0, "error") || inherits(probe1, "error")) {
    msg <- conditionMessage(if (inherits(probe0, "error")) probe0 else probe1)
    checks[["inject"]] <- .val_check("effect_injection_runs", FALSE, msg)
  } else {
    checks[["zero_delta"]] <- .val_check(
      "zero_delta_leaves_outcomes_identical",
      isTRUE(all(probe0$y_sim == panel$y_log1p)) &&
        isTRUE(all(probe0$y_sim_count == panel$filings_count)),
      "delta = 0 with count_pois must inject nothing"
    )
    checks[["nonneg_int"]] <- .val_check(
      "count_augmentation_nonnegative_integer",
      all(probe1$y_sim_count >= 0, na.rm = TRUE) &&
        all(probe1$y_sim_count == round(probe1$y_sim_count), na.rm = TRUE),
      sprintf("min y_sim_count = %s", min(probe1$y_sim_count, na.rm = TRUE))
    )
    checks[["seed_repro"]] <- .val_check(
      "same_seed_identical_injection",
      !inherits(probe1b, "error") &&
        isTRUE(all.equal(probe1$y_sim, probe1b$y_sim)),
      "impose_effect twice with the same seed must match exactly"
    )
  }
  checks[["state_const"]] <- .val_check(
    "pseudo_treatment_constant_within_state",
    nrow(sched_probe) == dplyr::n_distinct(sched_probe$state_abb),
    "one pseudo date per state"
  )

  # ---- BHNS loop: rep x delta ---------------------------------------------
  results <- purrr::map_dfr(seq_len(n_reps), function(rep) {
    seed_rep <- as.integer(seed) + 10007L * rep
    set.seed(seed_rep)
    treated <- sample(states, n_half)
    sched <- tibble::tibble(state_abb = treated, pseudo_g = common_date)

    purrr::map_dfr(effect_grid, function(delta) {
      sim <- fns$impose(panel, sched, mechanism = "count_pois",
                        shape = "step", delta = delta, params = list(),
                        outcome = "y_log1p", seed = seed_rep + 1L)
      truths <- .compute_truths(sim, sched, "step")
      res <- tryCatch(
        fns$estimate(sim, estimator = "twfe", spec = list()),
        error = function(e) .estimator_failure_row("twfe",
                                                   conditionMessage(e))
      )
      res <- .attach_truth(res, truths)
      res$scenario_id <- "VALIDATION_BHNS"
      res$rep <- rep
      res$delta <- delta
      res$seed_rep <- seed_rep
      res
    })
  })

  # ---- Operating characteristics ------------------------------------------
  # "simple" is run_estimators.R's label for the overall aggregation.
  ov <- results %>%
    filter(.data$estimand %in% c("overall", "simple"),
           .data$inference == "analytic" | is.na(.data$inference)) %>%
    mutate(converged = !is.na(.data$converged) & .data$converged)
  power_curve <- ov %>%
    group_by(.data$delta) %>%
    summarise(
      n_reps = dplyr::n(),
      n_converged = sum(.data$converged),
      power = mean(.data$p[.data$converged] <= 0.05, na.rm = TRUE),
      mean_att = mean(.data$att[.data$converged], na.rm = TRUE),
      mean_truth = mean(.data$truth[.data$converged], na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(.data$delta)

  # (a) Size at delta = 0. Loose bound 0.15, widened if needed to the exact
  # binomial 97.5th percentile under a true 5% size with n_reps draws
  # (e.g. n_reps = 25: qbinom(.975, 25, .05) = 3 -> 3/25 = 0.12).
  size <- power_curve$power[power_curve$delta == 0]
  size <- if (length(size) == 1L) size else NA_real_
  binom_ub <- stats::qbinom(0.975, n_reps, 0.05) / n_reps
  size_bound <- max(0.15, binom_ub)
  checks[["size"]] <- .val_check(
    "size_at_null_within_bounds",
    !is.na(size) && size >= 0 && size <= size_bound,
    sprintf("size = %.3f; bound = [0, %.3f] (exact binomial 97.5%% at true 5%% with %d reps = %.3f)",
            size, size_bound, n_reps, binom_ub)
  )

  # (b) Monotone nondecreasing power (one inversion within MC noise allowed).
  pw <- power_curve$power
  mc_tol <- 2 * sqrt(0.25 / n_reps)
  inversions <- sum(diff(pw) < -mc_tol, na.rm = TRUE)
  checks[["monotone"]] <- .val_check(
    "power_monotone_nondecreasing",
    inversions <= 1L,
    sprintf("power = {%s}; inversions beyond MC tol %.3f: %d (<= 1 allowed)",
            paste(sprintf("%.2f", pw), collapse = ", "), mc_tol, inversions)
  )

  # (c) MDE interpolation finite whenever power crosses 0.80.
  mde <- .mde_from_curve(power_curve$delta, power_curve$power, 0.80)
  crosses <- any(pw >= 0.80, na.rm = TRUE)
  checks[["mde"]] <- .val_check(
    "mde_finite_if_power_crosses_80",
    !crosses || is.finite(mde$mde),
    sprintf("crosses 0.80: %s; mde = %s (%s)", crosses,
            format(mde$mde, digits = 4), mde$reason)
  )

  checks[["failures"]] <- .val_check(
    "estimator_failure_rate_below_5pct",
    mean(!ov$converged) <= 0.05,
    sprintf("failure rate = %.3f", mean(!ov$converged))
  )

  checks_tbl <- bind_rows(checks)
  pass <- all(checks_tbl$pass)

  # ---- Write report + results (out_dir guarded at function entry) ---------
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  results_path <- file.path(out_dir, "validation_results.csv")
  report_path  <- file.path(out_dir, "validation_report.md")
  readr::write_csv(results, results_path)

  rpt <- c(
    "# Simulation-Engine Validation Report (BHNS-style, design doc §13)",
    "",
    sprintf("- Date: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    sprintf("- Overall: **%s**", if (pass) "PASS" else "FAIL"),
    sprintf("- Panel: S1 strict-universal, state level, anticipation = 0, %d states, months %s..%s",
            dplyr::n_distinct(panel$state_abb),
            min(panel$month_date), max(panel$month_date)),
    sprintf("- Common pseudo date: %s (seeded draw; >= %d pre / >= %d post months)",
            common_date, min_pre, min_post),
    sprintf("- Pseudo-treated per rep: %d of %d states (random half)",
            n_half, length(states)),
    "- Mechanism: count_pois augmentation (hypothesized effect is an increase)",
    sprintf("- Estimator: TWFE; n_reps = %d per grid point; base seed = %d",
            n_reps, as.integer(seed)),
    sprintf("- Runtime: %.1f min",
            as.numeric(difftime(Sys.time(), t0, units = "mins"))),
    "",
    "## Power curve (alpha = 0.05)",
    "",
    "| delta | n_reps | converged | power | mean ATT | mean truth |",
    "|---|---|---|---|---|---|",
    sprintf("| %.2f | %d | %d | %.3f | %.4f | %.4f |",
            power_curve$delta, power_curve$n_reps, power_curve$n_converged,
            power_curve$power, power_curve$mean_att, power_curve$mean_truth),
    "",
    sprintf("MDE (80%% power, local-linear interpolation): %s (%s)",
            format(mde$mde, digits = 4), mde$reason),
    "",
    "## Checks",
    "",
    "| check | pass | detail |",
    "|---|---|---|",
    sprintf("| %s | %s | %s |", checks_tbl$check,
            ifelse(checks_tbl$pass, "PASS", "FAIL"),
            gsub("\\|", "/", checks_tbl$detail)),
    "",
    "_Size bound note: with few replications the exact binomial acceptance",
    "region under a true 5% size is wide; the bound reported in the size",
    "check is max(0.15, qbinom(0.975, n_reps, 0.05)/n_reps)._",
    "",
    "_All inputs via load_blinded_panel(); outputs contain simulated operating",
    "characteristics only (blindness protocol §8)._"
  )
  writeLines(rpt, report_path)

  cat(sprintf("[%s] validate_simulation: %s (report: %s)\n",
              format(Sys.time(), "%H:%M:%S"),
              if (pass) "PASS" else "FAIL", report_path))

  list(pass = pass, checks = checks_tbl, power_curve = power_curve,
       mde = mde, results = results, out_dir = out_dir)
}
