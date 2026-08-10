#!/usr/bin/env Rscript
################################################################################
# power_sim_shared.R
#
# Shared DGP and TWFE-sim functions used by both:
#   - power_sim_border_county.R  (unit = county fips)
#   - power_sim_state_baseline.R (unit = state)
#
# Mirrors the design of
#   analysis/main/power_simulation_twfe_statepanel_staggered_parallel_fixed.R
#
# The caller supplies:
#   - `panel`: data frame with columns y (outcome), unit_id, t (integer month),
#              state_abb (for clustering), post_treat (0/1), untreated_obs (TRUE
#              for rows in the residual-fit pool: never-treated + pre-period).
#   - `effect_pcts`: numeric vector
#   - `n_sims`, `seed`, `alpha`: scalars
#
# Returns a tibble with one row per effect_pct (power_by_effect).
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(fixest)
  library(tibble)
})

ym_index <- function(date) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
}

# Prepare the residual pool, fit FE on untreated obs, predict yhat for all rows.
# Returns a list with: panel (mutated), resid_pool_by_t, global_pool.
prep_pool <- function(panel, min_units_per_month = 5L) {
  base_fe <- panel %>% filter(untreated_obs, is.finite(y), !is.na(unit_id), !is.na(t))

  # Drop months with no untreated obs (FE prediction undefined).
  untreated_t <- unique(base_fe$t)
  missing_t <- setdiff(unique(panel$t), untreated_t)
  if (length(missing_t) > 0) {
    panel   <- panel   %>% filter(!t %in% missing_t)
    base_fe <- base_fe %>% filter(!t %in% missing_t)
  }

  fe_fit <- fixest::feols(y ~ 1 | unit_id + t, data = base_fe,
                          warn = FALSE, notes = FALSE)
  panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))

  # Drop non-finite predictions (units with no untreated rows in this panel).
  panel <- panel[is.finite(panel$yhat), , drop = FALSE]
  base_fe <- panel %>% filter(untreated_obs, is.finite(y))

  fe_fit  <- fixest::feols(y ~ 1 | unit_id + t, data = base_fe,
                           warn = FALSE, notes = FALSE)
  panel$yhat  <- as.numeric(predict(fe_fit, newdata = panel))
  base_fe$ehat <- as.numeric(residuals(fe_fit))

  # Residual pool by month — drop months with too few untreated units.
  month_counts <- base_fe %>%
    group_by(t) %>%
    summarise(n_units = n_distinct(unit_id), .groups = "drop")
  ok_months <- month_counts$t[month_counts$n_units >= min_units_per_month]
  pool_dat <- base_fe %>% filter(t %in% ok_months)

  resid_pool_by_t <- split(pool_dat$ehat, pool_dat$t)
  global_pool <- pool_dat$ehat
  global_pool <- global_pool[is.finite(global_pool)]

  list(
    panel = panel,
    resid_pool_by_t = resid_pool_by_t,
    global_pool = global_pool,
    fe_fit = fe_fit
  )
}

# Draw one set of errors, iid resample within month.
draw_errors_iid_month <- function(tt, resid_pool_by_t, global_pool, min_pool = 5L) {
  vapply(tt, function(tt_i) {
    pool <- resid_pool_by_t[[as.character(tt_i)]]
    if (is.null(pool) || length(pool) < min_pool) pool <- global_pool
    sample(pool, size = 1L, replace = TRUE)
  }, FUN.VALUE = 0.0)
}

# One simulation: draw errors, build y_sim, estimate TWFE clustered by state.
one_sim_twfe <- function(seed, effect_log, panel, resid_pool_by_t, global_pool) {
  set.seed(seed)
  e_draw <- draw_errors_iid_month(panel$t, resid_pool_by_t, global_pool)
  y_sim <- panel$yhat + e_draw + ifelse(panel$post_treat == 1L, effect_log, 0)

  dat <- data.frame(
    unit_id    = panel$unit_id,
    t          = panel$t,
    state_abb  = panel$state_abb,
    post_treat = as.integer(panel$post_treat),
    y          = y_sim
  )

  tryCatch({
    est <- fixest::feols(y ~ post_treat | unit_id + t, data = dat,
                         cluster = ~state_abb, warn = FALSE, notes = FALSE)
    ct <- fixest::coeftable(est)
    att <- unname(ct["post_treat", "Estimate"])
    se  <- unname(ct["post_treat", "Std. Error"])
    p   <- unname(ct["post_treat", "Pr(>|t|)"])
    list(ok = is.finite(att) && is.finite(se) && se > 0 && is.finite(p),
         att = att, se = se, p = p)
  }, error = function(e) {
    list(ok = FALSE, att = NA_real_, se = NA_real_, p = NA_real_,
         err = conditionMessage(e))
  })
}

# Loop over effect grid, run N sims at each, return summary tibble.
run_power_grid <- function(panel, effect_pcts, n_sims, seed = 20260521L,
                           alpha = 0.05) {
  pool <- prep_pool(panel)
  panel_p <- pool$panel
  resid_pool_by_t <- pool$resid_pool_by_t
  global_pool <- pool$global_pool

  sim_seeds <- seed + seq_len(n_sims) * 10007L  # deterministic, comparable

  out_rows <- vector("list", length(effect_pcts))
  for (k in seq_along(effect_pcts)) {
    eff_pct <- effect_pcts[k]
    eff_log <- log(1 + eff_pct)
    cat(sprintf("Effect %.3f (log=%.5f): ", eff_pct, eff_log))

    res <- lapply(sim_seeds, function(s) {
      one_sim_twfe(s, eff_log, panel_p, resid_pool_by_t, global_pool)
    })
    ok  <- vapply(res, function(x) isTRUE(x$ok), logical(1))
    p   <- vapply(res, function(x) x$p,   numeric(1))
    att <- vapply(res, function(x) x$att, numeric(1))
    se  <- vapply(res, function(x) x$se,  numeric(1))

    n_ok <- sum(ok)
    rej  <- if (n_ok > 0) mean(p[ok] < alpha, na.rm = TRUE) else NA_real_
    cat(sprintf("ok=%d/%d  rej=%.3f  mean_att=%.4f  sd_att=%.4f  mean_se=%.4f\n",
                n_ok, n_sims, rej,
                ifelse(n_ok > 0, mean(att[ok], na.rm = TRUE), NA_real_),
                ifelse(n_ok > 1, sd(att[ok], na.rm = TRUE), NA_real_),
                ifelse(n_ok > 0, mean(se[ok], na.rm = TRUE), NA_real_)))

    out_rows[[k]] <- tibble(
      effect_pct = eff_pct,
      effect_log = eff_log,
      n_sims = n_sims,
      n_ok = n_ok,
      rejection_rate = rej,
      mean_att = if (n_ok > 0) mean(att[ok], na.rm = TRUE) else NA_real_,
      sd_att   = if (n_ok > 1) sd(att[ok], na.rm = TRUE)   else NA_real_,
      mean_se  = if (n_ok > 0) mean(se[ok], na.rm = TRUE)  else NA_real_,
      se_over_sdatt = if (n_ok > 1)
        mean(se[ok], na.rm = TRUE) / sd(att[ok], na.rm = TRUE) else NA_real_
    )
  }
  bind_rows(out_rows)
}
