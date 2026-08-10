#!/usr/bin/env Rscript
################################################################################
# wild_bootstrap_calibration.R
#
# Test whether wild cluster bootstrap inference (fwildclusterboot::boottest
# for TWFE and fwildclusterboot::boot_aggregate for Sun-Abraham) fixes the
# county-level Type I miscalibration found in the multi-estimator test.
#
# Baseline (analytic inference, 50 null sims, all-county panel, drop NH):
#   TWFE:        rejection 8% (anti-conservative, SE/SD = 0.95)
#   Sun-Abraham: rejection 30% (badly anti-conservative, SE/SD = 0.51)
#
# Question: does swapping the analytic p-value for a wild bootstrap p-value
# (B = 999 multipliers, Rademacher weights, state cluster) bring rejection
# closer to nominal 5%?
#
# Note on CS-DiD: skipped here because CS uses an influence-function-based
# SE, not a regression-based one. fwildclusterboot doesn't apply directly.
# The did::aggte built-in multiplier bootstrap (already tested in the
# Hollenbeck-style spec) produced wide CIs without fixing calibration.
#
# Outputs:
#   output/border_diagnostic/wild_bootstrap/calibration.csv
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tibble); library(glue)
  library(fixest); library(fwildclusterboot)
})

set.seed(20260521L)

N_SIMS    <- as.integer(Sys.getenv("N_SIMS", "30"))
N_WORKERS <- as.integer(Sys.getenv("N_WORKERS", "6"))
B_BOOT    <- as.integer(Sys.getenv("B_BOOT", "999"))
ALPHA     <- 0.05

repo_root <- normalizePath(".", winslash = "/")
out_dir   <- file.path(repo_root, "output", "border_diagnostic",
                       "wild_bootstrap")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

ym_index <- function(date) {
  as.integer(as.integer(format(date, "%Y")) * 12L
             + as.integer(format(date, "%m")))
}

state_fips_xwalk <- tibble::tribble(
  ~state_fips, ~state_abb,
   1,"AL", 2,"AK", 4,"AZ", 5,"AR", 6,"CA", 8,"CO", 9,"CT",
  10,"DE",11,"DC",12,"FL",13,"GA",15,"HI",16,"ID",
  17,"IL",18,"IN",19,"IA",20,"KS",21,"KY",22,"LA",
  23,"ME",24,"MD",25,"MA",26,"MI",27,"MN",28,"MS",
  29,"MO",30,"MT",31,"NE",32,"NV",33,"NH",34,"NJ",
  35,"NM",36,"NY",37,"NC",38,"ND",39,"OH",40,"OK",
  41,"OR",42,"PA",44,"RI",45,"SC",46,"SD",47,"TN",
  48,"TX",49,"UT",50,"VT",51,"VA",53,"WA",54,"WV",
  55,"WI",56,"WY"
)

COVID_START <- as.Date("2020-03-01")
COVID_END   <- as.Date("2022-03-31")
MIN_COUNTIES <- 5L

# ----------------------------- build panel ------------------------------------

county_raw <- read_csv(file.path(repo_root, "data", "raw",
                                  "monthly_county_data_download.csv"),
                       show_col_types = FALSE) %>%
  mutate(fips = as.integer(fips),
         state_fips = as.integer(floor(fips / 1000)),
         month_date = as.Date(date),
         filings_count = as.numeric(filings_count)) %>%
  left_join(state_fips_xwalk, by = "state_fips") %>%
  filter(!is.na(state_abb), !is.na(month_date))

state_treat_one <- read_csv(file.path(repo_root, "data", "raw",
                                       "state_month_panel_with_treatment.csv"),
                            show_col_types = FALSE) %>%
  group_by(state_abb) %>%
  summarise(treat_start = suppressWarnings(min(as.Date(treat_start),
                                                na.rm = TRUE)),
            .groups = "drop") %>%
  mutate(treat_start = if_else(is.finite(treat_start), treat_start,
                               as.Date(NA)))

counties_per_state <- county_raw %>%
  distinct(state_abb, fips) %>%
  count(state_abb, name = "n_counties")
drop_states <- counties_per_state %>%
  filter(n_counties < MIN_COUNTIES) %>%
  pull(state_abb)

panel <- county_raw %>%
  left_join(state_treat_one, by = "state_abb") %>%
  filter(state_abb != "ME", !(state_abb %in% drop_states),
         state_abb != "NH") %>%   # drop NH
  filter(!(month_date >= COVID_START & month_date <= COVID_END)) %>%
  mutate(y = log1p(pmax(filings_count, 0)),
         t = ym_index(month_date),
         g = if_else(!is.na(treat_start), as.integer(ym_index(treat_start)),
                     NA_integer_),
         first_treat = if_else(is.na(g), 10000L, as.integer(g)),
         post_treat = as.integer(!is.na(g) & t >= g),
         id = as.integer(fips),
         state_abb = as.character(state_abb),
         untreated_obs = is.na(g) | t < g) %>%
  filter(is.finite(y), !is.na(id), !is.na(t))

# Pre-drop singleton FE counties (fwildclusterboot can't handle FEs that
# feols removes internally). Require ≥ 2 observations per county.
counties_keep <- panel %>%
  count(id, name = "n_obs") %>%
  filter(n_obs >= 2L) %>%
  pull(id)
panel <- panel %>% filter(id %in% counties_keep)

n_states <- n_distinct(panel$state_abb)
cat("Panel: ", nrow(panel), "obs,", n_distinct(panel$id), "counties,",
    n_states, "states (NH dropped)\n\n")

# ----------------------------- residual pool ----------------------------------

base_fe <- panel %>% filter(untreated_obs, is.finite(y))
fe_fit <- fixest::feols(y ~ 1 | id + t, data = base_fe,
                        warn = FALSE, notes = FALSE)
panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))
if (any(!is.finite(panel$yhat))) {
  panel <- panel[is.finite(panel$yhat), , drop = FALSE]
  base_fe <- panel %>% filter(untreated_obs)
  fe_fit <- fixest::feols(y ~ 1 | id + t, data = base_fe,
                          warn = FALSE, notes = FALSE)
  panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))
}
base_fe$ehat <- as.numeric(residuals(fe_fit))
resid_pool_by_t <- split(base_fe$ehat, base_fe$t)
global_pool <- base_fe$ehat[is.finite(base_fe$ehat)]
cat("Residual pool:", nrow(base_fe), "obs across",
    length(resid_pool_by_t), "months\n\n")

# ----------------------------- simulation -------------------------------------

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

one_sim <- function(seed) {
  set.seed(seed)
  e_draw <- draw_errors(panel$t, resid_pool_by_t, global_pool)
  y_sim <- panel$yhat + e_draw   # null DGP: no treatment effect

  dat <- as.data.frame(data.frame(
    id = panel$id, t = panel$t, state_abb = panel$state_abb,
    post_treat = as.integer(panel$post_treat),
    first_treat = panel$first_treat,
    y = y_sim
  ))

  out <- list(seed = seed)

  # --- TWFE: analytic + wild bootstrap ---
  out$twfe_ok <- FALSE
  tryCatch({
    fit_twfe <- fixest::feols(y ~ post_treat | id + t, data = dat,
                              cluster = ~state_abb,
                              warn = FALSE, notes = FALSE)
    ct <- fixest::coeftable(fit_twfe)
    out$twfe_att <- as.numeric(ct["post_treat", "Estimate"])
    out$twfe_se_analytic  <- as.numeric(ct["post_treat", "Std. Error"])
    out$twfe_p_analytic   <- as.numeric(ct["post_treat", "Pr(>|t|)"])

    # Wild cluster bootstrap.
    wb <- suppressMessages(suppressWarnings(
      fwildclusterboot::boottest(fit_twfe, param = "post_treat",
                                  clustid = "state_abb",
                                  B = B_BOOT,
                                  conf_int = FALSE)
    ))
    out$twfe_p_wcb <- wb$p_val
    out$twfe_ok <- is.finite(out$twfe_att) &&
      is.finite(out$twfe_p_analytic) && is.finite(out$twfe_p_wcb)
  }, error = function(e) {
    out$twfe_err <<- conditionMessage(e)
  })

  # --- Sun-Abraham: analytic + boot_aggregate ---
  out$sa_ok <- FALSE
  tryCatch({
    fit_sa <- fixest::feols(y ~ sunab(cohort = first_treat, period = t,
                                       ref.p = -1) | id + t,
                            data = dat, cluster = ~state_abb,
                            warn = FALSE, notes = FALSE)
    # Aggregated ATT via fixest's standard agg.
    agg_sa <- summary(fit_sa, agg = "att")
    ct_sa <- fixest::coeftable(agg_sa)
    out$sa_att <- as.numeric(ct_sa[1, "Estimate"])
    out$sa_se_analytic  <- as.numeric(ct_sa[1, "Std. Error"])
    out$sa_p_analytic   <- as.numeric(ct_sa[1, "Pr(>|t|)"])

    # boot_aggregate — wild bootstrap version of the SunAb aggregation.
    ba <- suppressMessages(suppressWarnings(
      fwildclusterboot::boot_aggregate(fit_sa, agg = "att",
                                        clustid = "state_abb",
                                        B = B_BOOT)
    ))
    # boot_aggregate returns a matrix with column "Pr(>|t|)" — handle both
    # matrix and data.frame returns.
    p_col <- "Pr(>|t|)"
    if (!is.null(ba) && (is.matrix(ba) || is.data.frame(ba)) &&
        p_col %in% colnames(ba)) {
      out$sa_p_wcb <- as.numeric(ba[1, p_col])
    } else {
      out$sa_p_wcb <- NA_real_
    }
    out$sa_ok <- is.finite(out$sa_att) &&
      is.finite(out$sa_p_analytic) && is.finite(out$sa_p_wcb)
  }, error = function(e) {
    out$sa_err <<- conditionMessage(e)
  })

  out
}

# ----------------------------- run --------------------------------------------

seeds <- sample.int(1e8, N_SIMS)
use_parallel <- N_WORKERS > 1

cat(glue("Running {N_SIMS} null sims with B={B_BOOT}, ",
        "{N_WORKERS} workers..."), "\n")
t0 <- Sys.time()

if (use_parallel) {
  cl <- parallel::makeCluster(N_WORKERS, type = "PSOCK")
  on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)
  parallel::clusterEvalQ(cl, {
    suppressPackageStartupMessages({
      library(fixest); library(fwildclusterboot)
    })
    NULL
  })
  parallel::clusterExport(
    cl,
    varlist = c("panel", "resid_pool_by_t", "global_pool",
                "B_BOOT", "draw_errors", "one_sim"),
    envir = environment()
  )
  results <- parallel::parLapply(cl, seeds, one_sim)
} else {
  results <- lapply(seeds, one_sim)
}

elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(glue("Done in {round(elapsed)}s ({round(elapsed/60, 1)} min)"), "\n\n")

# ----------------------------- summarize --------------------------------------

df <- bind_rows(lapply(results, function(r) {
  tibble(
    seed = r$seed,
    twfe_ok = isTRUE(r$twfe_ok),
    twfe_p_analytic = r$twfe_p_analytic %||% NA_real_,
    twfe_p_wcb      = r$twfe_p_wcb      %||% NA_real_,
    sa_ok = isTRUE(r$sa_ok),
    sa_p_analytic = r$sa_p_analytic %||% NA_real_,
    sa_p_wcb      = r$sa_p_wcb      %||% NA_real_
  )
}))

`%||%` <- function(x, y) if (is.null(x)) y else x

write_csv(df, file.path(out_dir, "sim_results.csv"))

summarize_calib <- function(p, ok, name) {
  v <- ok & is.finite(p)
  if (sum(v) == 0) return(tibble(method = name, n_valid = 0, rejection = NA))
  tibble(method = name, n_valid = sum(v),
         rejection = mean(p[v] < ALPHA, na.rm = TRUE))
}

summary_df <- bind_rows(
  summarize_calib(df$twfe_p_analytic, df$twfe_ok, "TWFE analytic"),
  summarize_calib(df$twfe_p_wcb,      df$twfe_ok, "TWFE wild cluster boot"),
  summarize_calib(df$sa_p_analytic,   df$sa_ok,   "SunAb analytic"),
  summarize_calib(df$sa_p_wcb,        df$sa_ok,   "SunAb boot_aggregate")
)
write_csv(summary_df, file.path(out_dir, "calibration.csv"))

cat("=== Wild bootstrap calibration test (alpha = 0.05, n_sims =",
    N_SIMS, ") ===\n")
print(summary_df %>% mutate(rejection = signif(rejection, 3)))

cat("\nReference values from prior 50-sim multi-estimator test (analytic):\n")
cat("  TWFE county-level:  rejection 8% (anti-conservative)\n")
cat("  SunAb county-level: rejection 30% (anti-conservative)\n")
cat("  Target: 5%\n")
