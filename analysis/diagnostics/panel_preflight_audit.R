# =============================================================================
# panel_preflight_audit.R  (2026-09-14)
#
# Pre-flight check on data/raw/state_month_panel_with_treatment.csv BEFORE
# committing cluster time to a run. Every issue found here that is later fixed
# forces ANOTHER vintage boundary and invalidates the run, so the point is to
# surface everything now.
#
# Checks: structural integrity, interior gaps, level breaks, basket quality,
# treat_start vs schedule agreement, coverage-vs-own-treatment, control-pool
# composition, and upstream staleness. Descriptive: blindness-safe.
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(lubridate); library(glue)})
CS <- as.Date("2020-03-01"); CE <- as.Date("2021-07-31")
EXCL <- c("NV","ID","HI","MS")
p <- read_csv("data/raw/state_month_panel_with_treatment.csv", show_col_types=FALSE) %>%
  mutate(month_date = as.Date(month_date),
         treat_start = suppressWarnings(as.Date(treat_start)))
n_issue <- 0
flag <- function(lbl, tbl) {
  if (is.null(tbl) || !nrow(tbl)) { cat(glue("  [ok]   {lbl}"), "\n"); return(invisible(0)) }
  cat(glue("  [FLAG] {lbl} -- {nrow(tbl)} case(s)"), "\n")
  print(as.data.frame(utils::head(tbl, 12)), row.names = FALSE); cat("\n"); nrow(tbl)
}

cat("=== 1. STRUCTURAL ===\n")
n_issue <- n_issue + flag("duplicate state-months", p %>% count(state_abb, month_date) %>% filter(n>1))
n_issue <- n_issue + flag("NA / non-finite filings", p %>% filter(is.na(filings_count) | !is.finite(filings_count)))
n_issue <- n_issue + flag("negative filings", p %>% filter(filings_count < 0))
n_issue <- n_issue + flag("zero filings (log1p ok, but check)", p %>% filter(filings_count == 0) %>% count(state_abb))
n_issue <- n_issue + flag("rows inside the COVID drop window (loader drops these, so only a note)",
                          p %>% filter(month_date >= CS, month_date <= CE) %>% count(state_abb) %>% slice(0))

cat("=== 2. INTERIOR GAPS (non-COVID) ===\n")
gaps <- p %>% arrange(state_abb, month_date) %>% group_by(state_abb) %>%
  mutate(nx=lead(month_date), g=interval(month_date,nx) %/% months(1)) %>%
  filter(!is.na(g), g>1, !(month_date >= CS %m-% months(1) & nx <= CE %m+% months(1))) %>%
  transmute(state_abb, from=month_date, to=nx, gap_months=g-1) %>% ungroup()
n_issue <- n_issue + flag("interior holes", gaps)

cat("=== 3. LEVEL BREAKS (|log jump| > 0.75 between adjacent observed months) ===\n")
brk <- p %>% filter(month_date < CS | month_date > CE) %>%
  arrange(state_abb, month_date) %>% group_by(state_abb) %>%
  mutate(d = log1p(filings_count) - log1p(lag(filings_count)),
         step = interval(lag(month_date), month_date) %/% months(1)) %>%
  filter(!is.na(d), step == 1, abs(d) > 0.75) %>%
  transmute(state_abb, month_date, jump_log = round(d,3),
            from = lag(filings_count), to = filings_count) %>% ungroup()
n_issue <- n_issue + flag("abrupt level breaks", brk)

cat("=== 4. BASKET QUALITY ===\n")
bk <- p %>% group_by(state_abb) %>%
  summarise(min_share = suppressWarnings(min(as.numeric(basket_share), na.rm=TRUE)),
            src = first(panel_source), .groups="drop") %>%
  filter(is.finite(min_share), min_share < 0.90)
n_issue <- n_issue + flag("basket_share < 0.90 (levels are NOT statewide)", bk)
n_issue <- n_issue + flag("varying n_counties within a state (composition churn)",
  p %>% group_by(state_abb) %>% summarise(k=n_distinct(na.omit(n_counties)), .groups="drop") %>% filter(k>1))

cat("=== 5. TREATMENT COLUMNS vs SCHEDULE ===\n")
ab <- c(Delaware="DE",`New Jersey`="NJ",`West Virginia`="WV",Pennsylvania="PA",`Rhode Island`="RI",
  Arkansas="AR",`New York`="NY",Iowa="IA",Indiana="IN",Oregon="OR",`New Hampshire`="NH",Illinois="IL",
  Michigan="MI",Colorado="CO",`District of Columbia`="DC",Tennessee="TN",Virginia="VA",
  `North Carolina`="NC",Arizona="AZ",Wyoming="WY",Connecticut="CT",Louisiana="LA",Maryland="MD",
  Kansas="KS",Massachusetts="MA",Ohio="OH",Kentucky="KY",Maine="ME",Florida="FL",Vermont="VT",
  Missouri="MO",Mississippi="MS",Montana="MT",`North Dakota`="ND",`New Mexico`="NM",
  `South Dakota`="SD",Washington="WA",Wisconsin="WI")
sch <- read_csv("data/raw/sports_gambling_legalization_dates.csv", show_col_types=FALSE) %>%
  transmute(state_abb = ab[state], online = as.Date(online_start_date))
ts <- p %>% distinct(state_abb, treat_start) %>% left_join(sch, by="state_abb")
n_issue <- n_issue + flag("treat_start disagrees with online_start_date",
  ts %>% filter(!( (is.na(treat_start)&is.na(online)) | (!is.na(treat_start)&!is.na(online)&treat_start==online) )))
n_issue <- n_issue + flag("`treated` flag inconsistent with treat_start",
  p %>% mutate(exp = !is.na(treat_start) & month_date >= treat_start) %>%
    filter(treated != exp) %>% count(state_abb))

cat("=== 6. COVERAGE vs OWN TREATMENT ===\n")
cov <- p %>% group_by(state_abb) %>% summarise(hi=max(month_date), .groups="drop") %>%
  left_join(sch, by="state_abb") %>% filter(!is.na(online), hi < online) %>%
  mutate(months_short = interval(hi, online) %/% months(1))
n_issue <- n_issue + flag("series ENDS BEFORE its own legalization (can never be a switcher)", cov)

cat("=== 7. CONTROL POOL ===\n")
ctrl <- p %>% distinct(state_abb, treat_start) %>% filter(is.na(treat_start), !state_abb %in% EXCL) %>%
  left_join(read_csv("data/raw/sports_gambling_legalization_dates.csv", show_col_types=FALSE) %>%
              transmute(state_abb = ab[state], retail = as.Date(retail_start_date)), by="state_abb") %>%
  filter(!is.na(retail))
n_issue <- n_issue + flag("control-pool states with LEGAL RETAIL sports betting", ctrl)

cat("=== 8. UPSTREAM STALENESS (a refresh would force ANOTHER vintage boundary) ===\n")
st <- p %>% group_by(state_abb) %>% summarise(hi=max(month_date), src=first(panel_source), .groups="drop") %>%
  mutate(stale = interval(hi, Sys.Date()) %/% months(1)) %>% filter(stale >= 15) %>% arrange(desc(stale))
n_issue <- n_issue + flag("states >= 15 months stale", st)

cat(glue("\n=== PRE-FLIGHT TOTAL: {n_issue} flagged case(s) ==="), "\n")
