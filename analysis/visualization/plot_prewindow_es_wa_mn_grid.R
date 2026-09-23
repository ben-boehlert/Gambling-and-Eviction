################################################################################
# plot_prewindow_es_wa_mn_grid.R
#
# Event studies for the pre-window differential-trend diagnostic across the
# WA x MN inclusion 2x2:
#     both WA and MN | only WA (MN out) | only MN (WA out) | neither
# shown for each window start in PLOT_WINDOWS (default 2021-07 and 2021-08).
#
# Event-study coefficients are cheap, so this script estimates them itself
# rather than reading the full battery's CSVs -- no permutation loops involved.
# Inference shown is state-clustered analytic only; for wild-bootstrap and
# randomization p-values see analysis/pretrends/prewindow_differential_trends.R.
#
# All coefficients are PRE-TREATMENT: first adoption is KS, 2022-09.
################################################################################

suppressPackageStartupMessages({library(tidyverse); library(fixest); library(lubridate)})
theme_set(theme_minimal(base_size = 11))
source("utils/eviction_treatment_schedule.R")

SCH <- "data/raw/sports_gambling_legalization_dates.csv"
OUT <- "output/prewindow_trends_2021h2"
WSTARTS <- strsplit(Sys.getenv("PLOT_WINDOWS", "2021-07-01,2021-08-01"), ",")[[1]]
WEND <- as.Date("2022-06-01")

SAMPLES <- list(
  "both WA and MN" = character(0),
  "only WA (MN out)" = "MN",
  "only MN (WA out)" = "WA",
  "neither"          = c("WA", "MN")
)

pan <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date))
sched <- load_eviction_treatment_schedule(SCH, "online_start_date",
                                          states = EVICTION_STATE_UNIVERSE)
ps <- sort(unique(pan$state_abb))
CT_CONTROL <- suppressWarnings(
  eviction_control_states(ps, SCH, "online_start_date", censor_end = as.Date("2026-06-01")))
CT_TREATED <- sched %>% filter(state_abb %in% ps, !is.na(treat_start),
                               treat_start > as.Date("2022-06-01")) %>%
  pull(state_abb) %>% sort()

build <- function(w0, drop) {
  tt <- setdiff(CT_TREATED, drop); cc <- setdiff(CT_CONTROL, drop)
  d <- pan %>%
    filter(state_abb %in% c(tt, cc), month_date >= as.Date(w0), month_date <= WEND,
           !is.na(filings_per_1k_renters)) %>%
    mutate(D = as.integer(state_abb %in% tt))
  nf <- n_distinct(d$month_date)
  d %>% group_by(state_abb) %>% filter(n() == nf) %>% ungroup() %>%
    mutate(tnum = as.integer(factor(month_date)),
           tc   = tnum - mean(sort(unique(tnum))), Dt = D * tc,
           y    = log1p(filings_per_1k_renters),
           mfac = factor(month_date), state_abb = factor(state_abb)) %>%
    as.data.frame()
}

res <- list(); tab <- list()
for (w0 in WSTARTS) for (sn in names(SAMPLES)) {
  d  <- build(w0, SAMPLES[[sn]])
  m  <- feols(y ~ i(tnum, D, ref = 1) | state_abb + mfac, data = d, cluster = ~state_abb)
  m1 <- feols(y ~ Dt | state_abb + mfac, data = d, cluster = ~state_abb)
  wj <- wald(m, "tnum::", print = FALSE)
  k  <- grep("^tnum::", names(coef(m)), value = TRUE)

  res[[length(res) + 1]] <- bind_rows(
    tibble(period = as.integer(sub("^tnum::([0-9]+):.*$", "\\1", k)),
           estimate = unname(coef(m)[k]), se = unname(se(m)[k])),
    tibble(period = 1L, estimate = 0, se = 0)) %>%
    mutate(window = w0, sample = sn,
           month = as.Date(w0) %m+% months(period - 1L))

  tab[[length(tab) + 1]] <- tibble(
    window = w0, sample = sn,
    n_states = n_distinct(d$state_abb),
    n_months = n_distinct(d$month_date),
    trend = unname(coef(m1)["Dt"]), trend_se = unname(se(m1)["Dt"]),
    t = unname(coef(m1)["Dt"] / se(m1)["Dt"]),
    joint_wald_p = wj$p,
    endpoint = unname(coef(m)[tail(k, 1)]), endpoint_se = unname(se(m)[tail(k, 1)]))
}
es  <- bind_rows(res) %>%
  mutate(sample = factor(sample, levels = names(SAMPLES)),
         window = factor(window, levels = WSTARTS,
                         labels = paste("Window starts", substr(WSTARTS, 1, 7))))
sm <- bind_rows(tab)

cat("\n== linear trend and joint test by sample x window (log, unweighted) ==\n")
print(as.data.frame(sm %>% mutate(window = substr(window, 1, 7))), digits = 3)
TAGC <- paste(substr(WSTARTS, 1, 7), collapse = "_")
write_csv(sm, file.path(OUT, paste0("es_wa_mn_grid_summary_", TAGC, ".csv")))
write_csv(es, file.path(OUT, paste0("es_wa_mn_grid_coefs_", TAGC, ".csv")))

p <- ggplot(es, aes(month, estimate)) +
  geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey40") +
  geom_ribbon(aes(ymin = estimate - 1.96 * se, ymax = estimate + 1.96 * se),
              alpha = 0.15, fill = "#2166AC") +
  geom_line(linewidth = 0.5, colour = "#2166AC") +
  geom_point(size = 1.5, colour = "#2166AC") +
  # one window -> 2x2 of samples; several windows -> sample rows x window cols
  (if (length(WSTARTS) == 1) facet_wrap(~sample, ncol = 2)
   else facet_grid(sample ~ window)) +
  scale_x_date(date_labels = "%b\n%Y",
               date_breaks = if (length(WSTARTS) == 1) "1 month" else "2 months") +
  labs(x = NULL, y = "Later adopters minus never-legalizers (log points)",
       title = if (length(WSTARTS) == 1)
                 paste("Window starts", substr(WSTARTS, 1, 7)) else NULL,
       subtitle = paste0("Pre-treatment only; earliest adoption 2022-09. State and month FE, ",
                         "state-clustered 95% bands.\nEach window's first month normalized to zero."))
# window tag in the filename so runs for different windows never overwrite
# each other (they did once, 2026-09-18)
TAG <- paste(substr(WSTARTS, 1, 7), collapse = "_")
ggsave(file.path(OUT, paste0("event_study_wa_mn_grid_", TAG, ".png")), p,
       width  = if (length(WSTARTS) == 1) 9 else 3.6 * length(WSTARTS) + 2.2,
       height = if (length(WSTARTS) == 1) 6.5 else 9, dpi = 200)

q <- ggplot(es, aes(month, estimate, colour = sample, group = sample)) +
  geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey40") +
  geom_line(linewidth = 0.6) + geom_point(size = 1.3) +
  facet_wrap(~window) +
  scale_colour_manual(values = c("both WA and MN" = "#B2182B", "only WA (MN out)" = "#EF8A62",
                                 "only MN (WA out)" = "#67A9CF", "neither" = "#2166AC")) +
  scale_x_date(date_labels = "%b\n%Y", date_breaks = "2 months") +
  labs(x = NULL, y = "Later adopters minus never-legalizers (log points)", colour = NULL,
       subtitle = "Same four samples overlaid, point estimates only (CIs omitted for legibility).")
ggsave(file.path(OUT, paste0("event_study_wa_mn_overlay_", TAG, ".png")), q,
       width = 4.2 * length(WSTARTS) + 1.6, height = 4.6, dpi = 200)

cat("\nWrote:\n  ", file.path(OUT, paste0("event_study_wa_mn_grid_", TAG, ".png")),
    "\n  ", file.path(OUT, paste0("event_study_wa_mn_overlay_", TAG, ".png")), "\n")
