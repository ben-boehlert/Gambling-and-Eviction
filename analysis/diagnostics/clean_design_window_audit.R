################################################################################
# analysis/diagnostics/clean_design_window_audit.R  (2026-09-14)
#
# CANONICAL audit of which states the clean LP-DiD design can actually use, and
# how that set responds to the COVID drop boundary. Supersedes the hand-derived
# switcher counts that had been maintained in prose.
#
# ------------------------------------------------------------------ WHY -----
# The window convention is easy to get wrong and the error is silent. Under
# `lpdid_anchor: event_clean` the two windows are anchored on DIFFERENT dates:
#
#   baseline : [launch - pmd, launch - 1]         indexed at pseudo_LAUNCH
#   outcome  : [g + hmin, g + hmax], g = launch+12  indexed at pseudo_g
#
# so with pmd = 6, hmin = 0, hmax = 12 the design is
#
#   baseline [launch-6, launch-1]   outcome [launch+12, launch+24]
#
# Anchoring BOTH windows on shift12 (= launch + 12) places each of them twelve
# months too late and silently returns the wrong switcher set — it reports MI
# as outcome-blocked when MI is in fact baseline-blocked with a complete
# outcome window. This script therefore DERIVES the windows from the config and
# ASSERTS the invariants rather than hardcoding month offsets.
#
# Source of truth: config/power_lpdid_clean_gate_ewatt_pmd6_v20260914.yml
# (`lpdid_anchor`, `lpdid_pmd`, `lpdid_hmin`, `lpdid_post`, `treat_def`) and
# the `event_clean` branch of `.re_lpdid()` in R/power/run_estimators.R, where
# the outcome is `Y[, tt + h]` with `tt = gm` and the baseline is `B[, bb]`
# with `bb = lm`.
#
# ---------------------------------------------------------- COST MEASURE ----
# The estimator's unit is a long difference, dy = Y[outcome] - B[baseline], so
# a state's PERSISTENT suppression level cancels like a unit fixed effect. What
# reaches the estimate is the cross-state SD of the baseline->outcome DRIFT,
# where each window is measured against that state's own pre-COVID
# same-calendar-month norm.
#
# NORM COVERAGE. Requiring two years of 2017-19 coverage silently drops LA, NH
# and NY (series start 2019-01), which are exactly the states an earlier
# boundary admits — so the cost of moving the boundary looked like zero when it
# was merely unmeasured. NORM_MIN_YEARS = 1 scores them. Relaxing from 2 to 1
# leaves every already-scored state's drift bit-identical; it only adds states.
#
# Descriptive only: no outcome model is fit. Blindness-safe.
#
# Outputs (output/covid_end_sweep/):
#   clean_design_switcher_classification.csv
#   clean_design_end_sweep.csv
#   clean_design_state_drift.csv
################################################################################

suppressPackageStartupMessages({
  library(tidyverse); library(lubridate); library(yaml); library(glue)
})

CONFIG          <- "config/power_lpdid_clean_gate_ewatt_pmd6_v20260914.yml"
PANEL           <- "data/raw/state_month_panel_with_treatment.csv"
SCHEDULE        <- "data/processed/shift12_schedule.csv"
OUT             <- "output/covid_end_sweep"
EXCL            <- c("NV", "ID", "HI", "MS")
COVID_START     <- as.Date("2020-03-01")
COVID_END_LIVE  <- as.Date("2021-07-31")
NORM_YEARS      <- 2017:2019
NORM_MIN_YEARS  <- 1L
MIN_OUT         <- 6L        # outcome months required to count as a switcher
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---- 1. Derive the window convention from the config, and assert it ---------
cfg <- yaml::read_yaml(CONFIG)

stopifnot(
  "config is not the event_clean anchor"      = identical(cfg$lpdid_anchor, "event_clean"),
  "config is not on the shift12 treat_def"    = identical(cfg$treat_def, "shift12_start_date")
)
PMD   <- as.integer(cfg$lpdid_pmd %||% 3L)
HMIN  <- as.integer(cfg$lpdid_hmin %||% 0L)
HMAX  <- as.integer(cfg$lpdid_post %||% 12L)
SHIFT <- 12L                                   # shift12 = launch + 12 months

sch_raw <- read_csv(SCHEDULE, show_col_types = FALSE) %>%
  mutate(launch = as.Date(online_start_date), g = as.Date(shift12_start_date)) %>%
  filter(!is.na(launch), !is.na(g))
stopifnot(
  "shift12_start_date is not launch + 12 months" =
    all(sch_raw$g == sch_raw$launch %m+% months(SHIFT))
)

base_off <- c(-PMD, -1L)                       # months relative to LAUNCH
out_off  <- c(SHIFT + HMIN, SHIFT + HMAX)      # months relative to LAUNCH
stopifnot(
  "derived baseline is not [launch-6, launch-1]" = identical(base_off, c(-6L, -1L)),
  "derived outcome is not [launch+12, launch+24]" = identical(out_off, c(12L, 24L))
)
message(glue("window convention (derived from {basename(CONFIG)}): ",
             "baseline [launch{base_off[1]}, launch{base_off[2]}] | ",
             "outcome [launch+{out_off[1]}, launch+{out_off[2]}]"))

win <- function(L, off) seq(L %m+% months(off[1]), L %m+% months(off[2]), by = "month")

# ---- 2. Panel, schedule, per-state seasonal norm ---------------------------
pan <- read_csv(PANEL, show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date), y = log1p(filings_count)) %>%
  filter(!state_abb %in% EXCL, !is.na(filings_count))

xw  <- tibble(state = c(state.name, "District of Columbia"),
              abb   = c(state.abb, "DC"))
sch <- sch_raw %>% left_join(xw, by = "state") %>%
  transmute(st = abb, launch) %>% filter(!is.na(st), !st %in% EXCL)

norm <- pan %>% filter(year(month_date) %in% NORM_YEARS) %>%
  group_by(state_abb, m = month(month_date)) %>%
  summarise(y_norm = mean(y), n_yr = n(), .groups = "drop") %>%
  filter(n_yr >= NORM_MIN_YEARS)
dev <- pan %>% mutate(m = month(month_date)) %>%
  inner_join(norm, by = c("state_abb", "m")) %>%
  transmute(state_abb, month_date, dev = y - y_norm)
DEV <- split(setNames(dev$dev, format(dev$month_date, "%Y-%m")), dev$state_abb)
mdev <- function(s, mo) {
  v <- DEV[[s]][format(mo, "%Y-%m")]; v <- v[!is.na(v)]
  if (!length(v)) NA_real_ else mean(v)
}

obs  <- split(pan$month_date, pan$state_abb)
span <- pan %>% group_by(state_abb) %>%
  summarise(first = min(month_date), last = max(month_date), .groups = "drop")

# ---- 3. Classify every legalizer by its BINDING constraint -----------------
classify <- pmap_dfr(sch, function(st, launch) {
  bw <- win(launch, base_off); ow <- win(launch, out_off)
  if (!st %in% names(obs))
    return(tibble(st, launch, b_drop = NA, b_keep = NA, o_drop = NA, o_keep = NA,
                  reason = "no panel rows"))
  o  <- obs[[st]]
  od <- o[o < COVID_START | o > COVID_END_LIVE]
  sp <- span %>% filter(state_abb == st)
  bd <- sum(bw %in% od); bk <- sum(bw %in% o)
  od_n <- sum(ow %in% od); ok_n <- sum(ow %in% o)
  tibble(st, launch, b_drop = bd, b_keep = bk, o_drop = od_n, o_keep = ok_n,
         reason = if (bd == PMD && od_n >= 1L) "kept"
                  else if (any(ow > sp$last) | any(bw < sp$first)) "calendar edge"
                  else if (bd < PMD) "baseline short (COVID)"
                  else "outcome empty (COVID)")
}) %>% arrange(reason, launch)

write_csv(classify, file.path(OUT, "clean_design_switcher_classification.csv"))

# ---- 4. Boundary sweep, with the drift each state contributes --------------
arm <- function(covid_end, min_out = MIN_OUT) {
  o <- map(obs, ~ .x[.x < COVID_START | .x > covid_end])
  pmap_dfr(sch, function(st, launch) {
    if (!st %in% names(o)) return(NULL)
    bw <- win(launch, base_off)
    if (!all(bw %in% o[[st]])) return(NULL)
    ow <- win(launch, out_off); ow <- ow[ow %in% o[[st]]]
    if (length(ow) < min_out) return(NULL)
    tibble(st, n_out = length(ow), drift = mdev(st, ow) - mdev(st, bw))
  })
}

ENDS <- ceiling_date(seq(as.Date("2020-12-01"), as.Date("2022-06-01"), by = "month"),
                     "month") - 1
bym  <- dev %>% group_by(month_date) %>%
  summarise(mean_dev = mean(dev), sd_dev = sd(dev), .groups = "drop")

sweep <- map_dfr(ENDS, function(CE) {
  a  <- arm(CE); af <- a %>% filter(is.finite(drift))
  adm <- bym %>% filter(month_date > CE, month_date <= as.Date("2021-07-01"))
  tibble(covid_end = CE, switchers = nrow(a), scored = nrow(af),
         full_window = sum(a$n_out == (out_off[2] - out_off[1] + 1L)),
         sd_drift   = if (nrow(af) > 1) sd(af$drift) else NA_real_,
         per_switch = if (nrow(af) > 1) sd(af$drift) / sqrt(nrow(af)) else NA_real_,
         months_admitted   = nrow(adm),
         admitted_mean_dev = if (nrow(adm)) mean(adm$mean_dev) else 0,
         states = paste(sort(a$st), collapse = " "))
})
write_csv(sweep, file.path(OUT, "clean_design_end_sweep.csv"))

state_drift <- map_dfr(c(COVID_END_LIVE, as.Date("2021-06-30"), as.Date("2021-04-30")),
                       ~ arm(.x) %>% mutate(covid_end = .x, .before = 1))
write_csv(state_drift, file.path(OUT, "clean_design_state_drift.csv"))

# ---- 5. Report --------------------------------------------------------------
cat("\n== SWITCHER CLASSIFICATION (LIVE boundary", format(COVID_END_LIVE), ") ==\n")
print(as.data.frame(classify), row.names = FALSE)
cat("\n"); print(table(classify$reason))

cat("\n== COVID-END SWEEP ==\n")
cat(sprintf("%-10s %6s %6s %5s %9s %10s %6s %9s\n",
            "ends", "switch", "scored", "full", "SD(drift)", "SD/sqrt(n)",
            "mo.adm", "mean dev"))
pwalk(sweep, function(covid_end, switchers, scored, full_window, sd_drift,
                      per_switch, months_admitted, admitted_mean_dev, states)
  cat(sprintf("%-10s %6d %6d %5d %9.3f %10.4f %6d %9.2f%s\n",
              format(covid_end, "%Y-%m"), switchers, scored, full_window,
              sd_drift, per_switch, months_admitted, admitted_mean_dev,
              if (covid_end == COVID_END_LIVE) "  <- LIVE" else "")))

message("\nwrote ", OUT)
