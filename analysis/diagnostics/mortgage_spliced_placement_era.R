################################################################################
# mortgage_spliced_placement_era.R  (2026-09-29)
#
# Question: the spliced mortgage size gate
# (mortgage_lpdid_l618_pmd3_spliced_gate_v20260929) fails for LP-DiD wild
# (0.085, SE/SD 0.71). Is that the design, or a mixture of placement eras?
# Placements under anchor_rule random_feasible can land before COVID, after it,
# or straddle the dropped window, and the run does not record which.
#
# Method: regenerate every rep's pseudo-schedule with the runner's exact seed
# and arguments (run_scenario_grid.R, the make_pseudo_schedule() call), label
# each rep by where its pseudo-switchers' windows [g - pmd, g + hpost] sit
# relative to the dropped COVID months, and recompute size / SE/SD within era
# from the run's own results_raw. delta = 0 only: no treatment estimate exists.
#
# Run from the project root:
#   Rscript analysis/diagnostics/mortgage_spliced_placement_era.R
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
})
for (f in c("R/power/config.R", "R/power/blindness_checks.R",
            "R/power/inclusion_rule.R", "R/power/load_blinded_panel.R",
            "R/power/make_pseudo_schedules.R", "R/power/impose_effects.R",
            "R/power/run_estimators.R",
            "R/power/summarize_operating_characteristics.R",
            "R/power/run_scenario_grid.R")) source(f)

CONFIG  <- "config/power_mortgage_lpdid_l618_pmd3_spliced_gate_v20260929.yml"
RUN_DIR <- "output_blinded_power/mortgage_lpdid_l618_pmd3_spliced_gate_v20260929"
OUT_DIR <- "output/mortgage_spliced_placement_era"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

cfg  <- read_power_config(CONFIG)
grid <- expand_scenario_grid(cfg)
stopifnot(nrow(grid) == 1L)
sc <- as.list(grid[1, ])
sc$exclude_states  <- as.character(unlist(sc$exclude_states))
sc$template_states <- as.character(unlist(sc$template_states))
sc$excluded_months <- splice_excluded_months(cfg$covid_drop,
                                             sc$splice_buffer_months %||% 0L)

panel <- load_blinded_panel(
  level = sc$level, treat_def = sc$treat_def,
  anticipation = sc$loader_anticipation, sample = sc$sample,
  covid = sc$covid, quarterly = sc$quarterly,
  time_agg = sc$time_agg %||% "month",
  complete_periods_only = isTRUE(sc$complete_periods_only %||% FALSE),
  config = cfg
)
panel <- panel[!panel$state_abb %in% sc$exclude_states, , drop = FALSE]
real_schedule <- guarded_read_csv(cfg$schedule)

cov_lo <- as.Date(cfg$covid_drop[1]); cov_hi <- as.Date(cfg$covid_drop[2])
pmd    <- as.integer(sc$lpdid_pmd); hmin <- as.integer(sc$lpdid_hmin)
hpost  <- as.integer(sc$lpdid_post)

place_rep <- function(rep) {
  suppressWarnings(RNGkind("Mersenne-Twister", "Inversion", "Rejection"))
  seed_rep <- power_rep_seed(cfg$base_seed, rep, sc$scenario_seed_offset)
  s <- make_pseudo_schedule(
    design = sc$design, panel = panel, real_schedule = real_schedule,
    treat_def = sc$treat_def, min_pre = sc$min_pre, min_post = sc$min_post,
    seed = seed_rep, template = sc$template,
    eligibility = as.character(sc$eligibility), min_horizons = sc$min_horizons,
    pmd = pmd, excluded_months = sc$excluded_months,
    template_states = sc$template_states, hmin = hmin, hpost = hpost,
    anchor_rule = as.character(sc$anchor_rule)
  )
  g <- s$pseudo_g[!is.na(s$pseudo_g)]
  win_lo <- seq_along(g) |> vapply(function(i) as.numeric(seq(g[i], by = "-1 month", length.out = pmd + 1L)[pmd + 1L]), 0)
  win_hi <- seq_along(g) |> vapply(function(i) as.numeric(seq(g[i], by = "1 month", length.out = hpost + 1L)[hpost + 1L]), 0)
  n_pre  <- sum(win_hi < as.numeric(cov_lo))
  n_post <- sum(win_lo > as.numeric(cov_hi))
  tibble(rep = rep, seed_rep = seed_rep, n_sw = length(g),
         n_pre = n_pre, n_post = n_post, n_straddle = length(g) - n_pre - n_post,
         first_g = min(g), last_g = max(g),
         rescale = as.numeric(attr(s, "rescale_factor") %||% NA))
}

message("Regenerating 2,000 placements ...")
pl <- bind_rows(lapply(seq_len(sc$n_reps), place_rep)) %>%
  mutate(era = case_when(n_pre  == n_sw ~ "all_pre_covid",
                         n_post == n_sw ~ "all_post_covid",
                         n_straddle == 0 ~ "mixed_pre_and_post",
                         TRUE ~ "window_straddles_gap"))

res <- read_csv(file.path(RUN_DIR, "results_raw.csv.gz"), show_col_types = FALSE) %>%
  filter(delta == 0, converged)
chk <- res %>% distinct(rep, seed_rep) %>% inner_join(pl, by = "rep")
stopifnot(nrow(chk) == sc$n_reps, all(chk$seed_rep.x == chk$seed_rep.y))

by_era <- res %>% inner_join(select(pl, rep, era), by = "rep") %>%
  bind_rows(mutate(., era = "ALL")) %>%
  group_by(era, estimator, inference) %>%
  summarise(n_reps = n(), reject_005 = mean(p < 0.05),
            null_center = mean(att), sd_att = sd(att), mean_se = mean(se),
            se_sd_ratio = mean(se) / sd(att), .groups = "drop") %>%
  arrange(estimator, inference, era)

write_csv(pl, file.path(OUT_DIR, "placements_by_rep.csv"))
write_csv(by_era, file.path(OUT_DIR, "size_by_era.csv"))
print(count(pl, era))
print(as.data.frame(by_era), digits = 3)
