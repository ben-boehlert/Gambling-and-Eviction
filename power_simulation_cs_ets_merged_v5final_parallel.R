#!/usr/bin/env Rscript
################################################################################
# power_simulation_cs_ets_merged_v5style.R
#
# Staggered DiD power simulation for merged_ets_combined.csv using Callaway & Sant'Anna (did::att_gt)
# with placebo treatment assignment drawn from untreated/not-yet-treated periods (Black et al. style).
#
# Key goals:
#   - Uses log outcomes (default: log1p_filings_count)
#   - Uses full panel for never-treated and pre-real-treatment periods for treated units
#   - Placebo adoption months are sampled *unit-by-unit* from each unit's feasible window
#     to avoid degenerate draws that produce 0 treated groups -> p=1 everywhere.
#   - Robust logging: prints to console and appends to OUT_DIR/run.log (no sink()).
#   - No NA/NaN p-values: invalid estimates -> p=1 and fail logged.
################################################################################

# ---------- Prelude (no packages) ----------
script_path <- NA_character_
try({
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f) == 1) script_path <- sub("^--file=", "", f)
}, silent = TRUE)

DATA_FILE0 <- Sys.getenv("DATA_FILE", "merged_ets_combined.csv")
OUT_DIR0   <- Sys.getenv("OUT_DIR", "power_outputs")
dir.create(OUT_DIR0, recursive = TRUE, showWarnings = FALSE)

md5_txt <- "(md5 unavailable)"
try({
  if (!is.na(script_path) && file.exists(script_path)) {
    md5_txt <- as.character(tools::md5sum(script_path)[[1]])
  }
}, silent = TRUE)

cat("=== PRELUDE ===\n")
cat("SCRIPT_PATH: ", script_path, "\n", sep = "")
cat("SCRIPT_MD5 : ", md5_txt, "\n", sep = "")
cat("R_VERSION  : ", as.character(getRversion()), "\n", sep = "")
cat("DATA_FILE  : ", DATA_FILE0, "\n", sep = "")
cat("OUT_DIR    : ", OUT_DIR0, "\n", sep = "")
cat("DRY_RUN    : ", Sys.getenv("DRY_RUN", "FALSE"), "\n", sep = "")
cat("TEST_MODE  : ", Sys.getenv("TEST_MODE", "FALSE"), "\n", sep = "")
cat("N_WORKERS : ", Sys.getenv("N_WORKERS", ""), " (SLURM_CPUS_PER_TASK=", Sys.getenv("SLURM_CPUS_PER_TASK",""), ")\n", sep = "")
cat("=== END PRELUDE ===\n\n")

# Single-thread to reduce Della weirdness
Sys.setenv(
  OMP_NUM_THREADS = "1",
  OPENBLAS_NUM_THREADS = "1",
  MKL_NUM_THREADS = "1",
  VECLIB_MAXIMUM_THREADS = "1",
  BLIS_NUM_THREADS = "1"
)

# ---------- Packages ----------
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(glue)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

as_bool <- function(x, default = FALSE) {
  if (is.null(x) || identical(x, "")) return(default)
  x <- tolower(trimws(x))
  if (x %in% c("1","true","t","yes","y")) return(TRUE)
  if (x %in% c("0","false","f","no","n")) return(FALSE)
  default
}

parse_int_vec <- function(x, default = integer(0)) {
  if (is.null(x) || identical(trimws(x), "")) return(default)
  out <- suppressWarnings(as.integer(strsplit(x, ",")[[1]]))
  out <- out[is.finite(out)]
  sort(unique(out))
}

parse_num_vec <- function(x, default) {
  if (is.null(x) || identical(trimws(x), "")) return(default)
  out <- suppressWarnings(as.numeric(strsplit(x, ",")[[1]]))
  out <- out[is.finite(out)]
  if (length(out) == 0) default else out
}

clean_key <- function(x) {
  x %>% as.character() %>% stringr::str_to_lower() %>% stringr::str_replace_all("[^a-z]", "")
}

date_to_time_id <- function(d) {
  d <- as.Date(d)
  as.integer(lubridate::year(d) * 12L + lubridate::month(d))
}

pval_2sided <- function(z) 2 * stats::pnorm(-abs(z))

interp_mde <- function(effect_log, power, target = 0.8) {
  o <- order(effect_log)
  effect_log <- effect_log[o]
  power <- power[o]
  if (length(power) == 0 || all(is.na(power))) return(NA_real_)
  if (max(power, na.rm = TRUE) < target) return(NA_real_)
  j <- which(power >= target)[1]
  if (is.na(j)) return(NA_real_)
  if (j == 1) return(effect_log[1])
  x0 <- effect_log[j-1]; x1 <- effect_log[j]
  y0 <- power[j-1]; y1 <- power[j]
  if (!is.finite(y0) || !is.finite(y1) || (y1 - y0) == 0) return(effect_log[j])
  x0 + (target - y0) * (x1 - x0) / (y1 - y0)
}

# ---------- Config ----------
cfg <- list(
  data_file = Sys.getenv("DATA_FILE", "merged_ets_combined.csv"),
  out_dir   = Sys.getenv("OUT_DIR", "power_outputs"),
  outcome   = Sys.getenv("OUTCOME", "log1p_filings_count"),
  n_sims    = as.integer(Sys.getenv("N_SIMS", "5000")),
  n_workers = as.integer(Sys.getenv("N_WORKERS", Sys.getenv("SLURM_CPUS_PER_TASK", "1"))),
  alpha     = as.numeric(Sys.getenv("ALPHA", "0.05")),
  power_target = as.numeric(Sys.getenv("POWER_TARGET", "0.80")),
  pre_len   = as.integer(Sys.getenv("PRE_LEN", "24")),
  post_len  = as.integer(Sys.getenv("POST_LEN", "24")),
  grid_n_states = parse_int_vec(Sys.getenv("GRID_N_STATES", ""), default = integer(0)),
  make_heatmap = as_bool(Sys.getenv("MAKE_HEATMAP", "TRUE"), default = TRUE),
  dry_run   = as_bool(Sys.getenv("DRY_RUN", "FALSE"), default = FALSE),
  test_mode = as_bool(Sys.getenv("TEST_MODE", "FALSE"), default = FALSE),
  seed      = as.integer(Sys.getenv("SEED", "123")),
  save_draws = as_bool(Sys.getenv("SAVE_DRAWS", "FALSE"), default = FALSE),
  save_diagnostics = as_bool(Sys.getenv("SAVE_DIAGNOSTICS", "TRUE"), default = TRUE),
  # did options
  did_bstrap = as_bool(Sys.getenv("DID_BSTRAP", "FALSE"), default = FALSE),
  did_biters = as.integer(Sys.getenv("DID_BITERS", "0")),
  did_cband  = as_bool(Sys.getenv("DID_CTBAND", "FALSE"), default = FALSE),
  did_est_method = Sys.getenv("DID_EST_METHOD", "ipw"),
  # placebo treated share clamp
  treated_share_min = as.numeric(Sys.getenv("TREATED_SHARE_MIN", "0.20")),
  treated_share_max = as.numeric(Sys.getenv("TREATED_SHARE_MAX", "0.80")),
  effect_pcts = parse_num_vec(Sys.getenv("EFFECT_PCTS", "0,0.01,0.02,0.05,0.08,0.10"),
                              default = c(0,0.01,0.02,0.05,0.08,0.10))
)

cfg$n_workers <- max(1L, as.integer(cfg$n_workers))

cfg$did_est_method <- if (cfg$did_est_method %in% c("ipw","dr")) cfg$did_est_method else "ipw"
if (cfg$test_mode && cfg$n_sims > 200) cfg$n_sims <- 200L
cfg$effect_log <- log1p(cfg$effect_pcts)

dir.create(cfg$out_dir, showWarnings = FALSE, recursive = TRUE)

# ---------- Logging (no sink) ----------
runlog_path <- file.path(cfg$out_dir, "run.log")
log_line <- function(...) {
  msg <- paste0(..., collapse = "")
  cat(msg, "\n", sep = "")
  try(write(msg, file = runlog_path, append = TRUE), silent = TRUE)
}

write_started_marker <- function(cfg) {
  try(writeLines(
    c(
      glue("Started: {Sys.time()}"),
      glue("DATA_FILE: {cfg$data_file}"),
      glue("OUT_DIR: {cfg$out_dir}"),
      glue("DRY_RUN: {cfg$dry_run}  TEST_MODE: {cfg$test_mode}"),
      glue("N_SIMS: {cfg$n_sims}  ALPHA: {cfg$alpha}  POWER_TARGET: {cfg$power_target}")
    ),
    file.path(cfg$out_dir, "STARTED.txt")
  ), silent = TRUE)
}

write_fatal <- function(cfg, msg) {
  try(writeLines(msg, file.path(cfg$out_dir, "power_FATAL_ERROR.txt")), silent = TRUE)
  log_line(msg)
}

init_cluster <- function(cfg) {
  # Use SLURM_CPUS_PER_TASK by default; override with N_WORKERS.
  n_req <- suppressWarnings(as.integer(cfg$n_workers))
  if (!is.finite(n_req) || is.na(n_req) || n_req < 1L) n_req <- 1L

  # Don't spawn more workers than sims (wasteful) or more than available CPUs (best effort).
  n_used <- min(n_req, max(1L, cfg$n_sims))

  if (isTRUE(cfg$dry_run) || n_used <= 1L) return(list(cl = NULL, n_used = 1L))

  log_line(glue("Parallel: requested_workers={n_req}; using_workers={n_used}"))
  # PSOCK works on Linux and on Della compute nodes.
  cl <- parallel::makeCluster(n_used, type = "PSOCK", outfile = "")

  # Make workers single-threaded for BLAS/OpenMP to avoid oversubscription.
  parallel::clusterEvalQ(cl, {
    Sys.setenv(
      OMP_NUM_THREADS = "1",
      MKL_NUM_THREADS = "1",
      OPENBLAS_NUM_THREADS = "1",
      VECLIB_MAXIMUM_THREADS = "1",
      NUMEXPR_NUM_THREADS = "1"
    )
    suppressPackageStartupMessages({
      library(dplyr)
      library(tibble)
      library(stats)
      library(did)
    })
    NULL
  })

  # PSOCK workers do NOT inherit your global environment. Export helper functions
  # PSOCK workers do NOT inherit your global environment. Export the helper
  # functions they will need. If this fails, stop immediately (otherwise you
  # get mysterious "could not find function" errors 30 minutes later).
  exports <- c(
    "draw_placebo_schedule",
    "impose_effect",
    "att_gt_safe",
    "run_estimator_and_extract",
    "pval_2sided",
    "one_draw_worker_parallel"
  )
  missing <- exports[!vapply(exports, exists, logical(1), envir = .GlobalEnv, inherits = FALSE)]
  if (length(missing) > 0) {
    stop(glue("Missing helper(s) before clusterExport: {paste(missing, collapse=', ')}"), call. = FALSE)
  }
  parallel::clusterExport(cl, varlist = exports, envir = .GlobalEnv)

  # Record parallel configuration for peace of mind
  try({
    cfg_txt <- c(
      paste0("n_workers_requested=", n_req),
      paste0("n_workers_used=", n_used),
      paste0("SLURM_CPUS_PER_TASK=", Sys.getenv("SLURM_CPUS_PER_TASK","")),
      paste0("N_WORKERS=", Sys.getenv("N_WORKERS","")),
      paste0("host=", Sys.info()[["nodename"]])
    )
    writeLines(cfg_txt, file.path(cfg$out_dir, "parallel_config.txt"))
  }, silent = TRUE)

  list(cl = cl, n_used = n_used)
}

stop_cluster <- function(cl) {
  if (!is.null(cl)) {
    try(parallel::stopCluster(cl), silent = TRUE)
  }
  invisible(NULL)
}

# ---------- Data ----------
load_panel <- function(cfg) {
  if (!file.exists(cfg$data_file)) stop(glue("Missing DATA_FILE: {cfg$data_file}"), call. = FALSE)
  df <- readr::read_csv(cfg$data_file, show_col_types = FALSE)

  req <- c("location_std", "month_date", "filings_count", "filings_avg")
  miss <- setdiff(req, names(df))
  if (length(miss) > 0) stop(glue("DATA_FILE missing columns: {paste(miss, collapse=', ')}"), call. = FALSE)

  df <- df %>%
    mutate(
      month_date = as.Date(month_date),
      state_key  = clean_key(location_std),
      time_id    = date_to_time_id(month_date),
      time_id    = as.integer(time_id),
      filings_count = as.numeric(filings_count),
      filings_avg   = as.numeric(filings_avg),
      log1p_filings_count = log(pmax(filings_count, 0) + 1),
      log1p_filings_avg   = log(pmax(filings_avg,   0) + 1)
    ) %>%
    filter(!is.na(state_key), is.finite(time_id)) %>%
    mutate(time_id = as.integer(time_id))

  if (any(duplicated(df[, c("state_key","time_id")]))) {
    df <- df %>%
      group_by(state_key, time_id) %>%
      summarise(
        month_date = min(month_date, na.rm = TRUE),
        filings_count = sum(filings_count, na.rm = TRUE),
        filings_avg   = mean(filings_avg, na.rm = TRUE),
        log1p_filings_count = log(pmax(filings_count,0)+1),
        log1p_filings_avg   = log(pmax(filings_avg,0)+1),
        .groups = "drop"
      ) %>%
      mutate(time_id = as.integer(time_id))
  }

  if (!(cfg$outcome %in% names(df))) stop(glue("Unknown OUTCOME={cfg$outcome}"), call. = FALSE)
  df <- df %>% mutate(outcome = .data[[cfg$outcome]]) %>% filter(is.finite(outcome))

  unit_map <- df %>% distinct(state_key) %>% arrange(state_key) %>% mutate(unit_id = row_number())
  df <- df %>% left_join(unit_map, by = "state_key") %>% mutate(state_abb = state_key)

  if (n_distinct(df$unit_id) < 6) stop("Too few states for simulation.", call. = FALSE)
  if (n_distinct(df$time_id) < (cfg$pre_len + cfg$post_len + 12)) stop("Too few months for pre/post windows.", call. = FALSE)

  df
}

make_treat_schedule <- function(panel_df) {
  # Real rollout dates (edit if needed)
  launch <- tibble::tribble(
    ~state_key,        ~online_launch_date,
    "arizona",         "2021-09-09",
    "connecticut",     "2021-10-19",
    "delaware",        "2024-01-03",
    "florida",         "2023-11-07",
    "indiana",         "2019-10-03",
    "louisiana",       "2022-01-28",
    "massachusetts",   "2023-03-10",
    "newyork",         "2022-01-08",
    "ohio",            "2023-01-01",
    "pennsylvania",    "2019-05-28",
    "rhodeisland",     "2019-09-04",
    "tennessee",       "2020-11-01",
    "virginia",        "2021-01-21"
  ) %>%
    mutate(
      state_key = clean_key(state_key),
      online_launch_date = as.Date(online_launch_date),
      launch_month = lubridate::floor_date(online_launch_date, "month"),
      g_id_raw = date_to_time_id(launch_month)
    )

  # *** critical: integer time_set + integer nearest_time (fixes your vapply crash) ***
  time_set <- as.integer(sort(unique(panel_df$time_id)))

  nearest_time <- function(g) {
    g <- as.integer(round(g))
    if (is.na(g) || g <= 0) return(0L)
    as.integer(time_set[which.min(abs(time_set - g))])
  }

  states <- panel_df %>% distinct(state_key, unit_id, state_abb)

  states %>%
    left_join(launch %>% select(state_key, g_id_raw), by = "state_key") %>%
    mutate(
      g_id = if_else(is.na(g_id_raw), 0L, vapply(g_id_raw, nearest_time, integer(1))),
      ever_treated = g_id > 0L
    ) %>%
    select(unit_id, state_abb, g_id, ever_treated)
}

build_untreated_sample <- function(panel_df, sched) {
  panel_df %>%
    left_join(sched %>% select(unit_id, g_id, ever_treated), by = "unit_id") %>%
    filter((!ever_treated) | (ever_treated & time_id < g_id))
}

# ---------- Placebo assignment (unit-by-unit feasible windows) ----------
draw_placebo_schedule <- function(sched, cfg, baseline_df) {
  # IMPORTANT: sample placebo adoption dates from *observed* time_id values for
  # each unit. Do NOT sample on the integer grid (that can create g values that
  # never appear in the data, leading to gname==0 for everyone and power==0).

  # Observed time ids per unit
  ut <- baseline_df %>%
    distinct(unit_id, time_id) %>%
    arrange(unit_id, time_id) %>%
    group_by(unit_id) %>%
    summarise(times = list(as.integer(time_id)), nT = dplyr::n(), .groups = "drop") %>%
    mutate(ok = nT >= (as.integer(cfg$pre_len) + as.integer(cfg$post_len) + 1L))

  eligible <- ut %>% filter(ok)
  if (nrow(eligible) < 6) stop("Need >= 6 eligible baseline states with pre/post support.", call. = FALSE)

  treated_share <- mean(sched$ever_treated, na.rm = TRUE)
  if (!is.finite(treated_share)) treated_share <- 0.5
  treated_share <- max(cfg$treated_share_min, min(cfg$treated_share_max, treated_share))

  n_to_treat <- as.integer(round(nrow(eligible) * treated_share))
  n_to_treat <- max(2L, min(n_to_treat, nrow(eligible) - 2L))

  treated_units <- sample(eligible$unit_id, size = n_to_treat, replace = FALSE)
  treated_tbl <- eligible %>%
    filter(unit_id %in% treated_units) %>%
    rowwise() %>%
    mutate(
      g_placebo = {
        tt <- times[[1]]
        lo <- as.integer(cfg$pre_len) + 1L
        hi <- length(tt) - as.integer(cfg$post_len)
        cand <- tt[lo:hi]
        as.integer(sample(cand, size = 1L))
      }
    ) %>%
    ungroup() %>%
    select(unit_id, g_placebo)

  all_units <- baseline_df %>% distinct(unit_id)
  all_units %>%
    mutate(g_placebo = 0L) %>%
    left_join(treated_tbl, by = "unit_id", suffix = c("", "_new")) %>%
    mutate(g_placebo = if_else(!is.na(g_placebo_new), as.integer(g_placebo_new), as.integer(g_placebo))) %>%
    select(unit_id, g_placebo)
}

impose_effect <- function(df, placebo_schedule, effect_log) {
  df %>%
    left_join(placebo_schedule, by = "unit_id") %>%
    mutate(
      # avoid tidyr::replace_na (workers don't load tidyr)
      g_placebo = if_else(is.na(g_placebo), 0L, as.integer(g_placebo)),
      D = as.integer(g_placebo > 0L & time_id >= g_placebo),
      outcome_sim = outcome + effect_log * as.numeric(D)
    )
}

# ---------- Estimation ----------
att_gt_safe <- function(df_in, cfg, cluster_var) {
  df_in <- as.data.frame(df_in)

  args <- list(
    yname = "outcome_sim",
    tname = "time_id_seq",
    idname = "unit_id",
    gname = "gname",
    data = df_in,
    panel = TRUE,
    control_group = "notyettreated",
    bstrap = cfg$did_bstrap,
    biters = cfg$did_biters,
    cband = cfg$did_cband,
    est_method = cfg$did_est_method
  )

  if (isTRUE(cfg$did_bstrap) && !is.null(cluster_var) && cluster_var %in% names(df_in)) {
    args$clustervars <- cluster_var
  }

  fmls <- names(formals(did::att_gt))
  if ("allow_unbalanced_panel" %in% fmls) args$allow_unbalanced_panel <- TRUE
  if ("cores" %in% fmls) args$cores <- 1L
  if ("ncores" %in% fmls) args$ncores <- 1L
  if ("parallel" %in% fmls) args$parallel <- FALSE
  if ("print_details" %in% fmls) args$print_details <- FALSE

  res <- NULL
  # did::att_gt prints (via cat) "You have an unbalanced panel" repeatedly.
  # Capture stdout so logs stay readable and the subprocess doesn't look hung.
  utils::capture.output({
    res <- withCallingHandlers(
      do.call(did::att_gt, args),
      warning = function(w) {
        msg <- conditionMessage(w)
        if (grepl("Not returning pre-test Wald statistic", msg, fixed = TRUE) ||
            grepl("some small groups", msg, ignore.case = TRUE)) {
          invokeRestart("muffleWarning")
        }
      }
    )
  }, type = "output")
  res
}

run_estimator_and_extract <- function(df_sim, cfg, cluster_var, time_mapping) {
  out <- list(
    p = 1.0,
    est = NA_real_,
    se = NA_real_,
    fail = NA_character_,
    n_treated_units = NA_integer_,
    n_never_units = NA_integer_,
    n_cohorts = NA_integer_,
    treated_obs_share = NA_real_,
    n_obs = NA_integer_
  )

  # map time_id to sequential index
  df_in <- df_sim %>%
    left_join(time_mapping, by = "time_id") %>%
    mutate(time_id_seq = as.integer(time_id_seq))

  # cohort index in seq-time units
  gseq <- match(df_in$g_placebo, time_mapping$time_id)
  gseq <- ifelse(is.na(gseq), 0L, as.integer(gseq))
  df_in <- df_in %>%
    mutate(gname = if_else(g_placebo == 0L, 0, as.numeric(gseq)))

  n_treated <- n_distinct(df_in$unit_id[df_in$gname > 0])
  n_never   <- n_distinct(df_in$unit_id[df_in$gname == 0])

  out$n_treated_units <- as.integer(n_treated)
  out$n_never_units   <- as.integer(n_never)
  out$n_cohorts       <- as.integer(n_distinct(df_in$gname[df_in$gname > 0]))
  out$n_obs           <- as.integer(nrow(df_in))
  if ("D" %in% names(df_sim)) {
    out$treated_obs_share <- mean(df_sim$D == 1L, na.rm = TRUE)
  }

  if (n_treated < 2 || n_never < 2) {
    out$fail <- glue("insufficient_groups treated={n_treated} never={n_never}")
    return(out)
  }

  tryCatch({
    att <- att_gt_safe(df_in, cfg, cluster_var = cluster_var)
    agg <- did::aggte(att, type = "simple")
    est <- as.numeric(agg$overall.att)
    se  <- as.numeric(agg$overall.se)

    if (!is.finite(est) || !is.finite(se) || se <= 0) {
      out$fail <- "invalid_est_or_se"
      out$est <- est
      out$se  <- se
      return(out)
    }

    p <- pval_2sided(est / se)
    if (!is.finite(p) || is.na(p)) p <- 1.0

    list(
      p = p,
      est = est,
      se = se,
      fail = NA_character_,
      n_treated_units = out$n_treated_units,
      n_never_units = out$n_never_units,
      n_cohorts = out$n_cohorts,
      treated_obs_share = out$treated_obs_share,
      n_obs = out$n_obs
    )
  }, error = function(e) {
    out$fail <- paste0("est_error: ", conditionMessage(e))
    out
  })
}

# ---------- Simulation ----------

# Worker function for PSOCK clusters.
# Relies on these objects being present on the worker's global environment:
#   baseline, sched, cfg, effect_log, time_mapping, cluster_var
one_draw_worker_parallel <- function(s) {
  s <- as.integer(s)
  set.seed(cfg$seed + s)

  placebo <- draw_placebo_schedule(sched, cfg, baseline)
  df_sim  <- impose_effect(baseline, placebo, effect_log)

  df_sim <- df_sim %>%
    dplyr::select(unit_id, state_abb, month_date, time_id, g_placebo, D, outcome_sim)

  est_res <- run_estimator_and_extract(df_sim, cfg, cluster_var, time_mapping)

  tibble::tibble(
    sim = s,
    p = est_res$p,
    est = est_res$est,
    se = est_res$se,
    fail = est_res$fail,
    n_treated_units = est_res$n_treated_units,
    n_never_units = est_res$n_never_units,
    n_cohorts = est_res$n_cohorts,
    treated_obs_share = est_res$treated_obs_share,
    n_obs = est_res$n_obs
  )
}

simulate_power_for_effect <- function(baseline, sched, cfg, effect_log, n_states, save_env, save_tag = NULL, cl = NULL) {
  cluster_var <- "state_abb"

  time_mapping <- baseline %>%
    distinct(time_id) %>%
    arrange(time_id) %>%
    mutate(time_id_seq = row_number())

  draws <- NULL
  sims <- seq_len(cfg$n_sims)

  if (!is.null(cl) && cfg$n_sims > 1L) {
    # Export per-cell objects ONCE to workers, then send only the sim index.
    parallel::clusterExport(
      cl,
      varlist = c("baseline", "sched", "cfg", "effect_log", "time_mapping", "cluster_var"),
      envir = environment()
    )
    draw_list <- parallel::parLapplyLB(cl, sims, one_draw_worker_parallel)
    draws <- dplyr::bind_rows(draw_list)
  } else {
    one_draw_local <- function(s) {
      set.seed(cfg$seed + s)
      placebo <- draw_placebo_schedule(sched, cfg, baseline)
      df_sim  <- impose_effect(baseline, placebo, effect_log)
      df_sim <- df_sim %>%
        dplyr::select(unit_id, state_abb, month_date, time_id, g_placebo, D, outcome_sim)
      est_res <- run_estimator_and_extract(df_sim, cfg, cluster_var, time_mapping)
      tibble::tibble(
        sim = s,
        p = est_res$p,
        est = est_res$est,
        se = est_res$se,
        fail = est_res$fail,
        n_treated_units = est_res$n_treated_units,
        n_never_units = est_res$n_never_units,
        n_cohorts = est_res$n_cohorts,
        treated_obs_share = est_res$treated_obs_share,
        n_obs = est_res$n_obs
      )
    }
    draws <- purrr::map_dfr(sims, one_draw_local)
  }

  if (isTRUE(cfg$save_draws) && !isTRUE(save_env$example_done)) {
    save_env$example_done <- TRUE
    readr::write_csv(draws, file.path(cfg$out_dir, "draws_example.csv"))
  }

  if (isTRUE(cfg$save_diagnostics) && !is.null(save_tag)) {
    if (is.null(save_env$saved_tags)) save_env$saved_tags <- character(0)
    if (!(save_tag %in% save_env$saved_tags)) {
      save_env$saved_tags <- c(save_env$saved_tags, save_tag)
      fname <- paste0("draws_", save_tag, ".csv")
      readr::write_csv(draws, file.path(cfg$out_dir, fname))
    }
  }

  power <- mean(draws$p <= cfg$alpha, na.rm = TRUE)
  if (is.nan(power)) power <- NA_real_

  tibble(
    n_states = n_states,
    effect_log = effect_log,
    effect_pct = expm1(effect_log),
    power = power,
    alpha = cfg$alpha,
    n_sims = cfg$n_sims,
    fail_rate = mean(!is.na(draws$fail)),
    fail_insufficient = mean(grepl("insufficient_groups", draws$fail %||% ""), na.rm = TRUE),
    mean_p = mean(draws$p, na.rm = TRUE),
    frac_p_eq_1 = mean(draws$p == 1.0, na.rm = TRUE),
    frac_p_le_001 = mean(draws$p <= 0.01, na.rm = TRUE),
    mean_est = mean(draws$est, na.rm = TRUE),
    median_se = median(draws$se, na.rm = TRUE),
    mean_n_treated_units = mean(draws$n_treated_units, na.rm = TRUE),
    mean_n_never_units = mean(draws$n_never_units, na.rm = TRUE),
    mean_n_cohorts = mean(draws$n_cohorts, na.rm = TRUE),
    mean_treated_obs_share = mean(draws$treated_obs_share, na.rm = TRUE)
  )
}

make_heatmap_plot <- function(power_df, cfg) {
  if (!isTRUE(cfg$make_heatmap)) return(invisible(NULL))
  if (!("n_states" %in% names(power_df))) return(invisible(NULL))
  if (n_distinct(power_df$n_states) < 2) return(invisible(NULL))

  p <- ggplot(power_df, aes(x = effect_pct, y = n_states, fill = power)) +
    geom_tile() +
    geom_contour(aes(z = power), breaks = cfg$power_target, color = "black") +
    labs(
      x = "Effect size (percent increase)",
      y = "Number of states",
      fill = "Power",
      title = glue("Power heatmap (target={cfg$power_target})")
    )

  if (requireNamespace("scales", quietly = TRUE)) {
    p <- p + scale_x_continuous(labels = scales::percent_format(accuracy = 1))
  }

  ggplot2::ggsave(
    filename = file.path(cfg$out_dir, "power_heatmap.png"),
    plot = p,
    width = 8.5,
    height = 5.5,
    dpi = 200
  )
  invisible(NULL)
}
write_diagnostics_outputs <- function(power_df, mde_tbl, cfg) {
  if (!isTRUE(cfg$save_diagnostics)) return(invisible(NULL))

  # Overview table by n_states (type I error, max power, fail rates)
  alpha <- cfg$alpha

  p0 <- power_df %>%
    filter(abs(effect_pct) < 1e-12) %>%
    select(
      n_states,
      power0 = power,
      fail0 = fail_rate,
      p1_0 = frac_p_eq_1,
      treated_units0 = mean_n_treated_units,
      cohorts0 = mean_n_cohorts
    )

  pbig <- power_df %>%
    group_by(n_states) %>%
    slice_max(effect_pct, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    select(
      n_states,
      effect_big = effect_pct,
      power_big = power,
      fail_big = fail_rate,
      p1_big = frac_p_eq_1,
      treated_units_big = mean_n_treated_units,
      cohorts_big = mean_n_cohorts
    )

  overview <- pbig %>%
    left_join(p0, by = "n_states") %>%
    left_join(mde_tbl %>% select(n_states, mde_pct, max_power), by = "n_states") %>%
    mutate(
      alpha = alpha,
      power_jump = power_big - power0,
      type1_ok = is.finite(power0) & abs(power0 - alpha) <= 0.07,
      any_power_ok = is.finite(power_jump) & power_jump >= 0.05,
      fail_ok = is.finite(fail_big) & fail_big <= 0.25
    ) %>%
    arrange(n_states)

  readr::write_csv(overview, file.path(cfg$out_dir, "diagnostics_overview.csv"))

  # Human-readable report
  warnings <- character(0)

  if (any(!overview$type1_ok, na.rm = TRUE)) {
    warnings <- c(warnings, "Type I error check failed for at least one n_states: power(effect=0) not close to alpha.")
  }
  if (all(!overview$any_power_ok, na.rm = TRUE)) {
    warnings <- c(warnings, "No detectable power increase at large effects (power_big - power0 < 0.05). This often means p-values are stuck at 1 due to estimation failures or effect not being imposed.")
  }
  if (any(overview$fail_big > 0.25, na.rm = TRUE)) {
    warnings <- c(warnings, "High fail_rate at large effect for at least one n_states (>0.25).")
  }
  if (any(overview$p1_big > 0.95, na.rm = TRUE) || any(overview$p1_0 > 0.95, na.rm = TRUE)) {
    warnings <- c(warnings, "Many p-values equal 1.0 (frac_p_eq_1 > 0.95). This typically indicates the estimator is failing and the code is falling back to p=1.")
  }

  report <- c(
    "CS power simulation diagnostics",
    "=============================",
    "",
    glue("Generated: {Sys.time()}"),
    glue("DATA_FILE: {cfg$data_file}"),
    glue("OUT_DIR: {cfg$out_dir}"),
    glue("Outcome: {cfg$outcome}"),
    glue("Estimator: did::att_gt (control_group=notyettreated, est_method={cfg$did_est_method}, bstrap={cfg$did_bstrap}, biters={cfg$did_biters})"),
    glue("N_SIMS: {cfg$n_sims}   alpha: {cfg$alpha}   power_target: {cfg$power_target}"),
    glue("pre_len: {cfg$pre_len}   post_len: {cfg$post_len}"),
    "",
    "Quick checks (per n_states):",
    paste0("  - Type I error ok?   ", ifelse(any(!overview$type1_ok, na.rm = TRUE), "NO", "YES")),
    paste0("  - Any power increase? ", ifelse(all(!overview$any_power_ok, na.rm = TRUE), "NO", "YES")),
    paste0("  - Fail rate ok?      ", ifelse(any(overview$fail_big > 0.25, na.rm = TRUE), "NO", "YES")),
    "",
    "See diagnostics_overview.csv for details.",
    ""
  )

  if (length(warnings) > 0) {
    report <- c(report, "WARNINGS:", paste0("  - ", warnings), "")
  } else {
    report <- c(report, "No diagnostics warnings triggered.", "")
  }

  # Add a small table printout (text) for boss-friendly email/paste
  report <- c(report, "Overview (selected columns):")
  overview_print <- overview %>%
    select(n_states, alpha, power0, power_big, power_jump, fail_big, p1_big, mde_pct, max_power)
  report <- c(report, capture.output(print(overview_print, n = Inf)), "")

  writeLines(report, file.path(cfg$out_dir, "diagnostics_report.txt"))

  # Session info for reproducibility
  try(capture.output(sessionInfo(), file = file.path(cfg$out_dir, "session_info.txt")), silent = TRUE)

  # Diagnostic p-value histograms if diagnostic draws were saved
  for (tag in c("diag_null", "diag_big")) {
    f <- file.path(cfg$out_dir, paste0("draws_", tag, ".csv"))
    if (file.exists(f)) {
      d <- try(readr::read_csv(f, show_col_types = FALSE), silent = TRUE)
      if (!inherits(d, "try-error") && ("p" %in% names(d))) {
        pplot <- ggplot(d, aes(x = p)) +
          geom_histogram(bins = 30) +
          labs(
            x = "p-value",
            y = "Count",
            title = paste0("P-value histogram (", tag, ")")
          )
        ggplot2::ggsave(
          filename = file.path(cfg$out_dir, paste0("pvalues_", tag, ".png")),
          plot = pplot,
          width = 7,
          height = 4.5,
          dpi = 200
        )
      }
    }
  }

  invisible(NULL)
}

run_power_simulation <- function(cfg) {
  write_started_marker(cfg)
  run_start_time <- Sys.time()

  log_line("=== CS power simulation (v5-style) ===")
  log_line(glue("DRY_RUN={cfg$dry_run} TEST_MODE={cfg$test_mode}"))
  log_line(glue("DATA_FILE: {cfg$data_file}"))
  log_line(glue("OUT_DIR: {cfg$out_dir}"))
  log_line(glue("Outcome: {cfg$outcome}"))
  log_line(glue("N_SIMS={cfg$n_sims} alpha={cfg$alpha} target={cfg$power_target} pre={cfg$pre_len} post={cfg$post_len}"))
  log_line(glue("Effects(pct): {paste(cfg$effect_pcts, collapse=', ')}"))
  if (length(cfg$grid_n_states) > 0) log_line(glue("GRID_N_STATES: {paste(cfg$grid_n_states, collapse=', ')}"))
  log_line("")

  panel <- load_panel(cfg)
  sched <- make_treat_schedule(panel)
  baseline_all <- build_untreated_sample(panel, sched)

  # Initialize parallel workers (PSOCK) if available
  cl_info <- init_cluster(cfg)
  cl <- cl_info$cl
  on.exit(stop_cluster(cl), add = TRUE)

  log_line(glue("Panel: states={n_distinct(panel$unit_id)} months={n_distinct(panel$time_id)} rows={nrow(panel)}"))
  log_line(glue("Baseline(untreated): states={n_distinct(baseline_all$unit_id)} months={n_distinct(baseline_all$time_id)} rows={nrow(baseline_all)}"))
  log_line("")

  if (cfg$dry_run) {
    set.seed(cfg$seed)
    placebo <- draw_placebo_schedule(sched, cfg, baseline_all)
    dbg <- impose_effect(baseline_all, placebo, effect_log = cfg$effect_log[1]) %>%
      select(state_abb, unit_id, month_date, time_id, g_placebo, outcome, outcome_sim)
    outp <- file.path(cfg$out_dir, "debug_one_draw.csv")
    readr::write_csv(dbg, outp)
    log_line(glue("DRY_RUN wrote {outp}"))
    return(invisible(TRUE))
  }

  if (!requireNamespace("did", quietly = TRUE)) stop("Package 'did' is required for estimation.", call. = FALSE)

  total_states <- n_distinct(baseline_all$unit_id)
  grid <- cfg$grid_n_states
  if (length(grid) == 0) grid <- total_states
  grid <- grid[grid <= total_states]
  grid <- sort(unique(grid))
  if (length(grid) == 0) stop("GRID_N_STATES leaves no valid grid points.", call. = FALSE)

  # Nested subsets for monotonicity / reproducibility: keep units with the most rows
  state_order <- baseline_all %>%
    count(unit_id, name = "n_rows") %>%
    arrange(desc(n_rows), unit_id)

  save_env <- new.env(parent = emptyenv())
  save_env$example_done <- FALSE
  save_env$saved_tags <- character(0)

  res_list <- list()
  idx <- 0L

  min_el <- min(cfg$effect_log)
  max_el <- max(cfg$effect_log)
  max_ns <- max(grid)
  for (ns in grid) {
    keep <- state_order$unit_id[seq_len(ns)]
    baseline <- baseline_all %>% filter(unit_id %in% keep)
    if (n_distinct(baseline$unit_id) < 6) next

    for (el in cfg$effect_log) {
      idx <- idx + 1L
      save_tag <- NULL
      if (isTRUE(cfg$save_diagnostics) && ns == max_ns && isTRUE(all.equal(el, min_el))) save_tag <- "diag_null"
      if (isTRUE(cfg$save_diagnostics) && ns == max_ns && isTRUE(all.equal(el, max_el))) save_tag <- "diag_big"

      res_list[[idx]] <- simulate_power_for_effect(
        baseline = baseline,
        sched = sched,
        cfg = cfg,
        effect_log = el,
        n_states = ns,
        save_env = save_env,
        save_tag = save_tag,
        cl = cl
      )
    }
  }

  res <- dplyr::bind_rows(res_list)

  mde_tbl <- res %>%
    group_by(n_states) %>%
    summarise(
      mde_log = interp_mde(effect_log, power, target = cfg$power_target),
      mde_pct = if_else(is.na(mde_log), NA_real_, expm1(mde_log)),
      max_power = max(power, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(n_states)

  readr::write_csv(res, file.path(cfg$out_dir, "power_by_effect.csv"))
  readr::write_csv(mde_tbl, file.path(cfg$out_dir, "mde_summary.csv"))

  make_heatmap_plot(res, cfg)
  write_diagnostics_outputs(res, mde_tbl, cfg)

  run_end_time <- Sys.time()
  try(writeLines(c(glue("Started: {run_start_time}"), glue("Ended: {run_end_time}"), glue("Runtime_seconds: {as.numeric(difftime(run_end_time, run_start_time, units='secs'))}")), file.path(cfg$out_dir, "RUNTIME.txt")), silent = TRUE)
  log_line("=== Done ===")
  invisible(list(power = res, mde = mde_tbl))
}

if (sys.nframe() == 0L) {
  tryCatch(
    run_power_simulation(cfg),
    error = function(e) {
      write_fatal(cfg, paste0("FATAL ERROR: ", conditionMessage(e)))
      if (!interactive()) quit(status = 1)
      stop(e)
    }
  )
}