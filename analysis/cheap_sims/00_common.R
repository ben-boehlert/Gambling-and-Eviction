################################################################################
# analysis/cheap_sims/00_common.R
#
# Shared machinery for the cheap staged simulation framework (Sims 0-4).
# Sourced by 01_stage0_audit.R, 02_run_cheap_grid.R, 03_summarize.R,
# 04_jackknife_diag.R. Reuses R/power/ modules wherever possible.
#
# Design decisions (see quality_reports/plans/2026-08-12_cheap-staged-sim-
# framework.md and analysis/cheap_sims/CHEAP_POWER_SIM_NOTES.md):
#   - state-month panel, y_log1p outcome, panel floor 2016-01
#   - treatment = online_start_date from the REPAIRED schedule CSV (never the
#     stale treat_start embedded in state_month_panel_with_treatment.csv)
#   - NV hard-excluded: absent from the schedule CSV, so schedule-derived
#     "never-treated" logic would silently miscode it; it is online-treated
#     before the post-PASPA sample era
#   - ME included (repaired 2026-07-23; online Nov 2023)
#   - untreated ("blinded") sim panel censors every state at
#     first_start_date - anticipation months (protocol section 4)
#   - COVID window (framework protocol default 2020-03-01..2021-07-31) DROPPED
#   - placebo schedules preserve the REAL online cohort calendar exactly
#     (no anchor shift): COVID alignment is the object of study
#
# Working directory: repository root.
################################################################################

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
})

stopifnot(file.exists("power_simulation_cs.R"))  # repo-root guard

source("R/power/config.R")
source("R/power/blindness_checks.R")
source("R/power/load_blinded_panel.R")
source("R/power/impose_effects.R")     # .ie_baseline_mu, .ie_event_time, .ie_param
source("R/power/run_estimators.R")     # .re_prep, .re_tp, run_estimator
if (!exists("load_eviction_treatment_schedule", mode = "function")) {
  source("utils/eviction_treatment_schedule.R")
}

# ---- configuration ----------------------------------------------------------

.cs_envchr <- function(k, d) { v <- Sys.getenv(k); if (nzchar(v)) v else d }
.cs_envint <- function(k, d) { v <- Sys.getenv(k); if (nzchar(v)) as.integer(v) else d }

#' Cheap-sim configuration (env-overridable where it matters)
cheap_config <- function() {
  list(
    state_panel  = "data/raw/state_month_panel_with_treatment.csv",
    schedule     = "data/raw/sports_gambling_legalization_dates.csv",
    handle_csv   = "data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv",
    out_dir      = .cs_envchr("CHEAP_OUT_DIR", "output/cheap_power_sim"),
    panel_floor  = as.Date("2016-01-01"),
    covid_start  = as.Date(.cs_envchr("CHEAP_COVID_START", "2020-03-01")),
    covid_end    = as.Date(.cs_envchr("CHEAP_COVID_END",   "2021-07-31")),
    anticipation = .cs_envint("CHEAP_ANTICIPATION", 6L),
    min_pre      = .cs_envint("CHEAP_MIN_PRE", 12L),   # placebo eligibility
    min_post     = .cs_envint("CHEAP_MIN_POST", 6L),
    base_seed    = 20260723L,   # shared with the blinded power framework
    theta_nb     = 1.4,         # count_nb overdispersion (framework default)
    alpha        = 0.05,
    exclude_states = c("NV")    # see header
  )
}

.month_idx <- function(d) year(d) * 12L + (month(d) - 1L)

# ---- panel construction -----------------------------------------------------

#' Build the state-month design object.
#'
#' Returns a list:
#'   design : one row per state-month with real treatment context (for AUDIT:
#'            outcome, online date, event month, treated/not-yet flags, COVID
#'            flags, coverage). Contains treated-period outcomes; used only for
#'            audit tables and the unblinded Sim-4 LOSO diagnostic.
#'   sim    : the untreated ("blinded") simulation panel: rows censored at
#'            first_start - anticipation, COVID window dropped, NV excluded.
#'            Columns match impose_effect() expectations (unit_id, state_abb,
#'            month_date, t, filings_count, renters, y_log1p, g = 0).
#'   states : per-state audit summary (coverage, usable pre/post months, etc.)
build_sim_state_panel <- function(cfg = cheap_config()) {
  sched_online <- load_eviction_treatment_schedule(cfg$schedule, "online_start_date") %>%
    rename(online_g = treat_start)
  sched_first  <- load_eviction_treatment_schedule(cfg$schedule, "first_start_date") %>%
    rename(g_first = treat_start)

  raw <- read_csv(cfg$state_panel, show_col_types = FALSE) %>%
    mutate(month_date = floor_date(as.Date(month_date), "month")) %>%
    filter(!is.na(filings_count),
           month_date >= cfg$panel_floor,
           !state_abb %in% cfg$exclude_states)

  design <- raw %>%
    transmute(
      state_abb, month_date,
      filings_count = as.numeric(filings_count),
      renters       = as.numeric(renter_occupied_housing_units),
      y_log1p       = log1p(as.numeric(filings_count))
    ) %>%
    left_join(sched_online, by = "state_abb") %>%
    left_join(sched_first,  by = "state_abb") %>%
    mutate(
      event_m   = if_else(!is.na(online_g),
                          .month_idx(month_date) - .month_idx(online_g),
                          NA_integer_),
      treated_m = !is.na(online_g) & month_date >= online_g,
      not_yet_m = is.na(online_g) | month_date < online_g,
      covid_m   = month_date >= cfg$covid_start & month_date <= cfg$covid_end
    )

  states <- design %>%
    group_by(state_abb, online_g, g_first) %>%
    summarise(
      first_obs   = min(month_date),
      last_obs    = max(month_date),
      n_obs       = n(),
      n_pre_online  = sum(not_yet_m & !covid_m),
      n_post_online = sum(treated_m & !covid_m),
      .groups = "drop"
    ) %>%
    mutate(
      # A state is treated *in the observed sample* only if we ever observe a
      # post-online outcome month (NC and MO fail this: coverage ends first).
      treated_observed = !is.na(online_g) & n_post_online > 0L,
      censor_month     = if_else(!is.na(g_first),
                                 g_first %m-% months(cfg$anticipation),
                                 as.Date(NA)),
      # identification-era flags relative to the COVID window
      contributes_precovid  = treated_observed & online_g < cfg$covid_start,
      contributes_postcovid = treated_observed & online_g > cfg$covid_end,
      contributes_crosscovid = treated_observed &
        online_g >= cfg$covid_start & online_g <= cfg$covid_end
    )

  sim <- design %>%
    left_join(states %>% select(state_abb, censor_month), by = "state_abb") %>%
    filter(is.na(censor_month) | month_date < censor_month,
           !covid_m) %>%
    transmute(
      unit_id = state_abb, state_abb, month_date,
      filings_count, renters, y_log1p, g = 0
    )
  tkey  <- .month_idx(sim$month_date)
  sim$t <- as.integer(tkey - min(tkey) + 1L)

  list(design = design, sim = sim, states = states, cfg = cfg)
}

# ---- gambling exposure ramps ------------------------------------------------

#' State-specific normalized gambling-exposure profiles in ONLINE event time.
#'
#' exposure_s(e) = Handle_s(month at e) / mature_s, where mature_s is the
#' state's PEAK monthly handle excluding the COVID window -- the definition
#' settled in analysis/exploratory/quintile_timing_analysis.R (the same work
#' that calibrated the intensity_ramp tau). Capped at 1 (only COVID months can
#' exceed the non-COVID peak). Months before online start are 0 by
#' construction; interior gaps are linearly interpolated. Population/renters
#' cancel out of the normalization, so no per-capita series is needed here.
#'
#' Returns list(profiles = tibble(state_abb, e, expo),
#'              mature   = tibble(state_abb, mature_handle, peak_date, n_e))
build_exposure_ramps <- function(cfg = cheap_config()) {
  sched_online <- load_eviction_treatment_schedule(cfg$schedule, "online_start_date") %>%
    rename(online_g = treat_start) %>% filter(!is.na(online_g))

  h <- read_csv(cfg$handle_csv, show_col_types = FALSE) %>%
    transmute(state_abb = eviction_state_name_to_abb(State),
              month_date = floor_date(as.Date(month_date), "month"),
              handle = as.numeric(Handle)) %>%
    filter(!is.na(state_abb), !is.na(handle), handle > 0) %>%
    inner_join(sched_online, by = "state_abb") %>%
    mutate(e = .month_idx(month_date) - .month_idx(online_g),
           covid_m = month_date >= cfg$covid_start & month_date <= cfg$covid_end)

  mature <- h %>%
    filter(!covid_m) %>%
    group_by(state_abb) %>%
    summarise(mature_handle = max(handle),
              peak_date = month_date[which.max(handle)], .groups = "drop")

  profiles <- h %>%
    inner_join(mature, by = "state_abb") %>%
    filter(e >= 0L) %>%
    group_by(state_abb) %>%
    # interpolate interior gaps on a complete 0..max(e) grid
    group_modify(function(d, k) {
      grid <- tibble(e = 0L:max(d$e))
      grid$expo <- approx(d$e, pmin(d$handle / d$mature_handle, 1),
                          xout = grid$e, rule = 2)$y
      grid
    }) %>%
    ungroup()

  n_e <- profiles %>% count(state_abb, name = "n_e")
  list(profiles = profiles,
       mature   = mature %>% left_join(n_e, by = "state_abb"))
}

#' Exposure lookup for a donor state, extended beyond the observed profile by
#' holding the donor's trailing-6-month mean exposure. e < 0 -> 0.
.expo_fun <- function(profiles, donor) {
  p <- profiles %>% filter(state_abb == donor) %>% arrange(e)
  tail_mean <- mean(tail(p$expo, 6))
  max_e <- max(p$e)
  function(evec) {
    out <- numeric(length(evec))
    inb <- !is.na(evec) & evec >= 0L & evec <= max_e
    out[inb] <- p$expo[match(evec[inb], p$e)]
    out[!is.na(evec) & evec > max_e] <- tail_mean
    out
  }
}

# ---- calendar-preserving placebo schedules ----------------------------------

#' Placebo assignment that keeps the REAL cohort calendar fixed.
#'
#' template: tibble(g = Date, n_states = int) -- the real online cohorts of
#' panel states with observed post-treatment data. Eligibility of a state for
#' date d (computed on the CENSORED sim panel, so "actually untreated at the
#' placebo date" holds by construction):
#'   - observes >= min_pre_obs months strictly before d (non-COVID),
#'   - observes >= min_post months at/after d,
#'   - observes at least one month in the 3 months before d (base period).
#' Cohorts are filled scarcest-first without replacement; unfillable cohorts
#' are DROPPED and recorded in attr "dropped_cohorts" (this mirrors the real
#' design's control scarcity for late cohorts -- report it, don't hide it).
make_calendar_placebo <- function(sim_panel, template, min_pre = 12L,
                                  min_post = 6L, seed) {
  stopifnot(!missing(seed))
  set.seed(seed)
  obs <- sim_panel %>% distinct(state_abb, month_date)
  states <- unique(obs$state_abb)

  elig <- lapply(seq_len(nrow(template)), function(k) {
    d  <- template$g[k]; di <- .month_idx(d)
    obs %>%
      mutate(mi = .month_idx(month_date)) %>%
      group_by(state_abb) %>%
      summarise(pre  = sum(mi <  di), post = sum(mi >= di),
                base = any(mi >= di - 3L & mi < di), .groups = "drop") %>%
      filter(pre >= min_pre, post >= min_post, base) %>%
      pull(state_abb)
  })

  ord <- order(vapply(elig, length, integer(1)), template$g)
  used <- character(0)
  rows <- list(); dropped <- list()
  for (k in ord) {
    pool <- setdiff(elig[[k]], used)
    need <- template$n_states[k]
    take <- min(need, length(pool))
    if (take < need) {
      dropped[[length(dropped) + 1L]] <-
        tibble(g = template$g[k], needed = need, filled = take)
    }
    if (take > 0L) {
      pick <- if (length(pool) == take) pool else sample(pool, take)
      rows[[length(rows) + 1L]] <- tibble(state_abb = pick,
                                          pseudo_g = template$g[k])
      used <- c(used, pick)
    }
  }
  out <- bind_rows(rows) %>% arrange(pseudo_g, state_abb)
  attr(out, "dropped_cohorts") <- if (length(dropped)) bind_rows(dropped) else
    tibble(g = as.Date(character(0)), needed = integer(0), filled = integer(0))
  attr(out, "seed") <- seed
  out
}

#' Real online cohort template from the audit table (treated_observed only).
placebo_template <- function(states_audit) {
  states_audit %>%
    filter(treated_observed) %>%
    count(online_g, name = "n_states") %>%
    rename(g = online_g) %>%
    arrange(g)
}

# ---- effect injection: observed-ramp DGP ------------------------------------

#' Impose delta_mature * exposure(e - lag) via count_nb augmentation/thinning.
#'
#' Same mechanism as R/power/impose_effects.R count_nb (NegBin var/mean =
#' theta), but the per-row delta comes from a donor state's OBSERVED exposure
#' profile instead of a parametric shape. Donors are drawn seeded, without
#' replacement while the donor pool lasts.
impose_exposure_effect <- function(panel, schedule, ramps, delta, lag = 0L,
                                   seed, theta = 1.4, outcome = "y_log1p") {
  set.seed(seed)
  sched <- schedule %>% distinct(state_abb, pseudo_g)
  donors_all <- unique(ramps$profiles$state_abb)
  n_ps <- nrow(sched)
  donors <- if (n_ps <= length(donors_all)) sample(donors_all, n_ps) else
    sample(donors_all, n_ps, replace = TRUE)
  sched$donor <- donors

  out <- panel %>% left_join(sched, by = "state_abb")
  out$e <- .ie_event_time(out$month_date, out$pseudo_g)

  di <- numeric(nrow(out))
  for (i in seq_len(nrow(sched))) {
    idx <- which(out$state_abb == sched$state_abb[i] & !is.na(out$e))
    if (!length(idx)) next
    f <- .expo_fun(ramps$profiles, sched$donor[i])
    di[idx] <- delta * f(out$e[idx] - lag)
  }
  out$delta_imposed <- di

  # count_nb injection (mirrors impose_effect(); delta>0 augments, <0 thins)
  fc <- as.numeric(panel$filings_count)
  mu <- .ie_baseline_mu(panel$unit_id, panel$month_date, fc)
  dY <- numeric(nrow(out))
  pos <- which(out$delta_imposed > 0 & is.finite(mu))
  neg <- which(out$delta_imposed < 0 & is.finite(fc) & fc > 0)
  if (length(pos)) {
    m <- mu[pos] * (exp(out$delta_imposed[pos]) - 1)
    dY[pos] <- stats::rnbinom(length(pos), size = m / (theta - 1), mu = m)
  }
  if (length(neg)) {
    dY[neg] <- -stats::rbinom(length(neg), size = as.integer(fc[neg]),
                              prob = 1 - exp(out$delta_imposed[neg]))
  }
  out$y_sim_count <- as.integer(pmax(round(fc + dY), 0))
  out$y_sim <- log1p(out$y_sim_count)
  attr(out, "delta") <- delta; attr(out, "lag") <- lag
  attr(out, "donor_map") <- sched
  out
}

# ---- CS fit + COVID cell decomposition --------------------------------------

#' One att_gt fit on an injected panel; returns the fit plus index->month map.
fit_cs <- function(sim_injected) {
  est <- .re_prep(sim_injected)
  months <- sort(unique(sim_injected$month_date))
  dat <- data.frame(id = est$id, t = est$t, g = est$g_int, y = est$y_sim,
                    state_abb = est$state_abb, stringsAsFactors = FALSE)
  a <- did::att_gt(
    yname = "y", tname = "t", idname = "id", gname = "g",
    xformla = ~1, data = dat, panel = TRUE,
    allow_unbalanced_panel = TRUE, faster_mode = FALSE,
    clustervars = "state_abb", est_method = "reg",
    base_period = "varying", anticipation = 0L,
    control_group = "notyettreated", bstrap = FALSE,
    biters = 199L, cband = FALSE, print_details = FALSE)
  list(fit = a, months = months, est = est)
}

#' Classify each post-treatment (g,t) cell by its identifying comparison:
#' base month = months[g-1], outcome month = months[t].
#'   clean_pre : outcome month before COVID start (base necessarily too)
#'   clean_post: base month after COVID end
#'   cross     : base before COVID start, outcome after COVID end
classify_cell <- function(base_month, cell_month, covid_start, covid_end) {
  case_when(
    cell_month <  covid_start ~ "clean_pre",
    base_month >  covid_end   ~ "clean_post",
    base_month <  covid_start & cell_month > covid_end ~ "cross",
    TRUE ~ "other"   # should not occur when COVID months are dropped
  )
}

#' Subset-aggregate ATT(g,t) cells with influence-function SEs.
#'
#' Weights: cohort unit-count per cell (did's "simple" weights with pg treated
#' as fixed -- exact at state level where cohort sizes are known constants; the
#' full-design aggregate is validated against did::aggte(type="simple") which
#' additionally carries the weight-estimation IF term).
#'
#' true_att per design = same weights applied to the mean imposed delta in each
#' cell (from sim_injected$delta_imposed), so bias/coverage target the design's
#' own estimand.
aggregate_covid_subsets <- function(cs, sim_injected, cfg,
                                    alpha = cfg$alpha) {
  a <- cs$fit; months <- cs$months
  n <- nrow(a$inffunc); df_cl <- n - 1L
  z <- qt(1 - alpha / 2, df = df_cl)

  cells <- tibble(k = seq_along(a$att), g = a$group, t = a$t, att = a$att) %>%
    filter(t >= g, is.finite(att), g >= 2L) %>%
    mutate(base_month = months[g - 1L], cell_month = months[t],
           class = classify_cell(base_month, cell_month,
                                 cfg$covid_start, cfg$covid_end))

  # cohort sizes + per-cell true imposed delta from the injected panel.
  # NOTE: a pseudo_g inside the dropped COVID window maps to the first
  # OBSERVED month at/after it (as in .re_prep), so truth is keyed on that
  # mapped index, not the raw pseudo date.
  gsizes <- cs$est %>% distinct(id, g_int) %>% filter(g_int > 0L) %>%
    count(g_int, name = "n_g")
  map_g_int <- function(pg) {
    vapply(pg, function(d) {
      w <- which(months >= d)
      if (length(w) == 0L) NA_integer_ else as.integer(w[1])
    }, integer(1))
  }
  truth <- sim_injected %>%
    filter(!is.na(pseudo_g)) %>%
    mutate(g_int = map_g_int(pseudo_g)) %>%
    group_by(g_int, month_date) %>%
    summarise(true_d = mean(delta_imposed), .groups = "drop")
  cells <- cells %>%
    left_join(gsizes, by = c("g" = "g_int")) %>%
    left_join(truth, by = c("g" = "g_int", "cell_month" = "month_date")) %>%
    mutate(n_g = coalesce(n_g, 1L), true_d = coalesce(true_d, 0))

  designs <- list(
    full        = c("clean_pre", "clean_post", "cross", "other"),
    covid_clean = c("clean_pre", "clean_post"),
    pre_covid   = "clean_pre",
    post_covid  = "clean_post",
    cross_covid = "cross"
  )

  IF <- as.matrix(a$inffunc)
  # Per-unit cohort vector in the same row order as the influence function
  # (did orders rows by id; id = 1..n from as.factor).
  G <- cs$est %>% distinct(id, g_int) %>% arrange(id) %>% pull(g_int)
  stopifnot(length(G) == n)

  out <- map_dfr(names(designs), function(dn) {
    cc <- cells %>% filter(class %in% designs[[dn]])
    if (nrow(cc) == 0L) {
      return(tibble(design = dn, att = NA_real_, se = NA_real_, p = NA_real_,
                    ci_lo = NA_real_, ci_hi = NA_real_, true_att = NA_real_,
                    n_cells = 0L, n_cohorts = 0L, n_treated_states = 0L))
    }
    # did's simple-aggregation weights and influence function, replicated for
    # an arbitrary cell subset: w_k = pg_k / sum(pg), pg_k = P(G = g_k), plus
    # the weight-estimation term wif (did::compute.aggte internals).
    pg  <- vapply(cc$g, function(g) mean(G == g), numeric(1))
    spg <- sum(pg)
    w   <- pg / spg
    att <- sum(w * cc$att)
    ind <- vapply(cc$g, function(g) as.numeric(G == g),
                  numeric(n))                    # n x K membership matrix
    if1 <- sweep(ind, 2, pg, "-") / spg
    if2 <- rowSums(sweep(ind, 2, pg, "-")) %*% t(pg / spg^2)
    if_agg <- IF[, cc$k, drop = FALSE] %*% w + (if1 - if2) %*% cc$att
    se <- sqrt(sum(if_agg^2)) / n
    tibble(design = dn, att = att, se = se,
           p = .re_tp(att, se, df_cl),
           ci_lo = att - z * se, ci_hi = att + z * se,
           true_att = sum(w * cc$true_d),
           n_cells = nrow(cc), n_cohorts = n_distinct(cc$g),
           n_treated_states = sum(cc %>% distinct(g, n_g) %>% pull(n_g)))
  })

  # did's own simple aggregate on the same fit (validation / headline arm)
  simple <- tryCatch(suppressWarnings(
    did::aggte(a, type = "simple", na.rm = TRUE)), error = function(e) NULL)
  if (!is.null(simple)) {
    att <- as.numeric(simple$overall.att); se <- as.numeric(simple$overall.se)
    tw <- out$true_att[out$design == "full"]
    out <- bind_rows(out, tibble(
      design = "full_didsimple", att = att, se = se,
      p = .re_tp(att, se, df_cl), ci_lo = att - z * se, ci_hi = att + z * se,
      true_att = tw, n_cells = sum(is.finite(a$att[a$t >= a$group])),
      n_cohorts = n_distinct(a$group), n_treated_states = NA_integer_))
  }
  out
}

# ---- single simulation ------------------------------------------------------

#' Run one replication of one DGP cell. Returns tidy rows (one per design).
#'
#' dgp: list(shape = "expo_ramp" | "step", delta, lag)
run_one_sim <- function(sim_panel, sched, ramps, dgp, seed, cfg) {
  t0 <- Sys.time()
  inj <- if (dgp$shape == "expo_ramp") {
    impose_exposure_effect(sim_panel, sched, ramps, delta = dgp$delta,
                           lag = dgp$lag, seed = seed, theta = cfg$theta_nb)
  } else {
    impose_effect(sim_panel, sched, mechanism = "count_nb", shape = "step",
                  delta = dgp$delta, params = list(theta = cfg$theta_nb),
                  outcome = "y_log1p", seed = seed)
  }
  cs <- tryCatch(suppressMessages(suppressWarnings(fit_cs(inj))),
                 error = function(e) e)
  rt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  if (inherits(cs, "condition")) {
    return(tibble(design = "full", att = NA_real_, se = NA_real_, p = NA_real_,
                  ci_lo = NA_real_, ci_hi = NA_real_, true_att = NA_real_,
                  n_cells = NA_integer_, n_cohorts = NA_integer_,
                  n_treated_states = NA_integer_,
                  shape = dgp$shape, delta = dgp$delta, lag = dgp$lag,
                  converged = FALSE, error_msg = conditionMessage(cs),
                  runtime_s = rt))
  }
  aggregate_covid_subsets(cs, inj, cfg) %>%
    mutate(shape = dgp$shape, delta = dgp$delta, lag = dgp$lag,
           converged = is.finite(att), error_msg = NA_character_,
           runtime_s = rt)
}
