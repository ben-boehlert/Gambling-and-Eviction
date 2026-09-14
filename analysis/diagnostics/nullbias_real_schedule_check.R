# =============================================================================
# nullbias_real_schedule_check.R  (2026-09-14)
#
# Does the REAL adoption schedule show the same date/trend correlation that
# drives the simulated null bias?
#
# WHY THIS MATTERS. quality_reports/nullbias_decomposition_2026-08-25.md traces
# the +0.9 SD null center to `cor_date_trend` -- across pseudo-treated states,
# the correlation between pseudo-adoption month and that state's own real trend
# slope -- negative in 4,000/4,000 draws, caused by the eligibility structure of
# `.assign_cohorts()`. FINDINGS §2 concludes recentering is "the correct
# handling rather than a patch."
#
# That conclusion rests on an untested premise: that the correlation is an
# ARTIFACT of pseudo-placement. If the REAL schedule shows the same
# correlation, the simulated null bias is instead a faithful reproduction of a
# real selection-on-trends problem -- and recentering would remove from the
# size gate a bias the real estimate actually carries, since nobody can
# recenter a real-data estimate.
#
# Uses the identical feature the memo used: lm(y_log1p ~ t) per state on the
# covid-drop panel. Descriptive, no imposed effect, no treatment-effect
# estimate: blindness-safe (a selection/pre-trends design diagnostic).
#
# Output: output/nullbias_real_vs_sim/
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(lubridate)})
CS <- as.Date("2020-03-01"); CE <- as.Date("2021-07-31")
EXCL <- c("NV","ID","HI","MS")

pan <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types=FALSE) %>%
  mutate(month_date=as.Date(month_date)) %>%
  filter(month_date < CS | month_date > CE) %>%
  mutate(y_log1p = log1p(filings_count))

# Per-state real trend slope on the covid-drop panel -- the SAME descriptive
# feature the nullbias memo used (lm(y_log1p ~ t), once per state).
slopes <- pan %>% group_by(state_abb) %>%
  filter(n() >= 24) %>%
  summarise(slope = coef(lm(y_log1p ~ as.numeric(month_date)))[2], .groups="drop")

sched <- read_csv("data/raw/sports_gambling_legalization_dates.csv", show_col_types=FALSE) %>%
  filter(!is.na(online_start_date)) %>%
  mutate(online = as.Date(online_start_date))
abbmap <- c(Delaware="DE",`New Jersey`="NJ",`West Virginia`="WV",Pennsylvania="PA",
  `Rhode Island`="RI",Arkansas="AR",`New York`="NY",Iowa="IA",Indiana="IN",Oregon="OR",
  `New Hampshire`="NH",Illinois="IL",Michigan="MI",Colorado="CO",`District of Columbia`="DC",
  Tennessee="TN",Virginia="VA",`North Carolina`="NC",Arizona="AZ",Wyoming="WY",
  Connecticut="CT",Louisiana="LA",Maryland="MD",Kansas="KS",Massachusetts="MA",Ohio="OH",
  Kentucky="KY",Maine="ME",Florida="FL",Vermont="VT",Missouri="MO")
sched$st <- abbmap[sched$state]

real <- sched %>% inner_join(slopes, by=c("st"="state_abb")) %>%
  filter(!st %in% EXCL) %>%
  mutate(month_idx = as.integer(interval(min(online), online) %/% months(1)))

cat("Real online-legalizing states with a usable slope:", nrow(real), "\n")
rp <- cor(real$month_idx, real$slope, method="pearson")
rs <- cor(real$month_idx, real$slope, method="spearman")
ct <- cor.test(real$month_idx, real$slope)
cat(sprintf("REAL cor_date_trend  Pearson = %+.4f  (95%% CI %+.3f, %+.3f; p = %.3f)   Spearman = %+.4f\n",
            rp, ct$conf.int[1], ct$conf.int[2], ct$p.value, rs))

# Restrict to the actual clean-anchor switcher set (13)
SW <- c("WV","IN","NH","AR","KS","MD","OH","KY","ME","FL","DE","VT","NC")
rsw <- real %>% filter(st %in% SW)
cat(sprintf("Restricted to the 13 clean-anchor switchers: Pearson = %+.4f  Spearman = %+.4f  (n=%d)\n",
            cor(rsw$month_idx, rsw$slope), cor(rsw$month_idx, rsw$slope, method="spearman"), nrow(rsw)))

sim <- read_csv("output/nullbias_decomposition/rep_features_combined.csv", show_col_types=FALSE)
cat("\nSIMULATED cor_date_trend across", nrow(sim), "draws:\n")
print(summary(sim$cor_date_trend))
cat(sprintf("  mean %+.4f   sd %.4f   range [%+.4f, %+.4f]   share negative: %.3f\n",
            mean(sim$cor_date_trend), sd(sim$cor_date_trend),
            min(sim$cor_date_trend), max(sim$cor_date_trend),
            mean(sim$cor_date_trend < 0)))
pct <- 100*mean(sim$cor_date_trend < rp)
cat(sprintf("\nWhere does the REAL value sit in the simulated distribution? percentile = %.1f%%\n", pct))

dir.create("output/nullbias_real_vs_sim", recursive = TRUE, showWarnings = FALSE)
readr::write_csv(tibble::tibble(
  quantity = c("real_pearson_all24","real_pearson_ci_lo","real_pearson_ci_hi","real_p",
               "real_spearman_all24","real_pearson_switchers13","n_real","n_switchers",
               "sim_mean","sim_sd","sim_min","sim_max","sim_share_negative","real_percentile_in_sim"),
  value = c(rp, ct$conf.int[1], ct$conf.int[2], ct$p.value, rs,
            cor(rsw$month_idx, rsw$slope), nrow(real), nrow(rsw),
            mean(sim$cor_date_trend), sd(sim$cor_date_trend),
            min(sim$cor_date_trend), max(sim$cor_date_trend),
            mean(sim$cor_date_trend < 0), pct)),
  "output/nullbias_real_vs_sim/real_vs_sim_cor_date_trend.csv")
readr::write_csv(real %>% dplyr::select(st, online, month_idx, slope),
                 "output/nullbias_real_vs_sim/real_state_slopes.csv")
message("Wrote output/nullbias_real_vs_sim/")
