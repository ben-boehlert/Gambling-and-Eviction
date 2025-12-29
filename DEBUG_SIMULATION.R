################################################################################
# DEBUG THE SIMULATION
# Test one iteration to see what's happening
################################################################################

library(fixest)
library(lubridate)

cat("Loading data...\n")
load("power_analysis_FINAL.RData")

cat(sprintf("Panel has %d observations, %d states\n",
            nrow(analysis_panel), length(unique(analysis_panel$state))))
cat(sprintf("Treated states: %d\n",
            sum(unique(analysis_panel$state) %in%
                unique(analysis_panel$state[analysis_panel$treated_state]))))
cat(sprintf("Post-treatment obs: %d\n\n", sum(analysis_panel$post_treatment)))

# Set up one simulation manually
set.seed(123)

all_states <- unique(analysis_panel$state)
n_states <- length(all_states)
n_treated <- round(n_states / 2)
treatment_start <- median(analysis_panel$month)

cat(sprintf("Simulating with %d treated of %d states\n", n_treated, n_states))
cat(sprintf("Treatment starts: %s\n\n", treatment_start))

# Random treatment
treated_sim <- sample(all_states, n_treated, replace = FALSE)
cat("Randomly treated states:", paste(treated_sim, collapse=", "), "\n\n")

# Create treatment indicator
sim_data <- analysis_panel
sim_data$D <- as.integer(
  (sim_data$state %in% treated_sim) &
  (sim_data$month >= treatment_start)
)

cat(sprintf("Treatment indicator D created: %d treated observations\n", sum(sim_data$D)))

# Test with effect = 2
effect <- 2
sim_data$outcome_sim <- sim_data$outcome - effect * sim_data$D

cat(sprintf("Added effect of %.1f to treated observations\n\n", effect))

# Check means
cat("Checking means:\n")
cat(sprintf("  Mean outcome (control, D=0): %.3f\n",
            mean(sim_data$outcome_sim[sim_data$D == 0], na.rm=TRUE)))
cat(sprintf("  Mean outcome (treated, D=1): %.3f\n",
            mean(sim_data$outcome_sim[sim_data$D == 1], na.rm=TRUE)))
cat(sprintf("  Difference: %.3f (should be around %.1f)\n\n",
            mean(sim_data$outcome_sim[sim_data$D == 0], na.rm=TRUE) -
            mean(sim_data$outcome_sim[sim_data$D == 1], na.rm=TRUE),
            effect))

# Try the regression
cat("Running regression: outcome_sim ~ D | state + month\n\n")

tryCatch({
  model <- feols(outcome_sim ~ D | state + month,
                data = sim_data, cluster = ~state)

  cat("Model estimation SUCCEEDED!\n\n")
  print(summary(model))

  coef_est <- coef(model)["D"]
  se_est <- se(model)["D"]
  pval <- pvalue(model)["D"]

  cat("\n=== RESULTS ===\n")
  cat(sprintf("Coefficient: %.4f\n", coef_est))
  cat(sprintf("Std Error: %.4f\n", se_est))
  cat(sprintf("P-value: %.4f\n", pval))
  cat(sprintf("Significant at 5%%? %s\n", ifelse(pval < 0.05, "YES", "NO")))

}, error = function(e) {
  cat("MODEL FAILED!\n")
  cat("Error:", e$message, "\n\n")

  cat("Debugging info:\n")
  cat(sprintf("  Non-missing outcome_sim: %d\n", sum(!is.na(sim_data$outcome_sim))))
  cat(sprintf("  Non-missing D: %d\n", sum(!is.na(sim_data$D))))
  cat(sprintf("  Variation in D: %d unique values\n", length(unique(sim_data$D))))
  cat(sprintf("  Variation in state: %d unique values\n", length(unique(sim_data$state))))
  cat(sprintf("  Variation in month: %d unique values\n", length(unique(sim_data$month))))
})

cat("\n=== TEST COMPLETE ===\n")
cat("If the model succeeded and shows a significant negative coefficient,\n")
cat("the simulation SHOULD work. If it failed, there's a data issue.\n")
