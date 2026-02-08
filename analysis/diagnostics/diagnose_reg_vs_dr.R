#!/usr/bin/env Rscript
################################################################################
# diagnose_reg_vs_dr.R
#
# Test if est_method="reg" vs "dr" vs "ipw" makes a difference
# Using the TOY DGP (which we know works)
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
  library(did)
  library(tibble)
})

OUT_DIR <- "diagnostic_reg_vs_dr"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# Generate toy DGP (same as diagnose_se_toy.R)
set.seed(999)
n_states <- 50
n_months <- 120

panel_toy <- expand.grid(
  id = 1:n_states,
  t = 1:n_months
)

g_assignment <- c(rep(0, 10), rep(40, 10), rep(60, 10), rep(80, 10), rep(100, 10))
panel_toy$g <- g_assignment[panel_toy$id]

state_fe <- rnorm(n_states, mean = 5, sd = 1)
time_fe <- rnorm(n_months, mean = 0, sd = 0.5)

panel_toy$state_fe <- state_fe[panel_toy$id]
panel_toy$time_fe <- time_fe[panel_toy$t]
panel_toy$e_iid <- rnorm(nrow(panel_toy), mean = 0, sd = 1)
panel_toy$y <- panel_toy$state_fe + panel_toy$time_fe + panel_toy$e_iid

################################################################################
# Test function
################################################################################

run_test <- function(test_name, est_method, n_sims = 100) {
  cat(rep("=", 60), "\n", sep="")
  cat(glue("{test_name}\n"))
  cat(rep("=", 60), "\n", sep="")

  set.seed(12345)
  seeds <- sample.int(1e8, n_sims)

  results <- lapply(seeds, function(seed) {
    set.seed(seed)
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
        est_method = est_method,
        bstrap = TRUE,
        biters = 199,
        cband = FALSE,
        clustervars = "id"
      )

      agg <- did::aggte(est, type = "simple", na.rm = TRUE)

      att <- as.numeric(agg$overall.att)
      se <- as.numeric(agg$overall.se)
      z <- att / se
      p <- 2 * pnorm(-abs(z))

      list(ok = TRUE, att = att, se = se, z = z, p = p)
    }, error = function(e) {
      list(ok = FALSE, att = NA_real_, se = NA_real_, z = NA_real_, p = NA_real_, error = conditionMessage(e))
    })
  })

  ok_vec <- sapply(results, function(r) r$ok)
  att_ok <- sapply(results, function(r) r$att)[ok_vec]
  se_ok <- sapply(results, function(r) r$se)[ok_vec]
  p_ok <- sapply(results, function(r) r$p)[ok_vec]

  cat(glue("Success rate: {sum(ok_vec)}/{n_sims}\n"))
  cat(glue("SE inflation: {round(mean(se_ok) / sd(att_ok), 4)}\n"))
  cat(glue("Rejection rate: {round(mean(p_ok < 0.05), 4)}\n"))
  p_quants <- quantile(p_ok, c(0.05, 0.50, 0.95))
  cat(glue("P-value quantiles: 5%={round(p_quants[1], 4)}, 50%={round(p_quants[2], 4)}, 95%={round(p_quants[3], 4)}\n\n"))

  tibble(
    test_name = test_name,
    est_method = est_method,
    n_success = sum(ok_vec),
    se_inflation = mean(se_ok) / sd(att_ok),
    rejection_rate = mean(p_ok < 0.05),
    p05 = p_quants[1],
    p50 = p_quants[2],
    p95 = p_quants[3]
  )
}

################################################################################
# Run tests
################################################################################

results_list <- list()

results_list[[1]] <- run_test("REG estimator", "reg", n_sims = 100)
results_list[[2]] <- run_test("DR estimator", "dr", n_sims = 100)
results_list[[3]] <- run_test("IPW estimator", "ipw", n_sims = 100)

results_df <- bind_rows(results_list)
write_csv(results_df, file.path(OUT_DIR, "reg_vs_dr_comparison.csv"))

cat(rep("=", 60), "\n", sep="")
cat("COMPARISON\n")
cat(rep("=", 60), "\n", sep="")
print(results_df)

cat(glue("\nResults saved to: {OUT_DIR}/reg_vs_dr_comparison.csv\n"))
