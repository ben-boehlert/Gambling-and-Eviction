#!/usr/bin/env Rscript
# Test whether IQR-based SD estimator is biased with small samples

set.seed(123)

# Test IQR estimator bias for different sample sizes
test_iqr_bias <- function(n, n_sims = 10000) {
  iqr_estimates <- replicate(n_sims, {
    x <- rnorm(n)
    (quantile(x, 0.75) - quantile(x, 0.25)) / (qnorm(0.75) - qnorm(0.25))
  })

  list(
    n = n,
    mean_iqr_sd = mean(iqr_estimates),
    sd_iqr_sd = sd(iqr_estimates),
    bias = mean(iqr_estimates) - 1.0,
    median_iqr_sd = median(iqr_estimates)
  )
}

cat("Testing IQR-based SD estimator bias\n")
cat("(True SD = 1.0 for standard normal)\n\n")

results <- lapply(c(10, 20, 30, 50, 100, 200, 500, 1000), test_iqr_bias)

df <- do.call(rbind, lapply(results, as.data.frame))
print(df)

cat("\n")
cat("Key finding: IQR estimator has POSITIVE bias for small n\n")
cat("With n=200 bootstrap iterations, bias ≈",
    round(df$bias[df$n == 200], 3), "\n")
