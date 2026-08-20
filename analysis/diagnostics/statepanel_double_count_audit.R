#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# AUDIT: data/raw/state_month_panel_with_treatment.csv double-counts filings
#
# Finding (2026-08-20). The state panel's `filings_count` is NOT the ETS county
# download aggregated to the state. For 20 states it is
#
#     filings_count = (sum over reporting counties in monthly_county_data_download.csv)
#                   + (the ETS location series in ets_merged/merged_ets_combined.csv)
#
# added together. The ETS location series is the SAME filings already inside the
# county rows (statewide `state_level` series, or `cities_aggregated` city sites
# that sit inside counties the download already reports). So those state-months
# carry the same evictions twice.
#
# Because each state's ETS series covers a different span, the double count
# switches on/off at a state-specific date - a 1.5x-2.4x LEVEL BREAK in the
# middle of the panel with no eviction content. Two vintage boundaries dominate:
#   - `cities_aggregated` series START 2020-01  -> panel JUMPS UP  (AZ OH SC TN TX NV LA MA)
#   - `state_level` series END 2023-01          -> panel DROPS     (MN MO DE IN PA VA CT NM WI)
#   - FL and RI/NY `state_level` end 2019-12    -> panel DROPS at 2020-01
#
# This is the mechanism behind the TX (+0.785 vs -0.493) and MN (-0.715 vs
# -0.024) long-difference disagreements in longdiff_real_calendar_decomp.R.
#
# Usage:  Rscript analysis/diagnostics/statepanel_double_count_audit.R
# Output: output/statepanel_double_count/{identity_test,affected_states}.csv
# ─────────────────────────────────────────────────────────────────────────────

suppressMessages({ library(tidyverse); library(lubridate); library(glue) })
theme_set(theme_minimal())

# Reads the PRE-FIX panel by default so the audit stays reproducible after the
# 2026-08-20 rebuild. Point PANEL_AUDIT_FILE at the canonical file to confirm
# the fix landed (expected: 0 exact identities).
PANEL_AUDIT_FILE <- Sys.getenv("PANEL_AUDIT_FILE",
  "data/raw/deprecated/state_month_panel_with_treatment_double_counted_2026-08-20.csv")

OUT_DIR <- "output/statepanel_double_count"
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

fips_xwalk <- tibble(
  state_fips = c(1L,2L,4L,5L,6L,8L,9L,10L,11L,12L,13L,15L,16L,17L,18L,19L,20L,
                 21L,22L,23L,24L,25L,26L,27L,28L,29L,30L,31L,32L,33L,34L,35L,
                 36L,37L,38L,39L,40L,41L,42L,44L,45L,46L,47L,48L,49L,50L,51L,
                 53L,54L,55L,56L),
  state_abb  = c("AL","AK","AZ","AR","CA","CO","CT","DE","DC","FL","GA","HI",
                 "ID","IL","IN","IA","KS","KY","LA","ME","MD","MA","MI","MN",
                 "MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH",
                 "OK","OR","PA","RI","SC","SD","TN","TX","UT","VT","VA","WA",
                 "WV","WI","WY"))

# Counties per state (2020 Census) - used to judge whether the ETS download is
# already statewide, i.e. whether the added series can only be a duplicate.
n_counties <- c(AL=67,AK=29,AZ=15,AR=75,CA=58,CO=64,CT=8,DE=3,FL=67,GA=159,
                HI=5,ID=44,IL=102,IN=92,IA=99,KS=105,KY=120,LA=64,ME=16,MD=24,
                MA=14,MI=83,MN=87,MS=82,MO=115,MT=56,NE=93,NV=17,NH=10,NJ=21,
                NM=33,NY=62,NC=100,ND=53,OH=88,OK=77,OR=36,PA=67,RI=5,SC=46,
                SD=66,TN=95,TX=254,UT=29,VT=14,VA=133,WA=39,WV=55,WI=72,WY=23)

cty_raw <- read_csv("data/raw/monthly_county_data_download.csv",
                    show_col_types = FALSE) %>%
  mutate(month_date = floor_date(as.Date(date), "month"),
         state_fips = as.integer(fips) %/% 1000L) %>%
  inner_join(fips_xwalk, by = "state_fips") %>%
  filter(!is.na(filings_count))

cty <- cty_raw %>% group_by(state_abb, month_date) %>%
  summarise(cty = sum(filings_count), n_cty = n_distinct(fips), .groups = "drop")

# Coverage must be measured SIMULTANEOUSLY, not ever-observed: MN has all 87
# counties at some point but only 54-75 in any single month. Using ever-seen
# coverage would overstate how statewide the download is (audit finding, Codex
# review 2026-08-20).
cty_cov <- cty_raw %>% count(state_abb, month_date, name = "n_month") %>%
  group_by(state_abb) %>%
  summarise(n_cty_median_month = median(n_month),
            n_cty_max_month = max(n_month), .groups = "drop")

name_xwalk <- tibble(state_abb = state.abb,
                     nmz = tolower(gsub(" ", "", state.name)))

ets <- read_csv("data/raw/ets_merged/merged_ets_combined.csv",
                show_col_types = FALSE) %>%
  mutate(nmz = gsub(" ", "", location_std)) %>%
  inner_join(name_xwalk, by = "nmz") %>%
  select(state_abb, month_date, ets = filings_count, source)

sp <- read_csv(PANEL_AUDIT_FILE, show_col_types = FALSE) %>%
  mutate(month_date = as.Date(month_date)) %>%
  select(state_abb, month_date, spf = filings_count)

# ---- Identity test: state panel == county sum + ETS series? ----------------
ident <- sp %>%
  left_join(cty, by = c("state_abb", "month_date")) %>%
  left_join(ets, by = c("state_abb", "month_date")) %>%
  mutate(cty = coalesce(cty, NA_real_), ets = coalesce(ets, 0),
         pred = coalesce(cty, 0) + ets, resid = spf - pred)

# Genuine double counting requires BOTH sources non-zero in the same month.
# (States with ets > 0 but no county coverage at all -- LA MA MO NM NV NY RI --
# are single-sourced from ETS and are NOT double counted.)
overlap <- ident %>% filter(ets > 0, cty > 0)

ident_by_state <- overlap %>% group_by(state_abb, source) %>%
  summarise(n_double_counted_months = n(),
            pct_exact_identity = round(mean(abs(resid) < 0.5) * 100, 1),
            first_month = min(month_date), last_month = max(month_date),
            median_inflation = round(median(spf / pmax(cty, 1)), 2),
            .groups = "drop") %>%
  left_join(cty_cov, by = "state_abb") %>%
  left_join(overlap %>% group_by(state_abb) %>%
              summarise(ets_over_cty = round(median(ets / pmax(cty, 1)), 2),
                        .groups = "drop"), by = "state_abb") %>%
  mutate(counties_in_state = n_counties[state_abb],
         median_month_coverage = round(n_cty_median_month / counties_in_state, 2),
         # A duplicate label needs BOTH near-statewide simultaneous coverage AND
         # a like-for-like level. Neither alone is sufficient: the exact
         # `old = county + ETS` identity proves how the old panel was BUILT, not
         # that the two components measure the same geography.
         diagnosis = case_when(
           median_month_coverage >= 0.85 & abs(ets_over_cty - 1) <= 0.40 ~
             "near-statewide monthly coverage AND like-for-like level -> DUPLICATE",
           median_month_coverage >= 0.85 ~
             "near-statewide coverage but level differs -> duplicate + scope gap",
           TRUE ~
             "partial monthly coverage -> added series duplicates part, adds part")) %>%
  arrange(desc(n_double_counted_months))

cat(glue("\n{nrow(overlap)} state-months carry an added ETS series; ",
         "{sum(abs(overlap$resid) < 0.5)} ",
         "({round(mean(abs(overlap$resid) < 0.5) * 100, 1)}%) are an EXACT ",
         "county-sum + ETS-series addition.\n",
         "Panel audited: {PANEL_AUDIT_FILE}\n\n"))
print(as.data.frame(ident_by_state %>%
  select(state_abb, source, n_double_counted_months, pct_exact_identity,
         first_month, last_month, median_inflation, n_cty_median_month,
         counties_in_state, median_month_coverage, ets_over_cty, diagnosis)),
  digits = 3)

# ---- What it does to the real-calendar long difference ---------------------
BASE <- c(as.Date("2017-01-01"), as.Date("2018-12-01"))
ENDP <- c(as.Date("2024-10-01"), as.Date("2025-09-01"))

ld <- ident %>%
  mutate(win = case_when(month_date >= BASE[1] & month_date <= BASE[2] ~ "base",
                         month_date >= ENDP[1] & month_date <= ENDP[2] ~ "endp",
                         TRUE ~ NA_character_)) %>%
  filter(!is.na(win)) %>%
  filter(!is.na(cty)) %>%
  group_by(state_abb, win) %>%
  summarise(nm = n(), sp_l = mean(log1p(spf)), ct_l = mean(log1p(cty)),
            .groups = "drop") %>%
  pivot_wider(names_from = win, values_from = c(nm, sp_l, ct_l)) %>%
  filter(nm_base == 24, nm_endp == 12) %>%
  # keep only states the county download actually covers in BOTH windows
  semi_join(cty %>% filter(month_date >= BASE[1], month_date <= BASE[2]) %>%
              distinct(state_abb), by = "state_abb") %>%
  transmute(state_abb,
            dY_state_panel = sp_l_endp - sp_l_base,
            dY_county_file = ct_l_endp - ct_l_base,
            artifact = dY_state_panel - dY_county_file) %>%
  arrange(desc(abs(artifact)))

cat(glue("\n\nReal-calendar long difference, cross-state SD:\n",
         "  state panel  = {round(sd(ld$dY_state_panel), 3)}\n",
         "  county file  = {round(sd(ld$dY_county_file), 3)}\n\n"))
print(as.data.frame(ld), digits = 3)

write_csv(ident_by_state, file.path(OUT_DIR, "affected_states.csv"))
write_csv(ld,             file.path(OUT_DIR, "identity_test.csv"))
cat(glue("\nWrote {OUT_DIR}/affected_states.csv and identity_test.csv\n"))
