# =============================================================================
# d1_placement_autopsy.R  (2026-09-14)
#
#   Rscript analysis/diagnostics/d1_placement_autopsy.R
#
# "What's going on with the 0/25 — is it just a quirk in the data?"
#
# It is not a quirk and it is not stochastic. `.eligible_states()` is an
# ENDPOINT test: a state is eligible for cohort date d iff its series STARTS
# at or before d - min_pre and ENDS at or after d + min_post. It never looks at
# which months are actually present, so the COVID hole is invisible to it.
#
# make_pseudo_schedule() then slides the real cohort template across
# [panel_min + min_pre, panel_max - min_post]. Widening either bound shortens
# that window on BOTH ends at once: it removes candidate anchors, and it makes
# late cohorts demand states whose series run further right than any state's
# does. This script reports, per (min_pre, min_post): the window length, the
# template span, how many anchors survive, and — for the best anchor — exactly
# which cohorts come up short and by how many states.
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
  filter(!state_abb %in% cfg$exclude_states)
real <- read_csv(cfg$schedule, show_col_types = FALSE)

mi <- function(d) as.integer(format(as.Date(d), "%Y")) * 12L + as.integer(format(as.Date(d), "%m"))
cov <- panel %>% group_by(state_abb) %>%
  summarise(min_m = min(month_date), max_m = max(month_date), .groups = "drop")
panel_min <- min(panel$month_date); panel_max <- max(panel$month_date)

name2abb <- setNames(c(state.abb, "DC"), c(state.name, "District of Columbia"))
sched <- real %>%
  mutate(state_abb = if ("state_abb" %in% names(.)) .data$state_abb
                     else unname(name2abb[as.character(.data$state)]),
         g = as.Date(.data$shift12_start_date)) %>%
  filter(!is.na(g), !is.na(state_abb))
# template: panel  -> the template is RESTRICTED to states present in the panel
# (make_pseudo_schedules.R:225). Using the national template here would invent a
# larger structure than the config asks for.
sched <- sched %>% filter(state_abb %in% cov$state_abb)
cohorts <- sched %>% count(g, name = "n_states") %>% arrange(g)
offsets <- mi(cohorts$g) - mi(cohorts$g[1]); span <- max(offsets)

cat(glue("panel: {n_distinct(panel$state_abb)} states, ",
         "{format(panel_min,'%Y-%m')}..{format(panel_max,'%Y-%m')} ",
         "({mi(panel_max)-mi(panel_min)+1} months)"), "\n")
cat(glue("D1 template: {nrow(cohorts)} cohorts, span {span} months, ",
         "{sum(cohorts$n_states)} state-slots to fill"), "\n\n")

elig_at <- function(d, min_pre, min_post) {
  di <- mi(d)
  cov$state_abb[mi(cov$min_m) <= di - min_pre & mi(cov$max_m) >= di + min_post]
}

# Max bipartite matching (Hopcroft-Karp is overkill; Kuhn's is fine at this size)
.max_match <- function(el, need) {
  slots <- rep(seq_along(el), times = need)          # one node per state-slot
  matchL <- rep(NA_integer_, length(slots))          # slot -> state
  matchR <- list()                                   # state -> slot
  try_k <- function(j, seen) {
    for (st in el[[slots[j]]]) {
      if (isTRUE(seen[[st]])) next
      seen[[st]] <<- TRUE
      cur <- matchR[[st]]
      if (is.null(cur) || try_k(cur, seen)) {
        matchR[[st]] <<- j; matchL[j] <<- match(st, names(matchR)); return(TRUE)
      }
    }
    FALSE
  }
  n <- 0L
  for (j in seq_along(slots)) { seen <- new.env(); if (try_k(j, seen)) n <- n + 1L }
  n
}

report <- function(min_pre, min_post) {
  fs <- panel_min %m+% months(min_pre); fe <- panel_max %m-% months(min_post)
  L  <- mi(fe) - mi(fs)
  if (L < 0) { cat(sprintf("min_pre=%d, min_post=%-2d: window NEGATIVE\n", min_pre, min_post)); return(invisible()) }
  eff <- if (span > L) as.integer(round(offsets * (L / span))) else offsets
  slack <- L - max(eff)
  anchors <- if (slack > 0) 0:slack else 0L
  best <- NULL
  nok <- 0L
  for (so in anchors) {
    dts <- (fs %m+% months(so)) %m+% months(eff)
    el  <- lapply(dts, elig_at, min_pre = min_pre, min_post = min_post)
    used <- character(0); good <- TRUE
    for (k in order(lengths(el), dts)) {
      av <- setdiff(el[[k]], used)
      if (length(av) < cohorts$n_states[k]) { good <- FALSE; break }
      used <- c(used, av[seq_len(cohorts$n_states[k])])
    }
    if (good) nok <- nok + 1L
    if (is.null(best)) best <- list(dts = dts, el = el)
  }
  m <- .max_match(best$el, cohorts$n_states)
  cat(sprintf("min_pre=%2d, min_post=%-2d  window %s..%s (L=%2d)  span %2d%s  anchors %2d  FEASIBLE %2d   max matching %d/%d slots  distinct eligible states %d\n",
              min_pre, min_post, format(fs, "%Y-%m"), format(fe, "%Y-%m"), L,
              max(eff), if (span > L) "*" else " ", length(anchors), nok,
              m, sum(cohorts$n_states), length(unique(unlist(best$el)))))
  if (nok == 0L) {
    short <- tibble(cohort = format(best$dts, "%Y-%m"), need = cohorts$n_states,
                    eligible = lengths(best$el)) %>% filter(eligible < need)
    cat(sprintf("     first anchor: %d of %d cohorts individually short, %d cohorts EMPTY; shortfall is %d slots vs a %d-state pool\n",
                nrow(short), nrow(cohorts), sum(lengths(best$el) == 0),
                sum(cohorts$n_states) - m, nrow(cov)))
  }
}

for (mq in c(0L, 3L, 6L, 9L, 12L)) for (mp in c(12L, 15L, 18L)) report(mp, mq)

cat("---- why the endpoint test is the wrong test ----\n")
cat("A state passes min_pre by STARTING early enough, not by having the six\n")
cat("pre-launch months the PMD=6 baseline needs. Those can sit in the COVID hole.\n\n")
print(cov %>% arrange(min_m) %>% mutate(across(c(min_m, max_m), ~format(.x, "%Y-%m"))), n = Inf)
