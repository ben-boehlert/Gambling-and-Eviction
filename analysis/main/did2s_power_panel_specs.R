#!/usr/bin/env Rscript
################################################################################
# did2s_power_panel_specs.R
#
# How does panel specification affect did2s power?
#
# Tests the same did2s estimator across panel specs that vary in:
#   - Sample window (start/end dates)
#   - COVID handling (drop full / drop short / keep all)
#
# Each spec is auto-balanced to common months.
#
# Output:
#   data/output/did2s_power_panel_specs/spec_summary.csv
#   data/output/did2s_power_panel_specs/power_results.csv
#   data/output/did2s_power_panel_specs/power_curves.pdf
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr); library(glue)
  library(fixest); library(tibble); library(ggplot2); library(did2s)
})

source("utils/eviction_treatment_schedule.R")

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || !nzchar(as.character(x))) y else x
getenv1 <- function(key, default = "") { v <- Sys.getenv(key, unset = default); if (!nzchar(v)) default else v }
parse_int <- function(x, default = NA_integer_) { if (!nzchar(x)) return(default); suppressWarnings(as.integer(x)) }

N_SIMS    <- parse_int(getenv1("N_SIMS", "100"), 100L)
N_WORKERS <- parse_int(getenv1("N_WORKERS", "4"), 4L)
SEED      <- 20260505L
ALPHA     <- 0.05
EFFECT_SIZES <- c(0, 0.03, 0.05, 0.07, 0.10)

PANEL_FILE <- "data/raw/state_month_panel_with_treatment.csv"
TREAT_FILE <- "data/raw/sports_gambling_legalization_dates.csv"
OUT_DIR    <- "data/output/did2s_power_panel_specs"

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# Panel specs to compare
SPECS <- tibble::tribble(
  ~label,                              ~min_date,     ~max_date,     ~drop_start,    ~drop_end,
  "baseline: 2016-2024, drop COVID 24mo",  "2016-01-01",  "2024-12-31",  "2020-03-01",  "2022-03-31",
  "moratorium drop only (2020-03 to 2021-06)", "2016-01-01",  "2024-12-31",  "2020-03-01",  "2021-06-30",
  "shorter COVID drop (2020-03 to 2020-12)",   "2016-01-01",  "2024-12-31",  "2020-03-01",  "2020-12-31",
  "no COVID drop",                              "2016-01-01",  "2024-12-31",  NA,            NA,
  "pre-COVID only (2016-2020-02)",              "2016-01-01",  "2020-02-29",  NA,            NA,
  "extend later (2016-2025-06, drop COVID)",    "2016-01-01",  "2025-06-30",  "2020-03-01",  "2022-03-31",
  "tighter window (2018-2024, drop COVID)",     "2018-01-01",  "2024-12-31",  "2020-03-01",  "2022-03-31"
)

cat("=== did2s POWER ACROSS PANEL SPECS ===\n")
cat(glue("N_SIMS={N_SIMS}, N_WORKERS={N_WORKERS}"), "\n\n")

ym_index <- function(date) {
  as.integer(as.integer(format(date, "%Y")) * 12L + as.integer(format(date, "%m")))
}

build_panel <- function(min_date, max_date, drop_start, drop_end, exclude_states = c("ME")) {
  raw <- read_csv(PANEL_FILE, show_col_types = FALSE) |>
    transmute(state_abb = as.character(state_abb),
              month_date = as.Date(month_date),
              filings_count = as.numeric(filings_count)) |>
    filter(month_date >= as.Date(min_date), month_date <= as.Date(max_date)) |>
    filter(!(state_abb %in% exclude_states))

  if (!is.na(drop_start) && !is.na(drop_end)) {
    raw <- raw |> filter(!(month_date >= as.Date(drop_start) & month_date <= as.Date(drop_end)))
  }

  cov <- raw |> count(state_abb, name="n") |> arrange(desc(n))
  keep <- cov |> filter(n == max(n)) |> pull(state_abb)
  raw  <- raw |> filter(state_abb %in% keep)
  n_pre <- n_distinct(raw$state_abb)
  common <- raw |> count(month_date, name="n") |> filter(n == n_pre) |> pull(month_date)
  raw |> filter(month_date %in% common)
}

prep_panel <- function(p0) {
  treat_by_state <- load_eviction_treatment_schedule(
    treat_file = TREAT_FILE, treat_date_col = "online_start_date",
    states = p0$state_abb)
  p0 |>
    left_join(treat_by_state, by = "state_abb") |>
    mutate(
      y = log1p(pmax(filings_count, 0)),
      t = ym_index(month_date),
      g0 = ifelse(is.na(treat_start), 0L, ym_index(treat_start)),
      # Treat as never-treated if treatment falls outside sample window
      g = ifelse(g0 == 0L | g0 > max(t) | g0 < min(t), 0L, g0),
      g = as.integer(g),
      id = as.integer(as.factor(state_abb)),
      untreated_obs = (g == 0L) | (t < g)
    )
}

# ----------------------------- per-spec power ---------------------------------

run_spec <- function(spec_label, panel) {
  n_states  <- n_distinct(panel$state_abb)
  n_treated <- n_distinct(panel$state_abb[panel$g > 0L])
  n_never   <- n_states - n_treated
  n_months  <- n_distinct(panel$t)

  cat(glue("[{spec_label}] {n_states} states ({n_treated} treated, {n_never} never), {n_months} months, {nrow(panel)} obs"), "\n")

  if (n_treated < 2L || n_never < 2L) {
    cat("  -> Skipping: insufficient treated or control variation\n\n")
    return(NULL)
  }

  base_fe <- panel |> filter(untreated_obs, is.finite(y)) |> as.data.frame()
  fe_fit  <- feols(y ~ 1 | id + t, data = base_fe, warn=FALSE, notes=FALSE)
  panel$yhat <- as.numeric(predict(fe_fit, newdata = as.data.frame(panel)))
  panel <- panel |> filter(is.finite(yhat))

  base_fe$ehat <- as.numeric(residuals(fe_fit))
  resid_pool_by_t <- split(base_fe$ehat, base_fe$t)
  global_pool <- base_fe$ehat[is.finite(base_fe$ehat)]

  one_sim <- function(sim_seed, effect) {
    set.seed(sim_seed)
    e_draw <- vapply(panel$t, function(tv) {
      pool <- resid_pool_by_t[[as.character(tv)]]
      if (is.null(pool) || length(pool) < 3L) pool <- global_pool
      sample(pool, 1L)
    }, numeric(1))
    post_treat <- as.integer(panel$g > 0L & panel$t >= panel$g)
    y_sim <- panel$yhat + e_draw + effect * post_treat
    dat <- data.frame(id = panel$id, t = panel$t, g = panel$g,
                       y = y_sim, post_treat = post_treat)
    out <- list(att=NA_real_, se=NA_real_, p=NA_real_, ok=FALSE)
    tryCatch({
      suppressMessages(suppressWarnings({
        fit <- did2s(data=dat, yname="y", first_stage = ~ 0 | id + t,
                     second_stage = ~ post_treat, treatment="post_treat",
                     cluster_var="id")
        att <- as.numeric(coef(fit)[1])
        se  <- sqrt(diag(stats::vcov(fit)))[1]
        df  <- n_states - 1L
        p   <- if (is.finite(att) && is.finite(se) && se > 0)
                 2 * stats::pt(-abs(att/se), df=df) else NA_real_
        out$att <- att; out$se <- se; out$p <- p; out$ok <- is.finite(att) && is.finite(se)
      }))
    }, error = function(e) {})
    out
  }

  sim_grid <- expand_grid(
    effect = EFFECT_SIZES,
    sim    = seq_len(N_SIMS)
  ) |>
    mutate(sim_seed = sample.int(1e8, n()))

  if (N_WORKERS > 1L) {
    cl <- parallel::makeCluster(N_WORKERS, type="PSOCK")
    on.exit(try(parallel::stopCluster(cl), silent=TRUE), add=TRUE)
    parallel::clusterEvalQ(cl, suppressPackageStartupMessages({
      library(dplyr); library(fixest); library(did2s)
    }))
    parallel::clusterExport(cl,
      varlist=c("panel","resid_pool_by_t","global_pool","n_states","one_sim"),
      envir=environment())
    res <- parallel::parLapplyLB(cl, seq_len(nrow(sim_grid)), function(i) {
      r <- one_sim(sim_grid$sim_seed[i], sim_grid$effect[i])
      list(effect=sim_grid$effect[i], att=r$att, se=r$se, p=r$p, ok=r$ok)
    })
  } else {
    res <- lapply(seq_len(nrow(sim_grid)), function(i) {
      r <- one_sim(sim_grid$sim_seed[i], sim_grid$effect[i])
      list(effect=sim_grid$effect[i], att=r$att, se=r$se, p=r$p, ok=r$ok)
    })
  }

  results <- bind_rows(lapply(res, as_tibble))

  summary_tbl <- results |>
    filter(ok) |>
    group_by(effect) |>
    summarise(n_valid=n(),
              rejection=mean(p < ALPHA, na.rm=TRUE),
              mean_att=mean(att, na.rm=TRUE),
              sd_att=sd(att, na.rm=TRUE),
              mean_se=mean(se, na.rm=TRUE),
              se_over_sd=mean(se, na.rm=TRUE)/sd(att, na.rm=TRUE),
              .groups="drop") |>
    mutate(spec=spec_label, n_states=n_states, n_treated=n_treated,
           n_never=n_never, n_months=n_months, n_obs=nrow(panel))

  print(summary_tbl |> select(effect, rejection, mean_att, sd_att, mean_se, se_over_sd))
  cat("\n")
  summary_tbl
}

# ----------------------------- run all specs ----------------------------------

set.seed(SEED)
all_results <- list()
spec_meta <- list()

for (i in seq_len(nrow(SPECS))) {
  spec <- SPECS[i, ]
  t0 <- Sys.time()
  panel <- build_panel(spec$min_date, spec$max_date, spec$drop_start, spec$drop_end)
  panel <- prep_panel(panel)
  res <- run_spec(spec$label, panel)
  if (!is.null(res)) {
    all_results[[length(all_results)+1L]] <- res
    spec_meta[[length(spec_meta)+1L]] <- res |>
      distinct(spec, n_states, n_treated, n_never, n_months, n_obs)
  }
  cat(glue("  ({round(as.numeric(difftime(Sys.time(),t0,units='mins')),1)} min)"), "\n\n")
}

power_summary <- bind_rows(all_results)
spec_table    <- bind_rows(spec_meta) |> distinct()

write_csv(power_summary, file.path(OUT_DIR, "power_results.csv"))
write_csv(spec_table,    file.path(OUT_DIR, "spec_summary.csv"))

cat("=== SPEC TABLE ===\n")
print(spec_table)
cat("\n=== POWER SUMMARY ===\n")
print(power_summary |> select(spec, effect, rejection, sd_att, se_over_sd, n_states, n_treated, n_months), n=Inf)

# ----------------------------- plot -------------------------------------------

power_summary <- power_summary |>
  mutate(spec = factor(spec, levels = SPECS$label[SPECS$label %in% unique(spec)]))

p <- ggplot(power_summary,
            aes(x = effect*100, y = rejection,
                color = spec, linetype = spec, shape = spec)) +
  geom_hline(yintercept = 0.80, linetype="dotted", color="grey40") +
  geom_hline(yintercept = 0.05, linetype="dotted", color="grey40") +
  geom_line(linewidth = 0.6) +
  geom_point(size = 2) +
  scale_color_grey(start = 0, end = 0.75) +
  scale_shape_manual(values = c(16, 17, 15, 18, 1, 2, 0)) +
  scale_x_continuous(breaks = EFFECT_SIZES * 100) +
  scale_y_continuous(breaks = seq(0,1,0.2), limits = c(0,1)) +
  labs(x = "Effect size (log points, %)", y = "Rejection rate",
       color=NULL, linetype=NULL, shape=NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "right",
        legend.text = element_text(size = 8),
        panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        panel.background = element_rect(fill = "transparent", color = NA),
        plot.background = element_rect(fill = "transparent", color = NA))

ggsave(file.path(OUT_DIR, "power_curves.pdf"), plot = p,
       width = 8, height = 4.5, bg = "transparent")
ggsave(file.path(OUT_DIR, "power_curves.png"), plot = p,
       width = 8, height = 4.5, dpi = 200, bg = "white")

cat("\nWrote:", file.path(OUT_DIR, "power_results.csv"), "\n")
cat("       ", file.path(OUT_DIR, "power_curves.pdf"), "\n")
