################################################################################
# analysis/power/run_ddd_power_wild.R  (2026-09-14)
#
# Blinded power analysis of the poverty triple-difference WITH a wild cluster
# bootstrap arm, and with H assigned by a rule that has been balance-checked
# (see analysis/diagnostics/ddd_h_rule_balance.R).
#
# Usage:
#   Rscript analysis/power/run_ddd_power_wild.R [n_reps] [tag] [h_rule] [weight_by]
# Defaults: 500 poverty_resid none
#
# Writes, per tag:
#   checkpoint_raw_{drop,keep}.csv   per-arm resume points
#   ddd_power_raw.csv                every rep x delta x dgp x estimator
#   ddd_power_summary.csv            operating characteristics
#   size_gate.csv                    delta = 0 rows, analytic AND wild
#   mde.csv                          80%-power crossing on the wild arm
#   h_rule_balance.csv               what the H split actually selected
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr); library(purrr)
})
source("R/power/ddd_power.R")

# Pin fixest to a single thread BEFORE anything touches it: the OpenMP pool is
# initialised on first use, and a forked mclapply child that inherits an
# already-multithreaded pool segfaults on macOS.
fixest::setFixest_nthreads(1L)

args      <- commandArgs(trailingOnly = TRUE)
n_reps    <- if (length(args) >= 1) as.integer(args[1]) else 500L
tag       <- if (length(args) >= 2) args[2] else "wild"
h_rule    <- if (length(args) >= 3) args[3] else "poverty_resid"
weight_by <- if (length(args) >= 4) args[4] else "none"

OUT <- file.path("output", "ddd_power", tag)
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

cfg    <- read_power_config("config/power_primary.yml")
DELTAS <- c(0, 0.025, 0.05, 0.075, 0.10, 0.15, 0.20)
B      <- 999L

log_lines <- c(sprintf("DDD wild power run | tag=%s | n_reps=%d | h_rule=%s | weight_by=%s | B=%d | %s",
                       tag, n_reps, h_rule, weight_by, B, Sys.time()))
say <- function(...) { m <- sprintf(...); message(m); log_lines <<- c(log_lines, m) }

all_raw <- list(); all_sum <- list(); shares <- list(); bal <- list()

for (cv in c("drop", "keep")) {
  say("\n=== COVID window: %s ===", cv)
  sk <- build_ddd_skeleton(covid = cv, h_rule = h_rule, config = cfg)
  hs <- mean(sk$H)
  shares[[cv]] <- hs
  bal[[cv]] <- ddd_h_balance(sk) %>% mutate(covid = cv, .before = 1)

  say("skeleton: %d rows | %d counties | %d states | H=1 share %.3f | months %s..%s",
      nrow(sk), n_distinct(sk$unit_id), n_distinct(sk$state_abb), hs,
      format(min(sk$month_date)), format(max(sk$month_date)))
  say("balance: renter_share_hi %.3f | poverty_gap %.2f | size_ratio %.2f | evrate_ratio %.2f",
      bal[[cv]]$renter_share_hi, bal[[cv]]$poverty_gap,
      bal[[cv]]$size_ratio, bal[[cv]]$evrate_ratio)

  ckpt <- file.path(OUT, sprintf("checkpoint_raw_%s.csv", cv))
  if (file.exists(ckpt)) {
    raw <- read_csv(ckpt, show_col_types = FALSE)
    say("RESUMED arm '%s' from checkpoint (%d reps) - not re-run.", cv, n_distinct(raw$rep))
  } else {
    t0  <- Sys.time()
    raw <- run_ddd_power(sk, deltas = DELTAS, n_reps = n_reps,
                         wild = TRUE, B = B, weight_by = weight_by)
    say("elapsed: %.1f min | feasible reps: %d/%d",
        as.numeric(difftime(Sys.time(), t0, units = "mins")),
        n_distinct(raw$rep[raw$feasible]), n_reps)
    write_csv(raw, ckpt)
  }

  all_sum[[cv]] <- summarize_ddd(raw, high_share = hs) %>% mutate(covid = cv, .before = 1)
  all_raw[[cv]] <- raw %>% mutate(covid = cv, .before = 1)
}

raw_all <- bind_rows(all_raw); sum_all <- bind_rows(all_sum)
write_csv(raw_all, file.path(OUT, "ddd_power_raw.csv"))
write_csv(bind_rows(bal), file.path(OUT, "h_rule_balance.csv"))

# ---- RECENTERING ------------------------------------------------------------
# Every arm in this project carries a positive pseudo-placement bias (FINDINGS
# section 2), so testing against 0 flatters both size and MDE. The pre-registered
# number is rejection of the cell family's OWN delta = 0 mean, read off the
# stored wild CI (translation-equivariance), exactly as summarize_oc() does for
# the LP-DiD arms.
null_center <- raw_all %>%
  filter(.data$feasible, .data$delta == 0, .data$dgp == "differential") %>%
  group_by(covid, estimator) %>%
  summarise(null_center = mean(.data$est, na.rm = TRUE), .groups = "drop")

rc <- raw_all %>%
  filter(.data$feasible) %>%
  left_join(null_center, by = c("covid", "estimator")) %>%
  mutate(reject_rc = as.integer(.data$null_center < .data$ci_lo |
                                .data$null_center > .data$ci_hi)) %>%
  group_by(covid, dgp, delta, estimator) %>%
  summarise(null_center   = dplyr::first(.data$null_center),
            rej_rc        = mean(.data$reject_rc, na.rm = TRUE),
            n_rc          = sum(!is.na(.data$reject_rc)),
            .groups = "drop")

sum_all <- sum_all %>%
  left_join(rc, by = c("covid", "dgp", "delta", "estimator"))
write_csv(sum_all, file.path(OUT, "ddd_power_summary.csv"))

# ---- size gate: delta = 0, all three inference arms -------------------------
gate <- sum_all %>%
  filter(.data$delta == 0, .data$dgp == "differential") %>%
  select(covid, estimator, n_conv, mean_est, null_center, sd_est, mean_se, se_sd,
         rej_analytic = rej_rate, rej_wild = rej_rate_wild, rej_wild_rc = rej_rc)
write_csv(gate, file.path(OUT, "size_gate.csv"))

# ---- MDE: first delta whose wild power >= 0.80, linearly interpolated -------
mde_of <- function(dl, pw) {
  ok <- is.finite(dl) & is.finite(pw)
  dl <- dl[ok]; pw <- pw[ok]
  o <- order(dl); dl <- dl[o]; pw <- pw[o]
  i <- which(pw >= 0.80)[1L]
  if (is.na(i)) return(NA_real_)
  if (i == 1L) return(dl[1L])
  dl[i - 1L] + (0.80 - pw[i - 1L]) * (dl[i] - dl[i - 1L]) / (pw[i] - pw[i - 1L])
}
mde <- sum_all %>%
  filter(.data$dgp == "differential") %>%
  group_by(covid, estimator) %>%
  summarise(mde80_wild_rc  = mde_of(.data$delta, .data$rej_rc),
            mde80_wild_raw = mde_of(.data$delta, .data$rej_rate_wild),
            mde80_analytic = mde_of(.data$delta, .data$rej_rate),
            max_power_rc   = max(.data$rej_rc, na.rm = TRUE),
            .groups = "drop")
write_csv(mde, file.path(OUT, "mde.csv"))

# ---- blindness-safe power against a UNIFORM effect --------------------------
# The DDD estimand is 0 under a uniform effect by construction; this is the
# column that says how much of the total ATT the design is blind to.
unif <- sum_all %>% filter(.data$dgp == "uniform") %>%
  select(covid, estimator, delta, mean_est, rej_analytic = rej_rate,
         rej_wild = rej_rate_wild, rej_wild_rc = rej_rc)
write_csv(unif, file.path(OUT, "uniform_blindness.csv"))

say("\n--- SIZE GATE (delta = 0) ---")
say("%s", paste(capture.output(print(as.data.frame(gate), row.names = FALSE, digits = 3)), collapse = "\n"))
say("%s", "\n--- MDE (80% power, differential DGP) ---")
say("%s", paste(capture.output(print(as.data.frame(mde), row.names = FALSE, digits = 3)), collapse = "\n"))

writeLines(log_lines, file.path(OUT, "run_log.txt"))
message("\nwrote ", OUT)
