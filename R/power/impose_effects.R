################################################################################
# R/power/impose_effects.R
#
# Effect injection for the blinded power-simulation framework
# (POWER_SIMULATION_DESIGN.md §9). Takes a blinded untreated panel (g == 0
# everywhere) plus a pseudo-treatment schedule and imposes a KNOWN effect of a
# chosen shape via a chosen mechanism, returning the panel with per-cell imposed
# truth (`delta_imposed`) and simulated outcomes (`y_sim`, `y_sim_count`).
#
# Mechanisms (M1/M2, §9):
#   count_nb      count-based stochastic augmentation, NegBin(var/mean = theta)
#   count_pois    count-based stochastic augmentation, Poisson
#   thinning      binomial thinning only (BHNS mechanism; for delta <= 0)
#   deterministic transformed-scale additive shift (M2 benchmark)
#
# Shapes (§9): step, delayed, ramp, temporary, anticipation, cohort_het,
#   state_het, exposure_het, intensity_ramp, null.
#
# set.seed(seed) once at the top guarantees reproducibility: same seed ->
# identical injection. Working directory assumed to be the repository root.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
  library(rlang)
})

# Default-getter for params list entries.
.ie_param <- function(params, key, default) {
  v <- params[[key]]
  if (is.null(v) || length(v) == 0L || is.na(v[1])) default else v
}

# Integer number of months from pseudo_g to month_date (event time e).
.ie_event_time <- function(month_date, pseudo_g) {
  (year(month_date) - year(pseudo_g)) * 12L +
    (month(month_date) - month(pseudo_g))
}

#' Per-row imposed delta for a given effect shape
#'
#' Returns a numeric vector the length of \code{e}. Rows with \code{NA} event
#' time (never pseudo-treated states) always receive 0. Heterogeneous shapes
#' (cohort_het, state_het, exposure_het) draw / compute their multipliers from
#' the seeded RNG stream and the panel itself; the caller must have set the seed.
#'
#' @keywords internal
.ie_delta_by_shape <- function(shape, delta, e, cohort, state, renters,
                               params) {
  n <- length(e)
  di <- numeric(n)
  has_e <- !is.na(e)

  onset   <- as.integer(.ie_param(params, "onset", 6L))
  plateau <- as.integer(.ie_param(params, "plateau", 18L))
  dur     <- as.integer(.ie_param(params, "dur", 12L))
  antic   <- as.integer(.ie_param(params, "antic", 3L))
  sigma   <- as.numeric(.ie_param(params, "sigma", 0.4))
  # tau (intensity_ramp): HANDLE-CALIBRATED (2026-08-11). The LSR handle
  # quintile-timing analysis (analysis/exploratory/quintile_timing_analysis.R;
  # CLAUDE.md "Gambling Market Maturation") gives median 30 months from launch
  # to 80% of peak monthly handle: 1 - exp(-30/tau) = 0.8  =>  tau = 30/ln(5)
  # ≈ 18.6. This replaces the arbitrary 12-month default so the maturation
  # shape tracks observed market ramp-up rather than a guess. NOTE: shape
  # params are not part of the scenario content hash — change them only when
  # no partial for a scenario using this shape exists.
  tau     <- as.numeric(.ie_param(params, "tau", 30 / log(5)))

  switch(
    shape,
    null = {
      # di stays all zero.
    },
    step = {
      di[has_e & e >= 0L] <- delta
    },
    delayed = {
      di[has_e & e >= onset] <- delta
    },
    ramp = {
      post <- has_e & e >= 0L
      di[post] <- delta * pmin(e[post] + 1L, plateau + 1L) / (plateau + 1L)
    },
    temporary = {
      di[has_e & e >= 0L & e < dur] <- delta
    },
    anticipation = {
      di[has_e & e >= -antic] <- delta
    },
    cohort_het = {
      # One uniform(0.5, 1.5) multiplier per (pseudo-)cohort, drawn once.
      cl <- sort(unique(cohort[!is.na(cohort)]))
      mult <- stats::runif(length(cl), min = 0.5, max = 1.5)
      names(mult) <- as.character(cl)
      post <- has_e & e >= 0L
      di[post] <- delta * mult[as.character(cohort[post])]
    },
    state_het = {
      # Mean-preserving lognormal multiplier per state (mean 1).
      st <- sort(unique(state[!is.na(cohort)]))
      draw <- stats::rlnorm(length(st), meanlog = -sigma^2 / 2, sdlog = sigma)
      names(draw) <- st
      post <- has_e & e >= 0L
      di[post] <- delta * draw[state[post]]
    },
    exposure_het = {
      # Within-state renter-share exposure, scaled to mean 1 within each state.
      exp_unit <- rep(1, n)
      dfx <- tibble(state = state, renters = renters, idx = seq_len(n))
      dfx <- dfx %>%
        group_by(.data$state) %>%
        mutate(
          mr = mean(.data$renters[is.finite(.data$renters) & .data$renters > 0]),
          ex = ifelse(is.finite(.data$renters) & .data$renters > 0 &
                        is.finite(.data$mr) & .data$mr > 0,
                      .data$renters / .data$mr, 1)
        ) %>%
        ungroup()
      exp_unit[dfx$idx] <- dfx$ex
      post <- has_e & e >= 0L
      di[post] <- delta * exp_unit[post]
    },
    intensity_ramp = {
      post <- has_e & e >= 0L
      di[post] <- delta * (1 - exp(-(e[post] + 1L) / tau))
    },
    stop("Unknown shape: ", shape, call. = FALSE)
  )
  di
}

#' Baseline expected count mu_ist (county x calendar-month mean, floored)
#'
#' Computed FROM THE PANEL ITSELF (untreated by construction): the mean of
#' \code{filings_count} within each (unit, calendar-month) cell, falling back to
#' the unit mean where a cell is empty, floored at \code{max(unit mean, 0.5)} so
#' that even zero-count cells receive a strictly positive expected injection
#' (§9). Never zero.
#'
#' @keywords internal
.ie_baseline_mu <- function(unit_id, month_date, filings_count) {
  cal <- month(month_date)
  df <- tibble(unit_id = unit_id, cal = cal, fc = filings_count,
               idx = seq_along(unit_id))
  unit_mean <- df %>%
    group_by(.data$unit_id) %>%
    summarise(um = mean(.data$fc, na.rm = TRUE), .groups = "drop")
  cell_mean <- df %>%
    group_by(.data$unit_id, .data$cal) %>%
    summarise(cm = mean(.data$fc, na.rm = TRUE), .groups = "drop")
  out <- df %>%
    left_join(cell_mean, by = c("unit_id", "cal")) %>%
    left_join(unit_mean, by = "unit_id") %>%
    mutate(
      um = ifelse(is.finite(.data$um), .data$um, 0),
      cm = ifelse(is.finite(.data$cm), .data$cm, .data$um),
      mu = pmax(.data$cm, .data$um, 0.5)   # floor at max(unit mean, 0.5)
    ) %>%
    arrange(.data$idx)
  out$mu
}

#' Impose a known effect on a blinded panel
#'
#' @param panel A blinded panel from \code{load_blinded_panel()} (g == 0). Must
#'   contain unit_id, state_abb, month_date, filings_count, renters, and the
#'   chosen \code{outcome} transform column.
#' @param schedule Tibble(state_abb, pseudo_g). States absent from the schedule
#'   are treated as never pseudo-treated (receive no effect).
#' @param mechanism Injection mechanism (see file header).
#' @param shape Effect shape (see file header).
#' @param delta Nominal proportional effect (log-points) / additive shift.
#' @param params Named list of shape parameters (onset, plateau, dur, antic,
#'   sigma, tau) and mechanism parameters (theta).
#' @param outcome Analysis-scale outcome column: "y_log1p", "y_lograte", or
#'   "y_asinh".
#' @param seed RNG seed (set once at top; same seed -> identical injection).
#' @return The panel with added columns \code{pseudo_g}, \code{e},
#'   \code{delta_imposed}, \code{y_sim_count} (NA for deterministic), and
#'   \code{y_sim} (on the chosen \code{outcome} scale). Attributes: mechanism,
#'   shape, delta, params, seed, outcome.
#' @export
impose_effect <- function(panel, schedule,
                          mechanism = c("count_nb", "count_pois",
                                        "thinning", "deterministic"),
                          shape = c("step", "delayed", "ramp", "temporary",
                                    "anticipation", "cohort_het", "state_het",
                                    "exposure_het", "intensity_ramp", "null"),
                          delta = 0.10, params = list(),
                          outcome = c("y_log1p", "y_lograte", "y_asinh"),
                          seed = 1L) {
  mechanism <- match.arg(mechanism)
  shape     <- match.arg(shape)
  outcome   <- match.arg(outcome)
  stopifnot(all(c("state_abb", "month_date", "unit_id") %in% names(panel)))
  if (!outcome %in% names(panel)) {
    stop("outcome column '", outcome, "' not found in panel.", call. = FALSE)
  }

  set.seed(seed)

  # Join the pseudo-treatment schedule (states not present -> never treated).
  keep_cols <- intersect(c("state_abb", "pseudo_g", "pseudo_launch"),
                         names(schedule))
  sched <- schedule %>%
    distinct(dplyr::across(dplyr::all_of(keep_cols))) %>%
    mutate(pseudo_g = as.Date(.data$pseudo_g))
  if ("pseudo_launch" %in% keep_cols)
    sched$pseudo_launch <- as.Date(sched$pseudo_launch)
  out <- panel %>% left_join(sched, by = "state_abb")

  out$e <- .ie_event_time(out$month_date, out$pseudo_g)

  # Per-row imposed truth. cohort := pseudo_g (grouping); NA where never treated.
  di <- .ie_delta_by_shape(
    shape = shape, delta = delta, e = out$e,
    cohort = out$pseudo_g, state = out$state_abb, renters = out$renters,
    params = params
  )
  di[is.na(out$e)] <- 0
  out$delta_imposed <- di

  base_col <- panel[[outcome]]

  if (mechanism == "deterministic") {
    out$y_sim_count <- NA_integer_
    out$y_sim <- base_col + out$delta_imposed

  } else {
    stopifnot("filings_count" %in% names(panel))
    fc <- as.numeric(panel$filings_count)
    theta <- as.numeric(.ie_param(params, "theta", 1.4))
    dY <- numeric(nrow(out))

    if (mechanism == "thinning") {
      # Binomial thinning only; positive deltas cannot thin upward (no-op).
      neg <- which(out$delta_imposed < 0 & is.finite(fc) & fc > 0)
      if (length(neg) > 0L) {
        prob_remove <- 1 - exp(out$delta_imposed[neg])
        dY[neg] <- -stats::rbinom(length(neg), size = as.integer(fc[neg]),
                                  prob = prob_remove)
      }
    } else {
      # count_nb / count_pois: augmentation for delta>0, thinning for delta<0.
      mu <- .ie_baseline_mu(panel$unit_id, panel$month_date, fc)
      pos <- which(out$delta_imposed > 0 & is.finite(mu))
      neg <- which(out$delta_imposed < 0 & is.finite(fc) & fc > 0)
      if (length(pos) > 0L) {
        m <- mu[pos] * (exp(out$delta_imposed[pos]) - 1)   # mean of Delta Y
        if (mechanism == "count_pois" || !(theta > 1)) {
          dY[pos] <- stats::rpois(length(pos), lambda = m)
        } else {
          # NegBin parameterized so var/mean = theta: size = mean/(theta-1).
          size_r <- m / (theta - 1)
          dY[pos] <- stats::rnbinom(length(pos), size = size_r, mu = m)
        }
      }
      if (length(neg) > 0L) {
        prob_remove <- 1 - exp(out$delta_imposed[neg])
        dY[neg] <- -stats::rbinom(length(neg), size = as.integer(fc[neg]),
                                  prob = prob_remove)
      }
    }

    y_sim_count <- as.integer(pmax(round(fc + dY), 0))
    out$y_sim_count <- y_sim_count

    renters <- as.numeric(panel$renters)
    y_sim_log1p   <- log1p(y_sim_count)
    y_sim_lograte <- log(y_sim_count / renters * 1000 + 0.01)
    y_sim_asinh   <- asinh(y_sim_count)
    out$y_sim <- switch(outcome,
                        y_log1p   = y_sim_log1p,
                        y_lograte = y_sim_lograte,
                        y_asinh   = y_sim_asinh)
  }

  attr(out, "mechanism") <- mechanism
  attr(out, "shape")     <- shape
  attr(out, "delta")     <- delta
  attr(out, "params")    <- params
  attr(out, "seed")      <- seed
  attr(out, "outcome")   <- outcome
  out
}
