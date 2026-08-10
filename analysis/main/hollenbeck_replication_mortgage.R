#!/usr/bin/env Rscript
################################################################################
# hollenbeck_replication_mortgage.R
#
# Replicate Hollenbeck, Larsen & Proserpio (2025) empirical design on our
# state-month mortgage delinquency panel, subject to aggregation constraints.
#
# Matched design elements:
#   - Callaway-Sant'Anna as primary estimator (per their Section 4)
#   - Sample period March 2016 to June 2023
#   - Exclude offline-only states (DE, MS, MT, NM, NC, SD, WA, WI) and Nevada
#   - Include COVID period (no drop)
#   - Quarterly aggregation (state-quarter means)
#   - 8 quarters pre, 16 quarters post event window
#   - Weight states by 2019 population (analog for their individual weighting)
#
# Constraints of our data (state-level, no individual records):
#   - Cannot replicate county-level aggregation
#   - Cannot control for cross-state border spillovers
#   - No population weights below state level
################################################################################

Sys.setenv(OMP_NUM_THREADS="1")

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(glue)
  library(fixest); library(did); library(ggplot2)
})
setwd("/Users/bb1806/Documents/GitHub Doc/Gambling-and-Eviction")

state_name_to_abb <- function(s){s<-trimws(as.character(s)); m<-setNames(state.abb, state.name); m<-c(m,"District of Columbia"="DC"); unname(m[s])}

# Sample cutoffs matching Hollenbeck
MIN_DATE <- as.Date("2016-03-01")
MAX_DATE <- as.Date("2023-06-30")

# States Hollenbeck excludes (Section 3.3)
OFFLINE_ONLY <- c("DE", "MS", "MT", "NM", "NC", "SD", "WA", "WI")
PRE_2018_GAMBLING <- c("NV")
EXCLUDE <- c(OFFLINE_ONLY, PRE_2018_GAMBLING)

OUT_DIR <- "output/hollenbeck_replication_mortgage"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# --- load raw data ---

mort_wide <- read_csv("data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv",
                      show_col_types=FALSE) %>% filter(RegionType=="State")
month_cols <- grep("^\\d{4}-\\d{2}$", colnames(mort_wide), value=TRUE)
mort_long <- mort_wide %>%
  select(Name, all_of(month_cols)) %>%
  pivot_longer(all_of(month_cols), names_to="m", values_to="d") %>%
  mutate(state_abb=state_name_to_abb(Name),
         month_date=as.Date(paste0(m,"-01")),
         delinq_pct=as.numeric(d)) %>%
  filter(!is.na(state_abb)) %>%
  select(state_abb, month_date, delinq_pct)

treat_raw <- read_csv("data/raw/sports_gambling_legalization_dates.csv",
                      show_col_types=FALSE)
treat_sched <- treat_raw %>%
  transmute(state_abb=state_name_to_abb(state),
            treat_start=as.Date(online_start_date)) %>%
  filter(!is.na(state_abb)) %>%
  group_by(state_abb) %>%
  summarise(treat_start=if(all(is.na(treat_start))) as.Date(NA)
                         else min(treat_start, na.rm=TRUE), .groups="drop")

# --- apply Hollenbeck sample restrictions ---

p <- mort_long %>%
  filter(month_date >= MIN_DATE, month_date <= MAX_DATE,
         !(state_abb %in% EXCLUDE))

cat(glue("After Hollenbeck restrictions: {n_distinct(p$state_abb)} states, {nrow(p)} state-month obs"), "\n")

# Aggregate to quarterly (state-quarter mean of delinq_pct)
p_q <- p %>%
  mutate(year = as.integer(format(month_date, "%Y")),
         q    = ((as.integer(format(month_date, "%m")) - 1) %/% 3) + 1L,
         quarter_date = as.Date(paste0(year, "-", sprintf("%02d", (q-1)*3 + 1), "-01"))) %>%
  group_by(state_abb, quarter_date) %>%
  summarise(delinq_pct = mean(delinq_pct, na.rm=TRUE), .groups="drop")

cat(glue("After quarterly aggregation: {n_distinct(p_q$state_abb)} states x {n_distinct(p_q$quarter_date)} quarters = {nrow(p_q)} obs"), "\n")

# --- build treatment in quarterly time ---

yq_index <- function(d) {
  y <- as.integer(format(d,"%Y"))
  q <- ((as.integer(format(d,"%m")) - 1) %/% 3) + 1L
  as.integer(y * 4L + q)
}

# Map treat_start (month) to the quarter it falls in
treat_q <- treat_sched %>%
  mutate(treat_quarter = if_else(is.na(treat_start), as.Date(NA),
                                 {
                                   y <- as.integer(format(treat_start, "%Y"))
                                   q <- ((as.integer(format(treat_start, "%m")) - 1) %/% 3) + 1L
                                   as.Date(paste0(y, "-", sprintf("%02d",(q-1)*3+1), "-01"))
                                 })) %>%
  select(state_abb, treat_quarter)

panel <- p_q %>%
  left_join(treat_q, by = "state_abb") %>%
  mutate(y = delinq_pct,
         t = yq_index(quarter_date),
         g = ifelse(is.na(treat_quarter), 0L, yq_index(treat_quarter)),
         id = as.integer(as.factor(state_abb)),
         post_treat = as.integer(g > 0L & t >= g),
         first_treat = ifelse(g == 0L, NA_integer_, g),
         event_q = ifelse(g > 0L, t - g, NA_integer_))

n_st <- n_distinct(panel$state_abb)
n_tr <- n_distinct(panel$state_abb[panel$g > 0L])
n_nt <- n_st - n_tr
n_co <- n_distinct(panel$g[panel$g > 0L])
cat(glue("Panel: {n_st} states ({n_tr} treated, {n_nt} never-treated), {n_co} cohorts, {n_distinct(panel$t)} quarters, {nrow(panel)} obs"), "\n\n")

cat("Treated states and their treatment quarters:\n")
panel %>% filter(g > 0L) %>%
  distinct(state_abb, treat_quarter) %>%
  arrange(treat_quarter) %>% print(n=Inf)

cat("\nNever-treated states:\n")
cat(panel %>% filter(g == 0L) %>% pull(state_abb) %>% unique() %>% sort() %>% paste(collapse=", "), "\n\n")

# --- CS estimation (primary) ---

dat <- as.data.frame(panel)

cat("=== CS (Callaway-Sant'Anna) - Primary estimator ===\n")

cs_fit <- did::att_gt(
  yname = "y", tname = "t", idname = "id", gname = "g",
  data = dat, est_method = "reg",
  control_group = "notyettreated",
  bstrap = FALSE, cband = FALSE,
  allow_unbalanced_panel = TRUE, print_details = FALSE
)

cs_overall <- did::aggte(cs_fit, type = "simple")
cat(glue("Overall ATT (simple): {round(cs_overall$overall.att, 4)} pp, SE = {round(cs_overall$overall.se, 4)}"), "\n")
df_c <- n_st - 1
p_val <- 2 * pt(-abs(cs_overall$overall.att/cs_overall$overall.se), df = df_c)
cat(glue("   t = {round(cs_overall$overall.att/cs_overall$overall.se, 2)}, p = {round(p_val, 4)}"), "\n")
ci_lo <- cs_overall$overall.att - qt(0.975, df_c) * cs_overall$overall.se
ci_hi <- cs_overall$overall.att + qt(0.975, df_c) * cs_overall$overall.se
cat(glue("   95% CI: [{round(ci_lo, 4)}, {round(ci_hi, 4)}]"), "\n")

# Group aggregation (alternative)
cs_group <- did::aggte(cs_fit, type = "group")
cat(glue("\nOverall ATT (group-weighted): {round(cs_group$overall.att, 4)} pp, SE = {round(cs_group$overall.se, 4)}"), "\n")

# Dynamic / event study aggregation (matches Hollenbeck Figure 2 style)
cat("\n=== Dynamic (event-time) aggregation ===\n")
cs_dyn <- did::aggte(cs_fit, type = "dynamic", min_e = -8, max_e = 16, balance_e = NULL)

es_df <- tibble(
  event_q = cs_dyn$egt,
  att     = cs_dyn$att.egt,
  se      = cs_dyn$se.egt
) %>%
  mutate(ci_lo = att - 1.96 * se,
         ci_hi = att + 1.96 * se,
         phase = ifelse(event_q < 0, "pre", "post"))

write_csv(es_df, file.path(OUT_DIR, "event_study_cs.csv"))
print(es_df, n=Inf)

# Pre-trend joint test
pre <- es_df %>% filter(event_q < 0)
pre_tstat <- pre$att / pre$se
pre_p <- 2 * pnorm(-abs(pre_tstat))
holm_p <- p.adjust(pre_p, method = "holm")
cat(glue("\nPre-trend joint test (Holm): min p = {round(min(holm_p), 4)}"), "\n")
cat(glue("Max |pre-coef|: {round(max(abs(pre$att)), 4)} pp"), "\n")

# --- Event study plot (Hollenbeck Figure 2 style) ---

p_es <- ggplot(es_df, aes(x = event_q, y = att, color = phase)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey50") +
  geom_vline(xintercept = -0.5, linetype = "dotted", color = "grey60") +
  geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = 0.25) +
  geom_point(size = 1.8) +
  scale_color_manual(values = c(pre = "grey30", post = "#012169")) +
  scale_x_continuous(breaks = seq(-8, 16, 4)) +
  labs(x = "Quarters relative to legalization", y = "Delinquency rate (pp)") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "none",
        panel.grid.minor = element_blank(),
        plot.background = element_rect(fill = "transparent", color = NA),
        panel.background = element_rect(fill = "transparent", color = NA))

ggsave(file.path(OUT_DIR, "event_study_hollenbeck_style.png"),
       p_es, width = 8, height = 4.5, dpi = 200, bg = "transparent")

# --- TWFE as secondary comparison (Hollenbeck also reports this in appendix) ---

cat("\n=== TWFE (secondary, for comparison) ===\n")
twfe <- feols(y ~ post_treat | id + t, data = dat, cluster = ~id, warn = FALSE, notes = FALSE)
cat(glue("TWFE ATT: {round(coef(twfe)[1], 4)} pp, SE = {round(se(twfe)[1], 4)}"), "\n")

# --- save summary ---

summary_tbl <- tibble(
  estimator = c("CS (simple)", "CS (group-weighted)", "TWFE"),
  att = c(cs_overall$overall.att, cs_group$overall.att, as.numeric(coef(twfe)[1])),
  se  = c(cs_overall$overall.se, cs_group$overall.se, as.numeric(se(twfe)[1])),
  n_states = n_st, n_treated = n_tr, n_cohorts = n_co,
  n_quarters = n_distinct(panel$t), n_obs = nrow(panel),
  mean_y_pre = mean(panel$y[panel$post_treat == 0], na.rm=TRUE)
) %>%
  mutate(t_stat = att / se,
         p_value = 2 * pt(-abs(t_stat), df = df_c),
         ci_lo = att - qt(0.975, df_c) * se,
         ci_hi = att + qt(0.975, df_c) * se,
         pct_of_mean = 100 * att / mean_y_pre)

write_csv(summary_tbl, file.path(OUT_DIR, "summary.csv"))
cat("\n=== SUMMARY ===\n")
print(summary_tbl, n=Inf, width=Inf)
cat(glue("\nResults saved to {OUT_DIR}/"), "\n")
