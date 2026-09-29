################################################################################
# mortgage_never_switchers_over_time.R  (2026-09-29)
#
# 30-89 and 90+ day mortgage delinquency (CFPB, % of mortgages) for the states
# untreated through 2025-03 -- the mortgage design's control pool. NV out
# (always-treated). MO launches online 2025-12, after the data end, so it is
# untreated throughout and included. Blind-safe: no treated state-month enters.
#   figures/mortgage_never_switchers_over_time.{pdf,png}   state lines + mean, log scale
#   figures/mortgage_never_switchers_by_state.{pdf,png}    small multiples
# Run from the project root: Rscript analysis/visualization/mortgage_never_switchers_over_time.R
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
})
source("utils/eviction_treatment_schedule.R")
theme_set(theme_minimal(base_family = "serif"))

FILES <- c(`30-89 days` = "data/raw/StateMortgagesPercent-30-89DaysLate-thru-2025-03.csv",
           `90+ days`   = "data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv")
DATA_END <- as.Date("2025-03-01")
COVID <- as.Date(c("2020-03-01", "2021-07-31"))
DESIGN_START <- as.Date("2022-06-01")

read_bucket <- function(path, bucket) {
  mw <- read_csv(path, show_col_types = FALSE) %>% filter(RegionType == "State")
  mc <- grep("^\\d{4}-\\d{2}$", names(mw), value = TRUE)
  mw %>% select(Name, all_of(mc)) %>%
    pivot_longer(-Name, names_to = "m", values_to = "pct") %>%
    transmute(state_abb = eviction_state_name_to_abb(Name),
              date = as.Date(paste0(m, "-01")), pct = as.numeric(pct), bucket = bucket) %>%
    filter(!is.na(state_abb), date >= as.Date("2016-01-01"))
}
d <- bind_rows(Map(read_bucket, FILES, names(FILES))) %>%
  drop_pre_paspa_states("mortgage_never_switchers_over_time")

sched <- load_eviction_treatment_schedule("data/raw/sports_gambling_legalization_dates.csv",
                                          "online_start_date", states = unique(d$state_abb))
never <- sched %>% filter(is.na(treat_start) | treat_start > DATA_END) %>% pull(state_abb)
cov <- read_csv("data/processed/state_covariates_2019.csv", show_col_types = FALSE)
nv <- d %>% filter(state_abb %in% never) %>%
  left_join(select(cov, state_abb, judicial_only), by = "state_abb") %>%
  mutate(regime = if_else(judicial_only == 1, "Judicial", "Non-judicial"))
stopifnot(!anyNA(nv$pct), n_distinct(nv$state_abb) == length(never))
avg <- nv %>% group_by(bucket, date) %>% summarise(pct = mean(pct), .groups = "drop")

shade <- list(
  # dropped COVID window as dashed lines (a -Inf rectangle is NaN on a log axis)
  geom_vline(xintercept = COVID, linetype = "dashed", colour = "grey60"),
  geom_vline(xintercept = DESIGN_START, linetype = "dotted", colour = "grey40"),
  NULL)  # dotted line = June-2022 design start

p1 <- ggplot(nv, aes(date, pct)) + shade +
  geom_line(aes(group = state_abb, linetype = regime), colour = "grey55", linewidth = 0.3) +
  geom_line(data = avg, colour = "black", linewidth = 0.9) +
  facet_wrap(~ bucket, ncol = 1, scales = "free_y") +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  scale_y_log10() +
  labs(x = NULL, y = "% of mortgages delinquent (log scale)", linetype = NULL) +
  theme(legend.position = "bottom")
ggsave("figures/mortgage_never_switchers_over_time.pdf", p1, width = 6.5, height = 7)
ggsave("figures/mortgage_never_switchers_over_time.png", p1, width = 6.5, height = 7, dpi = 300)

p2 <- ggplot(nv, aes(date, pct, linetype = bucket)) + shade +
  geom_line(linewidth = 0.35) +
  facet_wrap(~ state_abb, ncol = 5) +
  scale_y_log10() +
  scale_x_date(date_breaks = "3 years", date_labels = "%Y") +
  labs(x = NULL, y = "% of mortgages delinquent (log scale)", linetype = NULL) +
  theme(legend.position = "bottom", panel.spacing = unit(0.6, "lines"))
ggsave("figures/mortgage_never_switchers_by_state.pdf", p2, width = 9, height = 8)
ggsave("figures/mortgage_never_switchers_by_state.png", p2, width = 9, height = 8, dpi = 300)
message("never-switchers (", length(never), "): ", paste(sort(never), collapse = " "))
