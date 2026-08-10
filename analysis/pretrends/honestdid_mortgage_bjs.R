#!/usr/bin/env Rscript
################################################################################
# honestdid_mortgage_bjs.R
#
# HonestDiD (Rambachan & Roth 2023) sensitivity analysis applied to the BJS
# imputation event study on the mortgage delinquency panel.
#
# BJS flagged a systematic negative pre-trend (coefficients drift from ~0 at
# k=-12 to -0.14 pp at k=-2). HonestDiD quantifies how robust the post-treatment
# estimates are to plausible extrapolations of that pre-trend.
#
# Two sensitivity classes reported:
#   - Relative magnitudes: post violation <= M * max pre violation
#   - Smoothness: post deviation <= M per period (bounded second differences)
#
# vcov: state-block bootstrap (didimputation has no analytic vcov export)
#
# USAGE:
#   N_BOOT=500 N_WORKERS=4 Rscript analysis/pretrends/honestdid_mortgage_bjs.R
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
  library(HonestDiD)
  library(glue)
})

getenv1 <- function(k, d="") { v <- Sys.getenv(k, unset=d); if(!nzchar(v)) d else v }
parse_int <- function(x, d=NA_integer_) if(!nzchar(x)) d else suppressWarnings(as.integer(x))

state_name_to_abb <- function(state_name) {
  state_name <- trimws(as.character(state_name))
  m <- setNames(state.abb, state.name)
  m <- c(m, "District of Columbia" = "DC")
  unname(m[state_name])
}
ym_index <- function(date) {
  as.integer(as.integer(format(date, "%Y")) * 12L + as.integer(format(date, "%m")))
}

# --- config ---
N_BOOT    <- parse_int(getenv1("N_BOOT", "500"), 500L)
N_WORKERS <- parse_int(getenv1("N_WORKERS", "4"), 4L)
SEED      <- parse_int(getenv1("SEED", "20260417"), 20260417L)

PRE_HORIZONS  <- -12:-2
POST_HORIZONS <- 0:11   # first 12 post months; keeps total params=23 so sigma
                         # stays well-conditioned at moderate bootstrap counts
N_PRE  <- length(PRE_HORIZONS)
N_POST <- length(POST_HORIZONS)

OUT_DIR <- "output/honestdid_mortgage_bjs"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# --- build panel (identical to pretrends pipeline) ---
cat("Building panel...\n")
mort_wide <- read_csv("data/raw/StateMortgagesPercent-90-plusDaysLate-thru-2025-03.csv",
                      show_col_types = FALSE) %>% filter(RegionType == "State")
month_cols <- grep("^\\d{4}-\\d{2}$", colnames(mort_wide), value = TRUE)

mort_long <- mort_wide %>%
  select(Name, all_of(month_cols)) %>%
  pivot_longer(cols = all_of(month_cols), names_to = "month_str",
               values_to = "delinq_pct") %>%
  mutate(state_abb  = state_name_to_abb(Name),
         month_date = as.Date(paste0(month_str, "-01")),
         delinq_pct = as.numeric(delinq_pct)) %>%
  filter(!is.na(state_abb),
         month_date >= as.Date("2016-01-01"),
         month_date <= as.Date("2024-12-31"),
         !(month_date >= as.Date("2020-03-01") & month_date <= as.Date("2021-07-31"))) %>%
  select(state_abb, month_date, delinq_pct)

treat_raw <- read_csv("data/raw/sports_gambling_legalization_dates.csv",
                      show_col_types = FALSE)
treat_sched <- treat_raw %>%
  transmute(state_abb = state_name_to_abb(state),
            treat_start = as.Date(online_start_date)) %>%
  filter(!is.na(state_abb)) %>%
  group_by(state_abb) %>%
  summarise(treat_start = if (all(is.na(treat_start))) as.Date(NA)
                          else min(treat_start, na.rm = TRUE),
            .groups = "drop")

coverage <- mort_long %>% count(state_abb, name = "n_months")
max_cov <- max(coverage$n_months)
keep <- coverage %>% filter(n_months >= max_cov) %>% pull(state_abb)
panel0 <- mort_long %>% filter(state_abb %in% keep)
n_states_pre <- n_distinct(panel0$state_abb)
common <- panel0 %>% count(month_date, name = "n") %>%
  filter(n == n_states_pre) %>% pull(month_date)
panel0 <- panel0 %>% filter(month_date %in% common)

panel <- panel0 %>%
  left_join(treat_sched, by = "state_abb") %>%
  mutate(y = delinq_pct,
         t = ym_index(month_date),
         g = ifelse(is.na(treat_start), 0L, ym_index(treat_start)),
         id = as.integer(as.factor(state_abb)),
         first_treat = ifelse(g == 0L, NA_integer_, g))

all_states <- unique(panel$state_abb)
n_states <- length(all_states)
cat(glue("Panel: {n_states} states, {n_distinct(panel$t)} months, {nrow(panel)} obs"), "\n\n")

# --- single-fit helper returns full event-study coefficient vector ---
fit_bjs_es <- function(p_df, return_errors = FALSE) {
  dat <- as.data.frame(p_df)
  tryCatch({
    res <- did_imputation(
      data = dat, yname = "y", gname = "first_treat",
      tname = "t", idname = "id",
      horizon = POST_HORIZONS, pretrends = PRE_HORIZONS,
      cluster_var = "id"
    )
    res_df <- as.data.frame(res)
    res_df$rel_time <- as.integer(res_df$term)
    ord <- c(PRE_HORIZONS, POST_HORIZONS)
    idx <- match(ord, res_df$rel_time)
    res_df$estimate[idx]
  }, error = function(e) {
    if (return_errors) message("fit error: ", conditionMessage(e))
    rep(NA_real_, N_PRE + N_POST)
  })
}

# --- point estimate ---
cat("Point estimate (full sample)...\n")
t0 <- Sys.time()
betahat <- fit_bjs_es(panel)
cat(glue("Done in {round(as.numeric(difftime(Sys.time(),t0,units='secs')),1)}s"), "\n")
stopifnot(length(betahat) == N_PRE + N_POST, all(is.finite(betahat)))

es_labels <- c(PRE_HORIZONS, POST_HORIZONS)
cat("\nEvent-study point estimates (pp):\n")
print(tibble(rel_time = es_labels, estimate = round(betahat, 4)), n = Inf)

# --- state-block bootstrap for vcov ---
cat(glue("\nState-block bootstrap with {N_BOOT} draws, {N_WORKERS} workers..."), "\n")
set.seed(SEED)
boot_seeds <- sample.int(1e8, N_BOOT)

one_boot <- function(seed) {
  set.seed(seed)
  draw <- sample(all_states, size = n_states, replace = TRUE)
  pieces <- vector("list", n_states)
  for (i in seq_along(draw)) {
    s <- draw[i]
    sub <- panel[panel$state_abb == s, , drop = FALSE]
    sub$id <- i
    pieces[[i]] <- sub
  }
  p <- do.call(rbind, pieces)
  out <- fit_bjs_es(p, return_errors = TRUE)
  if (all(is.na(out))) message("boot seed=", seed, " all NA")
  out
}

t0 <- Sys.time()
cl <- parallel::makeCluster(N_WORKERS, type = "PSOCK")
on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)
invisible(parallel::clusterEvalQ(cl, {
  suppressPackageStartupMessages({
    library(didimputation)
    library(dplyr)
  })
  NULL
}))
parallel::clusterExport(cl, varlist = c("panel", "all_states", "n_states",
                                         "PRE_HORIZONS", "POST_HORIZONS",
                                         "N_PRE", "N_POST", "fit_bjs_es",
                                         "one_boot"),
                         envir = environment())

# run in batches for progress logging
batch_size <- 50L
n_batches <- ceiling(N_BOOT / batch_size)
boot_mat <- matrix(NA_real_, nrow = N_BOOT, ncol = N_PRE + N_POST)

for (b in seq_len(n_batches)) {
  lo <- (b - 1) * batch_size + 1L
  hi <- min(b * batch_size, N_BOOT)
  batch <- parallel::parLapply(cl, boot_seeds[lo:hi], one_boot)
  boot_mat[lo:hi, ] <- do.call(rbind, batch)
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  eta <- elapsed / hi * (N_BOOT - hi)
  cat(glue("  [{hi}/{N_BOOT}] elapsed={round(elapsed)}s, ~{round(eta)}s remaining"), "\n")
}

ok_rows <- apply(boot_mat, 1, function(r) all(is.finite(r)))
cat(glue("\nValid bootstrap draws: {sum(ok_rows)}/{N_BOOT}"), "\n")
boot_mat <- boot_mat[ok_rows, , drop = FALSE]

sigma <- cov(boot_mat)
ses <- sqrt(diag(sigma))
cat("\nBootstrap SEs (compare to BJS analytic):\n")
print(tibble(rel_time = es_labels, estimate = round(betahat, 4),
             se_boot = round(ses, 4)), n = Inf)

saveRDS(list(betahat = betahat, sigma = sigma, es_labels = es_labels,
             N_PRE = N_PRE, N_POST = N_POST, boot_mat = boot_mat),
        file.path(OUT_DIR, "bjs_vcov.rds"))

# --- HonestDiD sensitivity ---

# Average over all post-treatment months in the window
POST_WINDOW <- N_POST
l_vec <- rep(1 / POST_WINDOW, N_POST)

cat(glue("\nBaseline: BJS avg over first {POST_WINDOW} months = {round(sum(l_vec * betahat[(N_PRE+1):(N_PRE+N_POST)]),4)} pp"), "\n")

# Original CI
orig <- constructOriginalCS(betahat = betahat, sigma = sigma,
                            numPrePeriods = N_PRE, numPostPeriods = N_POST,
                            l_vec = l_vec)
cat(glue("Original 95% CI: [{round(orig$lb,4)}, {round(orig$ub,4)}]"), "\n\n")

cat("--- Relative magnitudes sensitivity (post-violation <= M * max pre) ---\n")
Mbar_grid <- c(0, 0.5, 1, 1.5, 2)
sens_rm <- createSensitivityResults_relativeMagnitudes(
  betahat = betahat, sigma = sigma,
  numPrePeriods = N_PRE, numPostPeriods = N_POST,
  l_vec = l_vec, Mbarvec = Mbar_grid
)
print(sens_rm)
write_csv(sens_rm, file.path(OUT_DIR, "sensitivity_relative_magnitudes.csv"))

cat("\n--- Smoothness sensitivity (bounded second differences, M per period) ---\n")
# M values: 0 (linear extrapolation), then small deviations
M_grid <- c(0, 0.005, 0.01, 0.02, 0.05)
sens_sm <- createSensitivityResults(
  betahat = betahat, sigma = sigma,
  numPrePeriods = N_PRE, numPostPeriods = N_POST,
  l_vec = l_vec, Mvec = M_grid
)
print(sens_sm)
write_csv(sens_sm, file.path(OUT_DIR, "sensitivity_smoothness.csv"))

# --- plots ---
p_rm <- createSensitivityPlot_relativeMagnitudes(sens_rm, orig) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(plot.background = ggplot2::element_rect(fill="transparent", color=NA),
                 panel.background = ggplot2::element_rect(fill="transparent", color=NA))
ggsave(file.path(OUT_DIR, "sensitivity_relative_magnitudes.png"),
       p_rm, width = 7, height = 4, dpi = 200, bg = "transparent")

p_sm <- createSensitivityPlot(sens_sm, orig) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(plot.background = ggplot2::element_rect(fill="transparent", color=NA),
                 panel.background = ggplot2::element_rect(fill="transparent", color=NA))
ggsave(file.path(OUT_DIR, "sensitivity_smoothness.png"),
       p_sm, width = 7, height = 4, dpi = 200, bg = "transparent")

# --- breakdown M values ---
cat("\n--- Breakdown thresholds ---\n")
rm_breaks <- sens_rm %>% mutate(contains_zero = lb <= 0 & ub >= 0)
cat("Relative magnitudes:\n")
print(rm_breaks %>% select(Mbar, lb, ub, contains_zero))

sm_breaks <- sens_sm %>% mutate(contains_zero = lb <= 0 & ub >= 0)
cat("Smoothness:\n")
print(sm_breaks %>% select(M, lb, ub, contains_zero))

cat(glue("\nResults saved to {OUT_DIR}/"), "\n")
