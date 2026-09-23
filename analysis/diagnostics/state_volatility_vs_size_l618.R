#!/usr/bin/env Rscript
# Is any state's series jumpier than its size predicts? (2026-09-18)
# Per-state descriptives only (no treated-vs-control comparison, no estimator).
# For each state in the 6-18 design's calendar span: residual SD of log filings
# around the state's own linear trend + month-of-year effects, compared with
# the SD predicted from a cross-state regression of log(SD) on log(mean
# filings) (count noise shrinks like 1/sqrt(n)). Also flags single months whose
# residual is a robust outlier (|z| > 3.5, MAD scale).
# Run from the project root: Rscript --vanilla analysis/diagnostics/state_volatility_vs_size_l618.R
suppressMessages({ library(tidyverse) })
out_dir <- "output/panel_artifact_scan_l618"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

p <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types = FALSE) %>%
  transmute(state_abb, m = as.Date(month_date), f = filings_count, y = log1p(filings_count),
            panel_source, n_counties) %>%
  filter(!is.na(y), m >= as.Date("2022-06-01"), m <= as.Date("2025-09-01"),
         !state_abb %in% c("NV", "HI", "MS"))

res <- p %>% group_by(state_abb) %>% filter(n() >= 24) %>%
  group_modify(~ { fit <- lm(y ~ as.numeric(m) + factor(format(m, "%m")), data = .x)
                   mutate(.x, resid = resid(fit)) }) %>% ungroup()

st <- res %>% group_by(state_abb) %>%
  summarise(n = n(), mean_filings = mean(f), n_counties = median(n_counties, na.rm = TRUE),
            source = first(panel_source), sd_resid = sd(resid),
            sd_mom = sd(diff(y[order(m)])), .groups = "drop")
fit <- lm(log(sd_resid) ~ log(mean_filings), data = st)
st <- st %>% mutate(sd_expected = exp(predict(fit)), ratio = sd_resid / sd_expected) %>%
  arrange(desc(ratio))
write_csv(st, file.path(out_dir, "state_volatility_vs_size.csv"))

outl <- res %>% group_by(state_abb) %>%
  mutate(z = (resid - median(resid)) / (1.4826 * mad(resid))) %>% ungroup() %>%
  filter(abs(z) > 3.5) %>% transmute(state_abb, month = format(m, "%Y-%m"), filings = f,
                                     resid = round(resid, 3), z = round(z, 1)) %>%
  arrange(desc(abs(z)))
write_csv(outl, file.path(out_dir, "state_month_residual_outliers.csv"))

cat(sprintf("size law: log(sd) = %.2f %+.2f log(mean filings), R2 %.2f\n",
            coef(fit)[1], coef(fit)[2], summary(fit)$r.squared))
print(as.data.frame(st %>% transmute(state_abb, n, mean_filings = round(mean_filings),
      n_counties, sd_resid = round(sd_resid, 3), sd_expected = round(sd_expected, 3),
      ratio = round(ratio, 2))), row.names = FALSE)
cat("\nsingle-month outliers (|z| > 3.5):\n"); print(as.data.frame(outl), row.names = FALSE)
