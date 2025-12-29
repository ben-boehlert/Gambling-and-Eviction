# Test power simulation with hypothetical sample sizes
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(did)
})

set.seed(12345)

cfg <- list(
  data_dir = ".",
  panel_choice = "states_from_counties",
  outcome_preference = c("filings_count_per_1k_renters"),
  weights_var = NULL,  # Disable weights for simplicity
  treat_date_col = "online_start_date",
  pre_len = 12,
  post_len = 12,
  effect_shape = "step",
  delay_h = 6,
  did_bstrap = FALSE,
  cluster_level = "unit",
  estimand = "overall_att",
  alpha = 0.05
)

source("power_simulation_cs.R", echo = FALSE, verbose = FALSE)

cat("=== HYPOTHETICAL SAMPLE SIZE TEST ===\n\n")

# Load the actual data as a template
panel_df <- load_panel(cfg)
treat_schedule <- make_treat_schedule(panel_df, cfg)
treat_schedule_std <- standardize_treat_schedule(treat_schedule, panel_df)
baseline <- build_untreated_sample(panel_df, treat_schedule_std)

cat("Current real data:\n")
cat("  Never-treated states in baseline:", n_distinct(baseline$unit_id), "\n\n")

# Now simulate what would happen with MORE states
# Replicate the never-treated states to create a hypothetical larger sample
n_replications <- 3  # This gives us ~45 states (15 * 3)

cat("Creating hypothetical sample with", n_replications, "x replication...\n")

# Replicate states by adding offset to unit_id
# Create truly independent states (not tied to original state_abb)
hypothetical_baseline <- map_dfr(1:n_replications, function(i) {
  baseline %>%
    mutate(
      unit_id = unit_id + (i - 1) * 1000,  # Offset to create unique IDs
      state_abb = paste0("S", sprintf("%02d", unit_id + (i - 1) * 1000))  # Independent state IDs
    )
})

cat("  Hypothetical baseline states:", n_distinct(hypothetical_baseline$unit_id), "\n")
cat("  Observations:", nrow(hypothetical_baseline), "\n\n")

# Draw placebo schedule on hypothetical data
cat("Drawing placebo schedule...\n")
placebo <- draw_placebo_schedule(treat_schedule_std, cfg, baseline_df = hypothetical_baseline)

cat("  Placebo-treated states:", sum(placebo$g_placebo > 0), "\n")
cat("  Never-treated (controls):", sum(placebo$g_placebo == 0), "\n\n")

# Impose effect
cat("Imposing effect (size = 1.5)...\n")
df_sim <- impose_effect(hypothetical_baseline, placebo, effect_size = 1.5, cfg)

# Run CS estimator
cat("Running CS estimator...\n\n")
result <- run_estimator_and_extract_p(df_sim, cfg, "unit_id")

cat("=== RESULT ===\n")
cat("p-value:", result$p, "\n")
cat("estimate:", result$est, "\n")
cat("SE:", result$se, "\n\n")

if (!is.na(result$p)) {
  cat("✓✓✓ SUCCESS with hypothetical sample size! ✓✓✓\n")
  cat("\nWith ~", n_distinct(hypothetical_baseline$unit_id), "states, CS estimator works!\n")
  cat("True effect:", 1.5, "\n")
  cat("Estimated effect:", round(result$est, 3), "\n")
  cat("Significant at alpha=0.05:", result$p < 0.05, "\n")
} else {
  cat("Still failing - may need even larger sample\n")
}
