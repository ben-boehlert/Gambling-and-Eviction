################################################################################
# Simulated Power Analysis for Eviction-Gambling Study
# Following Black et al. (2021) and Burlig et al. (2020) Methodology
#
# This script implements a serial-correlation-robust power analysis using:
# - Real untreated/pre-period eviction filing data
# - Random assignment of pseudo-treatment
# - Moving-block bootstrap to preserve within-state autocorrelation
# - Two assignment schemes: (A) random treated states, (B) staggered adoption
################################################################################

library(tidyverse)
library(fixest)      # For feols() with clustering
library(boot)        # For bootstrap
library(fwildclusterboot)  # For wild cluster bootstrap
library(lubridate)
library(here)

set.seed(20251224)  # For reproducibility

################################################################################
# 1. DATA PREPARATION
################################################################################

# Load data files
cat("Loading data files...\n")

# County-month eviction data
county_monthly <- read_csv("monthly_county_data_download.csv")

# Eviction Lab sites monthly data
sites_monthly <- read_csv("all_sites_monthly_2020_2021.csv")

# Sports gambling legalization dates
gambling_dates <- read_csv("sports_gambling_legalization_dates.csv")

cat("Data loaded successfully.\n")
cat(sprintf("County data: %d rows\n", nrow(county_monthly)))
cat(sprintf("Sites data: %d rows\n", nrow(sites_monthly)))
cat(sprintf("Gambling dates: %d states\n", nrow(gambling_dates)))

################################################################################
# Build Panel 1: County data aggregated to state-month
################################################################################

cat("\nBuilding Panel 1: County data → State-month...\n")

# Extract state FIPS from county FIPS (first 2 digits)
panel1 <- county_monthly %>%
  mutate(
    date = ymd_hms(date),
    year_month = floor_date(date, "month"),
    state_fips = str_sub(as.character(fips), 1, 2)
  ) %>%
  group_by(state_fips, year_month) %>%
  summarise(
    filings = sum(filings_count, na.rm = TRUE),
    renter_hh = sum(renter_occupied_housing_units, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  filter(!is.na(state_fips), renter_hh > 0) %>%
  mutate(
    filings_per_1000_renters = (filings / renter_hh) * 1000
  )

cat(sprintf("Panel 1 created: %d state-months, %d unique states\n",
            nrow(panel1), n_distinct(panel1$state_fips)))

################################################################################
# Build Panel 2: Eviction Lab sites aggregated to state-month
################################################################################

cat("\nBuilding Panel 2: Sites data → State-month...\n")

# Parse city-state from sites data
panel2_raw <- sites_monthly %>%
  # Extract state abbreviation from city column (e.g., "Albuquerque, NM" → "NM")
  mutate(
    state_abbrev = str_trim(str_extract(city, "[A-Z]{2}$")),
    # Parse month (e.g., "Jan-20" → 2020-01-01)
    year_month = my(month)
  ) %>%
  filter(!is.na(state_abbrev), !is.na(year_month))

# Get state FIPS mapping
state_fips_map <- tibble(
  state_abbrev = state.abb,
  state_fips = sprintf("%02d", 1:50)
) %>%
  bind_rows(tibble(state_abbrev = "DC", state_fips = "11"))

panel2 <- panel2_raw %>%
  left_join(state_fips_map, by = "state_abbrev") %>%
  filter(!is.na(state_fips)) %>%
  group_by(state_fips, year_month) %>%
  summarise(
    filings_2020 = sum(filings_2020, na.rm = TRUE),
    filings_avg = sum(filings_avg, na.rm = TRUE),
    .groups = "drop"
  )

# Need renter households denominator - use county data as proxy
renter_by_state <- county_monthly %>%
  mutate(
    state_fips = str_sub(as.character(fips), 1, 2)
  ) %>%
  group_by(state_fips) %>%
  summarise(
    renter_hh = median(renter_occupied_housing_units, na.rm = TRUE),
    .groups = "drop"
  )

panel2 <- panel2 %>%
  left_join(renter_by_state, by = "state_fips") %>%
  mutate(
    # Use 2020 filings as main outcome
    filings = filings_2020,
    filings_per_1000_renters = (filings / renter_hh) * 1000
  ) %>%
  filter(!is.na(filings_per_1000_renters), renter_hh > 0)

cat(sprintf("Panel 2 created: %d state-months, %d unique states\n",
            nrow(panel2), n_distinct(panel2$state_fips)))

################################################################################
# Add treatment dates to both panels
################################################################################

cat("\nMerging gambling legalization dates...\n")

# Create state FIPS to gambling date mapping
gambling_dates_clean <- gambling_dates %>%
  left_join(state_fips_map, by = c("state" = "state_abbrev")) %>%
  filter(!is.na(state_fips)) %>%
  mutate(
    # Use first_start_date as treatment date
    treatment_date = ymd(first_start_date)
  ) %>%
  select(state_fips, treatment_date)

# Add to panel1
panel1 <- panel1 %>%
  left_join(gambling_dates_clean, by = "state_fips") %>%
  mutate(
    treated_state = !is.na(treatment_date),
    post_treatment = if_else(treated_state & year_month >= treatment_date, 1, 0, missing = 0)
  )

# Add to panel2
panel2 <- panel2 %>%
  left_join(gambling_dates_clean, by = "state_fips") %>%
  mutate(
    treated_state = !is.na(treatment_date),
    post_treatment = if_else(treated_state & year_month >= treatment_date, 1, 0, missing = 0)
  )

cat(sprintf("Panel 1: %d treated states, %d never-treated\n",
            sum(panel1 %>% distinct(state_fips, treated_state) %>% pull(treated_state)),
            sum(!(panel1 %>% distinct(state_fips, treated_state) %>% pull(treated_state)))))

cat(sprintf("Panel 2: %d treated states, %d never-treated\n",
            sum(panel2 %>% distinct(state_fips, treated_state) %>% pull(treated_state)),
            sum(!(panel2 %>% distinct(state_fips, treated_state) %>% pull(treated_state)))))

################################################################################
# Choose which panel to use for power analysis
################################################################################

# Use Panel 1 (county data) as it has broader coverage
analysis_panel <- panel1 %>%
  mutate(
    state = state_fips,
    month = year_month,
    outcome = filings_per_1000_renters
  ) %>%
  select(state, month, outcome, treated_state, post_treatment, treatment_date) %>%
  arrange(state, month)

cat(sprintf("\nAnalysis panel: %d observations from %d states over %d months\n",
            nrow(analysis_panel),
            n_distinct(analysis_panel$state),
            n_distinct(analysis_panel$month)))

# Get date range
cat(sprintf("Date range: %s to %s\n",
            min(analysis_panel$month),
            max(analysis_panel$month)))

################################################################################
# 2. CALIBRATE ERROR PROCESS FROM UNTREATED DATA
# Following Burlig et al. (2020) - use only untreated months
################################################################################

cat("\n" %+% paste(rep("=", 80), collapse = "") %+% "\n")
cat("CALIBRATING ERROR PROCESS FROM UNTREATED DATA\n")
cat(paste(rep("=", 80), collapse = "") %+% "\n")

# Identify untreated observations (never-treated states + pre-treatment months)
untreated_data <- analysis_panel %>%
  filter(!treated_state | (treated_state & post_treatment == 0))

cat(sprintf("Untreated data: %d observations from %d states\n",
            nrow(untreated_data),
            n_distinct(untreated_data$state)))

# Estimate baseline model to get residuals
# Following Black et al.: outcome ~ state FE + time FE
baseline_model <- feols(
  outcome ~ 1 | state + month,
  data = untreated_data,
  cluster = ~state
)

cat("\nBaseline model (untreated data only):\n")
print(summary(baseline_model))

# Extract residuals
untreated_data$residual <- resid(baseline_model)

# Calculate variance and covariance terms (Burlig et al. Assumption 5)
# This will be used for SCR power calculations

calculate_covariance_terms <- function(data, m_pre, r_post) {
  # data should have columns: state, month, residual
  # m_pre: number of pre-periods to use
  # r_post: number of post-periods to use

  # For each state, calculate pairwise covariances
  state_covs <- data %>%
    arrange(state, month) %>%
    group_by(state) %>%
    mutate(time_index = row_number()) %>%
    filter(n() >= m_pre + r_post) %>%  # Need enough observations
    slice(1:(m_pre + r_post)) %>%  # Take first m+r observations
    summarise(
      # Variance
      sigma2_omega = var(residual, na.rm = TRUE),

      # Pre-period covariances (psi_B)
      psi_B = if_else(
        m_pre > 1,
        mean(sapply(1:(m_pre-1), function(lag) {
          cor(residual[1:(m_pre-lag)], residual[(1+lag):m_pre], use = "complete.obs") *
            sigma2_omega
        }), na.rm = TRUE),
        0
      ),

      # Post-period covariances (psi_A)
      psi_A = if_else(
        r_post > 1,
        mean(sapply(1:(r_post-1), function(lag) {
          post_start <- m_pre + 1
          post_end <- m_pre + r_post
          cor(residual[post_start:(post_end-lag)], residual[(post_start+lag):post_end],
              use = "complete.obs") * sigma2_omega
        }), na.rm = TRUE),
        0
      ),

      # Cross-period covariances (psi_X)
      psi_X = mean(sapply(1:m_pre, function(i) {
        sapply(1:r_post, function(j) {
          cor(residual[i], residual[m_pre + j], use = "complete.obs") * sigma2_omega
        })
      }), na.rm = TRUE),

      .groups = "drop"
    )

  # Average across states (Assumption 5)
  list(
    sigma2_omega = mean(state_covs$sigma2_omega, na.rm = TRUE),
    psi_B = mean(state_covs$psi_B, na.rm = TRUE),
    psi_A = mean(state_covs$psi_A, na.rm = TRUE),
    psi_X = mean(state_covs$psi_X, na.rm = TRUE),
    n_states = nrow(state_covs)
  )
}

# Calculate for baseline design (e.g., 6 pre, 6 post months)
baseline_params <- calculate_covariance_terms(untreated_data, m_pre = 6, r_post = 6)

cat("\nEstimated error parameters (6 pre, 6 post):\n")
cat(sprintf("  σ²_ω = %.4f\n", baseline_params$sigma2_omega))
cat(sprintf("  ψ_B  = %.4f\n", baseline_params$psi_B))
cat(sprintf("  ψ_A  = %.4f\n", baseline_params$psi_A))
cat(sprintf("  ψ_X  = %.4f\n", baseline_params$psi_X))
cat(sprintf("  Based on %d states\n", baseline_params$n_states))

cat("\nError process calibration complete.\n")

################################################################################
# Save workspace
################################################################################

cat("\nSaving data and proceeding to simulation...\n")
save.image(file = "eviction_gambling_power_workspace.RData")

cat("\n=== DATA PREPARATION COMPLETE ===\n")
cat("Proceed to run power simulations in next section.\n\n")
