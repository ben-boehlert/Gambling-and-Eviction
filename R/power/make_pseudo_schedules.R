################################################################################
# R/power/make_pseudo_schedules.R
#
# Pseudo-treatment schedule generators (POWER_SIMULATION_DESIGN.md §8). All
# assign treatment at the state level; every county in a pseudo-treated state
# inherits the state's date downstream (this module is state-level only).
#
#   D1  Cohort-preserving reassignment (primary)
#   D2  Shifted actual design (real identities fixed; placement/rescaling chosen)
#   D3  Untreated-risk-set uniform date draws
#   D4  Never-treated placebo (structure scaled to available states)
#
# set.seed(seed) at the top guarantees reproducibility: same seed -> identical
# schedule. Working directory assumed to be the repo root.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
  library(rlang)
})

if (!exists("eviction_state_name_to_abb", mode = "function")) {
  if (!file.exists("utils/eviction_treatment_schedule.R")) {
    stop("utils/eviction_treatment_schedule.R not found; run from repo root.",
         call. = FALSE)
  }
  source("utils/eviction_treatment_schedule.R")
}

if (!exists("switcher_inclusion_ok", mode = "function")) {
  source("R/power/inclusion_rule.R")
}

# Integer month index of a first-of-month date.
.month_index <- function(d) year(d) * 12L + (month(d) - 1L)

#' Months from the pseudo-cohort date back to the launch, for a treat_def
#'
#' 0 for the raw launch definitions; otherwise the median (over the template
#' states) of round((treat_def date - online_start_date) / 30.44) -- the same
#' rank-median rule run_scenario_grid uses to attach pseudo_launch after
#' placement, so eligibility and estimation agree on where the launch is.
#' @keywords internal
.template_launch_lag <- function(real_schedule, treat_def, states = NULL) {
  if (treat_def %in% c("online_start_date", "first_start_date")) return(0L)
  nm <- names(real_schedule)
  if (!all(c("state", "online_start_date", treat_def) %in% nm)) return(0L)
  ab <- eviction_state_name_to_abb(real_schedule[["state"]])
  ev <- as.Date(real_schedule[[treat_def]]); on <- as.Date(real_schedule[["online_start_date"]])
  ok <- !is.na(ev) & !is.na(on) & !is.na(ab)
  if (!is.null(states)) ok <- ok & ab %in% states
  if (!any(ok)) return(0L)
  lag <- round(as.numeric(difftime(ev[ok], on[ok], units = "days")) / 30.44)
  max(0L, as.integer(round(stats::median(lag))))
}

#' Extract the real per-state cohort dates under a treatment definition
#' @keywords internal
.extract_cohorts_states <- function(real_schedule, treat_def) {
  nm <- names(real_schedule)
  if ("state" %in% nm && treat_def %in% nm) {
    out <- tibble(
      state_abb = eviction_state_name_to_abb(real_schedule[["state"]]),
      g         = as.Date(real_schedule[[treat_def]])
    )
  } else if (all(c("state_abb", "g") %in% nm)) {
    out <- tibble(state_abb = real_schedule$state_abb,
                  g = as.Date(real_schedule$g))
  } else if (all(c("state_abb", "treat_start") %in% nm)) {
    out <- tibble(state_abb = real_schedule$state_abb,
                  g = as.Date(real_schedule$treat_start))
  } else {
    stop("real_schedule must have (state + '", treat_def,
         "') or (state_abb + g) or (state_abb + treat_start).", call. = FALSE)
  }
  out %>%
    filter(!is.na(.data$state_abb), !is.na(.data$g)) %>%
    group_by(.data$state_abb) %>%
    summarise(g = min(.data$g), .groups = "drop")
}

#' Never-treated states: panel states with no first-any treatment date
#' @keywords internal
.derive_never_treated <- function(real_schedule, panel_states) {
  nm <- names(real_schedule)
  if ("state" %in% nm && "first_start_date" %in% nm) {
    treated <- eviction_state_name_to_abb(
      real_schedule[["state"]][!is.na(real_schedule[["first_start_date"]])]
    )
  } else if (all(c("state_abb", "g_first") %in% nm)) {
    treated <- real_schedule$state_abb[!is.na(real_schedule$g_first)]
  } else {
    treated <- .extract_cohorts_states(real_schedule, "first_start_date")$state_abb
  }
  setdiff(panel_states, treated)
}

#' States with data covering [date - min_pre, date + min_post]
#'
#' ANCHOR WARNING. `d` is a pseudo-cohort date in the run's `treat_def` UNITS,
#' not the legalization date. Under the headline configs `treat_def` is
#' `shift12_start_date` = online launch + 12 months, so:
#'
#'   min_pre  = 12  ->  d - 12  =  the LAUNCH month (month 0 after legalization)
#'   min_post =  6  ->  d +  6  =  month +18 after legalization
#'
#' i.e. the eligibility box spans months [0, +18] after legalization and
#' contains NO pre-launch month. `min_pre` therefore guarantees none of the
#' clean-anchor baseline [launch-6, launch-1]; `min_post = 6` guarantees 7 of
#' the 13 outcome months [launch+12, launch+24].
#'
#' Reading these as launch-relative is a live trap: it produced an incorrect
#' (18,12) patch on 2026-09-14 that left D1 infeasible. And note this is a SPAN
#' check (does coverage reach far enough) while the strict PMD baseline is a
#' PRESENCE requirement (are those months observed) -- a state can clear
#' `min_pre` and still have its baseline punched out by the COVID drop, which
#' is why 34% of admitted state-slots contribute nothing. No (min_pre,min_post)
#' setting fixes that. See FINDINGS §6.
#'
#' @keywords internal
.eligible_states <- function(states, d, cov, min_pre, min_post, rule = NULL) {
  di <- .month_index(d)
  if (!is.null(rule)) {
    # PRESENCE eligibility (2026-09-16): a state is eligible for pseudo-date d
    # iff it would qualify as a switcher at the implied launch d - lag under
    # the inclusion rule (R/power/inclusion_rule.R): full observed baseline
    # and >= min_horizons usable, non-splice-adjacent outcome months. Replaces
    # the span box entirely; placed == contributing by construction.
    launch <- di - as.integer(rule$lag)
    ok <- vapply(states, function(s) {
      o <- rule$obs[[s]]
      !is.null(o) && switcher_inclusion_ok(o, launch, pmd = rule$pmd,
                                           min_horizons = rule$min_horizons,
                                           h_lo = rule$h_lo %||% 12L,
                                           h_hi = rule$h_hi %||% 24L,
                                           excluded = rule$excluded)
    }, logical(1))
    return(unname(states[ok]))
  }
  cov %>%
    filter(.data$state_abb %in% states,
           .month_index(.data$min_m) <= di - min_pre,
           .month_index(.data$max_m) >= di + min_post) %>%
    pull(.data$state_abb)
}

#' Assign cohorts to eligible states without replacement (shared by D1/D3/D4)
#'
#' @param placement Cohort-fill rule.
#'   \describe{
#'     \item{\code{"scarcest"}}{Historical default. Cohorts are filled in
#'       ascending order of eligible-state count (scarcest first) so that tight
#'       cohorts are not starved by earlier draws. This is DETERMINISTIC in the
#'       cohort order, which routes coverage-constrained states to particular
#'       cohort dates and makes assignment NON-EXCHANGEABLE: the pseudo-adoption
#'       date correlates negatively with a state's own outcome trend in 4,000 of
#'       4,000 draws examined, producing the positive delta = 0 null bias
#'       documented in quality_reports/nullbias_decomposition_2026-08-25.md.
#'       Kept as the default so every pre-2026-08-26 run reproduces exactly.}
#'     \item{\code{"random_order"}}{Fill cohorts in a RANDOM order, restarting
#'       on infeasibility. Breaks the systematic scarcest-first skew while
#'       keeping acceptance high. Not exactly uniform over feasible assignments.}
#'     \item{\code{"uniform"}}{Strict rejection sampling: draw a uniformly
#'       random assignment of sum(counts) pool states to cohort slots, keep it
#'       only if every assigned state is eligible for its own cohort. Exactly
#'       uniform over feasible assignments, hence exchangeable by construction —
#'       but acceptance can be very low when eligibility binds.}
#'   }
#' @param max_tries Restart/rejection budget for the non-default rules.
#' Returns NULL on infeasibility unless \code{error = TRUE}.
#' @keywords internal
.assign_cohorts <- function(dates, counts, pool, cov, min_pre, min_post,
                            error = TRUE, label = "assignment",
                            placement = c("scarcest", "random_order", "uniform"),
                            max_tries = 200L, rule = NULL, allow_drop = FALSE) {
  placement <- match.arg(placement)
  K <- length(dates)
  elig_all <- lapply(seq_len(K), function(k)
    .eligible_states(pool, dates[k], cov, min_pre, min_post, rule = rule))

  # allow_drop (presence eligibility only): a cohort date for which fewer
  # states qualify than the template asks for is DROPPED rather than making
  # the whole placement infeasible -- the analogue of a real cohort whose
  # states fail the inclusion rule (e.g. baselines inside the COVID gap).
  # Dropped dates are reported on the result as attr "dropped_cohorts".
  drop_k <- integer(0)
  if (isTRUE(allow_drop)) {
    drop_k <- which(vapply(elig_all, length, integer(1)) < counts)
  }
  keep_k <- setdiff(seq_len(K), drop_k)
  if (length(keep_k) == 0L) {
    if (error) stop(label, " infeasible: no cohort has enough eligible states.",
                    call. = FALSE)
    return(NULL)
  }

  # One greedy pass over cohorts in the supplied order. Row order and RNG
  # consumption match the pre-2026-08-26 implementation exactly.
  .fill <- function(ord) {
    ord  <- ord[ord %in% keep_k]
    used <- character(0)
    out  <- list()
    for (k in ord) {
      elig <- setdiff(elig_all[[k]], used)
      need <- counts[k]
      if (length(elig) < need) return(NULL)
      pick <- if (length(elig) == need) elig else sample(elig, need)
      out[[length(out) + 1L]] <- tibble(state_abb = pick, pseudo_g = dates[k])
      used <- c(used, pick)
    }
    bind_rows(out)
  }

  res <- NULL
  if (placement == "scarcest") {
    res <- .fill(order(vapply(elig_all, length, integer(1)), dates))

  } else if (placement == "random_order") {
    for (i in seq_len(max_tries)) {
      res <- .fill(sample.int(K))
      if (!is.null(res)) break
    }

  } else {
    total <- sum(counts)
    slot_k <- rep(seq_len(K), times = counts)
    for (i in seq_len(max_tries)) {
      res <- NULL
      if (length(pool) < total) break
      pick <- sample(pool, total)
      ok <- all(vapply(seq_along(pick), function(j)
        pick[j] %in% elig_all[[slot_k[j]]], logical(1)))
      if (ok) {
        res <- tibble(state_abb = pick, pseudo_g = dates[slot_k])
        break
      }
    }
  }

  if (is.null(res)) {
    if (error) {
      stop(label, " infeasible under placement = ", placement,
           " (min_pre = ", min_pre, ", min_post = ", min_post, ").",
           call. = FALSE)
    }
    return(NULL)
  }
  attr(res, "dropped_cohorts") <- dates[drop_k]
  res
}

#' Generate a pseudo-treatment schedule
#'
#' @param design One of "D1", "D2", "D3", "D4".
#' @param panel A blinded panel (state or county level); state-level coverage is
#'   derived from it.
#' @param real_schedule The real schedule: raw CSV tibble (state + *_start_date)
#'   or a tibble with state_abb + g.
#' @param treat_def Treatment-definition column used to read the real structure.
#' @param min_pre Minimum untreated months required before a pseudo date.
#' @param min_post Minimum months required at/after a pseudo date.
#' @param seed RNG seed (set once at top; same seed -> identical output).
#' @param template "national" (default): the cohort template is extracted from
#'   the FULL real schedule (online: 18 cohorts, ~24 states). "panel": the
#'   template is restricted to treated states PRESENT IN THE PANEL first —
#'   the design the real estimation actually identifies. Motivation
#'   (2026-08-10): the county panel holds ~29 usable states, so the national
#'   24-state template is deterministically unplaceable there (see
#'   POWER_SIMULATION_DESIGN.md §8 addenda); the panel template (~12 singleton
#'   cohorts) both fits and matches the real design's cohort structure.
#' @param never_treated Optional character vector of never-treated states (D4).
#'   Defaults to \code{attr(panel, "never_treated")} or a derivation from
#'   \code{real_schedule}.
#' @return Tibble(state_abb, pseudo_g[Date, first-of-month]) with attributes:
#'   design, seed, treat_def, min_pre, min_post, template,
#'   cohort_structure_target, cohort_structure_achieved, rescale_factor,
#'   feasibility.
#' @export
make_pseudo_schedule <- function(design = c("D1", "D2", "D3", "D4"),
                                 panel, real_schedule, treat_def,
                                 min_pre = 12L, min_post = 6L, seed,
                                 template = c("national", "panel"),
                                 never_treated = NULL,
                                 placement = c("scarcest", "random_order",
                                               "uniform"),
                                 eligibility = c("span", "presence"),
                                 min_horizons = 7L, pmd = 6L,
                                 excluded_months = as.Date(character(0)),
                                 launch_lag = NULL, template_states = NULL,
                                 hmin = NULL, hpost = NULL,
                                 anchor_rule = c("random_feasible",
                                                 "max_placed")) {
  design      <- match.arg(design)
  template    <- match.arg(template)
  placement   <- match.arg(placement)
  eligibility <- match.arg(eligibility)
  if (missing(seed)) stop("`seed` is required for reproducibility.", call. = FALSE)
  set.seed(seed)
  min_pre  <- as.integer(min_pre)
  min_post <- as.integer(min_post)

  # PRESENCE rule object (eligibility = "presence"; 2026-09-16). Under "span"
  # this is NULL and every code path below is byte-identical to before.
  # min_pre / min_post then only bound the anchor window; the per-state test
  # is the inclusion rule itself, on OBSERVED months.
  rule <- NULL
  if (identical(eligibility, "presence")) {
    obs <- split(.month_index(panel$month_date), as.character(panel$state_abb))
    if (is.null(launch_lag)) {
      launch_lag <- .template_launch_lag(real_schedule, treat_def,
                                         states = unique(panel$state_abb))
    }
    # Outcome window in months after LAUNCH (2026-09-18). NULL hmin/hpost keep
    # the historical hardcoded 12..24 (every config before this date). When the
    # caller passes the LP-DiD horizons, the window is the event-date horizons
    # shifted by the launch lag: a launch-indexed 6..18 design is lag 0 x 6..18.
    h_lo <- if (is.null(hmin))  12L else as.integer(launch_lag) + as.integer(hmin)
    h_hi <- if (is.null(hpost)) 24L else as.integer(launch_lag) + as.integer(hpost)
    rule <- list(obs = obs, lag = as.integer(launch_lag), pmd = as.integer(pmd),
                 min_horizons = min_horizons, h_lo = h_lo, h_hi = h_hi,
                 excluded = .month_index(as.Date(excluded_months)))
  }

  # State-level coverage (works for state OR county panels).
  cov <- panel %>%
    group_by(.data$state_abb) %>%
    summarise(min_m = min(.data$month_date),
              max_m = max(.data$month_date), .groups = "drop")
  panel_months <- sort(unique(panel$month_date))
  panel_min <- min(panel_months)
  panel_max <- max(panel_months)

  # Real cohort structure.
  sched   <- .extract_cohorts_states(real_schedule, treat_def)
  if (template == "panel") {
    sched <- sched %>% filter(.data$state_abb %in% cov$state_abb)
    if (nrow(sched) == 0L) {
      stop("Panel-restricted template is empty: no panel state has a ",
           "treatment date under treat_def = ", treat_def, ".", call. = FALSE)
    }
  }
  # TEMPLATE RESTRICTION (2026-09-16). The blinded panel holds untreated months
  # only, so a real treated state's own launch window is never observable
  # here and the rule cannot be evaluated on real switchers inside this
  # function. The real switcher set under the inclusion rule is computed by
  # the coverage-only audit (analysis/diagnostics/clean_design_window_audit.R)
  # and passed in as `template_states`; cohorts of real states that fail the
  # rule are then not asked of the simulation either. NULL = no restriction.
  template_dropped <- character(0)
  if (!is.null(template_states)) {
    keep <- sched$state_abb %in% as.character(template_states)
    template_dropped <- sched$state_abb[!keep]
    sched <- sched[keep, , drop = FALSE]
    if (nrow(sched) == 0L) {
      stop("template_states leaves no treated state in the template.",
           call. = FALSE)
    }
  }
  cohorts <- sched %>% count(.data$g, name = "n_states") %>% arrange(.data$g)
  K <- nrow(cohorts)
  if (K == 0L) {
    stop("No treated cohorts found under treat_def = ", treat_def, call. = FALSE)
  }
  offsets <- .month_index(cohorts$g) - .month_index(cohorts$g[1])
  span    <- max(offsets)

  feasible_start <- panel_min %m+% months(min_pre)
  feasible_end   <- panel_max %m-% months(min_post)
  L <- .month_index(feasible_end) - .month_index(feasible_start)
  if (L < 0L) {
    stop("Panel window too short: min_pre (", min_pre, ") + min_post (",
         min_post, ") exceed observed span.", call. = FALSE)
  }

  # Template placement (shared by D1/D2/D4): rescale gaps if they don't fit the
  # feasible window; then search anchor placements (seeded random order) for one
  # that yields a feasible assignment, since state coverage is uneven across the
  # panel's calendar span. Only error if NO placement works.
  rescale_factor   <- 1
  feasibility_flag <- "ok"
  eff_offsets <- offsets
  if (span > L) {
    rescale_factor   <- L / span
    eff_offsets      <- as.integer(round(offsets * rescale_factor))
    feasibility_flag <- "rescaled"
  }
  eff_span <- max(eff_offsets)
  slack    <- L - eff_span
  candidates <- if (slack > 0L) sample(0:slack) else 0L

  # Place the template at each candidate anchor and assign `pool` states.
  #
  # ANCHOR RULE under `presence` (2026-09-17, Ben's option A).
  #   "max_placed" (the 2026-09-16 original) keeps whichever anchor places the
  #     MOST states. Because coverage is densest at the real 2022-2024 dates,
  #     it lands there in 36 of 40 reps -- and there the only untreated states
  #     left are the handful of never-legalizers, which become the pseudo-
  #     switchers AND the entire control pool at once. The result is a
  #     degenerate comparison (state SD 0.215, reps piling at +1.06), not an
  #     estimator property. See FINDINGS.md 5.
  #   "random_feasible" (the new default) draws uniformly from the anchors that
  #     ARE feasible, so the template lands wherever the panel can actually
  #     support it -- pre-COVID in most reps, where a real control pool exists.
  #     The MDE is then translated back to the post-COVID era with the measured
  #     era-variance inflation (~2.04, the 08-19 memo) rather than being read
  #     off a design the panel cannot represent.
  # A pseudo-treatment design CANNOT reproduce the real post-COVID design at its
  # own calendar position -- the real control pool IS the never-treated set --
  # so the choice is which honest approximation to make, not whether to make one.
  # `anchor_rule: max_placed` in a config restores the old behaviour.
  anchor_rule <- match.arg(anchor_rule, c("random_feasible", "max_placed"))
  place_template <- function(pool, counts, offs, label) {
    best <- NULL; best_n <- -1L; feasible <- list()
    for (so in candidates) {
      dts <- (feasible_start %m+% months(so)) %m+% months(offs)
      res <- .assign_cohorts(dts, counts, pool = pool, cov = cov,
                             min_pre = min_pre, min_post = min_post,
                             error = FALSE, label = label,
                             placement = placement, rule = rule,
                             allow_drop = !is.null(rule))
      if (is.null(res)) next
      if (is.null(rule)) return(res)
      if (identical(anchor_rule, "random_feasible")) {
        # Collect every feasible anchor that fills the template, then draw one.
        # `candidates` is already in seeded random order, so taking the first
        # full placement IS a uniform draw over full-template anchors.
        if (nrow(res) == sum(counts)) return(res)
        feasible[[length(feasible) + 1L]] <- res
      } else {
        if (nrow(res) > best_n) { best <- res; best_n <- nrow(res) }
        if (nrow(res) == sum(counts)) break
      }
    }
    if (identical(anchor_rule, "random_feasible") && length(feasible)) {
      # No anchor fills the template: fall back to the fullest, as before, but
      # break ties at random rather than by scan order.
      ns <- vapply(feasible, nrow, integer(1))
      pick <- which(ns == max(ns))
      return(feasible[[pick[sample.int(length(pick), 1L)]]])
    }
    if (!is.null(best)) return(best)
    stop(label, " infeasible: no template placement within the panel window ",
         "yields enough eligible states (min_pre = ", min_pre,
         ", min_post = ", min_post, ").", call. = FALSE)
  }

  if (design == "D1") {
    assigned <- place_template(cov$state_abb, cohorts$n_states, eff_offsets, "D1")

  } else if (design == "D2") {
    treated_in_panel <- intersect(sched$state_abb, cov$state_abb)
    dropped <- setdiff(sched$state_abb, treated_in_panel)
    if (length(dropped) > 0L) {
      feasibility_flag <- paste0(feasibility_flag,
                                 ";dropped_not_in_panel=", length(dropped))
    }
    # Fixed identities: choose the placement minimizing unsupported states.
    best <- NULL; best_unsup <- Inf
    for (so in candidates) {
      dts  <- (feasible_start %m+% months(so)) %m+% months(eff_offsets)
      cmap <- tibble(g = cohorts$g, pseudo_g = dts)
      asg  <- sched %>%
        filter(.data$state_abb %in% treated_in_panel) %>%
        left_join(cmap, by = "g") %>%
        transmute(.data$state_abb, .data$pseudo_g)
      unsup <- asg %>%
        left_join(cov, by = "state_abb") %>%
        filter(.month_index(.data$min_m) > .month_index(.data$pseudo_g) - min_pre |
                 .month_index(.data$max_m) < .month_index(.data$pseudo_g) + min_post) %>%
        nrow()
      if (unsup < best_unsup) { best_unsup <- unsup; best <- asg }
      if (unsup == 0L) break
    }
    assigned <- best
    if (best_unsup > 0L) {
      feasibility_flag <- paste0(feasibility_flag,
                                 ";unsupported_states=", best_unsup)
    }

  } else if (design == "D3") {
    feas_months <- panel_months[panel_months >= feasible_start &
                                  panel_months <= feasible_end]
    if (length(feas_months) == 0L) {
      stop("D3 infeasible: no panel months within the feasible window.",
           call. = FALSE)
    }
    assigned <- NULL
    for (try_i in seq_len(500L)) {
      dts <- sort(feas_months[sample.int(length(feas_months), K,
                                         replace = TRUE)])
      res <- .assign_cohorts(dts, cohorts$n_states, pool = cov$state_abb,
                             placement = placement,
                             cov = cov, min_pre = min_pre, min_post = min_post,
                             error = FALSE, label = "D3")
      if (!is.null(res)) { assigned <- res; break }
    }
    if (is.null(assigned)) {
      stop("D3 infeasible: no uniform date draw yielded enough eligible ",
           "states after 500 attempts.", call. = FALSE)
    }

  } else { # D4
    nt <- never_treated %||% attr(panel, "never_treated") %||%
      .derive_never_treated(real_schedule, cov$state_abb)
    nt <- intersect(nt, cov$state_abb)
    N_nt <- length(nt)
    if (N_nt == 0L) stop("D4 infeasible: no never-treated states in panel.",
                         call. = FALSE)

    total_target <- sum(cohorts$n_states)
    target_total <- min(total_target, N_nt)
    raw     <- cohorts$n_states * (target_total / total_target)
    base_ct <- floor(raw)
    rem     <- target_total - sum(base_ct)
    if (rem > 0L) {
      frac_ord <- order(raw - base_ct, decreasing = TRUE)
      base_ct[frac_ord[seq_len(rem)]] <- base_ct[frac_ord[seq_len(rem)]] + 1L
    }
    keep <- base_ct > 0L
    assigned <- place_template(nt, base_ct[keep], eff_offsets[keep], "D4")
    feasibility_flag <- paste0(feasibility_flag, ";never_treated_pool=", N_nt)
  }

  out <- assigned %>%
    mutate(pseudo_g = floor_date(as.Date(.data$pseudo_g), "month")) %>%
    arrange(.data$pseudo_g, .data$state_abb)

  attr(out, "design")                    <- design
  attr(out, "seed")                      <- seed
  attr(out, "treat_def")                 <- treat_def
  attr(out, "min_pre")                   <- min_pre
  attr(out, "min_post")                  <- min_post
  attr(out, "template")                  <- template
  attr(out, "cohort_structure_target")   <- cohorts
  attr(out, "cohort_structure_achieved") <-
    out %>% count(.data$pseudo_g, name = "n_states") %>% arrange(.data$pseudo_g)
  attr(out, "rescale_factor")            <- rescale_factor
  attr(out, "eligibility")               <- eligibility
  attr(out, "min_horizons")              <- if (is.null(rule)) NA_integer_ else rule$min_horizons
  attr(out, "launch_lag")                <- if (is.null(rule)) NA_integer_ else rule$lag
  attr(out, "excluded_months")           <- as.Date(excluded_months)
  attr(out, "template_states_dropped")   <- template_dropped
  attr(out, "dropped_cohorts")           <- attr(assigned, "dropped_cohorts") %||% as.Date(character(0))
  if (length(template_dropped) > 0L) {
    feasibility_flag <- paste0(feasibility_flag, ";template_dropped=",
                               length(template_dropped))
  }
  if (length(attr(out, "dropped_cohorts")) > 0L) {
    feasibility_flag <- paste0(feasibility_flag, ";cohorts_dropped=",
                               length(attr(out, "dropped_cohorts")))
  }
  attr(out, "feasibility")               <- feasibility_flag

  out
}
