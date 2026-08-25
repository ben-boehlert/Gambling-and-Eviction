#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# Cohort-specific ramp-up lags: months from online legalization until the
# market is predicted to "really get going," defined as the predicted exposure
# index first crossing a threshold share of long-run market intensity.
#
# Why predicted, not realized: a state's own maturation date is a
# post-treatment outcome — assigning treatment timing from it conditions on
# post-treatment behavior. Here each state's lag comes from the exposure curve
# fit WITHOUT that state (leave-one-out), so the lag is a function of the
# state's legalization cohort only, determined by OTHER states' trajectories.
#
# Inputs (produced by analysis/exploratory/exposure_curve_model.R):
#   data/processed/gambling_exposure_index.csv    per-state LOO index
#   output/exposure_curve/cohort_exposure_curves.csv  full-model cohort curves
# Output:
#   data/processed/cohort_ramp_lags.csv   per-state lags + effective dates
#   output/exposure_curve/ramp_lags_report.txt
#
# Usage: Rscript analysis/exploratory/cohort_ramp_lags.R
# ─────────────────────────────────────────────────────────────────────────────

library(tidyverse)

theme_set(theme_minimal())

THRESHOLDS <- c(0.50, 0.75)
OUT_DIR    <- "output/exposure_curve"

idx <- read_csv("data/processed/gambling_exposure_index.csv", show_col_types = FALSE)
grid <- read_csv(file.path(OUT_DIR, "cohort_exposure_curves.csv"), show_col_types = FALSE)

# First event month at which the index reaches `thr`. Curves for late cohorts
# spike above 1 and settle back; the FIRST crossing is the economically
# relevant one ("market has arrived"), so which.max on the logical works.
first_cross <- function(a, index, thr) {
  hit <- which(index >= thr)
  if (!length(hit)) return(NA_integer_)
  a[min(hit)]
}

# ── Per-state lags from the leave-one-out curve ──────────────────────────────
state_lags <- idx %>%
  group_by(State, cohort, online_start_date) %>%
  arrange(event_month, .by_group = TRUE) %>%
  summarise(
    lag50          = first_cross(event_month, exposure_loo, 0.50),
    lag75          = first_cross(event_month, exposure_loo, 0.75),
    lag50_anchored = first_cross(event_month, exposure_loo_anchored, 0.50),
    lag75_anchored = first_cross(event_month, exposure_loo_anchored, 0.75),
    a_max          = max(event_month),
    .groups = "drop"
  ) %>%
  mutate(
    ramp50_date = online_start_date %m+% months(lag50),
    ramp75_date = online_start_date %m+% months(lag75),
    # NA lag75 means the LOO curve never reaches 75% within this state's
    # observed window — the state legalized too recently to have been
    # PREDICTED mature, i.e. genuinely right-censored, not endogenous.
    censored75  = is.na(lag75)
  )

# ── Cohort-level lags from the full-model curve (the "set amount of time") ───
cohort_lags <- grid %>%
  group_by(cohort) %>%
  arrange(a, .by_group = TRUE) %>%
  summarise(
    n_states       = first(n_states),
    lag50          = first_cross(a, index, 0.50),
    lag75          = first_cross(a, index, 0.75),
    lag50_anchored = first_cross(a, index_anchored, 0.50),
    lag75_anchored = first_cross(a, index_anchored, 0.75),
    .groups = "drop"
  )

# Smooth-in-cohort alternative: because cohort enters the model linearly, the
# lag is a smooth function of cohort year; fit lag ~ cohort to offer a single
# formula usable for any legalization date (incl. future states).
lin50 <- lm(lag50 ~ cohort, data = cohort_lags)
lin75 <- lm(lag75 ~ cohort, data = cohort_lags)

write_csv(state_lags, "data/processed/cohort_ramp_lags.csv")

sink(file.path(OUT_DIR, "ramp_lags_report.txt"), split = TRUE)

cat("=== COHORT RAMP LAGS: months from online launch to X% of long-run intensity ===\n")
cat("From the full-model cohort curve (long-run = month 48).\n\n")
print(as.data.frame(cohort_lags), row.names = FALSE)

cat(sprintf("\nLinear-in-cohort approximation:\n"))
cat(sprintf("  lag50 = %.1f - %.1f x (cohort year - 2021)   [R2 = %.2f]\n",
            predict(lin50, tibble(cohort = 2021)), -coef(lin50)[2], summary(lin50)$r.squared))
cat(sprintf("  lag75 = %.1f - %.1f x (cohort year - 2021)   [R2 = %.2f]\n",
            predict(lin75, tibble(cohort = 2021)), -coef(lin75)[2], summary(lin75)$r.squared))

cat("\n=== PER-STATE LAGS (leave-one-out; each state's lag excludes its own data) ===\n\n")
state_lags %>%
  select(State, cohort, lag50, lag75, lag50_anchored, lag75_anchored,
         ramp75_date, censored75) %>%
  arrange(cohort, State) %>%
  as.data.frame() %>% print(row.names = FALSE)

cat("\n=== SANITY CHECK: predicted (LOO) vs realized maturity ===\n")
realized <- read_csv("output/market_maturation/per_state_maturity.csv",
                     show_col_types = FALSE) %>%
  select(State, mo_realized = mo_from_online)
chk <- state_lags %>% inner_join(realized, by = "State") %>%
  filter(!is.na(lag75), !is.na(mo_realized))
cat(sprintf("  cor(lag75, realized months-to-maturity) = %.2f  (n = %d)\n",
            cor(chk$lag75, chk$mo_realized), nrow(chk)))
cat("  (High correlation expected — both are driven by cohort — but the LOO\n")
cat("   lag never uses the state's own handle, so it stays exogenous.)\n")

sink()

# ── Figure ───────────────────────────────────────────────────────────────────
p <- cohort_lags %>%
  pivot_longer(c(lag50, lag75), names_to = "threshold", values_to = "lag") %>%
  mutate(threshold = recode(threshold, lag50 = "50% of long-run", lag75 = "75% of long-run")) %>%
  ggplot(aes(cohort, lag, colour = threshold)) +
  geom_line() + geom_point(size = 2) +
  scale_x_continuous(breaks = 2018:2025) +
  labs(x = "Online legalization cohort", y = "Months from launch to threshold",
       colour = NULL,
       subtitle = "Cohort-specific ramp lags from the smooth exposure model (full sample)")
ggsave(file.path(OUT_DIR, "cohort_ramp_lags.png"), p, width = 7.5, height = 4.5, dpi = 150)

cat("\nWrote data/processed/cohort_ramp_lags.csv and diagnostics to output/exposure_curve/\n")
