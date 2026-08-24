################################################################################
# analysis/diagnostics/lpdid_official_crosscheck.R
#
# Cross-validate .re_lpdid (ewatt, pmd = 1) against the AUTHORS' reference
# implementation: Daniele Girardi's LP_DiD_R_example_EW.R from
# https://github.com/danielegirardi/lpdid (23 Feb 2026 version), run on the
# Stata package's own test dataset (lpdidtestdata1.dta, downloaded from the
# SSC/BC mirror at runtime -- requires network).
#
# Their per-horizon recipe: first-lag differencing (D{h}y = lead(Y,h) -
# lag(Y,1)), clean controls via F{h}_treat == 0, auxiliary regression of
# D_treat on time FE, weights = inverse of the TREATED unit's residual
# (normalized) -- i.e. 1/(1 - Dbar_cell) up to a constant, our "ewatt".
#
# RESULT (2026-08-24): ours matches theirs to 3.6e-13 at every h = 0..5;
# the pre-fix "cellsize" weights are off by up to 4.12 on effects of ~28
# (~15% relative). Third independent confirmation of the 2026-08-24 fix,
# and the only one against the authors' own code.
################################################################################
power_repo_root <- function() "."
source("R/power/impose_effects.R"); source("R/power/run_estimators.R")

df <- read_dta("http://fmwww.bc.edu/repec/bocode/l/lpdidtestdata1.dta")
cat("data:", n_distinct(df$unit), "units,", n_distinct(df$time), "periods\n")
post_window <- 5

# ---- THEIR recipe, verbatim logic (per-horizon EW) --------------------------
df <- df %>% group_by(unit) %>% arrange(time, .by_group=TRUE) %>%
  mutate(D_treat = treat - dplyr::lag(treat,1), L_Y = dplyr::lag(Y,1)) %>% ungroup()
for (h in 0:post_window) {
  df <- df %>% group_by(unit) %>% arrange(time, .by_group=TRUE) %>%
    mutate(!!paste0("F",h,"_treat") := dplyr::lead(treat,h),
           !!paste0("D",h,"y") := dplyr::lead(Y,h) - L_Y) %>% ungroup()
}
get_reweights <- function(df, h) {
  lead_col <- paste0("F",h,"_treat")
  clean_h <- df %>% filter(!is.na(D_treat), D_treat==1 | .data[[lead_col]]==0)
  m_w <- feols(D_treat ~ 1 | time, data=clean_h)
  clean_h$num_weights <- residuals(m_w)
  clean_h <- clean_h %>%
    mutate(num_weights = if_else(D_treat != 1, NA_real_, num_weights))
  den <- sum(clean_h$num_weights, na.rm=TRUE)
  clean_h <- clean_h %>% mutate(weight = num_weights/den) %>%
    group_by(time) %>%
    mutate(gweight = suppressWarnings(max(weight, na.rm=TRUE)),
           gweight = if_else(is.infinite(gweight), NA_real_, gweight),
           weight  = if_else(is.na(weight), gweight, weight)) %>%
    ungroup() %>% mutate(reweight = 1/weight)
  clean_h[, c("unit","time","reweight")]
}
theirs <- vapply(0:post_window, function(h) {
  lead_col <- paste0("F",h,"_treat")
  clean_h <- df %>% filter(!is.na(D_treat), D_treat==1 | .data[[lead_col]]==0) %>%
    left_join(get_reweights(df,h), by=c("unit","time"))
  coef(feols(as.formula(paste0("D",h,"y ~ D_treat | time")),
             data=clean_h, weights=~reweight, vcov=~unit))["D_treat"]
}, numeric(1))

# ---- OURS on the same data --------------------------------------------------
first_treat <- df %>% filter(treat==1) %>% group_by(unit) %>%
  summarise(g_time = min(time), .groups="drop")
months <- seq(as.Date("2000-01-01"), by="month", length.out=max(df$time))
sim <- df %>% left_join(first_treat, by="unit") %>%
  transmute(unit_id = as.character(unit), state_abb = as.character(unit),
            month_date = months[time], t = as.integer(time), y_sim = Y,
            pseudo_g = if_else(is.na(g_time), as.Date(NA), months[g_time]))
ours <- vapply(0:post_window, function(h) {
  r <- run_estimator(sim, estimator="lpdid",
                     spec=list(lpdid_pmd=1L, lpdid_weights="ewatt",
                               lpdid_hmin=h, lpdid_post=h))
  r$att[r$inference=="analytic"][1]
}, numeric(1))
old <- vapply(0:post_window, function(h) {
  r <- run_estimator(sim, estimator="lpdid",
                     spec=list(lpdid_pmd=1L, lpdid_weights="cellsize",
                               lpdid_hmin=h, lpdid_post=h))
  r$att[r$inference=="analytic"][1]
}, numeric(1))

cmp <- tibble(h=0:post_window, official=theirs, ours_ewatt=ours,
              ours_old_cellsize=old,
              diff_ewatt=ours-theirs, diff_old=old-theirs)
print(as.data.frame(cmp), row.names=FALSE, digits=7)
cat("\nmax |ours_ewatt - official| :", max(abs(cmp$diff_ewatt)), "\n")
cat("max |old_cellsize - official|:", max(abs(cmp$diff_old)), "\n")
