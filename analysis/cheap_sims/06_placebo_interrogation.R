#!/usr/bin/env Rscript
################################################################################
# analysis/cheap_sims/06_placebo_interrogation.R
#
# Interrogate the placebo generator behind the cross-COVID "+0.67" placebo mean.
# Question: is it a genuine placebo failure (nonparallel COVID-era dynamics), or
# a mechanical artifact of coverage-driven eligibility sorting particular kinds
# of states into particular pseudo-treatment dates?
#
#   (1) Null placebo-ATT distributions by treatment-calendar class (full table).
#   (2) Eligibility matrix: which states are eligible for each placebo cohort,
#       and what TYPE of state (never-treated vs real-treated-censored) they are.
#   (3) Empirical assignment probabilities over the 250 logged schedules vs the
#       "equal probability among eligible" benchmark.
#   (4) Untreated trajectory check: post-COVID minus pre-COVID mean outcome by
#       host type -- do the states that CAN host cross-COVID pseudo cohorts
#       trend differently from never-treated states?
#   (5) Balanced common-support null: only full-coverage never-treated states
#       (eligibility identical by construction => exchangeable assignment),
#       scaled 4-cohort template, N_BAL_REPS null fits.
#
# Env: N_BAL_REPS (250), N_CORES. Run from repo root.
################################################################################

source("analysis/cheap_sims/00_common.R")
suppressPackageStartupMessages(library(parallel))
theme_set(theme_minimal())

cfg <- cheap_config()
N_BAL_REPS <- .cs_envint("N_BAL_REPS", 250L)
N_CORES    <- .cs_envint("N_CORES", max(1L, parallel::detectCores() - 2L))
out_dir <- file.path(cfg$out_dir, "placebo_interrogation")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

pan  <- readRDS(file.path(cfg$out_dir, "design_panel.rds"))
tmpl <- placebo_template(pan$states)

state_type <- pan$states %>%
  transmute(state_abb,
            type = case_when(
              is.na(g_first) ~ "never_treated",
              censor_month > cfg$covid_end ~ "real_treated_late_censor",
              TRUE ~ "real_treated_early_censor"),
            censor_month, first_obs, last_obs)

# ---- (1) null placebo-ATT distributions by class ---------------------------

raw <- read_csv(file.path(cfg$out_dir, "results_raw.csv"),
                show_col_types = FALSE) %>%
  filter(!is.na(design), converged, design != "full_didsimple",
         shape == "expo_ramp", lag == 0, delta == 0)

dist_tab <- raw %>%
  group_by(design) %>%
  summarise(n = n(), mean = mean(att), sd = sd(att),
            q05 = quantile(att, .05), q25 = quantile(att, .25),
            q50 = median(att), q75 = quantile(att, .75),
            q95 = quantile(att, .95),
            skew = mean(((att - mean(att)) / sd(att))^3),
            share_pos = mean(att > 0),
            mc_se_of_mean = sd(att) / sqrt(n()), .groups = "drop")
write_csv(dist_tab, file.path(out_dir, "null_att_distribution_by_class.csv"))
cat("===== (1) Null placebo-ATT distributions by calendar class =====\n")
print(as.data.frame(dist_tab), row.names = FALSE, digits = 3)

# ---- (2) eligibility matrix -------------------------------------------------

obs <- pan$sim %>% distinct(state_abb, month_date) %>%
  mutate(mi = .month_idx(month_date))
elig_long <- map_dfr(seq_len(nrow(tmpl)), function(k) {
  d <- tmpl$g[k]; di <- .month_idx(d)
  obs %>%
    group_by(state_abb) %>%
    summarise(pre = sum(mi < di), post = sum(mi >= di),
              base = any(mi >= di - 3L & mi < di), .groups = "drop") %>%
    mutate(cohort_g = d, n_slots = tmpl$n_states[k],
           eligible = pre >= cfg$min_pre & post >= cfg$min_post & base)
}) %>%
  left_join(state_type %>% select(state_abb, type), by = "state_abb")

elig_mat <- elig_long %>%
  filter(eligible) %>%
  select(state_abb, cohort_g) %>%
  mutate(x = 1L) %>%
  pivot_wider(names_from = cohort_g, values_from = x, values_fill = 0L) %>%
  arrange(state_abb)
write_csv(elig_mat, file.path(out_dir, "eligibility_matrix.csv"))

elig_by_cohort <- elig_long %>%
  filter(eligible) %>%
  count(cohort_g, n_slots, type) %>%
  pivot_wider(names_from = type, values_from = n, values_fill = 0L)
write_csv(elig_by_cohort, file.path(out_dir, "eligibility_by_cohort.csv"))
cat("\n===== (2) Eligible states per placebo cohort, by state type =====\n")
print(as.data.frame(elig_by_cohort), row.names = FALSE)

# ---- (3) empirical assignment probabilities vs equal-among-eligible ---------

schedlog <- read_csv(file.path(cfg$out_dir, "placebo_schedules_log.csv"),
                     show_col_types = FALSE)
n_reps_log <- n_distinct(schedlog$rep)

assign_p <- schedlog %>%
  count(state_abb, pseudo_g, name = "n_assigned") %>%
  mutate(p_assigned = n_assigned / n_reps_log) %>%
  full_join(elig_long %>% filter(eligible) %>%
              transmute(state_abb, pseudo_g = cohort_g, n_slots),
            by = c("state_abb", "pseudo_g")) %>%
  mutate(n_assigned = coalesce(n_assigned, 0L),
         p_assigned = coalesce(p_assigned, 0)) %>%
  group_by(pseudo_g) %>%
  mutate(n_eligible = n(),
         p_equal = first(n_slots) / n_eligible,     # equal-prob benchmark
         ratio_vs_equal = p_assigned / p_equal) %>%
  ungroup() %>%
  left_join(state_type %>% select(state_abb, type), by = "state_abb")
write_csv(assign_p, file.path(out_dir, "assignment_probabilities.csv"))

cat("\n===== (3) Assignment probability vs equal-among-eligible =====\n")
cat("Cohort-level dispersion of P(state assigned)/P(equal) among eligible states:\n")
disp <- assign_p %>%
  group_by(pseudo_g, n_eligible) %>%
  summarise(min_ratio = min(ratio_vs_equal), max_ratio = max(ratio_vs_equal),
            sd_ratio = sd(ratio_vs_equal), .groups = "drop")
print(as.data.frame(disp), row.names = FALSE, digits = 2)

cat("\nWho hosts PRE-COVID pseudo dates (the only cross-COVID-capable cohorts)?\n")
host_comp <- schedlog %>%
  mutate(era = case_when(pseudo_g < cfg$covid_start ~ "pre_covid_date",
                         pseudo_g > cfg$covid_end   ~ "post_covid_date",
                         TRUE ~ "covid_window_date")) %>%
  left_join(state_type %>% select(state_abb, type, last_obs), by = "state_abb") %>%
  mutate(has_postgap_data = last_obs > cfg$covid_end) %>%
  count(era, type, has_postgap_data) %>%
  group_by(era) %>% mutate(share = n / sum(n)) %>% ungroup()
write_csv(host_comp, file.path(out_dir, "host_composition_by_era.csv"))
print(as.data.frame(host_comp), row.names = FALSE, digits = 3)

# ---- (4) untreated trajectory check by host type ---------------------------

traj <- pan$sim %>%
  mutate(period = case_when(month_date < cfg$covid_start ~ "pre",
                            month_date > cfg$covid_end   ~ "post",
                            TRUE ~ NA_character_)) %>%
  filter(!is.na(period)) %>%
  group_by(state_abb, period) %>%
  summarise(mean_y = mean(y_log1p), n = n(), .groups = "drop") %>%
  pivot_wider(names_from = period, values_from = c(mean_y, n)) %>%
  filter(!is.na(mean_y_pre), !is.na(mean_y_post), n_post >= 6) %>%
  mutate(d_post_pre = mean_y_post - mean_y_pre) %>%
  left_join(state_type, by = "state_abb")
traj_sum <- traj %>%
  group_by(type) %>%
  summarise(n_states = n(), mean_d = mean(d_post_pre), sd_d = sd(d_post_pre),
            .groups = "drop")
write_csv(traj, file.path(out_dir, "untreated_trajectories.csv"))
cat("\n===== (4) Untreated post-COVID minus pre-COVID mean log(1+filings) =====\n")
cat("(only states observed untreated on both sides of the window)\n")
print(as.data.frame(traj_sum), row.names = FALSE, digits = 3)
print(as.data.frame(traj %>% filter(type == "real_treated_late_censor") %>%
                      select(state_abb, d_post_pre) %>% arrange(d_post_pre)),
      row.names = FALSE, digits = 3)

# ---- (5) balanced common-support null ---------------------------------------

bal_states <- pan$states %>%
  filter(is.na(online_g) | !treated_observed) %>%       # never/no-post only
  filter(is.na(g_first)) %>%                            # strictly never-treated
  filter(first_obs <= as.Date("2016-06-01"),
         last_obs >= as.Date("2025-06-01")) %>%
  pull(state_abb)
cat(sprintf("\n===== (5) Balanced common-support null: states = %s =====\n",
            paste(bal_states, collapse = ", ")))

bal_panel <- pan$sim %>% filter(state_abb %in% bal_states)
# 4 singleton cohorts spanning the real calendar's shape: 2 pre-COVID dates,
# 2 post-COVID dates; every state fully eligible for every date by construction.
bal_tmpl <- tibble(g = as.Date(c("2019-05-01", "2019-12-01",
                                 "2022-01-01", "2023-01-01")),
                   n_states = 1L)

one_bal <- function(rep) {
  seed <- cfg$base_seed + 10007L * rep + 101L * 903L
  sched <- make_calendar_placebo(bal_panel, bal_tmpl, cfg$min_pre,
                                 cfg$min_post, seed = seed)
  inj <- bal_panel %>%
    left_join(sched, by = "state_abb") %>%
    mutate(y_sim = y_log1p, delta_imposed = 0)
  cs <- tryCatch(suppressMessages(suppressWarnings(fit_cs(inj))),
                 error = function(e) NULL)
  if (is.null(cs)) return(tibble(rep = rep, design = "full", att = NA_real_,
                                 converged = FALSE))
  aggregate_covid_subsets(cs, inj, cfg) %>%
    mutate(rep = rep, converged = is.finite(att))
}

t0 <- Sys.time()
bal <- bind_rows(mclapply(seq_len(N_BAL_REPS), function(r)
  tryCatch(one_bal(r), error = function(e)
    tibble(rep = r, design = "full", att = NA_real_, converged = FALSE)),
  mc.cores = N_CORES, mc.preschedule = FALSE))
write_csv(bal, file.path(out_dir, "balanced_null_raw.csv"))

bal_sum <- bal %>%
  filter(converged, design != "full_didsimple") %>%
  group_by(design) %>%
  summarise(n = n(), reject_05 = mean(p < cfg$alpha, na.rm = TRUE),
            mean_att = mean(att), sd_att = sd(att),
            mc_se_of_mean = sd(att) / sqrt(n()),
            mean_se = mean(se), se_over_sd = mean(se) / sd(att),
            .groups = "drop")
write_csv(bal_sum, file.path(out_dir, "balanced_null_summary.csv"))
cat(sprintf("(%d reps, %.1f min)\n", N_BAL_REPS,
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))
print(as.data.frame(bal_sum), row.names = FALSE, digits = 3)

cat("\nInterrogation outputs in", out_dir, "\n")
