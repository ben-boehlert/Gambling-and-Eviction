#!/usr/bin/env Rscript
################################################################################
# analysis/cheap_sims/04_jackknife_diag.R
#
# SIM 4: CSDID cluster-jackknife (CV3) estimand-integrity diagnostics.
#
# The null REJECTION question is already answered by the 200-rep calibration in
# data/output/cs_cv3_calibration/state/ (Karim-Nielsen-MacKinnon-Webb CV3
# implemented in R/power/run_estimators.R): CS analytic rejects 21.5%, CV3
# rejects 0.5% with SE/SD = 1.24 -- CV3 over-corrects on this design. This
# script adds what that run did not record:
#
#   (A) Placebo-world LOSO anatomy (blinded, calendar-preserving schedules,
#       same seeds as the cheap grid): per delete-one-state replicate, which
#       ATT(g,t) cells disappear, how aggregation weights shift, and how much
#       of the CV3 spread is composition change rather than sampling noise.
#   (B) REAL-DATA leave-one-state-out ATT estimates (UNBLINDED -- uses actual
#       treatment timing and treated-period outcomes) as an influence
#       diagnostic, with the same cell-disappearance bookkeeping.
#
# Env: N_JACK_REPS (20), N_CORES (detectCores-2), SKIP_REAL / SKIP_PLACEBO.
# Run from repo root:  Rscript analysis/cheap_sims/04_jackknife_diag.R
################################################################################

source("analysis/cheap_sims/00_common.R")
suppressPackageStartupMessages(library(parallel))
theme_set(theme_minimal())

cfg <- cheap_config()
N_JACK_REPS <- .cs_envint("N_JACK_REPS", 20L)
N_CORES     <- .cs_envint("N_CORES", max(1L, parallel::detectCores() - 2L))
SCENARIO    <- 902L   # pair with the cheap grid's placebo draws

out_dir <- file.path(cfg$out_dir, "jackknife")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(cfg$out_dir, "figures"), showWarnings = FALSE)

pan   <- readRDS(file.path(cfg$out_dir, "design_panel.rds"))
tmpl  <- placebo_template(pan$states)

# ---- shared LOSO anatomy ----------------------------------------------------

# Post-treatment finite cells of an att_gt fit, with simple-agg weights.
.cells_of <- function(a, G) {
  cc <- tibble(g = a$group, t = a$t, att = a$att) %>%
    filter(t >= g, is.finite(att), g >= 2L)
  if (nrow(cc) == 0L) return(cc %>% mutate(w = numeric(0)))
  pg <- vapply(cc$g, function(g) mean(G == g), numeric(1))
  cc %>% mutate(w = pg / sum(pg))
}

# Fit CS on a frame (unit_id/state_abb/month_date/y_sim/pseudo_g), full +
# leave-one-state-out. Returns list(full = ..., loso = tibble).
loso_anatomy <- function(frame, label) {
  cs_full <- fit_cs(frame)
  G_full  <- cs_full$est %>% distinct(id, g_int) %>% arrange(id) %>% pull(g_int)
  cells_full <- .cells_of(cs_full$fit, G_full)
  simple_full <- did::aggte(cs_full$fit, type = "simple", na.rm = TRUE)
  att_full <- as.numeric(simple_full$overall.att)

  states <- sort(unique(frame$state_abb))
  treated_states <- frame %>% filter(!is.na(pseudo_g)) %>%
    distinct(state_abb) %>% pull()

  loso <- map_dfr(states, function(h) {
    sub <- frame %>% filter(state_abb != h)
    res <- tryCatch({
      cs_h <- suppressMessages(suppressWarnings(fit_cs(sub)))
      G_h  <- cs_h$est %>% distinct(id, g_int) %>% arrange(id) %>% pull(g_int)
      cells_h <- .cells_of(cs_h$fit, G_h) %>%
        mutate(g_month = cs_h$months[g], t_month = cs_h$months[t])
      simple_h <- did::aggte(cs_h$fit, type = "simple", na.rm = TRUE)

      cf <- cells_full %>%
        mutate(g_month = cs_full$months[g], t_month = cs_full$months[t])
      shared <- cf %>%
        inner_join(cells_h, by = c("g_month", "t_month"),
                   suffix = c("_f", "_h"))
      lost <- anti_join(cf, cells_h, by = c("g_month", "t_month"))
      wshift <- if (nrow(shared)) {
        sum(abs(shared$w_f / sum(shared$w_f) -
                  shared$w_h / sum(shared$w_h))) / 2
      } else NA_real_
      tibble(
        dropped_state = h,
        dropped_treated = h %in% treated_states,
        att_loso = as.numeric(simple_h$overall.att),
        n_cells_full = nrow(cf), n_cells_lost = nrow(lost),
        n_cohorts_lost = n_distinct(lost$g_month),
        share_weight_lost = sum(cf$w[paste(cf$g_month, cf$t_month) %in%
                                       paste(lost$g_month, lost$t_month)]),
        weight_shift_shared = wshift, converged = TRUE, error_msg = NA_character_)
    }, error = function(e) tibble(
      dropped_state = h, dropped_treated = h %in% treated_states,
      att_loso = NA_real_, n_cells_full = nrow(cells_full),
      n_cells_lost = NA_integer_, n_cohorts_lost = NA_integer_,
      share_weight_lost = NA_real_, weight_shift_shared = NA_real_,
      converged = FALSE, error_msg = conditionMessage(e)))
    res
  })

  ok <- loso %>% filter(converged, is.finite(att_loso))
  H <- nrow(ok)
  cv3_se <- if (H >= 2L)
    sqrt(((H - 1) / H) * sum((ok$att_loso - att_full)^2)) else NA_real_

  list(label = label, att_full = att_full,
       se_analytic = as.numeric(simple_full$overall.se),
       cv3_se = cv3_se, loso = loso %>% mutate(label = label))
}

# ---- (A) placebo-world anatomy ---------------------------------------------

if (!nzchar(Sys.getenv("SKIP_PLACEBO"))) {
  cat(sprintf("=== Placebo LOSO anatomy: %d reps x ~%d states ===\n",
              N_JACK_REPS, n_distinct(pan$sim$state_abb)))
  t0 <- Sys.time()
  plc <- mclapply(seq_len(N_JACK_REPS), function(rep) {
    seed_rep <- cfg$base_seed + 10007L * rep + 101L * SCENARIO
    sched <- make_calendar_placebo(pan$sim, tmpl, cfg$min_pre, cfg$min_post,
                                   seed = seed_rep)
    frame <- pan$sim %>%
      left_join(sched, by = "state_abb") %>%
      mutate(y_sim = y_log1p)          # null: pure pass-through
    an <- tryCatch(loso_anatomy(frame, sprintf("placebo_rep%03d", rep)),
                   error = function(e) NULL)
    if (is.null(an)) return(NULL)
    list(summary = tibble(rep = rep, att_full = an$att_full,
                          se_analytic = an$se_analytic, cv3_se = an$cv3_se),
         loso = an$loso %>% mutate(rep = rep))
  }, mc.cores = N_CORES, mc.preschedule = FALSE)
  plc <- plc[!vapply(plc, is.null, logical(1))]

  plc_sum  <- bind_rows(lapply(plc, `[[`, "summary"))
  plc_loso <- bind_rows(lapply(plc, `[[`, "loso"))
  write_csv(plc_sum,  file.path(out_dir, "placebo_cv3_summary.csv"))
  write_csv(plc_loso, file.path(out_dir, "placebo_loso_cells.csv"))

  cat(sprintf("done in %.1f min\n",
              as.numeric(difftime(Sys.time(), t0, units = "mins"))))

  anat <- plc_loso %>%
    filter(converged) %>%
    left_join(plc_sum %>% select(rep, att_full), by = "rep") %>%
    group_by(dropped_treated) %>%
    summarise(
      n = n(),
      mean_cells_lost = mean(n_cells_lost),
      share_reps_losing_cells = mean(n_cells_lost > 0),
      mean_share_weight_lost = mean(share_weight_lost),
      mean_weight_shift_shared = mean(weight_shift_shared, na.rm = TRUE),
      sd_att_loso_dev = sd(att_loso - att_full),
      .groups = "drop")
  cat("\n--- Cell disappearance by dropped-cluster type (placebo, null) ---\n")
  print(as.data.frame(anat), row.names = FALSE, digits = 3)
  write_csv(anat, file.path(out_dir, "placebo_loso_anatomy.csv"))
}

# ---- (B) real-data LOSO (UNBLINDED) ----------------------------------------

if (!nzchar(Sys.getenv("SKIP_REAL"))) {
  cat("\n=== REAL-DATA LOSO (unblinded influence diagnostic) ===\n")
  real_frame <- pan$design %>%
    filter(!covid_m) %>%
    transmute(unit_id = state_abb, state_abb, month_date,
              y_sim = y_log1p, pseudo_g = online_g)
  tkey <- .month_idx(real_frame$month_date)
  real_frame$t <- as.integer(tkey - min(tkey) + 1L)
  t0 <- Sys.time()
  rl <- loso_anatomy(real_frame, "real_data")
  cat(sprintf("done in %.1f min\n",
              as.numeric(difftime(Sys.time(), t0, units = "mins"))))

  write_csv(rl$loso, file.path(out_dir, "real_loso_att.csv"))
  cat(sprintf("\nReal data: ATT = %.4f | analytic SE = %.4f | CV3 SE = %.4f (ratio %.2f)\n",
              rl$att_full, rl$se_analytic, rl$cv3_se, rl$cv3_se / rl$se_analytic))

  p_inf <- rl$loso %>%
    filter(converged) %>%
    mutate(state = fct_reorder(dropped_state, att_loso)) %>%
    ggplot(aes(att_loso, state, color = dropped_treated)) +
    geom_vline(xintercept = rl$att_full, linetype = "dashed") +
    geom_point() +
    scale_color_manual(values = c(`FALSE` = "grey55", `TRUE` = "firebrick"),
                       labels = c("control dropped", "treated dropped")) +
    labs(x = "Leave-one-state-out overall ATT (log points)", y = NULL,
         color = NULL)
  ggsave(file.path(cfg$out_dir, "figures", "real_loso_influence.pdf"),
         p_inf, width = 7, height = 8)

  lost_t <- rl$loso %>% filter(dropped_treated, converged)
  cat(sprintf("Treated deletions losing cells: %d/%d | mean cells lost %.1f | mean weight share lost %.3f\n",
              sum(lost_t$n_cells_lost > 0), nrow(lost_t),
              mean(lost_t$n_cells_lost), mean(lost_t$share_weight_lost)))
}

cat("\nSim 4 diagnostics complete. Outputs in", out_dir, "\n")
