################################################################################
# CRASH-PROOF VERSION - No tidyverse, base R only
# Use this if tidyverse causes crashes
################################################################################

cat("=================================================================================\n")
cat("POWER ANALYSIS - BASE R VERSION (No tidyverse)\n")
cat("=================================================================================\n\n")

# Load only essential packages
cat("Loading packages...\n")
library(fixest)  # For regression with clustering
library(lubridate)  # For date handling

set.seed(20251224)
cat("Packages loaded successfully.\n\n")

################################################################################
# 1. LOAD DATA (base R methods)
################################################################################

cat("Step 1: Loading data files...\n")

# County data
county_monthly <- read.csv("monthly_county_data_download.csv", stringsAsFactors = FALSE)
cat(sprintf("  County data: %,d rows\n", nrow(county_monthly)))

# Sites data
sites_monthly <- read.csv("all_sites_monthly_2020_2021.csv", stringsAsFactors = FALSE)
cat(sprintf("  Sites data: %,d rows\n", nrow(sites_monthly)))

# Gambling dates
gambling_dates <- read.csv("sports_gambling_legalization_dates.csv", stringsAsFactors = FALSE)
cat(sprintf("  Gambling dates: %d rows\n\n", nrow(gambling_dates)))

################################################################################
# 2. BUILD PANEL 1 (base R)
################################################################################

cat("Step 2: Building Panel 1 (County -> State-month)...\n")

# Parse dates
county_monthly$date <- ymd_hms(county_monthly$date)
county_monthly$year_month <- floor_date(county_monthly$date, "month")

# Extract state FIPS (first 2 digits of county FIPS)
county_monthly$state_fips <- substr(as.character(county_monthly$fips), 1, 2)

# Aggregate by state-month
panel1 <- aggregate(
  cbind(filings_count, renter_occupied_housing_units) ~ state_fips + year_month,
  data = county_monthly,
  FUN = sum,
  na.rm = TRUE
)

# Rename columns
names(panel1)[3:4] <- c("filings", "renter_hh")

# Calculate filings per 1000 renters
panel1$filings_per_1000 <- (panel1$filings / panel1$renter_hh) * 1000

# Remove missing/invalid
panel1 <- panel1[!is.na(panel1$state_fips) & panel1$renter_hh > 0, ]

cat(sprintf("  Panel 1 created: %d state-months, %d unique states\n\n",
            nrow(panel1), length(unique(panel1$state_fips))))

################################################################################
# 3. ADD TREATMENT DATES
################################################################################

cat("Step 3: Adding treatment dates...\n")

# Create state abbreviation to FIPS mapping
state_abbrev <- c(state.abb, "DC")
state_fips_codes <- c(sprintf("%02d", 1:50), "11")
state_fips_map <- data.frame(
  state_abbrev = state_abbrev,
  state_fips = state_fips_codes,
  stringsAsFactors = FALSE
)

# Merge gambling dates
gambling_dates_clean <- merge(
  gambling_dates,
  state_fips_map,
  by.x = "state",
  by.y = "state_abbrev",
  all.x = TRUE
)

gambling_dates_clean$treatment_date <- ymd(gambling_dates_clean$first_start_date)
gambling_dates_clean <- gambling_dates_clean[, c("state_fips", "treatment_date")]

# Merge with panel1
panel1 <- merge(
  panel1,
  gambling_dates_clean,
  by = "state_fips",
  all.x = TRUE
)

# Create treatment indicators
panel1$treated_state <- !is.na(panel1$treatment_date)
panel1$post_treatment <- ifelse(
  panel1$treated_state & panel1$year_month >= panel1$treatment_date,
  1,
  0
)

cat(sprintf("  Treated states: %d\n",
            sum(unique(panel1[panel1$treated_state, "state_fips"]) != "")))
cat(sprintf("  Never-treated: %d\n\n",
            sum(!unique(panel1$state_fips) %in% unique(panel1[panel1$treated_state, "state_fips"]))))

################################################################################
# 4. CREATE ANALYSIS PANEL
################################################################################

analysis_panel <- data.frame(
  state = panel1$state_fips,
  month = panel1$year_month,
  outcome = panel1$filings_per_1000,
  treated_state = panel1$treated_state,
  post_treatment = panel1$post_treatment,
  treatment_date = panel1$treatment_date,
  stringsAsFactors = FALSE
)

# Sort by state and month
analysis_panel <- analysis_panel[order(analysis_panel$state, analysis_panel$month), ]

cat(sprintf("Analysis panel: %d observations, %d states\n",
            nrow(analysis_panel),
            length(unique(analysis_panel$state))))
cat(sprintf("Date range: %s to %s\n\n",
            min(analysis_panel$month), max(analysis_panel$month)))

################################################################################
# 5. CALIBRATE ERROR PROCESS (UNTREATED DATA ONLY)
################################################################################

cat("=================================================================================\n")
cat("CALIBRATING ERROR PROCESS (UNTREATED DATA ONLY)\n")
cat("=================================================================================\n\n")

# Get untreated observations (never-treated + pre-treatment)
untreated_data <- analysis_panel[
  !analysis_panel$treated_state | analysis_panel$post_treatment == 0,
]

cat(sprintf("Untreated data: %d observations from %d states\n\n",
            nrow(untreated_data),
            length(unique(untreated_data$state))))

# Estimate baseline model: outcome ~ 1 | state + month
cat("Estimating baseline model...\n")

baseline_model <- feols(
  outcome ~ 1 | state + month,
  data = untreated_data,
  cluster = ~state
)

print(summary(baseline_model))

# Extract residuals
untreated_data$residual <- resid(baseline_model)

# Calculate variance by state
variance_by_state <- aggregate(
  residual ~ state,
  data = untreated_data,
  FUN = function(x) var(x, na.rm = TRUE)
)

names(variance_by_state)[2] <- "sigma2"

cat("\n")
cat(sprintf("Mean residual variance (sigma^2): %.4f\n",
            mean(variance_by_state$sigma2, na.rm = TRUE)))
cat(sprintf("Median residual variance: %.4f\n\n",
            median(variance_by_state$sigma2, na.rm = TRUE)))

################################################################################
# 6. SIMPLE POWER SIMULATION (Scheme A)
################################################################################

cat("=================================================================================\n")
cat("RUNNING SIMPLE POWER SIMULATION\n")
cat("=================================================================================\n\n")

# Simulation parameters
n_sims <- 100  # Reduced for testing
effect_sizes <- c(0, 1, 2, 3, 4, 5)  # Filings per 1000
alpha <- 0.05

cat(sprintf("Simulations: %d per effect size\n", n_sims))
cat(sprintf("Effect sizes: %s\n\n", paste(effect_sizes, collapse = ", ")))

# Storage for results
results <- data.frame(
  effect_size = numeric(),
  n_sig = numeric(),
  n_total = numeric(),
  power = numeric(),
  mean_coef = numeric(),
  stringsAsFactors = FALSE
)

# Get unique states
all_states <- unique(analysis_panel$state)
n_states <- length(all_states)
n_treated <- round(n_states / 2)

cat(sprintf("Total states: %d, Treating: %d\n\n", n_states, n_treated))

# Define pseudo-treatment start (median month)
treatment_start <- median(analysis_panel$month)

# Loop over effect sizes
for (effect in effect_sizes) {
  cat(sprintf("Effect size: %.1f ... ", effect))

  n_sig <- 0
  coefs <- numeric(n_sims)

  # Run simulations
  for (sim in 1:n_sims) {
    # Randomly select treated states
    treated_states <- sample(all_states, n_treated, replace = FALSE)

    # Create simulation dataset
    sim_data <- analysis_panel
    sim_data$pseudo_treated <- sim_data$state %in% treated_states
    sim_data$pseudo_post <- sim_data$month >= treatment_start
    sim_data$D <- as.integer(sim_data$pseudo_treated & sim_data$pseudo_post)

    # Add effect
    sim_data$outcome_sim <- sim_data$outcome - effect * sim_data$D

    # Estimate model
    tryCatch({
      model <- feols(
        outcome_sim ~ D | state + month,
        data = sim_data,
        cluster = ~state
      )

      coef_est <- coef(model)["D"]
      pval <- pvalue(model)["D"]

      coefs[sim] <- coef_est
      if (pval <= alpha) n_sig <- n_sig + 1

    }, error = function(e) {
      # Skip if model fails
    })
  }

  # Calculate power
  power <- n_sig / n_sims

  # Store results
  results <- rbind(results, data.frame(
    effect_size = effect,
    n_sig = n_sig,
    n_total = n_sims,
    power = power,
    mean_coef = mean(coefs, na.rm = TRUE),
    stringsAsFactors = FALSE
  ))

  cat(sprintf("Power: %.1f%%\n", power * 100))
}

cat("\n")
print(results)

################################################################################
# 7. CALCULATE MDE
################################################################################

cat("\n=================================================================================\n")
cat("MINIMUM DETECTABLE EFFECT\n")
cat("=================================================================================\n\n")

# Find MDE at 80% power via linear interpolation
power_target <- 0.80
results_nonzero <- results[results$effect_size > 0, ]

if (nrow(results_nonzero) >= 2) {
  # Find two closest points to target power
  results_nonzero$gap <- abs(results_nonzero$power - power_target)
  results_nonzero <- results_nonzero[order(results_nonzero$gap), ]

  closest_two <- results_nonzero[1:2, ]

  # Linear interpolation
  fit <- lm(power ~ effect_size, data = closest_two)
  mde <- (power_target - coef(fit)[1]) / coef(fit)[2]

  cat(sprintf("MDE at 80%% power, 5%% alpha: %.3f filings per 1,000 renters\n\n", mde))
} else {
  cat("Not enough data points to calculate MDE\n\n")
}

################################################################################
# 8. SAVE RESULTS
################################################################################

cat("Saving results...\n")

write.csv(results, "power_results_base_r.csv", row.names = FALSE)
write.csv(analysis_panel, "analysis_panel_base_r.csv", row.names = FALSE)

save(
  analysis_panel,
  untreated_data,
  baseline_model,
  results,
  file = "power_analysis_base_r.RData"
)

cat("\n=================================================================================\n")
cat("ANALYSIS COMPLETE\n")
cat("=================================================================================\n\n")
cat("Output files:\n")
cat("  - power_results_base_r.csv\n")
cat("  - analysis_panel_base_r.csv\n")
cat("  - power_analysis_base_r.RData\n\n")
cat("This version uses only base R and should not crash.\n\n")
