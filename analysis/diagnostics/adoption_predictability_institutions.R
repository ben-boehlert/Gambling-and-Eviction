################################################################################
# adoption_predictability_institutions.R
#
# QUESTION: do POLITICAL / INSTITUTIONAL variables forecast sports-betting
#           adoption and its timing, where eviction and macro variables do not?
#
# The inferential point is not "which block wins". It is that unpredictability
# alone is weak evidence for a staggered DiD -- it is equally consistent with
# 30 adopters simply being too few to fit anything. The informative pattern is
# ASYMMETRIC predictability: adoption is forecastable from gambling-policy
# institutions, and NOT forecastable from the outcome's own history. That is a
# statement about WHICH variables the assignment mechanism runs on.
#
# Blocks actually implemented here (real data only -- see the acquisition table
# in docs/methodology/ADOPTION_PREDICTORS_FEASIBILITY.md for the rest):
#   POLITICAL  citizen + government ideology, Berry-Ringquist-Fording-Hanson,
#              measured 1991 -- genuinely PRE-PASPA (enacted October 1992)
#   REGION     Census 4-region classification (base R state.region), timeless
#   MACRO      mortgage distress + size + geography (from the pre-PASPA script)
#   EVICTION   pre-period eviction level + slope
#
# NOT implemented, because the data are not in this workspace and will not be
# hand-keyed from memory: casino/tribal gaming structure, lottery adoption year,
# constitutional/referendum barriers, legislature professionalism, fiscal
# dependence on gaming, neighbouring-state legalization.
#
# Output: output/adoption_predictability_institutions/
################################################################################

suppressPackageStartupMessages({
  library(tidyverse)
  library(readxl)
  library(survival)
})

theme_set(theme_minimal())
set.seed(20260821)

OUT <- "output/adoption_predictability_institutions"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

source("utils/eviction_treatment_schedule.R")
source("utils/cv_predictability.R")

ORIGIN     <- as.Date("2018-06-01")
CENSOR_END <- as.Date("2024-12-01")
TREAT_FILE <- "data/raw/sports_gambling_legalization_dates.csv"

IDEOLOGY_FILE <- file.path("/Users/bb1806/Documents/GitHub Doc/Funding",
                           "Data/stateideology_v2018.xlsx")
PRE_PASPA_YEAR <- 1991   # PASPA was enacted in October 1992

# ================================================================== outcomes ==
outcomes <- eviction_adoption_outcomes(TREAT_FILE, "online_start_date",
                                       censor_end = CENSOR_END, origin = ORIGIN) %>%
  filter(!pre_paspa_legal) %>%          # NV is always-treated, not a never-adopter
  rename(months = months_to_adopt)

# ================================================= POLITICAL block (pre-PASPA) =
# citi6016     = citizen ideology  (higher = more liberal)
# inst6017_nom = government/institutional ideology (NOMINATE-based)
ideo <- read_excel(IDEOLOGY_FILE, sheet = 1) %>%
  mutate(across(c(year, citi6016, inst6017_nom), as.numeric),
         state_abb = eviction_state_name_to_abb(state)) %>%
  filter(!is.na(state_abb), year == PRE_PASPA_YEAR) %>%
  transmute(state_abb,
            ideo_citizen = citi6016,
            ideo_govt    = inst6017_nom)

stopifnot(nrow(ideo) > 45, !any(duplicated(ideo$state_abb)))

# ==================================================================== REGION ===
# base R state.region is the Census 4-region classification; DC is not in it and
# is assigned to the South, matching Census practice.
region <- tibble(state_abb = state.abb,
                 region = as.character(state.region)) %>%
  bind_rows(tibble(state_abb = "DC", region = "South")) %>%
  mutate(region = recode(region, "North Central" = "Midwest"))

# expand to numeric dummies (Northeast = reference) because the CV machinery
# takes a numeric matrix
region_d <- region %>%
  mutate(v = 1L) %>%
  pivot_wider(names_from = region, values_from = v, values_fill = 0L,
              names_prefix = "reg_") %>%
  select(-reg_Northeast)

# =============================================== MACRO + EVICTION (as before) ==
mort <- read_csv("data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv",
                 show_col_types = FALSE) %>%
  filter(RegionType == "State") %>%
  mutate(state_abb = eviction_state_name_to_abb(Name)) %>%
  filter(!is.na(state_abb)) %>%
  select(-RegionType, -Name, -FIPSCode) %>%
  pivot_longer(-state_abb, names_to = "ym", values_to = "pct") %>%
  mutate(date = as.Date(paste0(ym, "-01")), pct = as.numeric(pct)) %>%
  filter(!is.na(pct)) %>%
  group_by(state_abb) %>%
  summarise(
    mort_level = mean(pct[date >= as.Date("2016-01-01") & date <= as.Date("2017-12-01")]),
    mort_peak  = max(pct[date >= as.Date("2009-01-01") & date <= as.Date("2010-12-01")]),
    .groups = "drop")

pop <- read_csv("data/processed/state_adult_population_monthly.csv",
                show_col_types = FALSE) %>%
  mutate(state_abb = eviction_state_name_to_abb(State),
         month_date = as.Date(month_date)) %>%
  filter(!is.na(state_abb), month_date == min(month_date)) %>%
  transmute(state_abb, log_pop = log(pop18))

ev <- local({
  cty <- read_csv("data/raw/county_court-issued_2000_2023_ben_update_5_12.csv",
                  show_col_types = FALSE) %>%
    mutate(state_abb = eviction_state_name_to_abb(state)) %>%
    filter(!is.na(state_abb), state_abb != "ID", year >= 2009, year <= 2015)
  basket <- cty %>%
    filter(!is.na(filings_observed), !is.na(renting_hh), renting_hh > 0) %>%
    count(state_abb, fips_county) %>% filter(n == 7) %>% select(state_abb, fips_county)
  cty %>% semi_join(basket, by = c("state_abb", "fips_county")) %>%
    group_by(state_abb, year) %>%
    summarise(f = sum(filings_observed), r = sum(renting_hh), .groups = "drop") %>%
    mutate(y = log(1000 * f / r)) %>%
    group_by(state_abb) %>% filter(n() == 7, all(is.finite(y))) %>%
    summarise(ev_level = mean(y[year >= 2013]),
              ev_slope = coef(lm(y ~ I(year - mean(year))))[2], .groups = "drop")
})

# ---- GAMBLING INSTITUTIONS, pre-PASPA (built 2026-08-21) --------------------
# Provenance: data/raw/gambling_institutions/SOURCES.md. Secondary-source
# compilation; adequate as a predictor block, not for publication without
# verification against primary statutes.
gamb <- read_csv("data/raw/gambling_institutions/state_gambling_institutions_prepaspa.csv",
                 show_col_types = FALSE) %>%
  select(state_abb, lottery_years_91, lottery_by_91, casino_auth_by_91, casino_op_by_91)

dat <- outcomes %>%
  left_join(gamb,     by = "state_abb") %>%
  left_join(ideo,     by = "state_abb") %>%
  left_join(region_d, by = "state_abb") %>%
  left_join(mort,     by = "state_abb") %>%
  left_join(pop,      by = "state_abb") %>%
  left_join(ev,       by = "state_abb")

# lottery_years_91 (maturity, 0 if no lottery yet) rather than the binary, and
# casino AUTHORIZATION rather than operation: authorization is the legislative
# act, and the hypothesis is that a legislature which has already authorized
# casino gambling authorizes sports betting sooner.
GAMBLING  <- c("lottery_years_91", "casino_auth_by_91")
POLITICAL <- c("ideo_citizen", "ideo_govt")
REGION    <- setdiff(names(region_d), "state_abb")
MACRO     <- c("mort_level", "mort_peak", "log_pop")
EVICTION  <- c("ev_level", "ev_slope")

cat("universe:", nrow(dat), "states |", sum(dat$ever), "adopted |",
    "ideology coverage:", sum(!is.na(dat$ideo_citizen)),
    "| eviction coverage:", sum(!is.na(dat$ev_level)), "\n")
cat("pre-PASPA gambling: lottery by 1991 =", sum(dat$lottery_by_91),
    "| casino authorized by 1991 =", sum(dat$casino_auth_by_91),
    "(of", nrow(dat), "analysed states; NV excluded)\n\n")

# ====================================================================== main ==
BLOCKS <- list(
  "gambling institutions (pre-PASPA)" = GAMBLING,
  "  lottery maturity only"           = "lottery_years_91",
  "  casino authorized only"          = "casino_auth_by_91",
  "political (ideology 1991)"         = POLITICAL,
  "region"                            = REGION,
  "macro (mortgage, size)"            = MACRO,
  "eviction (level, slope)"           = EVICTION,
  "gambling + political"              = c(GAMBLING, POLITICAL),
  "gambling + region"                 = c(GAMBLING, REGION),
  "gambling + political + region"     = c(GAMBLING, POLITICAL, REGION),
  "everything incl. eviction"         = c(GAMBLING, POLITICAL, REGION, MACRO, EVICTION)
)

runs <- imap(BLOCKS, ~ evaluate(dat, .x, .y, "pre-PASPA political / pre-repeal macro"))

ever   <- bind_rows(map(runs, "ever"))
timing <- bind_rows(map(runs, "timing"))
cox    <- bind_rows(map(runs, "cox"))

options(width = 200)
cat("=========== (1) EVER ADOPT ONLINE ===========\n")
print(as.data.frame(ever %>% select(model, n, events, n_pred, insample_auc, cv_auc,
                                    cv_auc_null_mean, p_auc, brier_skill) %>%
                      mutate(across(where(is.numeric), ~round(., 3)))), row.names = FALSE)
cat("\n=========== (2) MONTHS TO ADOPTION (adopters) ===========\n")
print(as.data.frame(timing %>% select(model, n, n_pred, insample_r2, cv_r2,
                                      cv_r2_null_mean, p_r2) %>%
                      mutate(across(where(is.numeric), ~round(., 3)))), row.names = FALSE)
cat("\n=========== (3) ADOPTION HAZARD (Cox, censored) ===========\n")
print(as.data.frame(cox %>% select(model, n, events, n_pred, cv_cindex,
                                   cindex_null_mean, p_cindex) %>%
                      mutate(across(where(is.numeric), ~round(., 3)))), row.names = FALSE)

write_csv(ever,   file.path(OUT, "block_ever.csv"))
write_csv(timing, file.path(OUT, "block_timing.csv"))
write_csv(cox,    file.path(OUT, "block_cox.csv"))
write_csv(dat,    file.path(OUT, "state_predictors.csv"))

# ---- the orthogonality question the asymmetry argument actually rests on -----
# If the institutional predictors are themselves correlated with pre-period
# eviction level/slope, "assignment runs on institutions" does NOT imply
# "assignment is unrelated to eviction dynamics".
orth <- crossing(inst = c(GAMBLING, POLITICAL, REGION), ev = EVICTION) %>%
  rowwise() %>%
  mutate(n = sum(complete.cases(dat[[inst]], dat[[ev]])),
         r = cor(dat[[inst]], dat[[ev]], use = "complete.obs"),
         p = cor.test(dat[[inst]], dat[[ev]])$p.value) %>%
  ungroup()
cat("\n=========== (4) ORTHOGONALITY: institutions vs pre-period eviction ===========\n")
print(as.data.frame(orth %>% mutate(across(c(r, p), ~round(., 3)))), row.names = FALSE)
write_csv(orth, file.path(OUT, "orthogonality.csv"))

cat("\nWrote:", OUT, "\n")
