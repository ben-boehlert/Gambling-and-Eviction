#!/usr/bin/env Rscript
################################################################################
# did2s_power_cleaned_monthly.R
#
# did2s power simulation on the monthly ETS panel with surgical drops of
# verified bad observations (cross-validated against updated annual court data).
#
# Bad observations dropped:
#   - ID 2016-01 to 2016-07: ETS rollout undercount (9-28 filings/mo vs ~100/mo
#     after July 2016; court data has zero ID coverage 2016 to confirm directly,
#     but within-state pattern is clearly a ramp-up)
#   - CT 2016-01 to 2016-02: 186, 208 filings vs ~1,200/mo norm (county dropouts;
#     court data shows CT 2016 annual = 21,480 vs ETS sum 12,716 — significant
#     undercount, with Jan-Feb the worst months)
#   - UT 2023-11 to 2023-12: 49, 81 filings vs ~700/mo norm (UT 2023 annual sums
#     match court data 7252 vs 7307, so these months are mis-allocated by ETS)
#
# Output:
#   data/output/did2s_power_cleaned_monthly/
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

OUT_DIR <- "data/output/did2s_power_cleaned_monthly"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

cat("=== did2s POWER ON CLEANED MONTHLY PANEL ===\n")
cat(glue("N_SIMS={N_SIMS}, N_WORKERS={N_WORKERS}"), "\n\n")

ym_index <- function(d) as.integer(as.integer(format(d,"%Y"))*12 + as.integer(format(d,"%m")))

bad_obs <- tibble::tribble(
  ~state_abb, ~month_date,
  "ID","2016-01-01","ID","2016-02-01","ID","2016-03-01","ID","2016-04-01",
  "ID","2016-05-01","ID","2016-06-01","ID","2016-07-01",
  "CT","2016-01-01","CT","2016-02-01",
  "UT","2023-11-01","UT","2023-12-01"
) |> mutate(month_date = as.Date(month_date))

cat("Surgical drops (", nrow(bad_obs), "obs):\n"); print(bad_obs); cat("\n")

build_monthly <- function(drop_bad = TRUE,
                           min_date = as.Date("2016-01-01"),
                           max_date = as.Date("2024-12-31"),
                           drop_start = as.Date("2020-03-01"),
                           drop_end   = as.Date("2022-03-31")) {
  raw <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                  show_col_types=FALSE) |>
    transmute(state_abb=as.character(state_abb),
              month_date=as.Date(month_date),
              filings_count=as.numeric(filings_count)) |>
    filter(month_date >= min_date, month_date <= max_date,
           state_abb != "ME") |>
    filter(!(month_date >= drop_start & month_date <= drop_end))

  if (drop_bad) raw <- raw |> anti_join(bad_obs, by=c("state_abb","month_date"))

  cov <- raw |> count(state_abb, name="n") |> arrange(desc(n))
  keep <- cov |> filter(n == max(n)) |> pull(state_abb)
  raw <- raw |> filter(state_abb %in% keep)
  n_pre <- n_distinct(raw$state_abb)
  common <- raw |> count(month_date, name="n") |> filter(n == n_pre) |> pull(month_date)
  raw <- raw |> filter(month_date %in% common)

  treat <- load_eviction_treatment_schedule(
    treat_file="data/raw/sports_gambling_legalization_dates.csv",
    treat_date_col="online_start_date", states=raw$state_abb)
  raw |> left_join(treat, by="state_abb") |>
    mutate(y = log1p(pmax(filings_count,0)),
           t = ym_index(month_date),
           g = ifelse(is.na(treat_start), 0L, ym_index(treat_start)),
           g = as.integer(g),
           id = as.integer(as.factor(state_abb)),
           untreated_obs = (g == 0L) | (t < g))
}

run_power <- function(panel, label) {
  n_states  <- n_distinct(panel$state_abb)
  n_treated <- n_distinct(panel$state_abb[panel$g > 0L])
  n_periods <- n_distinct(panel$t)
  cat(glue("[{label}] {n_states} states ({n_treated} treated), {n_periods} months, {nrow(panel)} obs"), "\n")

  base_fe <- panel |> filter(untreated_obs, is.finite(y)) |> as.data.frame()
  fe_fit  <- feols(y ~ 1 | id + t, data=base_fe, warn=FALSE, notes=FALSE)
  panel$yhat <- as.numeric(predict(fe_fit, newdata=as.data.frame(panel)))
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
    dat <- data.frame(id=panel$id, t=panel$t, g=panel$g,
                      y=y_sim, post_treat=post_treat)
    out <- list(att=NA_real_, se=NA_real_, p=NA_real_, ok=FALSE)
    tryCatch({
      suppressMessages(suppressWarnings({
        fit <- did2s(data=dat, yname="y", first_stage = ~ 0 | id + t,
                     second_stage = ~ post_treat, treatment="post_treat",
                     cluster_var="id")
        att <- as.numeric(coef(fit)[1])
        se  <- sqrt(diag(stats::vcov(fit)))[1]
        p   <- if (is.finite(att) && is.finite(se) && se > 0)
                 2*stats::pt(-abs(att/se), df=n_states-1L) else NA_real_
        out$att <- att; out$se <- se; out$p <- p
        out$ok <- is.finite(att) && is.finite(se)
      }))
    }, error = function(e) {})
    out
  }

  sim_grid <- expand_grid(effect=EFFECT_SIZES, sim=seq_len(N_SIMS)) |>
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
  s <- results |> filter(ok) |> group_by(effect) |>
    summarise(n_valid=n(), rejection=mean(p<ALPHA, na.rm=TRUE),
              mean_att=mean(att,na.rm=TRUE), sd_att=sd(att,na.rm=TRUE),
              mean_se=mean(se,na.rm=TRUE),
              se_over_sd=mean(se,na.rm=TRUE)/sd(att,na.rm=TRUE),
              .groups="drop") |>
    mutate(spec=label, n_states=n_states, n_treated=n_treated, n_periods=n_periods)
  print(s |> select(effect, rejection, sd_att, mean_se, se_over_sd))
  cat("\n")
  s
}

set.seed(SEED)
panel_raw   <- build_monthly(drop_bad = FALSE)
panel_clean <- build_monthly(drop_bad = TRUE)

# Tighter window cleaned (combines clean + 2018-2024 window)
panel_tight_clean <- build_monthly(drop_bad = TRUE,
                                    min_date = as.Date("2018-01-01"))

# Cleaned + shorter COVID drop
panel_clean_short_covid <- build_monthly(drop_bad = TRUE,
                                          drop_start = as.Date("2020-03-01"),
                                          drop_end = as.Date("2020-12-31"))

all_results <- list(
  run_power(panel_raw,   "raw monthly (baseline)"),
  run_power(panel_clean, "+ surgical drops (Fix 1)"),
  run_power(panel_clean_short_covid, "+ Fix 1 + 10-mo COVID drop"),
  run_power(panel_tight_clean, "+ Fix 1 + 2018-2024 window")
)
power_summary <- bind_rows(all_results)
write_csv(power_summary, file.path(OUT_DIR, "power_summary.csv"))

cat("=== FULL SUMMARY ===\n")
print(power_summary |>
  select(spec, effect, rejection, sd_att, se_over_sd, n_states, n_treated, n_periods),
  n=Inf)

power_summary <- power_summary |>
  mutate(spec = factor(spec, levels = unique(spec)))

p <- ggplot(power_summary, aes(x=effect*100, y=rejection,
                               color=spec, linetype=spec, shape=spec)) +
  geom_hline(yintercept=0.80, linetype="dotted", color="grey40") +
  geom_hline(yintercept=0.05, linetype="dotted", color="grey40") +
  geom_line(linewidth=0.6) + geom_point(size=2) +
  scale_color_grey(start=0, end=0.7) +
  scale_x_continuous(breaks=EFFECT_SIZES*100) +
  scale_y_continuous(breaks=seq(0,1,0.2), limits=c(0,1)) +
  labs(x="Effect size (log points, %)", y="Rejection rate",
       color=NULL, linetype=NULL, shape=NULL) +
  theme_minimal(base_size=11) +
  theme(legend.position="right",
        panel.grid.minor=element_blank(),
        panel.grid.major.x=element_blank(),
        panel.background=element_rect(fill="transparent",color=NA),
        plot.background=element_rect(fill="transparent",color=NA))

ggsave(file.path(OUT_DIR, "power_curves.pdf"), plot=p,
       width=8, height=4.5, bg="transparent")
ggsave(file.path(OUT_DIR, "power_curves.png"), plot=p,
       width=8, height=4.5, dpi=200, bg="white")

# Save cleaned panel for downstream use
write_csv(panel_clean |> select(state_abb, month_date, filings_count, treat_start),
          file.path(OUT_DIR, "monthly_panel_cleaned.csv"))

cat("\nWrote:", file.path(OUT_DIR, "power_summary.csv"), "\n")
cat("       ", file.path(OUT_DIR, "power_curves.pdf"), "\n")
cat("       ", file.path(OUT_DIR, "monthly_panel_cleaned.csv"), "\n")
