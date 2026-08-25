################################################################################
# analysis/diagnostics/nullbias_verify_reconstruction.R
#
# MANDATORY VERIFICATION GATE for the null-bias decomposition
# (quality_reports/nullbias_decomposition_2026-08-25.md).
#
# Reconstructs the exact D1 pseudo-treatment schedule and delta=0 estimate for
# a handful of reps of the lpdid_shift12_gate_vwatt / _ewatt runs, using the
# framework's OWN code path (make_pseudo_schedule -> impose_effect ->
# run_estimator), driven by the seed_rep value RECORDED in the partial CSVs.
# If the reconstructed `att` does not match the recorded `att` to near
# machine precision, the decomposition in nullbias_decomposition.R is invalid
# and must not be trusted.
#
# Only writes: output/nullbias_decomposition/verification_log.csv (append via
# nullbias_decomposition.R keeps everything else untouched).
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

root <- normalizePath(rprojroot::find_root(rprojroot::has_file("CLAUDE.md")))
setwd(root)

for (mod in c("config.R", "blindness_checks.R", "load_blinded_panel.R",
              "make_pseudo_schedules.R", "impose_effects.R",
              "run_estimators.R", "run_scenario_grid.R")) {
  source(file.path("R", "power", mod))
}

RUNS <- list(
  vwatt = list(
    config = "config/power_lpdid_shift12_gate_vwatt.yml",
    partial_spliced = "output_blinded_power/lpdid_shift12_gate_vwatt/partials/Sd8aabd8f96_mde_spliced-state-s2-drop-d1-count_nb-step-y_log1p-a0-tpanel.csv",
    cfg_overrides = list()
  ),
  ewatt = list(
    config = "config/power_lpdid_shift12_gate_ewatt.yml",
    partial_spliced = "output_blinded_power/lpdid_shift12_gate_ewatt/partials/Sdc1ca7a0b5_mde_spliced-state-s2-drop-d1-count_nb-step-y_log1p-a0-tpanel.csv",
    # run_metadata.json for this run (git_rev 7aba318, 2026-08-24 15:55) shows
    # lpdid_anchor = "event" was live at execution time; the code default has
    # since moved to "event_clean" (git_rev df08995, the vwatt run). Pin the
    # historical value so the reconstruction uses the SAME estimator the
    # partial was actually fit under, not today's default.
    cfg_overrides = list(lpdid_anchor = "event")
  )
)

REPS_TO_CHECK <- c(1L, 2L, 3L, 500L, 1999L)  # 3 mandated + 2 extra for confidence

verify_one <- function(weight_arm) {
  info <- RUNS[[weight_arm]]
  cat(sprintf("\n==== Verifying %s (%s) ====\n", weight_arm, info$config))

  cfg  <- read_power_config(info$config)
  for (k in names(info$cfg_overrides)) cfg[[k]] <- info$cfg_overrides[[k]]
  grid <- expand_scenario_grid(cfg)
  grid <- grid[grid$name == "mde_spliced", , drop = FALSE]
  stopifnot(nrow(grid) == 1L)
  sc <- as.list(grid[1, ])
  sc$exclude_states <- as.character(unlist(sc$exclude_states %||% character(0)))
  cat("scenario_id:", sc$scenario_id, "\n")

  recorded <- read_csv(info$partial_spliced, show_col_types = FALSE)
  stopifnot(unique(recorded$scenario_id) == sc$scenario_id)

  real_schedule <- guarded_read_csv(cfg$schedule)
  panel <- load_blinded_panel(
    level = sc$level, treat_def = sc$treat_def,
    anticipation = sc$loader_anticipation, sample = sc$sample,
    covid = sc$covid, quarterly = sc$quarterly,
    time_agg = sc$time_agg %||% "month",
    complete_periods_only = isTRUE(sc$complete_periods_only %||% FALSE),
    config = cfg
  )
  if (length(sc$exclude_states) > 0L) {
    panel <- panel[!panel$state_abb %in% sc$exclude_states, , drop = FALSE]
  }

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
  cat("lpdid_weights spec:", spec$lpdid_weights,
      " lpdid_wild:", spec$lpdid_wild, "\n")

  out <- list()
  for (rep in REPS_TO_CHECK) {
    seed_rep_calc <- power_rep_seed(cfg$base_seed, rep, sc$scenario_seed_offset)
    seed_rep_rec  <- unique(recorded$seed_rep[recorded$rep == rep])
    stopifnot(length(seed_rep_rec) == 1L)
    seed_match <- identical(as.integer(seed_rep_calc), as.integer(seed_rep_rec))

    sched <- make_pseudo_schedule(
      design = sc$design, panel = panel, real_schedule = real_schedule,
      treat_def = sc$treat_def, min_pre = sc$min_pre, min_post = sc$min_post,
      seed = seed_rep_rec, template = sc$template
    )

    # HYBRID CONTROL CODING — mirrors run_scenario_grid.R:1375-1414 verbatim.
    if (!sc$treat_def %in% c("online_start_date", "first_start_date") &&
        all(c("online_start_date", sc$treat_def, "state") %in% names(real_schedule))) {
      rs <- real_schedule
      rs$._ev <- as.Date(rs[[sc$treat_def]])
      rs$._on <- as.Date(rs$online_start_date)
      rs$._ab <- c(state.abb, "DC")[match(rs$state,
                                          c(state.name, "District of Columbia"))]
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
          isTRUE(all(diff(.month_index(pd)) == diff(.month_index(coh$._ev))))
        lag_vec <- if (spacing_ok) as.integer(coh$._lag) else
          rep(as.integer(stats::median(coh$._lag)), length(pd))
        lag_by_date <- stats::setNames(pmax(lag_vec, 0L), as.character(pd))
        sched$pseudo_launch <- as.Date(sched$pseudo_g) %m-%
          months(lag_by_date[as.character(as.Date(sched$pseudo_g))])
      }
    }

    sim <- impose_effect(panel, sched, mechanism = sc$mechanism,
                         shape = sc$shape, delta = 0, params = list(),
                         outcome = sc$outcome, seed = seed_rep_rec + 1L)

    for (est in c("twfe", "lpdid")) {
      res <- tryCatch(run_estimator(sim, estimator = est, spec = spec),
                      error = function(e) e)
      if (inherits(res, "condition")) {
        out[[length(out) + 1L]] <- tibble(
          weight_arm = weight_arm, rep = rep, estimator = est,
          att_recon = NA_real_, att_recorded = NA_real_,
          abs_diff = NA_real_, seed_match = seed_match,
          note = paste("estimator error:", conditionMessage(res)))
        next
      }
      att_recon <- res$att[res$inference == "analytic" & res$estimand == "simple"][1]
      att_rec <- unique(recorded$att[recorded$rep == rep &
                                       recorded$estimator == est &
                                       recorded$inference == "analytic"])
      out[[length(out) + 1L]] <- tibble(
        weight_arm = weight_arm, rep = rep, estimator = est,
        att_recon = att_recon, att_recorded = att_rec[1],
        abs_diff = abs(att_recon - att_rec[1]), seed_match = seed_match,
        note = NA_character_)
    }
  }
  bind_rows(out)
}

results <- bind_rows(lapply(names(RUNS), verify_one))
print(results, n = 100)

dir.create("output/nullbias_decomposition", recursive = TRUE, showWarnings = FALSE)
write_csv(results, "output/nullbias_decomposition/verification_log.csv")

max_diff <- max(results$abs_diff, na.rm = TRUE)
cat(sprintf("\nMax |att_recon - att_recorded| across %d checks: %.3e\n",
           nrow(results), max_diff))
cat(sprintf("All seed_rep matches: %s\n", all(results$seed_match)))
if (max_diff > 1e-6) {
  stop("VERIFICATION FAILED: reconstruction does not match recorded att to ",
       "near machine precision. Do not proceed to decomposition.", call. = FALSE)
} else {
  cat("VERIFICATION PASSED.\n")
}
