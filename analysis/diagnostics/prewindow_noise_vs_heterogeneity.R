################################################################################
# prewindow_noise_vs_heterogeneity.R
#
# CONCERN: small-basket states are noisy, and that noise is what makes the
#          2021-07..2022-06 pre-window differential trend look bad.
#
# The concern has two distinct versions, and they have different fixes:
#   (V1) NOISE. State slopes scatter because thin baskets sample few filings.
#        Fix = precision weighting (inverse-variance / population). Shrinks SEs.
#   (V2) HETEROGENEITY. State slopes scatter because states genuinely recovered
#        from the moratorium at different speeds. No weighting scheme fixes it;
#        it is real dispersion in the estimand.
#
# The test is a variance decomposition on the per-state slopes:
#     Var(slope_hat)  =  Var(true slope)  +  E[ sampling var of slope_hat ]
# so   Var(true) = Var(slope_hat) - mean(SE_slope^2).
# If Var(true) dominates, V2 is the binding problem, not V1.
#
# Also reports: noise-vs-size scaling, FGLS/precision-weighted refits, and
# size-threshold subsamples.
#
# Window 2021-07..2022-06, log(1+filings per 1k renters). Pre-treatment only.
################################################################################

suppressPackageStartupMessages({library(tidyverse); library(fixest)})
source("utils/eviction_treatment_schedule.R")
theme_set(theme_minimal(base_size = 11))

SCH <- "data/raw/sports_gambling_legalization_dates.csv"
EXCLUDE <- toupper(trimws(strsplit(Sys.getenv("EXCLUDE_STATES", ""), ",")[[1]]))
EXCLUDE <- EXCLUDE[nzchar(EXCLUDE)]
OUT <- if (length(EXCLUDE)) paste0("output/prewindow_trends_2021h2_ex", paste(EXCLUDE, collapse="")) else "output/prewindow_trends_2021h2"

pan <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date))
sc  <- load_eviction_treatment_schedule(SCH, "online_start_date",
                                        states = EVICTION_STATE_UNIVERSE)
ps <- sort(unique(pan$state_abb))
CT_CONTROL <- suppressWarnings(
  eviction_control_states(ps, SCH, "online_start_date", censor_end = as.Date("2026-06-01")))
CT_TREATED <- sc %>% filter(state_abb %in% ps, !is.na(treat_start),
                            treat_start > as.Date("2022-06-01")) %>% pull(state_abb) %>% sort()

if (length(EXCLUDE)) {
  message("Excluding by request: ", paste(EXCLUDE, collapse = " "))
  CT_TREATED <- setdiff(CT_TREATED, EXCLUDE)
  CT_CONTROL <- setdiff(CT_CONTROL, EXCLUDE)
}


d <- pan %>%
  filter(state_abb %in% .env$CT_TREATED | state_abb %in% .env$CT_CONTROL,
         month_date >= as.Date("2021-07-01"), month_date <= as.Date("2022-06-01"),
         !is.na(filings_per_1k_renters)) %>%
  mutate(D = as.integer(state_abb %in% .env$CT_TREATED)) %>%
  group_by(state_abb) %>% filter(n() == 12) %>% ungroup() %>%
  mutate(tnum = as.integer(factor(month_date)),
         tc   = tnum - mean(sort(unique(tnum))),
         Dt   = D * tc,
         y    = log1p(filings_per_1k_renters),
         mfac = factor(month_date), state_abb = factor(state_abb)) %>%
  as.data.frame()

# ---- per-state slope, its sampling SE, and basket size ------------------------
st <- d %>% group_by(state_abb, D) %>%
  group_modify(~{
    m <- lm(y ~ tc, data = .x)
    tibble(slope = coef(m)[2], slope_se = summary(m)$coefficients[2, 2],
           sigma = summary(m)$sigma,
           renters = mean(.x$renter_occupied_housing_units),
           filings = mean(.x$filings_count),
           n_counties = mean(.x$n_counties))
  }) %>% ungroup() %>%
  mutate(arm = if_else(D == 1, "later adopter", "never-legalizer"),
         prec = 1 / slope_se^2)

# ---- does noise scale with basket size? ---------------------------------------
sz <- lm(log(sigma) ~ log(filings), data = st)
cat("\n== residual noise vs basket size ==\n")
cat(sprintf("log(sigma) on log(mean monthly filings): slope = %+.3f (SE %.3f), R2 = %.2f\n",
            coef(sz)[2], summary(sz)$coefficients[2, 2], summary(sz)$r.squared))
cat("  (pure Poisson counting noise in logs would give about -0.50)\n")

# ---- THE DECOMPOSITION --------------------------------------------------------
cat("\n== variance decomposition of state slopes, by arm ==\n")
dec <- st %>% group_by(arm) %>%
  summarise(n = n(),
            var_observed = var(slope),
            var_sampling = mean(slope_se^2),
            .groups = "drop") %>%
  mutate(var_true = pmax(var_observed - var_sampling, 0),
         share_noise = var_sampling / var_observed,
         sd_observed = sqrt(var_observed), sd_true = sqrt(var_true))
print(as.data.frame(dec %>% select(arm, n, sd_observed, sd_true, share_noise)), digits = 3)

pooled <- st %>% group_by(arm) %>% mutate(dm = slope - mean(slope)) %>% ungroup()
vo <- sum(pooled$dm^2) / (nrow(pooled) - 2); vs <- mean(pooled$slope_se^2)
cat(sprintf("\nPooled within-arm: SD(observed) = %.4f, SD(sampling) = %.4f, SD(true) = %.4f\n",
            sqrt(vo), sqrt(vs), sqrt(max(vo - vs, 0))))
cat(sprintf("Share of slope dispersion attributable to sampling noise: %.1f%%\n",
            100 * vs / vo))

# ---- estimators that would help if noise were the problem ---------------------
fit <- function(dd, w = NULL, lab) {
  dd <- droplevels(dd)
  m <- if (is.null(w)) feols(y ~ Dt | state_abb + mfac, data = dd, cluster = ~state_abb)
       else { dd$.w <- w(dd); feols(y ~ Dt | state_abb + mfac, data = dd,
                                    cluster = ~state_abb, weights = ~.w) }
  cat(sprintf("%-34s b = %+.5f  SE = %.5f  t = %+.2f  n = %d\n",
              lab, coef(m)["Dt"], se(m)["Dt"], coef(m)["Dt"] / se(m)["Dt"],
              n_distinct(dd$state_abb)))
  invisible(c(b = unname(coef(m)["Dt"]), se = unname(se(m)["Dt"])))
}
pmap <- setNames(st$prec, as.character(st$state_abb))

cat("\n== weighting / trimming ==\n")
fit(d, NULL, "unweighted (headline)")
fit(d, function(x) x$renter_occupied_housing_units, "renter-weighted")
fit(d, function(x) x$filings_count,                 "filings-weighted")
fit(d, function(x) unname(pmap[as.character(x$state_abb)]), "inverse-variance (FGLS)")

cat("\n== basket-size thresholds (renters in covered basket) ==\n")
for (thr in c(0, 1e5, 2e5, 4e5)) {
  keep <- st$state_abb[st$renters >= thr]
  dd <- filter(d, state_abb %in% keep)
  if (n_distinct(dd$D) == 2 && n_distinct(dd$state_abb) >= 8)
    fit(dd, NULL, sprintf("renters >= %s", format(thr, big.mark = ",", scientific = FALSE)))
}

cat("\n== per-state detail, noisiest first ==\n")
print(as.data.frame(st %>% arrange(desc(slope_se)) %>%
  transmute(state_abb, arm, slope = round(slope, 4), slope_se = round(slope_se, 4),
            sigma = round(sigma, 3), renters = round(renters), n_counties)), digits = 3)

write_csv(st,  file.path(OUT, "noise_per_state.csv"))
write_csv(dec, file.path(OUT, "noise_variance_decomposition.csv"))

p <- ggplot(st, aes(renters, slope, colour = arm)) +
  geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey40") +
  geom_pointrange(aes(ymin = slope - 1.96 * slope_se, ymax = slope + 1.96 * slope_se),
                  size = 0.3) +
  ggrepel::geom_text_repel(aes(label = state_abb), size = 2.8, show.legend = FALSE) +
  scale_x_log10(labels = scales::comma) +
  scale_colour_manual(values = c("later adopter" = "#B2182B",
                                 "never-legalizer" = "#2166AC")) +
  labs(x = "Renters in covered basket (log scale)",
       y = "Own trend, log pts/month", colour = NULL,
       subtitle = "Per-state pre-window slope vs basket size, with sampling CIs.")
ggsave(file.path(OUT, "noise_slope_vs_size.png"), p, width = 8, height = 5, dpi = 200)
cat("\nWrote noise diagnostics to ", OUT, "\n")
