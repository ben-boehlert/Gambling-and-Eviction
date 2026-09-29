################################################################################
# mortgage_covariate_noise_reduction.R  (2026-09-29)
#
# How much do the four locked/selected mortgage covariates (judicial flag, 2019
# unemployment, HPI growth 2016Q4-19Q4, age 65+; z-scored) reduce residual noise
# in the log delinquency rate beyond state + month FE? Untreated state-months
# only (cut at launch - 6), 2016+, residual-pool COVID exclusion [2020-03, 2021-06)
# as in the application-era sim. Blind: no post-launch outcome.
# Specs: FE only; + covariates x linear trend; + covariates x month FE.
# Metrics: df-adjusted residual SD, AR(1), SD of a 12-month-vs-3-month contrast.
# Run from the project root: Rscript analysis/diagnostics/mortgage_covariate_noise_reduction.R
################################################################################

suppressPackageStartupMessages({library(dplyr);library(tidyr);library(readr);library(fixest);library(lubridate)})
source("utils/eviction_treatment_schedule.R")
cov <- read_csv("data/processed/state_covariates_2019.csv", show_col_types=FALSE) %>%
  mutate(across(c(unemp_2019, hpi_growth_2016q4_2019q4, age65_pct), ~ (.x-mean(.x))/sd(.x)))
sched <- load_eviction_treatment_schedule("data/raw/sports_gambling_legalization_dates.csv","online_start_date", states=cov$state_abb)
run <- function(file, label) {
  mw <- read_csv(file, show_col_types=FALSE) %>% filter(RegionType=="State")
  mc <- grep("^\\d{4}-\\d{2}$", names(mw), value=TRUE)
  d <- mw %>% select(Name, all_of(mc)) %>% pivot_longer(-Name, names_to="m", values_to="y") %>%
    transmute(state_abb=eviction_state_name_to_abb(Name), month_date=as.Date(paste0(m,"-01")), y=log(as.numeric(y))) %>%
    filter(!is.na(state_abb), month_date>=as.Date("2016-01-01"), state_abb!="NV",
           !(month_date>=as.Date("2020-03-01") & month_date<as.Date("2021-06-01"))) %>%
    left_join(sched, by="state_abb") %>%
    filter(is.na(treat_start) | month_date < treat_start %m-% months(6)) %>%
    left_join(cov, by="state_abb") %>% filter(!is.na(judicial_only)) %>%
    mutate(tr = as.numeric(month_date - as.Date("2016-01-01"))/365.25)
  specs <- list(
    `FE only`                 = y ~ 1 | state_abb + month_date,
    `+ covariates x trend`    = y ~ judicial_only:tr + unemp_2019:tr + hpi_growth_2016q4_2019q4:tr + age65_pct:tr | state_abb + month_date,
    `+ covariates x month FE` = y ~ 1 | state_abb + month_date + month_date[judicial_only, unemp_2019, hpi_growth_2016q4_2019q4, age65_pct])
  bind_rows(lapply(names(specs), function(nm) {
    f <- feols(specs[[nm]], data=d)
    r <- resid(f, na.rm=FALSE); k <- f$nparams
    dd <- d %>% mutate(r=r) %>% filter(!is.na(r)) %>% arrange(state_abb, month_date) %>% group_by(state_abb) %>% mutate(rl=lag(r)) %>% ungroup()
    rho <- unname(coef(lm(r ~ rl, dd))[2])
    ld <- dd %>% group_by(state_abb) %>% summarise(v = if (n()>=30) mean(tail(r,12)) - mean(head(tail(r,27),3)) else NA_real_, .groups="drop")
    tibble(outcome=label, spec=nm, n=nrow(dd), params=k,
           resid_sd_dfadj = sqrt(sum(dd$r^2)/(nrow(dd)-k)), ar1=rho, sd_long_diff=sd(ld$v, na.rm=TRUE))
  }))
}
out <- bind_rows(run("data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv","90+"),
                 run("data/raw/StateMortgagesPercent-30-89DaysLate-thru-2025-03.csv","30-89")) %>%
  group_by(outcome) %>% mutate(sd_ratio_vs_FE = resid_sd_dfadj/resid_sd_dfadj[1], ld_ratio_vs_FE = sd_long_diff/sd_long_diff[1]) %>% ungroup()
print(as.data.frame(out), digits=3)
dir.create("output/mortgage_covariate_noise_reduction", recursive = TRUE, showWarnings = FALSE)
write_csv(out, "output/mortgage_covariate_noise_reduction/noise_by_spec.csv")
