#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(fixest)
  library(did)
  library(tibble)
  library(parallel)
})

getenv1 <- function(key, default = "") {
  v <- Sys.getenv(key, unset = default)
  if (!nzchar(v)) default else v
}

parse_num <- function(x, default = NA_real_) {
  if (!nzchar(x)) return(default)
  suppressWarnings(as.numeric(x))
}

parse_int <- function(x, default = NA_integer_) {
  if (!nzchar(x)) return(default)
  suppressWarnings(as.integer(x))
}

parse_num_list <- function(x, default = numeric()) {
  if (!nzchar(x)) return(default)
  parts <- strsplit(x, ",", fixed = TRUE)[[1]]
  out <- suppressWarnings(as.numeric(trimws(parts)))
  out[is.finite(out)]
}

parse_chr_list <- function(x, default = character()) {
  if (!nzchar(x)) return(default)
  trimws(strsplit(x, ",", fixed = TRUE)[[1]])
}

parse_bool <- function(x, default = FALSE) {
  if (!nzchar(x)) return(default)
  x <- toupper(trimws(x))
  x %in% c("1", "TRUE", "T", "YES", "Y")
}

ym_index <- function(date) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
}

fips_to_state_abb <- function(state_fips) {
  lookup <- c(
    `1` = "AL", `2` = "AK", `4` = "AZ", `5` = "AR", `6` = "CA", `8` = "CO", `9` = "CT",
    `10` = "DE", `11` = "DC", `12` = "FL", `13` = "GA", `15` = "HI", `16` = "ID",
    `17` = "IL", `18` = "IN", `19` = "IA", `20` = "KS", `21` = "KY", `22` = "LA",
    `23` = "ME", `24` = "MD", `25` = "MA", `26` = "MI", `27` = "MN", `28` = "MS",
    `29` = "MO", `30` = "MT", `31` = "NE", `32` = "NV", `33` = "NH", `34` = "NJ",
    `35` = "NM", `36` = "NY", `37` = "NC", `38` = "ND", `39` = "OH", `40` = "OK",
    `41` = "OR", `42` = "PA", `44` = "RI", `45` = "SC", `46` = "SD", `47` = "TN",
    `48` = "TX", `49` = "UT", `50` = "VT", `51` = "VA", `53` = "WA", `54` = "WV",
    `55` = "WI", `56` = "WY"
  )
  unname(lookup[as.character(as.integer(state_fips))])
}

state_abbr_from_geoid <- function(geo_id) {
  x <- tolower(trimws(as.character(geo_id)))
  key <- gsub("[^a-z]", "", x)
  name_key <- gsub("[^a-z]", "", tolower(state.name))
  m <- setNames(state.abb, name_key)
  unname(m[key])
}

build_state_panel <- function(df) {
  county_state <- df %>%
    filter(geo_level == "county") %>%
    mutate(
      fips_num = suppressWarnings(as.integer(fips)),
      state_fips = as.integer(floor(fips_num / 1000)),
      state_abb = fips_to_state_abb(state_fips),
      month_date = as.Date(month_date),
      filings_count = as.numeric(filings_count),
      renter_occupied_housing_units = as.numeric(renter_occupied_housing_units)
    ) %>%
    filter(!is.na(state_abb), !is.na(month_date)) %>%
    group_by(state_abb, month_date) %>%
    summarise(
      filings_count = sum(filings_count, na.rm = TRUE),
      renter_occupied_housing_units = sum(renter_occupied_housing_units, na.rm = TRUE),
      .groups = "drop"
    )

  county_states <- unique(county_state$state_abb)

  state_fallback <- df %>%
    filter(geo_level == "state") %>%
    transmute(
      state_abb = state_abbr_from_geoid(geo_id),
      month_date = as.Date(month_date),
      filings_count = as.numeric(filings_count),
      renter_occupied_housing_units = as.numeric(renter_occupied_housing_units)
    ) %>%
    filter(!is.na(state_abb), !is.na(month_date)) %>%
    filter(!(state_abb %in% county_states))

  bind_rows(county_state, state_fallback) %>%
    arrange(state_abb, month_date)
}

run_serial_or_parallel <- function(X, FUN, cores = 1L) {
  cores <- as.integer(max(1L, cores))
  if (cores <= 1L) return(lapply(X, FUN))
  if (.Platform$OS.type == "windows") return(lapply(X, FUN))
  mclapply(X, FUN, mc.cores = cores)
}

DATA_FILE <- getenv1("DATA_FILE", "backup_cleanup_20260112_094739/combined_monthly_panel.csv")
TREAT_FILE <- getenv1("TREAT_FILE", "backup_cleanup_20260112_094739/state_month_panel_with_treatment.csv")
OUT_DIR <- getenv1("OUT_DIR", "output/cs_threshold_sweep_nocovid_small")

SEED <- parse_int(getenv1("SEED", "123"), 123L)
N_SIMS <- parse_int(getenv1("N_SIMS", "25"), 25L)
ALPHA <- parse_num(getenv1("ALPHA", "0.05"), 0.05)
EFFECT_PCTS <- parse_num_list(getenv1("EFFECT_PCTS", "0,0.05,0.1,0.15,0.2"), c(0, 0.05, 0.1, 0.15, 0.2))
THRESHOLDS <- parse_num_list(getenv1("COVERAGE_THRESHOLDS", "0,40,60,80,100,110,117"), c(0, 40, 60, 80, 100, 110, 117))
THRESHOLDS <- sort(unique(as.integer(THRESHOLDS)))

OUTCOME <- getenv1("OUTCOME", "log1p_filings_count")
RATE_EPS <- parse_num(getenv1("RATE_EPS", "0.01"), 0.01)

EXCLUDE_STATES <- parse_chr_list(getenv1("EXCLUDE_STATES", "ME"), character())
MAX_DATE <- as.Date(getenv1("MAX_DATE", "2024-12-31"))
MIN_STATES_PER_MONTH <- parse_int(getenv1("MIN_STATES_PER_MONTH", "5"), 5L)
DID_FASTER_MODE <- parse_bool(getenv1("DID_FASTER_MODE", "FALSE"), FALSE)
DID_BSTRAP <- parse_bool(getenv1("DID_BSTRAP", "FALSE"), FALSE)
DID_BITERS <- parse_int(getenv1("DID_BITERS", "199"), 199L)
did_allow_unbalanced <- parse_bool(getenv1("DID_ALLOW_UNBALANCED_PANEL", "FALSE"), FALSE)
DEBUG_ERRORS <- parse_bool(getenv1("DEBUG_ERRORS", "FALSE"), FALSE)

EXCLUDE_START <- as.Date(getenv1("EXCLUDE_START", ""))
EXCLUDE_END <- as.Date(getenv1("EXCLUDE_END", ""))

req_cores <- parse_int(getenv1("N_CORES", ""), NA_integer_)
if (!is.finite(req_cores) || req_cores < 1L) {
  req_cores <- max(1L, parallel::detectCores(logical = FALSE) - 1L)
}
N_CORES <- max(1L, req_cores)

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

cat("CS threshold sweep configuration\n")
cat("DATA_FILE:", DATA_FILE, "\n")
cat("TREAT_FILE:", TREAT_FILE, "\n")
cat("OUT_DIR:", OUT_DIR, "\n")
cat("N_SIMS:", N_SIMS, "ALPHA:", ALPHA, "SEED:", SEED, "\n")
cat("EFFECT_PCTS:", paste(EFFECT_PCTS, collapse = ","), "\n")
cat("COVERAGE_THRESHOLDS:", paste(THRESHOLDS, collapse = ","), "\n")
cat("OUTCOME:", OUTCOME, "RATE_EPS:", RATE_EPS, "\n")
cat("EXCLUDE_STATES:", ifelse(length(EXCLUDE_STATES) > 0, paste(EXCLUDE_STATES, collapse = ","), "none"), "\n")
cat("MAX_DATE:", as.character(MAX_DATE), "\n")
cat("MIN_STATES_PER_MONTH:", MIN_STATES_PER_MONTH, "\n")
cat("DID_FASTER_MODE:", DID_FASTER_MODE, "\n")
cat("DID_BSTRAP:", DID_BSTRAP, "DID_BITERS:", DID_BITERS, "\n")
cat("DID_ALLOW_UNBALANCED_PANEL:", did_allow_unbalanced, "\n")
cat("DEBUG_ERRORS:", DEBUG_ERRORS, "\n")
cat("EXCLUDE_START/END (resid pool only):", as.character(EXCLUDE_START), as.character(EXCLUDE_END), "\n")
cat("N_CORES:", N_CORES, "\n\n")

if (!file.exists(DATA_FILE)) stop("DATA_FILE not found: ", DATA_FILE, call. = FALSE)
if (!file.exists(TREAT_FILE)) stop("TREAT_FILE not found: ", TREAT_FILE, call. = FALSE)

raw <- readr::read_csv(DATA_FILE, show_col_types = FALSE)
panel_raw <- build_state_panel(raw)
panel_raw <- panel_raw %>%
  mutate(
    filings_per_1k_renters = if_else(
      is.finite(renter_occupied_housing_units) & renter_occupied_housing_units > 0,
      1000 * as.numeric(filings_count) / as.numeric(renter_occupied_housing_units),
      NA_real_
    )
  )

treat <- readr::read_csv(TREAT_FILE, show_col_types = FALSE) %>%
  transmute(
    state_abb = as.character(state_abb),
    month_date = as.Date(month_date),
    treat_start = as.Date(treat_start)
  )

panel0 <- panel_raw %>%
  left_join(treat, by = c("state_abb", "month_date")) %>%
  filter(state_abb %in% unique(treat$state_abb))

if (length(EXCLUDE_STATES) > 0) {
  panel0 <- panel0 %>% filter(!(state_abb %in% EXCLUDE_STATES))
}
if (!is.na(MAX_DATE)) {
  panel0 <- panel0 %>% filter(month_date <= MAX_DATE)
}

coverage <- panel0 %>%
  count(state_abb, name = "n_months") %>%
  arrange(desc(n_months), state_abb)
readr::write_csv(coverage, file.path(OUT_DIR, "coverage_by_state.csv"))

max_coverage <- if (nrow(coverage) > 0) max(coverage$n_months, na.rm = TRUE) else NA_integer_
if (is.finite(max_coverage)) {
  bad_thr <- THRESHOLDS[THRESHOLDS > max_coverage]
  if (length(bad_thr) > 0L) {
    cat("WARNING: Some thresholds exceed max possible coverage (", max_coverage, "): ",
        paste(bad_thr, collapse = ","), "\n", sep = "")
  }
}

sim_seeds <- SEED + seq_len(N_SIMS) * 10007L

all_rows <- list()
summary_rows <- list()

for (thr in THRESHOLDS) {
  cat("\nStarting threshold", thr, "...\n")
  if (!is.na(max_coverage) && thr > max_coverage) {
    summary_rows[[length(summary_rows) + 1L]] <- tibble(
      coverage_threshold = thr,
      n_states = 0L,
      n_rows = 0L,
      n_months = 0L,
      mde80 = NA_real_,
      zero_power = NA_real_,
      note = "skipped_threshold_gt_max_coverage"
    )
    next
  }
  keep_states <- coverage %>%
    filter(n_months >= thr) %>%
    pull(state_abb)

  panel <- panel0 %>% filter(state_abb %in% keep_states)
  n_states <- n_distinct(panel$state_abb)

  if (n_states < 8L || nrow(panel) < 200L) {
    summary_rows[[length(summary_rows) + 1L]] <- tibble(
      coverage_threshold = thr,
      n_states = n_states,
      n_rows = nrow(panel),
      n_months = n_distinct(panel$month_date),
      mde80 = NA_real_,
      zero_power = NA_real_,
      note = "skipped_too_small"
    )
    next
  }

  panel <- panel %>%
    group_by(state_abb) %>%
    mutate(
      treat_start_state = if (all(is.na(treat_start))) as.Date(NA) else min(treat_start, na.rm = TRUE)
    ) %>%
    ungroup() %>%
    mutate(
      t = ym_index(month_date),
      g = ifelse(is.na(treat_start_state), 0L, ym_index(treat_start_state)),
      g = as.integer(g),
      id = as.integer(as.factor(state_abb)),
      post_treat = (g > 0L) & (t >= g),
      untreated_obs = (g == 0L) | (t < g),
      y = dplyr::case_when(
        OUTCOME == "log1p_filings_count" ~ log1p(pmax(as.numeric(filings_count), 0)),
        OUTCOME == "log1p_rate" ~ log(pmax(as.numeric(filings_per_1k_renters), 0) + RATE_EPS),
        TRUE ~ NA_real_
      )
    )
  if (!OUTCOME %in% c("log1p_filings_count", "log1p_rate")) {
    stop("Unknown OUTCOME: ", OUTCOME, call. = FALSE)
  }
  if (any(!is.finite(panel$y))) {
    n_bad <- sum(!is.finite(panel$y))
    cat("  WARNING: dropping", n_bad, "rows with non-finite y after OUTCOME transform.\n")
    panel <- panel %>% filter(is.finite(y))
  }

  base_fe <- panel %>% filter(untreated_obs, is.finite(y), !is.na(id), !is.na(t))
  untreated_by_t <- base_fe %>% count(t, name = "n_untreated")
  missing_t <- setdiff(unique(panel$t), untreated_by_t$t)
  if (length(missing_t) > 0L) {
    panel <- panel %>% filter(!(t %in% missing_t))
    base_fe <- panel %>% filter(untreated_obs, is.finite(y), !is.na(id), !is.na(t))
  }

  if (nrow(base_fe) < 50L) {
    summary_rows[[length(summary_rows) + 1L]] <- tibble(
      coverage_threshold = thr,
      n_states = n_states,
      n_rows = nrow(panel),
      n_months = n_distinct(panel$month_date),
      mde80 = NA_real_,
      zero_power = NA_real_,
      note = "skipped_low_untreated_pool"
    )
    next
  }

  fe_fit <- fixest::feols(y ~ 1 | id + t, data = base_fe, notes = FALSE, warn = FALSE)
  panel$yhat <- as.numeric(stats::predict(fe_fit, newdata = panel))

  if (any(!is.finite(panel$yhat))) {
    panel <- panel[is.finite(panel$yhat), , drop = FALSE]
    base_fe <- panel %>% filter(untreated_obs, is.finite(y), !is.na(id), !is.na(t))
    fe_fit <- fixest::feols(y ~ 1 | id + t, data = base_fe, notes = FALSE, warn = FALSE)
    panel$yhat <- as.numeric(stats::predict(fe_fit, newdata = panel))
  }

  base_fe <- panel %>% filter(untreated_obs, is.finite(y), !is.na(id), !is.na(t))
  base_fe$ehat <- as.numeric(residuals(fe_fit))

  exclude_active <- !is.na(EXCLUDE_START) && !is.na(EXCLUDE_END)
  pool_dat_before_month_filter <- if (exclude_active) {
    base_fe %>% filter(!(month_date >= EXCLUDE_START & month_date < EXCLUDE_END))
  } else {
    base_fe
  }

  month_state_counts <- pool_dat_before_month_filter %>%
    group_by(month_date, t) %>%
    summarise(n_states = n_distinct(state_abb), .groups = "drop")
  months_retained <- month_state_counts %>% filter(n_states >= MIN_STATES_PER_MONTH)
  pool_dat <- pool_dat_before_month_filter %>% filter(t %in% months_retained$t)

  resid_pool_by_t <- split(pool_dat$ehat, pool_dat$t)
  global_pool <- pool_dat$ehat
  global_pool <- global_pool[is.finite(global_pool)]
  if (length(global_pool) < 20L) stop("Too few finite residuals in global pool after filtering.", call. = FALSE)

  draw_errors_iid_month <- function(tt) {
    vapply(tt, function(tt_i) {
      pool <- resid_pool_by_t[[as.character(tt_i)]]
      if (is.null(pool) || length(pool) < MIN_STATES_PER_MONTH) pool <- global_pool
      sample(pool, size = 1L, replace = TRUE)
    }, FUN.VALUE = 0.0)
  }

  mk_base <- function(seed) {
    set.seed(seed)
    e_draw <- draw_errors_iid_month(panel$t)
    list(
      id = panel$id,
      t = panel$t,
      g = panel$g,
      post = as.integer(panel$post_treat),
      y0 = panel$yhat + e_draw
    )
  }

  base_draws <- run_serial_or_parallel(sim_seeds, mk_base, cores = N_CORES)

  one_cs0 <- function(base_dat) {
    dat <- data.frame(id = base_dat$id, t = base_dat$t, g = base_dat$g, y = base_dat$y0)
    out <- tryCatch({
      suppressMessages(suppressWarnings({
        mp <- did::att_gt(
          yname = "y",
          tname = "t",
          idname = "id",
          gname = "g",
          xformla = ~ 1,
          data = dat,
          panel = TRUE,
          control_group = "notyettreated",
          allow_unbalanced_panel = did_allow_unbalanced,
          est_method = "reg",
          faster_mode = DID_FASTER_MODE,
          bstrap = DID_BSTRAP,
          biters = DID_BITERS,
          cband = FALSE
        )
        agg <- did::aggte(mp, type = "simple", na.rm = TRUE)
        att <- as.numeric(agg$overall.att)
        se <- as.numeric(agg$overall.se)
        if (!is.finite(att) || !is.finite(se) || se <= 0) stop("non-finite att/se")
        list(ok = TRUE, att0 = att, se0 = se, err = NA_character_)
      }))
    }, error = function(e) {
      list(ok = FALSE, att0 = NA_real_, se0 = NA_real_, err = conditionMessage(e))
    })
    out
  }

  rows_this_threshold <- list()

  cat("  Estimating CS once per sim (effect=0), then shifting for other effects...\n")
  sims0 <- run_serial_or_parallel(base_draws, one_cs0, cores = N_CORES)

  ok <- vapply(sims0, function(x) isTRUE(x$ok), logical(1))
  att0 <- vapply(sims0, function(x) x$att0, numeric(1))
  se0 <- vapply(sims0, function(x) x$se0, numeric(1))
  err <- vapply(sims0, function(x) {
    v <- x$err
    if (!is.character(v) || length(v) != 1L || !nzchar(v)) NA_character_ else v
  }, character(1))
  if (DEBUG_ERRORS && sum(ok) == 0L) {
    cat("  All simulations failed for threshold ", thr, ". Top errors:\n", sep = "")
    print(sort(table(err), decreasing = TRUE)[1:min(5, length(unique(err)))])
  }

  for (eff in EFFECT_PCTS) {
    cat("  Effect", eff, "...\n")
    eff_log <- log1p(eff)
    att <- att0 + eff_log
    se <- se0
    p <- rep(NA_real_, length(att))
    p[ok] <- 2 * pt(-abs(att[ok] / se[ok]), df = n_states - 1)

    row <- tibble(
      coverage_threshold = thr,
      n_states = n_states,
      n_rows = nrow(panel),
      n_months = n_distinct(panel$month_date),
      effect_pct = eff,
      effect_log = eff_log,
      n_sims = N_SIMS,
      n_ok = sum(ok),
      n_fail = sum(!ok),
      power = if (sum(ok) > 0) mean(p[ok] < ALPHA, na.rm = TRUE) else NA_real_,
      mean_att = if (sum(ok) > 0) mean(att[ok], na.rm = TRUE) else NA_real_,
      sd_att = if (sum(ok) > 1) sd(att[ok], na.rm = TRUE) else NA_real_,
      mean_se = if (sum(ok) > 0) mean(se[ok], na.rm = TRUE) else NA_real_,
      se_over_sdatt = if (sum(ok) > 1) mean(se[ok], na.rm = TRUE) / sd(att[ok], na.rm = TRUE) else NA_real_
    )
    rows_this_threshold[[length(rows_this_threshold) + 1L]] <- row
  }

  rows_df <- bind_rows(rows_this_threshold)
  all_rows[[length(all_rows) + 1L]] <- rows_df

  mde80 <- NA_real_
  rows_mde <- rows_df %>% filter(is.finite(effect_pct), is.finite(power)) %>% arrange(effect_pct)
  if (nrow(rows_mde) > 0) {
    hi_idx <- which(rows_mde$power >= 0.8)
    if (length(hi_idx) > 0L) {
      j <- hi_idx[1]
      if (j == 1L) {
        mde80 <- rows_mde$effect_pct[1]
      } else {
        x0 <- rows_mde$effect_pct[j - 1L]
        x1 <- rows_mde$effect_pct[j]
        y0 <- rows_mde$power[j - 1L]
        y1 <- rows_mde$power[j]
        if (is.finite(x0) && is.finite(x1) && is.finite(y0) && is.finite(y1) && (y1 > y0)) {
          mde80 <- x0 + (0.8 - y0) * (x1 - x0) / (y1 - y0)
        } else {
          mde80 <- x1
        }
      }
    }
  }

  zero_pow <- rows_df %>%
    filter(abs(effect_pct) < 1e-12) %>%
    pull(power)
  zero_pow <- if (length(zero_pow) > 0) zero_pow[[1]] else NA_real_

  summary_rows[[length(summary_rows) + 1L]] <- tibble(
    coverage_threshold = thr,
    n_states = n_states,
    n_rows = nrow(panel),
    n_months = n_distinct(panel$month_date),
    mde80 = mde80,
    zero_power = zero_pow,
    note = "ok"
  )

  power_df_partial <- bind_rows(all_rows) %>% arrange(coverage_threshold, effect_pct)
  summary_df_partial <- bind_rows(summary_rows) %>% arrange(coverage_threshold)
  readr::write_csv(power_df_partial, file.path(OUT_DIR, "power_by_threshold_effect.csv"))
  readr::write_csv(summary_df_partial, file.path(OUT_DIR, "threshold_summary.csv"))

  cat("Finished threshold", thr, "with", n_states, "states. MDE80:", mde80, "\n")
}

power_df <- bind_rows(all_rows) %>% arrange(coverage_threshold, effect_pct)
summary_df <- bind_rows(summary_rows) %>% arrange(coverage_threshold)

readr::write_csv(power_df, file.path(OUT_DIR, "power_by_threshold_effect.csv"))
readr::write_csv(summary_df, file.path(OUT_DIR, "threshold_summary.csv"))

cat("\nSweep complete.\n")
cat("Wrote:", file.path(OUT_DIR, "coverage_by_state.csv"), "\n")
cat("Wrote:", file.path(OUT_DIR, "power_by_threshold_effect.csv"), "\n")
cat("Wrote:", file.path(OUT_DIR, "threshold_summary.csv"), "\n")
