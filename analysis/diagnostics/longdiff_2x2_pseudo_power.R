#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# PSEUDO-TREATMENT POWER SIMULATION for the binary 2x2 long difference.
#
#   tau = (Ybar^T_end - Ybar^C_end) - (Ybar^T_pre - Ybar^C_pre)
#
# THE DESIGN MOVE (Black, Hollingsworth, Nunes & Simon 2022). Rather than
# truncating each state's panel at its own legalization date and clinging to
# the real 2024-25 endpoint — which leaves only ~6 blind-usable states and so
# can only describe a 6-state design — the WHOLE experiment is shifted into
# the pre-treatment era, exactly as BHNS move the ACA experiment from 2014-16
# back to a 2011 pseudo-treatment. No state in this window has legalized
# sports betting of any kind (first-ever legalization: 2018-06, DE/NJ), so
# every observation is untreated by construction and no per-state truncation
# is needed.
#
# WHAT IS PRESERVED. Real design: baseline CY2017-2018 (24 months) -> endpoint
# 2024-10..2025-09 (12 months), a 70-month baseline-end-to-endpoint-start
# distance, ~22 treated / 15 control states. Pseudo design: baseline CY2008-09
# (24 months) -> endpoint CY2016 (12 months), a 72-month distance, 22 treated /
# 15 control drawn at random from the 37 states observed in all three years.
# Counts, widths, and distance all hold. This requires the ANNUAL county court
# panel: the ETS monthly panel's untreated era is only 29 months long, so it
# cannot host a 70-month distance at any window width (that substrate instead
# runs the averaging-window exercise, and the era-noise bridge lives in
# analysis/diagnostics/longdiff_era_variance.R).
#
# ASSIGNMENT is random, preserving the real counts — that is what makes this a
# power simulation rather than a single placebo: every draw is a genuine
# realization under the sharp null, and the same draws serve as the
# randomization-inference reference distribution.
#
# INFERENCE. Randomization inference is primary (exact under the sharp null,
# free here, and immune to the MacKinnon-Webb fragility of cluster-robust
# inference at 37 unbalanced clusters). State CRVE and a Rademacher wild
# cluster bootstrap (WCR, null-imposed) are reported alongside; disagreement
# between them is itself a size finding.
#
# OUTPUTS, per Black et al.: size at delta = 0, the power curve, MDE-80, and —
# conditional on significance — the sign-error rate (Type S) and the
# exaggeration ratio (Type M).
#
# Usage:  Rscript analysis/diagnostics/longdiff_2x2_pseudo_power.R [n_reps]
# Output: output/longdiff_2x2_pseudo/{reps.csv, operating_characteristics.csv,
#         power_curve.png, design_summary.csv}
# ─────────────────────────────────────────────────────────────────────────────

suppressMessages({
  library(tidyverse); library(glue)
})
theme_set(theme_minimal())

set.seed(20260723)                     # framework base_seed, once, at the top

OUT_DIR <- "output/longdiff_2x2_pseudo"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

args   <- commandArgs(trailingOnly = TRUE)
N_REPS <- if (length(args) >= 1) as.integer(args[1]) else 500L
N_RI   <- 499L                          # randomization-inference permutations
N_WCB  <- 499L                          # wild cluster bootstrap draws
THETA  <- 1.4                           # var/mean for count_nb, matches framework
DELTAS <- c(0, 0.02, 0.05, 0.08, 0.10, 0.15, 0.20, 0.25, 0.30, 0.40)
ALPHA  <- 0.05

N_TREATED <- 22L
N_CONTROL <- 15L

ANNUAL_PATH <- "data/raw/county_court-issued_2000_2023_ben_update_5_12.csv"

# ── Designs: calendar x baseline width ───────────────────────────────────────
# `main` preserves the real geometry exactly (24-month baseline, 12-month
# endpoint, 72-month distance vs the real 70). `late` moves the baseline off
# the foreclosure crisis to test whether crisis-era dispersion drives the
# answer — endpoint 2016 rather than 2017 because a 2017 endpoint drops the
# design to 32 states and would break the 22/15 split, whereas 2016 keeps 42
# states and costs only 11 months of distance. `main_b12` halves the baseline
# (the Burlig-Preonas-Woerman question: does a 24-month baseline buy anything
# a 12-month baseline does not, given serial correlation?).
DESIGNS <- list(
  main     = list(base_years = c(2008L, 2009L), end_year = 2016L),
  main_b12 = list(base_years = 2009L,           end_year = 2016L),
  late     = list(base_years = c(2010L, 2011L), end_year = 2016L)
)

# ── Data ─────────────────────────────────────────────────────────────────────
source("utils/eviction_treatment_schedule.R")
sched_online <- load_eviction_treatment_schedule(
  "data/raw/sports_gambling_legalization_dates.csv", "online_start_date")
ever_online <- sched_online %>% filter(!is.na(treat_start)) %>% pull(state_abb)

# The compiled court file spells DC "District Of Columbia"; a case-sensitive
# join silently drops it, and DC is ever-online (2020-05), so the drop would
# quietly change the treated/control split.
xw <- tibble(state_abb = c(state.abb, "DC"),
             state_key = tolower(c(state.name, "district of columbia")))

annual_raw <- read_csv(ANNUAL_PATH, show_col_types = FALSE) %>%
  transmute(state_key = tolower(str_trim(state)),
            fips      = as.integer(fips_county),
            year      = as.integer(year),
            filings   = as.numeric(filings_observed),
            renting_hh = as.numeric(renting_hh)) %>%
  inner_join(xw, by = "state_key") %>%
  filter(!is.na(fips), !is.na(filings), filings >= 0) %>%
  # NEVADA: legal sports betting since 1949, so it is absent from the schedule
  # because there was no post-PASPA legalization event -- NOT because it never
  # adopted. Leaving it in makes an ALWAYS-TREATED state a never-treated
  # control. Dropped here rather than filtered downstream so that every state
  # set built below (treated, never, and all-states) is consistently free of it.
  # See docs/methodology/ADOPTION_UNIVERSE_AUDIT.md.
  filter(!state_abb %in% PRE_PASPA_SPORTS_BETTING)

#' Build one design's county-level baseline/endpoint table
build_design <- function(base_years, end_year) {
  need <- c(base_years, end_year)
  d <- annual_raw %>% filter(year %in% need)

  # A county must be observed in EVERY required year, else the long difference
  # is not defined for it and including it would change the sample by delta.
  complete <- d %>% count(fips) %>% filter(n == length(need)) %>% pull(fips)
  d <- d %>% filter(fips %in% complete)

  base <- d %>% filter(year %in% base_years) %>%
    group_by(state_abb, fips) %>%
    summarise(y_pre = mean(log1p(filings)),
              w     = mean(renting_hh, na.rm = TRUE), .groups = "drop")
  endp <- d %>% filter(year == end_year) %>%
    select(state_abb, fips, filings_end = filings)

  inner_join(base, endp, by = c("state_abb", "fips")) %>%
    # Renter weights are the pre-specified weight; counties missing them fall
    # back to equal weight rather than being dropped (dropping would make the
    # sample depend on a covariate).
    mutate(w = ifelse(is.finite(w) & w > 0, w, 1))
}

# ── Estimation machinery ─────────────────────────────────────────────────────
# With a constant and a single binary regressor, weighted OLS of dY on D is
# exactly the difference of weighted group means, so every permutation reduces
# to per-state sufficient statistics (Sw = sum(w*dY), W = sum(w)). That makes
# 499 RI draws essentially free.
tau_from_sets <- function(Sw, W, treat_idx) {
  st <- sum(Sw[treat_idx]) / sum(W[treat_idx])
  sc <- sum(Sw[-treat_idx]) / sum(W[-treat_idx])
  st - sc
}

#' State-clustered CRVE for the weighted 2x2, plus a null-imposed
#' Rademacher wild cluster bootstrap.
crve_and_wcb <- function(dY, w, D, state_idx, n_states, n_wcb) {
  X  <- cbind(1, D)
  sw <- sqrt(w)
  XtWX_inv <- tryCatch(solve(crossprod(X * sw)), error = function(e) NULL)
  if (is.null(XtWX_inv)) return(list(tau = NA_real_, se = NA_real_,
                                     p_crve = NA_real_, p_wcb = NA_real_))
  beta <- XtWX_inv %*% crossprod(X * sw, dY * sw)
  u    <- as.numeric(dY - X %*% beta)

  meat <- matrix(0, 2, 2)
  for (g in seq_len(n_states)) {
    idx <- which(state_idx == g)
    if (!length(idx)) next
    sc  <- crossprod(X[idx, , drop = FALSE] * w[idx], u[idx])
    meat <- meat + tcrossprod(sc)
  }
  # CR1 small-sample correction, the fixest/Stata default.
  cadj <- n_states / (n_states - 1) * (length(dY) - 1) / (length(dY) - 2)
  V    <- XtWX_inv %*% meat %*% XtWX_inv * cadj
  tau  <- beta[2]; se <- sqrt(V[2, 2])
  p_crve <- 2 * pt(-abs(tau / se), df = n_states - 1)

  # WCR: impose the null (drop D), resample cluster-level Rademacher weights.
  Xr    <- matrix(1, nrow = length(dY), ncol = 1)
  br    <- sum(w * dY) / sum(w)
  ur    <- as.numeric(dY - br)
  t_obs <- tau / se
  t_b   <- numeric(n_wcb)
  for (b in seq_len(n_wcb)) {
    v  <- sample(c(-1, 1), n_states, replace = TRUE)[state_idx]
    yb <- br + ur * v
    bb <- XtWX_inv %*% crossprod(X * sw, yb * sw)
    ub <- as.numeric(yb - X %*% bb)
    mb <- matrix(0, 2, 2)
    for (g in seq_len(n_states)) {
      idx <- which(state_idx == g)
      if (!length(idx)) next
      scb <- crossprod(X[idx, , drop = FALSE] * w[idx], ub[idx])
      mb  <- mb + tcrossprod(scb)
    }
    Vb <- XtWX_inv %*% mb %*% XtWX_inv * cadj
    t_b[b] <- bb[2] / sqrt(Vb[2, 2])
  }
  p_wcb <- (1 + sum(abs(t_b) >= abs(t_obs))) / (n_wcb + 1)

  list(tau = tau, se = se, p_crve = p_crve, p_wcb = p_wcb)
}

# ── Simulation ───────────────────────────────────────────────────────────────
run_design <- function(design_name, spec) {
  dsn <- build_design(spec$base_years, spec$end_year)
  states <- sort(unique(dsn$state_abb))
  n_states_all <- length(states)

  # Preserve the real 22/15 split when the calendar supports it; otherwise
  # scale both counts proportionally and record what was actually used, so a
  # thinner calendar degrades visibly instead of silently.
  n_tr <- N_TREATED; n_ct <- N_CONTROL
  if (n_states_all < N_TREATED + N_CONTROL) {
    n_tr <- max(2L, round(n_states_all * N_TREATED / (N_TREATED + N_CONTROL)))
    n_ct <- n_states_all - n_tr
    warning(glue("[{design_name}] only {n_states_all} states; split scaled to ",
                 "{n_tr}/{n_ct}"), call. = FALSE)
  }

  cat(glue("\n[{design_name}] baseline {paste(spec$base_years, collapse='+')} ",
           "-> endpoint {spec$end_year}: {n_states_all} states, ",
           "{nrow(dsn)} counties\n"))

  # Restrict to a fixed pool of exactly N_TREATED + N_CONTROL states so the
  # design size is the real one. When more states qualify, the pool is drawn
  # once (not per rep) so every rep faces the same design.
  pool <- if (n_states_all > n_tr + n_ct) {
    sort(sample(states, n_tr + n_ct))
  } else states
  dsn <- dsn %>% filter(state_abb %in% pool)
  pool <- sort(unique(dsn$state_abb))
  n_pool <- length(pool)

  state_idx <- match(dsn$state_abb, pool)
  w   <- dsn$w
  ypre <- dsn$y_pre
  fend <- dsn$filings_end
  n_c  <- nrow(dsn)

  out <- vector("list", N_REPS * length(DELTAS))
  k <- 0L
  for (rep in seq_len(N_REPS)) {
    treat_states <- sample.int(n_pool, n_tr)
    D <- as.numeric(state_idx %in% treat_states)

    for (delta in DELTAS) {
      # count_nb effect imposition, matching R/power/impose_effects.R: extra
      # filings drawn NegBin with mean mu*(exp(delta)-1) and var/mean = theta,
      # mu the county's own endpoint level.
      f_sim <- fend
      if (delta > 0) {
        pos <- which(D == 1 & is.finite(fend))
        m   <- fend[pos] * (exp(delta) - 1)
        add <- numeric(length(pos))
        ok  <- m > 0
        add[ok] <- rnbinom(sum(ok), size = m[ok] / (THETA - 1), mu = m[ok])
        f_sim[pos] <- fend[pos] + add
      }
      dY <- log1p(f_sim) - ypre

      # Realized truth on the analysis scale: the weighted mean shift actually
      # imposed on treated counties (attenuated below delta at small counts).
      truth <- if (delta > 0) {
        tr <- which(D == 1)
        sum(w[tr] * (log1p(f_sim[tr]) - log1p(fend[tr]))) / sum(w[tr])
      } else 0

      # Randomization inference on per-state sufficient statistics.
      agg <- tapply(w * dY, state_idx, sum)
      Sw  <- as.numeric(agg[as.character(seq_len(n_pool))])
      W   <- as.numeric(tapply(w, state_idx, sum)[as.character(seq_len(n_pool))])
      tau_obs <- tau_from_sets(Sw, W, treat_states)
      tau_ri  <- vapply(seq_len(N_RI), function(i)
        tau_from_sets(Sw, W, sample.int(n_pool, n_tr)), numeric(1))
      p_ri <- (1 + sum(abs(tau_ri) >= abs(tau_obs))) / (N_RI + 1)

      cw <- crve_and_wcb(dY, w, D, state_idx, n_pool, N_WCB)

      k <- k + 1L
      out[[k]] <- tibble(design = design_name, rep = rep, delta = delta,
                         truth = truth, tau = cw$tau, se = cw$se,
                         tau_ri_check = tau_obs,
                         p_ri = p_ri, p_crve = cw$p_crve, p_wcb = cw$p_wcb,
                         n_states = n_pool, n_treated = n_tr,
                         n_counties = n_c)
    }
    if (rep %% 50 == 0) cat(glue("  [{design_name}] rep {rep}/{N_REPS}\n"))
  }
  bind_rows(out)
}

reps <- imap_dfr(DESIGNS, ~ run_design(.y, .x))
write_csv(reps, file.path(OUT_DIR, "reps.csv"))

# ── Operating characteristics ────────────────────────────────────────────────
oc <- reps %>%
  pivot_longer(c(p_ri, p_crve, p_wcb), names_to = "inference",
               values_to = "p") %>%
  mutate(inference = recode(inference, p_ri = "RI", p_crve = "CRVE",
                            p_wcb = "WCB")) %>%
  group_by(design, inference, delta) %>%
  summarise(n_ok        = sum(is.finite(p)),
            reject      = mean(p < ALPHA, na.rm = TRUE),
            truth_mean  = mean(truth),
            bias        = mean(tau - truth, na.rm = TRUE),
            sd_tau      = sd(tau, na.rm = TRUE),
            se_mean     = mean(se, na.rm = TRUE),
            se_over_sd  = mean(se, na.rm = TRUE) / sd(tau, na.rm = TRUE),
            # Black et al. Type S / Type M, conditional on significance.
            sign_error  = {
              sig <- which(is.finite(p) & p < ALPHA)
              if (!length(sig) || mean(truth) == 0) NA_real_
              else mean(sign(tau[sig]) != sign(mean(truth)))
            },
            exaggeration = {
              sig <- which(is.finite(p) & p < ALPHA)
              if (!length(sig) || mean(truth) == 0) NA_real_
              else mean(abs(tau[sig])) / abs(mean(truth))
            },
            .groups = "drop")

# MDE-80: first delta where power crosses 0.80, linearly interpolated.
mde <- oc %>%
  group_by(design, inference) %>%
  arrange(delta, .by_group = TRUE) %>%
  summarise(size = reject[delta == 0][1],
            mde80 = {
              d <- delta; r <- reject
              hit <- which(r >= 0.80)
              if (!length(hit) || hit[1] == 1) NA_real_
              else {
                i <- hit[1]
                d[i - 1] + (0.80 - r[i - 1]) * (d[i] - d[i - 1]) /
                  (r[i] - r[i - 1])
              }
            }, .groups = "drop") %>%
  mutate(size_valid = size <= 0.075,
         mde80_pct  = 100 * (exp(mde80) - 1))

write_csv(oc,  file.path(OUT_DIR, "operating_characteristics.csv"))
write_csv(mde, file.path(OUT_DIR, "mde_summary.csv"))

p <- oc %>%
  ggplot(aes(delta, reject, colour = inference)) +
  geom_hline(yintercept = ALPHA, linetype = "dotted") +
  geom_hline(yintercept = 0.80, linetype = "dashed") +
  geom_line() + geom_point(size = 1) +
  facet_wrap(~design) +
  scale_y_continuous(limits = c(0, 1)) +
  labs(x = "imposed effect (log points)", y = "rejection rate",
       colour = "inference",
       subtitle = glue("Pseudo-treatment 2x2 long difference, {N_REPS} reps; ",
                       "dotted = 5% size, dashed = 80% power"))
ggsave(file.path(OUT_DIR, "power_curve.png"), p, width = 10, height = 4.2,
       dpi = 200)

cat("\n===== SIZE and MDE-80 =====\n")
print(as.data.frame(mde), digits = 3)
cat("\n===== OPERATING CHARACTERISTICS (main design) =====\n")
print(as.data.frame(oc %>% filter(design == "main") %>%
                      select(inference, delta, reject, truth_mean, bias,
                             se_over_sd, sign_error, exaggeration)), digits = 3)
