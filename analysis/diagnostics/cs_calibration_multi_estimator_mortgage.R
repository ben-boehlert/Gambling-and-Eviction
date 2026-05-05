#!/usr/bin/env Rscript
################################################################################
# cs_calibration_multi_estimator_mortgage.R
#
# PURPOSE: Multi-estimator calibration test on the MORTGAGE DELINQUENCY panel.
#          Mirror of cs_calibration_multi_estimator.R (which tests the eviction
#          panel) — same DGP pattern (FE-fit + resampled residuals), applied to
#          the 51-state mortgage panel with % 90+ days delinquent as outcome.
#
# Key question: Are heterogeneity-robust estimators (CS, SunAb, didimputation,
# did2s) as badly miscalibrated here as on the 24-state eviction panel? The
# mortgage panel has 51 states and 6 multi-state cohorts alongside singletons,
# so CS may be substantially better behaved.
#
# Estimators tested: TWFE, Sun-Abraham, CS analytic, CS bootstrap,
#                    didimputation, did2s
#
# USAGE:
#   N_SIMS=100 N_WORKERS=4 \
#     Rscript analysis/diagnostics/cs_calibration_multi_estimator_mortgage.R
################################################################################

Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1",
  MKL_NUM_THREADS = "1", VECLIB_MAXIMUM_THREADS = "1",
  NUMEXPR_NUM_THREADS = "1"
)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(glue)
  library(fixest)
  library(did)
  library(tibble)
})

HAS_DIDIMP <- requireNamespace("didimputation", quietly = TRUE)
HAS_DID2S  <- requireNamespace("did2s", quietly = TRUE)
if (HAS_DIDIMP) library(didimputation)
if (HAS_DID2S)  library(did2s)

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || !nzchar(as.character(x))) y else x

getenv1 <- function(key, default = "") {
  v <- Sys.getenv(key, unset = default)
  if (!nzchar(v)) default else v
}
parse_int <- function(x, default = NA_integer_) {
  if (!nzchar(x)) return(default)
  suppressWarnings(as.integer(x))
}
parse_bool <- function(x, default = FALSE) {
  if (!nzchar(x)) return(default)
  toupper(trimws(x)) %in% c("1", "TRUE", "T", "YES", "Y")
}

state_name_to_abb <- function(state_name) {
  state_name <- trimws(as.character(state_name))
  m <- setNames(state.abb, state.name)
  m <- c(m, "District of Columbia" = "DC")
  unname(m[state_name])
}

ym_index <- function(date) {
  as.integer(as.integer(format(date, "%Y")) * 12L + as.integer(format(date, "%m")))
}

# ----------------------------- config -----------------------------------------

N_SIMS     <- parse_int(getenv1("N_SIMS", "100"), 100L)
N_WORKERS  <- parse_int(getenv1("N_WORKERS", "4"), 4L)
SEED       <- parse_int(getenv1("SEED", "20260417"), 20260417L)
ALPHA      <- 0.05
DID_BITERS <- parse_int(getenv1("DID_BITERS", "199"), 199L)

MORTGAGE_FILE  <- getenv1("MORTGAGE_FILE",
  "data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv")
TREAT_FILE     <- getenv1("TREAT_FILE",
  "data/raw/sports_gambling_legalization_dates.csv")
TREAT_DATE_COL <- getenv1("TREAT_DATE_COL", "online_start_date")
OUT_DIR        <- getenv1("OUT_DIR", "output/cs_calibration_multi_mortgage")

MIN_DATE       <- as.Date(getenv1("MIN_DATE", "2016-01-01"))
MAX_DATE       <- as.Date(getenv1("MAX_DATE", "2024-12-31"))
DROP_START     <- as.Date(getenv1("DROP_START", "2020-03-01"))
DROP_END       <- as.Date(getenv1("DROP_END", "2021-07-31"))

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

cat("=== MORTGAGE MULTI-ESTIMATOR CALIBRATION TEST ===\n")
cat(glue("N_SIMS={N_SIMS}, N_WORKERS={N_WORKERS}, SEED={SEED}"), "\n")
cat(glue("Treatment: {TREAT_DATE_COL}  COVID drop: [{DROP_START}, {DROP_END}]"), "\n")
cat(glue("Estimators: TWFE, SunAb, CS-analytic, CS-bootstrap"), "\n")
if (HAS_DIDIMP) cat("  + didimputation\n")
if (HAS_DID2S)  cat("  + did2s\n")
cat("\n")

# ----------------------------- build panel (match pretrends_mortgage) ---------

cat("Loading mortgage delinquency data...\n")
mort_wide <- read_csv(MORTGAGE_FILE, show_col_types = FALSE) %>%
  filter(RegionType == "State")
month_cols <- grep("^\\d{4}-\\d{2}$", colnames(mort_wide), value = TRUE)

mort_long <- mort_wide %>%
  select(Name, all_of(month_cols)) %>%
  pivot_longer(cols = all_of(month_cols),
               names_to = "month_str", values_to = "delinq_pct") %>%
  mutate(
    state_abb  = state_name_to_abb(Name),
    month_date = as.Date(paste0(month_str, "-01")),
    delinq_pct = as.numeric(delinq_pct)
  ) %>%
  filter(!is.na(state_abb)) %>%
  select(state_abb, month_date, delinq_pct) %>%
  filter(month_date >= MIN_DATE, month_date <= MAX_DATE) %>%
  filter(!(month_date >= DROP_START & month_date <= DROP_END))

cat("Loading treatment schedule...\n")
treat_raw <- read_csv(TREAT_FILE, show_col_types = FALSE)
stopifnot(TREAT_DATE_COL %in% colnames(treat_raw))

treat_sched <- treat_raw %>%
  transmute(
    state_abb   = state_name_to_abb(state),
    treat_start = as.Date(.data[[TREAT_DATE_COL]])
  ) %>%
  filter(!is.na(state_abb)) %>%
  group_by(state_abb) %>%
  summarise(treat_start = if (all(is.na(treat_start))) as.Date(NA) else
                             min(treat_start, na.rm = TRUE),
            .groups = "drop")

# Coverage auto + common-month balancing (same as pretrends_mortgage)
coverage <- mort_long %>% count(state_abb, name = "n_months")
max_cov <- max(coverage$n_months, na.rm = TRUE)
keep_states <- coverage %>% filter(n_months >= max_cov) %>% pull(state_abb)
panel0 <- mort_long %>% filter(state_abb %in% keep_states)

n_states_pre <- n_distinct(panel0$state_abb)
common_months <- panel0 %>% count(month_date, name = "n_states") %>%
  filter(n_states == n_states_pre) %>% pull(month_date)
panel0 <- panel0 %>% filter(month_date %in% common_months)

panel <- panel0 %>%
  left_join(treat_sched, by = "state_abb") %>%
  mutate(
    y = delinq_pct,
    t = ym_index(month_date),
    g = ifelse(is.na(treat_start), 0L, ym_index(treat_start)),
    g = as.integer(g),
    id = as.integer(as.factor(state_abb)),
    untreated_obs = (g == 0L) | (t < g),
    post_treat    = (g > 0L) & (t >= g),
    first_treat   = ifelse(g == 0L, NA_integer_, g),
    rel_time      = ifelse(g == 0L, NA_integer_, t - g)
  )

n_states <- n_distinct(panel$state_abb)
n_switch <- n_distinct(panel$state_abb[panel$g > 0L])
n_never  <- n_states - n_switch
n_months <- n_distinct(panel$t)
n_cohorts <- n_distinct(panel$g[panel$g > 0L])

cat(glue("Panel: {n_states} states ({n_switch} treated, {n_never} never-treated), {n_cohorts} cohorts, {n_months} months, {nrow(panel)} obs"), "\n")

bal <- panel %>% count(state_abb) %>% pull(n)
stopifnot(length(unique(bal)) == 1)
cat(glue("Balanced: {unique(bal)} obs per state"), "\n")

# ----------------------------- sanity check -----------------------------------

cat("\nSanity: real-data estimates...\n")
dat_real <- as.data.frame(panel)

twfe_real <- feols(y ~ post_treat | id + t, data = dat_real, cluster = ~id,
                   warn = FALSE, notes = FALSE)
cat(glue("  TWFE : ATT={round(coef(twfe_real)[1], 4)}, SE={round(se(twfe_real)[1], 4)}"), "\n")

sunab_real <- feols(y ~ sunab(first_treat, t) | id + t, data = dat_real,
                    cluster = ~id, warn = FALSE, notes = FALSE)
sunab_agg <- summary(sunab_real, agg = "att")
cat(glue("  SunAb: ATT={round(coef(sunab_agg)[1], 4)}, SE={round(se(sunab_agg)[1], 4)}"), "\n")

tryCatch({
  cs_real <- did::att_gt(yname = "y", tname = "t", idname = "id", gname = "g",
                         data = dat_real, est_method = "reg",
                         control_group = "notyettreated",
                         bstrap = FALSE, cband = FALSE,
                         allow_unbalanced_panel = TRUE, print_details = FALSE)
  cs_agg_real <- did::aggte(cs_real, type = "simple")
  cat(glue("  CS   : ATT={round(cs_agg_real$overall.att, 4)}, SE={round(cs_agg_real$overall.se, 4)}"), "\n")
}, error = function(e) cat("  CS   : ERROR -", conditionMessage(e), "\n"))

cat("\n")

# ----------------------------- FE + residual pool -----------------------------

base_fe <- panel %>% filter(untreated_obs, is.finite(y))
set.seed(SEED)
fe_fit <- feols(y ~ 1 | id + t, data = base_fe, warn = FALSE, notes = FALSE)
panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))

if (any(!is.finite(panel$yhat))) {
  n_bad <- sum(!is.finite(panel$yhat))
  cat(glue("Dropping {n_bad} non-finite yhat rows"), "\n")
  panel <- panel[is.finite(panel$yhat), , drop = FALSE]
  base_fe <- panel %>% filter(untreated_obs, is.finite(y))
  fe_fit <- feols(y ~ 1 | id + t, data = base_fe, warn = FALSE, notes = FALSE)
  panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))
}

base_fe$ehat <- as.numeric(residuals(fe_fit))
resid_pool_by_t <- split(base_fe$ehat, base_fe$t)
global_pool <- base_fe$ehat[is.finite(base_fe$ehat)]

cat(glue("Residual pool: {nrow(base_fe)} obs, {length(resid_pool_by_t)} months, SD={round(sd(global_pool),4)}"), "\n\n")

# ----------------------------- simulation function ----------------------------

draw_errors <- function(t_vec, pool_by_t, fallback) {
  e <- numeric(length(t_vec))
  for (tv in unique(t_vec)) {
    idx <- which(t_vec == tv)
    pool <- pool_by_t[[as.character(tv)]]
    if (is.null(pool) || length(pool) < 3) pool <- fallback
    e[idx] <- sample(pool, length(idx), replace = TRUE)
  }
  e
}

compute_t_p <- function(att, se, df) {
  if (is.finite(att) && is.finite(se) && se > 0) {
    2 * stats::pt(-abs(att / se), df = df)
  } else {
    NA_real_
  }
}

one_sim <- function(seed) {
  set.seed(seed)
  e_draw <- draw_errors(panel$t, resid_pool_by_t, global_pool)
  y_sim <- panel$yhat + e_draw

  dat <- as.data.frame(data.frame(
    id = panel$id, t = panel$t, g = panel$g, y = y_sim,
    post_treat = as.integer(panel$post_treat),
    first_treat = panel$first_treat,
    rel_time = panel$rel_time,
    state_abb = panel$state_abb
  ))

  out <- list(seed = seed)

  # --- TWFE ---
  tryCatch({
    suppressWarnings({
      fit <- feols(y ~ post_treat | id + t, data = dat, cluster = ~id,
                   warn = FALSE, notes = FALSE)
      out$twfe_att <- as.numeric(coef(fit)[1])
      out$twfe_se  <- as.numeric(se(fit)[1])
      out$twfe_p   <- as.numeric(pvalue(fit)[1])
      out$twfe_ok  <- TRUE
    })
  }, error = function(e) {
    out$twfe_ok <<- FALSE; out$twfe_att <<- NA; out$twfe_se <<- NA; out$twfe_p <<- NA
  })

  # --- Sun-Abraham ---
  tryCatch({
    suppressMessages(suppressWarnings({
      fit_sa <- feols(y ~ sunab(first_treat, t) | id + t, data = dat,
                      cluster = ~id, warn = FALSE, notes = FALSE)
      agg_sa <- summary(fit_sa, agg = "att")
      out$sunab_att <- as.numeric(coef(agg_sa)[1])
      out$sunab_se  <- as.numeric(se(agg_sa)[1])
      out$sunab_p   <- as.numeric(pvalue(agg_sa)[1])
      out$sunab_ok  <- TRUE
    }))
  }, error = function(e) {
    out$sunab_ok <<- FALSE; out$sunab_att <<- NA; out$sunab_se <<- NA; out$sunab_p <<- NA
    out$sunab_err <<- conditionMessage(e)
  })

  # --- CS Analytic ---
  tryCatch({
    suppressMessages(suppressWarnings({
      cs_fit <- did::att_gt(yname = "y", tname = "t", idname = "id", gname = "g",
                            data = dat, est_method = "reg",
                            control_group = "notyettreated",
                            bstrap = FALSE, cband = FALSE,
                            allow_unbalanced_panel = TRUE, print_details = FALSE)
      agg <- did::aggte(cs_fit, type = "simple")
      out$cs_att <- agg$overall.att
      out$cs_se  <- agg$overall.se
      out$cs_p <- compute_t_p(out$cs_att, out$cs_se, df = n_states - 1)
      out$cs_ok <- TRUE
    }))
  }, error = function(e) {
    out$cs_ok <<- FALSE; out$cs_att <<- NA; out$cs_se <<- NA; out$cs_p <<- NA
    out$cs_err <<- conditionMessage(e)
  })

  # --- CS Bootstrap ---
  tryCatch({
    suppressMessages(suppressWarnings({
      csb_fit <- did::att_gt(yname = "y", tname = "t", idname = "id", gname = "g",
                             data = dat, est_method = "reg",
                             control_group = "notyettreated",
                             bstrap = TRUE, biters = DID_BITERS, cband = FALSE,
                             allow_unbalanced_panel = TRUE, print_details = FALSE)
      aggb <- did::aggte(csb_fit, type = "simple")
      out$csb_att <- aggb$overall.att
      out$csb_se  <- aggb$overall.se
      out$csb_p   <- compute_t_p(out$csb_att, out$csb_se, df = n_states - 1)
      out$csb_ok  <- TRUE
    }))
  }, error = function(e) {
    out$csb_ok <<- FALSE; out$csb_att <<- NA; out$csb_se <<- NA; out$csb_p <<- NA
    out$csb_err <<- conditionMessage(e)
  })

  # --- didimputation ---
  if (HAS_DIDIMP) {
    tryCatch({
      suppressMessages(suppressWarnings({
        didimp_fit <- did_imputation(data = dat, yname = "y", gname = "first_treat",
                                      tname = "t", idname = "id", cluster_var = "id")
        out$didimp_att <- didimp_fit$estimate[1]
        out$didimp_se  <- didimp_fit$std.error[1]
        out$didimp_p   <- compute_t_p(out$didimp_att, out$didimp_se, df = n_states - 1)
        out$didimp_ok  <- is.finite(out$didimp_att) && is.finite(out$didimp_se)
      }))
    }, error = function(e) {
      out$didimp_ok <<- FALSE; out$didimp_att <<- NA; out$didimp_se <<- NA; out$didimp_p <<- NA
      out$didimp_err <<- conditionMessage(e)
    })
  }

  # --- did2s ---
  if (HAS_DID2S) {
    tryCatch({
      suppressMessages(suppressWarnings({
        d2s_fit <- did2s(data = dat, yname = "y", first_stage = ~ 0 | id + t,
                         second_stage = ~ post_treat, treatment = "post_treat",
                         cluster_var = "id")
        out$did2s_att <- as.numeric(coef(d2s_fit)[1])
        d2s_vcov <- tryCatch(stats::vcov(d2s_fit), error = function(e) NULL)
        out$did2s_se  <- if (!is.null(d2s_vcov)) sqrt(diag(d2s_vcov))[1] else NA_real_
        out$did2s_p   <- compute_t_p(out$did2s_att, out$did2s_se, df = n_states - 1)
        out$did2s_ok  <- is.finite(out$did2s_att) && is.finite(out$did2s_se)
      }))
    }, error = function(e) {
      out$did2s_ok <<- FALSE; out$did2s_att <<- NA; out$did2s_se <<- NA; out$did2s_p <<- NA
      out$did2s_err <<- conditionMessage(e)
    })
  }

  out
}

# ----------------------------- run simulations --------------------------------

cat(glue("Running {N_SIMS} simulations under the null..."), "\n")
set.seed(SEED)
seeds <- sample.int(1e8, N_SIMS)

use_parallel <- (N_WORKERS > 1L)
if (use_parallel) {
  cat(glue("Starting PSOCK cluster with {N_WORKERS} workers"), "\n")
  cl <- parallel::makeCluster(N_WORKERS, type = "PSOCK")
  on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)

  parallel::clusterEvalQ(cl, {
    suppressPackageStartupMessages({ library(fixest); library(did) })
    NULL
  })
  if (HAS_DIDIMP) parallel::clusterEvalQ(cl, { library(didimputation); NULL })
  if (HAS_DID2S)  parallel::clusterEvalQ(cl, { library(did2s); NULL })

  parallel::clusterExport(
    cl,
    varlist = c("panel", "resid_pool_by_t", "global_pool", "n_states",
                "DID_BITERS", "draw_errors", "compute_t_p", "one_sim",
                "HAS_DIDIMP", "HAS_DID2S"),
    envir = environment()
  )
}

t0 <- Sys.time()
batch_size <- 10L
n_batches <- ceiling(N_SIMS / batch_size)
results <- vector("list", N_SIMS)

for (b in seq_len(n_batches)) {
  lo <- (b - 1) * batch_size + 1L
  hi <- min(b * batch_size, N_SIMS)
  batch_seeds <- seeds[lo:hi]

  if (use_parallel) {
    batch_results <- parallel::parLapply(cl, batch_seeds, one_sim)
  } else {
    batch_results <- lapply(batch_seeds, one_sim)
  }
  results[lo:hi] <- batch_results

  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  done <- hi
  rate <- elapsed / done
  eta <- rate * (N_SIMS - done)
  cat(glue("  [{done}/{N_SIMS}] elapsed={round(elapsed)}s, ~{round(eta)}s remaining"), "\n")
}

elapsed_total <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(glue("\nDone in {round(elapsed_total)}s ({round(elapsed_total/60, 1)} min)"), "\n\n")

# ----------------------------- summarize --------------------------------------

df <- bind_rows(lapply(results, function(r) {
  row <- tibble(seed = r$seed)
  for (m in c("twfe", "sunab", "cs", "csb", "didimp", "did2s")) {
    row[[paste0(m, "_ok")]]  <- isTRUE(r[[paste0(m, "_ok")]])
    row[[paste0(m, "_att")]] <- r[[paste0(m, "_att")]] %||% NA_real_
    row[[paste0(m, "_se")]]  <- r[[paste0(m, "_se")]] %||% NA_real_
    row[[paste0(m, "_p")]]   <- r[[paste0(m, "_p")]] %||% NA_real_
  }
  row
}))

write_csv(df, file.path(OUT_DIR, "sim_results.csv"))

summarize_method <- function(ok, att, se, p, name) {
  valid <- ok & is.finite(att) & is.finite(se) & se > 0 & is.finite(p)
  n_valid <- sum(valid); n_fail <- sum(!ok)

  if (n_valid == 0) {
    cat(glue("\n=== {name} ==="), "\n")
    cat(glue("  ALL FAILED ({n_fail}/{length(ok)} errors)"), "\n")
    return(tibble(method = name, n_valid = 0, n_fail = n_fail,
                  rejection = NA_real_, mean_att = NA_real_, sd_att = NA_real_,
                  mean_se = NA_real_, se_over_sd = NA_real_))
  }

  att_v <- att[valid]; se_v <- se[valid]; p_v <- p[valid]
  rej <- mean(p_v < ALPHA)
  sd_a <- sd(att_v); mean_s <- mean(se_v)

  cat(glue("\n=== {name} ==="), "\n")
  cat(glue("  Valid: {n_valid}/{length(ok)} (fail: {n_fail})"), "\n")
  cat(glue("  Rejection at alpha={ALPHA}: {round(rej*100,1)}% (target: 5%)"), "\n")
  cat(glue("  Mean ATT: {round(mean(att_v),5)}  SD(ATT): {round(sd_a,4)}"), "\n")
  cat(glue("  Mean SE:  {round(mean_s,4)}  SE/SD: {round(mean_s/sd_a,2)}"), "\n")

  tibble(method = name, n_valid = n_valid, n_fail = n_fail,
         rejection = rej, mean_att = mean(att_v), sd_att = sd_a,
         mean_se = mean_s, se_over_sd = mean_s / sd_a)
}

cat("\n============================================================")
cat("\n  MORTGAGE PANEL — NULL REJECTION DIAGNOSTICS")
cat("\n============================================================\n")

methods <- list(
  list("twfe",   "TWFE (fixest)"),
  list("sunab",  "Sun-Abraham (fixest)"),
  list("cs",     "CS Analytic (did)"),
  list("csb",    "CS Bootstrap (did)"),
  list("didimp", "didimputation (BJS)"),
  list("did2s",  "did2s (Gardner)")
)

summary_rows <- bind_rows(lapply(methods, function(m) {
  col <- m[[1]]; name <- m[[2]]
  ok_col <- paste0(col, "_ok"); att_col <- paste0(col, "_att")
  se_col <- paste0(col, "_se"); p_col <- paste0(col, "_p")
  if (!(ok_col %in% names(df))) return(NULL)
  if (all(is.na(df[[ok_col]]))) return(NULL)
  summarize_method(df[[ok_col]], df[[att_col]], df[[se_col]], df[[p_col]], name)
}))

write_csv(summary_rows, file.path(OUT_DIR, "calibration_summary.csv"))

cat("\n\n=== NOISE RATIO vs TWFE ===\n")
twfe_sd <- summary_rows$sd_att[summary_rows$method == "TWFE (fixest)"]
if (length(twfe_sd) == 1 && is.finite(twfe_sd) && twfe_sd > 0) {
  for (i in seq_len(nrow(summary_rows))) {
    r <- summary_rows[i, ]
    if (is.finite(r$sd_att) && r$sd_att > 0) {
      ratio <- r$sd_att / twfe_sd
      cat(glue("  {r$method}: SD(ATT)={round(r$sd_att,4)}, noise ratio vs TWFE = {round(ratio,2)}x"), "\n")
    }
  }
}

cat(glue("\nResults saved to: {OUT_DIR}/"), "\n")
