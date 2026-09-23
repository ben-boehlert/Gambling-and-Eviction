################################################################################
# prewindow_trends_influence.R
#
# Is the negative pre-window differential trend driven by one state?
# Companion to analysis/pretrends/prewindow_differential_trends.R.
#
#   (1) per-state own slope of the outcome on centered month
#   (2) leave-one-state-out refits of the differential trend
#   (3) leave-one-source-out (the ETS internal extract states)
#
# Window 2021-07..2022-06, log(1 + filings per 1k renters), state + month FE,
# state-clustered SEs. Pre-treatment only.
################################################################################

suppressPackageStartupMessages({library(tidyverse); library(fixest)})
source("utils/eviction_treatment_schedule.R")
theme_set(theme_minimal(base_size = 11))

SCHED <- "data/raw/sports_gambling_legalization_dates.csv"
EXCLUDE <- toupper(trimws(strsplit(Sys.getenv("EXCLUDE_STATES", ""), ",")[[1]]))
EXCLUDE <- EXCLUDE[nzchar(EXCLUDE)]
OUT <- if (length(EXCLUDE)) paste0("output/prewindow_trends_2021h2_ex", paste(EXCLUDE, collapse="")) else "output/prewindow_trends_2021h2"
W0 <- as.Date("2021-07-01"); W1 <- as.Date("2022-06-01"); CUTOFF <- as.Date("2022-06-01")

pan <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date))
sched <- load_eviction_treatment_schedule(SCHED, "online_start_date",
                                          states = EVICTION_STATE_UNIVERSE)
ps <- sort(unique(pan$state_abb))
CT_CONTROL <- suppressWarnings(
  eviction_control_states(ps, SCHED, "online_start_date", censor_end = as.Date("2026-06-01")))
CT_TREATED <- sched %>% filter(state_abb %in% ps, !is.na(treat_start),
                               treat_start > CUTOFF) %>% pull(state_abb) %>% sort()

if (length(EXCLUDE)) {
  message("Excluding by request: ", paste(EXCLUDE, collapse = " "))
  CT_TREATED <- setdiff(CT_TREATED, EXCLUDE)
  CT_CONTROL <- setdiff(CT_CONTROL, EXCLUDE)
}


d <- pan %>%
  filter(state_abb %in% .env$CT_TREATED | state_abb %in% .env$CT_CONTROL,
         month_date >= W0, month_date <= W1, !is.na(filings_per_1k_renters)) %>%
  mutate(D = as.integer(state_abb %in% .env$CT_TREATED))
nf <- n_distinct(d$month_date)
d  <- d %>% group_by(state_abb) %>% filter(n() == nf) %>% ungroup() %>%
  mutate(tnum = as.integer(factor(month_date)),
         tc   = tnum - mean(sort(unique(tnum))),
         Dt   = D * tc,
         y    = log1p(filings_per_1k_renters),
         mfac = factor(month_date), state_abb = factor(state_abb)) %>%
  as.data.frame()

fitT1 <- function(dd) {
  m <- feols(y ~ Dt | state_abb + mfac, data = dd, cluster = ~state_abb)
  c(b = unname(coef(m)["Dt"]), se = unname(se(m)["Dt"]))
}
base <- fitT1(d)
cat(sprintf("\nFull sample: b = %+.5f (SE %.5f), %d states\n\n",
            base["b"], base["se"], n_distinct(d$state_abb)))

# ---- (1) per-state own slope --------------------------------------------------
slopes <- d %>% group_by(state_abb, D, panel_source) %>%
  summarise(slope = unname(coef(lm(y ~ tc))[2]),
            mean_y = mean(y), .groups = "drop") %>%
  mutate(group = if_else(D == 1, "later adopter", "never-legalizer")) %>%
  arrange(desc(slope))

# ---- (2) leave-one-state-out --------------------------------------------------
loo <- map_dfr(levels(d$state_abb), function(s) {
  f <- fitT1(droplevels(filter(d, state_abb != s)))
  tibble(dropped = s,
         group = if_else(s %in% CT_TREATED, "later adopter", "never-legalizer"),
         b = f["b"], se = f["se"], t = f["b"] / f["se"],
         shift = f["b"] - base["b"])
}) %>% arrange(desc(abs(shift)))

# ---- (3) leave-one-source-out -------------------------------------------------
src <- d %>% distinct(state_abb, panel_source)
lso <- map_dfr(sort(unique(as.character(src$panel_source))), function(sc) {
  keep <- src$state_abb[src$panel_source != sc]
  dd <- droplevels(filter(d, state_abb %in% keep))
  if (n_distinct(dd$D) < 2 || n_distinct(dd$state_abb) < 6) return(tibble())
  f <- fitT1(dd)
  tibble(dropped_source = sc, n_states_dropped = sum(src$panel_source == sc),
         b = f["b"], se = f["se"], t = f["b"] / f["se"])
})

cat("== per-state own slope (log pts/month), sorted ==\n")
print(as.data.frame(slopes %>% select(state_abb, group, slope, panel_source)), digits = 3)
cat("\n== leave-one-state-out, most influential first ==\n")
print(as.data.frame(loo), digits = 3)
cat("\n== leave-one-source-out ==\n")
print(as.data.frame(lso), digits = 3)

write_csv(slopes, file.path(OUT, "influence_per_state_slopes.csv"))
write_csv(loo,    file.path(OUT, "influence_leave_one_out.csv"))
write_csv(lso,    file.path(OUT, "influence_leave_one_source_out.csv"))

pl <- ggplot(loo, aes(reorder(dropped, b), b, colour = group)) +
  geom_hline(yintercept = base["b"], linetype = 2, linewidth = 0.3) +
  geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey40") +
  geom_pointrange(aes(ymin = b - 1.96 * se, ymax = b + 1.96 * se), size = 0.3) +
  coord_flip() +
  scale_colour_manual(values = c("later adopter" = "#B2182B",
                                 "never-legalizer" = "#2166AC")) +
  labs(x = "State dropped", y = "Differential trend, log pts/month", colour = NULL,
       subtitle = "Leave-one-state-out. Dashed line = full-sample estimate.")
ggsave(file.path(OUT, "influence_leave_one_out.png"), pl, width = 7, height = 6, dpi = 200)
cat("\nWrote influence outputs to ", OUT, "\n")
