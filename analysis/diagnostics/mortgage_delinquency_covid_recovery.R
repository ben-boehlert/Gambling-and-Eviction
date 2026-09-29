################################################################################
# mortgage_delinquency_covid_recovery.R  (2026-09-29)
#
# When do 30-89 and 90+ day mortgage delinquency return to pre-COVID behaviour?
# Same logic as the eviction recovery check (cross_state_dispersion_recovery.R):
# cross-state SD of 12-month log growth vs its 2017-01..2020-02 90th percentile;
# first month at/below it from 2021-08; first run of six consecutive months;
# plus the cross-state mean level vs its pre-COVID 10th percentile. All states
# (NV out), no treatment split -- blind.
# Run from the project root: Rscript analysis/diagnostics/mortgage_delinquency_covid_recovery.R
################################################################################

suppressPackageStartupMessages({library(dplyr);library(tidyr);library(readr)})
source("utils/eviction_treatment_schedule.R")
rec <- function(file, label) {
  mw <- read_csv(file, show_col_types=FALSE) %>% filter(RegionType=="State")
  mc <- grep("^\\d{4}-\\d{2}$", names(mw), value=TRUE)
  d <- mw %>% select(Name, all_of(mc)) %>% pivot_longer(-Name, names_to="m", values_to="y") %>%
    transmute(state_abb=eviction_state_name_to_abb(Name), month=as.Date(paste0(m,"-01")), y=as.numeric(y)) %>%
    filter(!is.na(state_abb), state_abb!="NV", month>=as.Date("2016-01-01"))
  g <- d %>% arrange(state_abb, month) %>% group_by(state_abb) %>% mutate(g12=log(y)-lag(log(y),12)) %>% ungroup() %>%
    group_by(month) %>% summarise(mean_pp=mean(y), sd_g12=sd(g12, na.rm=TRUE), .groups="drop")
  pre <- g %>% filter(month>=as.Date("2017-01-01"), month<as.Date("2020-03-01"))
  ceil <- quantile(pre$sd_g12, .9); lvl_pre <- mean(pre$mean_pp)
  lvl_lo <- quantile(pre$mean_pp, .1)
  post <- g %>% filter(month>=as.Date("2021-08-01"))
  first_ok <- post$month[which(post$sd_g12 <= ceil)[1]]
  ok <- post$sd_g12 <= ceil; run6 <- NA
  for (i in seq_along(ok)) if (i>=6 && all(ok[(i-5):i])) { run6 <- post$month[i-5]; break }
  lvl_back <- post$month[which(post$mean_pp >= lvl_lo)[1]]
  cat(sprintf("\n== %s: pre-COVID (2017-01..2020-02) mean level %.2fpp (10th pct %.2f); dispersion ceiling (p90) %.3f\n", label, lvl_pre, lvl_lo, ceil))
  cat(sprintf("   first month >= 2021-08 with dispersion <= ceiling: %s | first run of 6 consecutive: starts %s | level back to pre-COVID 10th pct: %s\n",
              format(first_ok), format(run6), format(lvl_back)))
  q <- g %>% filter(month>=as.Date("2019-12-01"), format(month,"%m") %in% c("03","06","09","12")) %>%
    transmute(month=format(month,"%Y-%m"), mean_pp=round(mean_pp,2), sd_g12=round(sd_g12,3), above_ceiling = sd_g12 > ceil)
  q
}
a <- rec("data/raw/StateMortgagesPercent-30-89DaysLate-thru-2025-03.csv", "30-89 day")
b <- rec("data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv", "90+ day")
cat("\nQuarter-end months (all 50 states excl. NV incl. DC; no treatment split):\n")
print(as.data.frame(full_join(rename(a, mean_3089=mean_pp, disp_3089=sd_g12, above_3089=above_ceiling),
                              rename(b, mean_90=mean_pp, disp_90=sd_g12, above_90=above_ceiling), by="month")), row.names=FALSE)
dir.create("output/mortgage_delinquency_covid_recovery", recursive = TRUE, showWarnings = FALSE)
write_csv(bind_rows(mutate(a, outcome = "30-89"), mutate(b, outcome = "90+")), "output/mortgage_delinquency_covid_recovery/quarter_end_recovery.csv")
