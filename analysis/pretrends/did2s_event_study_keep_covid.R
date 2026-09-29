#!/usr/bin/env Rscript
################################################################################
# did2s_event_study_keep_covid.R
#
# did2s event study on the "keep COVID, no adjustment" spec — same panel
# as spec (2) of did2s_covid_adjustment_test.R. No g-snapping needed since
# all treated states have observable pre-period.
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr); library(glue)
  library(fixest); library(tibble); library(ggplot2); library(did2s)
})

source("utils/eviction_treatment_schedule.R")

OUT_DIR <- "data/output/did2s_event_study_keep_covid"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

ym_index <- function(d) as.integer(as.integer(format(d,"%Y"))*12 + as.integer(format(d,"%m")))

PRE_WINDOW  <- -18L
POST_WINDOW <- 18L

bad_obs <- tibble::tribble(
  ~state_abb, ~month_date,
  "ID","2016-01-01","ID","2016-02-01","ID","2016-03-01","ID","2016-04-01",
  "ID","2016-05-01","ID","2016-06-01","ID","2016-07-01",
  "CT","2016-01-01","CT","2016-02-01",
  "UT","2023-11-01","UT","2023-12-01"
) |> mutate(month_date = as.Date(month_date))

# Build panel: 2018-2024, KEEP COVID, surgical drops, balance to common months
raw <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                show_col_types=FALSE) |>
  transmute(state_abb=as.character(state_abb), month_date=as.Date(month_date),
            filings_count=as.numeric(filings_count)) |>
  filter(month_date >= as.Date("2018-01-01"), month_date <= as.Date("2024-12-31"),
         state_abb != "ME") |>
  anti_join(bad_obs, by=c("state_abb","month_date"))

cov <- raw |> count(state_abb, name="n") |> arrange(desc(n))
keep <- cov |> filter(n == max(n)) |> pull(state_abb)
raw <- raw |> filter(state_abb %in% keep) |> drop_pre_paspa_states("did2s_event_study_keep_covid")
n_pre <- n_distinct(raw$state_abb)
common <- raw |> count(month_date, name="n") |> filter(n == n_pre) |> pull(month_date)
raw <- raw |> filter(month_date %in% common)

treat <- load_eviction_treatment_schedule(
  treat_file="data/raw/sports_gambling_legalization_dates.csv",
  treat_date_col="online_start_date", states=raw$state_abb)

panel <- raw |> left_join(treat, by="state_abb") |>
  mutate(y = log1p(pmax(filings_count, 0)),
         t = ym_index(month_date),
         g = ifelse(is.na(treat_start), 0L, ym_index(treat_start)),
         g = as.integer(g),
         id = as.integer(as.factor(state_abb)),
         rel_time = ifelse(g == 0L, NA_integer_, t - g),
         post_treat = as.integer(g > 0L & t >= g))

n_states <- n_distinct(panel$state_abb)
n_treated <- n_distinct(panel$state_abb[panel$g > 0L])
cat(glue("Panel: {n_states} states ({n_treated} treated), {n_distinct(panel$t)} months, {nrow(panel)} obs"), "\n")
cat(glue("Date range: {min(panel$month_date)} to {max(panel$month_date)} (COVID kept)"), "\n\n")

# Cohort contributions per rel_time
cat("=== Cohort contributions per rel_time ===\n")
contrib <- panel |> filter(g > 0L, rel_time >= PRE_WINDOW, rel_time <= POST_WINDOW) |>
  group_by(rel_time) |>
  summarise(n_states = n_distinct(state_abb),
            states = paste(sort(unique(state_abb)), collapse=","),
            .groups="drop") |>
  arrange(rel_time)
print(contrib, n=Inf)
cat("\n")

# did2s event study (need to handle that g must be in t — true here since no drop)
es_long <- event_study(data=as.data.frame(panel), yname="y", idname="id",
                        gname="g", tname="t", estimator="did2s", verbose=FALSE)
es <- as_tibble(es_long) |>
  mutate(rel_time = as.integer(term)) |>
  filter(rel_time >= PRE_WINDOW, rel_time <= POST_WINDOW) |>
  mutate(ci_lo = estimate - 1.96 * std.error,
         ci_hi = estimate + 1.96 * std.error) |>
  arrange(rel_time) |>
  dplyr::select(rel_time, estimate, std.error, ci_lo, ci_hi)

es <- es |> left_join(contrib |> dplyr::select(rel_time, n_cohorts = n_states),
                       by = "rel_time")

cat("=== Event study coefficients ===\n")
print(as.data.frame(es), digits=3)
write_csv(es, file.path(OUT_DIR, "event_study.csv"))

# Plot
p <- ggplot(es, aes(x=rel_time, y=estimate)) +
  geom_hline(yintercept=0, linetype="dashed", color="grey40") +
  geom_vline(xintercept=-0.5, linetype="dotted", color="grey60") +
  geom_ribbon(aes(ymin=ci_lo, ymax=ci_hi), alpha=0.15) +
  geom_point(aes(size=n_cohorts)) +
  geom_line(linewidth=0.4) +
  scale_size_continuous(range=c(0.8, 3.5), name="N cohorts") +
  scale_x_continuous(breaks=seq(PRE_WINDOW, POST_WINDOW, 3)) +
  labs(x="Months relative to treatment", y="ATT (log filings)") +
  theme_minimal(base_size=11) +
  theme(panel.grid.minor=element_blank(),
        panel.grid.major.x=element_blank(),
        panel.background=element_rect(fill="transparent",color=NA),
        plot.background=element_rect(fill="transparent",color=NA),
        legend.position="right")

ggsave(file.path(OUT_DIR, "event_study_plot.pdf"), plot=p,
       width=8, height=4.5, bg="transparent")
ggsave(file.path(OUT_DIR, "event_study_plot.png"), plot=p,
       width=8, height=4.5, dpi=200, bg="white")

cat("\nWrote:", OUT_DIR, "\n")
