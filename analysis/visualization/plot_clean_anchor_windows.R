# =============================================================================
# plot_clean_anchor_windows.R  (2026-09-14)
#
# Design figure for the clean-anchor spec: for every online-legalizing state,
# draw the 6-month pre-launch baseline, the 12-month buildup (excluded from the
# outcome), and the 12-24 month outcome window -- against the COVID splice and
# that state's actual panel coverage.
#
# Purpose: show at a glance WHY only ~12 states are switchers. The answer is
# the interaction of launch timing with the COVID gap and series coverage,
# not the number of legalizers.
#
# treat_def = online_start_date (the headline definition). Retail-only states
# have no online date and are not switchers under this spec; they are listed in
# the console output, not drawn.
#
# STATUS FLAGS ARE THE ESTIMATOR'S OWN INCLUSION RULE, not a coverage heuristic.
# Reconciled 2026-09-14 against R/power/run_estimators.R `.re_lpdid`, anchor
# "event_clean" (lines ~1232-1265), driven by
# config/power_lpdid_shift12_clean_gate_ewatt_pmd6.yml:
#
#   * anchor: cell is (event = shift12 = launch+12, base = launch, h);
#     hmin = 0, hmax = lpdid_post = 12  =>  outcome months = launch+12 .. +24.
#   * baseline: `lpdid_pmd_min` is ABSENT from the config, so the STRICT regime
#     applies -- B = rowMeans of the PMD=6 CALENDAR months [launch-6, launch-1],
#     which is NA unless ALL SIX survive. This single rule, not coverage, is
#     what disqualifies TN/VA/AZ/CT/NY/LA: their baselines sit in the COVID gap.
#   * covid: drop, window ["2020-03-01","2021-07-31"] (R/power/config.R:103),
#     applied as `< start | > end`, so 2020-03 .. 2021-07 inclusive are removed.
#   * exclude_states: [NV, ID, HI, MS].
#   * a switcher contributes at horizon h only where that outcome month is
#     observed => "partial" = 1..12 of the 13 outcome months survive.
#
# NECESSARY, NOT SUFFICIENT: a cell is also dropped unless some not-yet-launched
# control survives in it (`ctl <- is.na(lm) | lm > far`). That is a cross-state
# condition and is not drawn here.
#
# No estimation, no outcome values touched: blindness-safe.
#
# Output: figures/clean_anchor_windows.{png,pdf}
#         output/spillover_cluster_feasibility/clean_anchor_window_status.csv
# =============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(glue)
})

theme_set(theme_minimal(base_size = 11))

SCHED   <- "data/raw/sports_gambling_legalization_dates.csv"
PANEL   <- "data/raw/state_month_panel_with_treatment.csv"
FIG_DIR <- "figures"
OUT_CSV <- "output/spillover_cluster_feasibility/clean_anchor_window_status.csv"
dir.create(FIG_DIR, recursive = TRUE, showWarnings = FALSE)

PRE_MONTHS  <- 6
POST_LO     <- 12
POST_HI     <- 24
COVID_START <- as.Date("2020-03-01")
COVID_END   <- as.Date("2021-07-31")   # R/power/config.R:103
EXCL_STATES <- c("ID", "HI", "MS", "NV")   # documented exclusions

state_abb <- c(
  Alabama="AL", Alaska="AK", Arizona="AZ", Arkansas="AR", California="CA",
  Colorado="CO", Connecticut="CT", Delaware="DE", `District of Columbia`="DC",
  Florida="FL", Georgia="GA", Hawaii="HI", Idaho="ID", Illinois="IL",
  Indiana="IN", Iowa="IA", Kansas="KS", Kentucky="KY", Louisiana="LA",
  Maine="ME", Maryland="MD", Massachusetts="MA", Michigan="MI", Minnesota="MN",
  Mississippi="MS", Missouri="MO", Montana="MT", Nebraska="NE", Nevada="NV",
  `New Hampshire`="NH", `New Jersey`="NJ", `New Mexico`="NM", `New York`="NY",
  `North Carolina`="NC", `North Dakota`="ND", Ohio="OH", Oklahoma="OK",
  Oregon="OR", Pennsylvania="PA", `Rhode Island`="RI", `South Carolina`="SC",
  `South Dakota`="SD", Tennessee="TN", Texas="TX", Utah="UT", Vermont="VT",
  Virginia="VA", Washington="WA", `West Virginia`="WV", Wisconsin="WI",
  Wyoming="WY")

# ---- Schedule ---------------------------------------------------------------
sched <- read_csv(SCHED, show_col_types = FALSE) %>%
  mutate(st = state_abb[state],
         online = as.Date(online_start_date))

retail_only <- sched %>% filter(is.na(online)) %>% pull(st)
message("Retail-only (no online date, not switchers under this spec): ",
        paste(sort(retail_only), collapse = ", "))

# ---- Panel coverage ---------------------------------------------------------
cover <- read_csv(PANEL, show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date)) %>%
  group_by(st = state_abb) %>%
  summarise(obs_min = min(month_date), obs_max = max(month_date),
            .groups = "drop")

# ---- Window construction + status ------------------------------------------
# Months surviving the COVID drop, per state, exactly as the loader leaves them.
obs_months <- read_csv(PANEL, show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date)) %>%
  filter(month_date < COVID_START | month_date > COVID_END) %>%
  distinct(st = state_abb, month_date)

obs_set <- split(obs_months$month_date, obs_months$st)

win <- sched %>%
  filter(!is.na(online)) %>%
  transmute(st, online,
            pre_lo  = online %m-% months(PRE_MONTHS),
            post_lo = online %m+% months(POST_LO),
            post_hi = online %m+% months(POST_HI)) %>%
  left_join(cover, by = "st") %>%
  rowwise() %>%
  mutate(
    in_panel = !is.na(obs_min),
    excluded = st %in% EXCL_STATES,
    # STRICT baseline: all PMD calendar months [launch-6, launch-1] must survive
    n_base = sum(seq(online %m-% months(PRE_MONTHS), by = "month",
                     length.out = PRE_MONTHS) %in% (obs_set[[st]] %||% as.Date(NA))),
    # Outcome months launch+12 .. launch+24 that survive
    n_out  = sum(seq(online %m+% months(POST_LO), online %m+% months(POST_HI),
                     by = "month") %in% (obs_set[[st]] %||% as.Date(NA)))
  ) %>%
  ungroup() %>%
  mutate(
    base_ok = n_base == PRE_MONTHS,
    n_out_max = POST_HI - POST_LO + 1L,
    status = case_when(
      !in_panel               ~ "Not in panel",
      excluded                ~ "Excluded (NV/ID/HI/MS)",
      !base_ok                ~ "No baseline (6-mo pre-launch incomplete)",
      n_out == 0              ~ "No outcome months",
      n_out == n_out_max      ~ "Switcher - full outcome window",
      TRUE                    ~ "Switcher - partial outcome window"
    )
  ) %>%
  arrange(online) %>%
  mutate(st = factor(st, levels = rev(unique(st))))

write_csv(win %>% mutate(st = as.character(st)), OUT_CSV)

print(win %>% count(status, sort = TRUE) %>% as.data.frame(), row.names = FALSE)
sw <- win %>% filter(grepl("^Switcher", status))
cat("\nSWITCHERS (", nrow(sw), "):\n", sep = "")
print(as.data.frame(sw %>% transmute(st = as.character(st), online,
                                     n_base, n_out, status)), row.names = FALSE)
cat("\nFINDINGS.md \u00a72 lists 12 switchers: KS MD OH KY ME NC (full);",
    "NH IN DE VT WV AR (partial)\n")

# ---- Long form for the three window segments --------------------------------
segs <- bind_rows(
  win %>% transmute(st, status, seg = "Baseline (-6 to 0)",  x = pre_lo,  xend = online),
  win %>% transmute(st, status, seg = "Buildup (0 to 12)",   x = online,  xend = post_lo),
  win %>% transmute(st, status, seg = "Outcome (12 to 24)",  x = post_lo, xend = post_hi)
) %>%
  mutate(seg = factor(seg, levels = c("Baseline (-6 to 0)",
                                      "Buildup (0 to 12)",
                                      "Outcome (12 to 24)")))

pal <- c("Baseline (-6 to 0)" = "#2C7FB8",
         "Buildup (0 to 12)"  = "#C6DBEF",
         "Outcome (12 to 24)" = "#D94801")

status_pal <- c("Switcher - full outcome window"          = "#1A9850",
                "Switcher - partial outcome window"       = "#7FBC70",
                "No baseline (6-mo pre-launch incomplete)" = "#B2182B",
                "No outcome months"                        = "#E08214",
                "Excluded (NV/ID/HI/MS)"                   = "#777777",
                "Not in panel"                             = "#BBBBBB")

xlim_lo <- as.Date("2017-06-01"); xlim_hi <- as.Date("2028-06-01")

# Clamp the coverage underlay to the axis so long series (MD/MO start 2012)
# are drawn truncated rather than dropped by the scale limits.
cover_draw <- win %>% filter(in_panel) %>%
  mutate(obs_min = pmax(obs_min, xlim_lo), obs_max = pmin(obs_max, xlim_hi)) %>%
  filter(obs_max > obs_min)

p <- ggplot() +
  # COVID splice
  annotate("rect", xmin = COVID_START, xmax = COVID_END,
           ymin = -Inf, ymax = Inf, fill = "grey40", alpha = 0.16) +
  annotate("text", x = COVID_START + (COVID_END - COVID_START)/2,
           y = Inf, vjust = -0.6, label = "COVID window dropped",
           size = 2.9, colour = "grey25") +
  # panel coverage underlay
  geom_segment(data = cover_draw,
               aes(x = obs_min, xend = obs_max, y = st, yend = st),
               colour = "grey88", linewidth = 4.2, lineend = "butt") +
  # design windows
  geom_segment(data = segs,
               aes(x = x, xend = xend, y = st, yend = st, colour = seg),
               linewidth = 3.1, lineend = "butt") +
  # launch date
  geom_point(data = win, aes(x = online, y = st), shape = 18, size = 1.9,
             colour = "grey15") +
  # status flag in the right margin
  geom_point(data = win, aes(x = xlim_hi - 75, y = st, fill = status),
             shape = 22, size = 2.6, colour = "white", stroke = 0.3) +
  scale_colour_manual(values = pal, name = "Design window") +
  scale_fill_manual(values = status_pal, name = "Status") +
  scale_x_date(limits = c(xlim_lo, xlim_hi), date_breaks = "1 year",
               date_labels = "%Y", expand = expansion(mult = c(0.01, 0.01))) +
  labs(x = NULL, y = NULL) +
  guides(colour = guide_legend(order = 1, nrow = 1,
                               override.aes = list(linewidth = 3)),
         fill   = guide_legend(order = 2, nrow = 3, byrow = TRUE,
                               override.aes = list(size = 3))) +
  coord_cartesian(clip = "off") +
  theme(plot.margin = margin(t = 16, r = 6, b = 4, l = 4),
        panel.grid.major.y = element_blank(),
        panel.grid.minor.x = element_blank(),
        legend.position = "bottom",
        legend.box = "vertical",
        legend.margin = margin(t = -4),
        axis.text.y = element_text(size = 8))

ggsave(file.path(FIG_DIR, "clean_anchor_windows.png"), p,
       width = 10.5, height = 8.8, dpi = 220, bg = "white")
ggsave(file.path(FIG_DIR, "clean_anchor_windows.pdf"), p,
       width = 10.5, height = 8.8, bg = "white")

message("Wrote figures/clean_anchor_windows.{png,pdf}")
