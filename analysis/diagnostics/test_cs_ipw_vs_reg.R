#!/usr/bin/env Rscript
################################################################################
# test_cs_ipw_vs_reg.R
#
# Test if est_method="ipw" vs "reg" is the cause of the 0% rejection rate
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
  library(fixest)
  library(did)
})

args <- commandArgs(trailingOnly = TRUE)
EST_METHOD <- if (length(args) > 0) args[1] else "reg"
N_SIMS <- if (length(args) > 1) as.integer(args[2]) else 500

cat("================================================================================\n")
cat("CS DiD NULL SIZE TEST - est_method =", EST_METHOD, "\n")
cat("N_SIMS:", N_SIMS, "\n")
cat("================================================================================\n\n")

# Create synthetic panel
set.seed(12345)
n_states <- 38
n_months <- 120

treatment_timing <- c(
  rep(0, 10),   # Never treated
  rep(60, 14),  # Early treated
  rep(80, 14)   # Late treated
)
treatment_timing <- sample(treatment_timing)

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

cat("Panel: n_states=", n_states, ", n_obs=", nrow(panel), "\n\n")

# Fit FE on untreated only
base_fe <- panel %>% filter(untreated_obs, is.finite(y))
fe_fit <- fixest::feols(y ~ 1 | id + t, data = base_fe, notes = FALSE, warn = FALSE)
panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))
base_fe$ehat <- as.numeric(residuals(fe_fit))
resid_pool <- base_fe$ehat

cat("Residual pool size:", length(resid_pool), "\n\n")

# One simulation
one_sim <- function(seed) {
  set.seed(seed)
  e_draw <- sample(resid_pool, size = nrow(panel), replace = TRUE)
  y_sim <- panel$yhat + e_draw  # NULL

  dat <- data.frame(
    id = panel$id,
    t  = panel$t,
    g  = panel$g,
    y  = y_sim
  )

  out <- tryCatch({
    suppressWarnings({
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
        est_method = EST_METHOD,
        faster_mode = FALSE,
        bstrap = TRUE,
        biters = 199,
        cband = FALSE,
        clustervars = "id"
      )

      agg <- did::aggte(est, type = "simple", na.rm = TRUE)
      att <- as.numeric(agg$overall.att)
      se  <- as.numeric(agg$overall.se)
      z <- att / se
      p <- if (is.finite(z)) 2 * pt(-abs(z), df = n_states - 1) else NA_real_

      list(ok = TRUE, att = att, se = se, z = z, p = p)
    })
  }, error = function(e) {
    list(ok = FALSE, att = NA_real_, se = NA_real_, z = NA_real_, p = NA_real_,
         error = conditionMessage(e))
  })

  out
}

# Run simulations
cat("Running", N_SIMS, "null simulations with est_method =", EST_METHOD, "...\n")
set.seed(20240101)
seeds <- sample.int(1e6, N_SIMS)

results <- list()
pb <- txtProgressBar(min = 0, max = N_SIMS, style = 3)
for (i in seq_len(N_SIMS)) {
  results[[i]] <- one_sim(seeds[i])
  setTxtProgressBar(pb, i)
}
close(pb)

df <- bind_rows(results)

cat("\n\nSuccess rate:", sum(df$ok), "/", nrow(df), "\n")

if (sum(df$ok) == 0) {
  cat("ERROR: All simulations failed!\n")
  cat("Sample error:", df$error[1], "\n")
  quit(status = 1)
}

df_ok <- df %>% filter(ok == TRUE, is.finite(att), is.finite(se), se > 0)

cat("\n================================================================================\n")
cat("RESULTS: est_method =", EST_METHOD, "\n")
cat("================================================================================\n\n")

reject_rate <- mean(df_ok$p < 0.05, na.rm = TRUE)
mean_se <- mean(df_ok$se, na.rm = TRUE)
sd_att <- sd(df_ok$att, na.rm = TRUE)
ratio <- mean_se / sd_att
sd_z <- sd(df_ok$z, na.rm = TRUE)

cat("reject_rate:", sprintf("%.4f", reject_rate), sprintf("(%.1f%%)", 100*reject_rate), "\n")
cat("mean(SE) / sd(ATT):", sprintf("%.3f", ratio), "\n")
cat("sd(Z):", sprintf("%.4f", sd_z), "\n\n")

p_quants <- quantile(df_ok$p, c(0.01, 0.05, 0.10, 0.50, 0.90), na.rm = TRUE)
cat("P-value quantiles:\n")
cat("  p01:", sprintf("%.3f", p_quants[1]), "\n")
cat("  p05:", sprintf("%.3f", p_quants[2]), "\n")
cat("  p10:", sprintf("%.3f", p_quants[3]), "\n")
cat("  p50:", sprintf("%.3f", p_quants[4]), "\n")
cat("  p90:", sprintf("%.3f", p_quants[5]), "\n\n")

# Save result
result_df <- data.frame(
  est_method = EST_METHOD,
  n_sims = N_SIMS,
  success_rate = nrow(df_ok) / nrow(df),
  reject_rate = reject_rate,
  ratio = ratio,
  sd_z = sd_z,
  p01 = p_quants[1],
  p05 = p_quants[2],
  p10 = p_quants[3],
  p50 = p_quants[4],
  p90 = p_quants[5]
)

out_file <- glue("cs_power_out/ipw_vs_reg_results.csv")
if (!file.exists(out_file)) {
  write_csv(result_df, out_file)
} else {
  write_csv(result_df, out_file, append = TRUE)
}

cat("Saved to:", out_file, "\n")
