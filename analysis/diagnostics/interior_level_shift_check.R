# =============================================================================
# interior_level_shift_check.R  (2026-09-17)
#
# The mid-panel analogue of series_start_ramp_check.R. That script only looks
# at LEADING months (the CT/NH case). This one looks for discontinuities
# ANYWHERE in a state's series -- start, middle, or end -- that are shaped like
# a coverage/source artifact rather than like evictions moving.
#
# THREE SHAPES, detected separately:
#   (A) STEP   -- a sustained level shift: the 6 months after a boundary sit at
#                 a different level than the 6 before, and stay there.
#   (B) SPIKE  -- a single month far off its own local neighbourhood that
#                 reverts immediately (one bad reporting month).
#   (C) GAP    -- interior missing months. Not an artifact by itself, but the
#                 seam where a source change or backfill can hide, so every gap
#                 is reported with the level on each side of it.
#
# METHOD. Work in logs, deseasonalized by the state's OWN month-of-year
# pattern (classic centered-13-MA decomposition), so seasonality cannot
# masquerade as a step. COVID months (2020-03..2021-07) are excluded from
# estimation AND from being flagged, and every comparison window must be
# CALENDAR-CONTIGUOUS -- so no window straddles the COVID hole or a data gap,
# and the COVID entry/exit cliffs are never flagged.
#
# A step must be BOTH absolutely large (>= MIN_STEP log points) AND an outlier
# in that state's own distribution of 6-vs-6 changes (|z| >= MIN_Z). The second
# condition is what separates an artifact from the genuine post-COVID climb:
# a state trending steadily upward has a large delta at EVERY cut point, so no
# single one stands out.
#
# Descriptive, uses no treatment timing: blindness-safe.
# Output: output/interior_level_shift/{steps,spikes,gaps}.csv
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(lubridate); library(glue)})

CS <- as.Date("2020-03-01"); CE <- as.Date("2021-07-31")   # COVID drop window
W        <- 6      # months each side of a candidate boundary
MIN_STEP <- 0.25   # log points (~28%) -- absolute size floor for a step
MIN_Z    <- 2.5    # ... and it must be this many MADs out in the state's own delta distribution
MIN_SPIKE<- 0.40   # log points for a single-month, self-reverting outlier
MIN_MONTHS <- 30   # states shorter than this are reported but not step-tested

OUT <- "output/interior_level_shift"; dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

pan <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date))

mad0 <- function(x) { m <- mad(x, na.rm = TRUE); if (!is.finite(m) || m < 1e-8) sd(x, na.rm = TRUE) else m }

# ---- per-state: put the series on a complete calendar grid, deseasonalize ----
prep <- function(s) {
  d <- pan %>% filter(state_abb == s) %>% arrange(month_date)
  grid <- tibble(month_date = seq(min(d$month_date), max(d$month_date), by = "month")) %>%
    left_join(d %>% select(month_date, filings_count, panel_source), by = "month_date") %>%
    mutate(state_abb = s,
           is_covid  = month_date >= CS & month_date <= CE,
           ly        = ifelse(is.na(filings_count), NA_real_, log(pmax(filings_count, 1))),
           use       = !is.na(ly) & !is_covid)
  # centered 13-term moving average -> trend; seasonal = mean(ly - trend) by calendar month
  n <- nrow(grid); tr <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    lo <- i - 6; hi <- i + 6
    if (lo >= 1 && hi <= n) { w <- grid$ly[lo:hi]; if (sum(!is.na(w)) >= 9) tr[i] <- mean(w, na.rm = TRUE) }
  }
  grid$trend <- tr
  seas <- grid %>% filter(use, !is.na(trend)) %>% mutate(m = month(month_date)) %>%
    group_by(m) %>% summarise(s_eff = mean(ly - trend), n_s = n(), .groups = "drop") %>%
    mutate(s_eff = ifelse(n_s >= 2, s_eff, 0))
  seas$s_eff <- seas$s_eff - mean(seas$s_eff)          # center so adj stays on the log-level scale
  grid %>% mutate(m = month(month_date)) %>%
    left_join(seas %>% select(m, s_eff), by = "m") %>%
    mutate(s_eff = coalesce(s_eff, 0), adj = ly - s_eff)
}

# ---- (A) steps: 6-vs-6 on calendar-contiguous, non-COVID, fully-present windows ----
steps_for <- function(g) {
  n <- nrow(g); ok <- g$use
  cand <- tibble()
  for (c in seq_len(n)) {
    pre <- (c - W):(c - 1); post <- c:(c + W - 1)
    if (min(pre) < 1 || max(post) > n) next
    if (!all(ok[pre]) || !all(ok[post])) next          # contiguity: no gap, no COVID inside a window
    cand <- bind_rows(cand, tibble(
      idx = c, boundary = g$month_date[c],
      pre_med = median(g$adj[pre]), post_med = median(g$adj[post])))
  }
  if (!nrow(cand)) return(tibble())
  cand <- cand %>% mutate(delta = post_med - pre_med)
  z_scale <- mad0(cand$delta)
  cand %>% mutate(z = (delta - median(delta)) / z_scale,
                  pct = exp(delta) - 1,
                  state_abb = g$state_abb[1])
}

# does the shift persist? level 7..18 months after vs the 6 before
persist_for <- function(g, idx) {
  n <- nrow(g); far <- (idx + W):(idx + W + 11); far <- far[far <= n]
  far <- far[g$use[far]]
  if (length(far) < 6) return(NA_real_)
  pre <- (idx - W):(idx - 1)
  median(g$adj[far]) - median(g$adj[pre])
}

# ---- (B) single-month self-reverting outliers ----
spikes_for <- function(g) {
  n <- nrow(g); out <- tibble()
  for (i in seq_len(n)) {
    if (!g$use[i]) next
    nb <- c((i - 3):(i - 1), (i + 1):(i + 3)); nb <- nb[nb >= 1 & nb <= n]; nb <- nb[g$use[nb]]
    if (length(nb) < 4) next
    dev <- g$adj[i] - median(g$adj[nb])
    if (abs(dev) >= MIN_SPIKE)
      out <- bind_rows(out, tibble(state_abb = g$state_abb[1], month_date = g$month_date[i],
                                   filings_count = g$filings_count[i], dev = dev,
                                   pct = exp(dev) - 1, nbr_median_filings = round(exp(median(g$adj[nb])))))
  }
  out
}

# ---- (C) interior gaps ----
gaps_for <- function(g) {
  miss <- g %>% filter(is.na(filings_count))
  if (!nrow(miss)) return(tibble())
  miss %>% mutate(run = cumsum(c(1, diff(as.integer(month_date)) > 32))) %>%
    group_by(run) %>%
    summarise(state_abb = g$state_abb[1], gap_start = min(month_date), gap_end = max(month_date),
              n_months = n(), .groups = "drop") %>% select(-run)
}

# ---- (D) SERIES-END step, TWO-SIDED -------------------------------------
# series_start_ramp_check.R does this at the START of a series, and
# censor_trailing_partial_months.R catches a trailing month that is too LOW.
# NOTHING checks a trailing run that is too HIGH -- the shape a backfill or a
# late basket change leaves at the ingest cutoff. This closes that gap, and
# unlike the step test it runs on SHORT series too (HI has only 16 usable
# non-COVID months, so it is never step-tested).
# Each of the last <=12 months is compared to the same calendar month in the
# PRECEDING 3 years, COVID excluded, so seasonality cannot false-positive.
END_LO <- 0.60; END_HI <- 1.60
end_for <- function(s) {
  d <- pan %>% filter(state_abb == s) %>% arrange(month_date)
  if (nrow(d) < 24) return(tibble())
  d <- d %>% mutate(is_covid = month_date >= CS & month_date <= CE)
  last12 <- tail(d$month_date, 12); cut <- min(last12)
  ref <- d %>% filter(month_date < cut, month_date >= cut %m-% months(36), !is_covid) %>%
    group_by(m = month(month_date)) %>%
    summarise(norm = mean(filings_count), n_ref = n(), .groups = "drop") %>% filter(n_ref >= 2)
  tl <- d %>% filter(month_date %in% last12, !is_covid) %>% mutate(m = month(month_date)) %>%
    inner_join(ref, by = "m") %>% mutate(ratio = filings_count / norm) %>% arrange(desc(month_date))
  if (!nrow(tl)) return(tibble())
  out <- tl$ratio < END_LO | tl$ratio > END_HI          # counted from the END backwards
  runlen <- if (!out[1]) 0L else which(c(!out, TRUE))[1] - 1L
  tibble(state_abb = s, series_end = max(d$month_date), end_run = runlen,
         last_ratio = tl$ratio[1],
         worst_ratio = if (runlen > 0) tl$ratio[which.max(abs(log(tl$ratio[seq_len(runlen)])))] else NA_real_,
         ratios_last4 = paste(sprintf("%.2f", head(tl$ratio, 4)), collapse = " "))
}

states <- sort(unique(pan$state_abb))
G <- map(states, prep) %>% set_names(states)

all_steps <- map_dfr(G, function(g) if (sum(g$use) >= MIN_MONTHS) steps_for(g) else tibble())
all_steps <- all_steps %>%
  mutate(persist = map2_dbl(state_abb, idx, ~ persist_for(G[[.x]], .y)),
         flag = abs(delta) >= MIN_STEP & abs(z) >= MIN_Z)

# ---- CO-MOVEMENT: is this boundary shared, or does this state step alone? ----
# The post-COVID rebound is a real nationwide shock -- nearly every state steps up
# at 2022-02..2022-05. A step is only artifact-SHAPED if the state takes it ALONE.
# For each flagged step we count how many OTHER states also step, same sign,
# within +/- 2 months of the same boundary.
peers <- all_steps %>% filter(flag) %>% select(state_abb, boundary, delta)
co_count <- function(st, bd, dl) {
  peers %>% filter(state_abb != st, sign(delta) == sign(dl),
                   abs(as.numeric(difftime(boundary, bd, units = "days"))) <= 70) %>%
    distinct(state_abb) %>% nrow()
}
all_steps <- all_steps %>%
  mutate(n_peer_states = ifelse(flag, pmap_int(list(state_abb, boundary, delta),
                                               ~ co_count(..1, ..2, ..3)), NA_integer_),
         verdict = case_when(
           !flag ~ NA_character_,
           n_peer_states >= 8 ~ "common shock",
           n_peer_states >= 3 ~ "partly shared",
           TRUE               ~ "IDIOSYNCRATIC"))

all_spikes <- map_dfr(G, spikes_for)
all_gaps   <- map_dfr(G, gaps_for)

write_csv(all_steps  %>% arrange(desc(abs(z))), file.path(OUT, "steps_all_candidates.csv"))
write_csv(all_steps  %>% filter(flag) %>% arrange(desc(abs(delta))), file.path(OUT, "steps_flagged.csv"))
write_csv(all_spikes %>% arrange(desc(abs(dev))), file.path(OUT, "spikes.csv"))
write_csv(all_gaps   %>% arrange(state_abb, gap_start), file.path(OUT, "gaps.csv"))

cat(glue("Interior level-shift check: {length(states)} states, ",
         "{sum(map_int(G, ~sum(.x$use)))} usable non-COVID state-months\n\n"))

cat(glue("=== (A) STEPS: sustained level shifts (>= {MIN_STEP} log pts AND |z| >= {MIN_Z}) ===\n"))
fl <- all_steps %>% filter(flag) %>% arrange(state_abb, boundary)
show <- function(df) {
  if (!nrow(df)) { cat("  none\n"); return(invisible()) }
  cat(sprintf("%-4s %-9s %8s %7s %6s %9s %6s  %s\n",
              "st","boundary","delta","pct","z","persist","peers","reading"))
  pwalk(df, function(state_abb, boundary, delta, pct, z, persist, n_peer_states, ...)
    cat(sprintf("%-4s %-9s %8.2f %6.0f%% %6.1f %9s %6d  %s\n", state_abb, format(boundary,"%Y-%m"),
                delta, 100*pct, z, ifelse(is.na(persist),"n/a",sprintf("%+.2f",persist)), n_peer_states,
                ifelse(is.na(persist), "edge of series",
                       ifelse(abs(persist) >= 0.5*abs(delta), "persists", "reverts")))))
}
cat("\n-- IDIOSYNCRATIC (state steps alone: <3 peer states) -> ARTIFACT SUSPECTS --\n")
show(fl %>% filter(verdict == "IDIOSYNCRATIC"))
cat("\n-- partly shared (3-7 peers) -> check individually --\n")
show(fl %>% filter(verdict == "partly shared"))
cat(glue("\n-- common shock (>=8 peers): {nrow(fl %>% filter(verdict=='common shock'))} boundaries across ",
         "{n_distinct((fl %>% filter(verdict=='common shock'))$state_abb)} states -- the post-COVID rebound, not an artifact --\n"))
cnt <- fl %>% filter(verdict == "common shock") %>% count(boundary) %>% arrange(desc(n))
cat("   busiest boundaries: ", paste(sprintf("%s (%d states)", format(head(cnt$boundary,4),"%Y-%m"), head(cnt$n,4)), collapse = ", "), "\n")

cat(glue("\n=== (B) SPIKES: single months >= {MIN_SPIKE} log pts off their own neighbourhood ===\n"))
if (nrow(all_spikes)) {
  print(as.data.frame(all_spikes %>% arrange(desc(abs(dev))) %>%
    mutate(pct = sprintf("%+.0f%%", 100*pct), dev = round(dev,2))), row.names = FALSE)
} else cat("  none\n")

all_end <- map_dfr(sort(unique(pan$state_abb)), end_for) %>% arrange(desc(end_run), desc(abs(log(last_ratio))))
write_csv(all_end, file.path(OUT, "series_end_step.csv"))
cat(glue("\n=== (D) SERIES-END STEP, two-sided (last months outside [{END_LO}, {END_HI}] of their own seasonal norm) ===\n"))
fe <- all_end %>% filter(end_run > 0)
if (nrow(fe)) {
  cat(sprintf("%-4s %-9s %5s %8s %8s  %s\n","st","ends","run","last","worst","last 4 ratios (newest first)"))
  pwalk(fe, function(state_abb, series_end, end_run, last_ratio, worst_ratio, ratios_last4)
    cat(sprintf("%-4s %-9s %5d %8.2f %8.2f  %s\n", state_abb, format(series_end,"%Y-%m"),
                end_run, last_ratio, worst_ratio, ratios_last4)))
} else cat("  none\n")

cat("\n=== (C) INTERIOR GAPS ===\n")
if (nrow(all_gaps)) {
  print(as.data.frame(all_gaps %>% arrange(state_abb, gap_start)), row.names = FALSE)
} else cat("  none\n")
cat(glue("\nWrote {OUT}/\n"))
