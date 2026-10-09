################################################################################
# build_mortgage3089_panel.R  (2026-09-29)
#
# State-month 30-89 day mortgage delinquency panel for the blinded power
# framework (config key `mortgage_panel`; loader level `state_mortgage` reads
# state_abb, month_date, delinquency_rate). Same layout as the 90+ file
# data/processed/mortgage_treatment_panel.csv. Rate in percentage points; the
# framework builds y_pp and y_log_pp from it. Treatment columns follow the
# online_start_date schedule for reference only (the loader uses the schedule).
# Input:  data/raw/StateMortgagesPercent-30-89DaysLate-thru-2025-03.csv (CFPB)
# Output: data/processed/mortgage3089_treatment_panel.csv
# Run from the project root: Rscript data_prep/build_mortgage3089_panel.R
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
})
source("utils/eviction_treatment_schedule.R")

# MORT_FILE / OUT_FILE env (2026-10-09): defaults unchanged (30-89). Set
#   MORT_FILE=data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv
#   OUT_FILE=data/processed/mortgage_treatment_panel.csv
# to rebuild the 90+ panel on the CURRENT schedule (the 2026-01-23 build of that
# file predates the 2026-08-10 schedule repair and lacks DE FL KY ME NC VT MO).
IN  <- Sys.getenv("MORT_FILE", "data/raw/StateMortgagesPercent-30-89DaysLate-thru-2025-03.csv")
OUT <- Sys.getenv("OUT_FILE",  "data/processed/mortgage3089_treatment_panel.csv")

mw <- read_csv(IN, show_col_types = FALSE) %>% filter(RegionType == "State")
mc <- grep("^\\d{4}-\\d{2}$", names(mw), value = TRUE)
p <- mw %>% select(Name, FIPSCode, all_of(mc)) %>%
  pivot_longer(all_of(mc), names_to = "m", values_to = "delinquency_rate") %>%
  transmute(state_abb = eviction_state_name_to_abb(Name),
            month_date = as.Date(paste0(m, "-01")),
            delinquency_rate = as.numeric(delinquency_rate),
            log_delinquency_rate = log(delinquency_rate),
            fips_numeric = as.integer(gsub("'", "", FIPSCode)))  # CFPB quotes FIPS as '01'
sched <- load_eviction_treatment_schedule("data/raw/sports_gambling_legalization_dates.csv",
                                          "online_start_date", states = unique(p$state_abb))
p <- p %>% left_join(rename(sched, treatment_date = treat_start), by = "state_abb") %>%
  mutate(treated = !is.na(treatment_date) & month_date >= treatment_date) %>%
  select(state_abb, month_date, delinquency_rate, log_delinquency_rate,
         treatment_date, treated, fips_numeric) %>%
  arrange(state_abb, month_date)
stopifnot(!anyNA(p$state_abb), !anyDuplicated(p[c("state_abb", "month_date")]),
          all(p$delinquency_rate > 0))
write_csv(p, OUT)
message("wrote ", OUT, ": ", nrow(p), " rows, ", n_distinct(p$state_abb), " states")
