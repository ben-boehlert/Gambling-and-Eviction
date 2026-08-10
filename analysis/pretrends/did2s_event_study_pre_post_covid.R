#!/usr/bin/env Rscript
################################################################################
# did2s_event_study_pre_post_covid.R
#
# Event studies on two subsamples:
#   (A) Pre-COVID only (2018-01 to 2020-02): treated = WV, PA, IN (3 cohorts)
#   (B) Post-COVID only (2022-04 to 2024-12): treated = KS, OH (2 cohorts);
#       drop already-treated states whose treatment fell during/before COVID.
#
# Both are weakly powered but cleanly separate the two regimes.
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr); library(glue)
  library(fixest); library(tibble); library(ggplot2); library(did2s)
  library(patchwork)
})

source("utils/eviction_treatment_schedule.R")

OUT_DIR <- "data/output/did2s_event_study_pre_post_covid"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

ym_index <- function(d) as.integer(as.integer(format(d,"%Y"))*12 + as.integer(format(d,"%m")))

bad_obs <- tibble::tribble(
  ~state_abb, ~month_date,
  "ID","2016-01-01","ID","2016-02-01","ID","2016-03-01","ID","2016-04-01",
  "ID","2016-05-01","ID","2016-06-01","ID","2016-07-01",
  "CT","2016-01-01","CT","2016-02-01",
  "UT","2023-11-01","UT","2023-12-01"
) |> mutate(month_date = as.Date(month_date))

# ----- subsample builder ------------------------------------------------------

build_subsample <- function(min_date, max_date, drop_already_treated = FALSE) {
  raw <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                  show_col_types=FALSE) |>
    transmute(state_abb = as.character(state_abb),
              month_date = as.Date(month_date),
              filings_count = as.numeric(filings_count)) |>
    filter(month_date >= as.Date(min_date), month_date <= as.Date(max_date),
           state_abb != "ME") |>
    anti_join(bad_obs, by=c("state_abb","month_date"))

  cov <- raw |> count(state_abb, name="n") |> arrange(desc(n))
  keep <- cov |> filter(n == max(n)) |> pull(state_abb)
  raw <- raw |> filter(state_abb %in% keep)
  n_pre <- n_distinct(raw$state_abb)
  common <- raw |> count(month_date, name="n") |> filter(n == n_pre) |> pull(month_date)
  raw <- raw |> filter(month_date %in% common)

  treat <- load_eviction_treatment_schedule(
    treat_file="data/raw/sports_gambling_legalization_dates.csv",
    treat_date_col="online_start_date", states=raw$state_abb)

  panel <- raw |> left_join(treat, by="state_abb") |>
    mutate(y = log1p(pmax(filings_count, 0)),
           t = ym_index(month_date),
           g_raw = ifelse(is.na(treat_start), 0L, ym_index(treat_start)),
           g_raw = as.integer(g_raw),
           id = as.integer(as.factor(state_abb)))

  # Treatment scoping: g must be inside the panel window, else treat as missing
  min_t <- min(panel$t); max_t <- max(panel$t)
  panel <- panel |>
    mutate(g = ifelse(g_raw == 0L, 0L,
                ifelse(g_raw < min_t,
                       if (drop_already_treated) -1L else 0L,  # -1 flag for drop
                ifelse(g_raw > max_t, 0L,  # treatment after panel ends -> never-treated
                       g_raw))),
           g = as.integer(g))

  if (drop_already_treated) {
    panel <- panel |> filter(g != -1L)
  }

  # Re-create id after potential filtering
  panel <- panel |>
    mutate(id = as.integer(as.factor(state_abb)),
           rel_time = ifelse(g <= 0L, NA_integer_, t - g),
           post_treat = as.integer(g > 0L & t >= g))

  panel
}

# ----- event study for one subsample -----------------------------------------

run_event_study <- function(panel, label, pre_window, post_window) {
  n_states <- n_distinct(panel$state_abb)
  n_treated <- n_distinct(panel$state_abb[panel$g > 0L])
  cat(glue("\n[{label}] {n_states} states ({n_treated} treated), {n_distinct(panel$t)} months, {nrow(panel)} obs"), "\n")
  cat("Treated states:",
      paste(sort(unique(panel$state_abb[panel$g > 0L])), collapse=", "), "\n")

  if (n_treated < 1L) { cat("  No treated states. Skip.\n"); return(NULL) }

  contrib <- panel |> filter(g > 0L, rel_time >= pre_window, rel_time <= post_window) |>
    group_by(rel_time) |>
    summarise(n_cohorts = n_distinct(state_abb), .groups="drop")

  es_long <- tryCatch(
    event_study(data=as.data.frame(panel), yname="y", idname="id",
                gname="g", tname="t", estimator="did2s", verbose=FALSE),
    error = function(e) { cat("  ERROR:", conditionMessage(e), "\n"); NULL })
  if (is.null(es_long)) return(NULL)

  es <- as_tibble(es_long) |>
    mutate(rel_time = as.integer(term)) |>
    filter(rel_time >= pre_window, rel_time <= post_window) |>
    mutate(ci_lo = estimate - 1.96 * std.error,
           ci_hi = estimate + 1.96 * std.error) |>
    arrange(rel_time) |>
    left_join(contrib, by="rel_time") |>
    dplyr::select(rel_time, estimate, std.error, ci_lo, ci_hi, n_cohorts)

  cat("Event study (cohort count per bin):\n")
  print(as.data.frame(es), digits=3)
  attr(es, "label") <- label
  attr(es, "n_states") <- n_states
  attr(es, "n_treated") <- n_treated
  es
}

# ----- run both subsamples ----------------------------------------------------

# Pre-COVID: 2018-01 to 2020-02
panel_pre <- build_subsample("2018-01-01", "2020-02-29")
es_pre <- run_event_study(panel_pre, "Pre-COVID (2018-01 to 2020-02)",
                            pre_window = -18L, post_window = 18L)

# Post-COVID: 2022-04 to 2024-12, drop states already-treated by 2022-04
panel_post <- build_subsample("2022-04-01", "2024-12-31", drop_already_treated = TRUE)
es_post <- run_event_study(panel_post, "Post-COVID (2022-04 to 2024-12)",
                             pre_window = -18L, post_window = 18L)

# ----- plot side-by-side ------------------------------------------------------

mk_plot <- function(es) {
  if (is.null(es)) return(NULL)
  ggplot(es, aes(x=rel_time, y=estimate)) +
    geom_hline(yintercept=0, linetype="dashed", color="grey40") +
    geom_vline(xintercept=-0.5, linetype="dotted", color="grey60") +
    geom_ribbon(aes(ymin=ci_lo, ymax=ci_hi), alpha=0.15) +
    geom_point(aes(size=n_cohorts)) +
    geom_line(linewidth=0.4) +
    scale_size_continuous(range=c(0.8, 3.5), name="N cohorts",
                          breaks = pretty(es$n_cohorts, n=4)) +
    scale_x_continuous(breaks=seq(-18, 18, 6)) +
    labs(x="Months relative to treatment", y="ATT (log filings)") +
    theme_minimal(base_size=11) +
    theme(panel.grid.minor=element_blank(),
          panel.grid.major.x=element_blank(),
          panel.background=element_rect(fill="transparent",color=NA),
          plot.background=element_rect(fill="transparent",color=NA))
}

p_pre  <- mk_plot(es_pre)
p_post <- mk_plot(es_post)

# Combined plot
if (!is.null(p_pre) && !is.null(p_post)) {
  combined <- (p_pre + ggtitle(NULL)) / (p_post + ggtitle(NULL))
  # Use plot_annotation for labels since we can't use titles
  combined <- combined + plot_annotation(
    tag_levels = list(c("Pre-COVID (3 treated)", "Post-COVID (2 treated, drops already-treated)")),
    theme = theme(plot.tag = element_text(size = 10, face = "italic"))
  ) & theme(plot.tag.position = c(0.02, 0.98))
  ggsave(file.path(OUT_DIR, "event_study_pre_post_covid.png"),
         plot = combined, width=8, height=8, dpi=200, bg="white")
  ggsave(file.path(OUT_DIR, "event_study_pre_post_covid.pdf"),
         plot = combined, width=8, height=8, bg="transparent")
}

if (!is.null(p_pre)) {
  ggsave(file.path(OUT_DIR, "pre_covid_event_study.png"),
         plot = p_pre, width=8, height=4.5, dpi=200, bg="white")
}
if (!is.null(p_post)) {
  ggsave(file.path(OUT_DIR, "post_covid_event_study.png"),
         plot = p_post, width=8, height=4.5, dpi=200, bg="white")
}

# Save CSVs
if (!is.null(es_pre))  write_csv(es_pre,  file.path(OUT_DIR, "pre_covid_event_study.csv"))
if (!is.null(es_post)) write_csv(es_post, file.path(OUT_DIR, "post_covid_event_study.csv"))

cat("\nDone. Outputs in", OUT_DIR, "\n")
