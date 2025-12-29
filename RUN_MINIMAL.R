################################################################################
# MINIMAL WORKING VERSION
# No wild bootstrap, no tidyverse, just core power analysis
################################################################################

cat("\n")
cat("================================================================================\n")
cat("    MINIMAL POWER ANALYSIS - SPORTS GAMBLING -> EVICTION FILINGS\n")
cat("================================================================================\n\n")

# Only load packages that are definitely available
cat("Loading required packages...\n")

# Check and install only essential packages
essential_packages <- c("fixest", "lubridate")

for (pkg in essential_packages) {
  if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
    cat(sprintf("Installing %s...\n", pkg))
    install.packages(pkg, quiet = TRUE)
    library(pkg, character.only = TRUE)
  }
}

cat("✓ Essential packages loaded\n\n")

set.seed(20251224)

################################################################################
# LOAD DATA
################################################################################

cat("Loading data files...\n")

county_monthly <- read.csv("monthly_county_data_download.csv", stringsAsFactors = FALSE)
gambling_dates <- read.csv("sports_gambling_legalization_dates.csv", stringsAsFactors = FALSE)

cat(sprintf("  County data: %d rows\n", nrow(county_monthly)))
cat(sprintf("  Gambling dates: %d states\n\n", nrow(gambling_dates)))

################################################################################
# PREPARE DATA
################################################################################

cat("Preparing analysis panel...\n")

# Parse dates
county_monthly$date <- ymd_hms(county_monthly$date)
county_monthly$year_month <- floor_date(county_monthly$date, "month")
county_monthly$state_fips <- substr(as.character(county_monthly$fips), 1, 2)

# Aggregate to state-month
panel1 <- aggregate(
  cbind(filings_count, renter_occupied_housing_units) ~ state_fips + year_month,
  data = county_monthly,
  FUN = sum,
  na.rm = TRUE
)

names(panel1)[3:4] <- c("filings", "renter_hh")
panel1$outcome <- (panel1$filings / panel1$renter_hh) * 1000
panel1 <- panel1[!is.na(panel1$state_fips) & panel1$renter_hh > 0, ]

# Add treatment dates
state_fips_map <- data.frame(
  state_abbrev = c(state.abb, "DC"),
  state_fips = c(sprintf("%02d", 1:50), "11"),
  stringsAsFactors = FALSE
)

gambling_clean <- merge(gambling_dates, state_fips_map,
                        by.x = "state", by.y = "state_abbrev", all.x = TRUE)
gambling_clean$treatment_date <- ymd(gambling_clean$first_start_date)
gambling_clean <- gambling_clean[, c("state_fips", "treatment_date")]

panel1 <- merge(panel1, gambling_clean, by = "state_fips", all.x = TRUE)
panel1$treated_state <- !is.na(panel1$treatment_date)
panel1$post_treatment <- ifelse(
  panel1$treated_state & panel1$year_month >= panel1$treatment_date, 1, 0
)

# Create analysis panel
analysis_panel <- data.frame(
  state = panel1$state_fips,
  month = panel1$year_month,
  outcome = panel1$outcome,
  treated_state = panel1$treated_state,
  post_treatment = panel1$post_treatment,
  stringsAsFactors = FALSE
)

analysis_panel <- analysis_panel[order(analysis_panel$state, analysis_panel$month), ]

cat(sprintf("  Panel: %d observations, %d states, %d months\n",
            nrow(analysis_panel),
            length(unique(analysis_panel$state)),
            length(unique(analysis_panel$month))))
cat(sprintf("  Date range: %s to %s\n\n",
            min(analysis_panel$month), max(analysis_panel$month)))

################################################################################
# CALIBRATE ERROR PROCESS
################################################################################

cat("================================================================================\n")
cat("CALIBRATING ERROR PROCESS (UNTREATED DATA ONLY)\n")
cat("================================================================================\n\n")

untreated <- analysis_panel[!analysis_panel$treated_state | analysis_panel$post_treatment == 0, ]

cat(sprintf("Untreated data: %d observations from %d states\n\n",
            nrow(untreated), length(unique(untreated$state))))

cat("Estimating baseline model: outcome ~ 1 | state + month\n")
baseline_model <- feols(outcome ~ 1 | state + month, data = untreated, cluster = ~state)

print(summary(baseline_model))

untreated$residual <- resid(baseline_model)
sigma2 <- mean(aggregate(residual ~ state, data = untreated,
                        FUN = function(x) var(x, na.rm = TRUE))$residual,
               na.rm = TRUE)

cat(sprintf("\nMean residual variance (σ²): %.4f\n\n", sigma2))

################################################################################
# POWER SIMULATION
################################################################################

cat("================================================================================\n")
cat("RUNNING POWER SIMULATION - SCHEME A (RANDOM ASSIGNMENT)\n")
cat("================================================================================\n\n")

# Parameters
n_sims <- 250  # Reasonable for testing
effect_sizes <- c(0, 1, 2, 3, 4, 5)
alpha <- 0.05

all_states <- unique(analysis_panel$state)
n_states <- length(all_states)
n_treated <- round(n_states / 2)
treatment_start <- median(analysis_panel$month)

cat(sprintf("Simulations: %d per effect size\n", n_sims))
cat(sprintf("States: %d total, treating %d\n", n_states, n_treated))
cat(sprintf("Effect sizes: %s\n\n", paste(effect_sizes, collapse = ", ")))

# Run simulations
results <- data.frame()

for (effect in effect_sizes) {
  cat(sprintf("Effect = %.1f ... ", effect))

  n_sig <- 0
  coefs <- numeric(n_sims)

  for (sim in 1:n_sims) {
    # Random treatment assignment
    treated_states <- sample(all_states, n_treated, replace = FALSE)

    sim_data <- analysis_panel
    sim_data$D <- as.integer(
      (sim_data$state %in% treated_states) &
      (sim_data$month >= treatment_start)
    )

    # Add effect
    sim_data$outcome_sim <- sim_data$outcome - effect * sim_data$D

    # Estimate
    tryCatch({
      model <- feols(outcome_sim ~ D | state + month, data = sim_data, cluster = ~state)
      coef_est <- coef(model)["D"]
      pval <- pvalue(model)["D"]

      coefs[sim] <- coef_est
      if (pval <= alpha) n_sig <- n_sig + 1
    }, error = function(e) NULL)
  }

  power <- n_sig / n_sims

  results <- rbind(results, data.frame(
    effect_size = effect,
    power = power,
    mean_coef = mean(coefs, na.rm = TRUE),
    median_coef = median(coefs, na.rm = TRUE),
    n_sims = n_sims
  ))

  cat(sprintf("Power = %.1f%%\n", power * 100))
}

################################################################################
# CALCULATE MDE
################################################################################

cat("\n================================================================================\n")
cat("MINIMUM DETECTABLE EFFECT\n")
cat("================================================================================\n\n")

results_nonzero <- results[results$effect_size > 0, ]

if (nrow(results_nonzero) >= 2) {
  power_target <- 0.80
  results_nonzero$gap <- abs(results_nonzero$power - power_target)
  results_nonzero <- results_nonzero[order(results_nonzero$gap), ]

  closest <- results_nonzero[1:2, ]
  fit <- lm(power ~ effect_size, data = closest)
  mde <- (power_target - coef(fit)[1]) / coef(fit)[2]

  cat(sprintf("MDE at 80%% power, 5%% alpha: %.3f filings per 1,000 renters\n\n", mde))

  # Save MDE to results
  results$mde_80 <- NA
  results$mde_80[1] <- mde
}

################################################################################
# DISPLAY RESULTS
################################################################################

cat("Power Analysis Results:\n")
cat("--------------------------------------------------------------------------------\n")
print(results, row.names = FALSE)
cat("--------------------------------------------------------------------------------\n\n")

################################################################################
# SAVE
################################################################################

cat("Saving results...\n")

write.csv(results, "power_results_MINIMAL.csv", row.names = FALSE)
write.csv(analysis_panel, "analysis_panel_MINIMAL.csv", row.names = FALSE)

save(analysis_panel, baseline_model, results, sigma2,
     file = "power_analysis_MINIMAL.RData")

cat("\n================================================================================\n")
cat("ANALYSIS COMPLETE\n")
cat("================================================================================\n\n")

cat("Output files:\n")
cat("  • power_results_MINIMAL.csv - Power analysis results\n")
cat("  • analysis_panel_MINIMAL.csv - Prepared panel data\n")
cat("  • power_analysis_MINIMAL.RData - Full workspace\n\n")

cat("Summary:\n")
cat(sprintf("  States: %d\n", n_states))
cat(sprintf("  Observations: %d\n", nrow(analysis_panel)))
cat(sprintf("  Simulations: %d per effect size\n", n_sims))
if (exists("mde")) {
  cat(sprintf("  MDE (80%% power): %.3f filings per 1,000 renters\n\n", mde))
}

cat("To view results:\n")
cat("  results <- read.csv('power_results_MINIMAL.csv')\n")
cat("  print(results)\n\n")

