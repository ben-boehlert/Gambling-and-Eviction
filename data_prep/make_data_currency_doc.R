# =============================================================================
# make_data_currency_doc.R   (2026-09-14)
#
# GENERATES docs/DATA_CURRENCY.md from the panel itself, so the currency table
# can never drift from the data the way prose does. Re-run after any panel
# rebuild or source refresh:
#
#     Rscript data_prep/make_data_currency_doc.R
#
# Answers one question per state: how old is this series, who supplies it, how
# much of the state does it cover, what role can it play, and what command
# refreshes it. Descriptive only: blindness-safe.
# =============================================================================

suppressPackageStartupMessages({library(tidyverse); library(lubridate); library(glue)})

PANEL <- "data/raw/state_month_panel_with_treatment.csv"
OUT   <- "docs/DATA_CURRENCY.md"
TODAY <- Sys.Date()
CS <- as.Date("2020-03-01"); CE <- as.Date("2021-07-31")
PRE <- 6; PLO <- 12; PHI <- 24
EXCL <- c("NV","ID","HI","MS")

REFRESH <- c(
  county_download_fixed_basket      = "Download a fresh `monthly_county_data_download.csv` from civilcourtdata.lsc.gov, then `Rscript data_prep/rebuild_state_month_panel.R`",
  `ets_internal_county_2026-09-03`  = "Obtain a newer Eviction Lab internal extract, replace `ets_county_month.csv`, then `Rscript data_prep/rebuild_single_series_from_ets_internal.R`",
  md_judiciary_lt_complaint_filings = "Pull new monthly PDFs from the MD Judiciary statistics page into `data/raw/monthly_expansion/md_raw/`, then re-run the MD extraction",
  `nh_court_source_repair_2026-07-23` = "Request an updated extract from the NH Judicial Branch",
  `wi_court_source_repair_2026-07-23` = "Re-download the WI Dept. of Administration series",
  `or_ojd_plus_evictedinoregon_2026-09-14` = "Re-export the Evicted in Oregon dashboard (mutable -- the publisher revises it), then `Rscript data_prep/add_oregon_to_state_panel.R`",
  `ets_internal_county_wa_2026-09-14` = "Obtain a newer Eviction Lab internal extract, replace `ets_county_month.csv`, then `Rscript data_prep/add_wa_to_state_panel.R`",
  `mi_jdw_statewide_2026-09-03` = "Re-download `conditional-dismissals.pdf` from courts.michigan.gov, run `python3 data_prep/parse_mi_jdw_lt_filings_pdf.py`, then `Rscript data_prep/add_mi_to_state_panel.R`",
  `id_courts_a12_2026-09-14` = "`Rscript data_prep/pull_id_powerbi_eviction_filings.R`, then `Rscript data_prep/add_id_to_state_panel.R` (the ID dashboard is a rolling five-year window)")

pan <- read_csv(PANEL, show_col_types = FALSE) %>% mutate(month_date = as.Date(month_date))
sched <- read_csv("data/raw/sports_gambling_legalization_dates.csv", show_col_types = FALSE)
ab <- c(Delaware="DE",`New Jersey`="NJ",`West Virginia`="WV",Pennsylvania="PA",`Rhode Island`="RI",
  Arkansas="AR",`New York`="NY",Iowa="IA",Indiana="IN",Oregon="OR",`New Hampshire`="NH",Illinois="IL",
  Michigan="MI",Colorado="CO",`District of Columbia`="DC",Tennessee="TN",Virginia="VA",
  `North Carolina`="NC",Arizona="AZ",Wyoming="WY",Connecticut="CT",Louisiana="LA",Maryland="MD",
  Kansas="KS",Massachusetts="MA",Ohio="OH",Kentucky="KY",Maine="ME",Florida="FL",Vermont="VT",
  Missouri="MO",Mississippi="MS",Montana="MT",`North Dakota`="ND",`New Mexico`="NM",
  `South Dakota`="SD",Washington="WA",Wisconsin="WI")
online <- setNames(as.Date(sched$online_start_date), ab[sched$state])

obs <- pan %>% filter(month_date < CS | month_date > CE) %>% distinct(state_abb, month_date)
oset <- split(obs$month_date, obs$state_abb)

gaps <- pan %>% arrange(state_abb, month_date) %>% group_by(state_abb) %>%
  mutate(nx = lead(month_date), g = interval(month_date, nx) %/% months(1)) %>%
  filter(!is.na(g), g > 1, !(month_date >= CS %m-% months(1) & nx <= CE %m+% months(1))) %>%
  summarise(max_gap = max(g) - 1L, .groups = "drop")

d <- pan %>% group_by(state_abb) %>%
  summarise(source = first(panel_source), months = n(),
            lo = min(month_date), hi = max(month_date),
            n_counties = suppressWarnings(max(as.numeric(n_counties), na.rm = TRUE)),
            basket_share = suppressWarnings(min(as.numeric(basket_share), na.rm = TRUE)),
            has_denom = any(!is.na(renter_occupied_housing_units)), .groups = "drop") %>%
  left_join(gaps, by = "state_abb") %>%
  mutate(max_gap = replace_na(max_gap, 0L),
         stale = interval(hi, TODAY) %/% months(1),
         online = online[state_abb],
         across(c(n_counties, basket_share), ~ if_else(is.finite(.x), .x, NA_real_))) %>%
  rowwise() %>%
  mutate(n_base = if (is.na(online)) NA_integer_ else
           sum(seq(online %m-% months(PRE), by = "month", length.out = PRE) %in% oset[[state_abb]]),
         n_out = if (is.na(online)) NA_integer_ else
           sum(seq(online %m+% months(PLO), online %m+% months(PHI), by = "month") %in% oset[[state_abb]])) %>%
  ungroup() %>%
  mutate(role = case_when(
    state_abb %in% EXCL ~ "excluded",
    is.na(online) ~ "control (no online date)",
    n_base == PRE & n_out == 13 ~ "**switcher (full)**",
    n_base == PRE & n_out > 0 ~ glue("switcher (partial {n_out}/13)"),
    TRUE ~ "not a switcher"),
    flag = case_when(stale >= 24 ~ "STALE", stale >= 15 ~ "aging", TRUE ~ ""),
    flag = if_else(!is.na(basket_share) & basket_share < 0.9,
                   paste(flag, "THIN-BASKET"), flag) %>% str_trim())

fmt <- function(x, d = 2) if_else(is.na(x), "--", formatC(x, format = "f", digits = d))
rows <- d %>% arrange(desc(stale)) %>%
  transmute(line = glue("| {state_abb} | {source} | {format(lo,'%Y-%m')}–{format(hi,'%Y-%m')} | {months} | ",
                        "**{stale}** | {if_else(max_gap>0, as.character(max_gap), '--')} | ",
                        "{if_else(is.na(n_counties),'--',as.character(n_counties))} | {fmt(basket_share)} | ",
                        "{if_else(has_denom,'yes','**no**')} | {role} | {flag} |")) %>% pull(line)

src <- d %>% group_by(source) %>%
  summarise(n = n(), med_stale = median(stale), med_hi = max(hi), .groups = "drop") %>%
  arrange(desc(med_stale)) %>%
  mutate(line = glue("| `{source}` | {n} | {med_stale} | {format(med_hi,'%Y-%m')} | {REFRESH[source]} |"))

writeLines(c(
  "# Data Currency",
  "",
  glue("**Generated {TODAY} by `data_prep/make_data_currency_doc.R` — do not hand-edit.**"),
  glue("Regenerate after any panel rebuild or source refresh. Source of truth: `{PANEL}`."),
  "",
  "Companion docs: [DATA_PROVENANCE.md](DATA_PROVENANCE.md) (who collected what, and whether that is verified)",
  "and [STATE_SOURCES.md](STATE_SOURCES.md) (per-state scope — whole state vs county basket vs single city).",
  "",
  "## How to read this",
  "",
  glue("- **Stale** = months between the series' last month and {format(TODAY,'%Y-%m')}. `aging` at 15+, `STALE` at 24+."),
  "- **Max gap** = longest interior hole in months, *excluding* the COVID drop window (2020-03 – 2021-07).",
  "- **Basket** = `basket_share`, the fraction of the state's reporting counties held in the fixed basket.",
  "  `THIN-BASKET` flags anything below 0.90 — those states' LEVELS are not statewide and must not be read as such.",
  "- **Denominator** = whether `renter_occupied_housing_units` is populated. The headline outcome is",
  "  `y_log1p = log1p(filings_count)` (counts), so a missing denominator blocks only the `y_lograte`",
  "  sensitivity arm, not the main analysis.",
  "- **Role** = status under the clean-anchor rule (6-month pre-launch baseline, outcomes 12–24 months",
  "  post-launch, COVID window dropped, ex NV/ID/HI/MS). Necessary but not sufficient — a cell also needs a",
  "  surviving not-yet-treated control.",
  "",
  "## By source",
  "",
  "| Source | States | Median stale (mo) | Latest month | How to refresh |",
  "|---|---:|---:|---|---|",
  src$line,
  "",
  "## By state — stalest first",
  "",
  "| State | Source | Span | Months | Stale (mo) | Max gap | Counties | Basket | Denom | Role | Flag |",
  "|---|---|---|---:|---:|---:|---:|---:|---|---|---|",
  rows,
  "",
  "## Known limits of this table",
  "",
  "- It reports what the panel *contains*, not whether the upstream source has newer data. A state can look",
  "  current and still be behind its provider.",
  "- `basket_share` is computed against counties observed **in this panel**, not against all counties in the",
  "  state. A state whose provider only ever covered 3 counties shows 1.00.",
  "- Staleness is measured against today's date, so this file's numbers drift until it is regenerated."
), OUT)

cat(glue("Wrote {OUT}: {nrow(d)} states, {nrow(src)} sources.\n\n"))
print(as.data.frame(d %>% filter(flag != "") %>%
        select(state_abb, source, hi, stale, basket_share, role, flag) %>%
        arrange(desc(stale))), row.names = FALSE)
