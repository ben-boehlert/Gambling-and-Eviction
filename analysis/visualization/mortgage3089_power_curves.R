################################################################################
# mortgage3089_power_curves.R  (2026-09-29)
# Power curves from mortgage3089_lpdid_l618_start202206_v20260929 (30-89 day
# mortgage delinquency, log rate, June-2022 LP-DiD design): rejection rate at
# alpha 0.05 (recentered, as for the pre-registered MDEs) vs imposed effect,
# by estimator x inference x placement arm. Simulated data only.
# Run from the project root: Rscript analysis/visualization/mortgage3089_power_curves.R
################################################################################
suppressPackageStartupMessages({ library(dplyr); library(readr); library(ggplot2) })
theme_set(theme_minimal(base_family = "serif"))
d <- read_csv("output_blinded_power/mortgage3089_lpdid_l618_start202206_v20260929/oc_summary.csv",
              show_col_types = FALSE) %>%
  mutate(arm = sub("-state_mortgage.*", "", sub("^S[0-9a-f]+_", "", scenario_id))) %>%
  filter(grepl("_mde$", arm)) %>%
  mutate(arm = recode(arm, precovid_mde = "Pre-COVID placement (10 T / 40 C)",
                      start202206_mde = "Real-era placement (6 T / 13 C)"),
         spec = paste(toupper(estimator), inference),
         effect_pct = 100 * (exp(delta) - 1))
p <- ggplot(d, aes(effect_pct, reject_rc_005, linetype = spec, shape = spec)) +
  geom_hline(yintercept = c(0.05, 0.8), colour = "grey70") +
  geom_line() + geom_point(size = 1.4) +
  facet_wrap(~ arm, ncol = 1) +
  scale_x_continuous(breaks = seq(0, 80, 10)) +
  scale_y_continuous(breaks = c(0, 0.05, 0.2, 0.4, 0.6, 0.8, 1)) +
  coord_cartesian(xlim = c(0, 40)) +
  labs(x = "Imposed effect on the 30-89 day delinquency rate (%)",
       y = "Rejection rate at 5% (recentered)", linetype = NULL, shape = NULL) +
  theme(legend.position = "bottom")
ggsave("figures/mortgage3089_power_curves.pdf", p, width = 6.5, height = 6)
ggsave("figures/mortgage3089_power_curves.png", p, width = 6.5, height = 6, dpi = 300)
