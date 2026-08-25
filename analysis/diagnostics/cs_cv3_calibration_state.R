#!/usr/bin/env Rscript
################################################################################
# cs_cv3_calibration_state.R
#
# Does the CV3 cluster jackknife (Karim, Nielsen, MacKinnon & Webb 2026) fix
# CSDID's inference on OUR design?
#
# Null-only (delta = 0) calibration on the blinded STATE panel, using the
# pre-registered D1 pseudo-schedule machinery, so the answer is comparable to
# the size gate the PAP's estimator-selection rule already applies. CS is run
# with all four inference arms (analytic / boot_t / boot / jack) plus TWFE and
# did2s as reference arms in the SAME simulated panels.
#
# THE OPEN QUESTION. KNMW's Monte Carlo always places multiple states per
# cohort. Ours are singletons: deleting a treated state removes that cohort's
# ATT(g,t) terms outright, so the delete-one estimates vary partly through
# aggregation COMPOSITION rather than sampling noise (their Section 4, second
# caveat). Whether CV3 stays calibrated under that regime is not answered by
# their paper and is what this script measures.
#
# Reported per estimator x inference arm:
#   reject_05   rejection rate at alpha = .05 (= Type I error, since delta = 0)
#   se_over_sd  mean(SE) / sd(ATT)  -- 1.0 is calibrated, <1 means SEs too small
#   convergence share of reps producing a usable estimate
#
# Env knobs: N_REPS (default 200), N_CORES (default cores-2), BATCH (25),
#            OUT_DIR, LEVEL (state), FASTER_MODE (FALSE).
#
# Results append per batch to results_raw.csv, so a kill never loses more than
# one batch (2026-08-08 lesson: the county primary run lost 42h of work by
# accumulating everything in RAM).
#
# Run from the repository root:
#   N_REPS=200 N_CORES=8 Rscript analysis/diagnostics/cs_cv3_calibration_state.R
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
  library(lubridate)
  library(parallel)
})

stopifnot(file.exists("power_simulation_cs.R"))  # repo-root guard

source("R/power/config.R")
source("R/power/blindness_checks.R")
source("R/power/load_blinded_panel.R")
source("R/power/make_pseudo_schedules.R")
source("R/power/impose_effects.R")
source("R/power/run_estimators.R")

# ---- settings ---------------------------------------------------------------

.envint <- function(k, d) { v <- Sys.getenv(k); if (nzchar(v)) as.integer(v) else d }
.envchr <- function(k, d) { v <- Sys.getenv(k); if (nzchar(v)) v else d }

N_REPS  <- .envint("N_REPS", 200L)
BATCH   <- .envint("BATCH", 25L)
N_CORES <- .envint("N_CORES", max(1L, parallel::detectCores() - 2L))
LEVEL   <- .envchr("LEVEL", "state")
OUT_DIR <- .envchr("OUT_DIR", file.path("data/output/cs_cv3_calibration", LEVEL))
# faster_mode=TRUE threw "singular matrix ... not enough control units" on the
# first D1 state draw probed (2026-08-11); the calibration therefore runs with
# faster_mode=FALSE, matching what actually estimates on this design.
FASTER  <- identical(toupper(.envchr("FASTER_MODE", "FALSE")), "TRUE")

# TWFE is EXCLUDED by default. Its wild-bootstrap arm calls
# fwildclusterboot::boottest(), which raised an irrecoverable R exception
# (process abort, not a catchable error) inside forked mclapply workers on the
# state panel, taking the whole batch with it (2026-08-11). The abort happens
# below R's condition system, so tryCatch cannot contain it. VERIFIED: the same
# rep/seed runs cleanly SERIALLY (analytic p = .625, wild p = .600), so this is
# the boottest-under-fork interaction, not a state-panel estimation problem.
# TWFE state-level operating characteristics already exist from the 500-rep
# cheap run; this diagnostic exists for CS, so the default reference is did2s.
# Set ESTIMATORS=cs,twfe,did2s to re-include it (use N_CORES=1).
ESTIMATORS <- strsplit(.envchr("ESTIMATORS", "cs,did2s"), ",")[[1]]
stopifnot(all(ESTIMATORS %in% c("cs", "twfe", "did2s")))

BASE_SEED <- 20260723L   # shared with power_primary/cheap/smoke -> paired panels
SCENARIO  <- 901L        # distinct scenario offset for this diagnostic
ALPHA     <- 0.05

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
RAW <- file.path(OUT_DIR, "results_raw.csv")

cat(sprintf(
  "CS CV3 calibration | level=%s reps=%d cores=%d batch=%d faster_mode=%s\nout: %s\n",
  LEVEL, N_REPS, N_CORES, BATCH, FASTER, OUT_DIR))

# ---- fixed inputs -----------------------------------------------------------

cfg <- read_power_config("config/power_smoke.yml")

panel <- load_blinded_panel(level = LEVEL, treat_def = "online_start_date",
                            anticipation = 6L, sample = "S2", covid = "drop",
                            config = cfg)
real_schedule <- load_eviction_treatment_schedule(
  "data/raw/sports_gambling_legalization_dates.csv", "online_start_date")

cat(sprintf("panel: %d rows, %d states, %d months\n", nrow(panel),
            dplyr::n_distinct(panel$state_abb),
            dplyr::n_distinct(panel$month_date)))

# ---- one replication --------------------------------------------------------

one_rep <- function(rep) {
  seed_rep <- BASE_SEED + 10007L * rep + 101L * SCENARIO

  sched <- tryCatch(
    make_pseudo_schedule(design = "D1", panel = panel,
                         real_schedule = real_schedule,
                         treat_def = "online_start_date",
                         min_pre = 12L, min_post = 6L,
                         seed = seed_rep, template = "panel"),
    error = function(e) e)
  if (inherits(sched, "condition")) {
    return(tibble(rep = rep, estimator = NA_character_, inference = NA_character_,
                  att = NA_real_, se = NA_real_, p = NA_real_, converged = FALSE,
                  error_msg = paste("schedule:", conditionMessage(sched)),
                  runtime_s = NA_real_))
  }

  sim <- impose_effect(panel, sched, mechanism = "count_nb", shape = "step",
                       delta = 0, params = list(), outcome = "y_log1p",
                       seed = seed_rep + 1L)

  specs <- list(
    cs    = list(cs_jack = TRUE, cs_faster_mode = FASTER),
    twfe  = list(), did2s = list()
  )[ESTIMATORS]
  out <- lapply(names(specs), function(est) {
    r <- tryCatch(run_estimator(sim, estimator = est, spec = specs[[est]]),
                  error = function(e) .re_row(est, "analytic", "simple",
                                              converged = FALSE,
                                              error_msg = conditionMessage(e)))
    # Keep only the pooled estimand; dynamic rows are not what the gate scores.
    r[r$estimand == "simple", , drop = FALSE]
  })
  bind_rows(out) %>%
    mutate(rep = rep) %>%
    select(rep, estimator, inference, att, se, p, converged, error_msg, runtime_s)
}

# ---- batched, checkpointed run ---------------------------------------------

done <- if (file.exists(RAW)) unique(suppressMessages(read_csv(RAW, show_col_types = FALSE))$rep) else integer(0)
todo <- setdiff(seq_len(N_REPS), done)
if (length(done)) cat(sprintf("resuming: %d reps already done\n", length(done)))

t_start <- Sys.time()
batches <- split(todo, ceiling(seq_along(todo) / BATCH))

for (bi in seq_along(batches)) {
  b <- batches[[bi]]
  raw <- parallel::mclapply(b, function(r) {
    tryCatch(one_rep(r), error = function(e)
      tibble(rep = r, estimator = NA_character_, inference = NA_character_,
             att = NA_real_, se = NA_real_, p = NA_real_, converged = FALSE,
             error_msg = conditionMessage(e), runtime_s = NA_real_))
  }, mc.cores = N_CORES)

  # A forked worker that dies (rather than errors) yields a try-error or bare
  # character instead of a tibble; bind_rows on that produces a frame with no
  # `estimator` column and the summary then fails on a stale CSV. Coerce
  # non-frames into explicit failure rows so a crashed worker is recorded.
  ok_frame <- vapply(raw, is.data.frame, logical(1))
  if (any(!ok_frame)) {
    msg <- vapply(raw[!ok_frame], function(x)
      paste("worker died:", paste(as.character(x), collapse = " ")), character(1))
    raw[!ok_frame] <- Map(function(r, m) tibble(
      rep = r, estimator = NA_character_, inference = NA_character_,
      att = NA_real_, se = NA_real_, p = NA_real_, converged = FALSE,
      error_msg = substr(m, 1, 300), runtime_s = NA_real_),
      b[!ok_frame], msg)
  }
  res <- bind_rows(raw)

  write_csv(res, RAW, append = file.exists(RAW))
  el <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))
  cat(sprintf("[batch %d/%d] reps %d-%d done | %.1f min elapsed\n",
              bi, length(batches), min(b), max(b), el))
}

# ---- summary ----------------------------------------------------------------

all <- suppressMessages(read_csv(RAW, show_col_types = FALSE))

summ <- all %>%
  filter(!is.na(estimator)) %>%
  group_by(estimator, inference) %>%
  summarise(
    n_reps     = n(),
    n_conv     = sum(converged, na.rm = TRUE),
    conv_share = mean(converged, na.rm = TRUE),
    mean_att   = mean(att[converged], na.rm = TRUE),
    sd_att     = stats::sd(att[converged], na.rm = TRUE),
    mean_se    = mean(se[converged], na.rm = TRUE),
    median_se  = stats::median(se[converged], na.rm = TRUE),
    se_over_sd = mean(se[converged], na.rm = TRUE) /
                 stats::sd(att[converged], na.rm = TRUE),
    reject_05  = mean(p[converged] < 0.05, na.rm = TRUE),
    reject_10  = mean(p[converged] < 0.10, na.rm = TRUE),
    med_runtime_s = stats::median(runtime_s[converged], na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(estimator, inference)

write_csv(summ, file.path(OUT_DIR, "summary.csv"))

cat("\n===== CS CV3 CALIBRATION (delta = 0; target reject_05 = 0.05,",
    "se_over_sd = 1.0) =====\n")
print(as.data.frame(summ), digits = 3)

fails <- all %>% filter(!is.na(error_msg)) %>% count(estimator, error_msg, sort = TRUE)
if (nrow(fails)) {
  cat("\n--- failures / notes ---\n"); print(as.data.frame(head(fails, 15)))
}
cat(sprintf("\nTotal wall clock: %.1f min\n",
            as.numeric(difftime(Sys.time(), t_start, units = "mins"))))
