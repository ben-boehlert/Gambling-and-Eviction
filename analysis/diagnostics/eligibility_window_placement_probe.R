################################################################################
# analysis/diagnostics/eligibility_window_placement_probe.R
#
# WHY does the (18,0) eligibility window nearly double the state LP-DiD delta=0
# SD relative to (12,6) on the same panel and the same 24T/11C placement?
# (Runs: lpdid_clean_gate_ewatt_pmd6_v20260914 SD 0.0628 vs _w126 SD 0.0337.)
#
# Regenerates the D1 pseudo-schedules of both runs from their recorded seed_rep
# (first 300 reps) and scores every placed switcher on what the clean-anchor
# estimator can actually use: is the strict 6-month pre-launch baseline
# observed, and how many of the 13 outcome months [launch+12, launch+24] exist.
# No outcomes are touched -- placement + coverage only (blind-safe).
#
# RESULT 2026-09-16 (300 reps each):
#   (12,6): 24 placed, 11.8 contributing, 9.9 dead (no baseline), 1.7 thin
#           (<=3 horizons), 5.2 full (13/13); 114 horizons; SD(att) 0.033
#   (18,0): 24 placed, 16.3 contributing, 7.7 dead, 4.9 thin, 4.5 full;
#           119 horizons; SD(att) 0.060
#   (18,0) converts ~4.5 dead slots per rep into THIN contributors: 48% of thin
#   slots have their outcome months at the pre-COVID edge (2020-01/02), 34% at
#   the post-reopening edge (2021-08..10), 18% at a series end. Total usable
#   horizons barely move (114 -> 119). Within (18,0), SD rises with the thin
#   count (0.051 at 3-4 thin vs 0.065 at 5+).
#
# Output (aggregates): output/eligibility_window_probe/{rep_summary,slot_summary,
#   thin_reasons,thin_outcome_months}.csv
# Run from the project root:
#   Rscript analysis/diagnostics/eligibility_window_placement_probe.R
################################################################################
suppressPackageStartupMessages({library(dplyr); library(lubridate); library(readr)})
source("R/power/config.R"); source("R/power/blindness_checks.R")
source("R/power/load_blinded_panel.R"); source("R/power/make_pseudo_schedules.R")
cfg <- read_power_config("config/power_lpdid_clean_gate_ewatt_pmd6_v20260914.yml")
panel <- load_blinded_panel(level = "state", treat_def = "shift12_start_date",
                            anticipation = 6L, sample = "S2", covid = "drop",
                            quarterly = FALSE, time_agg = "month",
                            complete_periods_only = FALSE, config = cfg)
panel <- panel[!panel$state_abb %in% c("NV","ID","HI","MS"), ]
real_schedule <- guarded_read_csv(cfg$schedule)
obs <- split(.month_index(panel$month_date), panel$state_abb)

score_rep <- function(seed_rep, min_pre, min_post) {
  sched <- tryCatch(make_pseudo_schedule("D1", panel, real_schedule, "shift12_start_date",
                                         min_pre = min_pre, min_post = min_post,
                                         seed = seed_rep, template = "panel"),
                    error = function(e) NULL)
  if (is.null(sched)) return(NULL)
  # lag from event to launch: same rank-matched rule as the runner
  rs <- real_schedule; rs$ev <- as.Date(rs$shift12_start_date); rs$on <- as.Date(rs$online_start_date)
  rs$ab <- c(state.abb, "DC")[match(rs$state, c(state.name, "District of Columbia"))]
  rs <- rs[!is.na(rs$ev) & !is.na(rs$on) & rs$ab %in% unique(panel$state_abb), ]
  rs$lag <- as.integer(round(as.numeric(difftime(rs$ev, rs$on, units = "days")) / 30.44))
  coh <- aggregate(lag ~ ev, rs, median); coh <- coh[order(coh$ev), ]
  pd <- sort(unique(as.Date(sched$pseudo_g)))
  ok <- length(pd) == nrow(coh) && all(diff(.month_index(pd)) == diff(.month_index(coh$ev)))
  lagv <- if (ok) coh$lag else rep(median(coh$lag), length(pd))
  L <- .month_index(as.Date(sched$pseudo_g)) - lagv[match(as.Date(sched$pseudo_g), pd)]
  st <- sched$state_abb
  base_ok <- mapply(function(s, l) all((l - 6):(l - 1) %in% obs[[s]]), st, L)
  n_out   <- mapply(function(s, l) sum((l + 12):(l + 24) %in% obs[[s]]), st, L)
  tibble(state_abb = st, launch_m = L, base_ok = base_ok, n_out = n_out,
         contrib = base_ok & n_out >= 1)
}

load_att <- function(run) {
  read_csv(file.path("output_blinded_power", run, "results_raw.csv.gz"), show_col_types = FALSE) %>%
    filter(estimator == "lpdid", inference == "analytic", grepl("spliced", name)) %>%
    select(rep, seed_rep, att)
}
runs <- list(`(18,0)` = c("lpdid_clean_gate_ewatt_pmd6_v20260914", 18, 0),
             `(12,6)` = c("lpdid_clean_gate_ewatt_pmd6_v20260914_w126", 12, 6))
NREP <- 300
res <- list(); per_state <- list()
for (nm in names(runs)) {
  r <- runs[[nm]]; att <- load_att(r[1]) %>% filter(rep <= NREP)
  sc <- lapply(seq_len(nrow(att)), function(i) {
    s <- score_rep(att$seed_rep[i], as.integer(r[2]), as.integer(r[3]))
    if (is.null(s)) return(NULL)
    s$rep <- att$rep[i]; s
  }) %>% bind_rows()
  per_state[[nm]] <- sc %>% mutate(rule = nm)
  rep_sum <- sc %>% group_by(rep) %>%
    summarise(n_placed = n(), n_contrib = sum(contrib), n_dead = sum(!base_ok),
              n_thin = sum(contrib & n_out <= 3), n_full = sum(contrib & n_out == 13),
              horizons = sum(n_out[contrib]), .groups = "drop") %>%
    inner_join(att, by = "rep")
  res[[nm]] <- rep_sum %>% mutate(rule = nm)
}
allr <- bind_rows(res)
cat("\n== per-rep placement summary (means over", NREP, "reps) ==\n")
print(allr %>% group_by(rule) %>% summarise(across(c(n_placed, n_contrib, n_dead, n_thin, n_full, horizons), mean),
                                            sd_att = sd(att), mean_att = mean(att)), width = 200)
cat("\n== SD of att by number of thin (<=3 horizon) contributing switchers ==\n")
print(allr %>% mutate(thin_bin = cut(n_thin, c(-1, 0, 2, 4, 99), labels = c("0","1-2","3-4","5+"))) %>%
        group_by(rule, thin_bin) %>% summarise(n = n(), sd_att = sd(att), .groups = "drop"), width = 200)
cat("\n== horizon distribution of CONTRIBUTING switchers (share of switcher-slots) ==\n")
ps <- bind_rows(per_state)
print(ps %>% filter(contrib) %>% mutate(hbin = cut(n_out, c(0, 3, 6, 12, 13), labels = c("1-3","4-6","7-12","13"))) %>%
        count(rule, hbin) %>% group_by(rule) %>% mutate(share = round(n / sum(n), 3)) %>% select(-n) %>%
        tidyr::pivot_wider(names_from = hbin, values_from = share), width = 200)
cat("\n== which states are THIN contributors under (18,0) (share of that state's placements) ==\n")
print(ps %>% filter(rule == "(18,0)") %>% group_by(state_abb) %>%
        summarise(placed = n(), contrib = mean(contrib), thin = mean(contrib & n_out <= 3),
                  dead = mean(!base_ok), mean_out = mean(n_out[contrib]), .groups = "drop") %>%
        arrange(desc(thin)) %>% filter(thin > 0.05), n = 30)
cat("\n== dead (no-baseline) states under (12,6) ==\n")
print(ps %>% filter(rule == "(12,6)") %>% group_by(state_abb) %>%
        summarise(placed = n(), dead = mean(!base_ok), contrib = mean(contrib), mean_out = mean(n_out[contrib]), .groups = "drop") %>%
        arrange(desc(dead)) %>% filter(dead > 0.05), n = 30)

maxm <- sapply(obs, max)
gap_lo <- .month_index(as.Date("2020-03-01")); gap_hi <- .month_index(as.Date("2021-07-01"))
ps <- bind_rows(per_state) %>% mutate(is_contrib = contrib, is_thin = contrib & n_out <= 3, is_dead = !base_ok)
cat("\n== per-state, (18,0): share of placements contributing / thin / dead; mean horizons among contributing ==\n")
ps18 <- ps %>% filter(rule == "(18,0)") %>% group_by(state_abb) %>%
  summarise(placed = n(), p_contrib = mean(is_contrib), p_thin = mean(is_thin), p_dead = mean(is_dead),
            mean_out = mean(n_out[is_contrib]), .groups = "drop") %>% arrange(desc(p_thin))
print(ps18 %>% filter(p_thin > 0.05), n = 30)
cat("\n== per-state, (12,6): same ==\n")
ps12 <- ps %>% filter(rule == "(12,6)") %>% group_by(state_abb) %>%
  summarise(placed = n(), p_contrib = mean(is_contrib), p_thin = mean(is_thin), p_dead = mean(is_dead),
            mean_out = mean(n_out[is_contrib]), .groups = "drop") %>% arrange(desc(p_dead))
print(ps12 %>% filter(p_dead > 0.3 | p_thin > 0.05), n = 30)
cat("\n== thin contributing slots under (18,0): why thin? ==\n")
thin <- ps %>% filter(rule == "(18,0)", is_thin) %>% rowwise() %>% mutate(
  win_lo = launch_m + 12, win_hi = launch_m + 24,
  crosses_gap = win_lo <= gap_hi & win_hi >= gap_lo,
  pre_gap_edge  = crosses_gap & win_lo < gap_lo,          # outcome months are the last pre-COVID months
  post_gap_edge = crosses_gap & win_hi > gap_hi & win_lo >= gap_lo,  # outcome months are the first post-COVID months
  series_end    = !crosses_gap & maxm[state_abb] < win_hi,
  other         = !crosses_gap & !series_end) %>% ungroup()
print(thin %>% summarise(n = n(), pre_gap_edge = mean(pre_gap_edge), post_gap_edge = mean(post_gap_edge),
                         series_end = mean(series_end), other = mean(other)))
cat("\n== calendar months of the outcome observations of thin (18,0) slots ==\n")
mo <- thin %>% rowwise() %>% do({
  s <- .$state_abb; w <- (.$win_lo):(.$win_hi); w <- w[w %in% obs[[s]]]
  tibble(m = w)
}) %>% ungroup() %>% mutate(ym = sprintf("%d-%02d", m %/% 12, m %% 12 + 1)) %>% count(ym, sort = TRUE)
print(head(mo, 12))
cat("\n== under (12,6), the same-cohort slots: who fills them and how many horizons ==\n")
print(ps %>% filter(is_contrib) %>% group_by(rule) %>% summarise(slots = n(), mean_out = mean(n_out), share_thin = mean(n_out <= 3), share_full = mean(n_out == 13)))

readr::write_csv(allr, "output/eligibility_window_probe/rep_summary.csv")
readr::write_csv(bind_rows(ps18 %>% mutate(rule = "(18,0)"), ps12 %>% mutate(rule = "(12,6)")),
                 "output/eligibility_window_probe/slot_summary.csv")
readr::write_csv(thin %>% summarise(n = n(), pre_gap_edge = mean(pre_gap_edge), post_gap_edge = mean(post_gap_edge),
                                    series_end = mean(series_end)), "output/eligibility_window_probe/thin_reasons.csv")
readr::write_csv(mo, "output/eligibility_window_probe/thin_outcome_months.csv")
