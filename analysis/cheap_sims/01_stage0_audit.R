#!/usr/bin/env Rscript
################################################################################
# analysis/cheap_sims/01_stage0_audit.R
#
# STAGE 0: audit and dry run. Rebuilds the treatment schedule from the repaired
# CSV, produces the state coverage / event-horizon / cohort tables, verifies
# the gambling exposure ramps, probes calendar-preserving placebo feasibility,
# and caches the design objects for the Monte Carlo stages.
#
# Run from repo root:  Rscript analysis/cheap_sims/01_stage0_audit.R
################################################################################

source("analysis/cheap_sims/00_common.R")
theme_set(theme_minimal())

cfg <- cheap_config()
dir.create(cfg$out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(cfg$out_dir, "figures"), showWarnings = FALSE)

cat("=== STAGE 0: design audit ===\n")
cat(sprintf("COVID window dropped: %s .. %s | anticipation censor: %d mo\n",
            cfg$covid_start, cfg$covid_end, cfg$anticipation))

pan   <- build_sim_state_panel(cfg)
ramps <- build_exposure_ramps(cfg)

saveRDS(pan,   file.path(cfg$out_dir, "design_panel.rds"))
saveRDS(ramps, file.path(cfg$out_dir, "exposure_ramps.rds"))

# ---- 1-2. state table -------------------------------------------------------

st <- pan$states %>%
  mutate(
    era = case_when(
      !treated_observed & !is.na(online_g) ~ "treated_no_post_data",
      is.na(online_g)                      ~ "never_treated",
      contributes_precovid                 ~ "pre_covid_adopter",
      contributes_crosscovid               ~ "covid_window_adopter",
      contributes_postcovid                ~ "post_covid_adopter"
    )
  ) %>%
  arrange(online_g, state_abb)

write_csv(st, file.path(cfg$out_dir, "stage0_state_table.csv"))

cat("\n--- State audit table ---\n")
print(as.data.frame(st %>% select(state_abb, online_g, first_obs, last_obs,
                                  n_pre_online, n_post_online, era)),
      row.names = FALSE)

cat("\n--- Era counts ---\n")
print(st %>% count(era), n = 20)

# hard gates ------------------------------------------------------------------
stopifnot(!"NV" %in% st$state_abb)
bad_np <- st %>% filter(era == "treated_no_post_data")
cat(sprintf("\nTreated states with NO observed post-online outcomes (coded untreated/not-yet in-sample): %s\n",
            paste(bad_np$state_abb, collapse = ", ")))

# ---- 3. contributing treated states by event horizon ------------------------

horizons <- c(0L, 3L, 6L, 12L, 18L, 24L, 36L)
support <- map_dfr(horizons, function(h) {
  pan$design %>%
    filter(treated_m, !covid_m, event_m >= h) %>%
    distinct(state_abb) %>%
    summarise(event_horizon = h, n_treated_states = n())
}) %>%
  left_join(
    map_dfr(horizons, function(h) {
      pan$design %>%
        filter(treated_m, !covid_m, event_m == h) %>%
        summarise(event_horizon = h, n_states_at_exact_h = n())
    }), by = "event_horizon")
write_csv(support, file.path(cfg$out_dir, "stage0_event_horizon_support.csv"))
cat("\n--- Treated states contributing at/after each event horizon (non-COVID months) ---\n")
print(as.data.frame(support), row.names = FALSE)

# ---- 4. cohort structure ----------------------------------------------------

coh <- st %>% filter(treated_observed) %>% count(online_g, name = "n_states")
cat(sprintf("\nCohorts (treated_observed): %d | singleton cohorts: %d | treated states: %d\n",
            nrow(coh), sum(coh$n_states == 1L), sum(coh$n_states)))
write_csv(coh, file.path(cfg$out_dir, "stage0_cohorts.csv"))

# ---- 5. gambling ramp verification ------------------------------------------

mt <- ramps$mature %>% arrange(desc(mature_handle))
cat(sprintf("\nExposure ramps: %d states with online date + handle data\n", nrow(mt)))
write_csv(ramps$profiles, file.path(cfg$out_dir, "stage0_exposure_profiles.csv"))
write_csv(mt, file.path(cfg$out_dir, "stage0_mature_handle.csv"))

pool <- ramps$profiles %>%
  group_by(e) %>%
  summarise(median_expo = median(expo), q25 = quantile(expo, .25),
            q75 = quantile(expo, .75), n = n(), .groups = "drop") %>%
  filter(n >= 5)

rep_states <- c("NY", "OH", "TN", "AR", "MI", "CO")
p1 <- ramps$profiles %>%
  filter(state_abb %in% rep_states) %>%
  ggplot(aes(e, expo)) +
  geom_line(color = "grey40") +
  geom_line(data = pool %>% rename(expo = median_expo) %>%
              crossing(state_abb = rep_states),
            aes(e, expo), color = "firebrick", linetype = "dashed") +
  facet_wrap(~state_abb) +
  labs(x = "Months since online legalization",
       y = "Exposure (handle / non-COVID peak)")
ggsave(file.path(cfg$out_dir, "figures", "stage0_ramp_representative.pdf"),
       p1, width = 8, height = 5)

p2 <- ggplot(pool, aes(e, median_expo)) +
  geom_ribbon(aes(ymin = q25, ymax = q75), alpha = .15) +
  geom_line() +
  labs(x = "Months since online legalization",
       y = "Exposure (pooled median, IQR band)")
ggsave(file.path(cfg$out_dir, "figures", "stage0_ramp_pooled.pdf"),
       p2, width = 7, height = 4.5)

cat("\nPooled exposure at e = 0/6/12/24:",
    sprintf("%.2f", pool$median_expo[match(c(0, 6, 12, 24), pool$e)]), "\n")

# ---- 6. placebo feasibility probe -------------------------------------------

tmpl <- placebo_template(pan$states)
cat(sprintf("\nPlacebo template: %d cohorts, %d state slots, dates %s .. %s\n",
            nrow(tmpl), sum(tmpl$n_states), min(tmpl$g), max(tmpl$g)))

probe <- map_dfr(1:20, function(s) {
  sc <- make_calendar_placebo(pan$sim, tmpl, cfg$min_pre, cfg$min_post,
                              seed = cfg$base_seed + s)
  dr <- attr(sc, "dropped_cohorts")
  tibble(seed = s, n_assigned = nrow(sc),
         n_cohorts_assigned = n_distinct(sc$pseudo_g),
         n_dropped_slots = sum(dr$needed - dr$filled))
})
cat("\n--- Placebo feasibility over 20 seeds ---\n")
print(probe %>% summarise(across(-seed, list(mean = mean, min = min, max = max))),
      width = Inf)
write_csv(probe, file.path(cfg$out_dir, "stage0_placebo_feasibility.csv"))

sc1 <- make_calendar_placebo(pan$sim, tmpl, cfg$min_pre, cfg$min_post,
                             seed = cfg$base_seed + 1L)
cat("\nExample placebo draw (seed 1):\n")
print(as.data.frame(sc1), row.names = FALSE)
cat("Dropped cohorts (seed 1):\n")
print(as.data.frame(attr(sc1, "dropped_cohorts")), row.names = FALSE)

# ---- 7. single-fit dry run + timing -----------------------------------------

cat("\n--- Dry run: one null fit + decomposition ---\n")
t0 <- Sys.time()
r0 <- run_one_sim(pan$sim, sc1, ramps,
                  dgp = list(shape = "expo_ramp", delta = 0, lag = 0L),
                  seed = cfg$base_seed + 1L, cfg = cfg)
cat(sprintf("runtime: %.1f s\n", as.numeric(difftime(Sys.time(), t0, "secs"))))
print(as.data.frame(r0 %>% select(design, att, se, p, true_att, n_cells,
                                  n_cohorts, converged)), row.names = FALSE)

# validation: IF-aggregation vs did's own simple aggregate
v <- r0 %>% filter(design %in% c("full", "full_didsimple"))
if (nrow(v) == 2L) {
  cat(sprintf("validation full vs did-simple: att diff = %.2e, se ratio = %.3f\n",
              diff(v$att), v$se[2] / v$se[1]))
}

cat("\nStage 0 complete. Outputs in", cfg$out_dir, "\n")
