################################################################################
# mortgage_covariate_balance_screen.R  (2026-09-29)
#
# Step 3 of the mortgage covariate rule (Ben, 2026-09-29):
#   CORE (locked on theory): judicial-only foreclosure flag, 2019 unemployment
#     rate, house-price growth 2016Q4-2019Q4.
#   CANDIDATES enter only if |SMD| >= 0.25 between the June-2022 design's
#     switchers and its controls; total covariates capped at 4, so at most one
#     candidate joins; ties broken by largest |SMD|.
# Design: June-2022 start, 6-18 horizons, pmd 3, K = 7 -> 10 switchers; controls
# are the states untreated through 2025-03. NV excluded.
#
# BLIND: covariates are 2019 aggregates; the only outcome information is the
# pre-COVID (2016-2019) delinquency level and trend, reported for information
# and never a candidate.
#
# Run from the project root:
#   Rscript analysis/diagnostics/mortgage_covariate_balance_screen.R
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
})
source("utils/eviction_treatment_schedule.R")

COV_FILE   <- "data/processed/state_covariates_2019.csv"
SCHED_FILE <- "data/raw/sports_gambling_legalization_dates.csv"
MORT_FILE  <- "data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv"
OUT_DIR    <- "output/mortgage_covariate_balance_screen"
SMD_THRESHOLD <- 0.25
MAX_COVARIATES <- 4
DATA_END <- as.Date("2025-03-01")
SWITCHERS <- c("DE", "FL", "KS", "KY", "MA", "MD", "ME", "NC", "OH", "VT")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

core <- c(judicial_only = "Judicial-only foreclosure state",
          unemp_2019 = "Unemployment rate 2019 (%)",
          hpi_growth_2016q4_2019q4 = "House-price growth 2016Q4-2019Q4 (%)")
candidates <- c(med_hh_income = "Median household income ($)",
                owner_occ_pct = "Owner-occupied (%)",
                age65_pct = "Age 65+ (%)",
                ba_plus_pct = "BA or higher (%)",
                black_pct = "Black (%)",
                hispanic_pct = "Hispanic (%)",
                fha_va_share_2019 = "FHA/VA share of 2019 originations (%)")

cov <- read_csv(COV_FILE, show_col_types = FALSE) %>%
  drop_pre_paspa_states("balance_screen")
sched <- load_eviction_treatment_schedule(SCHED_FILE, "online_start_date",
                                          states = cov$state_abb)
controls <- sched %>%
  filter(is.na(treat_start) | treat_start > DATA_END) %>% pull(state_abb)
stopifnot(!length(intersect(controls, SWITCHERS)), length(SWITCHERS) == 10)

# Pre-COVID delinquency level and trend (information only).
mw <- read_csv(MORT_FILE, show_col_types = FALSE) %>% filter(RegionType == "State")
mc <- grep("^(2016|2017|2018|2019)-\\d{2}$", names(mw), value = TRUE)
pre <- mw %>% select(Name, all_of(mc)) %>%
  pivot_longer(-Name, names_to = "m", values_to = "y") %>%
  transmute(state_abb = eviction_state_name_to_abb(Name),
            t = as.numeric(as.Date(paste0(m, "-01"))), y = as.numeric(y)) %>%
  filter(state_abb %in% c(SWITCHERS, controls)) %>%
  group_by(state_abb) %>%
  summarise(delinq_2016_2019_mean = mean(y),
            delinq_2016_2019_slope = unname(coef(lm(y ~ t))[2]) * 365.25,
            .groups = "drop")

d <- cov %>% filter(state_abb %in% c(SWITCHERS, controls)) %>%
  left_join(pre, by = "state_abb") %>%
  mutate(group = if_else(state_abb %in% SWITCHERS, "switcher", "control"))
stopifnot(sum(d$group == "switcher") == 10, sum(d$group == "control") == length(controls))

balance_row <- function(v, label, role) {
  s <- d[[v]][d$group == "switcher"]; c <- d[[v]][d$group == "control"]
  tibble(role = role, variable = label, mean_switchers = mean(s),
         mean_controls = mean(c), diff = mean(s) - mean(c),
         smd = (mean(s) - mean(c)) / sqrt((var(s) + var(c)) / 2),
         p_welch = t.test(s, c)$p.value)
}
tab <- bind_rows(c(
  Map(balance_row, names(core), core, "core"),
  Map(balance_row, names(candidates), candidates, "candidate"),
  list(balance_row("delinq_2016_2019_mean", "90+ delinquency, 2016-19 mean (pp)",
                   "info: pre-COVID outcome"),
       balance_row("delinq_2016_2019_slope", "90+ delinquency, 2016-19 trend (pp/yr)",
                   "info: pre-COVID outcome"))
))

slots <- MAX_COVARIATES - length(core)
passing <- tab %>% filter(role == "candidate", abs(smd) >= SMD_THRESHOLD) %>%
  arrange(desc(abs(smd)))
selected <- head(passing$variable, slots)
tab <- tab %>% mutate(
  passes_threshold = role == "candidate" & abs(smd) >= SMD_THRESHOLD,
  selected = role == "core" | variable %in% selected)

write_csv(tab, file.path(OUT_DIR, "balance_switchers_vs_controls.csv"))
write_csv(tibble(group = c("switcher", "control"),
                 states = c(paste(sort(SWITCHERS), collapse = " "),
                            paste(sort(controls), collapse = " "))),
          file.path(OUT_DIR, "groups.csv"))

options(width = 160)
cat("Switchers (", length(SWITCHERS), "): ", paste(sort(SWITCHERS), collapse = " "), "\n", sep = "")
cat("Controls  (", length(controls), "): ", paste(sort(controls), collapse = " "), "\n\n", sep = "")
print(as.data.frame(tab), digits = 3)
cat("\nCandidates passing |SMD| >=", SMD_THRESHOLD, ":", nrow(passing),
    "| slots:", slots, "| selected:", if (length(selected)) paste(selected, collapse = "; ") else "none", "\n")
