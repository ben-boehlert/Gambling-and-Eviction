#!/usr/bin/env Rscript
################################################################################
# pretrends_did2s_cleaned.R
#
# Pre-trends pipeline using did2s (Gardner 2022) on the cleaned monthly panel.
#
# Specs run side-by-side:
#   A: baseline (2016-2024, drop full COVID, ME excluded)
#   B: cleaned + tighter window (2018-2024, drop full COVID, ME excluded,
#      drop UT 2023 Nov-Dec)
#
# Pretrends checks:
#   1. did2s::event_study() — relative-time coefficients
#   2. Joint Wald F-test on pre-period coefficients
#   3. HonestDiD sensitivity (Rambachan-Roth 2023) at M ∈ {0, 0.5, 1, 1.5, 2}
#   4. pretrends (Roth 2022) power against linear and "smoothness" violations
#   5. Overall ATT via did2s with post_treat indicator
#
# Output: data/output/pretrends_did2s_cleaned/<spec>/{event_study.csv,
#   summary.csv, event_study_plot.pdf, honestdid_sensitivity.pdf}
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr); library(glue)
  library(fixest); library(tibble); library(ggplot2)
  library(did2s); library(HonestDiD); library(pretrends)
})

source("utils/eviction_treatment_schedule.R")

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || !nzchar(as.character(x))) y else x

OUT_DIR <- "data/output/pretrends_did2s_cleaned"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

PRE_WINDOW  <- -12L  # most-negative relative time
POST_WINDOW <- 12L   # most-positive relative time

ym_index <- function(d) as.integer(as.integer(format(d,"%Y"))*12 + as.integer(format(d,"%m")))

bad_obs <- tibble::tribble(
  ~state_abb, ~month_date,
  "ID","2016-01-01","ID","2016-02-01","ID","2016-03-01","ID","2016-04-01",
  "ID","2016-05-01","ID","2016-06-01","ID","2016-07-01",
  "CT","2016-01-01","CT","2016-02-01",
  "UT","2023-11-01","UT","2023-12-01"
) |> mutate(month_date = as.Date(month_date))

# ----------------------------- panel build ------------------------------------

build_panel <- function(label, min_date, max_date, drop_bad,
                         drop_start = as.Date("2020-03-01"),
                         drop_end = as.Date("2022-03-31")) {
  raw <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                  show_col_types=FALSE) |>
    transmute(state_abb=as.character(state_abb),
              month_date=as.Date(month_date),
              filings_count=as.numeric(filings_count)) |>
    filter(month_date >= as.Date(min_date), month_date <= as.Date(max_date),
           state_abb != "ME") |>
    filter(!(month_date >= drop_start & month_date <= drop_end))

  if (drop_bad) raw <- raw |> anti_join(bad_obs, by=c("state_abb","month_date"))

  cov <- raw |> count(state_abb, name="n") |> arrange(desc(n))
  keep <- cov |> filter(n == max(n)) |> pull(state_abb)
  raw <- raw |> filter(state_abb %in% keep)
  n_pre <- n_distinct(raw$state_abb)
  common <- raw |> count(month_date, name="n") |> filter(n == n_pre) |> pull(month_date)
  raw <- raw |> filter(month_date %in% common)

  treat <- load_eviction_treatment_schedule(
    treat_file="data/raw/sports_gambling_legalization_dates.csv",
    treat_date_col="online_start_date", states=raw$state_abb)

  panel <- raw |> left_join(treat, by="state_abb") |>
    mutate(y = log1p(pmax(filings_count, 0)),
           t = ym_index(month_date),
           g_raw = ifelse(is.na(treat_start), 0L, ym_index(treat_start)),
           g_raw = as.integer(g_raw),
           id = as.integer(as.factor(state_abb)))

  # Snap g to the first available t >= g_raw (handles treatment dates that
  # fall inside the dropped COVID window or outside the panel range).
  t_values <- sort(unique(panel$t))
  snap_g <- function(g_raw) {
    if (g_raw == 0L) return(0L)
    candidates <- t_values[t_values >= g_raw]
    if (length(candidates) == 0L) return(0L)  # treatment is after panel ends
    as.integer(min(candidates))
  }
  state_g <- panel |> distinct(state_abb, g_raw) |>
    mutate(g = vapply(g_raw, snap_g, integer(1)))

  panel <- panel |>
    select(-g_raw) |>
    left_join(state_g, by = "state_abb") |>
    mutate(rel_time = ifelse(g == 0L, NA_integer_, t - g),
           post_treat = as.integer(g > 0L & t >= g),
           treated = as.integer(g > 0L))

  cat("Treatment-snapping summary:\n")
  state_g |> mutate(snapped = g != g_raw) |>
    filter(g_raw > 0L) |> arrange(g_raw) |> print(n = Inf)

  attr(panel, "label") <- label
  panel
}

# ----------------------------- diagnostics for one spec -----------------------

run_spec <- function(panel, label) {
  spec_dir <- file.path(OUT_DIR, gsub("[^A-Za-z0-9]+", "_", label))
  dir.create(spec_dir, recursive = TRUE, showWarnings = FALSE)
  cat(strrep("=", 60), "\n", sep="")
  cat("SPEC:", label, "\n")
  cat(strrep("=", 60), "\n", sep="")
  n_states  <- n_distinct(panel$state_abb)
  n_treated <- n_distinct(panel$state_abb[panel$g > 0L])
  n_months  <- n_distinct(panel$t)
  cat(glue("{n_states} states ({n_treated} treated), {n_months} months, {nrow(panel)} obs"), "\n\n")

  dat <- as.data.frame(panel)

  # Bin extreme leads/lags
  dat$rel_bin <- pmin(pmax(dat$rel_time, PRE_WINDOW), POST_WINDOW)
  # Drop reference period (rel_time = -1) by setting it as the omitted base
  # via fixest::i() with reference = -1.

  # ---- 1. did2s overall ATT --------------------------------------------------
  cat("[1] did2s overall ATT\n")
  d2s_att <- did2s(data=dat, yname="y",
                   first_stage = ~ 0 | id + t,
                   second_stage = ~ post_treat,
                   treatment = "post_treat",
                   cluster_var = "id")
  att_overall <- as.numeric(coef(d2s_att)[1])
  se_overall  <- sqrt(diag(stats::vcov(d2s_att)))[1]
  df_clust    <- n_states - 1L
  p_overall   <- 2 * stats::pt(-abs(att_overall/se_overall), df=df_clust)
  cat(glue("  ATT={round(att_overall,4)}, SE={round(se_overall,4)}, p={round(p_overall,4)}"), "\n\n")

  # ---- 2. did2s event study --------------------------------------------------
  cat("[2] did2s event study\n")
  # Use did2s event_study(): returns event-study estimates from multiple methods
  # We extract the did2s ('did2s') estimator from the long-format result.
  es_long <- event_study(data = dat, yname = "y", idname = "id", tname = "t",
                          gname = "g", estimator = "did2s", verbose = FALSE)
  es_did2s <- as_tibble(es_long) |>
    mutate(rel_time = as.integer(term)) |>
    filter(rel_time >= PRE_WINDOW, rel_time <= POST_WINDOW) |>
    mutate(ci_lo = estimate - 1.96 * std.error,
           ci_hi = estimate + 1.96 * std.error) |>
    arrange(rel_time) |>
    dplyr::select(rel_time, estimate, std.error, ci_lo, ci_hi)

  cat(glue("  {nrow(es_did2s)} relative-time bins (window: {PRE_WINDOW} to {POST_WINDOW})"), "\n")
  print(as.data.frame(es_did2s), digits = 3)

  write_csv(es_did2s |> select(rel_time, estimate, std.error, ci_lo, ci_hi),
            file.path(spec_dir, "event_study.csv"))

  # ---- 3. Joint pre-trend test (fixest sunab + Wald) -----------------------
  cat("\n[3] Joint pre-trend test (Sun-Abraham event study + fixest::wald)\n")
  wald_stat <- NA_real_; wald_df <- 0L; wald_p <- NA_real_
  tryCatch({
    treated_dat <- dat[!is.na(dat$rel_time), ]
    treated_dat$rel_bin <- pmin(pmax(treated_dat$rel_time, PRE_WINDOW), POST_WINDOW)
    sa_fit <- feols(y ~ sunab(g, t, no_agg = TRUE) | id + t,
                    data = dat, cluster = ~id, warn=FALSE, notes=FALSE)
    pre_terms <- grep("event::-(2|3|4|5|6|7|8|9|10|11|12)\\b",
                      names(coef(sa_fit)), value = TRUE)
    if (length(pre_terms) >= 2L) {
      w <- fixest::wald(sa_fit, keep = pre_terms, print = FALSE)
      wald_stat <- as.numeric(w$stat)
      wald_df   <- as.integer(w$df1)
      wald_p    <- as.numeric(w$p)
      cat(glue("  Wald F({wald_df}, ...) = {round(wald_stat,2)}, p = {round(wald_p,4)}"), "\n")
    } else {
      cat("  No pre-period coefficients found in sunab fit\n")
    }
  }, error = function(e) {
    cat("  Wald test failed:", conditionMessage(e), "\n")
  })

  # Reuse fixest event-study fit for HonestDiD/pretrends below; we'll keep the
  # raw rel_factor regression too for later sections.
  dat$rel_factor <- factor(dat$rel_bin, levels = sort(unique(dat$rel_bin)))
  if ("-1" %in% levels(dat$rel_factor)) {
    dat$rel_factor <- relevel(dat$rel_factor, ref = "-1")
  }
  es_fit <- feols(y ~ i(rel_factor, treated, ref = "-1") | id + t,
                  data = dat[!is.na(dat$rel_time), ],
                  cluster = ~id, warn=FALSE, notes=FALSE)
  coefs <- coef(es_fit)
  vcov_mat <- stats::vcov(es_fit)

  # ---- 4. HonestDiD sensitivity ---------------------------------------------
  cat("\n[4] HonestDiD sensitivity (Rambachan-Roth 2023)\n")
  honest_results <- NULL
  tryCatch({
    # Get full event-study betas (pre + post) and vcov from fixest model
    es_terms <- names(coefs)[grepl("rel_factor::", names(coefs))]
    es_levels <- gsub(".*rel_factor::(-?\\d+).*", "\\1", es_terms)
    ord <- order(as.integer(es_levels))
    beta_es <- coefs[es_terms][ord]
    vcov_es <- vcov_mat[es_terms, es_terms][ord, ord]
    levels_int <- as.integer(es_levels)[ord]
    n_pre  <- sum(levels_int < 0L)
    n_post <- sum(levels_int >= 0L)

    if (n_pre >= 2L && n_post >= 1L) {
      sens_orig <- HonestDiD::createSensitivityResults_relativeMagnitudes(
        betahat = beta_es,
        sigma   = vcov_es,
        numPrePeriods  = n_pre,
        numPostPeriods = n_post,
        Mbarvec = c(0, 0.5, 1, 1.5, 2)
      )
      orig_ci <- HonestDiD::constructOriginalCS(
        betahat = beta_es, sigma = vcov_es,
        numPrePeriods  = n_pre,
        numPostPeriods = n_post)
      honest_results <- list(sens = sens_orig, orig = orig_ci,
                              n_pre = n_pre, n_post = n_post)
      print(sens_orig)
      cat(glue("  Original CI for first post-period: [{round(orig_ci$lb,3)}, {round(orig_ci$ub,3)}]"), "\n")

      # Plot
      p_sens <- HonestDiD::createSensitivityPlot_relativeMagnitudes(sens_orig, orig_ci)
      ggsave(file.path(spec_dir, "honestdid_sensitivity.pdf"),
             plot = p_sens, width = 7, height = 4.5, bg = "transparent")
    } else {
      cat(glue("  Insufficient pre/post periods (pre={n_pre}, post={n_post})"), "\n")
    }
  }, error = function(e) {
    cat("  HonestDiD failed:", conditionMessage(e), "\n")
  })

  # ---- 5. pretrends (Roth 2022) power ---------------------------------------
  cat("\n[5] pretrends (Roth 2022) power\n")
  pretrends_results <- NULL
  tryCatch({
    if (!is.null(honest_results) && honest_results$n_pre >= 2L) {
      es_terms <- names(coefs)[grepl("rel_factor::", names(coefs))]
      es_levels <- as.integer(gsub(".*rel_factor::(-?\\d+).*", "\\1", es_terms))
      ord <- order(es_levels)
      beta_es <- coefs[es_terms][ord]
      vcov_es <- vcov_mat[es_terms, es_terms][ord, ord]
      levels_int <- es_levels[ord]
      n_pre  <- sum(levels_int < 0L)
      n_post <- sum(levels_int >= 0L)

      # Slope detectable at 50% power against linear pretrend
      slope_50 <- pretrends::slope_for_power(
        sigma = vcov_es, targetPower = 0.50,
        tVec = levels_int, referencePeriod = -1L
      )
      slope_80 <- pretrends::slope_for_power(
        sigma = vcov_es, targetPower = 0.80,
        tVec = levels_int, referencePeriod = -1L
      )
      cat(glue("  Slope detectable at 50% power: {round(slope_50, 4)} per period"), "\n")
      cat(glue("  Slope detectable at 80% power: {round(slope_80, 4)} per period"), "\n")

      pretrends_results <- list(slope_50 = slope_50, slope_80 = slope_80)
    } else {
      cat("  Insufficient pre-periods for power calc\n")
    }
  }, error = function(e) {
    cat("  pretrends failed:", conditionMessage(e), "\n")
  })

  # ---- 6. Plot event study --------------------------------------------------
  cat("\n[6] Event study plot\n")
  plot_df <- es_did2s |> filter(rel_time >= PRE_WINDOW, rel_time <= POST_WINDOW)

  p_es <- ggplot(plot_df, aes(x = rel_time, y = estimate)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
    geom_vline(xintercept = -0.5, linetype = "dotted", color = "grey60") +
    geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.15) +
    geom_point(size = 1.6) +
    geom_line(linewidth = 0.4) +
    scale_x_continuous(breaks = seq(PRE_WINDOW, POST_WINDOW, 3)) +
    labs(x = "Months relative to treatment", y = "ATT (log filings)") +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank(),
          panel.grid.major.x = element_blank(),
          panel.background = element_rect(fill = "transparent", color = NA),
          plot.background  = element_rect(fill = "transparent", color = NA))

  ggsave(file.path(spec_dir, "event_study_plot.pdf"),
         plot = p_es, width = 7, height = 4.5, bg = "transparent")
  ggsave(file.path(spec_dir, "event_study_plot.png"),
         plot = p_es, width = 7, height = 4.5, dpi = 200, bg = "white")

  # ---- 7. Summary CSV -------------------------------------------------------
  summary_row <- tibble(
    spec = label,
    n_states = n_states,
    n_treated = n_treated,
    n_months = n_months,
    n_obs = nrow(panel),
    overall_att = att_overall,
    overall_se  = se_overall,
    overall_p   = p_overall,
    wald_stat = wald_stat,
    wald_df = wald_df,
    wald_p = wald_p,
    pretrends_slope_50 = pretrends_results$slope_50 %||% NA_real_,
    pretrends_slope_80 = pretrends_results$slope_80 %||% NA_real_
  )
  write_csv(summary_row, file.path(spec_dir, "summary.csv"))
  cat("\nWrote:", spec_dir, "\n\n")
  summary_row
}

# ----------------------------- run both specs ---------------------------------

panel_A <- build_panel("baseline_2016_2024",
                       min_date = "2016-01-01", max_date = "2024-12-31",
                       drop_bad = FALSE)
panel_B <- build_panel("cleaned_2018_2024_dropUTQ4",
                       min_date = "2018-01-01", max_date = "2024-12-31",
                       drop_bad = TRUE)

results <- bind_rows(
  run_spec(panel_A, "baseline_2016_2024"),
  run_spec(panel_B, "cleaned_2018_2024")
)
write_csv(results, file.path(OUT_DIR, "all_specs_summary.csv"))

cat("=== ALL SPECS SUMMARY ===\n")
print(results, width = Inf)
