################################################################################
# analysis/power/run_ddd_power.R
#
# Blinded power analysis of the poverty triple-difference (DDD) design.
# Usage:  Rscript analysis/power/run_ddd_power.R [n_reps] [tag]
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr); library(ggplot2); library(purrr)
})
source("R/power/ddd_power.R")
theme_set(theme_minimal())

args   <- commandArgs(trailingOnly = TRUE)
n_reps <- if (length(args) >= 1) as.integer(args[1]) else 400L
tag    <- if (length(args) >= 2) args[2] else "main"
OUT    <- file.path("output", "ddd_power", tag)
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

cfg    <- read_power_config("config/power_primary.yml")
DELTAS <- c(0, 0.025, 0.05, 0.075, 0.10, 0.15, 0.20)

log_lines <- c(sprintf("DDD power run | tag=%s | n_reps=%d | %s", tag, n_reps, Sys.time()))
say <- function(...) { m <- sprintf(...); message(m); log_lines <<- c(log_lines, m) }

all_raw <- list(); all_sum <- list(); shares <- list()

for (cv in c("drop", "keep")) {
  say("\n=== COVID window: %s ===", cv)
  sk <- build_ddd_skeleton(covid = cv, h_rule = "within_state", config = cfg)
  hs <- mean(sk$H)
  shares[[cv]] <- hs
  say("skeleton: %d rows | %d counties | %d states | H=1 share %.3f | months %s..%s",
      nrow(sk), n_distinct(sk$unit_id), n_distinct(sk$state_abb), hs,
      format(min(sk$month_date)), format(max(sk$month_date)))

  # Per-arm checkpoint: an arm that finished is written immediately and is
  # reused on restart, so a kill/timeout never discards completed work.
  ckpt <- file.path(OUT, sprintf("checkpoint_raw_%s.csv", cv))
  if (file.exists(ckpt)) {
    raw <- read_csv(ckpt, show_col_types = FALSE)
    say("RESUMED arm '%s' from checkpoint (%d reps) - not re-run.", cv,
        n_distinct(raw$rep))
  } else {
    t0  <- Sys.time()
    raw <- run_ddd_power(sk, deltas = DELTAS, n_reps = n_reps)
    say("elapsed: %.1f min | feasible reps: %d/%d",
        as.numeric(difftime(Sys.time(), t0, units = "mins")),
        n_distinct(raw$rep[raw$feasible]), n_reps)
    write_csv(raw, ckpt)
    say("checkpointed arm '%s' -> %s", cv, ckpt)
  }

  sm <- summarize_ddd(raw, high_share = hs) %>% mutate(covid = cv, .before = 1)
  all_raw[[cv]] <- raw %>% mutate(covid = cv, .before = 1)
  all_sum[[cv]] <- sm
}

raw_all <- bind_rows(all_raw); sum_all <- bind_rows(all_sum)
write_csv(raw_all, file.path(OUT, "ddd_power_raw.csv"))
write_csv(sum_all, file.path(OUT, "ddd_power_summary.csv"))

# ---- Size gate + MDE ---------------------------------------------------------
size_tbl <- sum_all %>% filter(delta == 0, dgp == "differential") %>%
  select(covid, estimator, n_conv, mean_est, sd_est, mean_se, se_sd, rej_rate)

# Interpolated MDE-80 on each estimator's own estimand.
mde <- sum_all %>%
  filter((estimator == "ddd" & dgp == "differential") |
         (estimator == "did_twfe" & dgp == "uniform")) %>%
  group_by(covid, estimator) %>%
  summarise(mde80 = {
    p <- rej_rate; x <- delta
    if (max(p) < 0.80) NA_real_ else stats::approx(p, x, xout = 0.80, ties = "ordered")$y
  }, max_power = max(rej_rate), .groups = "drop")

write_csv(size_tbl, file.path(OUT, "size_gate.csv"))
write_csv(mde,      file.path(OUT, "mde.csv"))

say("\n--- SIZE GATE (delta = 0, nominal 5%%) ---")
log_lines <- c(log_lines, capture.output(print(as.data.frame(size_tbl), row.names = FALSE, digits = 3)))
say("\n--- MDE-80 ---")
log_lines <- c(log_lines, capture.output(print(as.data.frame(mde), row.names = FALSE, digits = 3)))
say("\n--- PLACEBO: uniform effect must not register as DDD ---")
log_lines <- c(log_lines, capture.output(print(as.data.frame(
  sum_all %>% filter(dgp == "uniform", estimator == "ddd") %>%
    select(covid, delta, mean_est, rej_rate)), row.names = FALSE, digits = 3)))

# ---- Plot --------------------------------------------------------------------
pd <- sum_all %>%
  filter((estimator == "ddd" & dgp == "differential") |
         (estimator == "did_twfe" & dgp == "uniform")) %>%
  mutate(spec = ifelse(estimator == "ddd",
                       "DDD: high-low differential\n(county + state x month + H x month FE)",
                       "TWFE DiD: average effect\n(county + month FE)"),
         covid_lab = ifelse(covid == "drop", "COVID window dropped", "COVID window kept"))

p <- ggplot(pd, aes(delta, rej_rate, colour = spec, shape = spec)) +
  geom_hline(yintercept = 0.80, linetype = "dashed", colour = "grey40") +
  geom_hline(yintercept = 0.05, linetype = "dotted", colour = "grey60") +
  geom_line(linewidth = 0.7) + geom_point(size = 2) +
  facet_wrap(~covid_lab) +
  scale_x_continuous(labels = scales::percent_format(accuracy = 1)) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0, 1)) +
  labs(x = "True effect on own estimand (log points)", y = "Rejection rate",
       colour = NULL, shape = NULL) +
  theme(legend.position = "bottom")
ggsave(file.path(OUT, "ddd_power_curves.png"), p, width = 10, height = 5, dpi = 200)

writeLines(log_lines, file.path(OUT, "run_log.txt"))
say("\nWrote outputs to %s", OUT)
