#!/usr/bin/env Rscript
################################################################################
# analysis/cheap_sims/02_run_cheap_grid.R
#
# Checkpointed Monte Carlo driver for Sims 1-3.
#
# Per replication: one calendar-preserving placebo schedule, then one CS fit
# per DGP cell, each decomposed into full / covid_clean / pre_covid /
# post_covid / cross_covid aggregates (Sim 1 = delta 0; Sim 2 = ramp deltas;
# Sim 2B = ramp + 6-month outcome lag; ramp-vs-step diagnostic = step deltas;
# Sim 3 = the design decomposition of all of the above).
#
# Seeds: base_seed + 10007*rep + 101*SCENARIO (framework convention;
# SCENARIO = 902, distinct from cs_cv3_calibration's 901).
#
# Env knobs: N_REPS (250), N_CORES (detectCores-2), BATCH (2*N_CORES),
#            CHEAP_OUT_DIR, plus the 00_common.R config knobs.
# Results append per batch to <out_dir>/results_raw.csv; safe to kill/resume.
#
# Run from repo root:
#   N_REPS=24 Rscript analysis/cheap_sims/02_run_cheap_grid.R   # smoke
#   N_REPS=250 Rscript analysis/cheap_sims/02_run_cheap_grid.R
################################################################################

source("analysis/cheap_sims/00_common.R")
suppressPackageStartupMessages(library(parallel))

cfg <- cheap_config()
N_REPS    <- .cs_envint("N_REPS", 250L)
REP_START <- .cs_envint("CHEAP_REP_START", 1L)   # Della shard support
N_CORES <- .cs_envint("N_CORES", max(1L, parallel::detectCores() - 2L))
BATCH   <- .cs_envint("BATCH", 2L * N_CORES)
SCENARIO <- 902L

dir.create(cfg$out_dir, recursive = TRUE, showWarnings = FALSE)
RAW   <- file.path(cfg$out_dir, "results_raw.csv")
SCHED <- file.path(cfg$out_dir, "placebo_schedules_log.csv")

# Cache the invariant preprocessing; rebuild if this out_dir has no cache yet
# (e.g. a fresh CHEAP_OUT_DIR for a smoke run).
.pan_rds   <- file.path(cfg$out_dir, "design_panel.rds")
.ramps_rds <- file.path(cfg$out_dir, "exposure_ramps.rds")
if (!file.exists(.pan_rds))   saveRDS(build_sim_state_panel(cfg), .pan_rds)
if (!file.exists(.ramps_rds)) saveRDS(build_exposure_ramps(cfg), .ramps_rds)
pan   <- readRDS(.pan_rds)
ramps <- readRDS(.ramps_rds)
tmpl  <- placebo_template(pan$states)

# Full delta curve for the headline ramp DGP; the lag-6 and step arms run at
# the 2.5% benchmark only (measured ~10 s/fit effective throughput makes the
# full 10-cell grid ~7 h at 250 reps; the spec's "add other effect sizes only
# if runtime is low" bites). Smoke runs at N_REPS<=24 keep the full grid.
DGPS <- if (.cs_envint("N_REPS", 250L) <= 24L) bind_rows(
  tibble(shape = "expo_ramp", delta = 0,                    lag = 0L),
  tibble(shape = "expo_ramp", delta = c(.01, .025, .05),    lag = 0L),
  tibble(shape = "expo_ramp", delta = c(.01, .025, .05),    lag = 6L),
  tibble(shape = "step",      delta = c(.01, .025, .05),    lag = 0L)
) else bind_rows(
  tibble(shape = "expo_ramp", delta = 0,                    lag = 0L),
  tibble(shape = "expo_ramp", delta = c(.01, .025, .05),    lag = 0L),
  tibble(shape = "expo_ramp", delta = .025,                 lag = 6L),
  tibble(shape = "step",      delta = .025,                 lag = 0L)
)

cat(sprintf("cheap grid | reps=%d cores=%d batch=%d dgps=%d fits/rep\nout: %s\n",
            N_REPS, N_CORES, BATCH, nrow(DGPS), RAW))

one_rep <- function(rep) {
  seed_rep <- cfg$base_seed + 10007L * rep + 101L * SCENARIO
  sched <- make_calendar_placebo(pan$sim, tmpl, cfg$min_pre, cfg$min_post,
                                 seed = seed_rep)
  dropped <- attr(sched, "dropped_cohorts")
  sched_log <- sched %>%
    mutate(rep = rep, seed = seed_rep,
           n_dropped_slots = sum(dropped$needed - dropped$filled))

  rows <- map_dfr(seq_len(nrow(DGPS)), function(j) {
    dg <- as.list(DGPS[j, ])
    tryCatch(
      run_one_sim(pan$sim, sched, ramps, dgp = dg,
                  seed = seed_rep + 7L * j, cfg = cfg),
      error = function(e) tibble(
        design = "full", att = NA_real_, se = NA_real_, p = NA_real_,
        ci_lo = NA_real_, ci_hi = NA_real_, true_att = NA_real_,
        n_cells = NA_integer_, n_cohorts = NA_integer_,
        n_treated_states = NA_integer_, shape = dg$shape, delta = dg$delta,
        lag = dg$lag, converged = FALSE, error_msg = conditionMessage(e),
        runtime_s = NA_real_)
    )
  }) %>%
    mutate(rep = rep, seed = seed_rep,
           n_placebo_states = nrow(sched),
           n_dropped_slots = sum(dropped$needed - dropped$filled))
  list(rows = rows, sched = sched_log)
}

done <- if (file.exists(RAW))
  unique(suppressMessages(read_csv(RAW, show_col_types = FALSE))$rep) else integer(0)
todo <- setdiff(seq.int(REP_START, N_REPS), done)
if (length(done)) cat(sprintf("resuming: %d reps already done\n", length(done)))

t_start <- Sys.time()
batches <- split(todo, ceiling(seq_along(todo) / BATCH))

for (bi in seq_along(batches)) {
  b <- batches[[bi]]
  raw <- mclapply(b, function(r) {
    tryCatch(one_rep(r), error = function(e)
      list(rows = tibble(rep = r, converged = FALSE,
                         error_msg = conditionMessage(e)),
           sched = tibble()))
  }, mc.cores = N_CORES, mc.preschedule = FALSE)

  ok <- vapply(raw, is.list, logical(1))
  if (any(!ok)) {
    raw[!ok] <- Map(function(r, m) list(
      rows = tibble(rep = r, converged = FALSE,
                    error_msg = paste("worker died:",
                                      substr(paste(as.character(m),
                                                   collapse = " "), 1, 300))),
      sched = tibble()), b[!ok], raw[!ok])
  }
  res <- bind_rows(lapply(raw, `[[`, "rows"))
  scl <- bind_rows(lapply(raw, `[[`, "sched"))

  write_csv(res, RAW, append = file.exists(RAW))
  if (nrow(scl)) write_csv(scl, SCHED, append = file.exists(SCHED))
  el <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))
  eta <- el / bi * (length(batches) - bi)
  cat(sprintf("[batch %d/%d] reps %d-%d | %.1f min elapsed | ~%.0f min left\n",
              bi, length(batches), min(b), max(b), el, eta))
}

cat(sprintf("done. total %.1f min\n",
            as.numeric(difftime(Sys.time(), t_start, units = "mins"))))
