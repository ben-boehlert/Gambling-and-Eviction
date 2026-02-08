#!/usr/bin/env Rscript
# Minimal test: Does did::att_gt give correct test size under null?

suppressPackageStartupMessages({
  library(did)
  library(dplyr)
})

set.seed(20260113)

# Simple DGP: balanced panel, pure null (no effect)
n_units <- 40
n_periods <- 20
n_treated <- 20

# Create panel
df <- expand.grid(
  id = 1:n_units,
  t = 1:n_periods
) %>%
  mutate(
    g = ifelse(id <= n_treated, 10, 0),  # Half treated at period 10
    y = rnorm(n())  # Pure noise, no effect
  )

# Run CS estimation
result <- att_gt(
  yname = "y",
  tname = "t",
  idname = "id",
  gname = "g",
  data = df,
  panel = TRUE,
  control_group = "nevertreated",
  bstrap = TRUE,
  biters = 199,
  cband = FALSE,
  clustervars = "id"
)

# Aggregate
agg <- aggte(result, type = "simple", na.rm = TRUE)

# Extract
att <- agg$overall.att
se <- agg$overall.se

# Compute p-value
z <- att / se
p_t <- 2 * pt(-abs(z), df = n_units - 1)

cat("Minimal test (n_units=", n_units, ", null DGP):\n", sep = "")
cat("  ATT:", format(att, digits = 4), "\n")
cat("  SE: ", format(se, digits = 4), "\n")
cat("  Z:  ", format(z, digits = 4), "\n")
cat("  p:  ", format(p_t, digits = 4), "\n\n")

# Repeat 100 times
cat("Running 100 simulations...\n")
results <- replicate(100, {
  df$y <- rnorm(nrow(df))

  result <- suppressWarnings(att_gt(
    yname = "y", tname = "t", idname = "id", gname = "g",
    data = df, panel = TRUE, control_group = "nevertreated",
    bstrap = TRUE, biters = 199, cband = FALSE, clustervars = "id"
  ))

  agg <- aggte(result, type = "simple", na.rm = TRUE)
  att <- agg$overall.att
  se <- agg$overall.se
  z <- att / se
  p <- 2 * pt(-abs(z), df = n_units - 1)

  c(att = att, se = se, z = z, p = p)
})

results_df <- as.data.frame(t(results))

cat("\nResults summary (n=100):\n")
cat("  mean(ATT):", format(mean(results_df$att), digits = 4), "\n")
cat("  sd(ATT):  ", format(sd(results_df$att), digits = 4), "\n")
cat("  mean(SE): ", format(mean(results_df$se), digits = 4), "\n")
cat("  SE/sd(ATT) ratio:", format(mean(results_df$se) / sd(results_df$att), digits = 3), "\n")
cat("  sd(Z):    ", format(sd(results_df$z), digits = 4), "\n")
cat("  Rejection rate (5%):", format(mean(results_df$p < 0.05), digits = 3), "\n\n")

cat("If SE/sd(ATT) >> 1 and rejection rate << 5%, SE is inflated.\n")
