################################################################################
# adoption_predictability_prepaspa.R
#
# QUESTION: How predictable are (a) EVER adopting online sports betting and
#           (b) adoption TIMING, from variables measured before the PASPA repeal?
#
# "Before PASPA" is read two ways, and both are run:
#   PRE-REPEAL      predictors dated <= 2018-01, i.e. before Murphy v. NCAA
#                   (2018-05-14) and before the first legalization (2018-06).
#   PRE-ANTICIPATION predictors dated <= 2009-12, i.e. before New Jersey's 2012
#                   PASPA challenge, so before any state could plausibly be
#                   positioning for a repeal.
# A literal pre-1992 (PASPA enactment) read is not feasible here: the earliest
# eviction series in this repo starts in 2000 and the mortgage series in 2008.
#
# Predictability, not significance, is the object. With 51 states and a handful
# of predictors, in-sample fit is badly optimistic, so every number reported is
# LEAVE-ONE-OUT CROSS-VALIDATED and compared against a permutation null built by
# reshuffling the outcome and redoing the whole LOO loop.
#
# Output: output/adoption_predictability/
################################################################################

suppressPackageStartupMessages({
  library(tidyverse)
  library(survival)
})

theme_set(theme_minimal())
set.seed(20260821)

OUT <- "output/adoption_predictability"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
source("utils/eviction_treatment_schedule.R")

ORIGIN     <- as.Date("2018-06-01")
CENSOR_END <- as.Date("2024-12-01")
PERM       <- 2000

# ================================================================== outcomes ==
# The 51-state universe and the Nevada exclusion live in
# utils/eviction_treatment_schedule.R. Nevada is dropped: legal sports betting
# since 1949 makes it always-treated, not a never-adopter, so including it would
# put an always-treated state in the "did not adopt" class.
outcomes <- eviction_adoption_outcomes(
  "data/raw/sports_gambling_legalization_dates.csv",
  treat_date_col = "online_start_date",
  censor_end = CENSOR_END, origin = ORIGIN
) %>%
  filter(!pre_paspa_legal) %>%
  rename(months = months_to_adopt)

STATE_UNIVERSE <- outcomes$state_abb
cat("adoption universe:", nrow(outcomes), "states |", sum(outcomes$ever),
    "adopted online by", format(CENSOR_END), "| NV excluded (pre-PASPA)\n")

# ================================================================ predictors ==
# ---- mortgage 90+ day delinquency: 51 states, monthly 2008-01 onward ---------
mort_long <- read_csv("data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv",
                      show_col_types = FALSE) %>%
  filter(RegionType == "State") %>%
  mutate(state_abb = eviction_state_name_to_abb(Name)) %>%
  filter(!is.na(state_abb)) %>%
  select(-RegionType, -Name, -FIPSCode) %>%
  pivot_longer(-state_abb, names_to = "ym", values_to = "pct") %>%
  mutate(date = as.Date(paste0(ym, "-01")), pct = as.numeric(pct)) %>%
  filter(!is.na(pct))

slope_pp_yr <- function(d, v) 12 * coef(lm(v ~ I(as.numeric(d) / 30.4375)))[2]

mort_pre_repeal <- mort_long %>%
  group_by(state_abb) %>%
  summarise(
    mort_level = mean(pct[date >= as.Date("2016-01-01") & date <= as.Date("2017-12-01")]),
    mort_peak  = max(pct[date >= as.Date("2009-01-01") & date <= as.Date("2010-12-01")]),
    mort_slope = slope_pp_yr(date[date >= as.Date("2010-01-01") & date <= as.Date("2017-12-01")],
                             pct[date >= as.Date("2010-01-01") & date <= as.Date("2017-12-01")]),
    .groups = "drop")

mort_pre_antic <- mort_long %>%
  filter(date <= as.Date("2009-12-01")) %>%
  group_by(state_abb) %>%
  summarise(
    mort_level = mean(pct),
    mort_peak  = max(pct),
    mort_slope = slope_pp_yr(date, pct),
    .groups = "drop")

# ---- state size: adult population, first available month (2018-01) ----------
pop <- read_csv("data/processed/state_adult_population_monthly.csv",
                show_col_types = FALSE) %>%
  mutate(state_abb = eviction_state_name_to_abb(State),
         month_date = as.Date(month_date)) %>%
  filter(!is.na(state_abb), month_date == min(month_date)) %>%
  transmute(state_abb, log_pop = log(pop18))

# ---- geography: number of bordering states (time-invariant, truly pre-PASPA)--
adj <- read_lines("data/raw/county_adjacency_census.txt")
adj_tbl <- tibble(raw = adj) %>%
  separate(raw, into = c("a_name", "a_fips", "b_name", "b_fips"),
           sep = "\t", fill = "left") %>%
  mutate(a_name = na_if(str_remove_all(a_name, '"'), ""),
         b_name = str_remove_all(b_name, '"')) %>%
  fill(a_name, .direction = "down") %>%
  transmute(a_st = str_trim(str_sub(a_name, -2)),
            b_st = str_trim(str_sub(b_name, -2)))

border <- bind_rows(adj_tbl, adj_tbl %>% rename(a_st = b_st, b_st = a_st)) %>%
  filter(a_st != b_st, a_st %in% STATE_UNIVERSE, b_st %in% STATE_UNIVERSE) %>%
  distinct(a_st, b_st) %>%
  count(a_st, name = "n_border") %>%
  rename(state_abb = a_st) %>%
  # AK and HI have no land borders; count() drops them, which would silently
  # delete two genuine never-adopters. They are 0-border states, not missing.
  right_join(tibble(state_abb = STATE_UNIVERSE), by = "state_abb") %>%
  mutate(n_border = replace_na(n_border, 0L))

# ---- eviction level and slope (subset of states) ----------------------------
ev_features <- function(y0, y1, level_yrs) {
  cty <- read_csv("data/raw/county_court-issued_2000_2023_ben_update_5_12.csv",
                  show_col_types = FALSE) %>%
    mutate(state_abb = eviction_state_name_to_abb(state)) %>%
    filter(!is.na(state_abb), state_abb != "ID", year >= y0, year <= y1)
  nyr <- y1 - y0 + 1
  basket <- cty %>%
    filter(!is.na(filings_observed), !is.na(renting_hh), renting_hh > 0) %>%
    count(state_abb, fips_county) %>% filter(n == nyr) %>%
    select(state_abb, fips_county)
  cty %>%
    semi_join(basket, by = c("state_abb", "fips_county")) %>%
    group_by(state_abb, year) %>%
    summarise(filings = sum(filings_observed), renters = sum(renting_hh),
              n_cty = n(), .groups = "drop") %>%
    mutate(y = log(1000 * filings / renters)) %>%
    group_by(state_abb) %>%
    filter(n() == nyr, all(is.finite(y))) %>%
    summarise(ev_n_cty = first(n_cty),
              ev_level = mean(y[year %in% level_yrs]),
              ev_slope = coef(lm(y ~ I(year - mean(year))))[2],
              .groups = "drop")
}

ev_pre_repeal <- ev_features(2009, 2015, 2013:2015)
ev_pre_antic  <- ev_features(2003, 2009, 2007:2009)

cat("predictor coverage: mortgage", nrow(mort_pre_repeal), "| pop", nrow(pop),
    "| border", nrow(border), "| eviction pre-repeal", nrow(ev_pre_repeal),
    "| eviction pre-antic", nrow(ev_pre_antic), "\n")

source("utils/cv_predictability.R")

# ====================================================================== main ==
dat_repeal <- outcomes %>%
  left_join(mort_pre_repeal, by = "state_abb") %>%
  left_join(pop,             by = "state_abb") %>%
  left_join(border,          by = "state_abb") %>%
  left_join(ev_pre_repeal,   by = "state_abb")

dat_antic <- outcomes %>%
  left_join(mort_pre_antic, by = "state_abb") %>%
  left_join(border,         by = "state_abb") %>%
  left_join(ev_pre_antic,   by = "state_abb")

MACRO_R <- c("mort_level", "mort_peak", "mort_slope", "log_pop", "n_border")
MACRO_A <- c("mort_level", "mort_peak", "mort_slope", "n_border")
EV      <- c("ev_level", "ev_slope")

runs <- list(
  evaluate(dat_repeal, MACRO_R,            "macro only (51 st)",        "pre-repeal (<=2018-01)"),
  evaluate(dat_repeal %>% drop_na(all_of(EV)), MACRO_R, "macro only, eviction sample", "pre-repeal (<=2018-01)"),
  evaluate(dat_repeal, c(MACRO_R, EV),     "macro + eviction",          "pre-repeal (<=2018-01)"),
  evaluate(dat_repeal, EV,                 "eviction only",             "pre-repeal (<=2018-01)"),
  evaluate(dat_antic,  MACRO_A,            "macro only (51 st)",        "pre-anticipation (<=2009-12)"),
  evaluate(dat_antic %>% drop_na(all_of(EV)), MACRO_A, "macro only, eviction sample", "pre-anticipation (<=2009-12)"),
  evaluate(dat_antic,  c(MACRO_A, EV),     "macro + eviction",          "pre-anticipation (<=2009-12)"),
  evaluate(dat_antic,  EV,                 "eviction only",             "pre-anticipation (<=2009-12)")
)

ever   <- bind_rows(lapply(runs, `[[`, "ever"))
timing <- bind_rows(lapply(runs, `[[`, "timing"))
cox    <- bind_rows(lapply(runs, `[[`, "cox"))

options(width = 200)
cat("\n================ (1) EVER ADOPT ONLINE: out-of-sample discrimination ================\n")
print(as.data.frame(ever %>% mutate(across(where(is.numeric), ~round(., 3)))), row.names = FALSE)
cat("\n================ (2) TIMING AMONG ADOPTERS: out-of-sample R^2 ======================\n")
print(as.data.frame(timing %>% mutate(across(where(is.numeric), ~round(., 3)))), row.names = FALSE)
cat("\n================ (3) ADOPTION HAZARD: LOO Cox concordance ==========================\n")
print(as.data.frame(cox %>% mutate(across(where(is.numeric), ~round(., 3)))), row.names = FALSE)

write_csv(ever,   file.path(OUT, "predictability_ever.csv"))
write_csv(timing, file.path(OUT, "predictability_timing.csv"))
write_csv(cox,    file.path(OUT, "predictability_cox.csv"))

# ------------------------------------------- single-predictor LOO screening ---
single <- map_dfr(
  list(list(dat_repeal, c(MACRO_R, EV), "pre-repeal (<=2018-01)"),
       list(dat_antic,  c(MACRO_A, EV), "pre-anticipation (<=2009-12)")),
  function(cfg) {
    map_dfr(cfg[[2]], function(v) {
      r <- evaluate(cfg[[1]], v, paste0("single: ", v), cfg[[3]])
      bind_cols(r$ever %>% select(window, model, n, events, cv_auc, p_auc, brier_skill),
                r$cox  %>% select(cv_cindex, p_cindex))
    })
  })
cat("\n================ single-predictor screen ============================================\n")
print(as.data.frame(single %>% mutate(across(where(is.numeric), ~round(., 3)))), row.names = FALSE)
write_csv(single, file.path(OUT, "predictability_single.csv"))

# --------------------------------------------------------------------- plot ---
plot_dat <- bind_rows(
  ever %>% transmute(window, model, metric = "CV AUC (ever adopt)",
                     value = cv_auc, null = cv_auc_null_mean, p = p_auc, n),
  cox  %>% transmute(window, model, metric = "CV Cox concordance (timing)",
                     value = cv_cindex, null = cindex_null_mean, p = p_cindex, n)
)

p <- ggplot(plot_dat, aes(value, fct_rev(model))) +
  geom_vline(xintercept = 0.5, linetype = "dotted", colour = "grey75") +
  geom_segment(aes(x = null, xend = value, yend = fct_rev(model)),
               colour = "grey70", linewidth = 0.4) +
  geom_point(aes(x = null), colour = "grey60", size = 1.6, shape = 4) +
  geom_point(aes(colour = p < 0.05), size = 3) +
  geom_text(aes(label = sprintf("%.2f (p=%.2f, n=%d)", value, p, n)),
            hjust = -0.15, size = 2.7) +
  facet_grid(window ~ metric) +
  scale_colour_manual(values = c(`FALSE` = "grey35", `TRUE` = "firebrick"),
                      labels = c("not better than chance", "beats permutation null")) +
  coord_cartesian(xlim = c(0.2, 1.25)) +
  labs(x = "out-of-sample discrimination (0.5 = coin flip)", y = NULL, colour = NULL,
       caption = "x = mean of the permutation null (the correct reference, not 0.5). Repeated stratified 5-fold CV; 1,000 permutations.")
ggsave(file.path(OUT, "predictability_summary.png"), p, width = 11, height = 6.5, dpi = 200)

cat("\nWrote:", OUT, "\n")
