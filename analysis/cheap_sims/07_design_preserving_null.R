#!/usr/bin/env Rscript
################################################################################
# analysis/cheap_sims/07_design_preserving_null.R
#
# Design-preserving re-verification of the oracle null SD (BHNS point: simulated
# power can depend materially on how pseudo-treatment and untreated data are
# constructed).
#
# Everything about the DESIGN is held fixed at its real value: treated states,
# online legalization dates, cohort structure, per-state coverage/missingness,
# COVID-dropped months, and therefore the C&S ATT(g,t) cell set and aggregation
# weights. Only the UNTREATED outcome process varies across replications.
#
# Untreated model, estimated on genuinely untreated observations only
# (never-treated states + treated states before first_start - 6):
#     y_log1p_st = alpha_s + gamma_t + eps_st
# Simulated outcome: y*_st = alpha_s + gamma_t + eps*_st, with eps* from one of
# three generators preserving serial correlation:
#
#   G1 donor_blocks : calendar-aligned 24-month blocks; each block's residuals
#                     come from a randomly drawn full-coverage never-treated
#                     donor state (COVID-era blocks are actual COVID-era
#                     untreated residuals; cross-block donor mixing avoids
#                     whole-path duplication).
#   G2 own_blocks   : moving-block bootstrap (24 mo, wrapped) of the state's
#                     OWN untreated residuals. Deliberate lower bound: early-
#                     treated states' pools predate COVID volatility.
#   G3 ar1          : Gaussian AR(1); pooled AR coefficient, state-specific
#                     innovation SD from own untreated residuals.
#
# Delta = 0 throughout; the target is the null SD of the full-design ATT (and
# subsets). Verdict standard (user's): if full-ATT null SD remains ~0.10-0.15
# across sensible generators, the information conclusion stands.
#
# Env: N_DP_REPS (250), N_CORES, BLOCK_MONTHS (24).
# Run from repo root:  Rscript analysis/cheap_sims/07_design_preserving_null.R
################################################################################

source("analysis/cheap_sims/00_common.R")
suppressPackageStartupMessages({library(parallel); library(fixest)})
theme_set(theme_minimal())

cfg <- cheap_config()
N_DP_REPS <- .cs_envint("N_DP_REPS", 250L)
N_CORES   <- .cs_envint("N_CORES", max(1L, parallel::detectCores() - 2L))
BLOCK_M   <- .cs_envint("BLOCK_MONTHS", 24L)
SCENARIO  <- 904L

out_dir <- file.path(cfg$out_dir, "design_preserving")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

pan <- readRDS(file.path(cfg$out_dir, "design_panel.rds"))

# ---- fixed real-design frame ------------------------------------------------

frame0 <- pan$design %>%
  filter(!covid_m) %>%
  left_join(pan$states %>% select(state_abb, censor_month), by = "state_abb") %>%
  transmute(unit_id = state_abb, state_abb, month_date,
            y_obs = y_log1p, pseudo_g = online_g,
            untreated_obs = is.na(censor_month) | month_date < censor_month)
tkey <- .month_idx(frame0$month_date)
frame0$t <- as.integer(tkey - min(tkey) + 1L)

# ---- untreated two-way FE model --------------------------------------------

unt <- frame0 %>% filter(untreated_obs)
fe_fit <- feols(y_obs ~ 1 | state_abb + month_date, data = unt)
fes <- fixef(fe_fit)
alpha <- tibble(state_abb = names(fes$state_abb), alpha = as.numeric(fes$state_abb))
gamma <- tibble(month_date = as.Date(names(fes$month_date)),
                gamma = as.numeric(fes$month_date))
unt$resid <- resid(fe_fit)

cat(sprintf("untreated model: %d obs, %d states, %d months | resid SD = %.3f\n",
            nrow(unt), n_distinct(unt$state_abb), n_distinct(unt$month_date),
            sd(unt$resid)))

frame0 <- frame0 %>%
  left_join(alpha, by = "state_abb") %>%
  left_join(gamma, by = "month_date") %>%
  mutate(y_base = alpha + gamma)
stopifnot(!anyNA(frame0$y_base))

months_all <- sort(unique(frame0$month_date))

# donor pool: full-coverage never-treated states (calendar-complete paths)
donors <- pan$states %>%
  filter(is.na(g_first), first_obs <= as.Date("2016-06-01"),
         last_obs >= as.Date("2025-06-01")) %>% pull(state_abb)
donor_resid <- unt %>% filter(state_abb %in% donors) %>%
  select(state_abb, month_date, resid)
cat(sprintf("donor pool (G1): %s\n", paste(donors, collapse = ", ")))

# calendar blocks: consecutive observed months in chunks of BLOCK_M
block_id <- tibble(month_date = months_all,
                   block = (seq_along(months_all) - 1L) %/% BLOCK_M)
donor_wide <- donor_resid %>% left_join(block_id, by = "month_date")

# per-state own residual pools / AR params
own_pool <- unt %>% arrange(state_abb, month_date) %>%
  group_by(state_abb) %>% summarise(r = list(resid), .groups = "drop")
rho_pool <- {
  d <- unt %>% arrange(state_abb, month_date) %>% group_by(state_abb) %>%
    mutate(l1 = lag(resid)) %>% ungroup() %>% filter(!is.na(l1))
  coef(lm(resid ~ 0 + l1, data = d))[[1]]
}
sig_state <- unt %>% group_by(state_abb) %>%
  summarise(sig = sd(resid), .groups = "drop")
cat(sprintf("pooled AR(1) rho = %.3f | median state resid SD = %.3f\n",
            rho_pool, median(sig_state$sig)))

# ---- residual-path generators ----------------------------------------------

# G1: for each recipient state x calendar block, draw a donor observing every
# needed month of the block (TX is calendar-complete, so >=1 always exists).
gen_donor_blocks <- function(fr) {
  need <- fr %>% select(state_abb, month_date) %>%
    mutate(i = row_number()) %>%
    left_join(block_id, by = "month_date")
  out <- need %>%
    group_by(state_abb, block) %>%
    group_modify(function(d, k) {
      elig <- donor_wide %>% filter(block == k$block) %>%
        semi_join(d, by = "month_date") %>%
        count(state_abb) %>% filter(n == nrow(d)) %>% pull(state_abb)
      dn <- if (length(elig)) sample(elig, 1L) else "TX"
      dr <- donor_wide %>% filter(state_abb == dn) %>%
        select(month_date, resid)
      d %>% left_join(dr, by = "month_date") %>%
        mutate(resid = ifelse(is.na(resid), 0, resid))
    }) %>% ungroup() %>% arrange(i)
  out$resid
}

# G2: wrapped moving-block bootstrap of the state's own untreated residuals.
gen_own_blocks <- function(fr) {
  fr %>% select(state_abb) %>% mutate(i = row_number()) %>%
    group_by(state_abb) %>%
    group_modify(function(d, k) {
      r <- own_pool$r[[match(k$state_abb, own_pool$state_abb)]]
      L <- length(r); n <- nrow(d); b <- min(BLOCK_M, L)
      idx <- integer(0)
      while (length(idx) < n) {
        s <- sample.int(L, 1L)
        idx <- c(idx, ((s - 1L + 0:(b - 1L)) %% L) + 1L)
      }
      d$resid <- r[idx[seq_len(n)]]
      d
    }) %>% ungroup() %>% arrange(i) %>% pull(resid)
}

# G3: Gaussian AR(1), pooled rho, state-specific innovation SD.
gen_ar1 <- function(fr) {
  fr %>% select(state_abb) %>% mutate(i = row_number()) %>%
    group_by(state_abb) %>%
    group_modify(function(d, k) {
      sig <- sig_state$sig[match(k$state_abb, sig_state$state_abb)]
      if (!is.finite(sig) || sig <= 0) sig <- median(sig_state$sig)
      n <- nrow(d)
      innov_sd <- sig * sqrt(1 - rho_pool^2)
      e <- numeric(n); e[1] <- rnorm(1, 0, sig)
      for (j in seq_len(n - 1L)) e[j + 1L] <- rho_pool * e[j] + rnorm(1, 0, innov_sd)
      d$resid <- e
      d
    }) %>% ungroup() %>% arrange(i) %>% pull(resid)
}

GENS <- list(donor_blocks = gen_donor_blocks,
             own_blocks   = gen_own_blocks,
             ar1          = gen_ar1)

# ---- one replication --------------------------------------------------------

fr_sorted <- frame0 %>% arrange(state_abb, month_date)

one_rep <- function(rep, gen_name) {
  set.seed(cfg$base_seed + 10007L * rep + 101L * SCENARIO +
             1000003L * match(gen_name, names(GENS)))
  fr <- fr_sorted
  fr$y_sim <- fr$y_base + GENS[[gen_name]](fr)
  fr$delta_imposed <- 0
  cs <- tryCatch(suppressMessages(suppressWarnings(fit_cs(fr))),
                 error = function(e) NULL)
  if (is.null(cs)) return(tibble(rep = rep, generator = gen_name,
                                 design = "full", att = NA_real_,
                                 converged = FALSE))
  aggregate_covid_subsets(cs, fr, cfg) %>%
    mutate(rep = rep, generator = gen_name, converged = is.finite(att))
}

RAW <- file.path(out_dir, "design_preserving_raw.csv")
done <- if (file.exists(RAW))
  suppressMessages(read_csv(RAW, show_col_types = FALSE)) %>%
    distinct(rep, generator) else tibble(rep = integer(0), generator = character(0))
grid <- crossing(rep = seq_len(N_DP_REPS), generator = names(GENS)) %>%
  anti_join(done, by = c("rep", "generator"))
cat(sprintf("running %d rep x generator cells on %d cores\n", nrow(grid), N_CORES))

t0 <- Sys.time()
batches <- split(seq_len(nrow(grid)), ceiling(seq_len(nrow(grid)) / (2L * N_CORES)))
for (bi in seq_along(batches)) {
  b <- batches[[bi]]
  res <- mclapply(b, function(i)
    tryCatch(one_rep(grid$rep[i], grid$generator[i]), error = function(e)
      tibble(rep = grid$rep[i], generator = grid$generator[i], design = "full",
             att = NA_real_, converged = FALSE)),
    mc.cores = N_CORES, mc.preschedule = FALSE)
  ok <- vapply(res, is.data.frame, logical(1))
  res <- bind_rows(res[ok])
  write_csv(res, RAW, append = file.exists(RAW))
  cat(sprintf("[batch %d/%d] %.1f min elapsed\n", bi, length(batches),
              as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}

# ---- summary ----------------------------------------------------------------

all <- suppressMessages(read_csv(RAW, show_col_types = FALSE)) %>%
  filter(converged, design != "full_didsimple")

summ <- all %>%
  group_by(generator, design) %>%
  summarise(n = n(), mean_att = mean(att), sd_att = sd(att),
            mc_se_sd = sd(att) / sqrt(2 * (n() - 1)),   # approx SE of an SD
            mean_se = mean(se), se_over_sd = mean(se) / sd(att),
            reject_05 = mean(p < cfg$alpha, na.rm = TRUE), .groups = "drop")
write_csv(summ, file.path(out_dir, "design_preserving_summary.csv"))

cat("\n===== DESIGN-PRESERVING NULL SD (real treated states/dates/weights) =====\n")
print(as.data.frame(summ %>% arrange(design, generator)),
      row.names = FALSE, digits = 3)

full_sd <- summ %>% filter(design == "full") %>% select(generator, sd_att)
cat("\nFull-design null SD by generator (verdict band 0.10-0.15):\n")
print(as.data.frame(full_sd), row.names = FALSE, digits = 3)
cat("\nReference points: calendar-preserving placebo 0.140;",
    "balanced 6-state placebo 0.307.\n")
cat(sprintf("Total %.1f min\n",
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))
