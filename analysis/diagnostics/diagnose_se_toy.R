#!/usr/bin/env Rscript
################################################################################
# diagnose_se_toy.R
#
# Toy Monte Carlo sanity check:
# Clean DGP where inference should work perfectly
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
  library(did)
  library(tibble)
})

OUT_DIR <- "diagnostic_toy_mc"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

cat("TOY MONTE CARLO SANITY CHECK\n")
cat("============================\n\n")

################################################################################
# Generate toy DGP
################################################################################

set.seed(999)

n_states <- 50
n_months <- 120
n_obs <- n_states * n_months

# Create balanced panel
panel_toy <- expand.grid(
  id = 1:n_states,
  t = 1:n_months
)

# Staggered treatment:
# - 10 states never treated (g=0)
# - 40 states treated at various times
g_assignment <- c(
  rep(0, 10),  # never treated
  rep(40, 10), # treated at t=40
  rep(60, 10), # treated at t=60
  rep(80, 10), # treated at t=80
  rep(100, 10) # treated at t=100
)

panel_toy$g <- g_assignment[panel_toy$id]

# State fixed effects
state_fe <- rnorm(n_states, mean = 5, sd = 1)
panel_toy$state_fe <- state_fe[panel_toy$id]

# Time fixed effects
time_fe <- rnorm(n_months, mean = 0, sd = 0.5)
panel_toy$time_fe <- time_fe[panel_toy$t]

# IID errors
panel_toy$e_iid <- rnorm(n_obs, mean = 0, sd = 1)

# Outcome under NULL (effect = 0)
panel_toy$y <- panel_toy$state_fe + panel_toy$time_fe + panel_toy$e_iid

cat(glue("Toy panel: {n_states} states × {n_months} months = {n_obs} obs\n"))
cat(glue("Treatment groups: {length(unique(panel_toy$g))} (including g=0)\n"))
cat(glue("True effect: 0 (null)\n\n"))

################################################################################
# Run simulation
################################################################################

run_toy_sim <- function(seed, bstrap = TRUE, biters = 199) {
  set.seed(seed)

  # Resample errors to create new dataset
  dat <- panel_toy
  dat$e <- sample(dat$e_iid, size = nrow(dat), replace = TRUE)
  dat$y <- dat$state_fe + dat$time_fe + dat$e

  tryCatch({
    est <- did::att_gt(
      yname = "y",
      tname = "t",
      idname = "id",
      gname = "g",
      xformla = ~ 1,
      data = dat,
      panel = TRUE,
      control_group = "notyettreated",
      allow_unbalanced_panel = FALSE,
      est_method = "reg",
      bstrap = bstrap,
      biters = biters,
      cband = FALSE,
      clustervars = "id"
    )

    agg <- did::aggte(est, type = "simple", na.rm = TRUE)

    att <- as.numeric(agg$overall.att)
    se <- as.numeric(agg$overall.se)
    z <- att / se
    p <- 2 * pnorm(-abs(z))

    n_attgt_na <- sum(is.na(est$att))

    list(
      ok = TRUE,
      att = att,
      se = se,
      z = z,
      p = p,
      n_attgt_na = n_attgt_na
    )
  }, error = function(e) {
    list(
      ok = FALSE,
      att = NA_real_,
      se = NA_real_,
      z = NA_real_,
      p = NA_real_,
      n_attgt_na = NA_integer_,
      error = conditionMessage(e)
    )
  })
}

################################################################################
# Run many simulations
################################################################################

n_sims <- 200
cat(glue("Running {n_sims} simulations...\n\n"))

set.seed(12345)
seeds <- sample.int(1e8, n_sims)

results <- lapply(seeds, function(s) {
  if (s %% 20 == 0) cat(".")
  run_toy_sim(s, bstrap = TRUE, biters = 199)
})
cat("\n\n")

# Extract results
ok_vec <- sapply(results, function(r) r$ok)
att_vec <- sapply(results, function(r) r$att)
se_vec <- sapply(results, function(r) r$se)
z_vec <- sapply(results, function(r) r$z)
p_vec <- sapply(results, function(r) r$p)

att_ok <- att_vec[ok_vec]
se_ok <- se_vec[ok_vec]
z_ok <- z_vec[ok_vec]
p_ok <- p_vec[ok_vec]

cat("TOY MONTE CARLO RESULTS\n")
cat("=======================\n\n")

cat(glue("Successful sims: {sum(ok_vec)} / {n_sims}\n\n"))

cat("ATT diagnostics:\n")
cat(glue("  Mean: {round(mean(att_ok), 4)}\n"))
cat(glue("  SD: {round(sd(att_ok), 4)}\n\n"))

cat("SE diagnostics:\n")
cat(glue("  Mean: {round(mean(se_ok), 4)}\n"))
cat(glue("  Median: {round(median(se_ok), 4)}\n\n"))

cat("SE inflation ratio:\n")
cat(glue("  mean(SE) / sd(ATT) = {round(mean(se_ok) / sd(att_ok), 4)}\n"))
cat("  (Should be ~1.0)\n\n")

cat("P-value diagnostics:\n")
p_quants <- quantile(p_ok, c(0.05, 0.50, 0.95))
cat(glue("  5th percentile: {round(p_quants[1], 4)} (expect ~0.05)\n"))
cat(glue("  50th percentile: {round(p_quants[2], 4)} (expect ~0.50)\n"))
cat(glue("  95th percentile: {round(p_quants[3], 4)} (expect ~0.95)\n"))
cat(glue("  Rejection rate: {round(mean(p_ok < 0.05), 4)} (expect ~0.05)\n\n"))

# Save detailed results
results_df <- tibble(
  sim = 1:n_sims,
  ok = ok_vec,
  att = att_vec,
  se = se_vec,
  z = z_vec,
  p = p_vec
)

write_csv(results_df, file.path(OUT_DIR, "toy_mc_results.csv"))

cat(glue("\nResults saved to: {OUT_DIR}/toy_mc_results.csv\n"))
