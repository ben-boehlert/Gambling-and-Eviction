#!/usr/bin/env Rscript
# Quick test of single CS DiD simulation

suppressPackageStartupMessages({
  library(dplyr)
  library(fixest)
  library(did)
})

set.seed(12345)
n_states <- 38
n_months <- 120

# Create balanced treatment groups
# Group 0 = never treated (10 states)
# Group 60 = treated at t=60 (14 states)
# Group 80 = treated at t=80 (14 states)
treatment_timing <- c(
  rep(0, 10),   # Never treated
  rep(60, 14),  # Early treated
  rep(80, 14)   # Late treated
)
treatment_timing <- sample(treatment_timing)  # Randomize assignment

panel <- expand.grid(
  id = 1:n_states,
  t = 1:n_months
)

panel$g <- treatment_timing[panel$id]
panel$post_treat <- (panel$g > 0) & (panel$t >= panel$g)
panel$untreated_obs <- !panel$post_treat

set.seed(12345)
alpha_i <- rnorm(n_states, mean = 5, sd = 0.5)
lambda_t <- rnorm(n_months, mean = 0, sd = 0.3)

panel$y <- alpha_i[panel$id] + lambda_t[panel$t] + rnorm(nrow(panel), sd = 0.4)

cat("Panel setup complete\n")
cat("  n_states:", n_states, "\n")
cat("  n_obs:", nrow(panel), "\n")
cat("  Untreated obs:", sum(panel$untreated_obs), "\n\n")

# Fit FE on untreated only
base_fe <- panel %>% filter(untreated_obs, is.finite(y))
cat("Fitting FE on", nrow(base_fe), "untreated observations...\n")
fe_fit <- fixest::feols(y ~ 1 | id + t, data = base_fe, notes = FALSE, warn = FALSE)

panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))
cat("FE predictions generated\n\n")

# Create residual pool
base_fe$ehat <- as.numeric(residuals(fe_fit))
resid_pool <- base_fe$ehat

cat("Residual pool size:", length(resid_pool), "\n\n")

# One null simulation
set.seed(999)
e_draw <- sample(resid_pool, size = nrow(panel), replace = TRUE)
y_sim <- panel$yhat + e_draw  # NULL: no treatment effect

dat <- data.frame(
  id = panel$id,
  t  = panel$t,
  g  = panel$g,
  y  = y_sim
)

cat("Calling did::att_gt...\n")
est <- did::att_gt(
  yname = "y",
  tname = "t",
  idname = "id",
  gname = "g",
  xformla = ~ 1,
  data = dat,
  panel = TRUE,
  control_group = "nevertreated",
  allow_unbalanced_panel = TRUE,
  est_method = "reg",  # Use regression instead of IPW to avoid fastglm issue
  faster_mode = FALSE,
  bstrap = TRUE,
  biters = 199,
  cband = FALSE,
  clustervars = "id"
)

cat("att_gt succeeded!\n\n")

# Aggregate
agg <- did::aggte(est, type = "simple", na.rm = TRUE)

cat("Results:\n")
cat("  ATT:", agg$overall.att, "\n")
cat("  SE:", agg$overall.se, "\n")
cat("  Z:", agg$overall.att / agg$overall.se, "\n\n")

cat("SUCCESS!\n")
