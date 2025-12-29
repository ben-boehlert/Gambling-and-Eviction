################################################################################
# FIX DATA AND RUN POWER ANALYSIS - V2
# Fixed to use full state names from CSV
################################################################################

library(fixest)
library(lubridate)

set.seed(20251224)

cat("================================================================================\n")
cat("FIXED POWER ANALYSIS (V2 - Using Full State Names)\n")
cat("================================================================================\n\n")

################################################################################
# Step 1: REBUILD THE PANEL WITH CORRECT TREATMENT ASSIGNMENT
################################################################################

cat("Step 1: Loading and rebuilding data...\n\n")

# Load county data
county_monthly <- read.csv("monthly_county_data_download.csv", stringsAsFactors = FALSE)

# Parse dates and create state FIPS
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

cat(sprintf("  County data aggregated: %d state-months\n", nrow(panel1)))

# Load gambling dates
gambling_dates <- read.csv("sports_gambling_legalization_dates.csv", stringsAsFactors = FALSE)

cat(sprintf("  Gambling dates loaded: %d states\n", nrow(gambling_dates)))
cat("  First few states in gambling file:\n")
print(head(gambling_dates$state, 10))

# Create COMPREHENSIVE state name to FIPS mapping
state_name_to_fips <- data.frame(
  state_name = c(
    "Alabama", "Alaska", "Arizona", "Arkansas", "California",
    "Colorado", "Connecticut", "Delaware", "District of Columbia", "Florida",
    "Georgia", "Hawaii", "Idaho", "Illinois", "Indiana",
    "Iowa", "Kansas", "Kentucky", "Louisiana", "Maine",
    "Maryland", "Massachusetts", "Michigan", "Minnesota", "Mississippi",
    "Missouri", "Montana", "Nebraska", "Nevada", "New Hampshire",
    "New Jersey", "New Mexico", "New York", "North Carolina", "North Dakota",
    "Ohio", "Oklahoma", "Oregon", "Pennsylvania", "Rhode Island",
    "South Carolina", "South Dakota", "Tennessee", "Texas", "Utah",
    "Vermont", "Virginia", "Washington", "West Virginia", "Wisconsin", "Wyoming"
  ),
  state_fips = sprintf("%02d", c(
    1, 2, 4, 5, 6,  # AL-CA
    8, 9, 10, 11, 12,  # CO-FL
    13, 15, 16, 17, 18,  # GA-IN
    19, 20, 21, 22, 23,  # IA-ME
    24, 25, 26, 27, 28,  # MD-MS
    29, 30, 31, 32, 33,  # MO-NH
    34, 35, 36, 37, 38,  # NJ-ND
    39, 40, 41, 42, 44,  # OH-RI
    45, 46, 47, 48, 49,  # SC-UT
    50, 51, 53, 54, 55, 56  # VT-WY
  )),
  stringsAsFactors = FALSE
)

# Merge gambling dates with state FIPS using FULL STATE NAMES
gambling_clean <- merge(gambling_dates, state_name_to_fips,
                        by.x = "state", by.y = "state_name", all.x = TRUE)
gambling_clean$treatment_date <- ymd(gambling_clean$first_start_date)

# Keep only state_fips and treatment_date
gambling_clean <- gambling_clean[!is.na(gambling_clean$state_fips),
                                 c("state_fips", "treatment_date")]

cat(sprintf("\n  States with FIPS codes matched: %d\n", nrow(gambling_clean)))
cat("  Sample matched states:\n")
print(head(gambling_clean, 10))

# Merge with panel
panel1 <- merge(panel1, gambling_clean, by = "state_fips", all.x = TRUE)

# Create treatment indicators
panel1$treated_state <- !is.na(panel1$treatment_date)
panel1$post_treatment <- 0
panel1$post_treatment[panel1$treated_state &
                      panel1$year_month >= panel1$treatment_date] <- 1

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

cat("\n=== DATA SUMMARY ===\n")
cat(sprintf("Total observations: %d\n", nrow(analysis_panel)))
cat(sprintf("Unique states: %d\n", length(unique(analysis_panel$state))))
cat(sprintf("Date range: %s to %s\n",
            min(analysis_panel$month), max(analysis_panel$month)))

# Count treated states
treated_states <- unique(analysis_panel$state[analysis_panel$treated_state])
never_treated <- setdiff(unique(analysis_panel$state), treated_states)

cat(sprintf("\nTreated states: %d\n", length(treated_states)))
cat("Sample treated state FIPS codes:\n")
print(head(treated_states, 10))

cat(sprintf("\nNever-treated states: %d\n", length(never_treated)))
cat(sprintf("Observations with post_treatment=1: %d\n\n",
            sum(analysis_panel$post_treatment)))

if (length(treated_states) == 0) {
  cat("ERROR: Still no treated states found!\n")
  cat("\nDebugging info:\n")
  cat("Gambling states from CSV:\n")
  print(unique(gambling_dates$state))
  cat("\nState name to FIPS mapping (first 10):\n")
  print(head(state_name_to_fips, 10))
  stop("Cannot proceed without treated states")
}

################################################################################
# Step 2: CALIBRATE ERROR PROCESS
################################################################################

cat("================================================================================\n")
cat("Step 2: Calibrating error process (untreated data only)...\n")
cat("================================================================================\n\n")

untreated <- analysis_panel[!analysis_panel$treated_state |
                            analysis_panel$post_treatment == 0, ]

cat(sprintf("Untreated observations: %d from %d states\n\n",
            nrow(untreated), length(unique(untreated$state))))

baseline_model <- feols(outcome ~ 1 | state + month, data = untreated, cluster = ~state)

cat("Baseline Model Summary:\n")
print(summary(baseline_model))

untreated$residual <- resid(baseline_model)
sigma2 <- mean(aggregate(residual ~ state, data = untreated,
                        FUN = function(x) var(x, na.rm = TRUE))$residual,
               na.rm = TRUE)

cat(sprintf("\nMean residual variance (σ²): %.4f\n\n", sigma2))

################################################################################
# Step 3: POWER SIMULATION
################################################################################

cat("================================================================================\n")
cat("Step 3: Running power simulation...\n")
cat("================================================================================\n\n")

n_sims <- 250
effect_sizes <- c(0, 0.5, 1, 1.5, 2, 2.5, 3, 4, 5)
alpha <- 0.05

all_states <- unique(analysis_panel$state)
n_states <- length(all_states)
n_treated_sim <- round(n_states / 2)
treatment_start <- median(analysis_panel$month)

cat(sprintf("Simulations: %d per effect size\n", n_sims))
cat(sprintf("States: %d total, treating %d in simulations\n", n_states, n_treated_sim))
cat(sprintf("Pseudo-treatment starts: %s\n", treatment_start))
cat(sprintf("Effect sizes: %s\n\n", paste(effect_sizes, collapse = ", ")))

results <- data.frame()

for (effect in effect_sizes) {
  cat(sprintf("Effect = %.2f ... ", effect))

  n_sig <- 0
  coefs <- numeric(n_sims)

  for (sim in 1:n_sims) {
    # Random treatment assignment
    treated_sim <- sample(all_states, n_treated_sim, replace = FALSE)

    sim_data <- analysis_panel
    sim_data$D <- as.integer(
      (sim_data$state %in% treated_sim) &
      (sim_data$month >= treatment_start)
    )

    # Add effect (NEGATIVE because we expect reduction in evictions)
    sim_data$outcome_sim <- sim_data$outcome - effect * sim_data$D

    # Estimate
    tryCatch({
      model <- feols(outcome_sim ~ D | state + month,
                    data = sim_data, cluster = ~state)
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
# Step 4: CALCULATE MDE
################################################################################

cat("\n================================================================================\n")
cat("Step 4: Calculating MDE...\n")
cat("================================================================================\n\n")

results_nonzero <- results[results$effect_size > 0, ]

if (nrow(results_nonzero) >= 2) {
  power_target <- 0.80
  results_nonzero$gap <- abs(results_nonzero$power - power_target)
  results_nonzero <- results_nonzero[order(results_nonzero$gap), ]

  closest <- results_nonzero[1:min(2, nrow(results_nonzero)), ]
  fit <- lm(power ~ effect_size, data = closest)
  mde <- (power_target - coef(fit)[1]) / coef(fit)[2]

  cat(sprintf("✓ MDE at 80%% power, 5%% alpha: %.3f filings per 1,000 renters\n\n", mde))

  results$mde_80 <- NA
  results$mde_80[1] <- mde
}

cat("\n=== POWER ANALYSIS RESULTS ===\n")
cat("--------------------------------------------------------------------------------\n")
print(results, row.names = FALSE)
cat("--------------------------------------------------------------------------------\n\n")

################################################################################
# Step 5: SAVE RESULTS
################################################################################

cat("Saving results...\n")

write.csv(results, "power_results_FINAL.csv", row.names = FALSE)
write.csv(analysis_panel, "analysis_panel_FINAL.csv", row.names = FALSE)

save(analysis_panel, baseline_model, results, sigma2,
     file = "power_analysis_FINAL.RData")

cat("\n================================================================================\n")
cat("✓✓✓ ANALYSIS COMPLETE ✓✓✓\n")
cat("================================================================================\n\n")

cat("Output files:\n")
cat("  • power_results_FINAL.csv ← YOUR RESULTS ARE HERE\n")
cat("  • analysis_panel_FINAL.csv\n")
cat("  • power_analysis_FINAL.RData\n\n")

if (exists("mde")) {
  cat("================================================================================\n")
  cat(sprintf("  KEY RESULT: MDE = %.3f filings per 1,000 renters (80%% power)\n", mde))
  cat("================================================================================\n\n")
}

cat("Summary:\n")
cat(sprintf("  ✓ %d treated states (with gambling legalization)\n", length(treated_states)))
cat(sprintf("  ✓ %d never-treated states\n", length(never_treated)))
cat(sprintf("  ✓ %d total state-month observations\n", nrow(analysis_panel)))
cat(sprintf("  ✓ %d observations after treatment\n", sum(analysis_panel$post_treatment)))
cat(sprintf("  ✓ %d simulations per effect size\n\n", n_sims))
