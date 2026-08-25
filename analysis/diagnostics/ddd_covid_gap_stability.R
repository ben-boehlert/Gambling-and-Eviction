################################################################################
# analysis/diagnostics/ddd_covid_gap_stability.R
#
# Blinded diagnostic for the DDD design's identifying assumption.
#
# The DDD absorbs every state x month shock, so COVID is harmless to it PROVIDED
# the pandemic did not move the within-state high-poverty / low-poverty eviction
# GAP differently across states. This script measures, using UNTREATED county-
# months only (blindness protocol S2):
#
#   (1) how much outcome variance the state x month FE absorbs (the DDD's gain);
#   (2) whether the within-state high-low gap is more volatile during COVID than
#       outside it (the DDD's exposure).
#
# Usage: Rscript analysis/diagnostics/ddd_covid_gap_stability.R
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(ggplot2); library(lubridate); library(tidyr)
})
source("R/power/ddd_power.R")
theme_set(theme_minimal())

OUT <- "output/ddd_power/covid_gap_diagnostic"
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

cfg <- read_power_config("config/power_primary.yml")
sk  <- build_ddd_skeleton(covid = "keep", h_rule = "within_state", config = cfg)

covid_win <- cfg$covid_drop
cw_start  <- as.Date(covid_win[[1]]); cw_end <- as.Date(covid_win[[2]])
sk <- sk %>% mutate(era = ifelse(month_date >= cw_start & month_date <= cw_end,
                                 "COVID window", "Non-COVID"))

# ---- State-month means by poverty group, and the within-state gap ------------
gap <- sk %>%
  group_by(state_abb, month_date, era, H) %>%
  summarise(m = mean(y_log1p, na.rm = TRUE), n = n(), .groups = "drop") %>%
  pivot_wider(names_from = H, values_from = c(m, n), names_prefix = "H") %>%
  filter(!is.na(m_H0), !is.na(m_H1)) %>%
  mutate(state_level = (m_H0 + m_H1) / 2, gap = m_H1 - m_H0)

# De-mean within state so we measure MOVEMENT, not level differences.
gap <- gap %>% group_by(state_abb) %>%
  mutate(across(c(state_level, gap), ~ .x - mean(.x, na.rm = TRUE),
                .names = "{.col}_dm")) %>% ungroup()

# ---- (1) Variance absorbed by state x month FE ------------------------------
var_tbl <- gap %>% group_by(era) %>%
  summarise(n_state_months = n(),
            sd_state_level = sd(state_level_dm, na.rm = TRUE),
            sd_gap         = sd(gap_dm, na.rm = TRUE),
            ratio_gap_over_state = sd_gap / sd_state_level, .groups = "drop")

# Month-to-month innovations: what a DiD vs a DDD each has to fight.
innov <- gap %>% arrange(state_abb, month_date) %>% group_by(state_abb) %>%
  mutate(d_state = state_level - lag(state_level), d_gap = gap - lag(gap)) %>%
  ungroup() %>% filter(!is.na(d_state)) %>%
  group_by(era) %>%
  summarise(sd_d_state_level = sd(d_state, na.rm = TRUE),
            sd_d_gap = sd(d_gap, na.rm = TRUE),
            ratio = sd_d_gap / sd_d_state_level, .groups = "drop")

# ---- (2) Cross-state dispersion of the gap, month by month ------------------
disp <- gap %>% group_by(month_date, era) %>%
  summarise(n_states = n(),
            sd_across_states_gap   = sd(gap_dm, na.rm = TRUE),
            sd_across_states_level = sd(state_level_dm, na.rm = TRUE),
            .groups = "drop") %>% filter(n_states >= 10)

disp_era <- disp %>% group_by(era) %>%
  summarise(mean_sd_gap = mean(sd_across_states_gap),
            mean_sd_level = mean(sd_across_states_level),
            .groups = "drop") %>%
  mutate(gap_inflation_vs_level = mean_sd_gap / mean_sd_level)

write_csv(var_tbl,  file.path(OUT, "variance_by_era.csv"))
write_csv(innov,    file.path(OUT, "innovations_by_era.csv"))
write_csv(disp,     file.path(OUT, "cross_state_dispersion_by_month.csv"))
write_csv(disp_era, file.path(OUT, "cross_state_dispersion_by_era.csv"))

cat("\n=== Within-state variation, untreated county-months only ===\n")
print(as.data.frame(var_tbl), row.names = FALSE, digits = 3)
cat("\n=== Month-to-month innovations (what each design fights) ===\n")
print(as.data.frame(innov), row.names = FALSE, digits = 3)
cat("\n=== Cross-state dispersion, by era ===\n")
print(as.data.frame(disp_era), row.names = FALSE, digits = 3)

# ---- Plot: does the high-low gap blow up during COVID? ----------------------
p <- disp %>%
  pivot_longer(c(sd_across_states_gap, sd_across_states_level),
               names_to = "series", values_to = "sd") %>%
  mutate(series = recode(series,
      sd_across_states_gap   = "High-low GAP (what DDD uses)",
      sd_across_states_level = "State level (what state x month FE absorbs)")) %>%
  ggplot(aes(month_date, sd, colour = series)) +
  annotate("rect", xmin = cw_start, xmax = cw_end, ymin = -Inf, ymax = Inf,
           alpha = 0.12, fill = "grey40") +
  geom_line(linewidth = 0.6) +
  labs(x = NULL, y = "SD across states (log points)", colour = NULL,
       subtitle = "Shaded band = COVID window. Untreated county-months only.") +
  theme(legend.position = "bottom")
ggsave(file.path(OUT, "gap_vs_level_volatility.png"), p, width = 9, height = 4.5, dpi = 200)

cat("\nWrote to", OUT, "\n")
