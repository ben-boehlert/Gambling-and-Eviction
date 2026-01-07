#!/usr/bin/env Rscript
################################################################################
# power_simulation_cs_ets_merged_bestof.R
#
# Monte Carlo power simulation for staggered-adoption DiD using Callaway & Sant'Anna (did).
# Input: merged_ets_combined.csv (or DATA_FILE env var).
#
# Baseline construction (Black et al. design logic):
#   - Use never-treated units PLUS pre-period observations of eventually-treated units
#     to learn the "typical" untreated variation.
# Placebo assignment:
#   - Randomly assign placebo adoption months and treated units, respecting
#     minimum pre/post windows.
# Effect:
#   - Add a constant log-shift to log1p outcome in post periods for treated units.
# Power:
#   - Rejection rate at ALPHA, using two-sided normal approx from overall ATT / SE.
#
# Crash-avoidance design:
#   - NO future/furrr/progressr (these can trigger R6 / parallel issues on some installs)
#   - Bootstrap defaults OFF (DID_BSTRAP=FALSE) for stability; can be enabled by env var.
#   - Estimation uses a ladder of fallbacks:
#       requested control_group -> notyettreated fallback
#       bootstrap+cluster -> bootstrap no cluster -> no bootstrap
#   - Failed fits NEVER produce NA p-values; failures are counted as p_value=1.0.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(ggplot2)
  library(lubridate)
  library(stringr)
  library(did)
  library(glue)
})

# ----------------------------- Helpers ----------------------------------------

stop_with <- function(...) {
  msg <- glue(...)
  stop(msg, call. = FALSE)
}

as_bool <- function(x, default = FALSE) {
  if (is.null(x) || identical(x, "")) return(default)
  x <- tolower(trimws(x))
  if (x %in% c("1","true","t","yes","y")) return(TRUE)
  if (x %in% c("0","false","f","no","n")) return(FALSE)
  default
}

parse_num_vec <- function(x, default) {
  if (is.null(x) || identical(trimws(x), "")) return(default)
  suppressWarnings(as.numeric(strsplit(x, ",")[[1]]))
}

clean_state_key <- function(x) {
  x %>%
    as.character() %>%
    str_to_lower() %>%
    str_replace_all("[^a-z]", "")
}

ym_to_int <- function(d) {
  d <- as.Date(d)
  year(d) * 12L + month(d)
}

pct_to_logshift <- function(p) log1p(p)
pval_2sided <- function(z) 2 * stats::pnorm(-abs(z))

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
  if (is.na(y0) || is.na(y1) || (y1 - y0) == 0) return(effect_log[j])
  x0 + (target - y0) * (x1 - x0) / (y1 - y0)
}

# ----------------------------- Configuration ----------------------------------

cfg <- list(
  data_file      = Sys.getenv("DATA_FILE", "merged_ets_combined.csv"),
  out_dir        = Sys.getenv("OUT_DIR", "power_outputs"),
  seed           = as.integer(Sys.getenv("SEED", "123")),
  n_sims         = as.integer(Sys.getenv("N_SIMS", "5000")),  # default "enough sims"
  alpha          = as.numeric(Sys.getenv("ALPHA", "0.05")),
  power_target   = as.numeric(Sys.getenv("POWER_TARGET", "0.80")),
  pre_len        = as.integer(Sys.getenv("PRE_LEN", "24")),
  post_len       = as.integer(Sys.getenv("POST_LEN", "24")),
  effect_pcts    = parse_num_vec(Sys.getenv("EFFECT_PCTS", "0,0.01,0.02,0.05,0.08,0.10,0.15"),
                                 default = c(0,0.01,0.02,0.05,0.08,0.10,0.15)),
  outcome_choice = Sys.getenv("OUTCOME", "log1p_filings_count"),
  control_group_requested = Sys.getenv("CONTROL_GROUP", "notyettreated"),
  did_bstrap     = as_bool(Sys.getenv("DID_BSTRAP", "FALSE"), default = FALSE),
  did_biters     = as.integer(Sys.getenv("DID_BITERS", "0")),
  max_redraw     = as.integer(Sys.getenv("MAX_REDRAW", "30")),
  n_switchers    = as.integer(Sys.getenv("N_SWITCHERS", "-1")),
  shift_months   = as.integer(Sys.getenv("SHIFT_MONTHS", "-1")),
  grid_n_states  = Sys.getenv("GRID_N_STATES", "")
)

cfg$effect_log <- pct_to_logshift(cfg$effect_pcts)
cfg$control_group_requested <- ifelse(nzchar(cfg$control_group_requested), cfg$control_group_requested, "notyettreated")
cfg$control_group_requested <- if (cfg$control_group_requested == "never_treated") "never_treated" else "notyettreated"
cfg$control_group <- cfg$control_group_requested

# allow small sims for quick checks when TEST_MODE=TRUE
test_mode <- as_bool(Sys.getenv("TEST_MODE", "FALSE"), default = FALSE)
if (!test_mode && (is.na(cfg$n_sims) || cfg$n_sims < 500)) stop_with("N_SIMS must be >= 500 unless TEST_MODE=TRUE (got {cfg$n_sims}).")
if (test_mode && (is.na(cfg$n_sims) || cfg$n_sims < 1)) stop_with("In TEST_MODE, N_SIMS must be >= 1.")
if (!(cfg$control_group %in% c("never_treated", "notyettreated"))) {
  stop_with("CONTROL_GROUP must be 'never_treated' or 'notyettreated' (got '{cfg$control_group_requested}').")
}
if (cfg$pre_len < 6 || cfg$post_len < 6) stop_with("PRE_LEN and POST_LEN must be >= 6 months.")
if (cfg$shift_months < 0) cfg$shift_months <- cfg$post_len + 1L

if (max(cfg$effect_log, na.rm = TRUE) > 1.0) {
  stop_with("Max EFFECT_PCTS implies log shift > 1.0 (got {round(max(cfg$effect_log),3)}). Fix EFFECT_PCTS.")
}

dir.create(cfg$out_dir, showWarnings = FALSE, recursive = TRUE)

cat("=== Power simulation (CS-DiD) ===\n")
cat(glue("TEST_MODE: {test_mode}\n"))
cat(glue("Data: {cfg$data_file}\n"))
cat(glue("Outcome: {cfg$outcome_choice}\n"))
cat(glue("N_SIMS: {cfg$n_sims}, alpha: {cfg$alpha}, target power: {cfg$power_target}\n"))
cat(glue("Pre window: {cfg$pre_len} months, Post window: {cfg$post_len} months\n"))
cat(glue("Control group requested: {cfg$control_group_requested}\n"))
cat(glue("Bootstrap: {cfg$did_bstrap} (biters={cfg$did_biters})\n"))
cat(glue("Effect grid (pct): {paste(cfg$effect_pcts, collapse=', ')}\n\n"))

# ----------------------------- Data loading -----------------------------------

load_panel <- function(cfg) {
  if (!file.exists(cfg$data_file)) stop_with("Could not find DATA_FILE='{cfg$data_file}' in working directory.")

  df <- readr::read_csv(cfg$data_file, show_col_types = FALSE)

  required <- c("location_std", "month_date", "filings_count", "filings_avg")
  missing <- setdiff(required, names(df))
  if (length(missing) > 0) stop_with("DATA_FILE is missing required columns: {paste(missing, collapse=', ')}")

  df <- df %>%
    mutate(
      month_date = as.Date(month_date),
      unit_id    = clean_state_key(location_std),
      time_id    = ym_to_int(month_date),
      filings_count = as.numeric(filings_count),
      filings_avg   = as.numeric(filings_avg),
      log1p_filings_count = log(pmax(filings_count, 0) + 1),
      log1p_filings_avg   = log(pmax(filings_avg,   0) + 1)
    ) %>%
    filter(!is.na(unit_id), !is.na(time_id))

  # ensure unique id-time
  if (any(duplicated(df[, c("unit_id","time_id")]))) {
    df <- df %>%
      group_by(unit_id, time_id, month_date) %>%
      summarise(
        filings_count = sum(filings_count, na.rm = TRUE),
        filings_avg   = mean(filings_avg, na.rm = TRUE),
        log1p_filings_count = log(pmax(filings_count,0)+1),
        log1p_filings_avg   = log(pmax(filings_avg,0)+1),
        .groups = "drop"
      )
  }

  if (!(cfg$outcome_choice %in% names(df))) {
    stop_with("OUTCOME='{cfg$outcome_choice}' not found. Options include: {paste(names(df), collapse=', ')}")
  }
  df <- df %>% mutate(outcome = .data[[cfg$outcome_choice]]) %>% filter(!is.na(outcome))

  if (n_distinct(df$unit_id) < 6) stop_with("Too few units after cleaning: {n_distinct(df$unit_id)}.")
  if (n_distinct(df$time_id) < (cfg$pre_len + cfg$post_len + 6)) {
    stop_with("Not enough time periods ({n_distinct(df$time_id)}) for PRE_LEN+POST_LEN={cfg$pre_len + cfg$post_len}.")
  }
  df
}

panel <- load_panel(cfg)
cat(glue("Panel: {n_distinct(panel$unit_id)} states, {n_distinct(panel$time_id)} months, {nrow(panel)} rows\n"))
cat(glue("Date range: {min(panel$month_date)} to {max(panel$month_date)}\n\n"))

# ----------------------------- Real treatment schedule -------------------------
# Used to define baseline untreated observations + mimic timing distribution.
default_online_launch <- tibble::tribble(
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
    state_key = clean_state_key(state_key),
    online_launch_date = as.Date(online_launch_date)
  )

make_treat_schedule <- function(panel, default_map) {
  states <- tibble(unit_id = sort(unique(panel$unit_id)))

  sched <- states %>%
    mutate(state_key = unit_id) %>%
    left_join(default_map, by = "state_key") %>%
    mutate(
      launch_month = if_else(!is.na(online_launch_date),
                             floor_date(online_launch_date, "month"),
                             as.Date(NA)),
      g_real = if_else(!is.na(launch_month), ym_to_int(launch_month), 0L),
      g_real = as.integer(g_real)
    ) %>%
    select(unit_id, g_real)

  min_t <- min(panel$time_id)
  sched <- sched %>% mutate(g_real = if_else(g_real > 0L & g_real <= min_t, 0L, g_real))

  time_set <- sort(unique(panel$time_id))
  nearest_time <- function(g) if (g == 0L) 0L else time_set[which.min(abs(time_set - g))]
  sched %>% mutate(g_real = vapply(g_real, nearest_time, integer(1)))
}

treat_schedule <- make_treat_schedule(panel, default_online_launch)
n_real_treated <- sum(treat_schedule$g_real > 0L)
cat(glue("Real schedule: {n_real_treated} treated (g_real>0) out of {nrow(treat_schedule)} states\n\n"))

# ----------------------------- Untreated baseline sample -----------------------

build_untreated_sample <- function(panel, treat_schedule) {
  df <- panel %>%
    left_join(treat_schedule, by = "unit_id") %>%
    mutate(g_real = if_else(is.na(g_real), 0L, as.integer(g_real))) %>%
    filter(g_real == 0L | time_id < g_real)

  ranges <- df %>%
    group_by(unit_id) %>%
    summarise(min_t = min(time_id), max_t = max(time_id), .groups = "drop")

  list(df = df, ranges = ranges)
}

base <- build_untreated_sample(panel, treat_schedule)
baseline <- base$df
unit_ranges <- base$ranges

cat(glue("Untreated baseline: {nrow(baseline)} rows\n"))
cat(glue("Baseline date range: {min(baseline$month_date)} to {max(baseline$month_date)}\n\n"))

# ----------------------------- Placebo schedule draw ---------------------------

make_placebo_g_pool <- function(baseline, treat_schedule, cfg) {
  time_set <- sort(unique(baseline$time_id))
  min_t <- min(time_set)
  max_t <- max(time_set)

  real_g <- sort(unique(treat_schedule$g_real[treat_schedule$g_real > 0L]))
  g_pool <- integer(0)
  if (length(real_g) > 0) g_pool <- real_g - cfg$shift_months

  g_pool <- unique(g_pool)
  g_pool <- g_pool[g_pool >= (min_t + cfg$pre_len) & g_pool <= (max_t - cfg$post_len)]
  g_pool <- sort(g_pool)

  if (length(g_pool) == 0) {
    g_pool <- time_set[time_set >= (min_t + cfg$pre_len) & time_set <= (max_t - cfg$post_len)]
  }
  g_pool
}

draw_placebo_schedule <- function(unit_ranges, g_pool, cfg, n_treat_desired) {
  eligible <- unit_ranges %>%
    mutate(g_min = min_t + cfg$pre_len,
           g_max = max_t - cfg$post_len) %>%
    filter(g_min <= g_max)

  if (nrow(eligible) < (n_treat_desired + 2)) {
    stop_with("Not enough eligible states: eligible={nrow(eligible)}, desired treated={n_treat_desired}.")
  }

  treated_states <- sample(eligible$unit_id, size = n_treat_desired, replace = FALSE)

  sched <- unit_ranges %>% transmute(unit_id, g_placebo = 0L)

  for (u in treated_states) {
    rr <- eligible %>% filter(unit_id == u)
    g_min <- rr$g_min[[1]]
    g_max <- rr$g_max[[1]]
    g_candidates <- g_pool[g_pool >= g_min & g_pool <= g_max]
    if (length(g_candidates) == 0) next
    sched$g_placebo[sched$unit_id == u] <- as.integer(sample(g_candidates, size = 1))
  }
  sched
}

# ----------------------------- did estimator wrapper ---------------------------

make_time_maps <- function(df_in) {
  time_map <- df_in %>%
    distinct(time_id) %>%
    arrange(time_id) %>%
    mutate(t_seq = row_number())

  g_map <- time_map %>% transmute(g_placebo = time_id, g_seq = t_seq)
  list(time_map = time_map, g_map = g_map)
}

# Never returns NA p-values: failures return p_value=1.0
estimate_cs_overall <- function(df_in, cfg) {
  maps <- make_time_maps(df_in)
  df <- df_in %>%
    left_join(maps$time_map, by = "time_id") %>%
    left_join(maps$g_map, by = "g_placebo") %>%
    mutate(
      t_seq = as.integer(t_seq),
      g_seq = as.integer(if_else(is.na(g_seq), 0L, g_seq))
    )

  n_treated <- n_distinct(df$unit_id[df$g_seq > 0L])
  n_never   <- n_distinct(df$unit_id[df$g_seq == 0L])
  if (n_treated < 2 || n_never < 2) {
    return(list(ok = FALSE, p_value = 1.0, att = NA_real_, se = NA_real_,
                reason = glue("insufficient groups: treated={n_treated}, never={n_never}"),
                control_group_used = cfg$control_group))
  }

  run_att <- function(control_group, cluster, bstrap_flag) {
    args <- list(
      yname = "y_sim",
      tname = "t_seq",
      idname = "unit_id",
      gname = "g_seq",
      xformla = ~ 1,
      data = df,
      control_group = control_group,
      bstrap = isTRUE(bstrap_flag),
      biters = if (isTRUE(bstrap_flag)) as.integer(cfg$did_biters) else 0L,
      est_method = "dr"
    )

    if (isTRUE(bstrap_flag) && isTRUE(cluster)) args$clustervars <- "unit_id"
    fmls <- names(formals(did::att_gt))
    if ("allow_unbalanced_panel" %in% fmls) args$allow_unbalanced_panel <- TRUE
    if ("print_details" %in% fmls) args$print_details <- FALSE
    do.call(did::att_gt, args)
  }

  fallback_control <- "notyettreated"

  attempts <- list(
    list(control = cfg$control_group, cluster = TRUE,  bstrap = cfg$did_bstrap),
    list(control = cfg$control_group, cluster = FALSE, bstrap = cfg$did_bstrap),
    list(control = cfg$control_group, cluster = FALSE, bstrap = FALSE),
    list(control = fallback_control,  cluster = TRUE,  bstrap = cfg$did_bstrap),
    list(control = fallback_control,  cluster = FALSE, bstrap = cfg$did_bstrap),
    list(control = fallback_control,  cluster = FALSE, bstrap = FALSE)
  )

  att_obj <- NULL
  used <- NULL
  last_err <- NULL

  for (a in attempts) {
    att_obj <- tryCatch(run_att(a$control, a$cluster, a$bstrap),
                        error = function(e) { last_err <<- e; NULL })
    if (!is.null(att_obj)) { used <- a; break }
  }

  if (is.null(att_obj)) {
    msg <- if (!is.null(last_err)) conditionMessage(last_err) else "unknown"
    return(list(ok = FALSE, p_value = 1.0, att = NA_real_, se = NA_real_,
                reason = glue("att_gt error: {msg}"), control_group_used = cfg$control_group))
  }

  agg <- tryCatch(did::aggte(att_obj, type = "simple"), error = function(e) NULL)
  if (is.null(agg)) {
    return(list(ok = FALSE, p_value = 1.0, att = NA_real_, se = NA_real_,
                reason = "aggte(simple) failed", control_group_used = used$control))
  }

  att_hat <- as.numeric(agg$overall.att)
  se_hat  <- as.numeric(agg$overall.se)

  if (!is.finite(att_hat)) {
    return(list(ok = FALSE, p_value = 1.0, att = NA_real_, se = se_hat,
                reason = "overall ATT missing", control_group_used = used$control))
  }

  # if SE missing, compute from influence function if available
  if (!is.finite(se_hat) || is.na(se_hat) || se_hat <= 0) {
    IF <- NULL
    if (!is.null(att_obj$inffunc)) IF <- att_obj$inffunc
    if (!is.null(IF)) {
      IFm <- as.matrix(IF)
      IFv <- rowMeans(IFm, na.rm = TRUE)
      IFv <- IFv[is.finite(IFv)]
      if (length(IFv) > 10) se_hat <- sqrt(mean(IFv^2, na.rm = TRUE))
    }
  }

  if (!is.finite(se_hat) || is.na(se_hat) || se_hat <= 0) {
    return(list(ok = FALSE, p_value = 1.0, att = att_hat, se = se_hat,
                reason = "overall SE missing/invalid", control_group_used = used$control))
  }

  z <- att_hat / se_hat
  p <- pval_2sided(z)
  if (!is.finite(p) || is.na(p)) p <- 1.0

  list(ok = TRUE, p_value = p, att = att_hat, se = se_hat,
       reason = NA_character_, control_group_used = used$control)
}

# ----------------------------- One simulation draw -----------------------------

one_sim <- function(sim_id, effect_log, baseline, unit_ranges, g_pool, cfg, n_treat_desired) {
  set.seed(cfg$seed + sim_id)

  sched <- NULL
  for (k in seq_len(cfg$max_redraw)) {
    sched <- tryCatch(draw_placebo_schedule(unit_ranges, g_pool, cfg, n_treat_desired),
                      error = function(e) NULL)
    if (!is.null(sched)) break
  }
  if (is.null(sched)) {
    return(list(ok = FALSE, p_value = 1.0, att = NA_real_, se = NA_real_,
                reason = "placebo draw failed", control_group_used = cfg$control_group))
  }

  df_sim <- baseline %>%
    left_join(sched %>% select(unit_id, g_placebo), by = "unit_id") %>%
    mutate(
      g_placebo = if_else(is.na(g_placebo), 0L, as.integer(g_placebo)),
      treated   = g_placebo > 0L,
      post      = treated & (time_id >= g_placebo),
      y_sim     = if_else(post, outcome + effect_log, outcome)
    )

  estimate_cs_overall(df_sim, cfg)
}

# ----------------------------- Run (maybe on subsets) --------------------------

if (cfg$n_switchers > 0) {
  n_treat_desired <- cfg$n_switchers
} else {
  n_treat_desired <- max(2L, min(n_real_treated, n_distinct(baseline$unit_id) - 2L))
}
if (n_treat_desired >= n_distinct(baseline$unit_id)) stop_with("Too many switchers for baseline size.")
cat(glue("Per-sim treated states (placebo): {n_treat_desired}\n\n"))

grid_n_states <- parse_num_vec(cfg$grid_n_states, default = numeric(0))
if (length(grid_n_states) > 0) grid_n_states <- sort(unique(as.integer(grid_n_states)))

state_order <- baseline %>%
  count(unit_id, name = "n_rows") %>%
  arrange(desc(n_rows), unit_id)

make_subset <- function(n_states) {
  keep <- state_order$unit_id[seq_len(min(n_states, nrow(state_order)))]
  list(
    baseline = baseline %>% filter(unit_id %in% keep),
    unit_ranges = unit_ranges %>% filter(unit_id %in% keep)
  )
}

subset_grid <- if (length(grid_n_states) == 0) {
  data.frame(n_states = n_distinct(baseline$unit_id))
} else {
  data.frame(n_states = grid_n_states) |>
    dplyr::filter(n_states >= 6, n_states <= n_distinct(baseline$unit_id))
}

results <- list()

for (g in seq_len(nrow(subset_grid))) {
  n_states <- subset_grid$n_states[g]
  cat(glue("Running subset n_states={n_states}...\n"))

  sub <- make_subset(n_states)
  base_s <- sub$baseline
  ranges_s <- sub$unit_ranges

  g_pool <- make_placebo_g_pool(base_s, treat_schedule, cfg)
  if (length(g_pool) < 2) stop_with("Subset n_states={n_states}: too few feasible placebo months.")

  n_treat <- min(n_treat_desired, n_distinct(base_s$unit_id) - 2L)
  n_treat <- max(2L, n_treat)

  for (j in seq_along(cfg$effect_log)) {
    effect_log <- cfg$effect_log[j]
    pvals <- numeric(cfg$n_sims)
    okv   <- logical(cfg$n_sims)
    atts  <- rep(NA_real_, cfg$n_sims)
    ses   <- rep(NA_real_, cfg$n_sims)
    usedc <- character(cfg$n_sims)

    for (s in seq_len(cfg$n_sims)) {
      est <- one_sim(s, effect_log, base_s, ranges_s, g_pool, cfg, n_treat)
      pvals[s] <- est$p_value
      okv[s]   <- isTRUE(est$ok)
      atts[s]  <- est$att
      ses[s]   <- est$se
      usedc[s] <- est$control_group_used
    }

    power <- mean(pvals <= cfg$alpha)
    fail_rate <- mean(!okv)
    mean_att <- mean(atts, na.rm = TRUE)
    median_se <- stats::median(ses, na.rm = TRUE)

    results[[length(results) + 1]] <- data.frame(
      n_states = n_states,
      effect_log = effect_log,
      effect_pct = expm1(effect_log),
      power = power,
      alpha = cfg$alpha,
      control_group_requested = cfg$control_group_requested,
      control_group_used = if (any(nzchar(usedc))) usedc[which(nzchar(usedc))[1]] else cfg$control_group,
      fail_rate = fail_rate,
      mean_att = mean_att,
      median_se = median_se,
      n_sims = cfg$n_sims,
      stringsAsFactors = FALSE
    )
  }
}

all_results <- dplyr::bind_rows(results)

mde_tbl <- all_results %>%
  group_by(n_states) %>%
  summarise(
    mde_log = interp_mde(effect_log, power, target = cfg$power_target),
    mde_pct = if_else(is.na(mde_log), NA_real_, expm1(mde_log)),
    max_power = max(power, na.rm = TRUE),
    .groups = "drop"
  )

out_csv <- file.path(cfg$out_dir, "power_by_effect.csv")
readr::write_csv(all_results, out_csv)

out_mde <- file.path(cfg$out_dir, "mde_summary.csv")
readr::write_csv(mde_tbl, out_mde)

plt <- ggplot(all_results, aes(x = effect_pct, y = power, group = factor(n_states))) +
  geom_line() +
  geom_point(size = 1.2) +
  geom_hline(yintercept = cfg$power_target, linetype = "dashed") +
  scale_x_continuous(labels = scales::percent_format(accuracy = 1)) +
  scale_y_continuous(limits = c(0, 1)) +
  labs(
    x = "Imposed effect on (y+1) (percent change)",
    y = "Power (Pr[p ≤ alpha])",
    title = "Simulated power curve (CS-DiD)",
    subtitle = glue("alpha={cfg$alpha}, target={cfg$power_target}, sims={cfg$n_sims}, pre={cfg$pre_len}m post={cfg$post_len}m; control={cfg$control_group_requested}")
  ) +
  theme_minimal()

out_png <- file.path(cfg$out_dir, "power_curve.png")
ggsave(out_png, plt, width = 8.5, height = 5.2, dpi = 180)

out_txt <- file.path(cfg$out_dir, "README_results.txt")
txt <- c(
  "Simulated power analysis (CS-DiD) outputs",
  "",
  glue("Data file: {cfg$data_file}"),
  glue("Outcome: {cfg$outcome_choice}"),
  glue("N_SIMS: {cfg$n_sims}; alpha={cfg$alpha}; target power={cfg$power_target}"),
  glue("Required pre months: {cfg$pre_len}; required post months: {cfg$post_len}"),
  glue("Control group requested: {cfg$control_group_requested} (estimator may fallback if needed)"),
  glue("Bootstrap: {cfg$did_bstrap} (biters={cfg$did_biters})"),
  glue("Placebo treated states per sim: {n_treat_desired}"),
  "",
  "Files written:",
  glue("- {basename(out_csv)}"),
  glue("- {basename(out_mde)}"),
  glue("- {basename(out_png)}"),
  "",
  "Interpretation notes:",
  "- 'power' is the share of simulations rejecting at alpha (two-sided) when the imposed effect is present.",
  "- 'fail_rate' is the share of simulations where the CS estimator could not produce a valid overall SE; these are counted as non-rejections.",
  "- MDE is interpolated; if max_power < target, MDE is NA and max_power is reported."
)
writeLines(txt, out_txt)

cat("\n=== Done ===\n")
cat(glue("Wrote: {out_csv}\n"))
cat(glue("Wrote: {out_mde}\n"))
cat(glue("Wrote: {out_png}\n"))
cat(glue("Wrote: {out_txt}\n"))
