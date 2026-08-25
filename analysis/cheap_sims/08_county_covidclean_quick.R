#!/usr/bin/env Rscript
################################################################################
# analysis/cheap_sims/08_county_covidclean_quick.R
#
# QUICK TRIAGE (deadline run): power of the COVID-clean POST-gap county design —
# the split-sample implementation of the regime-FE spec (panel restricted to
# months after the COVID window, so no cross-gap imputation is possible by
# construction; the did2s global two-way model critique does not bite).
#
# Design: county panel (blinded S2, covid="post" => months > 2021-07),
# calendar-preserving placebo over the REAL post-COVID online cohorts,
# observed-ramp effect injection (count_nb), did2s (headline) + TWFE analytic
# (reference), state-clustered inference.
#
# Known cheap-run compromises (document, don't hide):
#   - ME excluded (county loader legacy exclusion) => one late cohort fewer.
#   - min_pre relaxed to 6 post-gap months: cohorts dated before ~2022-02
#     cannot have 12 post-gap pre-months for ANY host — the real split-sample
#     design faces the same constraint, so early-post cohorts (AZ/CT) drop.
#   - true effect approximated by the treated-cell mean imposed delta.
#   - TWFE wild bootstrap skipped (boottest aborts under fork); analytic only.
#
# Env: N_QC_REPS (80), N_CORES, QC_ARM ("post" | "pre").
# Run from repo root:  Rscript analysis/cheap_sims/08_county_covidclean_quick.R
################################################################################

source("analysis/cheap_sims/00_common.R")
suppressPackageStartupMessages({library(parallel); library(fixest)})

# fixest/data.table OpenMP threading aborts irrecoverably inside forked
# mclapply workers on the county panel ("R is aborting now", 2026-08-13);
# pin both to a single thread before any fork.
fixest::setFixest_nthreads(1)
try(data.table::setDTthreads(1L), silent = TRUE)

cfg  <- cheap_config()
ARM  <- .cs_envchr("QC_ARM", "post")
REPS <- .cs_envint("N_QC_REPS", 80L)
N_CORES <- .cs_envint("N_CORES", max(1L, parallel::detectCores() - 2L))
SCENARIO <- if (ARM == "post") 905L else 906L
MIN_PRE_QC <- .cs_envint("QC_MIN_PRE", 6L)

out_dir <- file.path(cfg$out_dir, "county_covidclean")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
RAW <- file.path(out_dir, sprintf("raw_%s.csv", ARM))

pcfg <- read_power_config("config/power_smoke.yml")
panel <- load_blinded_panel(level = "county", treat_def = "online_start_date",
                            anticipation = 6L, sample = "S2", covid = ARM,
                            config = pcfg)
covid_end <- pcfg$covid_drop[2]; covid_start <- pcfg$covid_drop[1]
cat(sprintf("county %s-COVID panel: %d rows, %d counties, %d states, months %s..%s\n",
            ARM, nrow(panel), n_distinct(panel$unit_id),
            n_distinct(panel$state_abb),
            format(min(panel$month_date)), format(max(panel$month_date))))

# Real cohort template for this regime: online dates inside the regime window,
# states present in the county panel, singleton slots.
sched_online <- load_eviction_treatment_schedule(pcfg$schedule, "online_start_date") %>%
  filter(!is.na(treat_start), state_abb %in% unique(panel$state_abb))
tmpl <- sched_online %>%
  filter(if (ARM == "post") treat_start > covid_end else treat_start < covid_start) %>%
  count(treat_start, name = "n_states") %>% rename(g = treat_start)
cat(sprintf("template: %d cohorts (%s..%s), %d slots\n", nrow(tmpl),
            format(min(tmpl$g)), format(max(tmpl$g)), sum(tmpl$n_states)))

ramps <- build_exposure_ramps(cfg)

probe <- make_calendar_placebo(panel, tmpl, MIN_PRE_QC, cfg$min_post,
                               seed = cfg$base_seed)
cat(sprintf("placebo probe: %d/%d slots filled; dropped: %s\n",
            nrow(probe), sum(tmpl$n_states),
            paste(format(attr(probe, "dropped_cohorts")$g), collapse = " ")))

DELTAS <- c(0, 0.01, 0.025, 0.05)

one_rep <- function(rep) {
  seed_rep <- cfg$base_seed + 10007L * rep + 101L * SCENARIO
  sched <- make_calendar_placebo(panel, tmpl, MIN_PRE_QC, cfg$min_post,
                                 seed = seed_rep)
  map_dfr(seq_along(DELTAS), function(j) {
    d <- DELTAS[j]
    inj <- impose_exposure_effect(panel, sched, ramps, delta = d, lag = 0L,
                                  seed = seed_rep + 7L * j, theta = cfg$theta_nb)
    true_d <- mean(inj$delta_imposed[!is.na(inj$e) & inj$e >= 0L])
    n_cl <- n_distinct(inj$state_abb); df_cl <- n_cl - 1L

    # did2s (headline)
    t0 <- Sys.time()
    r2 <- run_estimator(inj, estimator = "did2s")
    rt2 <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

    # TWFE analytic (reference; wild bootstrap skipped — boottest aborts
    # under forked workers)
    est <- .re_prep(inj)
    tw <- tryCatch({
      f <- feols(y_sim ~ post | id + t, data = as.data.frame(est),
                 cluster = ~state_abb, warn = FALSE, notes = FALSE)
      cf <- as.numeric(coef(f)["post"]); se <- as.numeric(fixest::se(f)["post"])
      tibble(estimator = "twfe", att = cf, se = se,
             p = .re_tp(cf, se, df_cl), converged = is.finite(cf * se))
    }, error = function(e) tibble(estimator = "twfe", att = NA_real_,
                                  se = NA_real_, p = NA_real_, converged = FALSE))

    bind_rows(
      r2 %>% filter(estimand == "simple") %>%
        select(estimator, att, se, p, converged),
      tw
    ) %>%
      mutate(rep = rep, delta = d, true_att = true_d,
             n_placebo = nrow(sched), runtime_s = rt2)
  })
}

done <- if (file.exists(RAW))
  unique(suppressMessages(read_csv(RAW, show_col_types = FALSE))$rep) else integer(0)
todo <- setdiff(seq_len(REPS), done)
t0 <- Sys.time()
batches <- split(todo, ceiling(seq_along(todo) / (2L * N_CORES)))
for (bi in seq_along(batches)) {
  b <- batches[[bi]]
  res <- mclapply(b, function(r) tryCatch(one_rep(r), error = function(e)
    tibble(rep = r, estimator = NA_character_, converged = FALSE,
           delta = NA_real_)), mc.cores = N_CORES, mc.preschedule = FALSE)
  res <- bind_rows(res[vapply(res, is.data.frame, logical(1))])
  write_csv(res, RAW, append = file.exists(RAW))
  cat(sprintf("[batch %d/%d] %.1f min\n", bi, length(batches),
              as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}

# ---- summary ----------------------------------------------------------------

all <- suppressMessages(read_csv(RAW, show_col_types = FALSE)) %>%
  filter(!is.na(estimator), converged)
summ <- all %>%
  group_by(estimator, delta) %>%
  summarise(n = n(), reject_05 = mean(p < .05, na.rm = TRUE),
            mean_att = mean(att), sd_att = sd(att), mean_true = mean(true_att),
            mean_se = mean(se), se_over_sd = mean(se) / sd(att),
            .groups = "drop") %>% arrange(estimator, delta)
write_csv(summ, file.path(out_dir, sprintf("summary_%s.csv", ARM)))

cat(sprintf("\n===== COVID-CLEAN COUNTY (%s regime) — did2s + TWFE =====\n", ARM))
print(as.data.frame(summ), row.names = FALSE, digits = 3)

orc <- summ %>% filter(delta == 0) %>%
  transmute(estimator, sd0 = sd_att,
            oracle_mde_att = 2.8 * sd_att)
dose <- summ %>% filter(delta == max(DELTAS)) %>%
  transmute(estimator, dose_ratio = mean_true / max(DELTAS))
orc <- orc %>% left_join(dose, by = "estimator") %>%
  mutate(oracle_mde_mature = oracle_mde_att / dose_ratio)
cat("\nOracle MDE (from null SD; mature scale via ramp dose):\n")
print(as.data.frame(orc), row.names = FALSE, digits = 3)
cat(sprintf("\nTotal %.1f min\n",
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))
