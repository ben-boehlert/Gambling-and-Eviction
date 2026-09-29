################################################################################
# mortgage_parallel_trends_blind_check.R  (2026-09-29)
#
# Blind look at parallel trends for the mortgage design: log 30-89 and 90+ day
# delinquency, June-2022 switchers (10) vs states untreated through 2025-03 (20).
# Switchers contribute ONLY months before launch - 6 (the blinded loader's
# anticipation rule); controls contribute everything. No post-launch outcome.
#   (1) Figure: group means of the log rate net of state and month FE, i.e. the
#       part a TWFE/LP-DiD design leaves for the switcher-control comparison.
#   (2) Differential linear trend (switcher x trend) with state + month FE,
#       state-clustered, in three eras: pre-COVID 2016-01..2020-02, recovery
#       2021-08..2022-05, and 2022-06+ (switchers' remaining pre-launch months).
# Run from the project root: Rscript analysis/diagnostics/mortgage_parallel_trends_blind_check.R
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(fixest)
  library(lubridate)
  library(ggplot2)
})
source("utils/eviction_treatment_schedule.R")
theme_set(theme_minimal(base_family = "serif"))

FILES <- c(`30-89 days` = "data/raw/StateMortgagesPercent-30-89DaysLate-thru-2025-03.csv",
           `90+ days`   = "data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv")
SWITCHERS <- c("DE", "FL", "KS", "KY", "MA", "MD", "ME", "NC", "OH", "VT")
DATA_END <- as.Date("2025-03-01")
COVID <- as.Date(c("2020-03-01", "2021-07-31"))
OUT_DIR <- "output/mortgage_parallel_trends_blind_check"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

read_bucket <- function(path, bucket) {
  mw <- read_csv(path, show_col_types = FALSE) %>% filter(RegionType == "State")
  mc <- grep("^\\d{4}-\\d{2}$", names(mw), value = TRUE)
  mw %>% select(Name, all_of(mc)) %>%
    pivot_longer(-Name, names_to = "m", values_to = "pct") %>%
    transmute(state_abb = eviction_state_name_to_abb(Name),
              date = as.Date(paste0(m, "-01")), y = log(as.numeric(pct)), bucket = bucket) %>%
    filter(!is.na(state_abb), date >= as.Date("2016-01-01"))
}
d0 <- bind_rows(Map(read_bucket, FILES, names(FILES))) %>%
  drop_pre_paspa_states("mortgage_parallel_trends_blind_check")
sched <- load_eviction_treatment_schedule("data/raw/sports_gambling_legalization_dates.csv",
                                          "online_start_date", states = unique(d0$state_abb))
controls <- sched %>% filter(is.na(treat_start) | treat_start > DATA_END) %>% pull(state_abb)

d <- d0 %>% filter(state_abb %in% c(SWITCHERS, controls)) %>%
  left_join(sched, by = "state_abb") %>%
  filter(!(state_abb %in% SWITCHERS) | date < treat_start %m-% months(6)) %>%
  filter(date < COVID[1] | date > COVID[2]) %>%
  mutate(switcher = as.integer(state_abb %in% SWITCHERS),
         group = if_else(switcher == 1, "Switchers (pre-launch months only)", "Controls"),
         era = case_when(date < COVID[1] ~ "pre-COVID 2016-01..2020-02",
                         date < as.Date("2022-06-01") ~ "recovery 2021-08..2022-05",
                         TRUE ~ "2022-06 on (switchers pre-launch)"),
         tr = as.numeric(date - as.Date("2016-01-01")) / 365.25)

# (1) residual after state + month FE, averaged by group
d <- d %>% group_by(bucket) %>%
  mutate(r = resid(feols(y ~ 1 | state_abb + date, data = pick(everything())), na.rm = FALSE)) %>%
  ungroup()
m <- d %>% filter(!is.na(r)) %>% group_by(bucket, group, date) %>%
  summarise(r = mean(r), n = n(), .groups = "drop")
p <- ggplot(m, aes(date, r, linetype = group)) +
  geom_hline(yintercept = 0, colour = "grey70") +
  geom_vline(xintercept = COVID, linetype = "dashed", colour = "grey60") +
  geom_vline(xintercept = as.Date("2022-06-01"), linetype = "dotted", colour = "grey40") +
  geom_line(linewidth = 0.5) +
  facet_wrap(~ bucket, ncol = 1) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  labs(x = NULL, y = "Log rate net of state and month FE", linetype = NULL) +
  theme(legend.position = "bottom")
ggsave("figures/mortgage_parallel_trends_blind_check.pdf", p, width = 6.5, height = 6)
ggsave("figures/mortgage_parallel_trends_blind_check.png", p, width = 6.5, height = 6, dpi = 300)

# (2) differential trend by era
tr <- d %>% group_by(bucket, era) %>% group_modify(function(x, k) {
  if (sum(x$switcher) < 12) return(tibble(diff_trend = NA_real_, se = NA_real_, p = NA_real_,
                                          n_switcher_states = n_distinct(x$state_abb[x$switcher == 1])))
  f <- feols(y ~ switcher:tr | state_abb + date, data = x, cluster = ~state_abb)
  tibble(diff_trend = unname(coef(f)[1]), se = unname(se(f)[1]), p = unname(pvalue(f)[1]),
         n_switcher_states = n_distinct(x$state_abb[x$switcher == 1]))
}) %>% ungroup()
write_csv(tr, file.path(OUT_DIR, "differential_trend_by_era.csv"))
write_csv(m, file.path(OUT_DIR, "group_mean_residuals.csv"))
options(width = 140)
print(as.data.frame(tr), digits = 3)
