################################################################################
# analysis/diagnostics/lpdid_cs_equivalence.R
#
# Does reweighted first-lag LP-DiD reproduce Callaway & Sant'Anna ON OUR DESIGN?
#
# Dube, Girardi, Jorda & Taylor (2023, NBER w31184 / FRBSF WP 2023-12), fn. 23:
# in a baseline setting with no covariates, binary absorbing treatment, and
# only not-yet-treated observations as controls, REWEIGHTED LP-DiD with
# FIRST-LAG differencing is numerically equivalent to CS at every h >= 0.
#
# tests/testthat/test-estimators.R already pins this on a clean toy panel. This
# script asks the harder question: does it survive OUR panel, whose spliced
# window has a 25-month COVID hole and per-state coverage gaps? LP-DiD drops
# any (t, h) cell whose base period or endpoint falls in a gap; did::att_gt
# with allow_unbalanced_panel handles missingness its own way. If the two
# diverge on the spliced window but agree post-COVID, the splice -- not the
# estimator -- is what separates them, which is the same conclusion the
# time-aggregation memo reached from the size side.
#
# The comparison runs on SIMULATED outcomes over the real design skeleton
# (pseudo-schedules from make_pseudo_schedule), so it never touches real
# treated outcomes and the blindness protocol holds.
#
# RESULT (2026-08-24). The equivalence holds EXACTLY on a contiguous panel --
# including a badly unbalanced one -- and breaks whenever the panel has an
# INTERIOR TIME GAP. Controlled decomposition on the toy design (section 2
# below), max |LP-DiD - CS| over h = 0..6:
#
#   A. balanced, contiguous                 3.3e-16   equivalence holds
#   B. unbalanced, staggered entry          9.4e-16   equivalence holds
#   C. balanced but a 7-month interior hole 5.8e-02   BREAKS
#
# The mechanism is .re_prep(), which hands did::att_gt a CONSECUTIVE rank
# index (t_c <- match(month_date, months)). That collapses every hole, so CS
# treats the month before the COVID splice and the month after as adjacent.
# .re_lpdid indexes true calendar months and refuses to bridge a gap by
# design. On our real S2 state panel this is not a corner case: the covid-keep
# window has 8 states with interior holes (84 months) and the covid-drop
# window has 19 states with 360 -- on top of the 25-month splice itself.
#
# So the honest statement for the PAP is that on THIS panel the two are not
# numerically identical; reweighted first-lag LP-DiD is merely the closest
# arm. It also flags something broader than LP-DiD: every CS run in this
# framework differences across the COVID hole as though it were one month.
#
# Env vars: N_REPS (default 5), DELTA (default 0), H_MAX (default 8),
#           WINDOWS (default "drop,post"), OUT_DIR, TOY_ONLY.
# Working directory: repository root.
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(tibble); library(readr); library(lubridate)
  library(fixest); library(did)
})

source("R/power/config.R")
source("R/power/blindness_checks.R")
source("R/power/load_blinded_panel.R")
source("R/power/make_pseudo_schedules.R")
source("R/power/impose_effects.R")
source("R/power/run_estimators.R")

getenv1 <- function(k, d) { v <- Sys.getenv(k); if (nzchar(v)) v else d }
N_REPS  <- as.integer(getenv1("N_REPS", "5"))
DELTA   <- as.numeric(getenv1("DELTA", "0"))
H_MAX   <- as.integer(getenv1("H_MAX", "8"))
WINDOWS <- strsplit(getenv1("WINDOWS", "drop,post"), ",")[[1]]
OUT_DIR <- getenv1("OUT_DIR", "output/lpdid_cs_equivalence")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# att_gt -> DRDID:::reg_did_rc -> fastglm ABORTS the R process (C-level,
# uncatchable) on the zero-row design matrices produced by non-identifiable
# (g,t) cells, which this design has many of. The guard must be installed
# before any att_gt call; faster_mode = FALSE is also required here (with TRUE
# CS failed on 100% of probed cells on this design, and FALSE is faster).
stopifnot(install_cs_safe_patches(TRUE))

CFG <- read_power_config("config/power_lpdid_shift12_gate_ewatt.yml")
real_schedule <- read_csv(CFG$schedule, show_col_types = FALSE)
BASE_SEED <- 20260723L

# CS exactly as .re_cs() calls it. g MUST be double: att_gt recodes
# never-treated to Inf and an integer column truncates that to NA, silently
# dropping every never-treated unit.
cs_dynamic <- function(panel_sim, hs) {
  est <- .re_prep(panel_sim)
  dat <- data.frame(id = est$id, t = est$t, g = as.numeric(est$g_int),
                    y = est$y_sim)
  fit <- try(suppressWarnings(suppressMessages(
    att_gt(yname = "y", tname = "t", idname = "id", gname = "g", data = dat,
           control_group = "notyettreated", est_method = "reg",
           bstrap = FALSE, cband = FALSE, base_period = "varying",
           allow_unbalanced_panel = TRUE, faster_mode = FALSE,
           clustervars = NULL))), silent = TRUE)
  if (inherits(fit, "try-error")) return(rep(NA_real_, length(hs)))
  dyn <- try(suppressWarnings(suppressMessages(
    aggte(fit, type = "dynamic", na.rm = TRUE))), silent = TRUE)
  if (inherits(dyn, "try-error")) return(rep(NA_real_, length(hs)))
  dyn$att.egt[match(hs, dyn$egt)]
}

lpdid_h <- function(panel_sim, hs, weights, pmd) {
  vapply(hs, function(h) {
    r <- try(run_estimator(panel_sim, estimator = "lpdid",
                           spec = list(lpdid_pmd = pmd, lpdid_weights = weights,
                                       lpdid_hmin = h, lpdid_post = h)),
             silent = TRUE)
    if (inherits(r, "try-error")) return(NA_real_)
    a <- r$att[r$inference == "analytic"]
    if (length(a) == 0L) NA_real_ else a[1]
  }, numeric(1))
}

hs  <- 0:H_MAX
out <- list()

for (win in WINDOWS) {
  panel <- load_blinded_panel(level = "state", treat_def = "shift12_start_date",
                              anticipation = 0L, sample = "S2", covid = win,
                              config = CFG)
  ex <- as.character(unlist(CFG$exclude_states %||% character(0)))
  if (length(ex) > 0L) panel <- panel[!panel$state_abb %in% ex, , drop = FALSE]
  message(sprintf("[%s] panel: %d states, %d months",
                  win, dplyr::n_distinct(panel$state_abb),
                  dplyr::n_distinct(panel$month_date)))

  for (rep in seq_len(N_REPS)) {
    seed_rep <- BASE_SEED + 10007L * rep
    sched <- tryCatch(
      make_pseudo_schedule(design = "D1", panel = panel,
                           real_schedule = real_schedule,
                           treat_def = "shift12_start_date",
                           min_pre = CFG$min_pre, min_post = CFG$min_post,
                           seed = seed_rep, template = "panel"),
      error = function(e) e)
    if (inherits(sched, "error")) {
      message(sprintf("  rep %d: schedule infeasible (%s)", rep,
                      conditionMessage(sched)))
      next
    }
    sim <- impose_effect(panel, sched, mechanism = "count_nb", shape = "step",
                         delta = DELTA, outcome = "y_log1p", seed = seed_rep + 1L)

    cs_att <- cs_dynamic(sim, hs)
    out[[length(out) + 1L]] <- tibble(
      window = win, rep = rep, h = hs, cs = cs_att,
      ewatt_pmd1    = lpdid_h(sim, hs, "ewatt",    1L),
      cellsize_pmd1 = lpdid_h(sim, hs, "cellsize", 1L),
      vwatt_pmd1    = lpdid_h(sim, hs, "vwatt",    1L),
      ewatt_pmd3    = lpdid_h(sim, hs, "ewatt",    3L))
    message(sprintf("  rep %d done", rep))
  }
}

# ---- 2. Controlled decomposition on the toy design --------------------------
# Isolates WHY the real-panel comparison diverges: balance vs contiguity.
toy_decomposition <- function() {
  build_toy <- function(seed, n_states, n_months, treat, noise_sd) {
    set.seed(seed)
    states <- sprintf("S%02d", seq_len(n_states))
    md <- seq(as.Date("2016-01-01"), by = "month", length.out = n_months)
    grid <- expand.grid(state_abb = states, mi = seq_len(n_months),
                        stringsAsFactors = FALSE)
    grid$unit_id <- grid$state_abb
    grid$month_date <- md[grid$mi]; grid$t <- as.integer(grid$mi)
    ufe <- setNames(rnorm(n_states), states)
    tfe <- setNames(rnorm(n_months, 0, 0.3), as.character(seq_len(n_months)))
    grid$y_log1p <- 2 + ufe[grid$state_abb] + tfe[as.character(grid$mi)] +
      rnorm(nrow(grid), 0, noise_sd)
    grid$filings_count <- pmax(round(expm1(grid$y_log1p)), 0)
    grid$renters <- 1000
    grid$y_lograte <- log(grid$filings_count / grid$renters * 1000 + 0.01)
    grid$y_asinh <- asinh(grid$filings_count); grid$g <- 0
    list(panel = as_tibble(grid),
         sched = tibble(state_abb = names(treat),
                        pseudo_g = md[as.integer(treat)]))
  }
  toy <- build_toy(55L, 16L, 60L,
                   c(S02=20L,S04=24L,S06=28L,S08=32L,S10=36L,S12=40L), 0.30)
  base <- impose_effect(toy$panel, toy$sched, mechanism = "deterministic",
                        shape = "step", delta = 0.20, outcome = "y_log1p",
                        seed = 3L)
  set.seed(9)
  starts <- setNames(sample(1:14, 16, replace = TRUE), sprintf("S%02d", 1:16))
  cases <- list(
    "A_balanced_contiguous"   = base,
    "B_unbalanced_staggered"  = base %>% filter(t >= starts[state_abb]),
    "C_interior_hole"         = base %>% filter(!(t %in% 44:50)))
  bind_rows(lapply(names(cases), function(nm) {
    d <- cases[[nm]]; cs <- cs_dynamic(d, hs)
    tibble(case = nm,
           ewatt_pmd1    = max(abs(lpdid_h(d, hs, "ewatt", 1L)    - cs), na.rm = TRUE),
           cellsize_pmd1 = max(abs(lpdid_h(d, hs, "cellsize", 1L) - cs), na.rm = TRUE),
           vwatt_pmd1    = max(abs(lpdid_h(d, hs, "vwatt", 1L)    - cs), na.rm = TRUE),
           ewatt_pmd3    = max(abs(lpdid_h(d, hs, "ewatt", 3L)    - cs), na.rm = TRUE))
  }))
}

toy_res <- toy_decomposition()
write_csv(toy_res, file.path(OUT_DIR, "toy_decomposition.csv"))
cat("\n=== max |LP-DiD arm - CS| on the controlled toy design ===\n")
print(as.data.frame(toy_res), row.names = FALSE, digits = 3)
cat("\nA and B at ~1e-16 with C at ~1e-2 means CONTIGUITY, not balance, is\n",
    "what the equivalence needs. .re_prep() bridges gaps for CS; .re_lpdid\n",
    "does not.\n", sep = "")

res <- bind_rows(out)
write_csv(res, file.path(OUT_DIR, "per_horizon_estimates.csv"))

arms <- c("ewatt_pmd1", "cellsize_pmd1", "vwatt_pmd1", "ewatt_pmd3")
summ <- res %>%
  tidyr::pivot_longer(all_of(arms), names_to = "arm", values_to = "att") %>%
  filter(is.finite(att), is.finite(cs)) %>%
  group_by(window, arm) %>%
  summarise(n_cells = n(), max_abs_diff = max(abs(att - cs)),
            median_abs_diff = median(abs(att - cs)), .groups = "drop") %>%
  arrange(window, max_abs_diff)
write_csv(summ, file.path(OUT_DIR, "summary.csv"))

cat("\n=== |LP-DiD arm - CS| by window (per-horizon, h =", min(hs), "..",
    max(hs), ") ===\n")
print(as.data.frame(summ), row.names = FALSE, digits = 4)
cat("\nEquivalence holds where max_abs_diff is at machine precision (~1e-15).\n")
cat("Outputs ->", OUT_DIR, "\n")
