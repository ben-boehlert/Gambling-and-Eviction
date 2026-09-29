#!/usr/bin/env Rscript
################################################################################
# did2s_state_level_effects.R
#
# State-level ATT estimates: for each of the 11 treated states, estimate
# did2s ATT vs. all 13 never-treated states. Produces forest-style plot
# showing per-state effect heterogeneity.
#
# Panel: keep-COVID, 2018-2024, surgical drops, 23 states.
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr); library(glue)
  library(fixest); library(tibble); library(ggplot2); library(did2s)
})

source("utils/eviction_treatment_schedule.R")

OUT_DIR <- "data/output/did2s_state_level_effects"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

ym_index <- function(d) as.integer(as.integer(format(d,"%Y"))*12 + as.integer(format(d,"%m")))

bad_obs <- tibble::tribble(
  ~state_abb, ~month_date,
  "ID","2016-01-01","ID","2016-02-01","ID","2016-03-01","ID","2016-04-01",
  "ID","2016-05-01","ID","2016-06-01","ID","2016-07-01",
  "CT","2016-01-01","CT","2016-02-01",
  "UT","2023-11-01","UT","2023-12-01"
) |> mutate(month_date = as.Date(month_date))

# Build keep-COVID panel
raw <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                show_col_types=FALSE) |>
  transmute(state_abb=as.character(state_abb), month_date=as.Date(month_date),
            filings_count=as.numeric(filings_count)) |>
  filter(month_date >= as.Date("2018-01-01"), month_date <= as.Date("2024-12-31"),
         state_abb != "ME") |>
  anti_join(bad_obs, by=c("state_abb","month_date"))
cov <- raw |> count(state_abb, name="n") |> arrange(desc(n))
keep <- cov |> filter(n == max(n)) |> pull(state_abb)
raw <- raw |> filter(state_abb %in% keep) |> drop_pre_paspa_states("did2s_state_level_effects")
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
         g = as.integer(g))

treated_states <- panel |> filter(g > 0L) |> distinct(state_abb, treat_start, g) |>
  arrange(treat_start)
never_treated  <- panel |> filter(g == 0L) |> distinct(state_abb) |> pull(state_abb)

cat("Treated states (n=", nrow(treated_states), "):\n", sep="")
print(treated_states)
cat("\nNever-treated states (n=", length(never_treated), "):\n", sep="")
cat(paste(never_treated, collapse=", "), "\n\n")

# Per-state ATT: for each treated state, run did2s against all never-treated states
state_atts <- list()
for (i in seq_len(nrow(treated_states))) {
  s <- treated_states$state_abb[i]
  g_s <- treated_states$g[i]
  treat_date_s <- treated_states$treat_start[i]
  states_to_use <- c(s, never_treated)
  sub <- panel |> filter(state_abb %in% states_to_use) |>
    mutate(id = as.integer(as.factor(state_abb)),
           post_treat = as.integer(g > 0 & t >= g))

  n_pre_obs  <- sum(sub$state_abb == s & sub$t < g_s)
  n_post_obs <- sum(sub$state_abb == s & sub$t >= g_s)

  fit <- tryCatch({
    suppressMessages(suppressWarnings({
      did2s(data = as.data.frame(sub), yname = "y",
            first_stage = ~ 0 | id + t,
            second_stage = ~ post_treat,
            treatment = "post_treat",
            cluster_var = "id")
    }))
  }, error = function(e) { cat("  ERROR for", s, ":", conditionMessage(e), "\n"); NULL })

  if (is.null(fit)) next
  att <- as.numeric(coef(fit)[1])
  se  <- sqrt(diag(stats::vcov(fit)))[1]
  state_atts[[length(state_atts)+1L]] <- tibble(
    state_abb = s, treat_start = treat_date_s,
    att = att, se = se,
    ci_lo = att - 1.96 * se, ci_hi = att + 1.96 * se,
    n_pre = n_pre_obs, n_post = n_post_obs
  )
  cat(sprintf("  %s (treat: %s): ATT = %+.3f, SE = %.3f, CI [%+.3f, %+.3f], n_pre=%d, n_post=%d\n",
              s, format(treat_date_s, "%Y-%m"),
              att, se, att - 1.96*se, att + 1.96*se, n_pre_obs, n_post_obs))
}

state_atts_df <- bind_rows(state_atts) |> arrange(att)
write_csv(state_atts_df, file.path(OUT_DIR, "state_level_atts.csv"))

cat("\n=== State-level ATTs (sorted) ===\n")
print(as.data.frame(state_atts_df), digits=3)

# Forest plot
state_atts_df <- state_atts_df |>
  mutate(state_label = paste0(state_abb, " (", format(treat_start, "%b %Y"), ")"),
         state_label = factor(state_label, levels = state_label))

# Compute simple inverse-variance weighted average
ivw_att <- sum(state_atts_df$att / state_atts_df$se^2) / sum(1 / state_atts_df$se^2)
ivw_se  <- sqrt(1 / sum(1 / state_atts_df$se^2))

cat(sprintf("\nInverse-variance weighted ATT: %+.4f (SE %.4f)\n", ivw_att, ivw_se))
cat(sprintf("  CI: [%+.3f, %+.3f]\n", ivw_att - 1.96*ivw_se, ivw_att + 1.96*ivw_se))

p <- ggplot(state_atts_df, aes(x = att, y = state_label)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
  geom_vline(xintercept = ivw_att, linetype = "dotted", color = "grey20") +
  geom_errorbarh(aes(xmin = ci_lo, xmax = ci_hi), height = 0.2, color = "grey50") +
  geom_point(size = 2.5) +
  scale_x_continuous(breaks = seq(-1.5, 1.5, 0.25)) +
  labs(x = "ATT (log filings)", y = NULL) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.y = element_blank(),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA))

ggsave(file.path(OUT_DIR, "state_atts_forest.pdf"), plot = p,
       width = 8, height = 5, bg = "transparent")
ggsave(file.path(OUT_DIR, "state_atts_forest.png"), plot = p,
       width = 8, height = 5, dpi = 200, bg = "white")

cat("\nWrote:", OUT_DIR, "\n")
