# =============================================================================
# plot_mo_leverage.R  (2026-09-14)
#
# Why the real `cor_date_trend` = -0.212 should not be read as a magnitude:
# Missouri alone carries it. Dropping MO moves the correlation to -0.055.
#
# Panel A: adoption timing vs each state's own real trend slope, with the fit
#          through all 24 states and the fit excluding MO.
# Panel B: leave-one-state-out jackknife of the correlation -- MO is the single
#          extreme influence point; every other state moves it very little.
#
# Companion to docs/findings-archive/nullbias-recentering-premise-check_2026-09-14.md
# Descriptive slopes + real adoption dates only; no estimation: blindness-safe.
#
# Output: figures/mo_leverage_cor_date_trend.{png,pdf}
# =============================================================================

suppressPackageStartupMessages({
  library(tidyverse); library(lubridate); library(patchwork); library(glue)
})
theme_set(theme_minimal(base_size = 11))

CS <- as.Date("2020-03-01"); CE <- as.Date("2021-07-31")
EXCL <- c("NV", "ID", "HI", "MS")
dir.create("figures", showWarnings = FALSE)

pan <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date)) %>%
  filter(month_date < CS | month_date > CE) %>%
  mutate(y = log1p(filings_count))

# Per-state trend slope in log points per YEAR, plus the calendar window the
# slope was actually fit on (MO's is the story).
slopes <- pan %>% group_by(state_abb) %>% filter(n() >= 24) %>%
  summarise(slope   = coef(lm(y ~ as.numeric(month_date)))[2] * 365.25,
            n_month = n(), win_lo = min(month_date), win_hi = max(month_date),
            .groups = "drop")

ab <- c(Delaware="DE",`New Jersey`="NJ",`West Virginia`="WV",Pennsylvania="PA",
  `Rhode Island`="RI",Arkansas="AR",`New York`="NY",Iowa="IA",Indiana="IN",Oregon="OR",
  `New Hampshire`="NH",Illinois="IL",Michigan="MI",Colorado="CO",`District of Columbia`="DC",
  Tennessee="TN",Virginia="VA",`North Carolina`="NC",Arizona="AZ",Wyoming="WY",
  Connecticut="CT",Louisiana="LA",Maryland="MD",Kansas="KS",Massachusetts="MA",Ohio="OH",
  Kentucky="KY",Maine="ME",Florida="FL",Vermont="VT",Missouri="MO")
sched <- read_csv("data/raw/sports_gambling_legalization_dates.csv", show_col_types = FALSE) %>%
  filter(!is.na(online_start_date)) %>%
  mutate(online = as.Date(online_start_date), st = ab[state])

d <- slopes %>% inner_join(sched %>% select(st, online), by = c("state_abb" = "st")) %>%
  filter(!state_abb %in% EXCL) %>%
  mutate(is_mo = state_abb == "MO")

r_all <- cor(as.numeric(d$online), d$slope)
d_no  <- d %>% filter(!is_mo)
r_no  <- cor(as.numeric(d_no$online), d_no$slope)

lab <- glue("all {nrow(d)} states: r = {sprintf('%+.3f', r_all)}")
lab_no <- glue("excluding MO: r = {sprintf('%+.3f', r_no)}")

pA <- ggplot(d, aes(online, slope)) +
  geom_hline(yintercept = 0, colour = "grey80", linewidth = 0.3) +
  geom_smooth(method = "lm", se = FALSE, aes(colour = "all"), linewidth = 0.8) +
  geom_smooth(data = d_no, method = "lm", se = FALSE,
              aes(colour = "noMO"), linewidth = 0.8, linetype = "22") +
  geom_point(aes(fill = is_mo, size = is_mo), shape = 21, colour = "white", stroke = 0.5) +
  ggrepel::geom_text_repel(aes(label = state_abb, fontface = ifelse(is_mo, "bold", "plain")),
                           size = 2.7, colour = "grey25", max.overlaps = 30,
                           segment.colour = "grey75", segment.size = 0.25) +
  scale_fill_manual(values = c(`FALSE` = "#2C7FB8", `TRUE` = "#D94801"), guide = "none") +
  scale_size_manual(values = c(`FALSE` = 2.1, `TRUE` = 3.6), guide = "none") +
  scale_colour_manual(name = NULL, values = c(all = "#B2182B", noMO = "#1A9850"),
                      labels = c(all = lab, noMO = lab_no)) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  labs(x = "Online legalization date", y = "Own trend slope (log points per year)") +
  theme(legend.position = "bottom", panel.grid.minor = element_blank())

# Panel B: leave-one-out jackknife
jk <- map_dfr(seq_len(nrow(d)), function(i) {
  dd <- d[-i, ]
  tibble(dropped = d$state_abb[i], r = cor(as.numeric(dd$online), dd$slope))
}) %>% mutate(is_mo = dropped == "MO",
              dropped = fct_reorder(dropped, r))

pB <- ggplot(jk, aes(r, dropped, fill = is_mo)) +
  geom_vline(xintercept = r_all, colour = "#B2182B", linewidth = 0.5) +
  geom_vline(xintercept = 0, colour = "grey80", linewidth = 0.3) +
  geom_point(shape = 21, size = 2.4, colour = "white", stroke = 0.4) +
  scale_fill_manual(values = c(`FALSE` = "#2C7FB8", `TRUE` = "#D94801"), guide = "none") +
  labs(x = "Correlation with that state dropped", y = NULL) +
  theme(panel.grid.major.y = element_blank(), panel.grid.minor = element_blank(),
        axis.text.y = element_text(size = 7.5))

p <- pA + pB + plot_layout(widths = c(2.05, 1)) + plot_annotation(tag_levels = "a")

ggsave("figures/mo_leverage_cor_date_trend.png", p, width = 11, height = 5.6, dpi = 220, bg = "white")
ggsave("figures/mo_leverage_cor_date_trend.pdf", p, width = 11, height = 5.6, bg = "white")

cat(sprintf("\nr(all %d) = %+.4f   r(ex MO) = %+.4f\n", nrow(d), r_all, r_no))
cat("\nMO vs the rest:\n")
print(as.data.frame(d %>% filter(is_mo) %>%
      select(state_abb, online, slope, n_month, win_lo, win_hi)), row.names = FALSE)
cat(sprintf("\nother 23 states: slope window typically %s .. %s; MO's ends %s\n",
            median(d_no$win_lo), median(d_no$win_hi), d$win_hi[d$is_mo]))
cat(sprintf("next-latest adopter after MO: %s (%s), a gap of %d months\n",
            d_no$state_abb[which.max(d_no$online)], max(d_no$online),
            interval(max(d_no$online), d$online[d$is_mo]) %/% months(1)))
message("Wrote figures/mo_leverage_cor_date_trend.{png,pdf}")
