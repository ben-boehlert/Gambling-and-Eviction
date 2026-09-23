################################################################################
# plot_prewindow_event_studies.R
#
# Event-study plots for the pre-window differential-trend diagnostic, for the
# 2021-07 and 2021-08 window starts, full sample vs ex-WA/MN.
#
# Reads the coefficient CSVs written by
#   analysis/pretrends/prewindow_differential_trends.R
# (run it once bare and once with EXCLUDE_STATES="WA,MN" first).
#
# Every point is PRE-TREATMENT: the first adopter in the treated arm legalizes
# 2022-09, after all of these windows close. Base month is each window's own
# first month, normalized to zero.
################################################################################

suppressPackageStartupMessages({library(tidyverse)})
theme_set(theme_minimal(base_size = 11))

DIRS <- c("full sample (25/26 states)"  = "output/prewindow_trends_2021h2",
          "ex WA, MN (24 states)"       = "output/prewindow_trends_2021h2_exWAMN")
WINDOWS <- strsplit(Sys.getenv("PLOT_WINDOWS",
  "2021-07..2022-06,2021-08..2022-06"), ",")[[1]]
OUT <- "output/prewindow_trends_2021h2"

start_of <- function(w) as.Date(paste0(sub("\\.\\..*$", "", w), "-01"))

es <- imap_dfr(DIRS, function(dir, lab) {
  f <- file.path(dir, "prewindow_event_study_coefs.csv")
  stopifnot(file.exists(f))
  read_csv(f, show_col_types = FALSE) %>% mutate(sample = lab)
}) %>%
  filter(window %in% WINDOWS, outcome == "y_log") %>%
  select(sample, window, period, estimate, se)

# add each window's normalized base period
base <- es %>% distinct(sample, window) %>% mutate(period = 1L, estimate = 0, se = 0)

es <- bind_rows(es, base) %>%
  mutate(month = start_of(window) %m+% months(period - 1L),
         sample = factor(sample, levels = names(DIRS)),
         window = factor(window, levels = WINDOWS,
                         labels = paste("Window starts", sub("\\.\\..*$", "", WINDOWS))))

p <- ggplot(es, aes(month, estimate)) +
  geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey40") +
  geom_ribbon(aes(ymin = estimate - 1.96 * se, ymax = estimate + 1.96 * se),
              alpha = 0.15, fill = "#2166AC") +
  geom_line(linewidth = 0.5, colour = "#2166AC") +
  geom_point(size = 1.6, colour = "#2166AC") +
  facet_grid(sample ~ window) +
  scale_x_date(date_labels = "%b\n%Y", date_breaks = "2 months") +
  labs(x = NULL,
       y = "Later adopters minus never-legalizers\n(log points)",
       subtitle = paste0("Pre-treatment only: post-June-2022 online adopters vs never-legalizers. ",
                         "Earliest adoption is 2022-09.\n",
                         "State and month fixed effects; state-clustered 95% bands; ",
                         "each window's first month normalized to zero."))

fn <- paste0("event_study_", paste(sub("\\.\\..*$", "", WINDOWS), collapse = "_and_"), ".png")
ggsave(file.path(OUT, fn), p, width = 3.4 * length(WINDOWS) + 2.4, height = 6, dpi = 200)
cat("Wrote ", file.path(OUT, fn), "\n")

cat("\n== endpoint (final month) coefficients, log points ==\n")
es %>% group_by(sample, window) %>% slice_max(month, n = 1) %>%
  transmute(sample, window, month, estimate = round(estimate, 4),
            lo = round(estimate - 1.96 * se, 4), hi = round(estimate + 1.96 * se, 4)) %>%
  ungroup() %>% as.data.frame() %>% print()
