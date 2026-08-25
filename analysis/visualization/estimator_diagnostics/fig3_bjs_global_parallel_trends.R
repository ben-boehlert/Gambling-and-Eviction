# ==============================================================================
# fig3_bjs_global_parallel_trends.R
#
# Purpose: Two-panel diagnostic figure contrasting the identifying assumption
#   used by imputation-style staggered-DiD estimators (Borusyak-Jaravel-Spiess
#   / did2s / didimputation) against Callaway-Sant'Anna (CS). BJS-style
#   imputation fits unit + time fixed effects on ALL untreated observations
#   (every never-treated state-month, plus a treated state's entire
#   pre-period) and therefore needs parallel trends to hold GLOBALLY over the
#   full sample window -- including across the excised COVID break. CS
#   anchors ATT(g,t) locally at the base period g-1 and only needs parallel
#   trends to hold LOCALLY near treatment.
#
#   Panel A (real data): Vermont's log(filings per 1,000 renters) series with
#     the BJS imputation-fit window and the CS base-period window overlaid.
#   Panel B (stylized simulation): a treated unit with a differential
#     pre-trend confined to the first half of the pre-period, exactly
#     parallel thereafter (local PT holds, global PT does not). Shows BJS
#     picks up a persistent spurious ATT while CS sits at ~0.
#
# Inputs:
#   data/raw/state_month_panel_with_treatment.csv
#   data/raw/sports_gambling_legalization_dates.csv
#   utils/eviction_treatment_schedule.R
#
# Outputs:
#   figures/estimator_diagnostics/fig3_bjs_global_parallel_trends.png
#   figures/estimator_diagnostics/fig3_bjs_global_parallel_trends.pdf
# ==============================================================================

library(tidyverse)
library(here)
library(patchwork)

theme_set(theme_minimal())

# ---- Paper-to-code naming map -----------------------------------------------
# Notation                 | Code name          | Description
# Y_it (log outcome)       | log_filings_pc     | log(filings_per_1k_renters)
# g (treated state)        | treat_start / g    | Online legalization month
# g - 1 (CS base period)   | base_month / BASE  | Last pre-treatment period
# k (event time, sim)      | k                  | Months relative to base
# ATT(g,t) [CS]            | att_hat_cs         | CS-style local DiD estimate
# ATT_hat [BJS imputation] | att_hat_bjs        | Imputation-estimator ATT
# Y(0) imputed [BJS]       | y0_hat_bjs         | Unit+time-FE fitted Y(0)
# Y(0) imputed [CS]        | y0_hat_cs          | Base-period-anchored Y(0)
# Y(0) true (sim DGP)      | y0_true            | Noiseless simulated Y(0)
# ------------------------------------------------------------------------------

SEED <- 20260812L
set.seed(SEED)

# Okabe-Ito colorblind-safe palette
OKABE_ITO <- c(
  black      = "#000000",
  orange     = "#E69F00",
  sky_blue   = "#56B4E9",
  green      = "#009E73",
  yellow     = "#F0E442",
  blue       = "#0072B2",
  vermillion = "#D55E00",
  pink       = "#CC79A7"
)

source(here("utils", "eviction_treatment_schedule.R"))

PANEL_FILE <- here("data", "raw", "state_month_panel_with_treatment.csv")
SCHEDULE_FILE <- here("data", "raw", "sports_gambling_legalization_dates.csv")
OUT_DIR <- here("figures", "estimator_diagnostics")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

FOCAL_STATE <- "VT"
SAMPLE_START <- as.Date("2016-01-01")
SAMPLE_END <- as.Date("2024-12-01")
COVID_START <- as.Date("2020-03-01")
COVID_END <- as.Date("2022-03-01")

safe_log <- function(x, eps = 1e-8) log(pmax(x, eps))

# ==============================================================================
# PANEL A -- real data: Vermont, imputation window vs. CS base-period window
# ==============================================================================

panel_raw <- read_csv(PANEL_FILE, show_col_types = FALSE)
stopifnot(FOCAL_STATE %in% panel_raw$state_abb)

schedule <- load_eviction_treatment_schedule(
  treat_file = SCHEDULE_FILE,
  treat_date_col = "online_start_date",
  states = unique(panel_raw$state_abb)
)

g_month <- schedule |>
  filter(state_abb == FOCAL_STATE) |>
  pull(treat_start)
stopifnot(length(g_month) == 1L, !is.na(g_month))
base_month <- g_month %m-% months(1)

never_treated_states <- schedule |>
  filter(is.na(treat_start), state_abb != FOCAL_STATE) |>
  pull(state_abb)
stopifnot(length(never_treated_states) > 0L)

panel_clean <- panel_raw |>
  filter(month_date >= SAMPLE_START, month_date <= SAMPLE_END) |>
  mutate(log_filings_pc = safe_log(filings_per_1k_renters))

covid_months <- seq(COVID_START, COVID_END, by = "month")

focal_series <- panel_clean |>
  filter(state_abb == FOCAL_STATE) |>
  transmute(
    month_date,
    value = if_else(month_date %in% covid_months, NA_real_, log_filings_pc),
    series = "Vermont (treated, online Jan 2024)"
  )

never_treated_series <- panel_clean |>
  filter(state_abb %in% never_treated_states) |>
  group_by(month_date) |>
  summarise(value = mean(log_filings_pc, na.rm = TRUE), .groups = "drop") |>
  mutate(
    value = if_else(month_date %in% covid_months, NA_real_, value),
    series = "Never-treated states (mean)"
  )

panel_a_long <- bind_rows(focal_series, never_treated_series)

y_range <- range(panel_a_long$value, na.rm = TRUE)
bracket_y <- y_range[1] - 0.28 * diff(y_range)

bjs_window_pre_covid <- tibble(
  x_start = SAMPLE_START,
  x_end = COVID_START %m-% months(1)
)
bjs_window_post_covid <- tibble(
  x_start = COVID_END %m+% months(1),
  x_end = base_month
)

panel_a <- ggplot() +
  annotate(
    "rect",
    xmin = COVID_START, xmax = COVID_END %m+% months(1),
    ymin = -Inf, ymax = Inf,
    fill = "grey70", alpha = 0.25
  ) +
  geom_line(
    data = panel_a_long,
    aes(x = month_date, y = value, color = series, linetype = series),
    linewidth = 0.7, na.rm = TRUE
  ) +
  geom_vline(xintercept = g_month, linetype = "dotted", color = OKABE_ITO["black"]) +
  geom_segment(
    data = bjs_window_pre_covid,
    aes(x = x_start, xend = x_end, y = bracket_y, yend = bracket_y),
    color = OKABE_ITO["vermillion"], linewidth = 1.1,
    arrow = arrow(length = unit(0.06, "in"), ends = "both", angle = 90)
  ) +
  geom_segment(
    data = bjs_window_post_covid,
    aes(x = x_start, xend = x_end, y = bracket_y, yend = bracket_y),
    color = OKABE_ITO["vermillion"], linewidth = 1.1,
    arrow = arrow(length = unit(0.06, "in"), ends = "both", angle = 90)
  ) +
  annotate(
    "point", x = base_month, y = bracket_y,
    color = OKABE_ITO["blue"], size = 3.2, shape = 18
  ) +
  annotate(
    "text",
    x = mean(c(SAMPLE_START, base_month)), y = bracket_y - 0.10 * diff(y_range),
    label = "BJS imputation fit window (2016-2023, excl. COVID)",
    color = OKABE_ITO["vermillion"], size = 3.1, hjust = 0.35
  ) +
  annotate(
    "text",
    x = base_month, y = bracket_y - 0.20 * diff(y_range),
    label = "CS base period (g-1)\nDec 2023 only",
    color = OKABE_ITO["blue"], size = 3.1, hjust = 1.0
  ) +
  annotate(
    "text",
    x = SAMPLE_START, y = y_range[2],
    label = str_wrap(
      "BJS imputes this state's 2023-24 counterfactual partly from its 2016-2019 behavior - parallel trends must hold across the COVID break.",
      width = 55
    ),
    hjust = 0, vjust = 1, size = 3.0, fontface = "italic"
  ) +
  scale_color_manual(
    values = c(
      "Vermont (treated, online Jan 2024)" = unname(OKABE_ITO["black"]),
      "Never-treated states (mean)" = "grey55"
    )
  ) +
  scale_linetype_manual(
    values = c(
      "Vermont (treated, online Jan 2024)" = "solid",
      "Never-treated states (mean)" = "dashed"
    )
  ) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  coord_cartesian(ylim = c(bracket_y - 0.30 * diff(y_range), y_range[2])) +
  labs(
    title = "Panel A: Which observations identify the counterfactual (real data)",
    subtitle = "Vermont - latest online sports-gambling legalization date in the ETS panel",
    x = NULL,
    y = "log(filings per 1,000 renter households)",
    color = NULL, linetype = NULL
  ) +
  theme(legend.position = "bottom")

# ==============================================================================
# PANEL B -- stylized simulation: local PT holds, global PT fails
# ==============================================================================

N_CONTROL <- 13L
N_UNITS <- N_CONTROL + 1L # unit 1 = treated
T0_PRE <- 90L
T1_POST <- 12L
T_TOTAL <- T0_PRE + T1_POST
G <- T0_PRE + 1L # first treated period
BASE <- T0_PRE # g - 1
RAMP_MONTHS <- 45L
DRIFT_END <- -0.15
UNIT_FE_SD <- 0.30
NOISE_SD <- 0.008

drift_fun <- function(t) {
  if_else(t <= RAMP_MONTHS, DRIFT_END * (t / RAMP_MONTHS), DRIFT_END)
}

unit_fe_vals <- rnorm(N_UNITS, mean = 0, sd = UNIT_FE_SD)

sim_df <- expand_grid(unit_id = seq_len(N_UNITS), t = seq_len(T_TOTAL)) |>
  mutate(
    is_treated_unit = unit_id == 1L,
    time_fe = 0.15 * sin(2 * pi * t / 12) + 0.004 * t,
    unit_fe = unit_fe_vals[unit_id],
    drift = if_else(is_treated_unit, drift_fun(t), 0),
    y0_true = unit_fe + time_fe + drift,
    y = y0_true + rnorm(n(), mean = 0, sd = NOISE_SD) # true effect = 0 throughout
  )

# BJS-style imputation: fit unit + time FE on ALL untreated obs (controls at
# every t, plus the treated unit's entire pre-period), then impute Y(0) for
# the treated unit's post-treatment cells.
bjs_fit_data <- sim_df |> filter(!(is_treated_unit & t >= G))
model_bjs <- lm(y ~ factor(unit_id) + factor(t), data = bjs_fit_data)

control_means <- sim_df |>
  filter(!is_treated_unit) |>
  summarise(ybar_control = mean(y), .by = t)
ybar_control_base <- control_means |>
  filter(t == BASE) |>
  pull(ybar_control)

y_treated_base <- sim_df |>
  filter(is_treated_unit, t == BASE) |>
  pull(y)

post_treated <- sim_df |>
  filter(is_treated_unit, t >= G) |>
  mutate(k = t - BASE) |>
  left_join(control_means, by = "t") |>
  mutate(
    y0_hat_bjs = predict(model_bjs, newdata = tibble(unit_id = 1L, t = t)),
    y0_hat_cs = y_treated_base + (ybar_control - ybar_control_base),
    att_hat_bjs = y - y0_hat_bjs,
    att_hat_cs = y - y0_hat_cs
  )

stopifnot(all(is.finite(post_treated$att_hat_bjs)))
stopifnot(all(is.finite(post_treated$att_hat_cs)))

mean_att_bjs <- mean(post_treated$att_hat_bjs)
mean_att_cs <- mean(post_treated$att_hat_cs)
avg_pre_deviation <- mean(drift_fun(seq_len(BASE)))
terminal_deviation <- drift_fun(BASE)

message("=== Simulated ATT bias summary (Panel B) ===")
message(sprintf("BJS-style mean post-period ATT_hat:  %.4f", mean_att_bjs))
message(sprintf("CS-style mean post-period ATT_hat:   %.4f", mean_att_cs))
message(sprintf(
  "Treated unit's average pre-period deviation (t=1..%d): %.4f",
  BASE, avg_pre_deviation
))
message(sprintf(
  "Treated unit's terminal (t=%d, g-1) deviation:          %.4f",
  BASE, terminal_deviation
))
message(
  "Analytic intuition: BJS's unit FE absorbs the AVERAGE pre-period ",
  "deviation; CS anchors on the LAST pre-period value only. BJS bias ",
  "= terminal deviation - average pre-period deviation = ",
  sprintf("%.4f", terminal_deviation - avg_pre_deviation),
  " (matches BJS mean post ATT_hat up to simulation noise); CS bias ~ 0."
)

# --- Panel B1: observed series, true Y(0), and both imputed counterfactuals
b1_long <- bind_rows(
  sim_df |> filter(is_treated_unit) |> transmute(t, value = y, series = "Observed (treated unit)"),
  sim_df |> filter(is_treated_unit) |> transmute(t, value = y0_true, series = "True Y(0), no noise"),
  control_means |> transmute(t, value = ybar_control, series = "Control mean"),
  post_treated |> transmute(t, value = y0_hat_bjs, series = "BJS imputed Y(0)"),
  post_treated |> transmute(t, value = y0_hat_cs, series = "CS imputed Y(0)")
)

series_colors <- c(
  "Observed (treated unit)" = unname(OKABE_ITO["black"]),
  "True Y(0), no noise" = "grey40",
  "Control mean" = "grey70",
  "BJS imputed Y(0)" = unname(OKABE_ITO["vermillion"]),
  "CS imputed Y(0)" = unname(OKABE_ITO["blue"])
)
series_linetypes <- c(
  "Observed (treated unit)" = "solid",
  "True Y(0), no noise" = "longdash",
  "Control mean" = "dotted",
  "BJS imputed Y(0)" = "dashed",
  "CS imputed Y(0)" = "dotdash"
)

panel_b1 <- ggplot() +
  annotate(
    "rect", xmin = 1, xmax = RAMP_MONTHS, ymin = -Inf, ymax = Inf,
    fill = "grey85", alpha = 0.4
  ) +
  annotate(
    "rect", xmin = G - 0.5, xmax = T_TOTAL + 0.5, ymin = -Inf, ymax = Inf,
    fill = NA, color = "grey40", linetype = "dashed", linewidth = 0.35
  ) +
  geom_line(
    data = b1_long |> filter(series %in% c("Observed (treated unit)", "True Y(0), no noise", "Control mean")),
    aes(x = t, y = value, color = series, linetype = series), linewidth = 0.6
  ) +
  geom_line(
    data = b1_long |> filter(series %in% c("BJS imputed Y(0)", "CS imputed Y(0)")),
    aes(x = t, y = value, color = series, linetype = series), linewidth = 0.9
  ) +
  geom_vline(xintercept = G - 0.5, linetype = "dotted", color = OKABE_ITO["black"]) +
  annotate(
    "text", x = RAMP_MONTHS / 2, y = Inf,
    label = "differential\npre-trend", size = 2.6, vjust = 1.1, hjust = 0.5
  ) +
  annotate(
    "text", x = (RAMP_MONTHS + BASE) / 2, y = Inf,
    label = "parallel (local PT holds)", size = 2.6, vjust = 1.1, hjust = 0.5
  ) +
  annotate(
    "text", x = (G + T_TOTAL) / 2, y = Inf,
    label = "post window\n(dashed box, zoom in B2)", size = 2.6, vjust = 1.1, hjust = 0.5
  ) +
  scale_color_manual(values = series_colors) +
  scale_linetype_manual(values = series_linetypes) +
  labs(
    title = "Panel B: When local PT holds but global PT fails (stylized simulation)",
    subtitle = "True effect = 0 throughout; shaded region = differential pre-trend (months 1-45)",
    x = "Simulated month", y = "Simulated log outcome",
    color = NULL, linetype = NULL
  ) +
  theme(legend.position = "bottom") +
  guides(color = guide_legend(nrow = 2), linetype = guide_legend(nrow = 2))

# --- Panel B2: event-time ATT_hat comparison
att_long <- bind_rows(
  post_treated |> transmute(k, att_hat = att_hat_bjs, method = "BJS-style imputation"),
  post_treated |> transmute(k, att_hat = att_hat_cs, method = "CS-style (base = g-1)")
)

panel_b2 <- ggplot(att_long, aes(x = k, y = att_hat, color = method, linetype = method, shape = method)) +
  geom_hline(yintercept = 0, color = OKABE_ITO["black"], linewidth = 0.5) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 1.8) +
  scale_color_manual(
    values = c(
      "BJS-style imputation" = unname(OKABE_ITO["vermillion"]),
      "CS-style (base = g-1)" = unname(OKABE_ITO["blue"])
    )
  ) +
  scale_linetype_manual(
    values = c(
      "BJS-style imputation" = "dashed",
      "CS-style (base = g-1)" = "dotdash"
    )
  ) +
  labs(
    x = "Event time k (months since g)",
    y = expression(hat(ATT)(k)),
    color = NULL, linetype = NULL, shape = NULL
  ) +
  theme(legend.position = "bottom") +
  guides(color = guide_legend(nrow = 2), linetype = guide_legend(nrow = 2), shape = guide_legend(nrow = 2))

panel_b <- panel_b1 + panel_b2 + plot_layout(widths = c(2, 1))

# ==============================================================================
# Assemble and save
# ==============================================================================

fig3 <- panel_a / panel_b + plot_layout(heights = c(1, 1.1))

png_path <- file.path(OUT_DIR, "fig3_bjs_global_parallel_trends.png")
pdf_path <- file.path(OUT_DIR, "fig3_bjs_global_parallel_trends.pdf")

ggsave(png_path, fig3, width = 12, height = 7, dpi = 300, bg = "white")
ggsave(pdf_path, fig3, width = 12, height = 7, device = pdf, bg = "white")

stopifnot(file.exists(png_path), file.exists(pdf_path))

message("=== Figure saved ===")
message(png_path)
message(pdf_path)
message(sprintf(
  "Panel A state: %s | online date g: %s | coverage: %s to %s",
  FOCAL_STATE, format(g_month), format(min(panel_clean$month_date)), format(max(panel_clean$month_date))
))
