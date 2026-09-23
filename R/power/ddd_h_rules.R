################################################################################
# R/power/ddd_h_rules.R
#
# Assignment rules for the DDD's high/low indicator H, plus the balance
# diagnostics that justify the choice.
#
# WHY THIS MODULE EXISTS (2026-09-14). The original rule -- a within-state
# median split on county poverty rate, counting counties -- does NOT produce a
# "poor renters vs better-off renters" contrast in this panel. Measured on the
# 2017-19 pre-period of `monthly_county_data_download.csv`:
#
#   within-state cor(poverty_rate, log eviction rate)  = -0.202
#   within-state cor(poverty_rate, log renters)        = -0.113
#   share of all renters landing in H = 1               =  0.352
#
# Poverty in this sample selects SMALLER, MORE RURAL counties with LOWER filing
# rates. So tau_high - tau_low under the legacy rule is closer to a
# rural-minus-urban contrast than to a distributional one, and because the
# count DGP injects effects proportional to baseline counts before log1p, the
# small-county arm is also where log1p is most nonlinear -- the likely source
# of the negative drift the uniform DGP shows.
#
# The rules below let the design state which contrast it is actually
# identifying, and `ddd_h_balance()` prints the evidence for each.
#
# BLINDNESS. Poverty is a covariate, not an outcome. The pre-period filing rate
# used by `poverty_resid` / `evrate_renterwt` is computed from the BLINDED
# skeleton (untreated county-months only, via load_blinded_panel) and is
# further restricted to months before `pre_end` so the COVID window cannot
# drive the classification. No treated-state outcome ever enters H.
#
# Working directory is assumed to be the repository root.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(rlang)
})

DDD_H_RULES <- c("poverty_median", "poverty_renterwt", "poverty_resid",
                 "evrate_renterwt", "national")

#' Weighted median
#' @keywords internal
.wmedian <- function(x, w) {
  ok <- is.finite(x) & is.finite(w) & w > 0
  if (!any(ok)) return(NA_real_)
  x <- x[ok]; w <- w[ok]
  o <- order(x); x <- x[o]; w <- w[o]
  cw <- cumsum(w) / sum(w)
  x[which(cw >= 0.5)[1L]]
}

#' Split on score so each arm carries ~half the WEIGHT, not half the units
#'
#' A strict `score > weighted_median` cut assigns the median unit wholly to the
#' low arm. When one county holds a large share of a state's renters that can
#' push the high arm far below 50% of renter mass -- which is exactly what the
#' first cut of `poverty_renterwt` did (0.365, no better than the count split).
#' Here units are ranked by score and taken into H = 1 until the cumulative
#' weight is closest to half.
#'
#' @param score Numeric ranking variable (higher = "high" arm).
#' @param w Non-negative weights.
#' @return Integer 0/1 vector, same length as score.
#' @keywords internal
.split_half_weight <- function(score, w) {
  n <- length(score)
  H <- integer(n)
  ok <- is.finite(score) & is.finite(w) & w > 0
  if (sum(ok) < 2L) return(H)
  idx <- which(ok)
  o   <- idx[order(score[idx], decreasing = TRUE)]
  cw  <- cumsum(w[o]) / sum(w[o])
  # take the prefix whose cumulative weight lands nearest 0.5, but always leave
  # at least one unit on each side so the state keeps a within-state contrast
  k <- which.min(abs(cw - 0.5))
  k <- max(1L, min(k, length(o) - 1L))
  H[o[seq_len(k)]] <- 1L
  H
}

#' County-level classifier inputs: one row per county
#'
#' @param panel Blinded county panel (unit_id, state_abb, month_date,
#'   filings_count, renters) already carrying `poverty_rate`.
#' @param pre_end Months strictly before this date define the pre-period used
#'   for the eviction-rate covariate. Default 2020-03-01 keeps the pandemic out
#'   of the classifier regardless of the run's covid setting.
#' @keywords internal
.ddd_county_frame <- function(panel, pre_end = as.Date("2020-03-01")) {
  panel %>%
    filter(.data$month_date < pre_end,
           is.finite(.data$filings_count), is.finite(.data$renters),
           .data$renters > 0) %>%
    group_by(.data$unit_id, .data$state_abb) %>%
    summarise(poverty_rate = dplyr::first(.data$poverty_rate),
              renters      = mean(.data$renters, na.rm = TRUE),
              mean_filings = mean(.data$filings_count, na.rm = TRUE),
              n_pre_months = dplyr::n(),
              .groups = "drop") %>%
    mutate(ev_rate  = 1000 * .data$mean_filings / .data$renters,
           l_evrate = log(.data$ev_rate + 0.1),
           l_rent   = log(.data$renters)) %>%
    filter(is.finite(.data$poverty_rate), is.finite(.data$l_evrate))
}

#' Assign the DDD high/low indicator H
#'
#' @param panel Blinded county panel carrying `poverty_rate`.
#' @param rule One of \code{DDD_H_RULES}:
#'   \describe{
#'     \item{poverty_median}{LEGACY. Within-state median split on poverty,
#'       counties counted equally. Retained for comparability with the
#'       2026-08-21 run; see the header for why it is not recommended.}
#'     \item{poverty_renterwt}{Within-state RENTER-WEIGHTED median split on
#'       poverty, so each arm holds ~half the renters rather than ~half the
#'       counties. Same contrast as the legacy rule, balanced exposure.}
#'     \item{poverty_resid}{Within-state renter-weighted median split on
#'       poverty RESIDUALIZED on log pre-period eviction rate and log renters.
#'       Isolates the poverty margin orthogonal to filing exposure and county
#'       size -- the closest available approximation to "poorer renters,
#'       otherwise similar county".}
#'     \item{evrate_renterwt}{CONTRAST ARM. Within-state renter-weighted median
#'       split on the pre-period eviction rate itself. Not a poverty contrast;
#'       included so a run can report what the filing-exposure margin does.
#'       Splits on a pre-period mean of the outcome, so read it as descriptive
#'       and expect mean reversion.}
#'     \item{national}{LEGACY. National poverty median, counties counted
#'       equally.}
#'   }
#' @param pre_end See \code{.ddd_county_frame()}.
#' @return `panel` with integer column `H`, and attribute "h_frame" holding the
#'   county-level classifier frame (used by `ddd_h_balance()`).
#' @export
ddd_assign_H <- function(panel, rule = "poverty_resid",
                         pre_end = as.Date("2020-03-01")) {
  rule <- match.arg(rule, DDD_H_RULES)
  cf   <- .ddd_county_frame(panel, pre_end = pre_end)

  cf <- switch(
    rule,
    poverty_median = cf %>% group_by(.data$state_abb) %>%
      mutate(score = .data$poverty_rate,
             cut   = stats::median(.data$poverty_rate)) %>% ungroup(),
    national = cf %>%
      mutate(score = .data$poverty_rate,
             cut   = stats::median(.data$poverty_rate)),
    poverty_renterwt = cf %>% group_by(.data$state_abb) %>%
      mutate(score = .data$poverty_rate,
             H_pre  = .split_half_weight(.data$poverty_rate, .data$renters)) %>%
      ungroup(),
    evrate_renterwt = cf %>% group_by(.data$state_abb) %>%
      mutate(score = .data$l_evrate,
             H_pre  = .split_half_weight(.data$l_evrate, .data$renters)) %>%
      ungroup(),
    poverty_resid = {
      # Residualize poverty on filing exposure and size WITHIN state. States
      # with too few counties to support the regression fall back to the raw
      # poverty score rather than dropping out.
      cf %>% group_by(.data$state_abb) %>%
        mutate(score = {
          if (dplyr::n() >= 5L && stats::var(.data$l_evrate) > 0 &&
              stats::var(.data$l_rent) > 0) {
            as.numeric(stats::resid(stats::lm(poverty_rate ~ l_evrate + l_rent)))
          } else {
            .data$poverty_rate - mean(.data$poverty_rate)
          }
        }) %>%
        mutate(H_pre = .split_half_weight(.data$score, .data$renters)) %>%
        ungroup()
    }
  )

  cf <- if ("H_pre" %in% names(cf)) {
    cf %>% mutate(H = as.integer(.data$H_pre)) %>% select(-"H_pre")
  } else {
    cf %>% mutate(H = as.integer(.data$score > .data$cut))
  }

  out <- panel %>% inner_join(cf %>% select("unit_id", "H"), by = "unit_id")

  # A state with no within-state contrast contributes nothing to beta once
  # state x month FE are in, and only inflates the cluster count.
  keep <- out %>% group_by(.data$state_abb) %>%
    summarise(k = dplyr::n_distinct(.data$H), .groups = "drop") %>%
    filter(.data$k == 2L) %>% pull(.data$state_abb)
  out <- out %>% filter(.data$state_abb %in% keep)

  attr(out, "h_rule")  <- rule
  attr(out, "h_frame") <- cf %>% filter(.data$state_abb %in% keep)
  out
}

#' Balance diagnostics for an H assignment
#'
#' Reports, per arm, what the split actually selected: counties, renter mass,
#' poverty, county size, and pre-period filing rate. A defensible poverty
#' contrast has a large poverty gap and a small size / filing-rate gap.
#'
#' @param panel Output of \code{ddd_assign_H()}.
#' @return One-row-per-arm tibble plus a "gap" row-pair summary as attributes.
#' @export
ddd_h_balance <- function(panel) {
  cf <- attr(panel, "h_frame")
  if (is.null(cf)) stop("panel has no h_frame attribute; use ddd_assign_H().", call. = FALSE)

  arms <- cf %>%
    group_by(H = .data$H) %>%
    summarise(
      n_counties   = dplyr::n(),
      renter_share = sum(.data$renters),
      med_poverty  = stats::median(.data$poverty_rate),
      med_renters  = stats::median(.data$renters),
      med_ev_rate  = stats::median(.data$ev_rate),
      .groups = "drop"
    ) %>%
    mutate(renter_share = .data$renter_share / sum(.data$renter_share))

  tibble::tibble(
    h_rule          = attr(panel, "h_rule"),
    n_states        = dplyr::n_distinct(cf$state_abb),
    n_counties_hi   = arms$n_counties[arms$H == 1L],
    n_counties_lo   = arms$n_counties[arms$H == 0L],
    renter_share_hi = arms$renter_share[arms$H == 1L],
    poverty_hi      = arms$med_poverty[arms$H == 1L],
    poverty_lo      = arms$med_poverty[arms$H == 0L],
    poverty_gap     = .data$poverty_hi - .data$poverty_lo,
    size_ratio      = arms$med_renters[arms$H == 1L] / arms$med_renters[arms$H == 0L],
    evrate_ratio    = arms$med_ev_rate[arms$H == 1L] / arms$med_ev_rate[arms$H == 0L]
  )
}
