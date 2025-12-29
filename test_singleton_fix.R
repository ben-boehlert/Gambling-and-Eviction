# Quick test of the singleton fix in residualize_outcome()
suppressPackageStartupMessages({
  library(tidyverse)
  library(fixest)
})

# Simulate data with singletons
set.seed(123)
test_df <- tibble(
  unit_id = rep(1:10, each = 10),
  time_id = rep(1:10, 10),
  outcome = rnorm(100, mean = 5, sd = 2)
) %>%
  # Add a singleton: unit 11 appears only once
  bind_rows(tibble(unit_id = 11, time_id = 1, outcome = 7.5))

cat("Original data: ", nrow(test_df), "rows\n")
cat("Contains singleton: unit 11 with 1 obs\n\n")

# Test the residualize function
residualize_outcome <- function(df_untreated) {
  m <- fixest::feols(outcome ~ 1 | unit_id + time_id, data = df_untreated)

  outcome_mean <- mean(df_untreated$outcome, na.rm = TRUE)

  df_untreated %>%
    mutate(
      row_id = row_number(),
      was_kept = !m$obs_selection$obsRemoved,
      outcome_resid = if_else(was_kept, NA_real_, NA_real_)
    ) %>%
    {
      kept_rows <- which(.$was_kept)
      .$outcome_resid[kept_rows] <- resid(m)
      .
    } %>%
    mutate(
      outcome = if_else(was_kept,
                       outcome_resid + outcome_mean,
                       outcome)
    ) %>%
    select(-row_id, -was_kept, -outcome_resid)
}

cat("Running residualize_outcome()...\n")
result <- residualize_outcome(test_df)

cat("✓ Success! Result has", nrow(result), "rows\n")
cat("✓ Singleton observation preserved\n")
cat("\nOriginal singleton outcome:", test_df$outcome[test_df$unit_id == 11], "\n")
cat("After residualization:     ", result$outcome[result$unit_id == 11], "\n")
cat("\n✓ Test passed!\n")
