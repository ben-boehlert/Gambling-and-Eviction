#!/usr/bin/env Rscript
################################################################################
# compare_twfe_vs_cs_same_data.R
#
# Run TWFE and CS-DiD on the EXACT SAME simulated datasets
# to see if CS-DiD systematically produces larger SEs
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
  library(fixest)
  library(did)
})

cat("DIRECT COMPARISON: TWFE vs CS-DiD on Same Data\n")
cat("==============================================\n\n")

# Load panel data (simplified - using toy data for clean test)
set.seed(999)
n_states <- 50
n_months <- 120

panel <- expand.grid(
  id = 1:n_states,
  t = 1:n_months
)

# Staggered treatment
g_assignment <- c(rep(0, 10), rep(40, 10), rep(60, 10), rep(80, 10), rep(100, 10))
panel$g <- g_assignment[panel$id]

# Create post_treat indicator
panel$post_treat <- (panel$g > 0) & (panel$t >= panel$g)

# Fixed effects
state_fe <- rnorm(n_states, mean = 5, sd = 1)
time_fe <- rnorm(n_months, mean = 0, sd = 0.5)
panel$state_fe <- state_fe[panel$id]
panel$time_fe <- time_fe[panel$t]

cat(glue("Panel: {n_states} states × {n_months} months\n"))
cat(glue("Treatment timing: {length(unique(panel$g))} groups\n\n"))

################################################################################
# Run simulations with BOTH methods on SAME data
################################################################################

run_both_methods <- function(seed) {
  set.seed(seed)

  # Generate ONE dataset
  e <- rnorm(nrow(panel), mean = 0, sd = 1)
  y <- panel$state_fe + panel$time_fe + e  # effect=0

  # Method 1: TWFE
  dat_twfe <- data.frame(
    id = panel$id,
    t = panel$t,
    post_treat = as.integer(panel$post_treat),
    y = y
  )

  twfe_result <- tryCatch({
    est_twfe <- fixest::feols(
      y ~ post_treat | id + t,
      data = dat_twfe,
      cluster = ~id,
      warn = FALSE,
      notes = FALSE
    )

    ct <- fixest::coeftable(est_twfe)
    list(
      ok = TRUE,
      att = unname(ct["post_treat", "Estimate"]),
      se = unname(ct["post_treat", "Std. Error"]),
      p = unname(ct["post_treat", "Pr(>|t|)"])
    )
  }, error = function(e) {
    list(ok = FALSE, att = NA_real_, se = NA_real_, p = NA_real_)
  })

  # Method 2: CS-DiD
  dat_cs <- data.frame(
    id = panel$id,
    t = panel$t,
    g = panel$g,
    y = y
  )

  cs_result <- tryCatch({
    est_cs <- did::att_gt(
      yname = "y",
      tname = "t",
      idname = "id",
      gname = "g",
      xformla = ~ 1,
      data = dat_cs,
      panel = TRUE,
      control_group = "notyettreated",
      allow_unbalanced_panel = FALSE,
      est_method = "reg",
      bstrap = TRUE,
      biters = 199,
      cband = FALSE,
      clustervars = "id"
    )

    agg_cs <- did::aggte(est_cs, type = "simple", na.rm = TRUE)

    att_cs <- as.numeric(agg_cs$overall.att)
    se_cs <- as.numeric(agg_cs$overall.se)
    p_cs <- 2 * pnorm(-abs(att_cs / se_cs))

    list(
      ok = TRUE,
      att = att_cs,
      se = se_cs,
      p = p_cs
    )
  }, error = function(e) {
    list(ok = FALSE, att = NA_real_, se = NA_real_, p = NA_real_)
  })

  # Also try CS with bstrap=FALSE
  cs_analytic_result <- tryCatch({
    est_cs_analytic <- did::att_gt(
      yname = "y",
      tname = "t",
      idname = "id",
      gname = "g",
      xformla = ~ 1,
      data = dat_cs,
      panel = TRUE,
      control_group = "notyettreated",
      allow_unbalanced_panel = FALSE,
      est_method = "reg",
      bstrap = FALSE,  # ANALYTICAL SE
      cband = FALSE,
      clustervars = "id"
    )

    agg_cs_analytic <- did::aggte(est_cs_analytic, type = "simple", na.rm = TRUE)

    att_cs_analytic <- as.numeric(agg_cs_analytic$overall.att)
    se_cs_analytic <- as.numeric(agg_cs_analytic$overall.se)
    p_cs_analytic <- 2 * pnorm(-abs(att_cs_analytic / se_cs_analytic))

    list(
      ok = TRUE,
      att = att_cs_analytic,
      se = se_cs_analytic,
      p = p_cs_analytic
    )
  }, error = function(e) {
    list(ok = FALSE, att = NA_real_, se = NA_real_, p = NA_real_)
  })

  list(
    twfe = twfe_result,
    cs = cs_result,
    cs_analytic = cs_analytic_result
  )
}

################################################################################
# Run many simulations
################################################################################

n_sims <- 100
cat(glue("Running {n_sims} simulations...\n\n"))

set.seed(12345)
seeds <- sample.int(1e8, n_sims)

results <- lapply(seeds, function(s) {
  if (s %% 10 == 0) cat(".")
  run_both_methods(s)
})
cat("\n\n")

# Extract results
twfe_ok <- sapply(results, function(r) r$twfe$ok)
cs_ok <- sapply(results, function(r) r$cs$ok)
cs_analytic_ok <- sapply(results, function(r) r$cs_analytic$ok)

twfe_att <- sapply(results, function(r) r$twfe$att)[twfe_ok]
twfe_se <- sapply(results, function(r) r$twfe$se)[twfe_ok]
twfe_p <- sapply(results, function(r) r$twfe$p)[twfe_ok]

cs_att <- sapply(results, function(r) r$cs$att)[cs_ok]
cs_se <- sapply(results, function(r) r$cs$se)[cs_ok]
cs_p <- sapply(results, function(r) r$cs$p)[cs_ok]

cs_analytic_att <- sapply(results, function(r) r$cs_analytic$att)[cs_analytic_ok]
cs_analytic_se <- sapply(results, function(r) r$cs_analytic$se)[cs_analytic_ok]
cs_analytic_p <- sapply(results, function(r) r$cs_analytic$p)[cs_analytic_ok]

################################################################################
# Compare
################################################################################

cat("RESULTS\n")
cat("=======\n\n")

cat("TWFE (fixest, cluster-robust SE):\n")
cat(glue("  Success rate: {sum(twfe_ok)}/{n_sims}\n"))
cat(glue("  Mean ATT: {round(mean(twfe_att), 4)}\n"))
cat(glue("  SD(ATT): {round(sd(twfe_att), 4)}\n"))
cat(glue("  Mean SE: {round(mean(twfe_se), 4)}\n"))
cat(glue("  SE inflation: {round(mean(twfe_se) / sd(twfe_att), 4)}\n"))
cat(glue("  Rejection rate: {round(mean(twfe_p < 0.05), 4)}\n\n"))

cat("CS-DiD (bootstrap SE):\n")
cat(glue("  Success rate: {sum(cs_ok)}/{n_sims}\n"))
cat(glue("  Mean ATT: {round(mean(cs_att), 4)}\n"))
cat(glue("  SD(ATT): {round(sd(cs_att), 4)}\n"))
cat(glue("  Mean SE: {round(mean(cs_se), 4)}\n"))
cat(glue("  SE inflation: {round(mean(cs_se) / sd(cs_att), 4)}\n"))
cat(glue("  Rejection rate: {round(mean(cs_p < 0.05), 4)}\n\n"))

cat("CS-DiD (analytical SE):\n")
cat(glue("  Success rate: {sum(cs_analytic_ok)}/{n_sims}\n"))
cat(glue("  Mean ATT: {round(mean(cs_analytic_att), 4)}\n"))
cat(glue("  SD(ATT): {round(sd(cs_analytic_att), 4)}\n"))
cat(glue("  Mean SE: {round(mean(cs_analytic_se), 4)}\n"))
cat(glue("  SE inflation: {round(mean(cs_analytic_se) / sd(cs_analytic_att), 4)}\n"))
cat(glue("  Rejection rate: {round(mean(cs_analytic_p < 0.05), 4)}\n\n"))

cat("COMPARISON:\n")
cat(glue("  CS-DiD bootstrap SE / TWFE SE: {round(mean(cs_se) / mean(twfe_se), 4)}\n"))
cat(glue("  CS-DiD analytic SE / TWFE SE: {round(mean(cs_analytic_se) / mean(twfe_se), 4)}\n"))

if (mean(cs_se) / mean(twfe_se) > 1.2) {
  cat("\n*** CS-DiD SE is >20% larger than TWFE SE even on same data! ***\n")
  cat("This suggests CS-DiD aggregation inherently produces larger SEs.\n")
} else {
  cat("\nCS-DiD and TWFE produce similar SEs.\n")
}

# Save comparison
comparison_df <- tibble(
  method = c("TWFE", "CS-DiD (bootstrap)", "CS-DiD (analytical)"),
  n_success = c(sum(twfe_ok), sum(cs_ok), sum(cs_analytic_ok)),
  mean_att = c(mean(twfe_att), mean(cs_att), mean(cs_analytic_att)),
  sd_att = c(sd(twfe_att), sd(cs_att), sd(cs_analytic_att)),
  mean_se = c(mean(twfe_se), mean(cs_se), mean(cs_analytic_se)),
  se_inflation = c(
    mean(twfe_se) / sd(twfe_att),
    mean(cs_se) / sd(cs_att),
    mean(cs_analytic_se) / sd(cs_analytic_att)
  ),
  rejection_rate = c(
    mean(twfe_p < 0.05),
    mean(cs_p < 0.05),
    mean(cs_analytic_p < 0.05)
  )
)

write_csv(comparison_df, "diagnostic_twfe_vs_cs/comparison.csv")
dir.create("diagnostic_twfe_vs_cs", showWarnings = FALSE, recursive = TRUE)
cat("\nResults saved to: diagnostic_twfe_vs_cs/comparison.csv\n")
