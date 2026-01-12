#!/usr/bin/env Rscript
################################################################################
# power_simulation_cs_ets_merged_v5style.R
#
# Staggered DiD power simulation (Callaway & Sant'Anna via did::att_gt)
# using merged_ets_combined.csv only.
#
# This version is deliberately "v4_5-like" in robustness:
#   - NO sink() (so subprocess captures output normally)
#   - always writes OUT_DIR/run.log (tee-style logger)
#   - always writes OUT_DIR/power_FATAL_ERROR.txt on any fatal error
#   - DRY_RUN path never loads did
#
# Env:
#   DATA_FILE=merged_ets_combined.csv
#   OUT_DIR=power_outputs
#   OUTCOME=log1p_filings_count | log1p_filings_avg
#   N_SIMS=5000
#   EFFECT_PCTS=0,0.01,0.02,0.05,0.08,0.10
#   ALPHA=0.05
#   POWER_TARGET=0.80
#   PRE_LEN=24
#   POST_LEN=24
#   GRID_N_STATES= (optional; e.g. 10,12,14,16,18,20)
#   MAKE_HEATMAP=TRUE|FALSE
#   DRY_RUN=TRUE|FALSE
#   TEST_MODE=TRUE|FALSE  (clamps N_SIMS down)
#   SEED=123
#
# did knobs (kept conservative for Della stability)
#   DID_BSTRAP=FALSE|TRUE
#   DID_BITERS=0|50|200
#   DID_CTBAND=FALSE|TRUE
#   DID_EST_METHOD=ipw|dr
################################################################################

# ---- Della safety: single-thread before anything else spins threads ----
Sys.setenv(
  OMP_NUM_THREADS = "1",
  OPENBLAS_NUM_THREADS = "1",
  MKL_NUM_THREADS = "1",
  VECLIB_MAXIMUM_THREADS = "1",
  BLIS_NUM_THREADS = "1"
)

# ---- Base preflight (no packages) ----
script_path <- NA_character_
try({
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f) == 1) script_path <- sub("^--file=", "", f)
}, silent = TRUE)

data_file0 <- Sys.getenv("DATA_FILE", "merged_ets_combined.csv")
out_dir0   <- Sys.getenv("OUT_DIR", "power_outputs")
dir.create(out_dir0, recursive = TRUE, showWarnings = FALSE)

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
cat("DATA_FILE  : ", data_file0, "\n", sep = "")
cat("OUT_DIR    : ", out_dir0, "\n", sep = "")
cat("DRY_RUN    : ", Sys.getenv("DRY_RUN", "FALSE"), "\n", sep = "")
cat("TEST_MODE  : ", Sys.getenv("TEST_MODE", "FALSE"), "\n", sep = "")
cat("=== END PRELUDE ===\n\n")

# ---- Simple tee logger (console + OUT_DIR/run.log) ----
runlog_path <- file.path(out_dir0, "run.log")
# truncate
try(writeLines(character(0), runlog_path), silent = TRUE)

log_line <- function(...) {
  msg <- paste0(...)
  cat(msg, "\n", sep = "")
  try(cat(msg, "\n", file = runlog_path, append = TRUE, sep = ""), silent = TRUE)
}

fatal_path <- file.path(out_dir0, "power_FATAL_ERROR.txt")
write_fatal <- function(msg) {
  try(writeLines(msg, fatal_path), silent = TRUE)
  try(cat(msg, "\n", file = runlog_path, append = TRUE, sep = ""), silent = TRUE)
}

# ---- Load packages with fatal logging ----
load_pkgs <- function() {
  suppressPackageStartupMessages({
    library(tidyverse)
    library(lubridate)
    library(stringr)
    library(glue)
    library(ggplot2)
  })
}
tryCatch(load_pkgs(), error = function(e) {
  msg <- paste0("FATAL ERROR (package load): ", conditionMessage(e))
  write_fatal(msg)
  message(msg)
  if (!interactive()) quit(status = 1)
  stop(e)
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

clean_key <- function(x) x %>% as.character() %>% str_to_lower() %>% str_replace_all("[^a-z]", "")

date_to_time_id <- function(d) {
  d <- as.Date(d)
  as.integer(year(d) * 12L + month(d))
}

pval_2sided <- function(z) 2 * stats::pnorm(-abs(z))

interp_mde <- function(effect_log, power, target = 0.8) {
  o <- order(effect_log)
  effect_log <- effect_log[o]
  power <- power[o]
  if (length(power) == 0) return(NA_real_)
  if (all(is.na(power))) return(NA_real_)
  if (max(power, na.rm = TRUE) < target) return(NA_real_)
  j <- which(power >= target)[1]
  if (is.na(j)) return(NA_real_)
  if (j == 1) return(effect_log[1])
  x0 <- effect_log[j-1]; x1 <- effect_log[j]
  y0 <- power[j-1]; y1 <- power[j]
  if (!is.finite(y0) || !is.finite(y1) || (y1 - y0) == 0) return(effect_log[j])
  x0 + (target - y0) * (x1 - x0) / (y1 - y0)
}

cfg <- list(
  data_file = Sys.getenv("DATA_FILE", "merged_ets_combined.csv"),
  out_dir   = Sys.getenv("OUT_DIR", "power_outputs"),
  outcome   = Sys.getenv("OUTCOME", "log1p_filings_count"),
  n_sims    = as.integer(Sys.getenv("N_SIMS", "5000")),
  alpha     = as.numeric(Sys.getenv("ALPHA", "0.05")),
  power_target = as.numeric(Sys.getenv("POWER_TARGET", "0.80")),
  pre_len   = as.integer(Sys.getenv("PRE_LEN", "24")),
  post_len  = as.integer(Sys.getenv("POST_LEN", "24")),
  grid_n_states = parse_int_vec(Sys.getenv("GRID_N_STATES", ""), default = integer(0)),
  make_heatmap = as_bool(Sys.getenv("MAKE_HEATMAP", "TRUE"), default = TRUE),
  dry_run   = as_bool(Sys.getenv("DRY_RUN", "FALSE"), default = FALSE),
  test_mode = as_bool(Sys.getenv("TEST_MODE", "FALSE"), default = FALSE),
  seed      = as.integer(Sys.getenv("SEED", "123")),
  did_bstrap = as_bool(Sys.getenv("DID_BSTRAP", "FALSE"), default = FALSE),
  did_biters = as.integer(Sys.getenv("DID_BITERS", "0")),
  did_cband  = as_bool(Sys.getenv("DID_CTBAND", "FALSE"), default = FALSE),
  did_est_method = Sys.getenv("DID_EST_METHOD", "ipw"),
  effect_pcts = parse_num_vec(Sys.getenv("EFFECT_PCTS", "0,0.01,0.02,0.05,0.08,0.10"),
                              default = c(0,0.01,0.02,0.05,0.08,0.10))
)

cfg$did_est_method <- if (cfg$did_est_method %in% c("ipw","dr")) cfg$did_est_method else "ipw"
if (cfg$test_mode && cfg$n_sims > 200) cfg$n_sims <- 200L
cfg$effect_log <- log1p(cfg$effect_pcts)

dir.create(cfg$out_dir, showWarnings = FALSE, recursive = TRUE)

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
      time_id    = as.integer(date_to_time_id(month_date)),
      filings_count = as.numeric(filings_count),
      filings_avg   = as.numeric(filings_avg),
      log1p_filings_count = log(pmax(filings_count, 0) + 1),
      log1p_filings_avg   = log(pmax(filings_avg,   0) + 1)
    ) %>%
    filter(!is.na(state_key), is.finite(time_id)) %>%
    mutate(time_id = as.integer(time_id))

  # collapse duplicates, if any
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
      launch_month = floor_date(online_launch_date, "month"),
      g_id = as.integer(date_to_time_id(launch_month))
    )

  time_set <- as.integer(sort(unique(panel_df$time_id)))
  nearest_time <- function(g) {
    if (is.na(g) || g <= 0) return(0L)
    as.integer(time_set[which.min(abs(time_set - as.integer(g)))])
  }

  states <- panel_df %>% distinct(state_key, unit_id, state_abb)

  states %>%
    left_join(launch %>% select(state_key, g_id), by = "state_key") %>%
    mutate(
      g_id = if_else(is.na(g_id), 0L, vapply(g_id, nearest_time, integer(1))),
      ever_treated = g_id > 0L
    ) %>%
    select(unit_id, state_abb, g_id, ever_treated)
}

build_untreated_sample <- function(panel_df, sched) {
  panel_df %>%
    left_join(sched %>% select(unit_id, g_id, ever_treated), by = "unit_id") %>%
    filter((!ever_treated) | (ever_treated & time_id < g_id))
}

draw_placebo_schedule <- function(sched, cfg, baseline_df) {
  unit_time_range <- baseline_df %>%
    group_by(unit_id, state_abb) %>%
    summarise(min_time_id = min(time_id), max_time_id = max(time_id), .groups = "drop")

  baseline_states <- sort(unique(unit_time_range$state_abb))
  baseline_states <- baseline_states[!is.na(baseline_states)]
  if (length(baseline_states) < 6) stop("Need >= 6 baseline states.", call. = FALSE)

  state_ts_full <- sched %>%
    distinct(state_abb, ever_treated, g_id) %>%
    filter(!is.na(state_abb))

  treated_share <- mean(state_ts_full$ever_treated, na.rm = TRUE)
  treated_share <- ifelse(is.finite(treated_share), treated_share, 0.5)

  treatment_dates <- sort(unique(state_ts_full$g_id[state_ts_full$ever_treated]))
  treatment_dates <- treatment_dates[is.finite(treatment_dates) & treatment_dates > 0L]
  if (length(treatment_dates) == 0) stop("No treated adoption dates found.", call. = FALSE)

  shift_months <- as.integer(max(cfg$post_len + 1L, 1L))

  min_t <- as.integer(min(baseline_df$time_id, na.rm = TRUE))
  max_t <- as.integer(max(baseline_df$time_id, na.rm = TRUE))

  # Try shifted adoption months first
  placebo_dates <- as.integer(treatment_dates) - shift_months
  placebo_dates <- placebo_dates[
    placebo_dates >= (min_t + cfg$pre_len) &
      placebo_dates <= (max_t - cfg$post_len)
  ]

  # Fallback to any month in baseline window with pre/post support
  if (length(placebo_dates) == 0) {
    placebo_dates <- seq.int(min_t + cfg$pre_len, max_t - cfg$post_len, by = 1L)
  }
  if (length(placebo_dates) == 0) stop("No valid placebo dates in baseline window.", call. = FALSE)

  n_to_treat <- round(length(baseline_states) * treated_share)
  n_to_treat <- max(2L, min(n_to_treat, length(baseline_states) - 1L))

  treated_states_sample <- sample(baseline_states, size = n_to_treat, replace = FALSE)
  placebo_dates_sample  <- sample(placebo_dates, size = n_to_treat, replace = TRUE)

  placebo_state <- tibble(
    state_abb = c(treated_states_sample, setdiff(baseline_states, treated_states_sample)),
    g_placebo = as.integer(c(placebo_dates_sample, rep(0L, length(baseline_states) - n_to_treat)))
  )

  unit_time_range %>%
    left_join(placebo_state, by = "state_abb") %>%
    mutate(
      g_placebo = replace_na(g_placebo, 0L),
      g_placebo = as.integer(g_placebo),
      g_placebo = if_else(
        g_placebo > 0L &
          (g_placebo < min_time_id + cfg$pre_len | g_placebo > max_time_id - cfg$post_len),
        0L,
        g_placebo
      )
    ) %>%
    select(unit_id, g_placebo)
}

impose_effect <- function(df, placebo_schedule, effect_log) {
  df %>%
    left_join(placebo_schedule, by = "unit_id") %>%
    mutate(
      g_placebo = replace_na(g_placebo, 0L),
      g_placebo = as.integer(g_placebo),
      D = as.integer(g_placebo > 0L & time_id >= g_placebo),
      outcome_sim = outcome + effect_log * as.numeric(D)
    )
}

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

  withCallingHandlers(
    do.call(did::att_gt, args),
    warning = function(w) {
      msg <- conditionMessage(w)
      if (grepl("some small groups", msg, ignore.case = TRUE) ||
          grepl("Not returning pre-test Wald statistic", msg, fixed = TRUE)) {
        invokeRestart("muffleWarning")
      } else {
        log_line("WARN(did): ", msg)
      }
    }
  )
}

run_estimator_and_extract_p <- function(df_sim, cfg, cluster_var, time_mapping) {
  out <- list(p = 1.0, est = NA_real_, se = NA_real_, fail = NA_character_)

  g_mapping <- df_sim %>%
    filter(!is.na(g_placebo) & g_placebo > 0L) %>%
    distinct(g_placebo) %>%
    left_join(time_mapping, by = c("g_placebo" = "time_id")) %>%
    transmute(g_placebo, g_placebo_seq = time_id_seq)

  df_in <- df_sim %>%
    left_join(time_mapping, by = "time_id") %>%
    left_join(g_mapping, by = "g_placebo") %>%
    mutate(gname = if_else(g_placebo == 0L, 0, as.numeric(coalesce(g_placebo_seq, 0L))))

  n_treated <- n_distinct(df_in$unit_id[df_in$gname > 0])
  n_never   <- n_distinct(df_in$unit_id[df_in$gname == 0])
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

    list(p = p, est = est, se = se, fail = NA_character_)
  }, error = function(e) {
    out$fail <- paste0("est_error: ", conditionMessage(e))
    out
  })
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

simulate_power_for_effect <- function(baseline, sched, cfg, effect_log, n_states) {
  cluster_var <- "state_abb"

  time_mapping <- baseline %>%
    distinct(time_id) %>%
    arrange(time_id) %>%
    mutate(time_id_seq = row_number())

  one_draw <- function(s) {
    set.seed(cfg$seed + s)
    placebo <- draw_placebo_schedule(sched, cfg, baseline)
    df_sim  <- impose_effect(baseline, placebo, effect_log)

    df_sim <- df_sim %>%
      left_join(time_mapping, by = "time_id") %>%
      mutate(time_id_seq = as.integer(time_id_seq)) %>%
      select(unit_id, state_abb, time_id, time_id_seq, month_date, outcome_sim, g_placebo)

    est_res <- run_estimator_and_extract_p(df_sim, cfg, cluster_var, time_mapping)
    tibble(sim = s, p = est_res$p, est = est_res$est, se = est_res$se, fail = est_res$fail %||% NA_character_)
  }

  draws <- purrr::map_dfr(seq_len(cfg$n_sims), one_draw)

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
    mean_est = mean(draws$est, na.rm = TRUE),
    median_se = median(draws$se, na.rm = TRUE)
  )
}

run_power_simulation <- function(cfg) {
  write_started_marker(cfg)

  log_line("=== CS power simulation (v5style) ===")
  log_line(glue("DRY_RUN={cfg$dry_run} TEST_MODE={cfg$test_mode}"))
  log_line(glue("DATA_FILE: {cfg$data_file}"))
  log_line(glue("OUT_DIR: {cfg$out_dir}"))
  log_line(glue("Outcome: {cfg$outcome}"))
  log_line(glue("N_SIMS={cfg$n_sims} alpha={cfg$alpha} target={cfg$power_target} pre={cfg$pre_len} post={cfg$post_len}"))
  log_line(glue("Effects(pct): {paste(cfg$effect_pcts, collapse=', ')}"))
  if (length(cfg$grid_n_states) > 0) log_line(glue("GRID_N_STATES: {paste(cfg$grid_n_states, collapse=', ')}"))

  panel <- load_panel(cfg)
  sched <- make_treat_schedule(panel)
  baseline_all <- build_untreated_sample(panel, sched)

  log_line(glue("Panel: states={n_distinct(panel$unit_id)} months={n_distinct(panel$time_id)} rows={nrow(panel)}"))
  log_line(glue("Baseline(untreated): states={n_distinct(baseline_all$unit_id)} months={n_distinct(baseline_all$time_id)} rows={nrow(baseline_all)}"))

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

  # stable ordering for nested subsets
  state_order <- baseline_all %>% count(unit_id, name = "n_rows") %>% arrange(desc(n_rows), unit_id)

  res_list <- list()
  idx <- 0L

  for (ns in grid) {
    keep <- state_order$unit_id[seq_len(ns)]
    baseline <- baseline_all %>% filter(unit_id %in% keep)
    if (n_distinct(baseline$unit_id) < 6) next

    for (el in cfg$effect_log) {
      idx <- idx + 1L
      res_list[[idx]] <- simulate_power_for_effect(
        baseline = baseline,
        sched = sched,
        cfg = cfg,
        effect_log = el,
        n_states = ns
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

  log_line("=== Done ===")
  invisible(list(power = res, mde = mde_tbl))
}

# Entrypoint
if (sys.nframe() == 0L) {
  tryCatch(
    run_power_simulation(cfg),
    error = function(e) {
      msg <- paste0("FATAL ERROR: ", conditionMessage(e))
      write_fatal(msg)
      message(msg)
      if (!interactive()) quit(status = 1)
      stop(e)
    }
  )
}
