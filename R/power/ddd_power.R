################################################################################
# R/power/ddd_power.R
#
# Blinded power simulation for the triple-difference (DDD) design:
#
#   Y_cst = alpha_c + lambda_st + gamma_t * H_c + beta * (D_st x H_c) + eps
#
# where H_c is a fixed pre-treatment high-poverty indicator, lambda_st is a
# state x month fixed effect (absorbing every within-state-common shock: COVID
# shutdowns, moratoria, statewide policy) and D_st is the state-level pseudo
# treatment. beta identifies tau_high - tau_low, NOT the total ATT.
#
# Follows POWER_SIMULATION_BLINDNESS_PROTOCOL.md: outcomes come only from
# untreated county-months via load_blinded_panel(); treatment is a pseudo
# schedule from make_pseudo_schedule(); effects are injected with the framework's
# count_nb mechanism.
#
# Working directory is assumed to be the repository root.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringr)
  library(lubridate)
  library(fixest)
})

if (!exists("power_paths", mode = "function"))          source("R/power/config.R")
if (!exists("assert_blinded", mode = "function"))       source("R/power/blindness_checks.R")
if (!exists("load_blinded_panel", mode = "function"))   source("R/power/load_blinded_panel.R")
if (!exists("make_pseudo_schedule", mode = "function")) source("R/power/make_pseudo_schedules.R")
if (!exists("impose_effect", mode = "function"))        source("R/power/impose_effects.R")
if (!exists("ddd_assign_H", mode = "function"))         source("R/power/ddd_h_rules.R")
if (!exists("ddd_fit_wild", mode = "function"))         source("R/power/ddd_wild.R")

DDD_BASE_SEED <- 20260723L   # shared with the rest of the power framework

#' Month index helper (calendar months since year 0)
#' @keywords internal
.ddd_mi <- function(d) year(d) * 12L + month(d)

#' Build the DDD design skeleton: blinded county panel + poverty classifier
#'
#' @param covid "drop" (framework default) or "keep" (the DDD's selling point:
#'   state x month FE absorb state-specific pandemic shocks, so the COVID window
#'   need not be discarded).
#' @param h_rule How the high/low indicator is assigned. See
#'   \code{R/power/ddd_h_rules.R} for the full menu and the balance evidence:
#'   "poverty_resid" (DEFAULT since 2026-09-14), "poverty_renterwt",
#'   "poverty_median", "evrate_renterwt", "national". The legacy value
#'   "within_state" is accepted as an alias for "poverty_median" so the
#'   2026-08-21 run stays reproducible.
#'
#'   DEFAULT CHANGED 2026-09-14. The old default ("within_state") splits
#'   counties, not renters, on raw poverty; in this panel that selects smaller,
#'   more rural, LOWER-filing-rate counties (within-state cor(poverty, log
#'   eviction rate) = -0.202; only 35.2% of renters land in H = 1). Any run
#'   meant to be compared with the 2026-08-21 output must pass
#'   h_rule = "within_state" explicitly.
#' @param config A power config list.
#' @return County panel with unit_id, state_abb, month_date, filings_count,
#'   renters, poverty_rate, H, and a precomputed count-DGP baseline mu.
#' @export
build_ddd_skeleton <- function(covid = c("drop", "keep"),
                               h_rule = "poverty_resid",
                               config,
                               county_csv = "data/raw/monthly_county_data_download.csv") {
  covid  <- match.arg(covid)
  if (identical(h_rule, "within_state")) h_rule <- "poverty_median"
  h_rule <- match.arg(h_rule, DDD_H_RULES)

  panel <- load_blinded_panel(level = "county", treat_def = "online_start_date",
                              anticipation = 6, sample = "S2", covid = covid,
                              config = config)

  pov <- guarded_read_csv(county_csv) %>%
    mutate(unit_id = as.character(.data$fips)) %>%
    distinct(.data$unit_id, .data$poverty_rate) %>%
    filter(!is.na(.data$poverty_rate))

  out <- panel %>%
    inner_join(pov, by = "unit_id")

  # H assignment + the no-contrast-state drop both live in ddd_h_rules.R, which
  # also attaches the county-level classifier frame for ddd_h_balance().
  out <- ddd_assign_H(out, rule = h_rule)

  # Count-DGP baseline mu depends only on (unit, calendar month, filings) which
  # are fixed across reps -> precompute once instead of per injection.
  hf <- attr(out, "h_frame")
  out$mu_base <- .ie_baseline_mu(out$unit_id, out$month_date, out$filings_count)

  attr(out, "covid")   <- covid
  attr(out, "h_rule")  <- h_rule
  attr(out, "h_frame") <- hf
  out
}

#' Inject a poverty-differential effect using the framework's count_nb mechanism
#'
#' @param d Skeleton with D (0/1 pseudo-treated), H, filings_count, mu_base.
#' @param delta_h Log-point effect in high-poverty counties.
#' @param delta_l Log-point effect in low-poverty counties.
#' @param theta Negative-binomial variance/mean ratio (framework default 1.4).
#' @return Numeric vector: simulated log1p(filings).
#' @keywords internal
.ddd_inject <- function(d, delta_h, delta_l, theta = 1.4) {
  di <- d$D * ifelse(d$H == 1L, delta_h, delta_l)
  dY <- numeric(nrow(d))

  pos <- which(di > 0 & is.finite(d$mu_base))
  if (length(pos) > 0L) {
    m <- d$mu_base[pos] * (exp(di[pos]) - 1)
    dY[pos] <- if (theta > 1) {
      stats::rnbinom(length(pos), size = m / (theta - 1), mu = m)
    } else {
      stats::rpois(length(pos), lambda = m)
    }
  }
  neg <- which(di < 0 & is.finite(d$filings_count) & d$filings_count > 0)
  if (length(neg) > 0L) {
    dY[neg] <- -stats::rbinom(length(neg), size = as.integer(d$filings_count[neg]),
                              prob = 1 - exp(di[neg]))
  }
  log1p(pmax(round(d$filings_count + dY), 0))
}

#' Fit the DDD and the comparison TWFE DiD on one simulated panel
#' @keywords internal
.ddd_fit <- function(d, alpha = 0.05) {
  G  <- n_distinct(d$state_abb)
  df <- G - 1L

  grab <- function(fit, term) {
    if (inherits(fit, "try-error")) {
      return(list(est = NA_real_, se = NA_real_, rej = NA))
    }
    ct <- coeftable(fit)
    if (!term %in% rownames(ct)) return(list(est = NA_real_, se = NA_real_, rej = NA))
    b  <- unname(ct[term, "Estimate"])
    s  <- unname(ct[term, "Std. Error"])
    list(est = b, se = s,
         rej = as.integer(2 * stats::pt(-abs(b / s), df = df) < alpha))
  }

  ddd <- try(feols(y_sim ~ DH | unit_id + state_abb^month_date + H^month_date,
                   data = d, cluster = ~state_abb, notes = FALSE), silent = TRUE)
  did <- try(feols(y_sim ~ D | unit_id + month_date,
                   data = d, cluster = ~state_abb, notes = FALSE), silent = TRUE)

  a <- grab(ddd, "DH"); b <- grab(did, "D")
  tibble(estimator = c("ddd", "did_twfe"),
         est = c(a$est, b$est), se = c(a$se, b$se),
         reject = c(a$rej, b$rej),
         reject_wild = NA_integer_, p_wild = NA_real_,
         ci_lo = NA_real_, ci_hi = NA_real_,
         n_clusters = G, df = df)
}

#' Run the DDD power simulation
#'
#' @param skeleton Output of \code{build_ddd_skeleton()}.
#' @param deltas Numeric grid of effect sizes (log points).
#' @param dgps "differential" (delta_l = 0, delta_h = delta; DDD estimand =
#'   delta) and/or "uniform" (delta_l = delta_h = delta; DDD estimand = 0, so it
#'   doubles as a placebo, while the DiD estimand = delta).
#' @param n_reps Replications per cell.
#' @param n_cores Parallel workers (forked; macOS/Linux).
#' @return Long tibble, one row per rep x delta x dgp x estimator.
#' @export
run_ddd_power <- function(skeleton, deltas = c(0, 0.025, 0.05, 0.075, 0.10, 0.15, 0.20),
                          dgps = c("differential", "uniform"),
                          n_reps = 400L, n_cores = max(1L, parallel::detectCores() - 2L),
                          real_schedule_path = "data/raw/sports_gambling_legalization_dates.csv",
                          theta = 1.4,
                          wild = TRUE, B = 999L,
                          weight_by = c("none", "renters")) {

  weight_by <- match.arg(weight_by)

  real_sched <- guarded_read_csv(real_schedule_path)
  states_ok  <- sort(unique(skeleton$state_abb))

  one_rep <- function(rep) {
    seed_rep <- DDD_BASE_SEED + 10007L * rep
    set.seed(seed_rep)

    sch <- try(make_pseudo_schedule("D1", panel = skeleton, real_schedule = real_sched,
                                    treat_def = "online_start_date", seed = seed_rep,
                                    template = "panel"), silent = TRUE)
    if (inherits(sch, "try-error")) {
      return(tibble(rep = rep, delta = NA_real_, dgp = NA_character_,
                    estimator = NA_character_, est = NA_real_, se = NA_real_,
                    reject = NA_integer_, reject_wild = NA_integer_,
                    p_wild = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_,
                    n_clusters = NA_integer_, df = NA_integer_,
                    n_treated_obs = NA_integer_, feasible = FALSE))
    }

    d <- skeleton %>%
      left_join(sch %>% select(state_abb, pseudo_g), by = "state_abb") %>%
      mutate(e = ifelse(is.na(.data$pseudo_g), NA_integer_,
                        .ddd_mi(.data$month_date) - .ddd_mi(.data$pseudo_g)),
             D  = as.integer(!is.na(.data$e) & .data$e >= 0),
             DH = .data$D * .data$H)
    n_tr <- sum(d$D)

    res <- list(); k <- 0L
    for (dg in dgps) for (dl in deltas) {
      dh <- dl
      ll <- if (dg == "differential") 0 else dl
      d$y_sim <- .ddd_inject(d, delta_h = dh, delta_l = ll, theta = theta)
      k <- k + 1L
      fitres <- if (wild) {
        ddd_fit_wild(d, B = B, weight_by = weight_by,
                     seed = seed_rep + 7919L * k) %>%
          mutate(df = .data$n_clusters - 1L)
      } else {
        .ddd_fit(d)
      }
      res[[k]] <- fitres %>%
        mutate(rep = rep, delta = dl, dgp = dg, n_treated_obs = n_tr, feasible = TRUE)
    }
    bind_rows(res)
  }

  reps <- seq_len(as.integer(n_reps))
  # fixest::demean() is OpenMP-threaded; forking a multithreaded process under
  # mclapply silently kills the workers on macOS ("did not deliver results").
  # Parallelism is across reps, so one thread per worker is also the right
  # allocation. Restored on exit.
  if (n_cores > 1L) {
    .old_nthreads <- fixest::getFixest_nthreads()
    fixest::setFixest_nthreads(1L)
    on.exit(fixest::setFixest_nthreads(.old_nthreads), add = TRUE)
  }
  out <- if (n_cores > 1L && .Platform$OS.type != "windows") {
    parallel::mclapply(reps, one_rep, mc.cores = n_cores, mc.preschedule = TRUE)
  } else {
    lapply(reps, one_rep)
  }
  bind_rows(out) %>%
    select(rep, dgp, delta, estimator, est, se, reject, reject_wild, p_wild,
           ci_lo, ci_hi, n_clusters, df, n_treated_obs, feasible)
}

#' Summarize operating characteristics (size, power, calibration, bias)
#'
#' @param raw Output of \code{run_ddd_power()}.
#' @param truth_fn Function(dgp, delta, estimator, high_share) -> estimand.
#' @param high_share Share of counties with H = 1 (for the DiD estimand under
#'   the differential DGP).
#' @export
summarize_ddd <- function(raw, high_share) {
  truth <- function(dgp, delta, estimator) {
    ifelse(estimator == "ddd",
           ifelse(dgp == "differential", delta, 0),
           ifelse(dgp == "differential", delta * high_share, delta))
  }
  raw %>%
    filter(.data$feasible, !is.na(.data$est)) %>%
    group_by(.data$dgp, .data$delta, .data$estimator) %>%
    summarise(
      n_conv   = n(),
      estimand = truth(dplyr::first(.data$dgp), dplyr::first(.data$delta),
                       dplyr::first(.data$estimator)),
      mean_est = mean(.data$est),
      bias     = mean_est - estimand,
      sd_est   = stats::sd(.data$est),
      mean_se  = mean(.data$se),
      se_sd    = mean_se / sd_est,
      rej_rate      = mean(.data$reject),
      rej_rate_wild = mean(.data$reject_wild),
      .groups  = "drop"
    ) %>%
    arrange(.data$dgp, .data$estimator, .data$delta)
}
