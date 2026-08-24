################################################################################
# analysis/diagnostics/lpdid_weights_paired_compare.R
#
# How much did the 2026-08-24 LP-DiD reweighting correction move the numbers?
#
# Pairs a pre-fix run (cell weights 1/Var_cell(D), the "cellsize" estimand)
# against its post-fix twin (1/(1 - Dbar_cell), the paper's EWATT). The two
# share base_seed and every other setting, so panels are identical rep for rep
# and the only difference is the weight vector.
#
# Env: PRE, POST (run names), OUT_DIR.
# Working directory: repository root.
################################################################################

suppressPackageStartupMessages({library(dplyr); library(readr); library(tidyr)})

getenv1 <- function(k, d) { v <- Sys.getenv(k); if (nzchar(v)) v else d }
PRE     <- getenv1("PRE",  "lpdid_shift12_gate_noNV")
POST    <- getenv1("POST", "lpdid_shift12_gate_ewatt")
OUT_DIR <- getenv1("OUT_DIR", "output/lpdid_weights_compare")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

rd <- function(run, file) {
  p <- file.path("output_blinded_power", run, file)
  if (!file.exists(p)) return(NULL)
  read_csv(p, show_col_types = FALSE)
}

# ---- size / operating characteristics ---------------------------------------
keys <- c("name", "estimator", "inference", "delta")
oc <- bind_rows(
  rd(PRE,  "oc_summary.csv") %>% mutate(weights = "cellsize (pre-fix)"),
  rd(POST, "oc_summary.csv") %>% mutate(weights = "ewatt (corrected)"))

if (!is.null(oc) && nrow(oc) > 0) {
  cmp <- oc %>%
    select(all_of(keys), weights, n_reps, reject_005, se_sd_ratio, sd_att,
           mean_se, coverage, bias) %>%
    pivot_wider(names_from = weights,
                values_from = c(n_reps, reject_005, se_sd_ratio, sd_att,
                                mean_se, coverage, bias)) %>%
    arrange(name, estimator, inference, delta)
  write_csv(cmp, file.path(OUT_DIR, "oc_paired.csv"))

  cat("\n=== SIZE at alpha = 0.05 (delta = 0 rows) ===\n")
  size <- oc %>% filter(delta == 0) %>%
    select(name, estimator, inference, weights, n_reps, reject_005,
           se_sd_ratio) %>%
    arrange(name, estimator, inference, weights)
  print(as.data.frame(size), row.names = FALSE, digits = 4)
  cat("\nGate is 0.075. Binomial 95% CI half-width at p = .06, n = 2000 is ~.010.\n")
}

# ---- MDE --------------------------------------------------------------------
mde <- bind_rows(
  rd(PRE,  "mde_table.csv") %>% mutate(weights = "cellsize (pre-fix)"),
  rd(POST, "mde_table.csv") %>% mutate(weights = "ewatt (corrected)"))

if (!is.null(mde) && nrow(mde) > 0) {
  write_csv(mde, file.path(OUT_DIR, "mde_paired.csv"))
  cat("\n=== MDE ===\n")
  cols <- intersect(c("name", "estimator", "inference", "weights", "mde",
                      "mde_lo", "mde_hi", "status"), names(mde))
  print(as.data.frame(mde[, cols]), row.names = FALSE, digits = 4)
}

cat("\nOutputs ->", OUT_DIR, "\n")
