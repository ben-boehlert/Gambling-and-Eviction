#!/usr/bin/env Rscript
################################################################################
# analysis/cheap_sims/03_summarize.R
#
# Summarize the cheap Monte Carlo grid: operating characteristics per
# design x DGP, power curves, null-size table, coarse 80%-power MDE, runtime
# report. Reads <out_dir>/results_raw.csv (02_run_cheap_grid.R output).
#
# Run from repo root:  Rscript analysis/cheap_sims/03_summarize.R
#   (CHEAP_OUT_DIR to point at a smoke dir)
################################################################################

source("analysis/cheap_sims/00_common.R")
theme_set(theme_minimal())

cfg <- cheap_config()
fig_dir <- file.path(cfg$out_dir, "figures")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

raw <- read_csv(file.path(cfg$out_dir, "results_raw.csv"),
                show_col_types = FALSE) %>%
  filter(!is.na(design))

alpha <- cfg$alpha

# ---- operating characteristics ---------------------------------------------

summ <- raw %>%
  filter(converged) %>%
  group_by(design, shape, delta, lag) %>%
  summarise(
    n_reps      = n(),
    reject_05   = mean(p < alpha, na.rm = TRUE),
    reject_10   = mean(p < 0.10, na.rm = TRUE),
    mean_att    = mean(att),
    sd_att      = sd(att),
    mean_true   = mean(true_att),
    bias        = mean(att - true_att),
    rmse        = sqrt(mean((att - true_att)^2)),
    coverage_95 = mean(ci_lo <= true_att & true_att <= ci_hi, na.rm = TRUE),
    mean_se     = mean(se),
    se_over_sd  = mean(se) / sd(att),
    sign_err_given_sig = {
      sig <- p < alpha & true_att > 0
      if (any(sig)) mean(att[sig] < 0) else NA_real_
    },
    exaggeration_given_sig = {
      sig <- p < alpha & true_att > 0
      if (any(sig)) mean(att[sig] / true_att[sig]) else NA_real_
    },
    mean_cells  = mean(n_cells),
    mean_runtime_s = mean(runtime_s, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(design, shape, lag, delta)

conv <- raw %>%
  group_by(design, shape, delta, lag) %>%
  summarise(n_total = n(), conv_share = mean(converged), .groups = "drop")
summ <- summ %>% left_join(conv, by = c("design", "shape", "delta", "lag"))

write_csv(summ, file.path(cfg$out_dir, "cheap_power_sim_summary.csv"))

# ---- null-size table --------------------------------------------------------

null_tab <- summ %>%
  filter(delta == 0) %>%
  select(design, n_reps, reject_05, reject_10, mean_att, sd_att, mean_se,
         se_over_sd, coverage_95)
write_csv(null_tab, file.path(cfg$out_dir, "null_size_table.csv"))
cat("\n===== NULL SIZE (delta = 0; nominal 5%) =====\n")
print(as.data.frame(null_tab), row.names = FALSE, digits = 3)

# ---- power table + coarse MDE ----------------------------------------------

interp_mde <- function(delta, power, target = 0.80) {
  ok <- is.finite(delta) & is.finite(power)
  delta <- delta[ok]; power <- pmin(pmax(power[ok], 1e-3), 1 - 1e-3)
  if (length(delta) < 2L) return(NA_real_)
  fit <- lm(qnorm(power) ~ delta)
  m <- (qnorm(target) - coef(fit)[1]) / coef(fit)[2]
  if (!is.finite(m) || m < 0) NA_real_ else as.numeric(m)
}

power_tab <- summ %>%
  filter(shape == "expo_ramp", lag == 0) %>%
  select(design, delta, reject_05) %>%
  pivot_wider(names_from = delta, values_from = reject_05,
              names_prefix = "power_d")
mde_tab <- summ %>%
  filter(shape == "expo_ramp", lag == 0) %>%
  group_by(design) %>%
  summarise(mde_80 = interp_mde(delta, reject_05), .groups = "drop") %>%
  mutate(extrapolated = mde_80 > 0.05)
power_tab <- power_tab %>% left_join(mde_tab, by = "design")
write_csv(power_tab, file.path(cfg$out_dir, "power_by_design_table.csv"))
cat("\n===== POWER (ramp DGP, lag 0; mature delta) + coarse 80% MDE =====\n")
print(as.data.frame(power_tab), row.names = FALSE, digits = 3)

# ---- ramp vs step, lag comparison ------------------------------------------

cmp <- summ %>%
  filter(delta > 0) %>%
  mutate(dgp = case_when(
    shape == "step" ~ "step (immediate)",
    lag == 0        ~ "ramp, contemporaneous",
    TRUE            ~ sprintf("ramp, %d-mo outcome lag", lag))) %>%
  select(design, dgp, delta, reject_05, mean_true, bias, rmse, coverage_95)
write_csv(cmp, file.path(cfg$out_dir, "dgp_comparison_table.csv"))
cat("\n===== DGP comparison (power at each mature delta) =====\n")
print(as.data.frame(cmp %>% filter(design %in% c("full", "covid_clean")) %>%
                      arrange(design, delta, dgp)),
      row.names = FALSE, digits = 3)

# ---- figures ----------------------------------------------------------------

design_lvls <- c(full = "Full", covid_clean = "COVID-clean",
                 pre_covid = "Early / pre-COVID", post_covid = "Late / post-COVID",
                 cross_covid = "Cross-COVID only")

pw <- summ %>%
  filter(shape == "expo_ramp", lag == 0, design %in% names(design_lvls)) %>%
  mutate(design_lab = factor(design_lvls[design], levels = unname(design_lvls)))

p_power <- ggplot(pw, aes(delta, reject_05, color = design_lab)) +
  geom_hline(yintercept = alpha, linetype = "dotted", color = "grey40") +
  geom_hline(yintercept = 0.80, linetype = "dashed", color = "grey40") +
  geom_line() + geom_point() +
  scale_x_continuous(labels = scales::percent_format(accuracy = 0.1)) +
  scale_y_continuous(limits = c(0, 1)) +
  scale_color_brewer(palette = "Set2") +
  labs(x = "Mature proportional effect (log points)",
       y = "Rejection probability (nominal 5% test)", color = NULL)
ggsave(file.path(fig_dir, "power_curves_by_design.pdf"), p_power,
       width = 7.5, height = 5)

p_null <- summ %>%
  filter(delta == 0, design %in% names(design_lvls)) %>%
  mutate(design_lab = factor(design_lvls[design], levels = unname(design_lvls)),
         mc_se = sqrt(reject_05 * (1 - reject_05) / n_reps)) %>%
  ggplot(aes(design_lab, reject_05)) +
  geom_col(fill = "grey65") +
  geom_errorbar(aes(ymin = pmax(0, reject_05 - 1.96 * mc_se),
                    ymax = reject_05 + 1.96 * mc_se), width = .2) +
  geom_hline(yintercept = alpha, linetype = "dashed", color = "firebrick") +
  labs(x = NULL, y = "Null rejection rate (target 0.05)")
ggsave(file.path(fig_dir, "null_size_by_design.pdf"), p_null,
       width = 7, height = 4.5)

# placebo ATT distributions under the null
p_dist <- raw %>%
  filter(delta == 0, converged, design %in% names(design_lvls)) %>%
  mutate(design_lab = factor(design_lvls[design], levels = unname(design_lvls))) %>%
  ggplot(aes(att)) +
  geom_histogram(bins = 30, fill = "grey70", color = "white") +
  geom_vline(xintercept = 0, linetype = "dashed") +
  facet_wrap(~design_lab, scales = "free") +
  labs(x = "Placebo ATT (log points)", y = "Replications")
ggsave(file.path(fig_dir, "null_att_distributions.pdf"), p_dist,
       width = 9, height = 5.5)

# ---- runtime report ---------------------------------------------------------

rt <- raw %>%
  distinct(rep, shape, delta, lag, runtime_s) %>%
  summarise(mean_fit_s = mean(runtime_s, na.rm = TRUE),
            fits_per_rep = n() / n_distinct(rep))
rep_s <- rt$mean_fit_s * rt$fits_per_rep
runtime <- tibble(
  mean_seconds_per_fit = rt$mean_fit_s,
  fits_per_rep = rt$fits_per_rep,
  seconds_per_rep_serial = rep_s,
  hours_250_reps_serial  = 250 * rep_s / 3600,
  hours_1000_reps_serial = 1000 * rep_s / 3600,
  hours_2500_reps_serial = 2500 * rep_s / 3600,
  hours_250_reps_8cores  = 250 * rep_s / 3600 / 8,
  della_warranted = 2500 * rep_s / 3600 / 8 > 12
)
write_csv(runtime, file.path(cfg$out_dir, "runtime_report.csv"))
cat("\n===== RUNTIME =====\n")
print(as.data.frame(runtime), row.names = FALSE, digits = 3)

cat("\nSummary written to", file.path(cfg$out_dir, "cheap_power_sim_summary.csv"), "\n")
