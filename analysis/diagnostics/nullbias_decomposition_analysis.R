################################################################################
# analysis/diagnostics/nullbias_decomposition_analysis.R
#
# STEP 3 (regression decomposition) for
# quality_reports/nullbias_decomposition_2026-08-25.md, run against the
# rep-level feature CSVs already written by
# analysis/diagnostics/nullbias_decomposition.R
# (output/nullbias_decomposition/rep_features_{vwatt,ewatt}.csv).
#
# Split out as its own script because the feature-reconstruction pass (2,000
# schedule draws x 2 arms) is the slow part (~18 min) and the regression
# pass is seconds; iterating on the regression spec should not re-pay that
# cost. Two features (sd_month_idx, share_treated_after2023) turned out to
# be numerically constant across all 4,000 reps -- the D1 template anchor has
# almost no slack in this panel window, so calendar TIMING of the pseudo
# cohorts barely varies rep to rep; only WHICH STATES are assigned to the
# (nearly fixed) cohort dates varies. Those two columns are dropped from the
# regression feature set (zero variance -> aliased / uninformative) but kept
# in the raw CSVs and flagged in the memo as a finding in their own right.
#
# Writes ONLY to output/nullbias_decomposition/.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
  library(tidyr)
})

feat_vwatt <- read_csv("output/nullbias_decomposition/rep_features_vwatt.csv",
                       show_col_types = FALSE)
feat_ewatt <- read_csv("output/nullbias_decomposition/rep_features_ewatt.csv",
                       show_col_types = FALSE)

feature_cols <- c("com_month_idx", "cor_date_trend", "cor_date_coverage",
                  "frac_postmonths_after2023", "n_churn_states_treated")
dropped_cols <- c("sd_month_idx", "share_treated_after2023")

for (arm_df in list(vwatt = feat_vwatt, ewatt = feat_ewatt)) {
  for (f in dropped_cols) {
    cat(sprintf("[%s] %s: sd = %.6g (dropped from regression, zero variance)\n",
               arm_df$weight_arm[1], f, sd(arm_df[[f]], na.rm = TRUE)))
  }
}

fit_and_report <- function(df, outcome, label) {
  df2 <- df[stats::complete.cases(df[, c(outcome, feature_cols)]), , drop = FALSE]
  form_full <- reformulate(feature_cols, response = outcome)
  m_full <- lm(form_full, data = df2)
  s_full <- summary(m_full)

  uni <- lapply(feature_cols, function(f) {
    m <- lm(reformulate(f, response = outcome), data = df2)
    sm <- summary(m)
    has_slope <- nrow(sm$coefficients) >= 2L
    tibble(feature = f,
          r2   = sm$r.squared,
          coef = if (has_slope) coef(m)[[2]] else NA_real_,
          p    = if (has_slope) sm$coefficients[2, 4] else NA_real_)
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

cat("\n\n================ REGRESSION SUMMARY ================\n")
reg_summary_rows <- list()
for (r in reg_results) {
  cat(sprintf("\n--- %s (n=%d, mean att = %.4f) ---\n", r$label, r$n, r$mean_att))
  cat(sprintf("Full model R^2 (all features): %.4f\n", r$full_r2))
  print(as.data.frame(r$univariate))
  reg_summary_rows[[length(reg_summary_rows) + 1L]] <- r$univariate %>%
    mutate(target = r$label, full_model_r2 = r$full_r2, n = r$n, mean_att = r$mean_att)
}
reg_summary <- bind_rows(reg_summary_rows) %>%
  select(target, n, mean_att, full_model_r2, feature, r2, coef, p)
write_csv(reg_summary, "output/nullbias_decomposition/regression_summary.csv")

full_coef_rows <- lapply(seq_along(reg_results), function(i) {
  r <- reg_results[[i]]
  co <- as.data.frame(r$full_summary$coefficients)
  co$term <- rownames(co)
  co$target <- r$label
  co
}) %>% bind_rows()
write_csv(full_coef_rows, "output/nullbias_decomposition/regression_full_coefficients.csv")
cat("\n\n================ FULL-MODEL COEFFICIENTS ================\n")
print(as_tibble(full_coef_rows), n = 100)

# ---------------------------------------------------------------------------
# Conditional-mean contrasts
# ---------------------------------------------------------------------------

cat("\n\n================ CONDITIONAL-MEAN CONTRASTS ================\n")
contrast_rows <- list()
for (tg in targets) {
  df <- tg$df
  outcome <- tg$outcome

  # (a) churn states (historical FL/TX/TN/ID) all-control vs any-treated.
  grp <- df %>%
    group_by(all_churn_states_control) %>%
    summarise(mean_att = mean(.data[[outcome]], na.rm = TRUE),
             n = n(), .groups = "drop")
  t_a <- tryCatch(t.test(df[[outcome]] ~ df$all_churn_states_control),
                  error = function(e) NULL)
  cat(sprintf("\n[%s] churn-state contrast (all-control vs any-treated):\n", tg$label))
  print(as.data.frame(grp))
  if (!is.null(t_a)) cat(sprintf("  t-test p = %.4f, diff = %.5f\n",
                                t_a$p.value, diff(rev(t_a$estimate))))
  contrast_rows[[length(contrast_rows) + 1L]] <- grp %>%
    rename(group = all_churn_states_control) %>%
    mutate(group = as.character(group)) %>%
    mutate(target = tg$label, contrast = "churn_states_all_control",
          p_value = if (!is.null(t_a)) t_a$p.value else NA_real_) %>%
    select(group, mean_att, n, target, contrast, p_value)

  # (b) adoption-date x trend correlation quartiles.
  q <- quantile(df$cor_date_trend, probs = seq(0, 1, 0.25), na.rm = TRUE)
  df$cor_q <- cut(df$cor_date_trend, breaks = unique(q), include.lowest = TRUE,
                  labels = NULL)
  grp2 <- df %>%
    group_by(cor_q) %>%
    summarise(mean_att = mean(.data[[outcome]], na.rm = TRUE),
             mean_cor = mean(cor_date_trend, na.rm = TRUE),
             n = n(), .groups = "drop") %>%
    arrange(mean_cor)
  cat(sprintf("\n[%s] att by cor(pseudo_date, state trend slope) quartile:\n", tg$label))
  print(as.data.frame(grp2))
  # Linear test: does mean_att increase monotonically with the quartile's
  # mean correlation? Report the quartile-level OLS slope too.
  m_q <- lm(mean_att ~ mean_cor, data = grp2)
  cat(sprintf("  quartile-level slope (att ~ mean_cor): %.4f\n", coef(m_q)[[2]]))
  contrast_rows[[length(contrast_rows) + 1L]] <- grp2 %>%
    rename(group = cor_q) %>%
    mutate(group = as.character(group)) %>%
    mutate(target = tg$label, contrast = "cor_date_trend_quartile", p_value = NA_real_) %>%
    select(group, mean_att, n, target, contrast, p_value)
}
contrast_out <- bind_rows(contrast_rows)
write_csv(contrast_out, "output/nullbias_decomposition/conditional_mean_contrasts.csv")

# ---------------------------------------------------------------------------
# Extra diagnostic: does the OVERALL bias differ between arms with near-zero
# cor_date_trend (placement ~exchangeable in this rep) vs strongly negative
# cor_date_trend? A negative correlation means late-adopting (high pseudo_g)
# states get assigned to states with LOWER trend slope -- i.e., states with
# earlier real-panel entry / steeper decline get pushed to shorter apparent
# post windows. Report the raw scatter correlation between att and
# cor_date_trend directly (already the univariate coefficient above) plus a
# decile table for a finer look.
# ---------------------------------------------------------------------------
cat("\n\n================ DECILE TABLE: att vs cor_date_trend ================\n")
decile_rows <- list()
for (tg in targets) {
  df <- tg$df
  outcome <- tg$outcome
  df$decile <- ntile(df$cor_date_trend, 10)
  dgrp <- df %>%
    group_by(decile) %>%
    summarise(mean_cor = mean(cor_date_trend), mean_att = mean(.data[[outcome]]),
             n = n(), .groups = "drop")
  cat(sprintf("\n[%s]\n", tg$label))
  print(as.data.frame(dgrp))
  decile_rows[[length(decile_rows) + 1L]] <- dgrp %>% mutate(target = tg$label)
}
write_csv(bind_rows(decile_rows), "output/nullbias_decomposition/decile_table_cor_date_trend.csv")

cat("\n\nAll regression/contrast outputs written to output/nullbias_decomposition/.\n")
