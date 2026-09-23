# =============================================================================
# county_vs_state_arm_coverage.R  (2026-09-14)
#
#   Rscript analysis/diagnostics/county_vs_state_arm_coverage.R
#
# Option C from the 2026-09-14 composition discussion: before changing any
# estimator, quantify what the COUNTY LP-DiD arm actually buys and costs
# against the STATE arm, on the CURRENT headline design
# (power_lpdid_shift12_clean_gate_ewatt_pmd6.yml: S2, covid drop, shift12,
# ex NV/ID/HI/MS).
#
# The trade:
#   GAIN  county keeps Miami-Dade, Harris, Rutherford, Ada, Kanawha -- every
#         county excluded from a state's fixed basket (the basket is a
#         state-aggregation device; the county reader applies none).
#   COST  the county download carries only LSC states. Every state the panel
#         gets from a court source (MD, NC, NH, WI) or the ETS internal
#         extract (LA, MA, MO, NM, NV, RI) vanishes -- and clusters, not
#         observations, are the binding power constraint.
#
# This reports the exchange rate in CLUSTERS, which is the currency that
# matters. It runs no simulation.
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(lubridate)})
source("R/power/config.R"); source("R/power/load_blinded_panel.R")
source("utils/eviction_treatment_schedule.R")

EXCLUDE   <- c("NV", "ID", "HI", "MS")
SCHEDULE  <- "data/processed/shift12_schedule.csv"
TREAT_DEF <- "shift12_start_date"
cfg <- read_power_config()

load_arm <- function(level, covid) {
  load_blinded_panel(level = level, sample = "S2", covid = covid,
                     treat_def = TREAT_DEF, anticipation = 6,
                     config = modifyList(cfg, list(schedule = SCHEDULE))) %>%
    filter(!state_abb %in% EXCLUDE)
}

sched <- read_csv(SCHEDULE, show_col_types = FALSE)
gcol  <- intersect(c(TREAT_DEF, "shift12_start_date", "g_first"), names(sched))[1]
name2abb <- setNames(c(state.abb, "DC"), c(state.name, "District of Columbia"))
sched <- sched %>%
  mutate(state_abb = if ("state_abb" %in% names(.)) .data$state_abb
                     else unname(name2abb[as.character(.data$state)])) %>%
  transmute(state_abb, g = as.Date(.data[[gcol]])) %>%
  filter(!is.na(state_abb))

summarise_arm <- function(p, level, covid) {
  st <- p %>% group_by(state_abb) %>%
    summarise(units = n_distinct(unit_id), months = n_distinct(month_date),
              first = min(month_date), last = max(month_date), .groups = "drop") %>%
    left_join(sched, by = "state_abb") %>%
    mutate(role = case_when(is.na(g) ~ "never-treated",
                            g >= first & g <= last ~ "SWITCHER in window",
                            TRUE ~ "treated outside window"))
  tibble(level = level, covid = covid,
         states = nrow(st), units = sum(st$units),
         switchers = sum(st$role == "SWITCHER in window"),
         controls  = sum(st$role != "SWITCHER in window")) %>%
    list(summary = ., by_state = st %>% mutate(level = level, covid = covid))
}

out <- map(c("drop", "post"), function(cv) {
  s <- summarise_arm(load_arm("state",  cv), "state",  cv)
  c_ <- summarise_arm(load_arm("county", cv), "county", cv)
  list(sum = bind_rows(s$summary, c_$summary),
       by  = bind_rows(s$by_state, c_$by_state))
})

summ <- map_dfr(out, "sum")
bys  <- map_dfr(out, "by")

cat("\n== Arm size under the headline design (ex NV/ID/HI/MS) ==\n")
print(summ, n = Inf)

cat("\n== States the COUNTY arm loses relative to the STATE arm ==\n")
for (cv in unique(bys$covid)) {
  b <- bys %>% filter(covid == cv)
  lost <- setdiff(b$state_abb[b$level == "state"], b$state_abb[b$level == "county"])
  lost_tab <- b %>% filter(level == "state", state_abb %in% lost) %>%
    select(state_abb, role, months, first, last) %>% arrange(role, state_abb)
  cat("\ncovid =", cv, "-- lost states:", length(lost), "\n")
  print(lost_tab, n = Inf)
  cat("  of which SWITCHERS lost:",
      sum(lost_tab$role == "SWITCHER in window"), "\n")
}

write_csv(summ, "data/processed/county_vs_state_arm_summary.csv")
write_csv(bys,  "data/processed/county_vs_state_arm_by_state.csv")
cat("\nWrote data/processed/county_vs_state_arm_{summary,by_state}.csv\n")
