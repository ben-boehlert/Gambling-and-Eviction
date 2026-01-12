#!/usr/bin/env Rscript
################################################################################
# test_power_simulation_cs_ets_merged_v5style_properties.R
#
# Property tests that should NOT SKIP:
#   - Power at effect=0 is ~ alpha (Type I error sanity check)
#   - Power increases with effect size (strong check using large effects)
#   - Power weakly increases with more states (nested subsets; weakly, with tolerance)
#   - MDE is weakly decreasing with more states for a *reachable* target (auto-chosen)
#
# Run:
#   /usr/local/R/4.4.2/bin/Rscript --vanilla test_power_simulation_cs_ets_merged_v5style_properties.R
################################################################################

suppressPackageStartupMessages({
  library(glue)
  library(readr)
  library(dplyr)
})

here <- normalizePath(getwd())
main <- file.path(here, "power_simulation_cs_ets_merged_v5style.R")
data <- file.path(here, "merged_ets_combined.csv")

if (!file.exists(main)) stop(glue("Missing main script: {main}"), call. = FALSE)
if (!file.exists(data)) stop(glue("Missing data file: {data}"), call. = FALSE)

rscript <- Sys.which("Rscript")
if (!nzchar(rscript)) stop("Rscript not found on PATH.", call. = FALSE)

interp_mde <- function(effect_log, power, target) {
  o <- order(effect_log)
  effect_log <- effect_log[o]
  power <- power[o]
  if (length(power) == 0) return(NA_real_)
  if (all(is.na(power))) return(NA_real_)
  if (max(power, na.rm = TRUE) < target) return(NA_real_)
  j <- which(power >= target)[1]
  if (is.na(j)) return(NA_real_)
  if (j == 1) return(effect_log[1])
  x0 <- effect_log[j-1]; x1 <- effect_log[j]
  y0 <- power[j-1]; y1 <- power[j]
  if (!is.finite(y0) || !is.finite(y1) || (y1 - y0) == 0) return(effect_log[j])
  x0 + (target - y0) * (x1 - x0) / (y1 - y0)
}

run_sub <- function(label, env, out_dir) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out <- system2(
    rscript,
    args = c("--vanilla", main),
    env = env,
    stdout = TRUE,
    stderr = TRUE
  )
  status <- attr(out, "status"); if (is.null(status)) status <- 0L
  writeLines(out, file.path(out_dir, paste0(label, ".captured.log")))

  cat(glue("\n=== {label} exit={status} ===\n"))
  cat(paste(out, collapse = "\n"), "\n")

  if (!identical(as.integer(status), 0L)) {
    fatal <- file.path(out_dir, "power_FATAL_ERROR.txt")
    if (file.exists(fatal)) {
      cat("\n---- power_FATAL_ERROR.txt ----\n")
      cat(paste(readLines(fatal, warn = FALSE), collapse = "\n"), "\n")
    }
    stop(glue("{label} failed (exit {status})"), call. = FALSE)
  }
}

tmp <- file.path(tempdir(), paste0("cs_power_props_", format(Sys.time(), "%Y%m%d_%H%M%S")))
dir.create(tmp, recursive = TRUE, showWarnings = FALSE)

out <- file.path(tmp, "props")

# IMPORTANT: use BIG effects so power definitely moves (so tests don't "skip")
# Keep TEST_MODE=TRUE but set N_SIMS to 200 (clamp happens only if huge).
env <- c(
  glue("DATA_FILE={data}"),
  glue("OUT_DIR={out}"),
  "DRY_RUN=FALSE",
  "TEST_MODE=TRUE",
  "N_SIMS=200",
  # multiple n_states so we can test monotonicity
  "GRID_N_STATES=8,10,12,14",
  # big enough effects to guarantee a power gradient (unit test; not your final grid)
  "EFFECT_PCTS=0,0.10,0.20,0.30,0.40",
  "MAKE_HEATMAP=TRUE",
  "SAVE_DRAWS=TRUE",
  "DID_BSTRAP=FALSE",
  "DID_BITERS=0",
  "DID_EST_METHOD=ipw"
)

run_sub("properties", env, out)

pwr <- readr::read_csv(file.path(out, "power_by_effect.csv"), show_col_types = FALSE)

need <- c("n_states","effect_pct","effect_log","power","alpha","fail_rate","n_sims","mean_est")
miss <- setdiff(need, names(pwr))
if (length(miss) > 0) stop(glue("Missing columns in power_by_effect.csv: {paste(miss, collapse=', ')}"), call. = FALSE)

# --- Basic "not all zero power" / bug-detection checks ---
alpha <- unique(pwr$alpha)
alpha <- alpha[is.finite(alpha)][1]
if (!is.finite(alpha)) stop("alpha missing/invalid.", call. = FALSE)

# Type I error check: at effect=0, power should be ~alpha (within a wide tolerance; MC noise + estimator quirks)
p0 <- pwr %>% filter(abs(effect_pct) < 1e-12) %>% summarise(p0 = mean(power, na.rm = TRUE)) %>% pull(p0)
if (!is.finite(p0)) stop("power at effect=0 is missing/NA (bug).", call. = FALSE)
if (abs(p0 - alpha) > 0.10) {
  print(pwr %>% filter(abs(effect_pct) < 1e-12) %>% arrange(n_states))
  stop(glue("Type I error sanity check failed: power(effect=0)={round(p0,3)} not within 0.10 of alpha={round(alpha,3)}."), call. = FALSE)
} else {
  cat(glue("PASS: Type I error sanity check: power(effect=0)={round(p0,3)} ~ alpha={round(alpha,3)}.\n"))
}

# Strong power check: at max effect, average power should exceed p0 by at least 0.05
pmax <- pwr %>%
  group_by(n_states) %>%
  summarise(p_big = power[which.max(effect_pct)],
            p0 = power[which.min(effect_pct)],
            .groups = "drop")

if (any(!is.finite(pmax$p_big))) stop("Missing power at max effect (bug).", call. = FALSE)

if (mean(pmax$p_big - pmax$p0, na.rm = TRUE) < 0.05) {
  print(pmax)
  stop("Power is not increasing at large effects (could be a bug, or estimator always returning p=1).", call. = FALSE)
} else {
  cat("PASS: Power increases at large effects.\n")
}

# Fail-rate sanity: if estimator fails constantly, power can be 0 due to p=1 fallback
if (mean(pwr$fail_rate, na.rm = TRUE) > 0.50) {
  print(pwr %>% arrange(desc(fail_rate)) %>% head(20))
  stop("Estimator fail_rate is too high (>0.50 on average).", call. = FALSE)
} else {
  cat("PASS: Fail rate is not extreme.\n")
}

# --- Monotonicity test 1: power weakly increases with n_states at each effect (tolerant) ---
tol_power <- 0.08  # allow MC noise
mono_bad <- pwr %>%
  group_by(effect_pct) %>%
  arrange(n_states, .by_group = TRUE) %>%
  summarise(min_diff = min(diff(power), na.rm = TRUE), .groups = "drop") %>%
  filter(is.finite(min_diff) & min_diff < -tol_power)

if (nrow(mono_bad) > 0) {
  print(mono_bad)
  stop("Power is not weakly increasing in n_states at some effect sizes (beyond tolerance).", call. = FALSE)
} else {
  cat("PASS: Power is weakly increasing in n_states (within tolerance).\n")
}

# --- Monotonicity test 2: MDE weakly decreases with n_states (auto target that is reachable for ALL n_states) ---
max_by_n <- pwr %>% group_by(n_states) %>% summarise(max_power = max(power, na.rm = TRUE), .groups = "drop")
min_max <- min(max_by_n$max_power, na.rm = TRUE)

# Choose a target that is definitely reachable at *every* n_states.
# If even the smallest max_power is low, this target will be low too; that's fine for a regression test.
target <- min(0.50, min_max - 0.02)
if (!is.finite(target) || target <= 0) target <- min_max * 0.8
if (!is.finite(target) || target <= 0) stop("Could not construct a valid MDE target.", call. = FALSE)

mde_tbl <- pwr %>%
  group_by(n_states) %>%
  summarise(
    mde_log = interp_mde(effect_log, power, target = target),
    mde_pct = if_else(is.na(mde_log), NA_real_, expm1(mde_log)),
    max_power = max(power, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(n_states)

if (any(!is.finite(mde_tbl$mde_pct))) {
  print(mde_tbl)
  stop("MDE is NA/inf for some n_states even though target should be reachable.", call. = FALSE)
}

diffs <- diff(mde_tbl$mde_pct)
if (any(diffs > 1e-8)) {
  print(mde_tbl)
  stop(glue("MDE is not weakly decreasing in n_states (target={round(target,3)})."), call. = FALSE)
} else {
  cat(glue("PASS: MDE weakly decreases with n_states (target={round(target,3)}).\n"))
}

# Heatmap existence
hm <- file.path(out, "power_heatmap.png")
if (!file.exists(hm)) stop("Expected power_heatmap.png but did not find it.", call. = FALSE)
cat("PASS: Heatmap written.\n")

# Draws example exists and has variation in p-values (not all 1's)
draws_csv <- file.path(out, "draws_example.csv")
if (!file.exists(draws_csv)) stop("Expected draws_example.csv but did not find it.", call. = FALSE)
draws <- readr::read_csv(draws_csv, show_col_types = FALSE)
if (!("p" %in% names(draws))) stop("draws_example.csv missing p column.", call. = FALSE)
if (all(abs(draws$p - 1) < 1e-12)) stop("All p-values are 1.0 in draws_example.csv (bug / always-fail).", call. = FALSE)
cat("PASS: draws_example.csv has non-trivial p-values.\n")

cat(glue("\nAll property tests passed. Outputs are in: {tmp}\n"))
