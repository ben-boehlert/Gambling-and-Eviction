#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# SELECTION PLACEBO for the binary 2x2 long difference.
#
# The power simulation assigns pseudo-treatment AT RANDOM, which is what makes
# it a power exercise. This script asks the complementary question with the
# REAL split: on a calendar where nobody has legalized anything, do the states
# that would EVENTUALLY legalize online sports betting already differ in their
# long difference from the states that never would?
#
# A large, significant contrast here is not a power finding — it is a threat to
# the real design's identifying assumption, because it means the two groups
# were on different trajectories before treatment could have caused anything.
#
# BLINDNESS NOTE. Every observation used predates the first-ever legalization
# (2018-06), so this is untreated data and permitted under the protocol. But it
# does reveal the REAL group contrast, which the randomized power simulation
# deliberately does not. It is therefore written to its own output directory
# and must not be used to select estimators, windows, or specifications — it is
# a pre-trends diagnostic, reported as such.
#
# Usage:  Rscript analysis/diagnostics/longdiff_2x2_selection_placebo.R
# Output: output/longdiff_2x2_selection/selection_placebo.csv
# ─────────────────────────────────────────────────────────────────────────────

suppressMessages({ library(tidyverse); library(glue) })
theme_set(theme_minimal())
set.seed(20260723)

OUT_DIR <- "output/longdiff_2x2_selection"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

N_RI <- 4999L

source("utils/eviction_treatment_schedule.R")
ever_online <- load_eviction_treatment_schedule(
  "data/raw/sports_gambling_legalization_dates.csv", "online_start_date") %>%
  filter(!is.na(treat_start)) %>% pull(state_abb)

xw <- tibble(state_abb = c(state.abb, "DC"),
             state_key = tolower(c(state.name, "district of columbia")))

annual <- read_csv("data/raw/county_court-issued_2000_2023_ben_update_5_12.csv",
                   show_col_types = FALSE) %>%
  transmute(state_key = tolower(str_trim(state)),
            fips = as.integer(fips_county), year = as.integer(year),
            filings = as.numeric(filings_observed),
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

DESIGNS <- list(
  main     = list(base_years = c(2008L, 2009L), end_year = 2016L),
  main_b12 = list(base_years = 2009L,           end_year = 2016L),
  late     = list(base_years = c(2010L, 2011L), end_year = 2016L)
)

run_one <- function(nm, spec) {
  need <- c(spec$base_years, spec$end_year)
  d <- annual %>% filter(year %in% need)
  keep <- d %>% count(fips) %>% filter(n == length(need)) %>% pull(fips)
  d <- d %>% filter(fips %in% keep)

  base <- d %>% filter(year %in% spec$base_years) %>%
    group_by(state_abb, fips) %>%
    summarise(y_pre = mean(log1p(filings)),
              w = mean(renting_hh, na.rm = TRUE), .groups = "drop")
  endp <- d %>% filter(year == spec$end_year) %>%
    transmute(state_abb, fips, y_end = log1p(filings))

  cty <- inner_join(base, endp, by = c("state_abb", "fips")) %>%
    mutate(w = ifelse(is.finite(w) & w > 0, w, 1),
           dY = y_end - y_pre,
           D  = as.integer(state_abb %in% ever_online))

  states <- sort(unique(cty$state_abb))
  idx    <- match(cty$state_abb, states)
  Sw <- as.numeric(tapply(cty$w * cty$dY, idx, sum))
  W  <- as.numeric(tapply(cty$w, idx, sum))
  D_state <- cty %>% distinct(state_abb, D) %>% arrange(state_abb) %>% pull(D)
  tr <- which(D_state == 1L)

  tau_of <- function(s) sum(Sw[s]) / sum(W[s]) -
                        sum(Sw[-s]) / sum(W[-s])
  tau <- tau_of(tr)
  n_tr <- length(tr)
  ri <- vapply(seq_len(N_RI),
               function(i) tau_of(sample.int(length(states), n_tr)),
               numeric(1))
  p_ri <- (1 + sum(abs(ri) >= abs(tau))) / (N_RI + 1)

  tibble(design = nm,
         baseline = paste(spec$base_years, collapse = "+"),
         endpoint = spec$end_year,
         n_states = length(states), n_treated = n_tr,
         n_counties = nrow(cty),
         tau = tau, tau_pct = 100 * (exp(tau) - 1),
         ri_sd = sd(ri), p_ri = p_ri)
}

res <- imap_dfr(DESIGNS, ~ run_one(.y, .x))
write_csv(res, file.path(OUT_DIR, "selection_placebo.csv"))

cat("\n===== SELECTION PLACEBO: real online-ever vs never split, ",
    "pre-treatment calendar =====\n", sep = "")
print(as.data.frame(res), digits = 3)
cat("\nInterpretation: tau is the long-difference contrast between states that\n",
    "would eventually legalize online and states that never did, measured\n",
    "entirely before any legalization. Large |tau| with small p_ri = the two\n",
    "groups were already diverging.\n", sep = "")
