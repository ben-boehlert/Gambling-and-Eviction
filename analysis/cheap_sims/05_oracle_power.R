#!/usr/bin/env Rscript
################################################################################
# analysis/cheap_sims/05_oracle_power.R
#
# Oracle-inference power: ignore the estimator's SEs entirely and ask what a
# perfectly calibrated test would do, using the empirical Monte Carlo
# distribution of the ATT itself.
#
# Two oracle tests per design x DGP:
#   emp  : empirical size-corrected critical values -- reject if the ATT under
#          delta falls outside the [2.5%, 97.5%] quantiles of the SAME design's
#          null (delta = 0) ATT distribution (exact 5% size by construction,
#          bias shared between null and alternative).
#   norm : normal approximation -- shift = mean(att_d) - mean(att_0),
#          power = P(|Z + shift/sd0| > 1.96).
#
# Oracle MDE (80% power, normal approx): estimand scale = 2.8 * sd0;
# mature scale = 2.8 * sd0 / dose_ratio, dose_ratio = mean(true_att)/delta.
# This separates "bad inference" from "no information": if the oracle MDE is
# still tens of log points, no SE method rescues the design.
#
# Run from repo root:  Rscript analysis/cheap_sims/05_oracle_power.R
################################################################################

source("analysis/cheap_sims/00_common.R")
theme_set(theme_minimal())

cfg <- cheap_config()
raw <- read_csv(file.path(cfg$out_dir, "results_raw.csv"),
                show_col_types = FALSE) %>%
  filter(!is.na(design), converged, design != "full_didsimple")

z975 <- qnorm(0.975); z80 <- qnorm(0.80)

nulls <- raw %>%
  filter(shape == "expo_ramp", lag == 0, delta == 0) %>%
  group_by(design) %>%
  summarise(n0 = n(), mean0 = mean(att), sd0 = sd(att),
            q025 = quantile(att, .025), q975 = quantile(att, .975),
            .groups = "drop")

oracle <- raw %>%
  filter(delta > 0) %>%
  group_by(design, shape, lag, delta) %>%
  summarise(n = n(), mean_att = mean(att), mean_true = mean(true_att),
            .groups = "drop") %>%
  left_join(nulls, by = "design") %>%
  mutate(
    shift = mean_att - mean0,
    dose  = mean_true / delta,
    power_emp = NA_real_,   # filled below (needs draws)
    power_norm = pnorm(-z975 + shift / sd0) + pnorm(-z975 - shift / sd0)
  )

# empirical size-corrected power needs the draws
emp <- raw %>%
  filter(delta > 0) %>%
  left_join(nulls %>% select(design, q025, q975), by = "design") %>%
  group_by(design, shape, lag, delta) %>%
  summarise(power_emp = mean(att < q025 | att > q975), .groups = "drop")
oracle <- oracle %>%
  select(-power_emp) %>%
  left_join(emp, by = c("design", "shape", "lag", "delta"))

# oracle MDE on the mature-effect scale, per design (headline ramp DGP)
mde <- oracle %>%
  filter(shape == "expo_ramp", lag == 0) %>%
  group_by(design) %>%
  summarise(sd0 = first(sd0),
            dose_ratio = mean(dose),
            mde_att_scale    = (z975 + z80) * sd0,
            mde_mature_scale = (z975 + z80) * sd0 / dose_ratio,
            .groups = "drop")

write_csv(oracle, file.path(cfg$out_dir, "oracle_power.csv"))
write_csv(mde,    file.path(cfg$out_dir, "oracle_mde.csv"))

cat("===== ORACLE POWER (perfectly calibrated test; ramp DGP unless noted) =====\n")
print(as.data.frame(oracle %>%
        filter(shape == "expo_ramp", lag == 0) %>%
        select(design, delta, mean_true, shift, sd0, power_emp, power_norm)),
      row.names = FALSE, digits = 3)

cat("\n===== ORACLE 80% MDE =====\n")
cat("(att scale = shift the estimand must move; mature scale = mature gambling\n")
cat(" effect needed given the ramp's dose dilution)\n")
print(as.data.frame(mde), row.names = FALSE, digits = 3)

cat("\n===== step / lag arms (delta = 0.025) =====\n")
print(as.data.frame(oracle %>%
        filter(delta == 0.025) %>%
        select(design, shape, lag, shift, sd0, power_emp, power_norm)),
      row.names = FALSE, digits = 3)

p <- oracle %>%
  filter(shape == "expo_ramp", lag == 0) %>%
  ggplot(aes(delta, power_norm, color = design)) +
  geom_hline(yintercept = .05, linetype = "dotted") +
  geom_hline(yintercept = .80, linetype = "dashed") +
  geom_line() + geom_point() +
  geom_line(aes(y = power_emp), linetype = "dashed") +
  scale_x_continuous(labels = scales::percent_format(accuracy = .1)) +
  scale_color_brewer(palette = "Set2") +
  labs(x = "Mature proportional effect", y = "Oracle power (solid norm, dashed emp)",
       color = NULL)
ggsave(file.path(cfg$out_dir, "figures", "oracle_power_curves.pdf"),
       p, width = 7.5, height = 5)
cat("\nWritten: oracle_power.csv, oracle_mde.csv, figures/oracle_power_curves.pdf\n")
