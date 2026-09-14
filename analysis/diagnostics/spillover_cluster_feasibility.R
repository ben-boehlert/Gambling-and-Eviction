# =============================================================================
# spillover_cluster_feasibility.R
#
# Option-A feasibility probe (2026-09-14): how many usable STATE clusters does
# the county spillover design actually have under the clean-anchor window?
#
# Motivation: data/processed/county_ets_exposure_panel.csv exists and classifies
# counties into direct / spillover / never-exposed pools, but no power run has
# ever been built over it (the blinded loader has no exposure treat_def; see
# config/power_addon1.yml header). Before plumbing a spillover DGP into
# R/power/, establish whether the design has enough clusters to be worth it.
#
# Inference is state-clustered, so 231 spillover-only COUNTIES is not the
# relevant number -- the number of usable spillover STATES is.
#
# This script estimates NOTHING and touches no outcome-conditional choice.
# It counts clusters and window coverage only: blindness-safe.
#
# Output: output/spillover_cluster_feasibility/
# =============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(glue)
})

PANEL    <- "data/processed/county_month_ets_exposure_panel.csv"
OUT_DIR  <- "output/spillover_cluster_feasibility"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# ---- Clean-anchor design parameters (match the headline state spec) ---------
PRE_MONTHS    <- 6    # pre-onset baseline width (pmd6)
POST_LO       <- 12   # outcomes pooled over months [12, 24] post-onset
POST_HI       <- 24
COVID_START   <- as.Date("2020-03-01")
COVID_END     <- as.Date("2021-07-01")
# Documented exclusions: ID (most extreme state in 100% of pre-era placements),
# HI/MS (thin baskets) per the clean-anchor headline spec. NV has no ETS rows.
EXCL_STATES   <- c("ID", "HI", "MS", "NV")

log_msg <- function(...) cat(format(Sys.time(), "%H:%M:%S"), "|", ..., "\n")

# ---- Load -------------------------------------------------------------------
log_msg("Reading", PANEL)
pan <- read_csv(PANEL, show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date),
         G          = as.Date(G))

log_msg(glue("Rows: {nrow(pan)} | counties: {n_distinct(pan$fips)} | ",
             "states: {n_distinct(pan$state_abb)} | ",
             "months: {min(pan$month_date)} .. {max(pan$month_date)}"))

# ---- Per-county exposure path and onset dates -------------------------------
# S_onset  = first month the county is spillover-exposed
# own_onset= first month the county's own state is online-legal (= G)
probe_one <- function(radius) {
  Scol <- rlang::sym(radius)

  cty <- pan %>%
    group_by(fips, state_abb) %>%
    summarise(
      ever_own   = any(own_legal == 1L),
      ever_S     = any(!!Scol == 1L),
      S_onset    = suppressWarnings(min(month_date[!!Scol == 1L])),
      own_onset  = suppressWarnings(min(month_date[own_legal == 1L])),
      obs_min    = min(month_date),
      obs_max    = max(month_date),
      .groups    = "drop"
    ) %>%
    mutate(
      S_onset   = if_else(is.finite(S_onset),   S_onset,   as.Date(NA)),
      own_onset = if_else(is.finite(own_onset), own_onset, as.Date(NA)),
      path = case_when(
        !ever_own & !ever_S ~ "never_exposed",
        !ever_own &  ever_S ~ "spillover_only",
         ever_own & !ever_S ~ "direct_only",
         ever_own &  ever_S ~ "spillover_then_direct"
      )
    )

  # ---- Candidate spillover switchers --------------------------------------
  # A county is a usable spillover switcher if its spillover onset admits a
  # full pre-baseline and a full [12,24] post window, with own-state
  # legalization not contaminating that window.
  cand <- cty %>%
    filter(path %in% c("spillover_only", "spillover_then_direct"),
           !is.na(S_onset)) %>%
    mutate(
      pre_lo   = S_onset %m-% months(PRE_MONTHS),
      post_lo  = S_onset %m+% months(POST_LO),
      post_hi  = S_onset %m+% months(POST_HI),
      has_pre  = pre_lo  >= obs_min,
      has_post = post_hi <= obs_max,
      # own-state legalization must not land before the end of the post window
      own_clean = is.na(own_onset) | own_onset > post_hi,
      # COVID splice: the pre-baseline and the post window must not sit inside
      # the dropped window
      pre_covid_clear  = !(pre_lo  <= COVID_END & S_onset >= COVID_START),
      post_covid_clear = !(post_lo <= COVID_END & post_hi >= COVID_START),
      excluded = state_abb %in% EXCL_STATES,
      usable = has_pre & has_post & own_clean &
               pre_covid_clear & post_covid_clear & !excluded
    )

  # ---- Control pool: never-exposed donut counties --------------------------
  ctrl <- cty %>% filter(path == "never_exposed", !state_abb %in% EXCL_STATES)

  list(cty = cty, cand = cand, ctrl = ctrl, radius = radius)
}

summarise_probe <- function(p) {
  r <- p$radius
  cand <- p$cand; ctrl <- p$ctrl

  by_state <- cand %>%
    group_by(state_abb) %>%
    summarise(n_counties = n(),
              n_usable   = sum(usable),
              n_excluded = sum(excluded),
              S_onset_min = min(S_onset),
              S_onset_max = max(S_onset),
              fail_pre   = sum(!has_pre),
              fail_post  = sum(!has_post),
              fail_own   = sum(!own_clean),
              fail_covid = sum(!(pre_covid_clear & post_covid_clear)),
              .groups = "drop") %>%
    arrange(desc(n_usable), desc(n_counties))

  usable_states <- by_state %>% filter(n_usable > 0)
  ctrl_states   <- ctrl %>% count(state_abb, name = "n_counties") %>%
                   arrange(desc(n_counties))

  cat("\n", strrep("=", 78), "\n", sep = "")
  cat(glue("RADIUS {r}\n"), "\n")
  cat(strrep("=", 78), "\n", sep = "")

  cat("\n-- Spillover candidate states (before/after window screen) --\n")
  print(as.data.frame(by_state), row.names = FALSE)

  cat(glue("\nUSABLE spillover STATE clusters: {nrow(usable_states)}"), "\n")
  cat(glue("USABLE spillover counties:        {sum(cand$usable)}"), "\n")
  cat(glue("Control (never-exposed) STATE clusters: {nrow(ctrl_states)}"), "\n")
  cat(glue("Control counties:                 {nrow(ctrl)}"), "\n")

  cat("\n-- Control pool by state --\n")
  print(as.data.frame(ctrl_states), row.names = FALSE)

  cat("\n-- Attrition of candidate counties --\n")
  attr_tbl <- tibble(
    stage = c("candidates (spillover_only + spillover_then_direct)",
              "  ... after documented state exclusions",
              "  ... with full 6mo pre-baseline",
              "  ... with full [12,24] post window",
              "  ... with own-state legalization clear of post window",
              "  ... clear of the COVID splice  [= USABLE]"),
    n_counties = c(
      nrow(cand),
      sum(!cand$excluded),
      sum(!cand$excluded & cand$has_pre),
      sum(!cand$excluded & cand$has_pre & cand$has_post),
      sum(!cand$excluded & cand$has_pre & cand$has_post & cand$own_clean),
      sum(cand$usable)),
    n_states = c(
      n_distinct(cand$state_abb),
      n_distinct(cand$state_abb[!cand$excluded]),
      n_distinct(cand$state_abb[!cand$excluded & cand$has_pre]),
      n_distinct(cand$state_abb[!cand$excluded & cand$has_pre & cand$has_post]),
      n_distinct(cand$state_abb[!cand$excluded & cand$has_pre & cand$has_post &
                                cand$own_clean]),
      n_distinct(cand$state_abb[cand$usable]))
  )
  print(as.data.frame(attr_tbl), row.names = FALSE)

  write_csv(by_state,  file.path(OUT_DIR, glue("spillover_by_state_{r}.csv")))
  write_csv(ctrl_states, file.path(OUT_DIR, glue("control_pool_{r}.csv")))
  write_csv(attr_tbl,  file.path(OUT_DIR, glue("attrition_{r}.csv")))

  tibble(radius = r,
         usable_spillover_states = nrow(usable_states),
         usable_spillover_counties = sum(cand$usable),
         control_states = nrow(ctrl_states),
         control_counties = nrow(ctrl))
}

res <- map(c("S60", "S15"), ~ summarise_probe(probe_one(.x))) %>% bind_rows()

cat("\n", strrep("=", 78), "\n", sep = "")
cat("HEADLINE CLUSTER COUNTS\n")
cat(strrep("=", 78), "\n", sep = "")
print(as.data.frame(res), row.names = FALSE)
write_csv(res, file.path(OUT_DIR, "cluster_summary.csv"))

log_msg("Wrote", OUT_DIR)

# =============================================================================
# PERMISSIVE VARIANT -- the screen above requires each window to sit ENTIRELY
# outside the COVID gap. The actual spliced design drops COVID months and
# stitches, so that strict screen understates feasibility. This variant allows
# the splice and asks only for enough SURVIVING (observed, non-COVID) months.
# The two together bracket the honest answer.
# =============================================================================

MIN_PRE_P  <- 3
MIN_POST_P <- 6

permissive <- function(radius) {
  Scol <- rlang::sym(radius)
  obs <- pan %>%
    filter(!(month_date >= COVID_START & month_date <= COVID_END)) %>%
    select(fips, month_date)

  cand <- pan %>%
    group_by(fips, state_abb) %>%
    summarise(ever_S    = any(!!Scol == 1L),
              S_onset   = suppressWarnings(min(month_date[!!Scol == 1L])),
              own_onset = suppressWarnings(min(month_date[own_legal == 1L])),
              .groups = "drop") %>%
    mutate(S_onset   = if_else(is.finite(S_onset),   S_onset,   as.Date(NA)),
           own_onset = if_else(is.finite(own_onset), own_onset, as.Date(NA))) %>%
    filter(ever_S, !is.na(S_onset), !state_abb %in% EXCL_STATES) %>%
    mutate(pre_lo  = S_onset %m-% months(PRE_MONTHS),
           post_lo = S_onset %m+% months(POST_LO),
           post_hi = S_onset %m+% months(POST_HI),
           own_clean = is.na(own_onset) | own_onset > post_hi)

  cnt <- cand %>%
    select(fips, pre_lo, S_onset, post_lo, post_hi) %>%
    inner_join(obs, by = "fips", relationship = "many-to-many") %>%
    group_by(fips) %>%
    summarise(n_pre  = sum(month_date >= pre_lo  & month_date <  S_onset),
              n_post = sum(month_date >= post_lo & month_date <= post_hi),
              .groups = "drop")

  out <- cand %>% left_join(cnt, by = "fips") %>%
    mutate(across(c(n_pre, n_post), ~ replace_na(.x, 0L)),
           usable = own_clean & n_pre >= MIN_PRE_P & n_post >= MIN_POST_P)

  st <- out %>% filter(usable) %>% count(state_abb, name = "n_usable") %>%
        arrange(desc(n_usable))

  cat(glue("\n-- {radius} PERMISSIVE (splice allowed; >={MIN_PRE_P} pre, ",
           ">={MIN_POST_P} post surviving months) --"), "\n")
  cat(glue("usable spillover STATE clusters: {nrow(st)} | counties: {sum(out$usable)}"), "\n")
  print(as.data.frame(st), row.names = FALSE)
  write_csv(st, file.path(OUT_DIR, glue("permissive_by_state_{radius}.csv")))

  tibble(radius = radius, screen = "permissive",
         usable_spillover_states = nrow(st),
         usable_spillover_counties = sum(out$usable))
}

cat("\n", strrep("=", 78), "\n", sep = "")
cat("PERMISSIVE SCREEN\n")
cat(strrep("=", 78), "\n", sep = "")
res_p <- map(c("S60", "S15"), permissive) %>% bind_rows()
write_csv(res_p, file.path(OUT_DIR, "cluster_summary_permissive.csv"))

cat("\n", strrep("=", 78), "\n", sep = "")
cat("BRACKET: strict vs permissive usable spillover STATE clusters\n")
cat(strrep("=", 78), "\n", sep = "")
bracket <- res %>% transmute(radius, strict = usable_spillover_states) %>%
  left_join(res_p %>% transmute(radius, permissive = usable_spillover_states),
            by = "radius")
print(as.data.frame(bracket), row.names = FALSE)
write_csv(bracket, file.path(OUT_DIR, "bracket.csv"))

log_msg("Done.")
