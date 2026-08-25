#!/usr/bin/env Rscript
################################################################################
# analysis/cheap_sims/11_exposure_time_vs_intensity.R
#
# Two questions about the "~91% of online-era handle is post-recovery" fact:
#
# Q1 (mechanical vs real): is that share just because more calendar months have
#     elapsed since the recovery month than between legalization and it? Answer
#     by comparing each state's POST-RECOVERY SHARE OF HANDLE to its
#     POST-RECOVERY SHARE OF MONTHS. If handle share == month share, the fact is
#     purely elapsed time; if handle share > month share, monthly intensity also
#     rose. Reported as the intensity ratio = mean monthly handle post / pre.
#
# Q2 (levels): how do monthly totals and per-capita handle in pre-COVID
#     legalization states compare with the most recent month available?
#     Sports betting is strongly seasonal (NFL season vs summer), so the
#     headline comparison uses 12-MONTH WINDOWS (last 12 observed months vs the
#     state's last 12 pre-COVID months); the single most recent month is also
#     reported, flagged for seasonality.
#
# Denominator: Census vintage-2023 state population estimates (tidycensus).
#
# Recovery anchor R = 2021-09-01 (see 10_exposure_timing_update.R).
#
# Run from repo root:  Rscript analysis/cheap_sims/11_exposure_time_vs_intensity.R
################################################################################

suppressPackageStartupMessages({
  library(tidyverse); library(lubridate); library(tidycensus)
})
source("utils/eviction_treatment_schedule.R")

R_MONTH     <- as.Date("2021-09-01")
COVID_START <- as.Date("2020-03-01")
out_dir <- "output/cheap_power_sim/county_covidclean"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ---- inputs -----------------------------------------------------------------

h <- read_csv("data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv",
              show_col_types = FALSE) %>%
  transmute(state_abb = eviction_state_name_to_abb(State),
            month_date = floor_date(as.Date(month_date), "month"),
            handle = as.numeric(Handle)) %>%
  filter(!is.na(state_abb), !is.na(handle), handle > 0)

sched <- read_csv("data/raw/sports_gambling_legalization_dates.csv",
                  show_col_types = FALSE) %>%
  mutate(state_abb = eviction_state_name_to_abb(state)) %>%
  # NV exclusion comes from the shared constant, not an inline literal, so the
  # pre-PASPA rule lives in exactly one place (see ADOPTION_UNIVERSE_AUDIT.md).
  filter(!is.na(online_start_date),
         !state_abb %in% PRE_PASPA_SPORTS_BETTING) %>%
  transmute(state_abb, g = as.Date(online_start_date))

pop <- get_estimates(geography = "state", product = "population",
                     year = 2023, vintage = 2023) %>%
  filter(variable == "POPESTIMATE") %>%
  transmute(state_abb = eviction_state_name_to_abb(NAME), pop = value) %>%
  filter(!is.na(state_abb))

online <- h %>% inner_join(sched, by = "state_abb") %>%
  filter(month_date >= g) %>%
  left_join(pop, by = "state_abb")
last_month <- max(online$month_date)
cat(sprintf("online-era handle: %d states, through %s\n",
            n_distinct(online$state_abb), format(last_month)))

# ---- Q1: months vs intensity ------------------------------------------------

q1 <- online %>%
  mutate(post = month_date > R_MONTH) %>%
  group_by(state_abb, g) %>%
  summarise(
    n_pre  = sum(!post), n_post = sum(post),
    h_pre  = sum(handle[!post]), h_post = sum(handle[post]),
    .groups = "drop") %>%
  filter(n_pre > 0) %>%              # states legalizing after R are trivially 100%
  mutate(
    pct_months_post = 100 * n_post / (n_pre + n_post),
    pct_handle_post = 100 * h_post / (h_pre + h_post),
    mean_pre  = h_pre / n_pre,
    mean_post = h_post / n_post,
    intensity_ratio = mean_post / mean_pre,
    # counterfactual: handle share if monthly intensity had never changed
    excess_pp = pct_handle_post - pct_months_post,
    class = if_else(g < COVID_START, "pre-COVID", "during COVID")
  ) %>%
  arrange(g)

write_csv(q1, file.path(out_dir, "exposure_time_vs_intensity.csv"))

cat("\n===== Q1: is the post-recovery share just elapsed time? =====\n")
print(as.data.frame(q1 %>%
  transmute(state_abb, g, class, n_pre, n_post,
            `%months post` = pct_months_post, `%handle post` = pct_handle_post,
            `excess pp` = excess_pp,
            `mean $M/mo pre` = mean_pre / 1e6,
            `mean $M/mo post` = mean_post / 1e6,
            `intensity x` = intensity_ratio)),
  row.names = FALSE, digits = 3)

agg <- q1 %>% summarise(
  months_post = 100 * sum(n_post) / sum(n_pre + n_post),
  handle_post = 100 * sum(h_post) / sum(h_pre + h_post),
  intensity   = (sum(h_post) / sum(n_post)) / (sum(h_pre) / sum(n_pre)))
cat(sprintf("\nPooled (states with pre-recovery months): months post %.1f%% | handle post %.1f%% | intensity %.2fx\n",
            agg$months_post, agg$handle_post, agg$intensity))

# ---- Q2: levels, pre-COVID states then vs now -------------------------------

pre_states <- sched %>% filter(g < COVID_START) %>% pull(state_abb)

# last 12 observed months (seasonality-neutral) and single latest month
recent <- online %>%
  filter(month_date > last_month %m-% months(12)) %>%
  group_by(state_abb, pop) %>%
  summarise(recent12_mo_mean = mean(handle), .groups = "drop")
latest <- online %>% filter(month_date == last_month) %>%
  select(state_abb, latest_month = handle)

# each pre-COVID state's last 12 months before the COVID break
pre_win <- online %>%
  filter(state_abb %in% pre_states, month_date < COVID_START) %>%
  group_by(state_abb) %>%
  summarise(n_pre_covid_mo = n(), preCOVID_mo_mean = mean(handle),
            .groups = "drop")

q2 <- pre_win %>%
  left_join(recent, by = "state_abb") %>%
  left_join(latest, by = "state_abb") %>%
  left_join(sched, by = "state_abb") %>%
  mutate(
    pre_pc     = preCOVID_mo_mean / pop,
    recent_pc  = recent12_mo_mean / pop,
    latest_pc  = latest_month / pop,
    growth_x   = recent12_mo_mean / preCOVID_mo_mean
  ) %>%
  arrange(g)

write_csv(q2, file.path(out_dir, "prcovid_states_levels_then_now.csv"))

cat(sprintf("\n===== Q2: pre-COVID legalizers, monthly handle then vs now (latest = %s) =====\n",
            format(last_month)))
print(as.data.frame(q2 %>%
  transmute(state_abb, g, `pre-COVID mo` = n_pre_covid_mo,
            `pre $M/mo` = preCOVID_mo_mean / 1e6,
            `recent12 $M/mo` = recent12_mo_mean / 1e6,
            `latest $M` = latest_month / 1e6,
            `pre $/capita/mo` = pre_pc,
            `recent $/capita/mo` = recent_pc,
            `growth x` = growth_x)),
  row.names = FALSE, digits = 3)

cat(sprintf("\nPre-COVID legalizers pooled: $%.0f/capita/mo pre-COVID vs $%.0f now (%.1fx)\n",
            sum(q2$preCOVID_mo_mean) / sum(q2$pop),
            sum(q2$recent12_mo_mean) / sum(q2$pop),
            sum(q2$recent12_mo_mean) / sum(q2$preCOVID_mo_mean)))

# all-state per-capita context for the latest 12 months
ctx <- recent %>% left_join(sched, by = "state_abb") %>%
  mutate(pc = recent12_mo_mean / pop,
         era = case_when(g < COVID_START ~ "pre-COVID legalizer",
                         g <= R_MONTH ~ "during-COVID legalizer",
                         TRUE ~ "post-recovery legalizer")) %>%
  group_by(era) %>%
  summarise(n = n(), median_pc = median(pc), mean_pc = mean(pc),
            .groups = "drop")
cat("\nCurrent per-capita monthly handle by legalization era (last 12 mo):\n")
print(as.data.frame(ctx), row.names = FALSE, digits = 3)
