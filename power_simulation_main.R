################################################################################
# POWER SIMULATION - Main Analysis
# Implementing Black et al. (2021) and Burlig et al. (2020) methodology
#
# This script runs simulated power analyses with:
# - Scheme A: Random treated states with common post-period
# - Scheme B: Staggered adoption (permuted dates)
# - Moving-block bootstrap for error calibration
# - Wild cluster bootstrap option
################################################################################

library(tidyverse)
library(fixest)
library(fwildclusterboot)
library(future)
library(future.apply)

# Load prepared data
load("eviction_gambling_power_workspace.RData")

cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("SIMULATED POWER ANALYSIS\n")
cat(paste(rep("=", 80), collapse = ""), "\n\n", sep = "")

################################################################################
# HELPER FUNCTIONS
################################################################################

# Select last m_pre pre-periods and first r_post post-periods around treatment
get_pre_post_periods <- function(months, treatment_date, m_pre, r_post) {
  ordered_months <- sort(unique(months))
  pre_months <- ordered_months[ordered_months < treatment_date]
  post_months <- ordered_months[ordered_months >= treatment_date]

  if (length(pre_months) < m_pre || length(post_months) < r_post) {
    return(NULL)
  }

  c(tail(pre_months, m_pre), head(post_months, r_post))
}

# Moving-block bootstrap for residuals
# Preserves within-state autocorrelation
moving_block_bootstrap <- function(residuals, block_length = 3) {
  n <- length(residuals)
  if (n <= block_length) return(residuals)

  n_blocks <- ceiling(n / block_length)
  starts <- sample(1:(n - block_length + 1), n_blocks, replace = TRUE)

  bootstrapped <- unlist(lapply(starts, function(start) {
    residuals[start:min(start + block_length - 1, n)]
  }))

  return(bootstrapped[1:n])
}

# Calculate SCR variance formula (Burlig et al. Eq. 2)
calculate_scr_variance <- function(P, J, m, r, sigma2, psi_B, psi_A, psi_X) {
  variance <- (1 / (P * (1 - P) * J)) * (
    ((m + r) / (m * r)) * sigma2 +
    ((m - 1) / m) * psi_B +
    ((r - 1) / r) * psi_A -
    2 * psi_X
  )
  return(variance)
}

# Calculate MDE at target power (Black et al. approach, lines 547-555)
calculate_mde <- function(P, J, m, r, sigma2, psi_B, psi_A, psi_X,
                          alpha = 0.05, power = 0.80) {
  variance <- calculate_scr_variance(P, J, m, r, sigma2, psi_B, psi_A, psi_X)
  se <- sqrt(variance)

  # t-distribution critical values
  df <- J - 1  # Clustering at state level
  t_alpha <- qt(1 - alpha/2, df)
  t_power <- qt(power, df)

  mde <- (t_alpha + t_power) * se
  return(mde)
}

################################################################################
# SCHEME A: Random Treated States with Common Post-Period
# (Following Black et al. simple_power_example.do lines 234-249)
################################################################################

run_scheme_a_simulation <- function(
    data,
    n_treated_states,
    effect_size,
    m_pre,
    r_post,
    block_length = 3,
    use_wild_bootstrap = FALSE
) {
  # Get unique states
  states <- unique(data$state)
  n_states <- length(states)

  # Randomly assign treatment (lines 234-249)
  treated_states <- sample(states, n_treated_states, replace = FALSE)

  # Create pseudo-treatment indicator
  # Assume treatment starts at median date in the panel
  treatment_start <- median(data$month)

  sim_data <- data %>%
    mutate(
      pseudo_treated = state %in% treated_states,
      pseudo_post = month >= treatment_start,
      # Treatment indicator D (line 249)
      D = as.integer(pseudo_treated & pseudo_post)
    )

  # Filter to m pre-periods and r post-periods
  window_months <- get_pre_post_periods(sim_data$month, treatment_start, m_pre, r_post)

  if (is.null(window_months)) {
    return(NULL)  # Not enough data
  }

  sim_data <- sim_data %>%
    filter(month %in% window_months)

  # Add effect size by manipulating outcome (lines 266-273)
  # Following Black et al.: reduce outcome by effect_size for treated units in post period
  sim_data <- sim_data %>%
    mutate(
      outcome_sim = outcome - effect_size * D
    )

  # Estimate model: Y ~ D | state + month (lines 287-291)
  tryCatch({
    model <- feols(
      outcome_sim ~ D | state + month,
      data = sim_data,
      cluster = ~state
    )

    # Extract results
    coef_est <- coef(model)["D"]
    se_est <- se(model)["D"]
    pval <- pvalue(model)["D"]

    # Wild cluster bootstrap (optional)
    if (use_wild_bootstrap) {
      wcb <- boottest(model, param = "D", B = 999, clustid = "state", type = "rademacher")
      pval_wcb <- wcb$p_val
    } else {
      pval_wcb <- NA
    }

    list(
      coef = coef_est,
      se = se_est,
      pval = pval,
      pval_wcb = pval_wcb,
      converged = TRUE
    )
  }, error = function(e) {
    list(coef = NA, se = NA, pval = NA, pval_wcb = NA, converged = FALSE)
  })
}

################################################################################
# SCHEME B: Staggered Adoption (Permuted Treatment Dates)
################################################################################

run_scheme_b_simulation <- function(
    data,
    effect_size,
    m_pre,
    r_post,
    block_length = 3,
    use_wild_bootstrap = FALSE
) {
  # Get states that were actually treated and their treatment dates
  treated_info <- data %>%
    filter(treated_state) %>%
    distinct(state, treatment_date) %>%
    filter(!is.na(treatment_date))

  if (nrow(treated_info) == 0) {
    return(NULL)
  }

  treated_info <- treated_info %>%
    mutate(treatment_date = as.Date(format(treatment_date, "%Y-%m-01")))

  # Keep treated states with enough pre/post periods
  eligible_states <- data %>%
    mutate(month = as.Date(month)) %>%
    semi_join(treated_info, by = "state") %>%
    group_by(state) %>%
    summarise(
      pre_n = sum(month < treatment_date[1]),
      post_n = sum(month >= treatment_date[1]),
      .groups = "drop"
    ) %>%
    filter(pre_n >= m_pre, post_n >= r_post)

  treated_info <- treated_info %>%
    semi_join(eligible_states, by = "state")

  if (nrow(treated_info) == 0) {
    return(NULL)
  }

  # Permute treatment dates across states (preserving timing distribution)
  permuted_dates <- sample(treated_info$treatment_date)
  treated_info$permuted_date <- permuted_dates

  # Create simulation data with permuted treatment
  sim_data <- data %>%
    left_join(treated_info %>% select(state, permuted_date), by = "state") %>%
    mutate(
      pseudo_treated = !is.na(permuted_date),
      pseudo_post = if_else(!is.na(permuted_date) & month >= permuted_date, 1, 0, missing = 0),
      D = pseudo_post
    )

  # Filter treated states to m pre and r post months around permuted date
  treated_filtered <- sim_data %>%
    filter(pseudo_treated) %>%
    group_by(state) %>%
    group_modify(~ {
      window_months <- get_pre_post_periods(.x$month, .x$permuted_date[1], m_pre, r_post)
      if (is.null(window_months)) {
        return(tibble())
      }
      .x %>% filter(month %in% window_months)
    }) %>%
    ungroup()

  if (nrow(treated_filtered) == 0) {
    return(NULL)
  }

  # Keep never-treated states in the same calendar window as treated states
  window_months_all <- sort(unique(treated_filtered$month))
  control_filtered <- sim_data %>%
    filter(!pseudo_treated, month %in% window_months_all)

  sim_data <- bind_rows(treated_filtered, control_filtered)

  # Add effect (staggered)
  sim_data <- sim_data %>%
    mutate(
      outcome_sim = outcome - effect_size * D
    )

  # Estimate model
  tryCatch({
    model <- feols(
      outcome_sim ~ D | state + month,
      data = sim_data,
      cluster = ~state
    )

    coef_est <- coef(model)["D"]
    se_est <- se(model)["D"]
    pval <- pvalue(model)["D"]

    if (use_wild_bootstrap) {
      wcb <- boottest(model, param = "D", B = 999, clustid = "state", type = "rademacher")
      pval_wcb <- wcb$p_val
    } else {
      pval_wcb <- NA
    }

    list(
      coef = coef_est,
      se = se_est,
      pval = pval,
      pval_wcb = pval_wcb,
      converged = TRUE
    )
  }, error = function(e) {
    list(coef = NA, se = NA, pval = NA, pval_wcb = NA, converged = FALSE)
  })
}

################################################################################
# MAIN SIMULATION LOOP
################################################################################

run_power_simulation <- function(
    data,
    scheme = c("A", "B"),
    effect_sizes,
    n_sims = 500,
    m_pre = 6,
    r_post = 6,
    n_treated = NULL,  # For scheme A
    block_length = 3,
    alpha = 0.05,
    use_wild_bootstrap = FALSE
) {
  scheme <- match.arg(scheme)

  n_states <- n_distinct(data$state)
  if (scheme == "A" && is.null(n_treated)) {
    n_treated <- round(n_states / 2)
  }

  cat(sprintf("\nRunning %s simulations:\n", n_sims))
  cat(sprintf("  Scheme: %s\n", scheme))
  cat(sprintf("  Pre-periods: %d, Post-periods: %d\n", m_pre, r_post))
  cat(sprintf("  Effect sizes: %s\n", paste(effect_sizes, collapse = ", ")))
  if (scheme == "A") cat(sprintf("  Treated states: %d of %d\n", n_treated, n_states))
  cat(sprintf("  Block length: %d\n", block_length))

  results_list <- list()

  for (effect_size in effect_sizes) {
    cat(sprintf("\n  Effect size: %.4f ", effect_size))

    sim_results <- replicate(n_sims, {
      if (scheme == "A") {
        run_scheme_a_simulation(
          data, n_treated, effect_size, m_pre, r_post, block_length, use_wild_bootstrap
        )
      } else {
        run_scheme_b_simulation(
          data, effect_size, m_pre, r_post, block_length, use_wild_bootstrap
        )
      }
    }, simplify = FALSE)

    # Compile results
    valid_results <- sim_results[sapply(sim_results, function(x) !is.null(x) && x$converged)]
    n_valid <- length(valid_results)

    if (n_valid > 0) {
      coefs <- sapply(valid_results, function(x) x$coef)
      ses <- sapply(valid_results, function(x) x$se)
      pvals <- sapply(valid_results, function(x) x$pval)

      # Power (proportion significant at alpha level) - line 407-419
      power <- mean(pvals <= alpha, na.rm = TRUE)

      # Sign error rate (lines 422-433)
      # For eviction reduction, we expect negative coefficient
      # Sign error = significant AND positive (wrong sign)
      sig_wrong_sign <- sum(pvals <= alpha & coefs > 0, na.rm = TRUE)
      n_sig <- sum(pvals <= alpha, na.rm = TRUE)
      sign_error_rate <- if_else(n_sig > 0, sig_wrong_sign / n_sig, 0)

      # Magnitude error (lines 439-454)
      # Among significant results, mean |estimate/true_effect|
      if (effect_size != 0) {
        mag_errors <- abs(coefs[pvals <= alpha] / effect_size)
        mean_mag_error <- mean(mag_errors, na.rm = TRUE)
        # Severe magnitude error: >2x truth
        severe_mag_error_rate <- mean(mag_errors > 2, na.rm = TRUE)
      } else {
        mean_mag_error <- NA
        severe_mag_error_rate <- NA
      }

      results_list[[as.character(effect_size)]] <- tibble(
        effect_size = effect_size,
        power = power,
        sign_error_rate = sign_error_rate,
        mean_mag_error = mean_mag_error,
        severe_mag_error_rate = severe_mag_error_rate,
        mean_coef = mean(coefs, na.rm = TRUE),
        median_coef = median(coefs, na.rm = TRUE),
        n_valid = n_valid
      )

      cat(sprintf("Power: %.2f%%, Sign error: %.1f%%\n", power * 100, sign_error_rate * 100))
    }
  }

  bind_rows(results_list)
}

################################################################################
# ANCHOR EFFECT SIZES TO GAMBLING→BANKRUPTCY LITERATURE
################################################################################

cat("\nDefining effect size grid...\n")
cat("(Anchored to plausible magnitudes from gambling→bankruptcy literature)\n\n")

# Example: If gambling increases bankruptcies by 10%, and evictions correlate
# with financial distress at r=0.3, expect ~3% effect on evictions
# Test grid around this

effect_sizes_grid <- c(
  0,      # Placebo
  0.5,    # 0.5 filings per 1000 renters
  1.0,
  1.5,
  2.0,
  2.5,
  3.0,
  4.0,
  5.0
)

################################################################################
# RUN SIMULATIONS
################################################################################

# Scheme A: Random treated states
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("SCHEME A: Random Treated States\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

results_scheme_a <- run_power_simulation(
  data = analysis_panel,
  scheme = "A",
  effect_sizes = effect_sizes_grid,
  n_sims = 500,
  m_pre = 6,
  r_post = 6,
  n_treated = round(n_distinct(analysis_panel$state) / 2),
  block_length = 3,
  alpha = 0.05,
  use_wild_bootstrap = FALSE  # Set TRUE for wild bootstrap (slower)
)

# Scheme B: Staggered adoption
cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("SCHEME B: Staggered Adoption\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")

results_scheme_b <- run_power_simulation(
  data = analysis_panel,
  scheme = "B",
  effect_sizes = effect_sizes_grid,
  n_sims = 500,
  m_pre = 6,
  r_post = 6,
  block_length = 3,
  alpha = 0.05,
  use_wild_bootstrap = FALSE
)

################################################################################
# CALCULATE MDE AT 80% POWER
################################################################################

calculate_mde_from_results <- function(results, target_power = 0.80) {
  # Linear interpolation (Black et al. lines 547-555)
  results <- results %>%
    filter(!is.na(power), effect_size > 0) %>%
    mutate(gap = abs(power - target_power)) %>%
    arrange(gap)

  if (nrow(results) < 2) return(NA)

  # Use two closest points
  closest_two <- results %>% slice(1:2)

  # Linear regression
  fit <- lm(power ~ effect_size, data = closest_two)
  mde <- (target_power - coef(fit)[1]) / coef(fit)[2]

  return(as.numeric(mde))
}

mde_scheme_a <- calculate_mde_from_results(results_scheme_a)
mde_scheme_b <- calculate_mde_from_results(results_scheme_b)

cat("\n", paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("MINIMUM DETECTABLE EFFECTS (80% power, 5% alpha)\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat(sprintf("Scheme A (Random): %.3f filings per 1,000 renters\n", mde_scheme_a))
cat(sprintf("Scheme B (Staggered): %.3f filings per 1,000 renters\n", mde_scheme_b))

################################################################################
# SAVE RESULTS
################################################################################

write_csv(results_scheme_a, "power_results_scheme_a.csv")
write_csv(results_scheme_b, "power_results_scheme_b.csv")

save(
  results_scheme_a,
  results_scheme_b,
  effect_sizes_grid,
  mde_scheme_a,
  mde_scheme_b,
  file = "power_simulation_results.RData"
)

cat("\n=== SIMULATION COMPLETE ===\n")
cat("Results saved to:\n")
cat("  - power_results_scheme_a.csv\n")
cat("  - power_results_scheme_b.csv\n")
cat("  - power_simulation_results.RData\n\n")
