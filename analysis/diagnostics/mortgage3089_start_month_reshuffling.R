################################################################################
# mortgage3089_start_month_reshuffling.R  (2026-09-29)
#
# Start month for a post-COVID 30-89 day mortgage panel. The 12-month-growth
# dispersion check is contaminated until 2022-07 (its lag reaches into COVID),
# so this measures reshuffling instead: each state's log rate relative to the
# cross-state mean (month FE removed), and the cross-state SD of its 6-month
# change, against the 2016-07..2020-02 band. All states, NV out, blind.
# Caveat: rounding (0.1pp) inflates the measure more at post-COVID levels (~1pp)
# than pre-COVID (~2pp).
# Run from the project root: Rscript analysis/diagnostics/mortgage3089_start_month_reshuffling.R
################################################################################

suppressPackageStartupMessages({library(dplyr);library(tidyr);library(readr)})
source("utils/eviction_treatment_schedule.R")
mw <- read_csv("data/raw/StateMortgagesPercent-30-89DaysLate-thru-2025-03.csv", show_col_types=FALSE) %>% filter(RegionType=="State")
mc <- grep("^\\d{4}-\\d{2}$", names(mw), value=TRUE)
d <- mw %>% select(Name, all_of(mc)) %>% pivot_longer(-Name, names_to="m", values_to="y") %>%
  transmute(s=eviction_state_name_to_abb(Name), t=as.Date(paste0(m,"-01")), y=log(as.numeric(y))) %>%
  filter(!is.na(s), s!="NV", t>=as.Date("2016-01-01"))
# state position relative to the cross-state mean each month (removes month FE)
d <- d %>% group_by(t) %>% mutate(rel = y - mean(y)) %>% ungroup()
# reshuffling: cross-state SD of the 6-month change in relative position
d <- d %>% arrange(s,t) %>% group_by(s) %>% mutate(ch6 = rel - lag(rel,6)) %>% ungroup()
z <- d %>% group_by(t) %>% summarise(mean_pct=round(mean(exp(y)),2), sd_ch6=sd(ch6,na.rm=TRUE), .groups="drop")
pre <- z %>% filter(t>=as.Date("2016-07-01"), t<as.Date("2020-03-01"))
cat("pre-COVID 6-month reshuffling SD: median", round(median(pre$sd_ch6),3), " p90", round(quantile(pre$sd_ch6,.9),3), "\n")
cat("level trough month:", format(z$t[which.min(z$mean_pct)]), "\n")
print(as.data.frame(z %>% filter(t>=as.Date("2020-12-01"), t<=as.Date("2023-06-01")) %>% mutate(t=format(t,"%Y-%m"), sd_ch6=round(sd_ch6,3), above_p90 = sd_ch6 > quantile(pre$sd_ch6,.9))), row.names=FALSE)
dir.create("output/mortgage3089_start_month_reshuffling", recursive = TRUE, showWarnings = FALSE)
write_csv(z, "output/mortgage3089_start_month_reshuffling/reshuffling_by_month.csv")
