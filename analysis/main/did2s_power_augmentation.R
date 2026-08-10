#!/usr/bin/env Rscript
################################################################################
# did2s_power_augmentation.R
#
# Power simulation for did2s (Gardner 2022) on the existing eviction state
# panel, plus three counterfactual augmentation scenarios:
#
#   A: +k synthetic never-treated states
#   B: +k synthetic treated states (with timing drawn from existing cohort dist)
#   C: +k of each
#
# Augmentation uses parametric bootstrap: synthetic state FEs drawn from
# N(mean, sd) of fitted state FEs (with jitter), and residuals resampled by
# month from the never-treated/pre-treatment residual pool. This preserves
# the empirical variance structure while giving distinct synthetic states.
#
# Output:
#   data/output/did2s_power_augmentation/power_results.csv
#   data/output/did2s_power_augmentation/power_curves.pdf
#
# USAGE:
#   N_SIMS=100 N_WORKERS=4 Rscript analysis/main/did2s_power_augmentation.R
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(glue)
  library(fixest)
  library(tibble)
  library(ggplot2)
})

stopifnot(requireNamespace("did2s", quietly = TRUE))
library(did2s)

source("utils/eviction_treatment_schedule.R")

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || !nzchar(as.character(x))) y else x
getenv1 <- function(key, default = "") {
  v <- Sys.getenv(key, unset = default); if (!nzchar(v)) default else v
}
parse_int <- function(x, default = NA_integer_) {
  if (!nzchar(x)) return(default); suppressWarnings(as.integer(x))
}

# ----------------------------- config -----------------------------------------

N_SIMS    <- parse_int(getenv1("N_SIMS", "100"), 100L)
N_WORKERS <- parse_int(getenv1("N_WORKERS", "4"), 4L)
SEED      <- 20260505L
ALPHA     <- 0.05

# Effect sizes in log points (e.g., 0.05 = 5% increase in filings)
EFFECT_SIZES <- c(0, 0.03, 0.05, 0.07, 0.10)

# Augmentation scenarios: (label, n_extra_nt, n_extra_t)
SCENARIOS <- tibble::tribble(
  ~label,           ~n_extra_nt, ~n_extra_t,
  "baseline",                0L,         0L,
  "+5 NT",                   5L,         0L,
  "+10 NT",                 10L,         0L,
  "+5 T",                    0L,         5L,
  "+10 T",                   0L,        10L,
  "+5 NT, +5 T",             5L,         5L,
  "+10 NT, +10 T",          10L,        10L
)

PANEL_FILE     <- "data/raw/state_month_panel_with_treatment.csv"
TREAT_FILE     <- "data/raw/sports_gambling_legalization_dates.csv"
TREAT_DATE_COL <- "online_start_date"
OUT_DIR        <- "data/output/did2s_power_augmentation"

EXCLUDE_STATES <- c("ME")
MIN_DATE       <- as.Date("2016-01-01")
MAX_DATE       <- as.Date("2024-12-31")
DROP_START     <- as.Date("2020-03-01")
DROP_END       <- as.Date("2022-03-31")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

cat("=== did2s POWER + AUGMENTATION ===\n")
cat(glue("N_SIMS={N_SIMS}, N_WORKERS={N_WORKERS}, SEED={SEED}"), "\n")
cat(glue("Effect sizes: {paste(EFFECT_SIZES, collapse=', ')}"), "\n")
cat(glue("Scenarios: {nrow(SCENARIOS)}"), "\n\n")

# ----------------------------- helpers ----------------------------------------

ym_index <- function(date) {
  as.integer(as.integer(format(date, "%Y")) * 12L + as.integer(format(date, "%m")))
}

# ----------------------------- build base panel -------------------------------

cat("Building base panel...\n")
panel0 <- read_csv(PANEL_FILE, show_col_types = FALSE) %>%
  transmute(state_abb = as.character(state_abb),
            month_date = as.Date(month_date),
            filings_count = as.numeric(filings_count)) %>%
  filter(month_date >= MIN_DATE, month_date <= MAX_DATE) %>%
  filter(!(state_abb %in% EXCLUDE_STATES)) %>%
  filter(!(month_date >= DROP_START & month_date <= DROP_END))

coverage   <- panel0 %>% count(state_abb, name = "n_months") %>% arrange(desc(n_months))
max_cov    <- max(coverage$n_months)
keep_states <- coverage %>% filter(n_months >= max_cov) %>% pull(state_abb)
panel0 <- panel0 %>% filter(state_abb %in% keep_states)

n_states_pre  <- n_distinct(panel0$state_abb)
common_months <- panel0 %>% count(month_date, name = "n_states") %>%
  filter(n_states == n_states_pre) %>% pull(month_date)
panel0 <- panel0 %>% filter(month_date %in% common_months)

treat_by_state <- load_eviction_treatment_schedule(
  treat_file = TREAT_FILE, treat_date_col = TREAT_DATE_COL, states = panel0$state_abb)

panel <- panel0 %>%
  left_join(treat_by_state, by = "state_abb") %>%
  mutate(
    y = log1p(pmax(filings_count, 0)),
    t = ym_index(month_date),
    g = ifelse(is.na(treat_start), 0L, ym_index(treat_start)),
    g = as.integer(g),
    id = as.integer(as.factor(state_abb)),
    untreated_obs = (g == 0L) | (t < g)
  )

real_n_states <- n_distinct(panel$state_abb)
real_n_treated <- n_distinct(panel$state_abb[panel$g > 0L])
real_n_never   <- real_n_states - real_n_treated
real_n_months  <- n_distinct(panel$t)

cat(glue("Real panel: {real_n_states} states ({real_n_treated} treated, {real_n_never} never), {real_n_months} months"), "\n")

# ----------------------------- estimate FEs + residual pool -------------------

base_fe <- panel %>% filter(untreated_obs, is.finite(y)) %>% as.data.frame()
fe_fit  <- feols(y ~ 1 | id + t, data = base_fe, warn = FALSE, notes = FALSE)

state_fe <- as.numeric(fixef(fe_fit)$id)
state_fe_mean <- mean(state_fe)
state_fe_sd   <- sd(state_fe)

time_fe_vec <- fixef(fe_fit)$t
time_fe_df  <- tibble(t = as.integer(names(time_fe_vec)),
                       time_fe = as.numeric(time_fe_vec))

base_fe$ehat <- as.numeric(residuals(fe_fit))
resid_pool_by_t <- split(base_fe$ehat, base_fe$t)
global_pool     <- base_fe$ehat[is.finite(base_fe$ehat)]

cat(glue("State FE: mean={round(state_fe_mean, 3)}, sd={round(state_fe_sd, 3)}"), "\n")
cat(glue("Residual pool: {nrow(base_fe)} obs across {length(resid_pool_by_t)} months"), "\n\n")

# ----------------------------- treatment timing distribution ------------------

real_treat_months <- panel %>% filter(g > 0L) %>%
  distinct(state_abb, g) %>% pull(g)

months_vec <- sort(unique(panel$t))

# ----------------------------- augmentation -----------------------------------

augment_panel <- function(real_panel, n_extra_nt, n_extra_t, seed) {
  set.seed(seed)
  if (n_extra_nt == 0L && n_extra_t == 0L) return(real_panel)

  next_id <- max(real_panel$id) + 1L
  rows_synth <- list()

  add_synth_state <- function(new_id, g_new) {
    fe_synth <- rnorm(1, mean = state_fe_mean, sd = state_fe_sd)
    yhat_synth <- fe_synth + time_fe_df$time_fe
    e_synth <- vapply(time_fe_df$t, function(tv) {
      pool <- resid_pool_by_t[[as.character(tv)]]
      if (is.null(pool) || length(pool) < 3L) pool <- global_pool
      sample(pool, 1L)
    }, numeric(1))
    y_synth <- yhat_synth + e_synth
    tibble(
      state_abb     = paste0("S", new_id),
      month_date    = as.Date(NA),
      filings_count = NA_real_,
      treat_start   = if (g_new == 0L) as.Date(NA) else as.Date(NA),
      y             = y_synth,
      t             = time_fe_df$t,
      g             = g_new,
      id            = new_id,
      untreated_obs = (g_new == 0L) | (time_fe_df$t < g_new)
    )
  }

  for (i in seq_len(n_extra_nt)) {
    rows_synth[[length(rows_synth) + 1L]] <- add_synth_state(next_id, 0L)
    next_id <- next_id + 1L
  }

  for (i in seq_len(n_extra_t)) {
    g_new <- as.integer(sample(real_treat_months, 1L))
    rows_synth[[length(rows_synth) + 1L]] <- add_synth_state(next_id, g_new)
    next_id <- next_id + 1L
  }

  bind_rows(real_panel %>% select(state_abb, month_date, filings_count, treat_start,
                                   y, t, g, id, untreated_obs),
            bind_rows(rows_synth))
}

# ----------------------------- single-sim run for did2s -----------------------

draw_y_for_real_panel <- function(real_panel, effect, sim_seed) {
  set.seed(sim_seed)
  e_draw <- vapply(real_panel$t, function(tv) {
    pool <- resid_pool_by_t[[as.character(tv)]]
    if (is.null(pool) || length(pool) < 3L) pool <- global_pool
    sample(pool, 1L)
  }, numeric(1))
  yhat_real <- as.numeric(predict(fe_fit, newdata = as.data.frame(real_panel)))
  post_treat <- as.integer(real_panel$g > 0L & real_panel$t >= real_panel$g)
  yhat_real + e_draw + effect * post_treat
}

apply_effect_to_synth <- function(synth_panel, effect) {
  post_treat <- as.integer(synth_panel$g > 0L & synth_panel$t >= synth_panel$g)
  synth_panel$y + effect * post_treat
}

one_sim <- function(scenario_idx, effect, sim_seed) {
  scen <- SCENARIOS[scenario_idx, ]
  real_with_y <- panel %>% mutate(y = draw_y_for_real_panel(panel, effect, sim_seed)) %>%
    select(state_abb, month_date, filings_count, treat_start, y, t, g, id, untreated_obs)

  full_panel <- augment_panel(real_with_y, scen$n_extra_nt, scen$n_extra_t,
                               seed = bitwXor(sim_seed, scenario_idx * 7919L))

  if (scen$n_extra_t > 0L) {
    full_panel$y <- ifelse(full_panel$id > max(panel$id),
                            apply_effect_to_synth(full_panel, effect),
                            full_panel$y)
  }

  full_panel <- full_panel %>%
    mutate(post_treat = as.integer(g > 0L & t >= g),
           first_treat = ifelse(g == 0L, NA_integer_, g))

  dat <- as.data.frame(full_panel)
  n_clusters <- length(unique(dat$id))

  out <- list(scenario_idx = scenario_idx, scenario_label = scen$label,
              effect = effect, sim_seed = sim_seed, n_clusters = n_clusters)

  tryCatch({
    suppressMessages(suppressWarnings({
      fit <- did2s(data = dat, yname = "y",
                   first_stage = ~ 0 | id + t,
                   second_stage = ~ post_treat,
                   treatment = "post_treat",
                   cluster_var = "id")
      vc  <- stats::vcov(fit)
      att <- as.numeric(coef(fit)[1])
      se  <- sqrt(diag(vc))[1]
      df  <- n_clusters - 1L
      p   <- if (is.finite(att) && is.finite(se) && se > 0)
        2 * stats::pt(-abs(att / se), df = df) else NA_real_
      out$att <- att; out$se <- se; out$p <- p; out$ok <- TRUE
    }))
  }, error = function(e) {
    out$att <<- NA_real_; out$se <<- NA_real_; out$p <<- NA_real_
    out$ok <<- FALSE; out$err <<- conditionMessage(e)
  })

  out
}

# ----------------------------- run all simulations ----------------------------

set.seed(SEED)
sim_grid <- expand_grid(
  scenario_idx = seq_len(nrow(SCENARIOS)),
  effect       = EFFECT_SIZES,
  sim          = seq_len(N_SIMS)
) %>%
  mutate(sim_seed = sample.int(1e8, n()))

n_total <- nrow(sim_grid)
cat(glue("Total simulations: {n_total}"), "\n")
cat(glue("  ({nrow(SCENARIOS)} scenarios x {length(EFFECT_SIZES)} effects x {N_SIMS} sims)"), "\n\n")

run_one <- function(i) {
  row <- sim_grid[i, ]
  one_sim(row$scenario_idx, row$effect, row$sim_seed)
}

t0 <- Sys.time()

if (N_WORKERS > 1L) {
  cat(glue("Starting PSOCK cluster with {N_WORKERS} workers..."), "\n")
  cl <- parallel::makeCluster(N_WORKERS, type = "PSOCK")
  on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)

  parallel::clusterEvalQ(cl, {
    suppressPackageStartupMessages({
      library(dplyr); library(tibble); library(fixest); library(did2s)
    })
    NULL
  })

  parallel::clusterExport(cl,
    varlist = c("panel", "fe_fit", "state_fe_mean", "state_fe_sd",
                "time_fe_df", "resid_pool_by_t", "global_pool",
                "real_treat_months", "SCENARIOS", "augment_panel",
                "draw_y_for_real_panel", "apply_effect_to_synth",
                "one_sim", "sim_grid"),
    envir = environment())

  results_list <- parallel::parLapplyLB(cl, seq_len(n_total), run_one)
} else {
  results_list <- vector("list", n_total)
  for (i in seq_len(n_total)) {
    results_list[[i]] <- run_one(i)
    if (i %% 50L == 0L) {
      cat(glue("  {i}/{n_total} ({round(100*i/n_total)}%)"), "\n")
    }
  }
}

t1 <- Sys.time()
cat(glue("Done in {round(as.numeric(difftime(t1, t0, units='mins')), 1)} min"), "\n\n")

results <- bind_rows(lapply(results_list, function(r) {
  tibble(
    scenario_idx   = r$scenario_idx %||% NA_integer_,
    scenario_label = r$scenario_label %||% NA_character_,
    effect         = r$effect %||% NA_real_,
    sim_seed       = r$sim_seed %||% NA_integer_,
    n_clusters     = r$n_clusters %||% NA_integer_,
    att            = r$att %||% NA_real_,
    se             = r$se %||% NA_real_,
    p              = r$p %||% NA_real_,
    ok             = r$ok %||% FALSE
  )
}))

# ----------------------------- aggregate to power curves ----------------------

power_summary <- results %>%
  filter(ok) %>%
  group_by(scenario_idx, scenario_label, effect, n_clusters) %>%
  summarise(
    n_valid     = n(),
    rejection   = mean(p < ALPHA, na.rm = TRUE),
    mean_att    = mean(att, na.rm = TRUE),
    sd_att      = sd(att, na.rm = TRUE),
    mean_se     = mean(se, na.rm = TRUE),
    se_over_sd  = mean(se, na.rm = TRUE) / sd(att, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(scenario_idx, effect)

write_csv(power_summary, file.path(OUT_DIR, "power_summary.csv"))
write_csv(results,        file.path(OUT_DIR, "sim_results.csv"))

cat("Power summary:\n")
print(power_summary, n = Inf)
cat("\n")

# ----------------------------- plot -------------------------------------------

scen_levels <- SCENARIOS$label
power_summary$scenario_label <- factor(power_summary$scenario_label,
                                         levels = scen_levels)

p <- ggplot(power_summary,
            aes(x = effect * 100, y = rejection,
                color = scenario_label, linetype = scenario_label,
                shape = scenario_label)) +
  geom_hline(yintercept = 0.80, linetype = "dotted", color = "grey40") +
  geom_hline(yintercept = 0.05, linetype = "dotted", color = "grey40") +
  geom_line(linewidth = 0.6) +
  geom_point(size = 2) +
  scale_color_grey(start = 0.0, end = 0.7) +
  scale_shape_manual(values = c(16, 17, 15, 18, 1, 2, 0)) +
  scale_x_continuous(breaks = EFFECT_SIZES * 100) +
  scale_y_continuous(breaks = seq(0, 1, 0.2), limits = c(0, 1)) +
  labs(x = "Effect size (log points, %)",
       y = "Rejection rate",
       color = NULL, linetype = NULL, shape = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "right",
        panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background  = element_rect(fill = "transparent", color = NA))

ggsave(file.path(OUT_DIR, "power_curves.pdf"),
       plot = p, width = 7, height = 4.5, bg = "transparent")
ggsave(file.path(OUT_DIR, "power_curves.png"),
       plot = p, width = 7, height = 4.5, dpi = 200, bg = "white")

cat(glue("Wrote: {file.path(OUT_DIR, 'power_summary.csv')}"), "\n")
cat(glue("       {file.path(OUT_DIR, 'sim_results.csv')}"), "\n")
cat(glue("       {file.path(OUT_DIR, 'power_curves.pdf')}"), "\n")
cat(glue("       {file.path(OUT_DIR, 'power_curves.png')}"), "\n")
