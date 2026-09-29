################################################################################
# build_mortgage_twfe_sim_inputs.R  (2026-09-29)
#
# Inputs for running the application-era AR(1) TWFE power sim
# (analysis/main/power_simulation_twfe_statepanel_staggered_parallel_fixed.R)
# on the 90+ day mortgage delinquency rate, so the mortgage MDE comes from the
# same machine as the eviction side's 5.5-6% (twfe_power_rerun_noMNWA_v20260922).
#
# The sim is used UNCHANGED. Its OUTCOME=log1p_rate branch computes
# log(filings_per_1k_renters + RATE_EPS); the launcher sets RATE_EPS=0 and this
# script puts the delinquency rate (pp) in that column, so y = log(rate).
# filings_count and renters are NA (only the log1p_filings_count outcome and
# UNIT_WEIGHTS=renters read them; neither is used).
#
# Treatment = online_start_date (the eviction run's definition), from the
# canonical schedule; never-legalizers have no date. NV (always-treated) is
# excluded. DC has no entry in the sim's state-name lookup and drops there, as
# in the eviction inputs.
#
# Output: output/twfe_power_mortgage_v20260929/inputs/{data_state_rows,treat_state_month}.csv
# Run from the project root:  Rscript data_prep/build_mortgage_twfe_sim_inputs.R
#   30-89 day: MORT_FILE=data/raw/StateMortgagesPercent-30-89DaysLate-thru-2025-03.csv \
#              OUT_DIR=output/twfe_power_mortgage3089_v20260929/inputs Rscript data_prep/build_mortgage_twfe_sim_inputs.R
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
})
source("utils/eviction_treatment_schedule.R")

# MORT_FILE / OUT_DIR env vars select the delinquency bucket (default 90+,
# byte-identical to the first run); 2026-09-29 adds the 30-89 day file.
MORT_FILE  <- Sys.getenv("MORT_FILE", "data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv")
SCHED_FILE <- "data/raw/sports_gambling_legalization_dates.csv"
OUT_DIR    <- Sys.getenv("OUT_DIR", "output/twfe_power_mortgage_v20260929/inputs")
PANEL_START <- as.Date("2016-01-01")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

mw <- read_csv(MORT_FILE, show_col_types = FALSE) %>% filter(RegionType == "State")
month_cols <- grep("^\\d{4}-\\d{2}$", names(mw), value = TRUE)
mort <- mw %>%
  select(Name, all_of(month_cols)) %>%
  pivot_longer(-Name, names_to = "m", values_to = "rate_pp") %>%
  transmute(state_name = Name, state_abb = eviction_state_name_to_abb(Name),
            month_date = as.Date(paste0(m, "-01")), rate_pp = as.numeric(rate_pp)) %>%
  filter(!is.na(state_abb), !is.na(rate_pp), month_date >= PANEL_START) %>%
  drop_pre_paspa_states("build_mortgage_twfe_sim_inputs")
stopifnot(all(mort$rate_pp > 0), !anyDuplicated(mort[c("state_abb", "month_date")]))

data_rows <- mort %>%
  transmute(geo_level = "state", geo_id = state_name, fips = NA, month_date,
            filings_count = NA_real_, renter_occupied_housing_units = NA_real_,
            filings_per_1k_renters = rate_pp)

sched <- load_eviction_treatment_schedule(SCHED_FILE, "online_start_date",
                                          states = unique(mort$state_abb))
treat_rows <- mort %>%
  select(state_abb, month_date) %>%
  left_join(sched, by = "state_abb") %>%
  mutate(treated = !is.na(treat_start) & month_date >= treat_start)

write_csv(data_rows, file.path(OUT_DIR, "data_state_rows.csv"), na = "NA")
write_csv(treat_rows, file.path(OUT_DIR, "treat_state_month.csv"), na = "NA")
message(sprintf("wrote %d state-months, %d states (%d with an online date <= %s)",
                nrow(data_rows), n_distinct(mort$state_abb),
                sum(!is.na(sched$treat_start) & sched$treat_start <= max(mort$month_date)),
                format(max(mort$month_date))))
