#!/usr/bin/env Rscript
################################################################################
# power_simulation_cs_ets_merged_v46like.R
#
# PURPOSE
#   Power simulation for staggered adoption DiD using Callaway & Sant'Anna (did::att_gt),
#   built to stay very close to the v4_6 script that previously ran for you.
#
# INPUT
#   merged_ets_combined.csv  (state x month panel)
#     required cols: location_std, month_date, filings_count, filings_avg
#
# OUTPUT (OUT_DIR)
#   - power_by_effect.csv
#   - mde_summary.csv
#   - debug_one_draw.csv (only when DRY_RUN=TRUE)
#
# KEY CHOICES (mirrors the "ran" scripts)
#   - att_gt: panel=TRUE, control_group="notyettreated", est_method="ipw"
#   - baseline uses: never-treated + pre-periods of treated (per Black et al logic)
#   - baseline is NOT residualized (A1 only) to avoid fixest/lm/version issues on clusters
#   - p-values never NA: failures count as p=1 with a fail code
#
# ENV VARS (optional)
#   DATA_FILE=merged_ets_combined.csv
#   OUT_DIR=power_outputs
#   OUTCOME=log1p_filings_count|log1p_filings_avg
#   N_SIMS=5000
#   EFFECT_PCTS=0,0.01,0.02,0.05,0.08,0.10
#   ALPHA=0.05
#   PRE_LEN=24
#   POST_LEN=24
#   OPTION=A1             # baseline NOT residualized (more robust)
#   DRY_RUN=TRUE|FALSE    # builds baseline + draws one placebo schedule + writes debug_one_draw.csv
#   TEST_MODE=TRUE|FALSE  # forces tiny sims unless you override N_SIMS
#
# DID knobs (defaults are "stable")
#   DID_BSTRAP=FALSE|TRUE
#   DID_BITERS=0|200
#   DID_CTBAND=FALSE|TRUE
################################################################################

Sys.setenv(
  OMP_NUM_THREADS = "1",
  OPENBLAS_NUM_THREADS = "1",
  MKL_NUM_THREADS = "1",
  VECLIB_MAXIMUM_THREADS = "1",
  BLIS_NUM_THREADS = "1"
)

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(glue)
})

# ----------------------------- helpers ----------------------------------------

as_bool <- function(x, default = FALSE) {
  if (is.null(x) || identical(x, "")) return(default)
  x <- tolower(trimws(x))
  if (x %in% c("1","true","t","yes","y")) return(TRUE)
  if (x %in% c("0","false","f","no","n")) return(FALSE)
  default
}

parse_num_vec <- function(x, default) {
  if (is.null(x) || identical(trimws(x), "")) return(default)
  out <- suppressWarnings(as.numeric(strsplit(x, ",")[[1]]))
  out <- out[is.finite(out)]
  if (length(out) == 0) default else out
}

clean_key <- function(x) {
  x %>% as.character() %>% str_to_lower() %>% str_replace_all("[^a-z]", "")
}

date_to_time_id <- function(d) {
  d <- as.Date(d)
  lubridate::year(d) * 12L + lubridate::month(d)
}

pval_2sided <- function(z) 2 * stats::pnorm(-abs(z))

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

interp_mde <- function(effect_log, power, target = 0.8) {
  o <- order(effect_log)
  effect_log <- effect_log[o]
  power <- power[o]
  if (all(is.na(power))) return(NA_real_)
  if (max(power, na.rm = TRUE) < target) return(NA_real_)
  j <- which(power >= target)[1]
  if (j == 1) return(effect_log[1])
  x0 <- effect_log[j-1]; x1 <- effect_log[j]
  y0 <- power[j-1]; y1 <- power[j]
  if (!is.finite(y0) || !is.finite(y1) || (y1 - y0) == 0) return(effect_log[j])
  x0 + (target - y0) * (x1 - x0) / (y1 - y0)
}

# ----------------------------- cfg --------------------------------------------

cfg <- list(
  data_file = Sys.getenv("DATA_FILE", "merged_ets_combined.csv"),
  out_dir   = Sys.getenv("OUT_DIR", "power_outputs"),
  outcome   = Sys.getenv("OUTCOME", "log1p_filings_count"),
  n_sims    = as.integer(Sys.getenv("N_SIMS", "5000")),
  alpha     = as.numeric(Sys.getenv("ALPHA", "0.05")),
  pre_len   = as.integer(Sys.getenv("PRE_LEN", "24")),
  post_len  = as.integer(Sys.getenv("POST_LEN", "24")),
  effect_pcts = parse_num_vec(Sys.getenv("EFFECT_PCTS", "0,0.01,0.02,0.05,0.08,0.10"),
                              default = c(0,0.01,0.02,0.05,0.08,0.10)),
  option    = toupper(Sys.getenv("OPTION", "A1")),
  dry_run   = as_bool(Sys.getenv("DRY_RUN", "FALSE"), default = FALSE),
  test_mode = as_bool(Sys.getenv("TEST_MODE", "FALSE"), default = FALSE),
  seed      = as.integer(Sys.getenv("SEED", "123")),
  # did settings (keep close to v4_6 defaults, but with safer defaults)
  did_bstrap = as_bool(Sys.getenv("DID_BSTRAP", "FALSE"), default = FALSE),
  did_biters = as.integer(Sys.getenv("DID_BITERS", "0")),
  did_cband  = as_bool(Sys.getenv("DID_CTBAND", "FALSE"), default = FALSE),
  did_est_method = Sys.getenv("DID_EST_METHOD", "ipw")
)

cfg$option <- if (cfg$option %in% c("A1")) cfg$option else "A1"
if (cfg$option != "A1") message("OPTION forced to A1 (no A2 residualization).")
cfg$did_est_method <- if (cfg$did_est_method %in% c("ipw","dr")) cfg$did_est_method else "ipw"

if (cfg$test_mode && cfg$n_sims > 100) cfg$n_sims <- 50L

cfg$effect_log <- log1p(cfg$effect_pcts)

dir.create(cfg$out_dir, showWarnings = FALSE, recursive = TRUE)

cat("=== CS power simulation (v4_6-like) ===\n")
cat(glue("Data: {cfg$data_file}\nOut dir: {cfg$out_dir}\nOutcome: {cfg$outcome}\n"))
cat(glue("N_SIMS={cfg$n_sims} alpha={cfg$alpha} pre={cfg$pre_len} post={cfg$post_len} option={cfg$option}\n"))
cat(glue("Effects(pct): {paste(cfg$effect_pcts, collapse=', ')}\n"))
cat(glue("did: est_method={cfg$did_est_method} bstrap={cfg$did_bstrap} biters={cfg$did_biters}\n\n"))

# ----------------------------- data -------------------------------------------

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
      filings_count = as.numeric(filings_count),
      filings_avg   = as.numeric(filings_avg),
      log1p_filings_count = log(pmax(filings_count, 0) + 1),
      log1p_filings_avg   = log(pmax(filings_avg,   0) + 1)
    ) %>%
    filter(is.finite(time_id), !is.na(state_key))

  # collapse any accidental duplicates
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
      )
  }

  if (!(cfg$outcome %in% names(df))) stop(glue("Unknown OUTCOME={cfg$outcome}"), call. = FALSE)
  df <- df %>% mutate(outcome = .data[[cfg$outcome]]) %>% filter(is.finite(outcome))

  unit_map <- df %>% distinct(state_key) %>% arrange(state_key) %>% mutate(unit_id = row_number())
  df <- df %>% left_join(unit_map, by = "state_key") %>% mutate(state_abb = state_key)

  if (n_distinct(df$unit_id) < 6) stop("Too few states for DiD simulation.", call. = FALSE)
  if (n_distinct(df$time_id) < (cfg$pre_len + cfg$post_len + 12)) stop("Too few months for pre/post windows.", call. = FALSE)

  list(panel = df, unit_map = unit_map)
}

# ----------------------------- treatment schedule -----------------------------

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
    mutate(state_key = clean_key(state_key),
           online_launch_date = as.Date(online_launch_date),
           launch_month = floor_date(online_launch_date, "month"),
           g_id = date_to_time_id(launch_month))

  time_set <- sort(unique(panel_df$time_id))
  nearest_time <- function(g) if (is.na(g) || g <= 0) 0L else time_set[which.min(abs(time_set - g))]

  states <- panel_df %>% distinct(state_key, unit_id, state_abb)
  sched <- states %>%
    left_join(launch %>% select(state_key, g_id), by = "state_key") %>%
    mutate(
      g_id = if_else(is.na(g_id), 0L, as.integer(vapply(g_id, nearest_time, integer(1)))),
      ever_treated = g_id > 0L
    ) %>%
    select(unit_id, state_key, state_abb, g_id, ever_treated)

  sched
}

# ----------------------------- baseline (untreated sample) --------------------

build_untreated_sample <- function(panel_df, treat_schedule) {
  panel_df %>%
    left_join(treat_schedule %>% select(unit_id, g_id, ever_treated), by = "unit_id") %>%
    filter((!ever_treated) | (ever_treated & time_id < g_id))
}

residualize_outcome <- function(df_untreated) {
  # NOTE: unused in A1-only version.

  # Robust FE residualization that won't break across fixest versions.
  # Goal: subtract unit + time fixed effects from the untreated sample, then add back the mean
  # so the level stays interpretable.
  #
  # If fixest is available and works, use it. Otherwise fall back to lm().
  mu <- mean(df_untreated$outcome, na.rm = TRUE)

  if (requireNamespace("fixest", quietly = TRUE)) {
    out <- tryCatch({
      m <- fixest::feols(outcome ~ 1 | unit_id + time_id, data = df_untreated)
      r <- as.numeric(stats::residuals(m))
      # residuals length should match nrow(df_untreated) as long as there are no dropped obs;
      # but be defensive.
      if (length(r) == nrow(df_untreated)) {
        df_untreated %>% mutate(outcome = r + mu)
      } else {
        message("fixest residual length mismatch -> falling back to lm FE residualization.")
        NULL
      }
    }, error = function(e) {
      message("fixest FE residualization failed -> falling back to lm(). Reason: ", conditionMessage(e))
      NULL
    })
    if (!is.null(out)) return(out)
  }

  # Safe fallback: lm with factor FE (fine for your ~20-state panel)
  m2 <- stats::lm(outcome ~ factor(unit_id) + factor(time_id), data = df_untreated)
  df_untreated %>% mutate(outcome = as.numeric(stats::residuals(m2)) + mu)
}

# ----------------------------- placebo assignment -----------------------------

draw_placebo_schedule <- function(treat_schedule, cfg, baseline_df, n_switchers = NULL) {
  # mimic the treated share + shifted adoption dates, staying within each state's observed window
  unit_time_range <- baseline_df %>%
    group_by(unit_id, state_abb) %>%
    summarise(min_time_id = min(time_id), max_time_id = max(time_id), .groups = "drop")

  baseline_states <- sort(unique(unit_time_range$state_abb))
  baseline_states <- baseline_states[!is.na(baseline_states)]

  state_ts_full <- treat_schedule %>%
    distinct(state_abb, ever_treated, g_id) %>%
    filter(!is.na(state_abb))

  treated_share <- mean(state_ts_full$ever_treated, na.rm = TRUE)
  treated_share <- ifelse(is.finite(treated_share), treated_share, 0.5)

  # adoption dates among actually-treated states
  treatment_dates <- sort(unique(state_ts_full$g_id[state_ts_full$ever_treated]))
  treatment_dates <- treatment_dates[is.finite(treatment_dates) & treatment_dates > 0L]

  if (length(treatment_dates) == 0) stop("No treated adoption dates found in treat_schedule.", call. = FALSE)

  shift_months <- cfg$pre_len  # same spirit as v4_6 shifting by target horizon
  min_t <- min(baseline_df$time_id, na.rm = TRUE)
  max_t <- max(baseline_df$time_id, na.rm = TRUE)

  placebo_dates <- treatment_dates - shift_months
  placebo_dates <- placebo_dates[
    placebo_dates >= (min_t + cfg$pre_len) &
      placebo_dates <= (max_t - cfg$post_len)
  ]
  if (length(placebo_dates) == 0) stop("No valid placebo dates after shifting into baseline window.", call. = FALSE)

  n_to_treat <- if (is.null(n_switchers)) round(length(baseline_states) * treated_share) else as.integer(n_switchers)
  n_to_treat <- max(1L, min(n_to_treat, length(baseline_states) - 1L))

  treated_states_sample <- sample(baseline_states, size = n_to_treat, replace = FALSE)
  placebo_dates_sample  <- sample(placebo_dates, size = n_to_treat, replace = TRUE)

  placebo_state <- tibble(
    state_abb = c(treated_states_sample, setdiff(baseline_states, treated_states_sample)),
    g_placebo = c(placebo_dates_sample, rep(0L, length(baseline_states) - n_to_treat))
  )

  placebo_unit <- unit_time_range %>%
    left_join(placebo_state, by = "state_abb") %>%
    mutate(
      g_placebo = replace_na(g_placebo, 0L),
      g_placebo = if_else(
        g_placebo > 0L &
          (g_placebo < min_time_id + cfg$pre_len | g_placebo > max_time_id - cfg$post_len),
        0L,
        g_placebo
      )
    ) %>%
    select(unit_id, g_placebo)

  placebo_unit
}

impose_effect <- function(df, placebo_schedule, effect_log, cfg) {
  df2 <- df %>%
    left_join(placebo_schedule, by = "unit_id") %>%
    mutate(
      g_placebo = replace_na(g_placebo, 0L),
      D = as.integer(g_placebo > 0L & time_id >= g_placebo),
      event_time = if_else(g_placebo > 0L, time_id - g_placebo, NA_integer_)
    )

  mult <- case_when(
    TRUE ~ as.numeric(df2$D)
  )

  df2 %>% mutate(outcome_sim = outcome + effect_log * mult)
}

# ----------------------------- did wrappers -----------------------------------

att_gt_safe <- function(df_in, cfg, cluster_var) {
  if (!requireNamespace("did", quietly = TRUE)) stop("Package 'did' not available.", call. = FALSE)
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
      }
    }
  )
}

run_estimator_and_extract_p <- function(df_sim, cfg, cluster_var, time_mapping = NULL) {
  # Always return finite p; failures => p=1 with fail code.
  out <- list(p = 1.0, est = NA_real_, se = NA_real_, fail = NA_character_)

  if (is.null(time_mapping)) {
    time_mapping <- df_sim %>%
      distinct(time_id) %>%
      arrange(time_id) %>%
      mutate(time_id_seq = row_number())
  }

  g_mapping <- df_sim %>%
    filter(!is.na(g_placebo) & g_placebo > 0L) %>%
    distinct(g_placebo) %>%
    left_join(time_mapping, by = c("g_placebo" = "time_id")) %>%
    transmute(g_placebo, g_placebo_seq = time_id_seq)

  df_in <- df_sim %>%
    left_join(time_mapping, by = "time_id") %>%
    left_join(g_mapping, by = "g_placebo") %>%
    mutate(
      gname = if_else(is.na(g_placebo) | g_placebo == 0L, 0, as.numeric(coalesce(g_placebo_seq, 0L)))
    )

  if (!any(df_in$gname > 0, na.rm = TRUE)) {
    out$fail <- "no_treated_groups"
    return(out)
  }

  tryCatch({
    att <- att_gt_safe(df_in, cfg, cluster_var = cluster_var)

    agg_result <- tryCatch({
      agg <- withCallingHandlers(
        did::aggte(att, type = "simple"),
        warning = function(w) {
          msg <- conditionMessage(w)
          if (grepl("some small groups", msg, ignore.case = TRUE) ||
              grepl("Not returning pre-test Wald statistic", msg, fixed = TRUE)) {
            invokeRestart("muffleWarning")
          }
        }
      )
      list(success = TRUE, att = agg$overall.att, se = agg$overall.se)
    }, error = function(e) {
      # fallback: manual overall ATT + SE from influence function
      est_manual <- mean(att$att, na.rm = TRUE)
      se_manual <- NA_real_
      if (!is.null(att$inffunc) && length(dim(att$inffunc)) == 2 && nrow(att$inffunc) > 0) {
        inff <- att$inffunc
        inff_dense <- if (inherits(inff, "Matrix")) as.matrix(inff) else inff
        inf_simple <- rowMeans(inff_dense, na.rm = TRUE)
        se_manual <- sqrt(mean(inf_simple^2, na.rm = TRUE))
      }
      list(success = is.finite(est_manual) && is.finite(se_manual) && se_manual > 0,
           att = est_manual, se = se_manual)
    })

    if (!isTRUE(agg_result$success)) {
      out$fail <- "aggte_failed"
      return(out)
    }

    est <- as.numeric(agg_result$att)
    se  <- as.numeric(agg_result$se)
    if (!is.finite(est) || !is.finite(se) || se <= 0) {
      out$fail <- "invalid_se"
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

# ----------------------------- simulation -------------------------------------

simulate_power_for_effect <- function(baseline, treat_schedule, cfg, effect_log) {
  cluster_var <- "state_abb"

  time_mapping <- baseline %>%
    distinct(time_id) %>%
    arrange(time_id) %>%
    mutate(time_id_seq = row_number())

  one_draw <- function(s) {
    set.seed(cfg$seed + s)

    placebo_schedule <- draw_placebo_schedule(
      treat_schedule = treat_schedule,
      cfg = cfg,
      baseline_df = baseline,
      n_switchers = NULL
    )

    df_sim <- impose_effect(baseline, placebo_schedule, effect_log = effect_log, cfg = cfg)

    # enforce fields used downstream
    df_sim <- df_sim %>%
      left_join(time_mapping, by = "time_id") %>%
      mutate(time_id_seq = as.integer(time_id_seq)) %>%
      select(unit_id, state_abb, time_id, time_id_seq, month_date, outcome_sim, g_placebo)

    # group counts (guard rails)
    n_treated_units <- n_distinct(df_sim$unit_id[df_sim$g_placebo > 0])
    n_never_units   <- n_distinct(df_sim$unit_id[df_sim$g_placebo == 0])

    if (n_treated_units < 2) return(tibble(sim = s, p = 1.0, est = NA_real_, se = NA_real_, fail = "too_few_treated"))
    if (n_never_units < 2)   return(tibble(sim = s, p = 1.0, est = NA_real_, se = NA_real_, fail = "too_few_never"))

    est <- run_estimator_and_extract_p(df_sim, cfg, cluster_var = cluster_var, time_mapping = time_mapping)
    tibble(sim = s, p = est$p, est = est$est, se = est$se, fail = est$fail %||% NA_character_)
  }

  draws <- purrr::map_dfr(seq_len(cfg$n_sims), one_draw)

  power <- mean(draws$p <= cfg$alpha, na.rm = TRUE)
  if (is.nan(power)) power <- NA_real_

  tibble(
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
  loaded <- load_panel(cfg)
  panel <- loaded$panel
  treat_schedule <- make_treat_schedule(panel)

  baseline <- build_untreated_sample(panel, treat_schedule)
  if (nrow(baseline) == 0) stop("Baseline is empty after untreated filtering.", call. = FALSE)

  cat(glue("Panel: states={n_distinct(panel$unit_id)} months={n_distinct(panel$time_id)} rows={nrow(panel)}\n"))
  cat(glue("Baseline: states={n_distinct(baseline$unit_id)} months={n_distinct(baseline$time_id)} rows={nrow(baseline)}\n\n"))

  if (cfg$dry_run) {
    set.seed(cfg$seed)
    placebo <- draw_placebo_schedule(treat_schedule, cfg, baseline)
    dbg <- impose_effect(baseline, placebo, effect_log = cfg$effect_log[1], cfg = cfg) %>%
      select(state_abb, unit_id, month_date, time_id, g_placebo, outcome, outcome_sim)
    outp <- file.path(cfg$out_dir, "debug_one_draw.csv")
    readr::write_csv(dbg, outp)
    cat(glue("DRY_RUN wrote {outp}\n"))
    return(invisible(NULL))
  }

  # did package only needed if not dry_run
  if (!requireNamespace("did", quietly = TRUE)) stop("Package 'did' is required for estimation.", call. = FALSE)

  res <- purrr::map_dfr(cfg$effect_log, ~simulate_power_for_effect(baseline, treat_schedule, cfg, effect_log = .x))

  mde_log <- interp_mde(res$effect_log, res$power, target = 0.80)
  mde_tbl <- tibble(
    mde_log = mde_log,
    mde_pct = if_else(is.na(mde_log), NA_real_, expm1(mde_log)),
    max_power = max(res$power, na.rm = TRUE)
  )

  readr::write_csv(res, file.path(cfg$out_dir, "power_by_effect.csv"))
  readr::write_csv(mde_tbl, file.path(cfg$out_dir, "mde_summary.csv"))

  cat("=== Done ===\n")
  cat(glue("Wrote power_by_effect.csv and mde_summary.csv to {cfg$out_dir}\n"))
  invisible(list(power = res, mde = mde_tbl))
}

# ----------------------------- entrypoint -------------------------------------

if (sys.nframe() == 0L) {
  run_power_simulation(cfg)
}
