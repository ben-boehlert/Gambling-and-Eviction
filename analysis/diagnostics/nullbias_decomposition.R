################################################################################
# analysis/diagnostics/nullbias_decomposition.R
#
# Null-bias decomposition for the state-level D1 pseudo-treatment placement in
# the blinded power framework (quality_reports/nullbias_decomposition_2026-08-25.md).
# Run ONLY after analysis/diagnostics/nullbias_verify_reconstruction.R has
# PASSED (it must print "VERIFICATION PASSED.").
#
# For every rep of the shift12_gate_{vwatt,ewatt} spliced scenarios (2,000
# reps each), reconstructs the D1 pseudo-schedule from the seed_rep recorded
# in the run's own partial CSV, builds placement features, and joins them to
# the recorded (already-estimated) att for twfe and lpdid. No re-estimation
# is performed here (that would be redundant with, and slower than, the
# verification gate) -- only schedule reconstruction + feature extraction +
# a join against the recorded results.
#
# Writes ONLY to output/nullbias_decomposition/.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
  library(purrr)
})

stopifnot(getwd() != "" )  # run from repo root per CLAUDE.md convention

for (mod in c("config.R", "blindness_checks.R", "load_blinded_panel.R",
              "make_pseudo_schedules.R", "run_scenario_grid.R")) {
  source(file.path("R", "power", mod))
}

.month_index <- function(d) year(d) * 12L + (month(d) - 1L)
CUTOFF_2023 <- as.Date("2023-01-01")
CHURN_STATES_HISTORICAL <- c("FL", "TX", "TN", "ID")  # CLAUDE.md rebuild narrative

RUNS <- list(
  vwatt = list(
    config  = "config/power_lpdid_shift12_gate_vwatt.yml",
    partial = "output_blinded_power/lpdid_shift12_gate_vwatt/partials/Sd8aabd8f96_mde_spliced-state-s2-drop-d1-count_nb-step-y_log1p-a0-tpanel.csv",
    cfg_overrides = list()
  ),
  ewatt = list(
    config  = "config/power_lpdid_shift12_gate_ewatt.yml",
    partial = "output_blinded_power/lpdid_shift12_gate_ewatt/partials/Sdc1ca7a0b5_mde_spliced-state-s2-drop-d1-count_nb-step-y_log1p-a0-tpanel.csv",
    cfg_overrides = list(lpdid_anchor = "event")  # see verification script comment
  )
)

# ---------------------------------------------------------------------------
# 1. Panel + per-state trend slopes (shared across both arms -- the panel
#    itself does not depend on lpdid_weights, only the schedule draw does).
# ---------------------------------------------------------------------------

cfg0 <- read_power_config(RUNS$vwatt$config)
panel <- load_blinded_panel(
  level = "state", treat_def = "shift12_start_date", anticipation = 6L,
  sample = "S2", covid = "drop", quarterly = FALSE, time_agg = "month",
  complete_periods_only = FALSE, config = cfg0
)
panel <- panel[panel$state_abb != "NV", , drop = FALSE]

state_features <- panel %>%
  group_by(state_abb) %>%
  summarise(
    coverage_months = n(),
    trend_slope     = coef(lm(y_log1p ~ t))[["t"]],
    .groups = "drop"
  )
cat("State-level trend slopes and coverage computed for", nrow(state_features),
   "states.\n")

# Composition-break QA (documented for completeness -- see memo for the
# finding that the CURRENT state panel is fixed-basket for every state).
qa <- read_csv("data/processed/state_panel_coverage_qa.csv", show_col_types = FALSE)
churn_flagged_qa <- qa$state_abb[qa$composition_risk != "ok"]
cat("States flagged composition_risk != 'ok' in state_panel_coverage_qa.csv:",
   if (length(churn_flagged_qa) == 0) "(none)" else paste(churn_flagged_qa, collapse = ", "),
   "\n")

# ---------------------------------------------------------------------------
# 2. Per-arm: reconstruct sched for every rep, build features, join to the
#    recorded att.
# ---------------------------------------------------------------------------

build_arm <- function(arm_name) {
  info <- RUNS[[arm_name]]
  cat(sprintf("\n==== Building features for %s ====\n", arm_name))

  cfg <- read_power_config(info$config)
  for (k in names(info$cfg_overrides)) cfg[[k]] <- info$cfg_overrides[[k]]
  grid <- expand_scenario_grid(cfg)
  grid <- grid[grid$name == "mde_spliced", , drop = FALSE]
  stopifnot(nrow(grid) == 1L)
  sc <- as.list(grid[1, ])
  sc$exclude_states <- as.character(unlist(sc$exclude_states %||% character(0)))

  recorded <- read_csv(info$partial, show_col_types = FALSE)
  stopifnot(unique(recorded$scenario_id) == sc$scenario_id)

  real_schedule <- guarded_read_csv(cfg$schedule)

  reps <- sort(unique(recorded$rep))
  cat("scenario_id:", sc$scenario_id, " | reps:", length(reps), "\n")

  out <- vector("list", length(reps))
  n_infeasible <- 0L
  for (j in seq_along(reps)) {
    rep <- reps[j]
    seed_rep <- unique(recorded$seed_rep[recorded$rep == rep])[1]

    sched <- tryCatch(
      make_pseudo_schedule(
        design = sc$design, panel = panel, real_schedule = real_schedule,
        treat_def = sc$treat_def, min_pre = sc$min_pre, min_post = sc$min_post,
        seed = seed_rep, template = sc$template
      ),
      error = function(e) e)

    if (inherits(sched, "condition")) {
      n_infeasible <- n_infeasible + 1L
      next
    }

    sched <- sched %>%
      left_join(state_features, by = "state_abb") %>%
      mutate(pseudo_g_idx = .month_index(.data$pseudo_g))

    n_treated <- nrow(sched)
    com_idx   <- mean(sched$pseudo_g_idx)
    sd_idx    <- sd(sched$pseudo_g_idx)
    cor_date_trend    <- suppressWarnings(cor(sched$pseudo_g_idx, sched$trend_slope))
    cor_date_trend_sp <- suppressWarnings(cor(sched$pseudo_g_idx, sched$trend_slope,
                                              method = "spearman"))
    cor_date_coverage <- suppressWarnings(cor(sched$pseudo_g_idx, sched$coverage_months))
    share_after_2023  <- mean(sched$pseudo_g >= CUTOFF_2023)

    # 12-month post-window share of person-months after 2023-01 (lpdid_post
    # default = 12). Clipped to whatever calendar months the panel offers.
    panel_max_idx <- max(.month_index(panel$month_date))
    post_frac <- vapply(seq_len(nrow(sched)), function(k) {
      g_idx <- sched$pseudo_g_idx[k]
      win_end <- min(g_idx + 11L, panel_max_idx)
      if (win_end < g_idx) return(NA_real_)
      months_idx <- seq(g_idx, win_end)
      mean(months_idx >= .month_index(CUTOFF_2023))
    }, numeric(1))
    frac_postmonths_after2023 <- mean(post_frac, na.rm = TRUE)

    treated_states <- sort(sched$state_abb)
    n_churn_treated <- sum(CHURN_STATES_HISTORICAL %in% treated_states)
    all_churn_control <- n_churn_treated == 0L

    out[[j]] <- tibble(
      weight_arm = arm_name, rep = rep, seed_rep = seed_rep,
      n_treated = n_treated,
      com_month_idx = com_idx, sd_month_idx = sd_idx,
      cor_date_trend = cor_date_trend, cor_date_trend_spearman = cor_date_trend_sp,
      cor_date_coverage = cor_date_coverage,
      share_treated_after2023 = share_after_2023,
      frac_postmonths_after2023 = frac_postmonths_after2023,
      n_churn_states_treated = n_churn_treated,
      all_churn_states_control = all_churn_control,
      treated_states = paste(treated_states, collapse = ";")
    )
  }
  cat("infeasible/failed schedule draws:", n_infeasible, "of", length(reps), "\n")
  feat <- bind_rows(out)

  att_wide <- recorded %>%
    filter(.data$inference == "analytic") %>%
    select(rep, estimator, att) %>%
    tidyr::pivot_wider(names_from = estimator, values_from = att,
                       names_prefix = "att_")

  feat %>% left_join(att_wide, by = "rep")
}

feat_vwatt <- build_arm("vwatt")
feat_ewatt <- build_arm("ewatt")

dir.create("output/nullbias_decomposition", recursive = TRUE, showWarnings = FALSE)
write_csv(feat_vwatt, "output/nullbias_decomposition/rep_features_vwatt.csv")
write_csv(feat_ewatt, "output/nullbias_decomposition/rep_features_ewatt.csv")
combined <- bind_rows(feat_vwatt, feat_ewatt)
write_csv(combined, "output/nullbias_decomposition/rep_features_combined.csv")

cat("\nRows: vwatt =", nrow(feat_vwatt), " ewatt =", nrow(feat_ewatt), "\n")
cat("n_treated range (should be near-constant):",
   paste(range(combined$n_treated, na.rm = TRUE), collapse = "-"), "\n")

# ---------------------------------------------------------------------------
# 3. Decomposition: regressions + conditional-mean contrasts
# ---------------------------------------------------------------------------

feature_cols <- c("com_month_idx", "sd_month_idx", "cor_date_trend",
                  "cor_date_coverage", "share_treated_after2023",
                  "frac_postmonths_after2023", "n_churn_states_treated")

fit_and_report <- function(df, outcome, label) {
  df2 <- df[stats::complete.cases(df[, c(outcome, feature_cols)]), , drop = FALSE]
  form_full <- reformulate(feature_cols, response = outcome)
  m_full <- lm(form_full, data = df2)
  s_full <- summary(m_full)

  # Univariate R^2 for each feature, to see which channel carries the signal.
  uni <- lapply(feature_cols, function(f) {
    m <- lm(reformulate(f, response = outcome), data = df2)
    tibble(feature = f, r2 = summary(m)$r.squared,
          coef = coef(m)[[2]], p = summary(m)$coefficients[2, 4])
  }) %>% bind_rows()

  list(label = label, n = nrow(df2), mean_att = mean(df2[[outcome]]),
      full_r2 = s_full$r.squared, full_model = m_full, full_summary = s_full,
      univariate = uni)
}

targets <- list(
  list(df = feat_vwatt, outcome = "att_lpdid", label = "vwatt: lpdid (variance-weighted)"),
  list(df = feat_vwatt, outcome = "att_twfe",  label = "vwatt: twfe"),
  list(df = feat_ewatt, outcome = "att_lpdid", label = "ewatt: lpdid (equally-weighted)"),
  list(df = feat_ewatt, outcome = "att_twfe",  label = "ewatt: twfe")
)

reg_results <- lapply(targets, function(tg) fit_and_report(tg$df, tg$outcome, tg$label))
names(reg_results) <- vapply(targets, function(tg) paste(tg$df$weight_arm[1], tg$outcome, sep = "_"),
                             character(1))

cat("\n\n================ REGRESSION SUMMARY ================\n")
reg_summary_rows <- list()
for (r in reg_results) {
  cat(sprintf("\n--- %s (n=%d, mean att = %.4f) ---\n", r$label, r$n, r$mean_att))
  cat(sprintf("Full model R^2 (all features): %.4f\n", r$full_r2))
  print(r$univariate)
  reg_summary_rows[[length(reg_summary_rows) + 1L]] <- r$univariate %>%
    mutate(target = r$label, full_model_r2 = r$full_r2, n = r$n, mean_att = r$mean_att)
}
reg_summary <- bind_rows(reg_summary_rows) %>%
  select(target, n, mean_att, full_model_r2, feature, r2, coef, p)
write_csv(reg_summary, "output/nullbias_decomposition/regression_summary.csv")

# Full-model coefficient tables (with SEs) saved separately for the memo.
full_coef_rows <- lapply(names(reg_results), function(nm) {
  r <- reg_results[[nm]]
  co <- as.data.frame(r$full_summary$coefficients)
  co$term <- rownames(co)
  co$target <- r$label
  co
}) %>% bind_rows()
write_csv(full_coef_rows, "output/nullbias_decomposition/regression_full_coefficients.csv")

# ---- Conditional-mean contrasts -------------------------------------------

cat("\n\n================ CONDITIONAL-MEAN CONTRASTS ================\n")
contrast_rows <- list()
for (tg in targets) {
  df <- tg$df
  outcome <- tg$outcome
  # (a) churn states (historical FL/TX/TN/ID) all-control vs any-treated
  grp <- df %>%
    group_by(all_churn_states_control) %>%
    summarise(mean_att = mean(.data[[outcome]], na.rm = TRUE),
             n = n(), .groups = "drop")
  t_a <- tryCatch(t.test(df[[outcome]] ~ df$all_churn_states_control),
                  error = function(e) NULL)
  cat(sprintf("\n[%s] churn-state contrast (all-control vs any-treated):\n", tg$label))
  print(grp)
  if (!is.null(t_a)) cat(sprintf("  t-test p = %.4f\n", t_a$p.value))
  contrast_rows[[length(contrast_rows) + 1L]] <- grp %>%
    mutate(target = tg$label, contrast = "churn_states_all_control",
          p_value = if (!is.null(t_a)) t_a$p.value else NA_real_)

  # (b) adoption-date x trend correlation quartiles
  q <- quantile(df$cor_date_trend, probs = seq(0, 1, 0.25), na.rm = TRUE)
  df$cor_q <- cut(df$cor_date_trend, breaks = q, include.lowest = TRUE,
                  labels = c("Q1 (most neg.)", "Q2", "Q3", "Q4 (most pos.)"))
  grp2 <- df %>%
    group_by(cor_q) %>%
    summarise(mean_att = mean(.data[[outcome]], na.rm = TRUE),
             mean_cor = mean(cor_date_trend, na.rm = TRUE),
             n = n(), .groups = "drop")
  cat(sprintf("\n[%s] att by cor(date, trend_slope) quartile:\n", tg$label))
  print(grp2)
  contrast_rows[[length(contrast_rows) + 1L]] <- grp2 %>%
    rename(group = cor_q) %>%
    mutate(target = tg$label, contrast = "cor_date_trend_quartile", p_value = NA_real_) %>%
    select(group, mean_att, n, target, contrast, p_value)
}
# Normalize column names before writing (group is either logical or factor).
contrast_out <- bind_rows(lapply(contrast_rows, function(x) {
  if ("all_churn_states_control" %in% names(x)) {
    x %>% rename(group = all_churn_states_control) %>%
      mutate(group = as.character(group)) %>%
      select(group, mean_att, n, target, contrast, p_value)
  } else {
    x %>% mutate(group = as.character(group)) %>%
      select(group, mean_att, n, target, contrast, p_value)
  }
}))
write_csv(contrast_out, "output/nullbias_decomposition/conditional_mean_contrasts.csv")

cat("\n\nAll decomposition outputs written to output/nullbias_decomposition/.\n")
