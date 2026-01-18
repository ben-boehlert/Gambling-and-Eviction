#!/usr/bin/env Rscript
################################################################################
# diagnose_actual_dgp_standalone.R
#
# Replicate the ACTUAL DGP from the power simulation to see where SE inflation comes from
# This is a MINIMAL version that extracts just the DGP logic
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
  library(fixest)
  library(did)
})

cat("="*60, "\n")
cat("TESTING ACTUAL DGP\n")
cat("="*60, "\n\n")

# Load the prepared panel data (assuming it exists from previous run)
if (file.exists("/tmp/cs_test_out/panel_for_diagnosis.rds")) {
  cat("Loading pre-saved panel...\n")
  panel_data <- readRDS("/tmp/cs_test_out/panel_for_diagnosis.rds")
} else {
  cat("Panel not found. Run the main simulation first to generate it.\n")
  cat("Creating minimal version from scratch...\n")

  # This would require rebuilding everything - skipping for now
  stop("Need panel data. Run main simulation first.")
}

# Extract what we need
panel <- panel_data$panel
resid_pool_by_t <- panel_data$resid_pool_by_t
global_pool <- panel_data$global_pool
MIN_STATES_PER_MONTH <- panel_data$MIN_STATES_PER_MONTH
n_states <- panel_data$n_states

cat(glue("n_states: {n_states}\n"))
cat(glue("Panel dims: {nrow(panel)} x {ncol(panel)}\n"))
cat(glue("Residual pool size: {length(global_pool)}\n\n"))

# Error generation function
draw_errors_iid_month <- function(t_vec, pool_by_t, fallback_pool, min_states) {
  e <- numeric(length(t_vec))
  for (t_val in unique(t_vec)) {
    idx <- which(t_vec == t_val)
    pool <- pool_by_t[[as.character(t_val)]]
    if (is.null(pool) || length(pool) < min_states) pool <- fallback_pool
    e[idx] <- sample(pool, size = length(idx), replace = TRUE)
  }
  e
}

# Run multiple sims
n_sims <- 50
results <- list()

set.seed(99999)
for (i in 1:n_sims) {
  if (i %% 10 == 0) cat(".")

  e_draw <- draw_errors_iid_month(panel$t, resid_pool_by_t, global_pool, MIN_STATES_PER_MONTH)

  y_sim <- panel$yhat + e_draw  # effect=0

  dat <- data.frame(
    id = panel$id,
    t = panel$t,
    g = panel$g,
    y = y_sim
  )

  res <- tryCatch({
    est <- did::att_gt(
      yname = "y",
      tname = "t",
      idname = "id",
      gname = "g",
      xformla = ~ 1,
      data = dat,
      panel = TRUE,
      control_group = "notyettreated",
      allow_unbalanced_panel = TRUE,
      est_method = "reg",
      bstrap = TRUE,
      biters = 199,
      cband = FALSE,
      clustervars = "id"
    )

    agg <- did::aggte(est, type = "simple", na.rm = TRUE)

    list(
      ok = TRUE,
      att = as.numeric(agg$overall.att),
      se = as.numeric(agg$overall.se),
      n_attgt_na = sum(is.na(est$att))
    )
  }, error = function(e) {
    list(ok = FALSE, att = NA_real_, se = NA_real_, n_attgt_na = NA_integer_)
  })

  results[[i]] <- res
}

cat("\n\n")

# Analyze
ok_vec <- sapply(results, function(r) r$ok)
att_vec <- sapply(results, function(r) r$att)
se_vec <- sapply(results, function(r) r$se)

att_ok <- att_vec[ok_vec]
se_ok <- se_vec[ok_vec]

cat(glue("Success: {sum(ok_vec)}/{n_sims}\n\n"))

cat("ATT diagnostics:\n")
cat(glue("  Mean: {round(mean(att_ok), 4)}\n"))
cat(glue("  SD: {round(sd(att_ok), 4)}\n\n"))

cat("SE diagnostics:\n")
cat(glue("  Mean: {round(mean(se_ok), 4)}\n\n"))

cat("SE INFLATION:\n")
se_infl <- mean(se_ok) / sd(att_ok)
cat(glue("  {round(se_infl, 4)}\n"))
if (se_infl > 1.3) {
  cat("  *** INFLATED! ***\n")
} else {
  cat("  (Looks OK)\n")
}

p_vals <- 2 * pnorm(-abs(att_ok / se_ok))
cat(glue("\nRejection rate: {round(mean(p_vals < 0.05), 4)}\n"))
