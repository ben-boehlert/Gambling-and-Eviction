################################################################################
# analysis/diagnostics/ddd_h_rule_balance.R  (2026-09-14)
#
# What does each candidate H rule actually select? Blindness-safe: poverty is a
# covariate and the pre-period filing rate is computed from the blinded
# (untreated-only) skeleton, restricted to months before 2020-03.
#
# Read the output as: a defensible POVERTY contrast has a large poverty_gap,
# a renter_share_hi near 0.5, and size_ratio / evrate_ratio near 1.
#
# Output: output/ddd_power/h_rule_balance.csv
################################################################################

suppressPackageStartupMessages({library(dplyr); library(readr); library(purrr)})
source("R/power/ddd_power.R")

cfg <- read_power_config("config/power_primary.yml")
OUT <- file.path("output", "ddd_power")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

rows <- map_dfr(DDD_H_RULES, function(r) {
  message("h_rule: ", r)
  sk <- build_ddd_skeleton(covid = "drop", h_rule = r, config = cfg)
  ddd_h_balance(sk) %>% mutate(n_counties = n_distinct(sk$unit_id), .after = n_states)
})

write_csv(rows, file.path(OUT, "h_rule_balance.csv"))
print(as.data.frame(rows), row.names = FALSE, digits = 3)
message("\nwrote ", file.path(OUT, "h_rule_balance.csv"))
