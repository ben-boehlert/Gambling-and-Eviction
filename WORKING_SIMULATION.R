################################################################################
# WORKING POWER SIMULATION
# Fixed coefficient extraction bug
################################################################################

library(fixest)
library(lubridate)

set.seed(20251224)

cat("================================================================================\n")
cat("POWER SIMULATION - WORKING VERSION\n")
cat("================================================================================\n\n")

# Load data
load("power_analysis_FINAL.RData")

cat(sprintf("Panel: %d observations, %d states, %d treated\n\n",
            nrow(analysis_panel),
            length(unique(analysis_panel$state)),
            sum(unique(analysis_panel$state) %in%
                unique(analysis_panel$state[analysis_panel$treated_state]))))

################################################################################
# POWER SIMULATION
################################################################################

n_sims <- 250
effect_sizes <- c(0, 0.5, 1, 1.5, 2, 2.5, 3, 4, 5)
alpha <- 0.05

all_states <- unique(analysis_panel$state)
n_states <- length(all_states)
n_treated_sim <- round(n_states / 2)
treatment_start <- median(analysis_panel$month)

cat(sprintf("Simulations: %d per effect size\n", n_sims))
cat(sprintf("States: %d total, treating %d\n", n_states, n_treated_sim))
cat(sprintf("Treatment starts: %s\n", treatment_start))
cat(sprintf("Effect sizes: %s\n\n", paste(effect_sizes, collapse = ", ")))

results <- data.frame()

for (effect in effect_sizes) {
  cat(sprintf("Effect = %.2f ... ", effect))

  n_sig <- 0
  coefs <- numeric(n_sims)
  ses <- numeric(n_sims)
  pvals <- numeric(n_sims)

  for (sim in 1:n_sims) {
    # Random treatment
    treated_sim <- sample(all_states, n_treated_sim, replace = FALSE)

    sim_data <- analysis_panel
    sim_data$D <- as.integer(
      (sim_data$state %in% treated_sim) &
      (sim_data$month >= treatment_start)
    )

    # Add effect
    sim_data$outcome_sim <- sim_data$outcome - effect * sim_data$D

    # Estimate
    model <- tryCatch({
      feols(outcome_sim ~ D | state + month,
            data = sim_data, cluster = ~state)
    }, error = function(e) NULL)

    if (!is.null(model)) {
      # FIXED: Proper extraction from fixest object
      coef_D <- coef(model)["D"]
      se_D   <- fixest::se(model)["D"]
      pval_D <- fixest::pvalue(model)["D"]

      coefs[sim] <- coef_D
      ses[sim] <- se_D
      pvals[sim] <- pval_D

      if (pval_D <= alpha) n_sig <- n_sig + 1
    }
  }

  power <- n_sig / n_sims

  results <- rbind(results, data.frame(
    effect_size = effect,
    power = power,
    mean_coef = mean(coefs, na.rm = TRUE),
    median_coef = median(coefs, na.rm = TRUE),
    mean_se = mean(ses, na.rm = TRUE),
    n_sims = n_sims,
    stringsAsFactors = FALSE
  ))

  cat(sprintf("Power = %.1f%%\n", power * 100))
}

################################################################################
# CALCULATE MDE
################################################################################

cat("\n================================================================================\n")
cat("CALCULATING MDE\n")
cat("================================================================================\n\n")

results_nonzero <- results[results$effect_size > 0, ]

if (nrow(results_nonzero) >= 2) {
  power_target <- 0.80
  results_nonzero$gap <- abs(results_nonzero$power - power_target)
  results_nonzero <- results_nonzero[order(results_nonzero$gap), ]

  closest <- results_nonzero[1:min(2, nrow(results_nonzero)), ]
  fit <- lm(power ~ effect_size, data = closest)
  mde <- (power_target - coef(fit)[1]) / coef(fit)[2]

  cat(sprintf("MDE at 80%% power, 5%% alpha: %.3f filings per 1,000 renters\n\n", mde))

  results$mde_80 <- NA
  results$mde_80[1] <- mde
}

cat("\n=== POWER ANALYSIS RESULTS ===\n")
cat("--------------------------------------------------------------------------------\n")
print(results, row.names = FALSE)
cat("--------------------------------------------------------------------------------\n\n")

################################################################################
# SAVE
################################################################################

cat("Saving results...\n")

write.csv(results, "power_results_WORKING.csv", row.names = FALSE)

save(analysis_panel, baseline_model, results, sigma2,
     file = "power_analysis_WORKING.RData")

cat("\n================================================================================\n")
cat("SUCCESS!\n")
cat("================================================================================\n\n")

cat("Output files:\n")
cat("  • power_results_WORKING.csv ← YOUR RESULTS\n")
cat("  • power_analysis_WORKING.RData\n\n")

if (exists("mde")) {
  cat("================================================================================\n")
  cat(sprintf("  MDE (80%% power, 5%% alpha) = %.3f filings per 1,000 renters\n", mde))
  cat("================================================================================\n\n")

  cat("Interpretation:\n")
  cat(sprintf("With %d states and this panel design, you can detect effects of\n", n_states))
  cat(sprintf("%.2f or larger filings per 1,000 renters with 80%% power.\n\n", mde))
}

cat("Power curve summary:\n")
for (i in 1:nrow(results)) {
  cat(sprintf("  Effect = %.1f: Power = %.1f%%\n",
              results$effect_size[i], results$power[i] * 100))
}

cat("\n✓ Analysis complete!\n\n")
