#!/usr/bin/env Rscript
# Debug IPW failure with full error details
# NO quit() - capture all errors for analysis

suppressPackageStartupMessages({
  library(dplyr)
  library(fixest)
  library(did)
})

cat("================================================================================\n")
cat("IPW FAILURE DEBUGGING - DETAILED ERROR ANALYSIS\n")
cat("================================================================================\n\n")

# Create synthetic panel
set.seed(12345)
n_states <- 38
n_months <- 120

treatment_timing <- c(rep(0, 10), rep(60, 14), rep(80, 14))
treatment_timing <- sample(treatment_timing)

panel <- expand.grid(id = 1:n_states, t = 1:n_months)
panel$g <- treatment_timing[panel$id]
panel$post_treat <- (panel$g > 0) & (panel$t >= panel$g)
panel$untreated_obs <- !panel$post_treat

alpha_i <- rnorm(n_states, mean = 5, sd = 0.5)
lambda_t <- rnorm(n_months, mean = 0, sd = 0.3)
panel$y <- alpha_i[panel$id] + lambda_t[panel$t] + rnorm(nrow(panel), sd = 0.4)

# Fit FE
base_fe <- panel %>% filter(untreated_obs, is.finite(y))
fe_fit <- fixest::feols(y ~ 1 | id + t, data = base_fe, notes = FALSE, warn = FALSE)
panel$yhat <- as.numeric(predict(fe_fit, newdata = panel))
resid_pool <- as.numeric(residuals(fe_fit))

cat("Panel created: n_states=", n_states, ", n_obs=", nrow(panel), "\n\n")

# Run 10 simulations with est_method="ipw" and capture ALL errors
n_sims <- 10
errors <- list()
tracebacks <- list()

cat("Running", n_sims, "simulations with est_method=\"ipw\"...\n\n")

for (i in 1:n_sims) {
  set.seed(1000 + i)
  e_draw <- sample(resid_pool, size = nrow(panel), replace = TRUE)
  y_sim <- panel$yhat + e_draw

  dat <- data.frame(id = panel$id, t = panel$t, g = panel$g, y = y_sim)

  result <- tryCatch({
    # Enable traceback capture
    withCallingHandlers({
      est <- did::att_gt(
        yname = "y", tname = "t", idname = "id", gname = "g",
        xformla = ~ 1, data = dat, panel = TRUE,
        control_group = "nevertreated",
        allow_unbalanced_panel = TRUE,
        est_method = "ipw",
        faster_mode = FALSE,
        bstrap = FALSE,  # Faster for debugging
        cband = FALSE,
        clustervars = "id"
      )
      "SUCCESS"
    }, error = function(e) {
      # Capture traceback
      tb <- sys.calls()
      tracebacks[[i]] <<- tb
      e
    })
  }, error = function(e) {
    list(
      message = conditionMessage(e),
      call = deparse(conditionCall(e)),
      class = class(e)
    )
  })

  if (is.list(result) && !is.null(result$message)) {
    errors[[i]] <- result
    cat("  Sim", i, ": FAILED -", result$message, "\n")
  } else {
    cat("  Sim", i, ": SUCCESS\n")
  }
}

cat("\n")
cat("================================================================================\n")
cat("ERROR FREQUENCY TABLE\n")
cat("================================================================================\n\n")

if (length(errors) > 0) {
  # Extract error messages
  error_msgs <- sapply(errors, function(e) e$message)

  # Count unique errors
  unique_errors <- unique(error_msgs)
  error_counts <- sapply(unique_errors, function(msg) sum(error_msgs == msg))

  cat("Total simulations:", n_sims, "\n")
  cat("Failed simulations:", length(errors), "\n")
  cat("Success rate:", sprintf("%.1f%%", 100 * (n_sims - length(errors)) / n_sims), "\n\n")

  cat("Unique error types:", length(unique_errors), "\n\n")

  for (i in seq_along(unique_errors)) {
    cat("Error type", i, "(", error_counts[i], "occurrences):\n")
    cat("  Message:", unique_errors[i], "\n\n")
  }

  cat("================================================================================\n")
  cat("FULL EXAMPLE ERROR (First Failure)\n")
  cat("================================================================================\n\n")

  first_error <- errors[[1]]
  cat("Error message:\n")
  cat("  ", first_error$message, "\n\n")

  cat("Error call:\n")
  cat("  ", first_error$call, "\n\n")

  cat("Error class:\n")
  cat("  ", paste(first_error$class, collapse = ", "), "\n\n")

  # Show traceback if captured
  if (length(tracebacks) > 0 && !is.null(tracebacks[[1]])) {
    cat("Call stack (last 15 calls):\n")
    tb <- tracebacks[[1]]
    n_calls <- length(tb)
    start_idx <- max(1, n_calls - 14)

    for (j in start_idx:n_calls) {
      call_text <- deparse(tb[[j]], width.cutoff = 100)[1]
      cat(sprintf("  %2d: %s\n", j - start_idx + 1, call_text))
    }
  }

} else {
  cat("No errors occurred - all simulations succeeded!\n")
}

cat("\n")
cat("================================================================================\n")
cat("DIAGNOSIS COMPLETE\n")
cat("================================================================================\n")
