#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# FEASIBILITY PROBE — clean-anchor LP-DiD geometry on the mortgage panel.
#
# WHAT THIS IS. The outcome-swap plumbing for running the headline eviction
# design (LP-DiD, event_clean anchor on shift12, PMD=6 pre-launch baseline,
# outcomes pooled over launch+12..24, launched states never controls) against
# state 90+ day mortgage delinquency — plus a geometry report.
#
# WHAT THIS IS NOT. It runs NO regression and produces NO estimate, SE, or
# ATT of any kind. The PAP is blinded (see FINDINGS.md, memory:
# pap_blindness_no_results_to_ben): only design diagnostics leave this script.
# The outcome-granularity diagnostic below is deliberately POOLED across
# switchers and clean controls — splitting it by D_treat would be a DiD in
# disguise. Do not add that split without an explicit unblinding decision.
#
# OUTCOME SCALE: LEVELS (percentage points), not logs. Decided 2026-09-04.
# The series is rounded to 0.1pp and 87% of design-window state-months sit at
# or below 1.0pp, so one rounding tick is a 17%+ relative move — roughly twice
# the eviction design's recentered MDE. In levels the rounding is additive
# noise instead of a multiplicative step function.
#
# NV: structurally present in the 51-state mortgage panel and always-treated
# (legal since 1949). Excluded via the canonical universe helper, never by a
# hand-written filter. The prior mortgage pretrends run is flagged CONTAMINATED
# in RUN_LEDGER.md for exactly this omission.
#
# ID/HI/MS: the headline eviction spec excludes these for basket-composition
# reasons (see docs/STATE_SOURCES.md). Mortgage has no basket — the series is
# whole-state — so they are KEPT by default. Override with EXCLUDE_EXTRA.
#
# Usage:
#   Rscript analysis/diagnostics/mortgage_lpdid_feasibility_probe.R
#   DROP_END=2022-06-30 Rscript analysis/diagnostics/mortgage_lpdid_feasibility_probe.R
#   EXCLUDE_EXTRA=ID,HI,MS Rscript analysis/diagnostics/mortgage_lpdid_feasibility_probe.R
#
# Output: output/mortgage_lpdid_feasibility/*
# ─────────────────────────────────────────────────────────────────────────────

suppressMessages({
  library(tidyverse); library(lubridate); library(glue)
})

source("utils/eviction_treatment_schedule.R")

getenv1 <- function(k, d) { v <- Sys.getenv(k); if (nzchar(v)) v else d }

# ── Design knobs (defaults = the headline clean-anchor spec) ─────────────────
PMD      <- as.integer(getenv1("PMD", "6"))        # pre-launch baseline width
POST_MIN <- as.integer(getenv1("POST_MIN", "12"))  # pooled horizons, low end
POST     <- as.integer(getenv1("POST", "24"))      # pooled horizons, high end
# Diagnostic leads. NOTE 24, not the eviction script's 12. Under shift12 the
# event sits 12 months after launch, so a lead at h <= 12 lands inside the
# buildup and event_clean correctly refuses it (far >= launch_t). Leads only
# become genuinely pre-launch at h > 12; h = 13..24 maps to launch-1..launch-12.
PRE      <- as.integer(getenv1("PRE", "24"))

MIN_DATE   <- as.Date(getenv1("MIN_DATE",   "2016-01-01"))
MAX_DATE   <- as.Date(getenv1("MAX_DATE",   "2025-03-01"))
DROP_START <- as.Date(getenv1("DROP_START", "2020-03-01"))
# NOTE: the eviction default is 2021-07-31, calibrated to eviction moratoria.
# Mortgage forbearance (CARES) suppressed measured delinquency well past that —
# this series FALLS through COVID rather than spiking. The probe reports both
# windows so the splice length is a visible decision, not a default.
DROP_END   <- as.Date(getenv1("DROP_END",   "2021-07-31"))

EXCLUDE_EXTRA <- setdiff(strsplit(getenv1("EXCLUDE_EXTRA", ""), ",")[[1]], "")

OUT_DIR <- "output/mortgage_lpdid_feasibility"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

ym_index <- function(d) (as.integer(format(d, "%Y")) - 2000L) * 12L +
  as.integer(format(d, "%m"))
G_DROP <- c(ym_index(DROP_START), ym_index(DROP_END))
spans_gap <- function(lo, hi) lo <= G_DROP[2] && hi >= G_DROP[1]

# ── Panel: mortgage delinquency, LEVELS ─────────────────────────────────────
p <- read_csv("data/processed/mortgage_treatment_panel.csv",
              show_col_types = FALSE) %>%
  transmute(state_abb = as.character(state_abb),
            month_date = as.Date(month_date),
            delinq_pp = as.numeric(delinquency_rate)) %>%
  filter(!is.na(delinq_pp)) %>%
  filter(month_date >= MIN_DATE, month_date <= MAX_DATE) %>%
  filter(!(month_date >= DROP_START & month_date <= DROP_END))

# NV is always-treated. Canonical helper, not a hand-rolled filter.
drop_states <- unique(c(PRE_PASPA_SPORTS_BETTING, EXCLUDE_EXTRA))
n_before <- n_distinct(p$state_abb)
p <- p %>% filter(!state_abb %in% drop_states)

# Balance to states with full coverage, then to common months (mirrors
# lpdid_statepanel.R so the geometry is comparable across outcomes).
cov_tbl <- p %>% count(state_abb, name = "n")
p <- p %>% filter(state_abb %in% cov_tbl$state_abb[cov_tbl$n == max(cov_tbl$n)])
k  <- n_distinct(p$state_abb)
cm <- p %>% count(month_date, name = "j") %>% filter(j == k) %>% pull(month_date)
p  <- p %>% filter(month_date %in% cm) %>%
  mutate(y = delinq_pp, t = ym_index(month_date))

# ── Treatment: shift12 schedule (full state names -> abbreviations) ──────────
abb <- tibble(state = c(state.name, "District of Columbia"),
              state_abb = c(state.abb, "DC"))
sched <- read_csv("data/processed/shift12_schedule.csv", show_col_types = FALSE) %>%
  left_join(abb, by = "state") %>%
  transmute(state_abb,
            treat_start = as.Date(online_start_date),
            treat_date  = as.Date(shift12_start_date))
unmatched <- sched %>% filter(is.na(state_abb)) %>% nrow()

t_max <- max(p$t)
treat_tbl <- tibble(state_abb = sort(unique(p$state_abb))) %>%
  left_join(sched, by = "state_abb") %>%
  mutate(
    # g gates the SWITCH (shift12 event); g_launch gates CONTROL status
    # (actual online launch). Hybrid coding, as in lpdid_statepanel.R.
    g        = ifelse(is.na(treat_date),  NA_integer_, ym_index(treat_date)),
    g_launch = ifelse(is.na(treat_start), NA_integer_, ym_index(treat_start)),
    g        = ifelse(!is.na(g) & g > t_max, NA_integer_, g),
    g_launch = ifelse(!is.na(g_launch) & g_launch > t_max, NA_integer_, g_launch))

panel <- p %>% left_join(treat_tbl %>% select(state_abb, g), by = "state_abb")

n_treat  <- sum(!is.na(treat_tbl$g))
n_never  <- sum(is.na(treat_tbl$g_launch))
n_dirty  <- sum(!is.na(treat_tbl$g_launch) & is.na(treat_tbl$g))

cat(glue("
MORTGAGE LP-DiD FEASIBILITY PROBE — geometry only, no estimates
  outcome        : 90+ day delinquency, LEVELS (pp)
  anchor         : event_clean | PMD {PMD} | pooled horizons {POST_MIN}..{POST}
  window         : {MIN_DATE} .. {MAX_DATE}
  splice dropped : {DROP_START} .. {DROP_END}  (index [{G_DROP[1]}, {G_DROP[2]}])
  excluded       : {paste(drop_states, collapse = ', ')}  ({n_before} -> {n_distinct(p$state_abb)} states pre-balance)
  panel          : {n_distinct(panel$state_abb)} states, {n_distinct(panel$t)} months
  switchers      : {n_treat}   never-launched (control pool): {n_never}   launched-but-immature (dirty): {n_dirty}
  schedule rows unmatched to an abbreviation: {unmatched}
"), "\n")

# ── Cell construction (event_clean) ─────────────────────────────────────────
y_lookup <- panel %>% select(state_abb, t, y) %>%
  { split(setNames(.$y, .$t), .$state_abb) }

y_at <- function(state, tt) {
  v <- y_lookup[[state]][as.character(tt)]
  as.numeric(ifelse(is.na(names(v)) | is.na(v), NA_real_, v))
}
baseline_at <- function(state, tt) {
  b <- vapply(seq(tt - PMD, tt - 1L), function(s) y_at(state, s), numeric(1))
  if (any(is.na(b))) NA_real_ else mean(b)
}

states <- sort(unique(panel$state_abb))
cohort_cells <- treat_tbl %>%
  filter(!is.na(g), g <= t_max, !is.na(g_launch), g_launch <= t_max) %>%
  transmute(event_t = as.integer(g), launch_t = as.integer(g_launch),
            cell_t = event_t, base_t = launch_t,
            cell_id = paste(event_t, launch_t, sep = "_")) %>%
  distinct()

build_h <- function(h, side = c("post", "pre")) {
  side <- match.arg(side)
  map_dfr(seq_len(nrow(cohort_cells)), function(j) {
    cc <- cohort_cells[j, ]
    far <- if (side == "post") cc$cell_t + h else cc$cell_t - h
    if (side == "pre" && far >= cc$launch_t) return(NULL)
    map_dfr(states, function(s) {
      g_s <- treat_tbl$g[treat_tbl$state_abb == s]
      g_s <- if (length(g_s) == 0 || is.na(g_s)) NA_integer_ else g_s
      g_l <- treat_tbl$g_launch[treat_tbl$state_abb == s]
      g_l <- if (length(g_l) == 0 || is.na(g_l)) NA_integer_ else g_l
      is_switch <- !is.na(g_s) && !is.na(g_l) &&
        g_s == cc$event_t && g_l == cc$launch_t
      is_clean_ctrl <- is.na(g_l) || g_l > far
      if (!is_switch && !is_clean_ctrl) return(NULL)
      base <- baseline_at(s, cc$base_t); yfar <- y_at(s, far)
      if (is.na(base) || is.na(yfar)) return(NULL)
      lo <- min(far, cc$base_t - PMD); hi <- max(far, cc$base_t - 1L)
      tibble(state_abb = s, cell_id = cc$cell_id,
             D_treat = as.integer(is_switch), dy = yfar - base,
             straddles = spans_gap(lo, hi))
    })
  })
}

# ── Horizon-by-horizon geometry ─────────────────────────────────────────────
lead_h <- seq(PRE, 13)   # h <= 12 is buildup, not a pre-launch lead (see PRE)
horizons <- tibble(h = c(lead_h, seq(POST_MIN, POST)),
                   side = c(rep("pre", length(lead_h)),
                            rep("post", POST - POST_MIN + 1)))

geom <- pmap_dfr(list(horizons$h, horizons$side), function(h, side) {
  d <- build_h(h, side)
  if (nrow(d) == 0) {
    return(tibble(side = side, h = h, n_cells_raw = 0L, n_cells_identified = 0L,
                  n_switchers = 0L, n_controls = 0L, n_obs = 0L,
                  n_straddling = 0L, identified = FALSE))
  }
  ident <- d %>% group_by(cell_id) %>% filter(n_distinct(D_treat) == 2) %>% ungroup()
  tibble(side = side, h = h,
         n_cells_raw        = n_distinct(d$cell_id),
         n_cells_identified = n_distinct(ident$cell_id),
         n_switchers        = sum(ident$D_treat == 1),
         n_controls         = sum(ident$D_treat == 0),
         n_obs              = nrow(ident),
         n_straddling       = sum(ident$straddles),
         identified         = nrow(ident) > 0)
})

write_csv(geom, file.path(OUT_DIR, "horizon_geometry.csv"))
cat("── Horizon geometry (identified cells require both switchers and controls) ──\n")
print(as.data.frame(geom), row.names = FALSE)

# ── Switcher survival: WHY a switcher does or does not contribute ───────────
# A switcher enters horizon h only if BOTH its PMD-month pre-launch baseline
# and its outcome month at event+h exist in the balanced panel. The splice and
# the panel end are the two things that remove them.
t_lo <- min(panel$t); t_hi <- max(panel$t)
surv <- treat_tbl %>%
  filter(!is.na(g), !is.na(g_launch)) %>%
  rowwise() %>%
  mutate(
    base_ok   = !is.na(baseline_at(state_abb, g_launch)),
    base_lo   = g_launch - PMD, base_hi = g_launch - 1L,
    base_in_gap = base_lo <= G_DROP[2] && base_hi >= G_DROP[1],
    base_pre_panel = base_lo < t_lo,
    n_post_ok = sum(vapply(seq(POST_MIN, POST),
                           function(h) !is.na(y_at(state_abb, g + h)), logical(1))),
    last_needed = g + POST,
    post_past_end = last_needed > t_hi) %>%
  ungroup() %>%
  mutate(contributes = base_ok & n_post_ok > 0,
         reason = case_when(
           contributes                    ~ "contributes",
           !base_ok & base_in_gap         ~ "baseline falls in dropped splice",
           !base_ok & base_pre_panel      ~ "baseline precedes panel start",
           !base_ok                       ~ "baseline unavailable (other)",
           post_past_end                  ~ "outcome window past panel end",
           TRUE                           ~ "outcome months unavailable")) %>%
  select(state_abb, g_launch, g, base_ok, n_post_ok, contributes, reason) %>%
  arrange(desc(contributes), state_abb)

write_csv(surv, file.path(OUT_DIR, "switcher_survival.csv"))
cat("\n── Switcher survival (of ", nrow(surv), " switchers) ──\n", sep = "")
print(as.data.frame(surv %>% count(reason, name = "n_states") %>%
                      arrange(desc(n_states))), row.names = FALSE)
cat("\nContributing switchers: ",
    paste(surv$state_abb[surv$contributes], collapse = ", "), "\n", sep = "")
cat("Lost switchers:         ",
    paste(surv$state_abb[!surv$contributes], collapse = ", "), "\n", sep = "")

# ── Outcome granularity in LEVELS — POOLED across D_treat (blindness) ────────
pooled <- map_dfr(seq(POST_MIN, POST), function(h) build_h(h, "post")) %>%
  group_by(cell_id) %>% filter(n_distinct(D_treat) == 2) %>% ungroup()

if (nrow(pooled) > 0) {
  dy <- pooled$dy                       # NOT split by D_treat, by design
  gran <- tibble(
    n_obs              = length(dy),
    sd_dy_pp           = sd(dy),
    iqr_dy_pp          = IQR(dy),
    tick_pp            = 0.1,           # published rounding of the source series
    ticks_per_sd       = sd(dy) / 0.1,
    share_within_1tick = mean(abs(dy) < 0.1),
    n_distinct_dy      = n_distinct(round(dy, 4)))
  write_csv(gran, file.path(OUT_DIR, "outcome_granularity_levels.csv"))
  cat("\n── Outcome granularity, LEVELS, pooled across switchers and controls ──\n")
  print(as.data.frame(gran), row.names = FALSE)
  cat(glue("
  Read: the source series is published to {gran$tick_pp}pp. The pooled long
  difference has SD {round(gran$sd_dy_pp, 3)}pp = {round(gran$ticks_per_sd, 1)} rounding ticks, and
  {round(100 * gran$share_within_1tick)}% of long differences fall inside a single tick.
"), "\n")
}

cat(glue("\nWrote geometry to {OUT_DIR}/. No estimates produced.\n"))
