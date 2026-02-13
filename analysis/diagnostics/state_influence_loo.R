#!/usr/bin/env Rscript
################################################################################
# state_influence_loo.R
#
# Leave-one-out (LOO) influence diagnostic: drop each state in turn,
# re-estimate TWFE (post_treat indicator) and Sun-Abraham (dynamic),
# measure how much the ATT moves.
#
# Answers: "Is one or two states driving the entire effect?"
#
# Usage:
#   Rscript analysis/diagnostics/state_influence_loo.R
#   OUTCOME=log1p_rate Rscript analysis/diagnostics/state_influence_loo.R
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
  library(ggplot2)
  library(fixest)
  library(glue)
  library(patchwork)
})

# ---- helpers ----
getenv1 <- function(key, default = "") {
  v <- Sys.getenv(key, unset = default)
  if (!nzchar(v)) default else v
}
parse_bool <- function(x, default = FALSE) {
  if (!nzchar(x)) return(default)
  toupper(trimws(x)) %in% c("1", "TRUE", "T", "YES", "Y")
}
parse_chr_list <- function(x, default = character()) {
  if (!nzchar(x)) return(default)
  trimws(strsplit(x, ",", fixed = TRUE)[[1]])
}
parse_date <- function(x, default = as.Date(NA)) {
  if (!nzchar(x)) return(default)
  out <- suppressWarnings(as.Date(x))
  if (is.na(out)) default else out
}
parse_num <- function(x, default = NA_real_) {
  if (!nzchar(x)) return(default)
  suppressWarnings(as.numeric(x))
}
parse_int <- function(x, default = NA_integer_) {
  if (!nzchar(x)) return(default)
  suppressWarnings(as.integer(x))
}
ym_index <- function(date) {
  as.integer(as.integer(format(date, "%Y")) * 12L + as.integer(format(date, "%m")))
}

# ---- configuration ----
PANEL_FILE     <- getenv1("PANEL_FILE", "data/raw/state_month_panel_with_treatment.csv")
EXCLUDE_STATES <- parse_chr_list(getenv1("EXCLUDE_STATES", "ME"))
MIN_DATE       <- as.Date(getenv1("MIN_DATE", "2016-01-01"))
MAX_DATE       <- as.Date(getenv1("MAX_DATE", "2024-12-31"))
DROP_START     <- parse_date(getenv1("DROP_START", ""))
DROP_END       <- parse_date(getenv1("DROP_END", ""))
COVERAGE_THRESHOLD_RAW <- getenv1("COVERAGE_THRESHOLD", "")
COVERAGE_THRESHOLD <- if (nzchar(COVERAGE_THRESHOLD_RAW)) {
  parse_int(COVERAGE_THRESHOLD_RAW, 0L)
} else {
  NA_integer_
}
BALANCE_COMMON_MONTHS <- parse_bool(getenv1("BALANCE_COMMON_MONTHS", "TRUE"), TRUE)
OUTCOME        <- getenv1("OUTCOME", "log1p_filings_count")
RATE_EPS       <- parse_num(getenv1("RATE_EPS", "0.01"), 0.01)
OUT_DIR        <- getenv1("OUT_DIR", "output/state_influence_loo")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

cat("=== State Influence (Leave-One-Out) ===\n")
cat("PANEL_FILE:", PANEL_FILE, "\n")
cat("EXCLUDE_STATES:", paste(EXCLUDE_STATES, collapse = ","), "\n")
cat("MIN_DATE:", as.character(MIN_DATE), " MAX_DATE:", as.character(MAX_DATE), "\n")
cat("OUTCOME:", OUTCOME, "\n")
cat("OUT_DIR:", OUT_DIR, "\n\n")

if (!file.exists(PANEL_FILE)) stop("PANEL_FILE not found: ", PANEL_FILE, call. = FALSE)

################################################################################
# LOAD AND PREPARE PANEL (same restrictions as pretrends pipeline)
################################################################################

panel0 <- read_csv(PANEL_FILE, show_col_types = FALSE) %>%
  transmute(
    state_abb = as.character(state_abb),
    month_date = as.Date(month_date),
    treat_start = as.Date(treat_start),
    filings_count = as.numeric(filings_count),
    renter_occupied_housing_units = as.numeric(renter_occupied_housing_units),
    filings_per_1k_renters = as.numeric(filings_per_1k_renters)
  )

if (length(EXCLUDE_STATES) > 0) panel0 <- panel0 %>% filter(!(state_abb %in% EXCLUDE_STATES))
if (!is.na(MIN_DATE)) panel0 <- panel0 %>% filter(month_date >= MIN_DATE)
if (!is.na(MAX_DATE)) panel0 <- panel0 %>% filter(month_date <= MAX_DATE)

if (xor(is.na(DROP_START), is.na(DROP_END))) {
  stop("If setting DROP_START or DROP_END, set both.", call. = FALSE)
}
if (!is.na(DROP_START) && !is.na(DROP_END)) {
  panel0 <- panel0 %>% filter(!(month_date >= DROP_START & month_date <= DROP_END))
}

coverage <- panel0 %>% count(state_abb, name = "n_months") %>% arrange(desc(n_months))
max_coverage <- max(coverage$n_months, na.rm = TRUE)
if (!is.finite(COVERAGE_THRESHOLD)) COVERAGE_THRESHOLD <- max_coverage

keep_states <- coverage %>% filter(n_months >= COVERAGE_THRESHOLD) %>% pull(state_abb)
panel <- panel0 %>% filter(state_abb %in% keep_states)

treat_by_state <- panel %>%
  group_by(state_abb) %>%
  summarise(
    treat_start_state = if (all(is.na(treat_start))) as.Date(NA) else min(treat_start, na.rm = TRUE),
    .groups = "drop"
  )
panel <- panel %>% left_join(treat_by_state, by = "state_abb")

if (isTRUE(BALANCE_COMMON_MONTHS)) {
  n_st <- n_distinct(panel$state_abb)
  common <- panel %>% count(month_date, name = "ns") %>% filter(ns == n_st) %>% pull(month_date)
  panel <- panel %>% filter(month_date %in% common)
}

panel <- panel %>%
  mutate(
    id = as.integer(as.factor(state_abb)),
    t = ym_index(month_date),
    g = ifelse(is.na(treat_start_state), 0L, ym_index(treat_start_state)),
    g = as.integer(g),
    post_treat = as.integer(g > 0L & t >= g),
    event_time = ifelse(g > 0L, t - g, NA_integer_),
    filings_per_1k_renters = if_else(
      is.finite(filings_per_1k_renters), filings_per_1k_renters,
      if_else(is.finite(renter_occupied_housing_units) & renter_occupied_housing_units > 0 & is.finite(filings_count),
              1000 * filings_count / renter_occupied_housing_units, NA_real_)
    ),
    y = dplyr::case_when(
      OUTCOME == "log1p_filings_count" ~ log1p(pmax(filings_count, 0)),
      OUTCOME == "log1p_rate" ~ log(pmax(filings_per_1k_renters, 0) + RATE_EPS),
      TRUE ~ NA_real_
    )
  )

n_states <- n_distinct(panel$state_abb)
all_states <- sort(unique(panel$state_abb))
treated_states <- sort(unique(panel$state_abb[panel$g > 0L]))
never_states <- setdiff(all_states, treated_states)

cat(glue("Panel: {n_states} states ({length(treated_states)} treated, {length(never_states)} never-treated), {nrow(panel)} obs"), "\n\n")

################################################################################
# BASELINE MODELS (full sample)
################################################################################

cat("Estimating baseline models...\n")

# TWFE: simple post-treatment indicator
base_twfe <- feols(y ~ post_treat | id + t, data = panel, cluster = ~id, warn = FALSE, notes = FALSE)
base_att <- coef(base_twfe)["post_treat"]
base_se <- se(base_twfe)["post_treat"]
cat(glue("  Baseline TWFE ATT = {round(base_att, 5)} (SE = {round(base_se, 5)})"), "\n")

# Sun-Abraham: dynamic
base_sa <- tryCatch(
  feols(y ~ sunab(g, t) | id + t, data = panel, cluster = ~id, warn = FALSE, notes = FALSE),
  error = function(e) { cat("  SunAb baseline failed:", conditionMessage(e), "\n"); NULL }
)

if (!is.null(base_sa)) {
  # Overall ATT from SunAb (aggregate post-treatment coefficients)
  sa_coefs <- coef(base_sa)
  sa_names <- names(sa_coefs)
  event_times <- suppressWarnings(as.integer(gsub(".*::", "", sa_names)))
  post_idx <- which(!is.na(event_times) & event_times >= 0)
  sa_att_post <- mean(sa_coefs[post_idx], na.rm = TRUE)
  cat(glue("  Baseline SunAb mean post ATT = {round(sa_att_post, 5)} ({length(post_idx)} post coefficients)"), "\n")
}

################################################################################
# LEAVE-ONE-OUT: DROP EACH STATE
################################################################################

cat(glue("\nRunning leave-one-out across {n_states} states...\n"))

loo_results <- lapply(all_states, function(drop_st) {
  dat_loo <- panel %>% filter(state_abb != drop_st)
  is_treated <- drop_st %in% treated_states
  n_remaining <- n_distinct(dat_loo$state_abb)

  # Need to recompute id for feols (must be contiguous)
  dat_loo <- dat_loo %>% mutate(id_loo = as.integer(as.factor(state_abb)))

  # TWFE
  twfe_res <- tryCatch({
    mod <- feols(y ~ post_treat | id_loo + t, data = dat_loo, cluster = ~id_loo, warn = FALSE, notes = FALSE)
    tibble(att = coef(mod)["post_treat"], se = se(mod)["post_treat"])
  }, error = function(e) tibble(att = NA_real_, se = NA_real_))

  # SunAb
  sa_res <- tryCatch({
    mod <- feols(y ~ sunab(g, t) | id_loo + t, data = dat_loo, cluster = ~id_loo, warn = FALSE, notes = FALSE)
    sc <- coef(mod)
    sn <- names(sc)
    et <- suppressWarnings(as.integer(gsub(".*::", "", sn)))
    pidx <- which(!is.na(et) & et >= 0)
    tibble(att_post = mean(sc[pidx], na.rm = TRUE), n_post_coefs = length(pidx))
  }, error = function(e) tibble(att_post = NA_real_, n_post_coefs = NA_integer_))

  # State-level descriptives
  st_data <- panel %>% filter(state_abb == drop_st)
  mean_y <- mean(st_data$y, na.rm = TRUE)
  n_obs_st <- nrow(st_data)
  n_post <- sum(st_data$post_treat, na.rm = TRUE)

  tibble(
    state_abb = drop_st,
    treated = is_treated,
    n_remaining = n_remaining,
    n_obs_state = n_obs_st,
    n_post_obs = n_post,
    mean_y = mean_y,
    twfe_att_loo = twfe_res$att,
    twfe_se_loo = twfe_res$se,
    sa_att_post_loo = sa_res$att_post
  )
})

loo_df <- bind_rows(loo_results) %>%
  mutate(
    twfe_influence = base_att - twfe_att_loo,
    twfe_pct_change = 100 * twfe_influence / abs(base_att),
    sa_influence = sa_att_post - sa_att_post_loo,
    sa_pct_change = 100 * sa_influence / abs(sa_att_post)
  ) %>%
  arrange(desc(abs(twfe_influence)))

cat("\n=== LOO Results (sorted by |TWFE influence|) ===\n")
print(
  loo_df %>%
    select(state_abb, treated, twfe_att_loo, twfe_influence, twfe_pct_change,
           sa_att_post_loo, sa_influence, sa_pct_change) %>%
    mutate(across(where(is.numeric), ~ round(.x, 5))),
  n = 50
)

# Flag states with outsized influence (> 20% change in ATT)
big_influence <- loo_df %>% filter(abs(twfe_pct_change) > 20)
if (nrow(big_influence) > 0) {
  cat("\n!! States with > 20% TWFE influence:\n")
  print(big_influence %>% select(state_abb, treated, twfe_influence, twfe_pct_change), n = 20)
} else {
  cat("\nNo single state shifts the TWFE ATT by more than 20%.\n")
}

################################################################################
# CUMULATIVE INFLUENCE: PROGRESSIVELY DROP MOST INFLUENTIAL
################################################################################

cat("\n=== Cumulative Drop (most influential first) ===\n")

ranked <- loo_df %>% arrange(desc(abs(twfe_influence))) %>% pull(state_abb)

cumul_results <- list()
cumul_results[[1]] <- tibble(
  n_dropped = 0L, dropped = "", att = base_att, se = base_se,
  n_states = n_states, n_obs = nrow(panel)
)

drop_set <- character()
for (i in seq_along(ranked)) {
  drop_set <- c(drop_set, ranked[i])
  dat_cum <- panel %>%
    filter(!(state_abb %in% drop_set)) %>%
    mutate(id_cum = as.integer(as.factor(state_abb)))

  n_treated_left <- n_distinct(dat_cum$state_abb[dat_cum$g > 0L])
  if (n_treated_left < 2 || n_distinct(dat_cum$state_abb) < 5) break

  cum_mod <- tryCatch({
    feols(y ~ post_treat | id_cum + t, data = dat_cum, cluster = ~id_cum, warn = FALSE, notes = FALSE)
  }, error = function(e) NULL)

  if (!is.null(cum_mod)) {
    cumul_results[[length(cumul_results) + 1]] <- tibble(
      n_dropped = length(drop_set),
      dropped = paste(drop_set, collapse = ","),
      att = coef(cum_mod)["post_treat"],
      se = se(cum_mod)["post_treat"],
      n_states = n_distinct(dat_cum$state_abb),
      n_obs = nrow(dat_cum)
    )
  }

  if (length(drop_set) >= 10) break  # stop after top 10
}

cumul_df <- bind_rows(cumul_results)
cat("Cumulative drop (most influential first):\n")
print(cumul_df %>% mutate(across(where(is.numeric), ~ round(.x, 5))), n = 15)

################################################################################
# TREATED-STATE CONTRIBUTION: INDIVIDUAL ATTs
################################################################################

cat("\n=== Per-State Treatment Effect (treated states only) ===\n")

state_att <- lapply(treated_states, function(st) {
  st_data <- panel %>% filter(state_abb == st)
  pre <- st_data %>% filter(post_treat == 0)
  post <- st_data %>% filter(post_treat == 1)

  if (nrow(pre) == 0 || nrow(post) == 0) {
    return(tibble(state_abb = st, mean_pre = NA_real_, mean_post = NA_real_,
                  raw_diff = NA_real_, n_pre = 0L, n_post = 0L,
                  treat_start = as.Date(NA)))
  }

  tibble(
    state_abb = st,
    mean_pre = mean(pre$y, na.rm = TRUE),
    mean_post = mean(post$y, na.rm = TRUE),
    raw_diff = mean(post$y, na.rm = TRUE) - mean(pre$y, na.rm = TRUE),
    n_pre = nrow(pre),
    n_post = nrow(post),
    treat_start = min(st_data$treat_start_state, na.rm = TRUE)
  )
})

state_att_df <- bind_rows(state_att) %>% arrange(raw_diff)
cat("State-level raw pre/post differences (no controls, just descriptive):\n")
print(state_att_df %>% mutate(across(where(is.numeric), ~ round(.x, 4))), n = 50)

################################################################################
# PLOTS
################################################################################

cat("\nGenerating plots...\n")

base_theme <- theme_minimal(base_size = 12)

# Plot 1: LOO influence bar chart (TWFE)
p1 <- loo_df %>%
  mutate(
    state_abb = factor(state_abb, levels = state_abb[order(twfe_influence)]),
    fill_col = ifelse(treated, "Treated", "Never-treated")
  ) %>%
  ggplot(aes(x = state_abb, y = twfe_influence, fill = fill_col)) +
  geom_col(width = 0.7) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
  coord_flip() +
  scale_fill_manual(values = c("Treated" = "steelblue", "Never-treated" = "gray60")) +
  base_theme +
  labs(
    title = "Leave-One-Out Influence on TWFE ATT",
    subtitle = glue("Baseline ATT = {round(base_att, 4)} | Influence = baseline - LOO estimate"),
    x = NULL, y = "Influence (change in ATT when state is dropped)",
    fill = "Status"
  )
ggsave(file.path(OUT_DIR, "loo_influence_twfe.png"), p1, width = 10, height = max(6, n_states * 0.22), dpi = 300)

# Plot 2: LOO ATT estimates (forest plot style)
p2 <- loo_df %>%
  mutate(
    state_abb = factor(state_abb, levels = state_abb[order(twfe_att_loo)]),
    fill_col = ifelse(treated, "Treated", "Never-treated")
  ) %>%
  ggplot(aes(x = twfe_att_loo, y = state_abb, color = fill_col)) +
  geom_point(size = 2) +
  geom_errorbarh(aes(xmin = twfe_att_loo - 1.96 * twfe_se_loo,
                     xmax = twfe_att_loo + 1.96 * twfe_se_loo), height = 0.3) +
  geom_vline(xintercept = base_att, linetype = "solid", color = "red", linewidth = 0.8) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "gray40") +
  scale_color_manual(values = c("Treated" = "steelblue", "Never-treated" = "gray60")) +
  base_theme +
  labs(
    title = "TWFE ATT Estimates — Dropping Each State",
    subtitle = glue("Red line = full-sample ATT ({round(base_att, 4)})"),
    x = "ATT Estimate", y = NULL, color = "Status"
  )
ggsave(file.path(OUT_DIR, "loo_forest_twfe.png"), p2, width = 10, height = max(6, n_states * 0.22), dpi = 300)

# Plot 3: Cumulative drop
if (nrow(cumul_df) > 1) {
  p3 <- cumul_df %>%
    ggplot(aes(x = n_dropped, y = att)) +
    geom_ribbon(aes(ymin = att - 1.96 * se, ymax = att + 1.96 * se), alpha = 0.2, fill = "steelblue") +
    geom_line(color = "steelblue", linewidth = 1) +
    geom_point(size = 2, color = "steelblue") +
    geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
    geom_text(aes(label = ifelse(n_dropped > 0, gsub(".*,", "", dropped), "")),
              vjust = -1, size = 3, color = "gray30") +
    base_theme +
    labs(
      title = "Cumulative State Dropping (Most Influential First)",
      subtitle = "Labels show the last state dropped at each step",
      x = "Number of States Dropped", y = "TWFE ATT Estimate"
    )
  ggsave(file.path(OUT_DIR, "cumulative_drop.png"), p3, width = 10, height = 6, dpi = 300)
}

# Plot 4: Raw pre/post differences by treated state
if (nrow(state_att_df) > 0) {
  p4 <- state_att_df %>%
    filter(!is.na(raw_diff)) %>%
    mutate(state_abb = factor(state_abb, levels = state_abb[order(raw_diff)])) %>%
    ggplot(aes(x = state_abb, y = raw_diff)) +
    geom_col(fill = "steelblue", width = 0.7) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
    geom_hline(yintercept = mean(state_att_df$raw_diff, na.rm = TRUE),
               linetype = "dotted", color = "darkgreen", linewidth = 0.8) +
    coord_flip() +
    base_theme +
    labs(
      title = "Raw Pre/Post Difference by Treated State",
      subtitle = glue("Green dotted = mean across states ({round(mean(state_att_df$raw_diff, na.rm=TRUE), 4)}) | No controls, descriptive only"),
      x = NULL, y = "Mean Post - Mean Pre (log outcome)"
    )
  ggsave(file.path(OUT_DIR, "state_raw_diff.png"), p4, width = 10, height = max(6, length(treated_states) * 0.3), dpi = 300)
}

################################################################################
# SAVE OUTPUTS
################################################################################

write_csv(loo_df, file.path(OUT_DIR, "loo_results.csv"))
write_csv(cumul_df, file.path(OUT_DIR, "cumulative_drop.csv"))
write_csv(state_att_df, file.path(OUT_DIR, "state_raw_diffs.csv"))

# Summary statistics
sd_influence <- sd(loo_df$twfe_influence, na.rm = TRUE)
max_influence_state <- loo_df$state_abb[which.max(abs(loo_df$twfe_influence))]
max_influence_val <- max(abs(loo_df$twfe_influence), na.rm = TRUE)
hhi <- sum((loo_df$twfe_influence / sum(abs(loo_df$twfe_influence), na.rm = TRUE))^2, na.rm = TRUE)

summary_df <- tibble(
  baseline_att = base_att,
  baseline_se = base_se,
  n_states = n_states,
  n_treated = length(treated_states),
  max_influence_state = max_influence_state,
  max_influence_value = max_influence_val,
  max_pct_change = max(abs(loo_df$twfe_pct_change), na.rm = TRUE),
  sd_influence = sd_influence,
  influence_hhi = hhi,
  range_loo_att = diff(range(loo_df$twfe_att_loo, na.rm = TRUE)),
  outcome = OUTCOME
)
write_csv(summary_df, file.path(OUT_DIR, "summary.csv"))

cat("\n=== Summary ===\n")
cat(glue("Baseline ATT: {round(base_att, 5)}"), "\n")
cat(glue("Most influential state: {max_influence_state} (influence = {round(max_influence_val, 5)}, {round(max(abs(loo_df$twfe_pct_change), na.rm=TRUE), 1)}% of ATT)"), "\n")
cat(glue("LOO ATT range: [{round(min(loo_df$twfe_att_loo, na.rm=TRUE), 5)}, {round(max(loo_df$twfe_att_loo, na.rm=TRUE), 5)}]"), "\n")
cat(glue("Influence HHI: {round(hhi, 4)} (lower = more dispersed; 1/{n_states} = {round(1/n_states, 4)} if uniform)"), "\n")
cat(glue("Output: {OUT_DIR}"), "\n")
