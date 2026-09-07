# Parity harness, step 1: build simulated panels exactly as the blinded
# framework does for the headline config, run the framework's .re_lpdid,
# and export the same panels as real-data-shaped CSVs for the repo script.
# Run from the repo root.
suppressPackageStartupMessages({library(tidyverse); library(lubridate)})
source("R/power/config.R"); source("R/power/blindness_checks.R")
source("R/power/load_blinded_panel.R"); source("R/power/make_pseudo_schedules.R")
source("R/power/impose_effects.R"); source("R/power/run_estimators.R")
SCR <- Sys.getenv("SCR")
cfg <- read_power_config("config/power_lpdid_shift12_clean_mde_ewatt_pmd6.yml")
panel <- load_blinded_panel(level = "state", treat_def = "shift12_start_date",
                            anticipation = 6L, sample = "S2", covid = "drop",
                            config = cfg)
panel <- panel[!panel$state_abb %in% c("NV","ID","HI","MS"), , drop = FALSE]
real_schedule <- guarded_read_csv(cfg$schedule)
spec <- list(lpdid_wild = TRUE, lpdid_anchor = "event_clean", lpdid_hmin = 0L,
             lpdid_post = 12L, lpdid_pmd = 6L, lpdid_weights = "ewatt",
             anticipation = 0L, control_group = "notyettreated", outcome = "y_log1p")
abb2name <- setNames(c(state.name, "District of Columbia"), c(state.abb, "DC"))
out <- list()
for (seed in c(101L, 202L, 303L)) {
  sched <- make_pseudo_schedule("D1", panel = panel, real_schedule = real_schedule,
                                treat_def = "shift12_start_date", min_pre = 12L,
                                min_post = 6L, seed = seed, template = "panel")
  # run_scenario_grid attaches pseudo_launch = pseudo_g - cohort lag; under
  # shift12 every lag is 12 months (verified: shift12 == online + 12 for all).
  sched$pseudo_launch <- as.Date(sched$pseudo_g) %m-% months(12L)
  for (delta in c(0, 0.10)) {
    sim <- impose_effect(panel, sched, mechanism = "count_nb", shape = "step",
                         delta = delta, params = list(), outcome = "y_log1p",
                         seed = seed + 1L)
    res <- run_estimator(sim, "lpdid", spec = spec) %>%
      mutate(seed = seed, delta = delta, .before = 1)
    out[[length(out) + 1L]] <- res
    tag <- sprintf("s%d_d%03d", seed, round(delta * 100))
    d <- file.path(SCR, tag, "data", "raw"); dir.create(d, recursive = TRUE, showWarnings = FALSE)
    dir.create(file.path(SCR, tag, "data", "processed"), showWarnings = FALSE)
    sim %>% transmute(state_abb, month_date, filings_count = y_sim_count,
                      renter_occupied_housing_units = renters) %>%
      write_csv(file.path(d, "state_month_panel_with_treatment.csv"))
    sched %>% filter(!is.na(pseudo_launch)) %>%
      transmute(state = unname(abb2name[state_abb]),
                first_start_date = as.Date(pseudo_launch),
                online_start_date = as.Date(pseudo_launch),
                retail_start_date = as.Date(pseudo_launch)) %>%
      write_csv(file.path(d, "sports_gambling_legalization_dates.csv"))
    stopifnot(all.equal(sim$y_sim, log1p(sim$y_sim_count)))
  }
  cat(sprintf("seed %d: %d pseudo-switchers, %d states in panel\n", seed,
              sum(!is.na(sched$pseudo_g)), n_distinct(panel$state_abb)))
}
fw <- bind_rows(out) %>% select(seed, delta, inference, att, se, p, ci_lo, ci_hi,
                                n_treated_clusters, n_control_clusters, converged, error_msg)
print(as.data.frame(fw))
write_csv(fw, file.path(SCR, "framework_results.csv"))
