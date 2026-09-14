# =============================================================================
# eligibility_window_feasibility.R  (2026-09-14)
#
# Does the D1 pseudo-schedule still PLACE once the eligibility window is
# corrected to match what the event_clean anchor actually needs?
#
# `.eligible_states()` admits a state on coverage over [d - min_pre, d + min_post].
# The headline config used min_pre=12 / min_post=6, but event_clean needs
# [d-18, d+12]: d is the shift12 date (launch+12), the strict PMD=6 baseline
# reaches back to launch-6 = d-18, and outcomes run to launch+24 = d+12.
# Over-admitted states are never rejected -- they silently contribute no cells.
#
# Tightening eligibility shrinks the pool, so `.assign_cohorts()` may fail to
# fill the late cohorts. This script runs the real `make_pseudo_schedule()`
# under both windows, on many seeds, and reports the failure rate.
#
# No estimation: blindness-safe.
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(lubridate); library(glue)})
source("R/power/config.R"); source("R/power/blindness_checks.R")
source("R/power/load_blinded_panel.R"); source("R/power/make_pseudo_schedules.R")

CFG <- "config/power_lpdid_clean_gate_ewatt_pmd6_v20260914.yml"
cfg <- read_power_config(CFG)
panel <- load_blinded_panel(level = "state", treat_def = "shift12_start_date",
                            sample = "S2", covid = "drop", config = cfg) %>%
  filter(!state_abb %in% cfg$exclude_states)   # exclude_states is applied by the grid, not the loader
real <- read_csv(cfg$schedule, show_col_types = FALSE)
cat(glue("panel: {n_distinct(panel$state_abb)} states, ",
         "{format(min(panel$month_date),'%Y-%m')}..{format(max(panel$month_date),'%Y-%m')}"), "\n\n")

SEEDS <- cfg$base_seed + 10007L * (1:25)
try_one <- function(seed, mp, mq) {
  out <- tryCatch(
    make_pseudo_schedule(design = "D1", panel = panel, real_schedule = real,
                         treat_def = "shift12_start_date",
                         min_pre = mp, min_post = mq, seed = seed,
                         template = "panel"),
    error = function(e) structure(NA, err = conditionMessage(e)))
  if (isTRUE(is.na(out[1])) && !is.null(attr(out, "err")))
    return(list(ok = FALSE, msg = attr(out, "err"), n = NA_integer_))
  list(ok = TRUE, msg = NA_character_,
       n = sum(!is.na(out[[grep("start|_g$", names(out), value = TRUE)[1]]])))
}

GRID <- list(c(12L,6L),c(12L,9L),c(12L,12L),c(15L,6L),c(15L,9L),c(15L,12L),c(18L,6L),c(18L,9L),c(18L,12L))
for (w in GRID) {
  lab <- glue("min_pre={w[1]}, min_post={w[2]}")
  res <- map(SEEDS, try_one, mp = w[1], mq = w[2])
  ok  <- map_lgl(res, "ok")
  ns  <- map_int(res, "n")
  cat(glue("{lab}  ->  placed {sum(ok)}/{length(ok)} seeds"), "\n")
  if (any(ok)) cat(glue("      treated states placed: median {median(ns[ok], na.rm=TRUE)} ",
                        "(range {min(ns[ok],na.rm=TRUE)}-{max(ns[ok],na.rm=TRUE)})"), "\n")
  if (any(!ok)) {
    msgs <- unique(map_chr(res[!ok], "msg"))
    cat("      FAILURES:\n")
    for (m in head(msgs, 2)) cat("        ", str_trunc(m, 300), "\n")
  }
  cat("\n")
}
