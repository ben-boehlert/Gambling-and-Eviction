#!/usr/bin/env Rscript
################################################################################
# plot_pre2020_state_pretrends.R
#
# State-level visualization for the pre-2020 pre-trends specification used in
# evaluate_pretrends_modern_methods.R. Shows each treated state separately,
# rather than collapsing to treated vs never-treated averages.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(glue)
  library(lubridate)
  library(ggplot2)
  library(patchwork)
  library(scales)
})

DATA_FILE <- Sys.getenv("DATA_FILE", "data/raw/combined_monthly_panel.csv")
GAMBLING_FILE <- Sys.getenv("GAMBLING_FILE", "data/raw/sports_gambling_legalization_dates.csv")
OUT_DIR <- Sys.getenv("OUT_DIR", "output/pre2020_state_pretrends")
FIG_DIR <- Sys.getenv("FIG_DIR", "figures")
FIG_BASENAME <- Sys.getenv("FIG_BASENAME", "pre2020_state_pretrends_by_state")
EXCLUDE_STATES_RAW <- Sys.getenv("EXCLUDE_STATES", "ME")
MAX_DATE <- as.Date(Sys.getenv("MAX_DATE", "2019-12-31"))

parse_state_list <- function(x) {
  if (!nzchar(x)) return(character())
  trimws(strsplit(x, ",", fixed = TRUE)[[1]])
}

ym_index <- function(date) {
  y <- as.integer(format(date, "%Y"))
  m <- as.integer(format(date, "%m"))
  as.integer(y * 12L + m)
}

fips_to_state_abb <- function(state_fips) {
  lookup <- c(
    `1` = "AL", `2` = "AK", `4` = "AZ", `5` = "AR", `6` = "CA", `8` = "CO", `9` = "CT",
    `10` = "DE", `11` = "DC", `12` = "FL", `13` = "GA", `15` = "HI", `16` = "ID",
    `17` = "IL", `18` = "IN", `19` = "IA", `20` = "KS", `21` = "KY", `22` = "LA",
    `23` = "ME", `24` = "MD", `25` = "MA", `26` = "MI", `27` = "MN", `28` = "MS",
    `29` = "MO", `30` = "MT", `31` = "NE", `32` = "NV", `33` = "NH", `34` = "NJ",
    `35` = "NM", `36` = "NY", `37` = "NC", `38` = "ND", `39` = "OH", `40` = "OK",
    `41` = "OR", `42` = "PA", `44` = "RI", `45` = "SC", `46` = "SD", `47` = "TN",
    `48` = "TX", `49` = "UT", `50` = "VT", `51` = "VA", `53` = "WA", `54` = "WV",
    `55` = "WI", `56` = "WY"
  )
  unname(lookup[as.character(as.integer(state_fips))])
}

state_name_to_abb <- function(state_name) {
  state_name <- trimws(state_name)
  m <- setNames(state.abb, state.name)
  m2 <- c(m, "District of Columbia" = "DC")
  unname(m2[state_name])
}

state_abbr_from_geoid <- function(geo_id) {
  x <- tolower(trimws(as.character(geo_id)))
  key <- gsub("[^a-z]", "", x)
  name_key <- gsub("[^a-z]", "", tolower(state.name))
  m <- setNames(state.abb, name_key)
  unname(m[key])
}

build_state_panel <- function(df) {
  county_state <- df %>%
    filter(geo_level == "county") %>%
    mutate(
      fips_num = suppressWarnings(as.integer(fips)),
      state_fips = as.integer(floor(fips_num / 1000)),
      state_abb = fips_to_state_abb(state_fips),
      month_date = as.Date(month_date),
      filings_count = as.numeric(filings_count),
      renter_occupied_housing_units = as.numeric(renter_occupied_housing_units)
    ) %>%
    filter(!is.na(state_abb), !is.na(month_date)) %>%
    group_by(state_abb, month_date) %>%
    summarise(
      filings_count = sum(filings_count, na.rm = TRUE),
      renter_occupied_housing_units = sum(renter_occupied_housing_units, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      filings_per_1k_renters = if_else(
        is.finite(renter_occupied_housing_units) & renter_occupied_housing_units > 0,
        1000 * filings_count / renter_occupied_housing_units,
        as.numeric(NA)
      )
    )

  county_states <- unique(county_state$state_abb)

  state_fallback <- df %>%
    filter(geo_level == "state") %>%
    transmute(
      state_abb = state_abbr_from_geoid(geo_id),
      month_date = as.Date(month_date),
      filings_count = as.numeric(filings_count),
      renter_occupied_housing_units = as.numeric(renter_occupied_housing_units),
      filings_per_1k_renters = as.numeric(filings_per_1k_renters)
    ) %>%
    filter(!is.na(state_abb), !is.na(month_date)) %>%
    filter(!(state_abb %in% county_states))

  bind_rows(county_state, state_fallback) %>%
    arrange(state_abb, month_date)
}

exclude_states <- parse_state_list(EXCLUDE_STATES_RAW)
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(FIG_DIR, recursive = TRUE, showWarnings = FALSE)

panel_raw <- read_csv(DATA_FILE, show_col_types = FALSE) %>%
  build_state_panel()

gambling_dates <- read_csv(GAMBLING_FILE, show_col_types = FALSE) %>%
  mutate(
    state_abb = state_name_to_abb(state),
    online_start_date = as.Date(online_start_date, format = "%Y-%m-%d")
  ) %>%
  select(state_abb, online_start_date) %>%
  filter(!is.na(state_abb))

panel <- panel_raw %>%
  left_join(gambling_dates, by = "state_abb") %>%
  filter(!(state_abb %in% exclude_states)) %>%
  filter(month_date <= MAX_DATE) %>%
  mutate(
    t = ym_index(month_date),
    g = if_else(is.na(online_start_date), 0L, ym_index(online_start_date)),
    e = if_else(g > 0L, as.integer(t - g), NA_integer_),
    log_filings = log1p(pmax(filings_count, 0))
  ) %>%
  group_by(state_abb) %>%
  arrange(month_date, .by_group = TRUE) %>%
  mutate(
    lag12_filings = lag(filings_count, 12),
    yoy_pct = 100 * ((filings_count + 1) / (lag12_filings + 1) - 1)
  ) %>%
  ungroup()

plot_window <- panel %>%
  filter(g > 0L, !is.na(e), between(e, -12, 0))

treated_summary <- plot_window %>%
  distinct(state_abb, online_start_date) %>%
  arrange(online_start_date, state_abb) %>%
  mutate(
    treat_month = format(online_start_date, "%b %Y"),
    state_label = glue("{state_abb} ({treat_month})"),
    state_label = factor(state_label, levels = state_label)
  )

control_month <- panel %>%
  filter(g == 0L) %>%
  group_by(month_date) %>%
  summarise(control_log_filings = mean(log_filings, na.rm = TRUE), .groups = "drop")

line_data <- plot_window %>%
  left_join(control_month, by = "month_date") %>%
  left_join(treated_summary, by = c("state_abb", "online_start_date")) %>%
  group_by(state_abb) %>%
  mutate(
    state_center = log_filings - mean(log_filings[e >= -12 & e <= -1], na.rm = TRUE),
    control_center = control_log_filings - mean(control_log_filings[e >= -12 & e <= -1], na.rm = TRUE),
    standout_window = e %in% c(-5L, -4L)
  ) %>%
  ungroup() %>%
  mutate(state_label = factor(as.character(state_label), levels = levels(treated_summary$state_label)))

heat_data <- line_data %>%
  filter(e >= -12, e <= -1) %>%
  mutate(state_label = factor(state_label, levels = rev(levels(state_label))))

state_counts <- line_data %>%
  mutate(state_label = as.character(state_label)) %>%
  count(state_abb, state_label, name = "n_months") %>%
  arrange(state_label)

line_plot <- ggplot(line_data, aes(x = month_date)) +
  geom_hline(yintercept = 0, linewidth = 0.3, color = "gray85") +
  geom_line(aes(y = control_center), color = "gray45", linewidth = 0.55, linetype = "22") +
  geom_line(aes(y = state_center), color = "#1f78b4", linewidth = 0.85) +
  geom_point(
    data = line_data %>% filter(standout_window),
    aes(y = state_center),
    color = "#d95f02",
    size = 1.8
  ) +
  geom_vline(
    data = treated_summary,
    aes(xintercept = online_start_date),
    inherit.aes = FALSE,
    color = "black",
    linewidth = 0.35,
    linetype = "longdash"
  ) +
  facet_wrap(~state_label, ncol = 2) +
  scale_x_date(date_breaks = "4 months", date_labels = "%b\n%Y") +
  labs(
    title = "Pre-2020 Pre-Trends by Treated State",
    subtitle = "Blue: state log filings, centered on its own pre-window mean. Dashed gray: never-treated mean over the same calendar months.\nOrange points mark event times -5 and -4, the near-leads that remain significant even after dropping NH.",
    x = NULL,
    y = "Centered log(1 + filings)"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 15),
    plot.subtitle = element_text(size = 10.5, color = "gray30"),
    strip.text = element_text(face = "bold", size = 10),
    panel.grid.minor = element_blank(),
    axis.text.x = element_text(size = 8),
    legend.position = "none"
  )

heat_plot <- ggplot(heat_data, aes(x = month_date, y = state_label, fill = yoy_pct)) +
  geom_tile(color = "white", linewidth = 0.25, height = 0.9) +
  scale_fill_gradient2(
    low = "#b2182b",
    mid = "white",
    high = "#2166ac",
    midpoint = 0,
    limits = c(-60, 60),
    oob = squish,
    na.value = "gray65",
    name = "YoY %\nchange"
  ) +
  scale_x_date(date_breaks = "4 months", date_labels = "%b\n%Y") +
  labs(
    title = "Year-over-Year Change Within Each Treated State",
    subtitle = "Same pre-treatment months as the pre-2020 event-study window. Gray tiles mean no 12-month comparison exists in the underlying panel.",
    x = NULL,
    y = NULL
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 13),
    plot.subtitle = element_text(size = 10, color = "gray30"),
    panel.grid = element_blank(),
    axis.text.x = element_text(size = 8)
  )

combined_plot <- line_plot / heat_plot +
  plot_annotation(
    caption = glue(
      "Sample matches the pre-2020 specification in evaluate_pretrends_modern_methods.R. ",
      "Excluded states: {if (length(exclude_states) == 0) 'none' else paste(exclude_states, collapse = ', ')}. ",
      "Treatment is online legalization. NH is retained here to show the outlier that drives the far-pre lead."
    )
  ) &
  theme(plot.caption = element_text(hjust = 0, color = "gray35", size = 9))

fig_png <- file.path(FIG_DIR, paste0(FIG_BASENAME, ".png"))
fig_pdf <- file.path(FIG_DIR, paste0(FIG_BASENAME, ".pdf"))
data_csv <- file.path(OUT_DIR, "state_line_data.csv")
state_csv <- file.path(OUT_DIR, "treated_states_summary.csv")

write_csv(
  line_data %>%
    select(state_abb, state_label, month_date, online_start_date, e, filings_count, log_filings, state_center, control_center, yoy_pct, standout_window),
  data_csv
)
write_csv(
  treated_summary %>%
    mutate(state_label = as.character(state_label)) %>%
    left_join(state_counts, by = c("state_abb", "state_label")),
  state_csv
)

ggsave(fig_png, combined_plot, width = 14, height = 12, dpi = 320)
ggsave(fig_pdf, combined_plot, width = 14, height = 12)

cat(glue("Saved figure: {fig_png}\n"))
cat(glue("Saved figure: {fig_pdf}\n"))
cat(glue("Saved data:   {data_csv}\n"))
cat(glue("Saved state summary: {state_csv}\n"))
cat(glue("Treated states shown: {paste(treated_summary$state_abb, collapse = ', ')}\n"))
