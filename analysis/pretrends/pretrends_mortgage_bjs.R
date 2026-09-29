#!/usr/bin/env Rscript
################################################################################
# pretrends_mortgage_bjs.R
#
# BJS (Borusyak, Jaravel, Spiess 2024) imputation event study + pre-trends
# on the mortgage delinquency panel. Built to match pretrends_mortgage_delinquency.R
# panel construction exactly (same 51-state panel, same COVID drop).
#
# USAGE: Rscript analysis/pretrends/pretrends_mortgage_bjs.R
################################################################################

Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1",
  MKL_NUM_THREADS = "1", VECLIB_MAXIMUM_THREADS = "1"
)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
  library(didimputation)
  library(glue)
})
source("utils/eviction_treatment_schedule.R")  # drop_pre_paspa_states(): NV never enters

state_name_to_abb <- function(state_name) {
  state_name <- trimws(as.character(state_name))
  m <- setNames(state.abb, state.name)
  m <- c(m, "District of Columbia" = "DC")
  unname(m[state_name])
}
ym_index <- function(date) {
  as.integer(as.integer(format(date, "%Y")) * 12L + as.integer(format(date, "%m")))
}

MORTGAGE_FILE <- "data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv"
TREAT_FILE    <- "data/raw/sports_gambling_legalization_dates.csv"
TREAT_COL     <- "online_start_date"
MIN_DATE <- as.Date("2016-01-01"); MAX_DATE <- as.Date("2024-12-31")
DROP_START <- as.Date("2020-03-01"); DROP_END <- as.Date("2021-07-31")
OUT_DIR <- "output/pretrends_mortgage_bjs"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# ---- build panel (identical to pretrends_mortgage_delinquency.R) -------------

mort_wide <- read_csv(MORTGAGE_FILE, show_col_types = FALSE) %>%
  filter(RegionType == "State")
month_cols <- grep("^\\d{4}-\\d{2}$", colnames(mort_wide), value = TRUE)

mort_long <- mort_wide %>%
  select(Name, all_of(month_cols)) %>%
  pivot_longer(cols = all_of(month_cols), names_to = "month_str",
               values_to = "delinq_pct") %>%
  mutate(
    state_abb  = state_name_to_abb(Name),
    month_date = as.Date(paste0(month_str, "-01")),
    delinq_pct = as.numeric(delinq_pct)
  ) %>%
  filter(!is.na(state_abb)) %>%
  filter(month_date >= MIN_DATE, month_date <= MAX_DATE) %>%
  filter(!(month_date >= DROP_START & month_date <= DROP_END))

treat_raw <- read_csv(TREAT_FILE, show_col_types = FALSE)
treat_sched <- treat_raw %>%
  transmute(state_abb = state_name_to_abb(state),
            treat_start = as.Date(.data[[TREAT_COL]])) %>%
  filter(!is.na(state_abb)) %>%
  group_by(state_abb) %>%
  summarise(treat_start = if (all(is.na(treat_start))) as.Date(NA)
                          else min(treat_start, na.rm = TRUE),
            .groups = "drop")

coverage <- mort_long %>% count(state_abb, name = "n_months")
max_cov <- max(coverage$n_months)
keep <- coverage %>% filter(n_months >= max_cov) %>% pull(state_abb)
panel0 <- mort_long %>% filter(state_abb %in% keep) %>%
  drop_pre_paspa_states("pretrends_mortgage_bjs")
n_states_pre <- n_distinct(panel0$state_abb)
common <- panel0 %>% count(month_date, name = "n") %>%
  filter(n == n_states_pre) %>% pull(month_date)
panel0 <- panel0 %>% filter(month_date %in% common)

panel <- panel0 %>%
  left_join(treat_sched, by = "state_abb") %>%
  mutate(
    y = delinq_pct,
    t = ym_index(month_date),
    g = ifelse(is.na(treat_start), 0L, ym_index(treat_start)),
    g = as.integer(g),
    id = as.integer(as.factor(state_abb)),
    first_treat = ifelse(g == 0L, NA_integer_, g)
  )

n_states <- n_distinct(panel$state_abb)
n_treat  <- n_distinct(panel$state_abb[panel$g > 0L])
cat(glue("Panel: {n_states} states ({n_treat} treated), {n_distinct(panel$t)} months, {nrow(panel)} obs"), "\n")

# ---- BJS event study ---------------------------------------------------------

# Pre-trends: 12 months before treatment (k = -12..-2; -1 is omitted by convention
# in didimputation via reference). Post: 0..24 months.
PRE_HORIZONS  <- -12:-2
POST_HORIZONS <- 0:24

dat <- as.data.frame(panel)

cat("\nRunning BJS imputation event study...\n")
t0 <- Sys.time()

bjs_es <- did_imputation(
  data        = dat,
  yname       = "y",
  gname       = "first_treat",
  tname       = "t",
  idname      = "id",
  horizon     = POST_HORIZONS,
  pretrends   = PRE_HORIZONS,
  cluster_var = "id"
)

cat(glue("Done in {round(as.numeric(difftime(Sys.time(), t0, units='secs')),1)}s"), "\n\n")

# ---- tidy + save -------------------------------------------------------------

es_df <- as_tibble(bjs_es) %>%
  mutate(
    rel_time = as.integer(term),
    ci_lo = estimate - 1.96 * std.error,
    ci_hi = estimate + 1.96 * std.error,
    phase = ifelse(rel_time < 0, "pre", "post")
  ) %>%
  arrange(rel_time)

write_csv(es_df, file.path(OUT_DIR, "event_study_bjs.csv"))

# ---- pre-trend joint test (Wald) ---------------------------------------------

pre <- es_df %>% filter(phase == "pre")
if (nrow(pre) > 0) {
  # Per-period t-tests
  pre <- pre %>% mutate(t_stat = estimate / std.error,
                        p_val  = 2 * pnorm(-abs(t_stat)))
  holm_p <- p.adjust(pre$p_val, method = "holm")
  pre$holm_p <- holm_p
  any_rej <- any(holm_p < 0.05)
  min_p <- min(holm_p)

  cat("=== BJS Pre-trend diagnostics ===\n")
  cat(glue("  Pre-periods tested: {nrow(pre)} (k = {min(pre$rel_time)} to {max(pre$rel_time)})"), "\n")
  cat(glue("  Max |pre-coef|: {round(max(abs(pre$estimate)), 4)} pp"), "\n")
  cat(glue("  Mean |pre-coef|: {round(mean(abs(pre$estimate)), 4)} pp"), "\n")
  cat(glue("  Holm min p: {round(min_p, 4)}  (reject PT at 0.05: {any_rej})"), "\n\n")

  print(pre %>% select(rel_time, estimate, std.error, t_stat, p_val, holm_p),
        n = Inf)
}

# ---- plot --------------------------------------------------------------------

p <- ggplot(es_df, aes(x = rel_time, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey50") +
  geom_vline(xintercept = -0.5, linetype = "dotted", color = "grey60") +
  geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi, fill = phase), alpha = 0.2) +
  geom_line(aes(color = phase)) +
  geom_point(aes(color = phase), size = 1.8) +
  scale_color_manual(values = c(pre = "grey30", post = "#012169")) +
  scale_fill_manual(values = c(pre = "grey30", post = "#012169")) +
  scale_x_continuous(breaks = seq(-12, 24, 3)) +
  labs(x = "Months relative to legalization", y = "Delinquency rate (pp)") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "none",
        panel.grid.minor = element_blank(),
        plot.background = element_rect(fill = "transparent", color = NA),
        panel.background = element_rect(fill = "transparent", color = NA))

ggsave(file.path(OUT_DIR, "event_study_bjs.png"),
       p, width = 8, height = 4.5, dpi = 200, bg = "transparent")

cat(glue("\nSaved to {OUT_DIR}/"), "\n")
