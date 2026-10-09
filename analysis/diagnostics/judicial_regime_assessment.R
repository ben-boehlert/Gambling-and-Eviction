################################################################################
# judicial_regime_assessment.R  (2026-09-29)
#
# Is the judicial-foreclosure flag worth carrying as a control in the mortgage
# design? Two questions:
#   (a) Do 90+ day delinquency rates differ by foreclosure regime -- in level,
#       pre-COVID trend, COVID response, and post-2022 trend?
#   (b) Do judicial and non-judicial states differ systematically on baseline
#       covariates and on treatment status?
#
# Regime: RealtyTrac 2010 "judicial only" (the Mian, Sufi & Trebbi 2015 source),
# via data/processed/state_covariates_2019.csv (data_prep/build_state_covariates_2019.R).
#
# BLINDNESS. Part (a) uses UNTREATED state-months only: each launching state is
# cut at online launch minus 6 months (the blinded loader's anticipation
# convention), so no post-launch outcome enters. Part (b) uses no outcome data
# beyond the 2019 untreated baseline. NV excluded (drop_pre_paspa_states).
#
# Run from the project root:
#   Rscript analysis/diagnostics/judicial_regime_assessment.R
# Opt-in log outcome (2026-10-09): Y_LOG=TRUE takes log(rate) -- the blinded
# framework's y_log_pp convention; the 90+ rate has no zeros (min 0.2pp) -- and
# writes to output/judicial_regime_assessment_log/ and *_log figures. Levels are
# then log points, slopes log points/yr. Default (unset) is unchanged.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
  library(fixest)
  library(lubridate)
})
source("utils/eviction_treatment_schedule.R")
theme_set(theme_minimal(base_family = "serif"))

MORT_FILE  <- "data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv"
SCHED_FILE <- "data/raw/sports_gambling_legalization_dates.csv"
COV_FILE   <- "data/processed/state_covariates_2019.csv"
Y_LOG      <- identical(Sys.getenv("Y_LOG"), "TRUE")
OUT_DIR    <- paste0("output/judicial_regime_assessment", if (Y_LOG) "_log" else "")
FIG_DIR    <- "figures"
FIG_STEM   <- paste0("judicial_regime_delinquency_untreated", if (Y_LOG) "_log" else "")
ANTICIPATION_MONTHS <- 6
COVID_START <- as.Date("2020-03-01")
DESIGN_START <- as.Date("2022-06-01")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

cov <- read_csv(COV_FILE, show_col_types = FALSE) %>%
  drop_pre_paspa_states("judicial_regime_assessment") %>%
  mutate(regime = if_else(judicial_only == 1, "Judicial", "Non-judicial"))

sched <- load_eviction_treatment_schedule(SCHED_FILE, "online_start_date",
                                          states = cov$state_abb)

mw <- read_csv(MORT_FILE, show_col_types = FALSE) %>% filter(RegionType == "State")
month_cols <- grep("^\\d{4}-\\d{2}$", names(mw), value = TRUE)
mort <- mw %>%
  select(Name, all_of(month_cols)) %>%
  pivot_longer(-Name, names_to = "m", values_to = "delinq_pp") %>%
  transmute(state_abb = eviction_state_name_to_abb(Name),
            month_date = as.Date(paste0(m, "-01")),
            delinq_pp = as.numeric(delinq_pp)) %>%
  filter(!is.na(state_abb), month_date >= as.Date("2016-01-01")) %>%
  drop_pre_paspa_states("judicial_regime_assessment") %>%
  mutate(delinq_pp = if (Y_LOG) log(delinq_pp) else delinq_pp) %>%
  left_join(sched, by = "state_abb") %>%
  # untreated state-months only
  filter(is.na(treat_start) | month_date < treat_start %m-% months(ANTICIPATION_MONTHS)) %>%
  left_join(select(cov, state_abb, regime), by = "state_abb")
stopifnot(!anyNA(mort$regime))

# ---- (a) delinquency by regime ----------------------------------------------
monthly <- mort %>%
  group_by(regime, month_date) %>%
  summarise(mean_pp = mean(delinq_pp), n_states = n(), .groups = "drop")
write_csv(monthly, file.path(OUT_DIR, "monthly_mean_by_regime_untreated.csv"))

p <- ggplot(monthly, aes(month_date, mean_pp, linetype = regime, shape = regime)) +
  annotate("rect", xmin = COVID_START, xmax = as.Date("2021-07-31"),
           ymin = -Inf, ymax = Inf, alpha = 0.12) +
  geom_line() +
  scale_linetype_manual(values = c("solid", "dashed")) +
  labs(x = NULL, y = if (Y_LOG) "log of 90+ days delinquent (% of mortgages)"
           else "90+ days delinquent (% of mortgages)",
       linetype = NULL, shape = NULL) +
  theme(legend.position = "bottom")
ggsave(file.path(FIG_DIR, paste0(FIG_STEM, ".pdf")), p, width = 6.5, height = 4)
ggsave(file.path(FIG_DIR, paste0(FIG_STEM, ".png")), p, width = 6.5, height = 4, dpi = 300)

slope_pp_per_year <- function(d) {
  if (nrow(d) < 12) return(NA_real_)
  unname(coef(lm(delinq_pp ~ as.numeric(month_date), data = d))[2]) * 365.25
}
by_state <- mort %>%
  group_by(state_abb, regime) %>%
  summarise(
    level_2019   = mean(delinq_pp[format(month_date, "%Y") == "2019"]),
    slope_pre    = slope_pp_per_year(pick(month_date, delinq_pp)[month_date < COVID_START, ]),
    covid_change = mean(delinq_pp[month_date >= as.Date("2021-08-01") &
                                    month_date < DESIGN_START]) - level_2019,
    slope_post   = slope_pp_per_year(pick(month_date, delinq_pp)[month_date >= DESIGN_START, ]),
    .groups = "drop") %>%
  mutate(across(where(is.numeric), ~ ifelse(is.nan(.x), NA_real_, .x)))

diff_test <- function(var) {
  d <- by_state %>% filter(!is.na(.data[[var]]))
  f <- feols(as.formula(paste(var, "~ I(regime == 'Judicial')")), data = d, vcov = "hetero")
  tibble(measure = var,
         mean_judicial = mean(d[[var]][d$regime == "Judicial"]),
         mean_nonjudicial = mean(d[[var]][d$regime == "Non-judicial"]),
         diff = unname(coef(f)[2]), se = unname(se(f)[2]), p = unname(pvalue(f)[2]),
         sd_pooled = sd(d[[var]]),
         n_judicial = sum(d$regime == "Judicial"),
         n_nonjudicial = sum(d$regime == "Non-judicial"))
}
part_a <- bind_rows(lapply(c("level_2019", "slope_pre", "covid_change", "slope_post"), diff_test)) %>%
  mutate(diff_in_sd = diff / sd_pooled)
write_csv(part_a, file.path(OUT_DIR, "part_a_delinquency_by_regime.csv"))

# ---- (b) balance and treatment status -----------------------------------------
cov_vars <- c(med_hh_income = "Median household income ($)",
              owner_occ_pct = "Owner-occupied (%)",
              age65_pct = "Age 65+ (%)", ba_plus_pct = "BA or higher (%)",
              black_pct = "Black (%)", hispanic_pct = "Hispanic (%)",
              unemp_2019 = "Unemployment rate 2019 (%)",
              hpi_growth_2016q4_2019q4 = "House-price growth 2016Q4-2019Q4 (%)",
              fha_va_share_2019 = "FHA/VA share of 2019 originations (%)",
              rt_process_days = "RealtyTrac process period (days)")
part_b <- bind_rows(lapply(names(cov_vars), function(v) {
  x <- cov[[v]]; j <- cov$regime == "Judicial"
  tt <- t.test(x[j], x[!j])
  tibble(variable = cov_vars[[v]], mean_judicial = mean(x[j]), mean_nonjudicial = mean(x[!j]),
         diff = mean(x[j]) - mean(x[!j]),
         smd = (mean(x[j]) - mean(x[!j])) / sqrt((var(x[j]) + var(x[!j])) / 2),
         p_welch = tt$p.value)
}))
write_csv(part_b, file.path(OUT_DIR, "part_b_balance_by_regime.csv"))

june2022_switchers <- c("DE", "FL", "KS", "KY", "MA", "MD", "ME", "NC", "OH", "VT")
status <- cov %>% select(state_abb, regime) %>%
  left_join(sched, by = "state_abb") %>%
  mutate(status = case_when(
    state_abb %in% june2022_switchers ~ "June-2022 design switcher",
    is.na(treat_start) | treat_start > as.Date("2025-03-01") ~ "Untreated through 2025-03",
    treat_start < DESIGN_START ~ "Launched before 2022-06",
    TRUE ~ "Launched 2022-06+, not a switcher"))
xtab <- status %>% count(status, regime) %>%
  pivot_wider(names_from = regime, values_from = n, values_fill = 0)
write_csv(status, file.path(OUT_DIR, "treatment_status_by_regime.csv"))
write_csv(xtab, file.path(OUT_DIR, "treatment_status_by_regime_xtab.csv"))

region <- tibble(state_abb = state.abb, census_region = as.character(state.region)) %>%
  bind_rows(tibble(state_abb = "DC", census_region = "South"))
xreg <- cov %>% left_join(region, by = "state_abb") %>% count(census_region, regime) %>%
  pivot_wider(names_from = regime, values_from = n, values_fill = 0)
write_csv(xreg, file.path(OUT_DIR, "census_region_by_regime.csv"))

options(width = 150)
cat("\n(a) Delinquency by regime, untreated state-months",
    if (Y_LOG) "(log points; slopes log pts/yr)\n" else "(pp; slopes pp/yr)\n")
print(as.data.frame(part_a), digits = 3)
cat("\n(b) Baseline balance by regime\n"); print(as.data.frame(part_b), digits = 3)
cat("\nTreatment status by regime\n"); print(as.data.frame(xtab))
cat("\nCensus region by regime\n"); print(as.data.frame(xreg))
cat("\nJune-2022 switchers:\n"); print(as.data.frame(filter(status, status == "June-2022 design switcher") %>% select(state_abb, regime)))
