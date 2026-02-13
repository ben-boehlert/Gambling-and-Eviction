###############################################################################
# Retail vs Online Legalization: How much did gambling increase?
#
# Uses LSR handle/revenue data + legalization dates to compare gambling volumes
# after retail-only vs online legalization.
###############################################################################

library(tidyverse)
library(lubridate)

# ── Load data ────────────────────────────────────────────────────────────────

handle <- read_csv("data/raw/lsr_sports_betting_handle_revenue_by_state_month.csv",
                   show_col_types = FALSE)

dates <- read_csv("data/raw/sports_gambling_legalization_dates.csv",
                  show_col_types = FALSE)

# ── State name → abbreviation crosswalk ──────────────────────────────────────

state_xwalk <- tibble(
  state_name = c(state.name, "District of Columbia"),
  state_abb  = c(state.abb,  "DC")
)

handle <- handle %>%
  left_join(state_xwalk, by = c("State" = "state_name")) %>%
  mutate(month_date = as.Date(month_date))

dates <- dates %>%
  mutate(
    retail_start_date = as.Date(retail_start_date),
    online_start_date = as.Date(online_start_date)
  )

# ── Join legalization dates to handle data ───────────────────────────────────

# Match on state name since handle uses full names, dates uses full names
df <- handle %>%
  left_join(dates %>% select(state, retail_start_date, online_start_date,
                             has_online, has_retail),
            by = c("State" = "state")) %>%
  filter(!is.na(state_abb))  # drop any unmatched

cat("States in handle data:", n_distinct(df$State), "\n")
cat("Date range:", as.character(min(df$month_date)), "to",
    as.character(max(df$month_date)), "\n\n")

# ── Classify each state-month by legalization regime ─────────────────────────

df <- df %>%
  mutate(
    has_retail_active = !is.na(retail_start_date) & month_date >= retail_start_date,
    has_online_active = !is.na(online_start_date) & month_date >= online_start_date,
    regime = case_when(
      has_online_active & has_retail_active ~ "Both",
      has_online_active & !has_retail_active ~ "Online only",
      !has_online_active & has_retail_active ~ "Retail only",
      TRUE ~ "Pre-legalization"
    )
  )

cat("── Observations by regime ──\n")
df %>% count(regime) %>% print()
cat("\n")

# ── Summary: average monthly handle by regime ────────────────────────────────

regime_summary <- df %>%
  group_by(regime) %>%
  summarise(
    n_state_months = n(),
    n_states       = n_distinct(State),
    mean_handle    = mean(Handle, na.rm = TRUE),
    median_handle  = median(Handle, na.rm = TRUE),
    mean_revenue   = mean(Revenue, na.rm = TRUE),
    mean_hold_pct  = mean(Hold, na.rm = TRUE) * 100,
    .groups = "drop"
  ) %>%
  arrange(desc(mean_handle))

cat("── Average monthly handle & revenue by regime ──\n")
regime_summary %>%
  mutate(across(c(mean_handle, median_handle, mean_revenue),
                ~ scales::dollar(., accuracy = 1))) %>%
  print(n = Inf, width = Inf)
cat("\n")

# ── Focus: states that had retail BEFORE online ──────────────────────────────
# These states let us see the "online bump" — how much handle increased
# when online was added on top of existing retail.

staggered <- dates %>%
  filter(!is.na(retail_start_date), !is.na(online_start_date),
         online_start_date > retail_start_date) %>%
  select(state, retail_start_date, online_start_date) %>%
  mutate(gap_months = interval(retail_start_date, online_start_date) %/% months(1))

cat("── States with retail BEFORE online (staggered adoption) ──\n")
staggered %>%
  arrange(retail_start_date) %>%
  print(n = Inf)
cat("\n")

# For these states, compute average monthly handle in retail-only vs both periods
staggered_handle <- df %>%
  inner_join(staggered, by = c("State" = "state")) %>%
  filter(regime %in% c("Retail only", "Both")) %>%
  group_by(State, regime) %>%
  summarise(
    n_months      = n(),
    mean_handle   = mean(Handle, na.rm = TRUE),
    mean_revenue  = mean(Revenue, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  pivot_wider(
    names_from = regime,
    values_from = c(n_months, mean_handle, mean_revenue),
    names_glue = "{.value}_{regime}"
  ) %>%
  rename_with(~ str_replace_all(., " ", "_")) %>%
  mutate(
    handle_ratio     = mean_handle_Both / mean_handle_Retail_only,
    revenue_ratio    = mean_revenue_Both / mean_revenue_Retail_only,
    handle_increase  = mean_handle_Both - mean_handle_Retail_only
  ) %>%
  arrange(desc(handle_ratio))

cat("── Handle growth: retail-only → retail+online ──\n")
staggered_handle %>%
  mutate(
    across(starts_with("mean_handle"), ~ scales::dollar(., accuracy = 1)),
    handle_increase = scales::dollar(handle_increase, accuracy = 1),
    handle_ratio = sprintf("%.1fx", handle_ratio),
    revenue_ratio = sprintf("%.1fx", revenue_ratio)
  ) %>%
  select(State, starts_with("n_months"), starts_with("mean_handle"),
         handle_increase, handle_ratio) %>%
  print(n = Inf, width = Inf)
cat("\n")

# Overall multiplier
overall <- staggered_handle %>%
  summarise(
    mean_ratio    = mean(handle_ratio, na.rm = TRUE),
    median_ratio  = median(handle_ratio, na.rm = TRUE),
    weighted_ratio = sum(mean_handle_Both * n_months_Both, na.rm = TRUE) /
                     sum(mean_handle_Retail_only * n_months_Retail_only, na.rm = TRUE)
  )
cat(sprintf("Average multiplier (online added to retail): %.1fx\n", overall$mean_ratio))
cat(sprintf("Median multiplier: %.1fx\n", overall$median_ratio))
cat(sprintf("Weighted multiplier: %.1fx\n\n", overall$weighted_ratio))

# ── Event study: months relative to online launch for staggered states ───────

event_df <- df %>%
  filter(State %in% staggered$state) %>%
  mutate(
    months_since_online = interval(online_start_date, month_date) %/% months(1)
  ) %>%
  filter(months_since_online >= -24, months_since_online <= 24)

event_avg <- event_df %>%
  group_by(months_since_online) %>%
  summarise(
    mean_handle  = mean(Handle, na.rm = TRUE),
    mean_revenue = mean(Revenue, na.rm = TRUE),
    n_states     = n_distinct(State),
    .groups = "drop"
  )

# Normalize to mean of pre-online period (months -12 to -1)
baseline_handle <- event_avg %>%
  filter(months_since_online >= -12, months_since_online < 0) %>%
  pull(mean_handle) %>%
  mean()

event_avg <- event_avg %>%
  mutate(handle_index = mean_handle / baseline_handle * 100)

cat("── Event study: handle indexed to 100 at online launch ──\n")
cat(sprintf("Baseline (12 months pre-online): %s/month\n",
            scales::dollar(baseline_handle, accuracy = 1)))
cat(sprintf("12 months post-online: %s/month (%.0f%% increase)\n",
            scales::dollar(
              event_avg %>% filter(months_since_online >= 1,
                                   months_since_online <= 12) %>%
                pull(mean_handle) %>% mean(),
              accuracy = 1),
            event_avg %>% filter(months_since_online >= 1,
                                 months_since_online <= 12) %>%
              pull(handle_index) %>% mean() - 100))
cat("\n")

# ── Plot: event study around online legalization ─────────────────────────────

dir.create("output/retail_vs_online", showWarnings = FALSE, recursive = TRUE)

p_event <- ggplot(event_avg, aes(x = months_since_online, y = handle_index)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "red", linewidth = 0.8) +
  geom_line(linewidth = 1, color = "steelblue") +
  geom_point(size = 2, color = "steelblue") +
  annotate("text", x = 0.5, y = max(event_avg$handle_index) * 0.95,
           label = "Online launch", hjust = 0, color = "red", size = 3.5) +
  labs(
    title = "Sports Betting Handle Around Online Legalization",
    subtitle = sprintf("States with retail before online (n = %d) | Index: 100 = avg of 12 months pre-online",
                       n_distinct(event_df$State)),
    x = "Months relative to online launch",
    y = "Handle (indexed, pre-online avg = 100)"
  ) +
  theme_minimal(base_size = 13) +
  theme(plot.title = element_text(face = "bold"))

ggsave("output/retail_vs_online/event_study_online_launch.png",
       p_event, width = 10, height = 6, dpi = 150)
cat("Saved: output/retail_vs_online/event_study_online_launch.png\n")

# ── Plot: handle by regime (boxplot) ─────────────────────────────────────────

p_box <- df %>%
  filter(regime != "Pre-legalization") %>%
  mutate(regime = factor(regime, levels = c("Retail only", "Online only", "Both"))) %>%
  ggplot(aes(x = regime, y = Handle / 1e6, fill = regime)) +
  geom_boxplot(outlier.alpha = 0.3) +
  scale_fill_manual(values = c("Retail only" = "#e74c3c",
                                "Online only" = "#3498db",
                                "Both" = "#2ecc71")) +
  scale_y_continuous(labels = scales::dollar_format(suffix = "M")) +
  labs(
    title = "Monthly Sports Betting Handle by Legalization Regime",
    x = NULL, y = "Monthly handle"
  ) +
  theme_minimal(base_size = 13) +
  theme(legend.position = "none",
        plot.title = element_text(face = "bold"))

ggsave("output/retail_vs_online/handle_by_regime_boxplot.png",
       p_box, width = 8, height = 6, dpi = 150)
cat("Saved: output/retail_vs_online/handle_by_regime_boxplot.png\n")

# ── Plot: state-level before/after for staggered states ──────────────────────

p_state <- staggered_handle %>%
  select(State, Retail_only = mean_handle_Retail_only, Both = mean_handle_Both) %>%
  pivot_longer(-State, names_to = "Period", values_to = "Handle") %>%
  mutate(
    Period = factor(Period, levels = c("Retail_only", "Both"),
                    labels = c("Retail only", "Retail + Online")),
    State = fct_reorder(State, Handle, .fun = max)
  ) %>%
  ggplot(aes(x = State, y = Handle / 1e6, fill = Period)) +
  geom_col(position = "dodge") +
  scale_fill_manual(values = c("Retail only" = "#e74c3c",
                                "Retail + Online" = "#2ecc71")) +
  scale_y_continuous(labels = scales::dollar_format(suffix = "M")) +
  coord_flip() +
  labs(
    title = "Average Monthly Handle: Before vs After Online Launch",
    subtitle = "States that had retail before online legalization",
    x = NULL, y = "Average monthly handle", fill = NULL
  ) +
  theme_minimal(base_size = 13) +
  theme(plot.title = element_text(face = "bold"),
        legend.position = "bottom")

ggsave("output/retail_vs_online/state_before_after_online.png",
       p_state, width = 10, height = 7, dpi = 150)
cat("Saved: output/retail_vs_online/state_before_after_online.png\n\n")

# ── Online-only vs retail-only states ────────────────────────────────────────

cat("── States with online ONLY (no retail) ──\n")
online_only_states <- dates %>%
  filter(has_online %in% c("True", TRUE), has_retail %in% c("False", FALSE)) %>%
  select(state, online_start_date)
print(online_only_states, n = Inf)
cat("\n")

cat("── States with retail ONLY (no online) ──\n")
retail_only_states <- dates %>%
  filter(has_online %in% c("False", FALSE), has_retail %in% c("True", TRUE)) %>%
  select(state, retail_start_date)
print(retail_only_states, n = Inf)
cat("\n")

# Compare handle levels for pure online-only vs pure retail-only states
pure_comparison <- df %>%
  filter(
    (State %in% online_only_states$state & regime == "Online only") |
    (State %in% retail_only_states$state & regime == "Retail only")
  ) %>%
  mutate(type = if_else(State %in% online_only_states$state,
                        "Online-only states", "Retail-only states")) %>%
  group_by(type) %>%
  summarise(
    n_states      = n_distinct(State),
    n_months      = n(),
    mean_handle   = mean(Handle, na.rm = TRUE),
    median_handle = median(Handle, na.rm = TRUE),
    mean_revenue  = mean(Revenue, na.rm = TRUE),
    .groups = "drop"
  )

cat("── Pure online-only vs pure retail-only state comparison ──\n")
pure_comparison %>%
  mutate(across(c(mean_handle, median_handle, mean_revenue),
                ~ scales::dollar(., accuracy = 1))) %>%
  print(width = Inf)
cat("\n")

# ── Time series: average handle by regime over time ──────────────────────────

ts_regime <- df %>%
  filter(regime != "Pre-legalization") %>%
  group_by(month_date, regime) %>%
  summarise(
    mean_handle = mean(Handle, na.rm = TRUE),
    n_states    = n_distinct(State),
    .groups = "drop"
  )

p_ts <- ggplot(ts_regime, aes(x = month_date, y = mean_handle / 1e6,
                               color = regime)) +
  geom_line(linewidth = 1) +
  scale_color_manual(values = c("Retail only" = "#e74c3c",
                                 "Online only" = "#3498db",
                                 "Both" = "#2ecc71")) +
  scale_y_continuous(labels = scales::dollar_format(suffix = "M")) +
  labs(
    title = "Average Monthly Handle by Legalization Type Over Time",
    x = NULL, y = "Mean handle per state", color = "Regime"
  ) +
  theme_minimal(base_size = 13) +
  theme(plot.title = element_text(face = "bold"),
        legend.position = "bottom")

ggsave("output/retail_vs_online/handle_timeseries_by_regime.png",
       p_ts, width = 10, height = 6, dpi = 150)
cat("Saved: output/retail_vs_online/handle_timeseries_by_regime.png\n")

cat("\n── Done ──\n")
