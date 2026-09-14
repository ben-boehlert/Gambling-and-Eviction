# =============================================================================
# moratorium_vs_adoption.R  (2026-09-14)
#
# Is eviction-moratorium ENFORCEMENT related to gambling-legalization timing?
#
# The CDC moratorium (2020-09-04 .. 2021-08-26) was NATIONAL, so on its own it
# is absorbed by time fixed effects and would be no reason to drop the COVID
# window. It only threatens identification if its BITE varied with adoption --
# i.e. if states that legalized earlier/later also suppressed filings
# differently. This tests that directly.
#
# Enforcement proxy: `plateau_onset` from output/eviction_stabilization/ --
# the month each state's filings stabilized after the COVID trough. A later
# plateau = suppression persisted longer in that state.
#
# Selection diagnostic, in the same family as cor_date_trend and
# adoption_selection. Reports no treatment effect: blindness-safe.
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(lubridate); library(glue)})
EXCL <- c("NV","ID","HI","MS")
d <- read_csv("output/eviction_stabilization/stabilization_by_state.csv", show_col_types = FALSE) %>%
  mutate(plateau_onset = as.Date(plateau_onset),
         online = as.Date(online_start_date),
         onset_m = interval(as.Date("2020-01-01"), plateau_onset) %/% months(1),
         launch_m = interval(as.Date("2018-01-01"), online) %/% months(1)) %>%
  filter(!state_abb %in% EXCL, !is.na(plateau_onset))

cat(glue("states with a stabilization estimate: {nrow(d)} ",
         "({sum(d$ever_online)} ever-online, {sum(!d$ever_online)} never)"), "\n\n")

cat("=== 1. Did adopters and never-adopters differ in when filings stabilized? ===\n")
print(as.data.frame(d %>% group_by(ever_online) %>%
  summarise(n = n(), median_plateau = median(plateau_onset),
            mean_months_after_2020 = mean(onset_m), sd = sd(onset_m), .groups="drop")),
  row.names = FALSE)
tt <- t.test(onset_m ~ ever_online, data = d)
cat(sprintf("  difference in mean onset: %+.2f months (95%% CI %+.2f, %+.2f; p = %.3f)\n",
            diff(rev(tt$estimate)), tt$conf.int[1], tt$conf.int[2], tt$p.value))

cat("\n=== 2. Among adopters, does LAUNCH TIMING predict stabilization timing? ===\n")
a <- d %>% filter(ever_online, !is.na(online))
ct <- cor.test(a$launch_m, a$onset_m)
cat(sprintf("  cor(launch month, plateau onset) = %+.3f (95%% CI %+.3f, %+.3f; p = %.3f), n = %d\n",
            ct$estimate, ct$conf.int[1], ct$conf.int[2], ct$p.value, nrow(a)))
fit <- lm(onset_m ~ launch_m, data = a)
cat(sprintf("  slope: %+.4f months of later stabilization per month of later launch (p = %.3f)\n",
            coef(fit)[2], summary(fit)$coefficients[2,4]))

cat("\n=== 3. Same question on the other suppression measures ===\n")
for (v in c("plateau_vs_pre","plateau_sd_ratio","vol_floor_ratio")) {
  x <- d[[v]]; ok <- is.finite(x)
  if (sum(ok) < 6) next
  g <- t.test(x[ok] ~ d$ever_online[ok])
  aa <- a[[v]]; ok2 <- is.finite(aa)
  cc <- if (sum(ok2) > 4) cor(a$launch_m[ok2], aa[ok2]) else NA_real_
  cat(sprintf("  %-18s adopters vs never: %+.3f (p=%.3f) | cor with launch timing: %+.3f\n",
              v, diff(rev(g$estimate)), g$p.value, cc))
}

cat("\n=== 4. Split by whether the state launched BEFORE or AFTER the moratorium ended ===\n")
print(as.data.frame(d %>%
  mutate(grp = case_when(!ever_online ~ "never-online",
                         online <= as.Date("2021-08-26") ~ "online BEFORE moratorium end",
                         TRUE ~ "online AFTER moratorium end")) %>%
  group_by(grp) %>% summarise(n = n(), median_plateau = median(plateau_onset),
                              mean_onset_m = mean(onset_m), .groups = "drop")),
  row.names = FALSE)
