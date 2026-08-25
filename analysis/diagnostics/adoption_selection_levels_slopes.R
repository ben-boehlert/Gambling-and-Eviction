################################################################################
# adoption_selection_levels_slopes.R
#
# QUESTION: Is sports-gambling legalization TIMING related to pre-legalization
#           eviction rate LEVELS or SLOPES?
#
# This is a selection-into-treatment diagnostic for the staggered DiD design.
# Nothing here uses post-treatment data: every predictor is measured in a window
# that ends before the FIRST legalization anywhere in the US (2018-06).
#
# Two independent substrates (different sources, different eras):
#   A. Annual county court panel, 2009-2015  (county_court-issued_..._5_12.csv)
#   B. ETS monthly county download, 2016-01..2018-05 (monthly_county_data_download.csv)
#
# Both use a FIXED COUNTY BASKET (counties reporting in every period of the
# window) so that level and slope are not composition artifacts -- see the
# composition-churn warning in CLAUDE.md.
#
# Outcomes tested, for each of online_start_date and first_start_date:
#   (1) EVER adopt within the observation window (binary)
#   (2) TIMING among adopters (months from 2018-06 to adoption)
#   (3) Cox proportional hazard of adoption (handles never-adopters as censored)
#
# Output: output/adoption_selection/
################################################################################

suppressPackageStartupMessages({
  library(tidyverse)
  library(sandwich)
  library(lmtest)
  library(survival)
})

theme_set(theme_minimal())
set.seed(20260821)

OUT <- "output/adoption_selection"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

source("utils/eviction_treatment_schedule.R")

ORIGIN     <- as.Date("2018-06-01")   # first legalization anywhere (DE, NJ)
CENSOR_END <- as.Date("2024-12-01")   # end of usable eviction data
EXCLUDE    <- c("ID")                 # CLAUDE.md: Idaho data quality

# ---------------------------------------------------------------- treatment ---
# The 51-state universe and the Nevada exclusion are defined once, in
# utils/eviction_treatment_schedule.R. Do not re-derive them here.
TREAT_FILE <- "data/raw/sports_gambling_legalization_dates.csv"

make_treat <- function(datecol) {
  eviction_adoption_outcomes(TREAT_FILE, treat_date_col = datecol,
                             censor_end = CENSOR_END, origin = ORIGIN) %>%
    # Nevada had legal sports betting since 1949: it is always-treated, not a
    # never-adopter, so it cannot inform selection into post-2018 adoption.
    filter(!pre_paspa_legal) %>%
    rename(months = months_to_adopt)
}

treat_online <- make_treat("online_start_date")
treat_first  <- make_treat("first_start_date")

# ------------------------------------------------- Substrate A: annual court ---
build_annual <- function(y0, y1, level_yrs) {
  raw <- read_csv("data/raw/county_court-issued_2000_2023_ben_update_5_12.csv",
                  show_col_types = FALSE)

  cty <- raw %>%
    mutate(state_abb = eviction_state_name_to_abb(state)) %>%
    filter(!is.na(state_abb), !state_abb %in% EXCLUDE,
           year >= y0, year <= y1)

  nyr <- y1 - y0 + 1

  # fixed basket: county reports filings AND renters in EVERY year of the window
  basket <- cty %>%
    filter(!is.na(filings_observed), !is.na(renting_hh), renting_hh > 0) %>%
    count(state_abb, fips_county) %>%
    filter(n == nyr) %>%
    select(state_abb, fips_county)

  # denominator for basket coverage: all renters in the state's source counties
  all_renters <- cty %>%
    filter(!is.na(renting_hh)) %>%
    group_by(state_abb, year) %>%
    summarise(renters_all = sum(renting_hh), n_cty_all = n(), .groups = "drop")

  panel <- cty %>%
    semi_join(basket, by = c("state_abb", "fips_county")) %>%
    group_by(state_abb, year) %>%
    summarise(filings = sum(filings_observed),
              renters = sum(renting_hh),
              n_cty   = n(), .groups = "drop") %>%
    left_join(all_renters, by = c("state_abb", "year")) %>%
    mutate(rate = 1000 * filings / renters,
           y    = log(rate),
           basket_share = renters / renters_all)

  # every state-year must have the identical basket by construction
  stopifnot(panel %>% group_by(state_abb) %>%
              summarise(k = n_distinct(n_cty)) %>% pull(k) %>% max() == 1)

  panel %>%
    group_by(state_abb) %>%
    filter(n() == nyr, all(is.finite(y))) %>%
    summarise(
      n_cty   = first(n_cty),
      renters = mean(renters),
      basket_share = min(basket_share),
      level   = mean(y[year %in% level_yrs]),
      rate_lv = mean(rate[year %in% level_yrs]),
      slope   = coef(lm(y ~ I(year - mean(year))))[2],   # log pts / year
      .groups = "drop"
    )
}

# ------------------------------------------------------ Substrate B: ETS mo ---
build_ets <- function(d0, d1) {
  raw <- read_csv("data/raw/monthly_county_data_download.csv",
                  show_col_types = FALSE)

  fips_to_abb <- setNames(c(state.abb, "DC"), c(as.character(
    sprintf("%02d", c(1,2,4,5,6,8,9,10,12,13,15,16,17,18,19,20,21,22,23,24,25,26,
                      27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,44,45,46,
                      47,48,49,50,51,53,54,55,56))), "11"))

  cty <- raw %>%
    mutate(date = as.Date(substr(date, 1, 10)),
           st   = sprintf("%02d", as.integer(fips) %/% 1000),
           state_abb = unname(fips_to_abb[st])) %>%
    filter(!is.na(state_abb), !state_abb %in% EXCLUDE,
           date >= d0, date <= d1)

  nmo <- length(seq(d0, d1, by = "month"))

  basket <- cty %>%
    filter(!is.na(filings_count), !is.na(renter_occupied_housing_units),
           renter_occupied_housing_units > 0) %>%
    count(state_abb, fips) %>%
    filter(n == nmo) %>%
    select(state_abb, fips)

  all_renters <- cty %>%
    filter(!is.na(renter_occupied_housing_units)) %>%
    distinct(state_abb, fips, renter_occupied_housing_units) %>%
    group_by(state_abb) %>%
    summarise(renters_all = sum(renter_occupied_housing_units), .groups = "drop")

  panel <- cty %>%
    semi_join(basket, by = c("state_abb", "fips")) %>%
    group_by(state_abb, date) %>%
    summarise(filings = sum(filings_count),
              renters = sum(renter_occupied_housing_units),
              n_cty   = n(), .groups = "drop") %>%
    left_join(all_renters, by = "state_abb") %>%
    mutate(rate = 1000 * filings / renters,
           y    = log(rate),
           basket_share = renters / renters_all,
           t    = as.numeric(date - min(date)) / 30.4375)

  stopifnot(panel %>% group_by(state_abb) %>%
              summarise(k = n_distinct(n_cty)) %>% pull(k) %>% max() == 1)

  panel %>%
    group_by(state_abb) %>%
    filter(n() == nmo, all(is.finite(y))) %>%
    summarise(
      n_cty   = first(n_cty),
      renters = mean(renters),
      basket_share = min(basket_share),
      level   = mean(y),
      rate_lv = mean(rate),
      slope   = 12 * coef(lm(y ~ t))[2],                 # log pts / year
      .groups = "drop"
    )
}

# ------------------------------------------------------------------ testing ---
# Small N (16-29 states) => report 95% CIs, not just p-values, and back every
# parametric test with a permutation test that makes no distributional claim.

PERM <- 5000

perm_p <- function(x, y, stat = function(a, b) cor(a, b, method = "spearman")) {
  obs <- stat(x, y)
  nul <- replicate(PERM, stat(sample(x), y))
  list(stat = obs, p = mean(abs(nul) >= abs(obs) - 1e-12))
}

run_tests <- function(feat, tr, label) {
  df <- feat %>% inner_join(tr, by = "state_abb") %>%
    mutate(level_z = as.numeric(scale(level)),
           slope_z = as.numeric(scale(slope)))

  rob <- function(m, term) {
    ct <- coeftest(m, vcov. = sandwich::vcovHC(m, type = "HC3"))
    ci <- coefci(m, term, vcov. = sandwich::vcovHC(m, type = "HC3"))
    tibble(est = ct[term, 1], se = ct[term, 2], p = ct[term, 4],
           lo = ci[1, 1], hi = ci[1, 2])
  }

  out <- list()
  add <- function(...) out[[length(out) + 1]] <<- tibble(substrate = label, ...)

  # ---- (1) ever-adopt (binary). Degenerate if every state in the sample adopts.
  if (n_distinct(df$ever) == 2) {
    m1 <- lm(as.numeric(ever) ~ level_z + slope_z, data = df)
    for (v in c("level_z", "slope_z"))
      add(outcome = "ever_adopt (LPM, joint)", term = v, n = nrow(df), rob(m1, v))
    for (v in c("level_z", "slope_z")) {
      mu <- lm(reformulate(v, "as.numeric(ever)"), data = df)
      add(outcome = "ever_adopt (LPM, univariate)", term = v, n = nrow(df), rob(mu, v))
    }
  } else {
    for (v in c("level_z", "slope_z"))
      add(outcome = "ever_adopt (LPM, joint)", term = v, n = nrow(df),
          tibble(est = NA_real_, se = NA_real_, p = NA_real_, lo = NA_real_, hi = NA_real_))
  }

  # ---- (2) months to adoption, among adopters
  da <- df %>% filter(ever)
  m2 <- lm(months ~ level_z + slope_z, data = da)
  for (v in c("level_z", "slope_z"))
    add(outcome = "months to adoption (joint)", term = v, n = nrow(da), rob(m2, v))
  for (v in c("level_z", "slope_z")) {
    mu <- lm(reformulate(v, "months"), data = da)
    add(outcome = "months to adoption (univariate)", term = v, n = nrow(da), rob(mu, v))
  }

  # ---- (3) Cox PH over all states, never-adopters censored at CENSOR_END
  m3 <- coxph(Surv(surv_time, ever) ~ level_z + slope_z, data = df)
  s3 <- summary(m3)$coefficients; c3 <- summary(m3)$conf.int
  for (v in c("level_z", "slope_z"))
    add(outcome = "Cox PH (log hazard)", term = v, n = nrow(df),
        tibble(est = s3[v, "coef"], se = s3[v, "se(coef)"], p = s3[v, "Pr(>|z|)"],
               lo = log(c3[v, "lower .95"]), hi = log(c3[v, "upper .95"])))

  # ---- (4) permutation Spearman among adopters
  for (v in c("level", "slope")) {
    pp <- perm_p(da[[v]], da$months)
    add(outcome = "Spearman rho w/ months (perm test)", term = v, n = nrow(da),
        tibble(est = pp$stat, se = NA_real_, p = pp$p, lo = NA_real_, hi = NA_real_))
  }

  # ---- (5) permutation difference in means, adopters vs never
  if (n_distinct(df$ever) == 2) {
    for (v in c("level", "slope")) {
      dm <- function(g, x) mean(x[g == 1]) - mean(x[g == 0])
      obs <- dm(as.numeric(df$ever), df[[v]])
      nul <- replicate(PERM, dm(sample(as.numeric(df$ever)), df[[v]]))
      add(outcome = "adopter - never mean diff (perm test)", term = v, n = nrow(df),
          tibble(est = obs, se = sd(nul), p = mean(abs(nul) >= abs(obs) - 1e-12),
                 lo = NA_real_, hi = NA_real_))
    }
  }

  list(tests = bind_rows(out), data = df)
}

# --------------------------------------------------------------------- main ---
featA_all <- build_annual(2009, 2015, level_yrs = 2013:2015)
featB_all <- build_ets(as.Date("2016-01-01"), as.Date("2018-05-01"))

# Robustness sample: drop states whose fixed basket is a thin or unrepresentative
# slice of the state (1-2 reporting counties, or <50% of the state's renters).
MIN_CTY <- 5; MIN_SHARE <- 0.50
featA <- featA_all %>% filter(n_cty >= MIN_CTY, basket_share >= MIN_SHARE)
featB <- featB_all %>% filter(n_cty >= MIN_CTY, basket_share >= MIN_SHARE)

cat("\n=== Substrate A: annual court panel 2009-2015 (level 2013-15) ===\n")
cat("  full:", nrow(featA_all), "states,", sum(featA_all$n_cty), "counties\n")
cat("  trimmed (n_cty>=5, basket_share>=.5):", nrow(featA), "states\n")
cat("=== Substrate B: ETS monthly 2016-01..2018-05 ===\n")
cat("  full:", nrow(featB_all), "states,", sum(featB_all$n_cty), "counties\n")
cat("  trimmed:", nrow(featB), "states\n\n")

res <- list(
  run_tests(featA_all, treat_online, "A annual x online (full)"),
  run_tests(featA,     treat_online, "A annual x online (trimmed)"),
  run_tests(featA_all, treat_first,  "A annual x first  (full)"),
  run_tests(featB_all, treat_online, "B ETS x online (full)"),
  run_tests(featB,     treat_online, "B ETS x online (trimmed)"),
  run_tests(featB_all, treat_first,  "B ETS x first  (full)")
)

tests <- bind_rows(lapply(res, `[[`, "tests"))
write_csv(tests, file.path(OUT, "selection_tests.csv"))

for (sb in unique(tests$substrate)) {
  cat("\n###", sb, "\n")
  print(as.data.frame(tests %>% filter(substrate == sb) %>%
    transmute(outcome, term, n, est = round(est, 3), se = round(se, 3),
              `95%lo` = round(lo, 3), `95%hi` = round(hi, 3), p = round(p, 3))),
    row.names = FALSE)
}

write_csv(featA_all %>% inner_join(treat_online, by = "state_abb"),
          file.path(OUT, "state_features_annual_online.csv"))
write_csv(featB_all %>% inner_join(treat_online, by = "state_abb"),
          file.path(OUT, "state_features_ets_online.csv"))

grp <- bind_rows(
  featA_all %>% inner_join(treat_online, by = "state_abb") %>% mutate(substrate = "A annual x online (full)"),
  featA     %>% inner_join(treat_online, by = "state_abb") %>% mutate(substrate = "A annual x online (trimmed)"),
  featB_all %>% inner_join(treat_online, by = "state_abb") %>% mutate(substrate = "B ETS x online (full)"),
  featB     %>% inner_join(treat_online, by = "state_abb") %>% mutate(substrate = "B ETS x online (trimmed)")
) %>%
  group_by(substrate, ever) %>%
  summarise(n = n(), mean_rate = mean(rate_lv), mean_log_level = mean(level),
            mean_slope_pct_yr = 100 * mean(slope), sd_slope_pct = 100 * sd(slope),
            .groups = "drop")
cat("\n=== adopter vs never contrast (ONLINE) ===\n")
print(as.data.frame(grp %>% mutate(across(where(is.numeric), ~round(., 2)))), row.names = FALSE)
write_csv(grp, file.path(OUT, "group_means_online.csv"))

# ------------------------------------------- is the LEVEL signal just size? ---
# Cross-state levels of filings per renter are partly a court-practice artifact
# and partly a size/urbanization proxy. Add log(basket renters) as a control.
size_check <- function(feat, tr, lab) {
  d <- feat %>% inner_join(tr, by = "state_abb") %>%
    mutate(level_z = as.numeric(scale(level)),
           slope_z = as.numeric(scale(slope)),
           size_z  = as.numeric(scale(log(renters))))
  m  <- coxph(Surv(surv_time, ever) ~ level_z + slope_z + size_z, data = d)
  ms <- coxph(Surv(surv_time, ever) ~ size_z, data = d)
  cs <- summary(m)$coefficients
  bind_rows(
    tibble(sample = lab, n = nrow(d), events = sum(d$ever), term = rownames(cs),
           est = cs[, "coef"], se = cs[, "se(coef)"], p = cs[, "Pr(>|z|)"]),
    tibble(sample = lab, n = nrow(d), events = sum(d$ever), term = "size_z (alone)",
           est = coef(ms)[1], se = summary(ms)$coefficients[, "se(coef)"],
           p = summary(ms)$coefficients[, "Pr(>|z|)"])
  ) %>% mutate(cor_level_size = cor(d$level, log(d$renters)),
               cor_slope_size = cor(d$slope, log(d$renters)))
}

sz <- bind_rows(
  size_check(featA_all, treat_online, "A annual (full)"),
  size_check(featA,     treat_online, "A annual (trimmed)"),
  size_check(featB_all, treat_online, "B ETS (full)"),
  size_check(featB,     treat_online, "B ETS (trimmed)")
)
cat("\n=== Cox adoption hazard with state-size control (online) ===\n")
print(as.data.frame(sz %>% mutate(across(where(is.numeric), ~round(., 3)))), row.names = FALSE)
write_csv(sz, file.path(OUT, "cox_with_size_control.csv"))

# ------------------------------------------------------------------ figures ---
plot_df <- bind_rows(
  featA_all %>% inner_join(treat_online, by = "state_abb") %>%
    mutate(substrate = "A: annual court panel, 2009-2015"),
  featB_all %>% inner_join(treat_online, by = "state_abb") %>%
    mutate(substrate = "B: ETS monthly, 2016-01..2018-05")
) %>%
  mutate(adopt_lab = if_else(ever, "adopted online by 2024-12", "never (censored)"),
         months_pl = if_else(ever, as.numeric(months),
                             as.numeric(round(as.numeric(CENSOR_END - ORIGIN) / 30.4375))),
         thin = n_cty < MIN_CTY | basket_share < MIN_SHARE)

p <- plot_df %>%
  pivot_longer(c(level, slope), names_to = "measure", values_to = "value") %>%
  mutate(measure = recode(measure,
                          level = "pre-period LEVEL (log filings per 1k renters)",
                          slope = "pre-period SLOPE (log points per year)")) %>%
  ggplot(aes(value, months_pl, colour = adopt_lab, shape = thin)) +
  geom_point(size = 2) +
  ggrepel::geom_text_repel(aes(label = state_abb), size = 2.4, max.overlaps = 25,
                           show.legend = FALSE) +
  geom_smooth(data = ~ filter(.x, !thin, adopt_lab == "adopted online by 2024-12"),
              method = "lm", se = TRUE, colour = "grey30", linewidth = 0.4) +
  facet_grid(substrate ~ measure, scales = "free") +
  scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 1),
                     labels = c(`FALSE` = "basket ok", `TRUE` = "thin basket")) +
  labs(x = NULL, y = "months from 2018-06 to online legalization",
       colour = NULL, shape = NULL,
       caption = "Fit line: adopters only, thin-basket states excluded. Never-adopters plotted at the censoring horizon.")
ggsave(file.path(OUT, "adoption_timing_vs_pretrend.png"), p, width = 11, height = 7.5, dpi = 200)

cat("\nWrote:", OUT, "\n")
