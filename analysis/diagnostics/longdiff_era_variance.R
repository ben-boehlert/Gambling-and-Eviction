#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# Long-difference NOISE by era — does the pre-2018 (pseudo-treatment) era
# understate the post-COVID variance environment?
#
# WHY THIS EXISTS. The 2x2 long-difference power simulation is staged as a
# PSEUDO-TREATMENT in the pre-treatment era (Black, Hollingsworth, Nunes &
# Simon 2022, who move the ACA experiment from 2014-16 back to 2011). That
# buys an honestly untreated panel at real state counts, but it buys it in a
# calmer calendar. If the residual dispersion of state-level long differences
# is larger in the post-COVID era where the REAL endpoint sits, then a
# pre-era MDE is optimistic and must be inflated.
#
# WHAT IS MEASURED. For a window geometry (baseline B months, gap G months,
# endpoint E months) and a placement s, each state's long difference is
#
#     dY_s = mean(y | endpoint window) - mean(y | baseline window),   y = log1p(filings)
#
# and the object of interest is sigma = SD of dY_s ACROSS states. That is
# exactly the residual the state-clustered 2x2 standard error is built from:
#     SE(tau) ~= sigma * sqrt(1/N_T + 1/N_C),   MDE-80 ~= 2.80 * SE.
# Windows are slid over every feasible placement inside each era, so sigma is
# reported as a distribution over placements rather than one fragile number.
#
# THE APPLES-TO-APPLES COMPARISON is never-online states only, held fixed
# across eras: in the post-COVID era the eventually-treated states are
# genuinely treated, so the blindness protocol forbids them. The pre era is
# additionally reported on ALL states as a composition check (does restricting
# to never-online states by itself change sigma?).
#
# Endpoint widths 1/3/12 and baseline widths 6/12 are crossed so the same run
# answers the Burlig-Preonas-Woerman question — with serial correlation,
# averaging more months does not buy variance reduction proportional to T —
# separately WITHIN each era.
#
# Usage:  Rscript analysis/diagnostics/longdiff_era_variance.R
# Output: output/longdiff_era_variance/{placements.csv, summary.csv,
#         era_ratio.csv, sigma_by_endpoint_width.png}
# ─────────────────────────────────────────────────────────────────────────────

suppressMessages({
  library(tidyverse); library(glue)
})
theme_set(theme_minimal())

source("utils/eviction_treatment_schedule.R")

OUT_DIR <- "output/longdiff_era_variance"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# Real design counts (panel states): 24 ever-online, 15 never-online. The 2x2
# splits on "online by 2022", but for an SE scaling factor only the counts
# matter, and 22/15 is what the annual-court substrate supports.
N_TREATED_REAL <- 22L
N_CONTROL_REAL <- 15L
Z80 <- qnorm(0.975) + qnorm(0.80)          # 2.802 — 80% power, 5% two-sided

# Era boundaries. `pre` ends the month before the first-ever legalization
# (2018-06, DE/NJ): every state is untreated throughout. `post` starts at the
# framework's covid:post boundary (2021-08) and ends at the last month with
# broad coverage (2025-09; coverage collapses to <10 states after).
ERAS <- tribble(
  ~era,   ~start,                 ~end,
  "pre",  as.Date("2016-01-01"),  as.Date("2018-05-01"),
  "post", as.Date("2021-08-01"),  as.Date("2025-09-01")
)

# Geometry grid. The gap is swept as well as the window widths: with gap = 5
# the widest cell (B = 12, E = 12) exactly fills the 29-month pre era and
# admits a SINGLE placement, which is far too thin to carry an era ratio.
# gap = 0 and 3 buy additional pre-era placements at the same widths, and the
# gap is always MATCHED across eras so the baseline-to-endpoint distance is
# identical on both sides of every comparison.
GEOMETRY <- expand_grid(B = c(6L, 12L), E = c(1L, 3L, 12L),
                        gap = c(0L, 3L, 5L))

ym <- function(d) (as.integer(format(d, "%Y")) - 2000L) * 12L +
                   as.integer(format(d, "%m"))

# ── Data ─────────────────────────────────────────────────────────────────────
sched_first  <- load_eviction_treatment_schedule(
  "data/raw/sports_gambling_legalization_dates.csv", "first_start_date")
sched_online <- load_eviction_treatment_schedule(
  "data/raw/sports_gambling_legalization_dates.csv", "online_start_date")

panel <- read_csv("data/raw/state_month_panel_with_treatment.csv",
                  show_col_types = FALSE) %>%
  transmute(state_abb  = as.character(state_abb),
            month_date = as.Date(month_date),
            filings_count = as.numeric(filings_count)) %>%
  filter(!is.na(filings_count), month_date >= as.Date("2016-01-01")) %>%
  # NEVADA: legal sports betting since 1949, so it is absent from the schedule
  # because there was no post-PASPA legalization event -- NOT because it never
  # adopted. Leaving it in makes an ALWAYS-TREATED state a never-treated
  # control. Dropped here rather than filtered downstream so that every state
  # set built below (treated, never, and all-states) is consistently free of it.
  # See docs/methodology/ADOPTION_UNIVERSE_AUDIT.md.
  filter(!state_abb %in% PRE_PASPA_SPORTS_BETTING) %>%
  mutate(t = ym(month_date), y = log1p(filings_count))

# Blind-legal state sets. The protocol cuts on first_start_date (§4), so
# `never_any` — panel states with no legalization of ANY kind, including
# states simply absent from the schedule file — is the set that stays honestly
# untreated through the post-COVID era. `never_online` is wider (15 states)
# but 5 of its members legalized RETAIL betting, which is itself a plausible
# treatment; it is reported as a secondary, larger-n check only.
panel_states <- sort(unique(panel$state_abb))
ever_any     <- sched_first  %>% filter(!is.na(treat_start)) %>% pull(state_abb)
ever_online  <- sched_online %>% filter(!is.na(treat_start)) %>% pull(state_abb)
never_any    <- setdiff(panel_states, ever_any)
never_online <- setdiff(panel_states, ever_online)
# Idaho is excluded from annual analyses elsewhere in this project for data
# quality (CLAUDE.md). It turns out to be the single most extreme state in
# 100% of pre-era placements, so a raw SD comparison across eras is really an
# Idaho comparison. The `_exid` sets pre-specify its removal instead of
# relying on the data-dependent trim.
EXCLUDE_ID    <- "ID"
never_any_exid    <- setdiff(never_any, EXCLUDE_ID)
never_online_exid <- setdiff(never_online, EXCLUDE_ID)
cat(glue("panel states: {length(panel_states)} | never-any-legalization: ",
         "{length(never_any)} ({paste(never_any, collapse=' ')}) | ",
         "never-online: {length(never_online)}\n"))

# ── Core: sigma for one era x geometry x placement x state set ───────────────
sigma_one <- function(dat, t_base_start, B, G, E) {
  t_base_end  <- t_base_start + B - 1L
  t_end_start <- t_base_end + G + 1L
  t_end_end   <- t_end_start + E - 1L

  base <- dat %>% filter(t >= t_base_start, t <= t_base_end) %>%
    count(state_abb, wt = NULL, name = "n_b") %>% filter(n_b == B)
  endp <- dat %>% filter(t >= t_end_start, t <= t_end_end) %>%
    count(state_abb, name = "n_e") %>% filter(n_e == E)
  keep <- intersect(base$state_abb, endp$state_abb)
  # 6 is the floor: the strict never-any set has only 10 members, 7 of which
  # clear full pre-era coverage, 6 once Idaho is pre-excluded. An SD on 6
  # states is thin and is reported as such, never as the headline.
  if (length(keep) < 6L) return(NULL)

  dY <- dat %>%
    filter(state_abb %in% keep) %>%
    mutate(win = case_when(t >= t_base_start & t <= t_base_end  ~ "base",
                           t >= t_end_start  & t <= t_end_end   ~ "endp",
                           TRUE ~ NA_character_)) %>%
    filter(!is.na(win)) %>%
    group_by(state_abb, win) %>% summarise(m = mean(y), .groups = "drop") %>%
    pivot_wider(names_from = win, values_from = m) %>%
    mutate(dY = endp - base)

  # The raw SD across 7-12 states is hostage to a single extreme state, and
  # the SD/MAD gap below shows that is not hypothetical. `sigma_trim` drops
  # the one state furthest from the median and `outlier_state` names it, so a
  # ratio driven by one small state can never masquerade as an era effect.
  d   <- dY$dY
  far <- which.max(abs(d - median(d)))

  tibble(n_states      = nrow(dY),
         sigma         = sd(d),
         sigma_trim    = sd(d[-far]),
         sigma_from_mad = mad(d),          # already scaled by 1.4826
         iqr           = IQR(d),
         outlier_state = dY$state_abb[far])
}

# ── Sweep every era x geometry x placement x state set ───────────────────────
rows <- list()
for (i in seq_len(nrow(ERAS))) {
  era_name <- ERAS$era[i]
  t_lo <- ym(ERAS$start[i]); t_hi <- ym(ERAS$end[i])

  for (j in seq_len(nrow(GEOMETRY))) {
    B <- GEOMETRY$B[j]; E <- GEOMETRY$E[j]; G <- GEOMETRY$gap[j]
    span <- B + G + E
    if (t_lo + span - 1L > t_hi) next
    starts <- t_lo:(t_hi - span + 1L)

    # In the post era only never-treated states are blind-legal; in the pre era
    # every state is untreated, so all three sets are legitimate there.
    sets <- if (era_name == "pre")
              c("never_any", "never_any_exid", "never_online",
                "never_online_exid", "all_states")
            else
              c("never_any", "never_any_exid", "never_online",
                "never_online_exid")

    for (set_name in sets) {
      dat <- switch(set_name,
        never_any         = panel %>% filter(state_abb %in% never_any),
        never_any_exid    = panel %>% filter(state_abb %in% never_any_exid),
        never_online      = panel %>% filter(state_abb %in% never_online),
        never_online_exid = panel %>% filter(state_abb %in% never_online_exid),
        all_states        = panel)

      for (s in starts) {
        r <- sigma_one(dat, s, B, G, E)
        if (is.null(r)) next
        rows[[length(rows) + 1L]] <- r %>%
          mutate(era = era_name, state_set = set_name, B = B, E = E,
                 gap = G, placement_t = s, .before = 1)
      }
    }
  }
}
placements <- bind_rows(rows)
stopifnot(nrow(placements) > 0)

# ── Summaries ────────────────────────────────────────────────────────────────
se_scale <- sqrt(1 / N_TREATED_REAL + 1 / N_CONTROL_REAL)

summary_tbl <- placements %>%
  group_by(era, state_set, B, E, gap) %>%
  summarise(n_placements = n(),
            n_states_med = median(n_states),
            sigma_med    = median(sigma),
            sigma_mean   = mean(sigma),
            sigma_p10    = quantile(sigma, 0.10),
            sigma_p90    = quantile(sigma, 0.90),
            sigma_trim_med = median(sigma_trim),
            mad_med      = median(sigma_from_mad),
            top_outlier  = names(sort(table(outlier_state), decreasing = TRUE))[1],
            top_outlier_share = max(table(outlier_state)) / n(),
            .groups = "drop") %>%
  # Sampling SE of a single placement's SD estimate, sigma / sqrt(2(n-1)).
  # Placements OVERLAP heavily, so n_placements is not an independent-sample
  # count and this is the honest per-placement precision, not a precision for
  # the median across placements.
  mutate(sigma_se_1placement = sigma_med / sqrt(2 * (n_states_med - 1)),
         se_implied          = sigma_med * se_scale,
         mde80_implied       = Z80 * se_implied)

era_ratio <- summary_tbl %>%
  filter(state_set != "all_states") %>%
  select(era, state_set, B, E, gap, n_placements, sigma_med, sigma_trim_med,
         mad_med, mde80_implied) %>%
  pivot_wider(names_from = era,
              values_from = c(n_placements, sigma_med, sigma_trim_med,
                              mad_med, mde80_implied)) %>%
  mutate(sigma_ratio_post_over_pre = sigma_med_post / sigma_med_pre,
         trim_ratio_post_over_pre  = sigma_trim_med_post / sigma_trim_med_pre,
         mad_ratio_post_over_pre   = mad_med_post / mad_med_pre,
         mde_ratio_post_over_pre   = mde80_implied_post / mde80_implied_pre)

composition <- summary_tbl %>%
  filter(era == "pre") %>%
  filter(gap == 5L) %>%
  select(B, E, state_set, sigma_med) %>%
  pivot_wider(names_from = state_set, values_from = sigma_med) %>%
  mutate(ratio_neverany_over_all    = never_any / all_states,
         ratio_neveronline_over_all = never_online / all_states)

write_csv(placements,  file.path(OUT_DIR, "placements.csv"))
write_csv(summary_tbl, file.path(OUT_DIR, "summary.csv"))
write_csv(era_ratio,   file.path(OUT_DIR, "era_ratio.csv"))
write_csv(composition, file.path(OUT_DIR, "composition_check.csv"))

p <- placements %>%
  filter(state_set == "never_online_exid") %>%
  filter(gap == 5L) %>%
  mutate(baseline = glue("baseline {B} mo")) %>%
  ggplot(aes(factor(E), sigma, colour = era)) +
  geom_boxplot(outlier.size = 0.6) +
  facet_wrap(~baseline) +
  labs(x = "endpoint window width (months)",
       y = expression(sigma == "SD across states of the long difference"),
       colour = "era",
       subtitle = glue("Never-online states only; window slid over every ",
                       "feasible placement (gap fixed at 5 months)"))
ggsave(file.path(OUT_DIR, "sigma_by_endpoint_width.png"), p,
       width = 9, height = 4.5, dpi = 200)

cat("\n===== sigma by era x geometry (never-treated states) =====\n")
print(as.data.frame(summary_tbl %>% filter(state_set != "all_states") %>%
                      arrange(state_set, B, E) %>%
                      filter(state_set %in% c("never_online_exid",
                                              "never_any_exid")) %>%
                      select(state_set, era, B, E, gap, n_placements, n_states_med,
                             sigma_med, mad_med, mde80_implied)), digits = 3)
cat("\n===== POST / PRE ratio (the stress test) =====\n")
cat("(primary: never-ONLINE states, Idaho pre-excluded -- 14 members, the\n",
    " largest set that is untreated in BOTH eras under the online definition)\n")
print(as.data.frame(era_ratio %>% filter(state_set == "never_online_exid") %>%
                      select(B, E, gap, n_placements_pre, n_placements_post,
                             sigma_med_pre, sigma_med_post,
                             sigma_ratio_post_over_pre,
                             trim_ratio_post_over_pre,
                             mad_ratio_post_over_pre)), digits = 3)
cat("\n(strict blindness check: never-ANY-legalization states, Idaho excluded;\n",
    " only ~6 states clear pre-era coverage, so treat as directional)\n")
print(as.data.frame(era_ratio %>% filter(state_set == "never_any_exid") %>%
                      select(B, E, gap, sigma_med_pre, sigma_med_post,
                             sigma_ratio_post_over_pre)), digits = 3)
cat("\n===== composition check, pre era: never-online vs all states =====\n")
print(as.data.frame(composition), digits = 3)
# ── Center-anchored averaging test (the Burlig-Preonas-Woerman question) ─────
# The sweep above widens the endpoint window FORWARD from a fixed baseline, so
# a wider window also sits further from the baseline: "more averaging" and
# "more distance" move together and the two effects cannot be separated. Here
# the endpoint window's CENTRE is held fixed and only its WIDTH varies, so
# sigma(E) isolates averaging. The benchmark is the iid rate 1/sqrt(E): if
# months were independent, going from a 1-month to a 12-month endpoint would
# cut sigma to 0.289 of its value. Serial correlation means it will not.
WIDTHS <- c(1L, 3L, 6L, 12L)

sigma_centered <- function(dat, c_base, c_end, B, E) {
  # Windows of width w centred on c: [c - floor((w-1)/2), c + ceiling((w-1)/2)]
  lo <- function(c, w) c - (w - 1L) %/% 2L
  hi <- function(c, w) c + (w - 1L) - (w - 1L) %/% 2L
  tb <- c(lo(c_base, B), hi(c_base, B))
  te <- c(lo(c_end,  E), hi(c_end,  E))
  if (tb[2] >= te[1]) return(NULL)                    # windows must not overlap

  # NB: the count column is itself called `n`, so the argument must NOT be
  # named `n` -- `filter(n == n)` is vacuously TRUE and would silently admit
  # states with partial window coverage.
  ok <- function(rng, need) dat %>% filter(t >= rng[1], t <= rng[2]) %>%
    count(state_abb) %>% filter(n == need) %>% pull(state_abb)
  keep <- intersect(ok(tb, B), ok(te, E))
  if (length(keep) < 6L) return(NULL)

  d <- dat %>% filter(state_abb %in% keep) %>%
    mutate(win = case_when(t >= tb[1] & t <= tb[2] ~ "base",
                           t >= te[1] & t <= te[2] ~ "endp",
                           TRUE ~ NA_character_)) %>%
    filter(!is.na(win)) %>%
    group_by(state_abb, win) %>% summarise(m = mean(y), .groups = "drop") %>%
    pivot_wider(names_from = win, values_from = m) %>%
    mutate(dY = endp - base)
  far <- which.max(abs(d$dY - median(d$dY)))
  tibble(n_states = nrow(d), sigma = sd(d$dY),
         sigma_trim = sd(d$dY[-far]), sigma_from_mad = mad(d$dY))
}

bpw_rows <- list()
for (i in seq_len(nrow(ERAS))) {
  era_name <- ERAS$era[i]
  t_lo <- ym(ERAS$start[i]); t_hi <- ym(ERAS$end[i])
  dat  <- panel %>% filter(state_abb %in% never_online_exid)
  # Centres are placed so the widest window (12) fits inside the era, and the
  # baseline centre sits a fixed 18 months before the endpoint centre in BOTH
  # eras, so distance is matched across eras and constant across widths.
  for (c_end in (t_lo + 6L + 18L):(t_hi - 6L)) {
    c_base <- c_end - 18L
    if (c_base - 6L < t_lo) next
    for (B in c(6L, 12L)) for (E in WIDTHS) {
      r <- sigma_centered(dat, c_base, c_end, B, E)
      if (is.null(r)) next
      bpw_rows[[length(bpw_rows) + 1L]] <- r %>%
        mutate(era = era_name, B = B, E = E, c_end = c_end, .before = 1)
    }
  }
}
bpw <- bind_rows(bpw_rows)
if (nrow(bpw) > 0) {
  bpw_sum <- bpw %>% group_by(era, B, E) %>%
    summarise(n_placements = n(), sigma_med = median(sigma),
              sigma_trim_med = median(sigma_trim), .groups = "drop") %>%
    group_by(era, B) %>%
    mutate(sigma_rel_to_E1  = sigma_med / sigma_med[E == 1L],
           iid_benchmark    = 1 / sqrt(E),
           averaging_efficiency = (1 - sigma_rel_to_E1) /
                                  (1 - iid_benchmark)) %>%
    ungroup()
  write_csv(bpw,     file.path(OUT_DIR, "bpw_placements.csv"))
  write_csv(bpw_sum, file.path(OUT_DIR, "bpw_averaging.csv"))
  cat("\n===== AVERAGING vs SERIAL CORRELATION (centre-anchored) =====\n")
  cat("sigma_rel_to_E1 vs iid_benchmark 1/sqrt(E); efficiency 1 = iid, 0 = no gain\n")
  print(as.data.frame(bpw_sum), digits = 3)
}

# ── The real-calendar anchor (Fable D4 bridge) ───────────────────────────────
# sigma at the LITERAL design Ben wants — baseline 2017-01..2018-12, endpoint
# 2024-10..2025-09 (70-month distance) — measured on states that are never
# treated, so it needs no blinding cutoff and is legal to look at. This is the
# number the pseudo-era MDE must ultimately be reconciled against.
real_geom <- list(base = c(as.Date("2017-01-01"), as.Date("2018-12-01")),
                  endp = c(as.Date("2024-10-01"), as.Date("2025-09-01")))
real_rows <- map_dfr(c("never_any", "never_any_exid", "never_online",
                       "never_online_exid"), function(set_name) {
  keep_states <- switch(set_name,
                        never_any         = never_any,
                        never_any_exid    = never_any_exid,
                        never_online      = never_online,
                        never_online_exid = never_online_exid)
  dat <- panel %>% filter(state_abb %in% keep_states)
  r <- sigma_one(dat, ym(real_geom$base[1]), 24L,
                 ym(real_geom$endp[1]) - ym(real_geom$base[2]) - 1L, 12L)
  if (is.null(r)) return(tibble())
  r %>% mutate(state_set = set_name, .before = 1)
})
if (nrow(real_rows) > 0) {
  real_rows <- real_rows %>%
    mutate(se_implied   = sigma * se_scale,
           mde80_implied = Z80 * se_implied,
           mde80_pct     = 100 * (exp(mde80_implied) - 1))
  write_csv(real_rows, file.path(OUT_DIR, "real_calendar_sigma.csv"))
  cat("\n===== REAL-CALENDAR sigma (2017-01..2018-12 -> 2024-10..2025-09) =====\n")
  print(as.data.frame(real_rows), digits = 3)
} else {
  cat("\n[real-calendar anchor] too few states with BOTH windows complete.\n")
}

cat(glue("\nSE scaling used: sqrt(1/{N_TREATED_REAL} + 1/{N_CONTROL_REAL}) = ",
         "{round(se_scale, 4)}; MDE-80 = {round(Z80, 3)} x SE\n\n"))
