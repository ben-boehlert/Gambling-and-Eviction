#!/usr/bin/env Rscript
# ============================================================================
# append_lsc_site_months.R  (2026-09-17)
#
# Extend the HYBRID county file with the months the LSC site publishes beyond
# the bulk download's end, WITHOUT touching any existing row.
#
# READ CLAUDE.md's hybrid-file box first. data/raw/monthly_county_data_download
# .csv is LSC CCDI plus merged court sources (NC, ME). It must never be
# overwritten by a fresh LSC pull. This script is the safe operation the Maine
# repair established: existing (fips, month) keys are left byte-identical; only
# NEW keys are appended.
#
# WHAT IS APPENDED. Rows from the site pull whose (fips, month) key is absent
# from the hybrid file AND whose month is after the bulk download's terminal
# month (BULK_END, 2025-09 on the 2026-09-17 pull). Earlier site-only keys are
# the site's zero-fill or LSC's own back-fill of history; they are reported in
# the audit file, not appended -- adding history changes the fixed basket and
# is a separate decision.
#
# WHAT IS NOT DONE. LSC revises history between vintages. Shared keys whose
# value differs between the site and the hybrid file are written to an audit
# CSV (by state, year, size) and left as they are. Decide on revisions with
# that file in hand; do not fold them in here.
#
# After this script: Rscript data_prep/rebuild_state_month_panel.R, then
# Rscript data_prep/make_data_currency_doc.R. The rebuild's fixed-basket rule
# emits a new state-month only when EVERY basket county reports it, so a state
# whose basket is incomplete in the new months simply keeps its old end date.
#
# Input : data/raw/monthly_expansion/lsc_site/lsc_site_county_month_<stamp>.csv
#         data/raw/monthly_county_data_download.csv
# Output: data/raw/monthly_county_data_download.csv           (rows appended)
#         data/raw/deprecated/monthly_county_data_download_pre_lsc_site_<stamp>.csv
#         data/processed/lsc_site_append_<stamp>.csv           (what was added)
#         data/processed/lsc_site_revisions_<stamp>.csv        (what was NOT)
# Run from the project root:  Rscript data_prep/append_lsc_site_months.R
#   env SITE_STAMP=YYYY-MM-DD picks the pull; BULK_END overrides the cutoff.
# ============================================================================
suppressMessages({ library(tidyverse) })

STAMP    <- Sys.getenv("SITE_STAMP", format(Sys.Date(), "%Y-%m-%d"))
BULK_END <- as.Date(Sys.getenv("BULK_END", "2025-09-01"))
HYB      <- "data/raw/monthly_county_data_download.csv"
SITE     <- sprintf("data/raw/monthly_expansion/lsc_site/lsc_site_county_month_%s.csv", STAMP)
stopifnot(file.exists(SITE))

hyb_raw <- read_lines(HYB)                       # kept verbatim for the append
hyb <- read_csv(HYB, show_col_types = FALSE, col_types = cols(fips = col_character())) %>%
  mutate(month_date = as.Date(date))
site <- read_csv(SITE, show_col_types = FALSE, col_types = cols(fips = col_character())) %>%
  mutate(month_date = as.Date(date))
stopifnot(identical(names(hyb)[1:7], names(site)[1:7]))

key_h <- paste(hyb$fips, hyb$month_date)
key_s <- paste(site$fips, site$month_date)

# ---- Revisions audit (not applied) -----------------------------------------
rev <- site %>% mutate(key = key_s) %>%
  inner_join(hyb %>% mutate(key = key_h) %>% select(key, hyb_count = filings_count), by = "key") %>%
  filter(filings_count != hyb_count) %>%
  transmute(fips, name, state_short, month_date, hyb_count, site_count = filings_count,
            rel_change = (site_count - hyb_count) / pmax(hyb_count, 1))
write_csv(rev, sprintf("data/processed/lsc_site_revisions_%s.csv", STAMP))
cat(sprintf("revisions on shared keys (NOT applied): %d rows, %d states; median |rel| %.3f\n",
            nrow(rev), n_distinct(rev$state_short), median(abs(rev$rel_change))))
print(rev %>% count(state_short, sort = TRUE) %>% head(10))

# ---- New months -------------------------------------------------------------
add <- site %>% filter(!(key_s %in% key_h), month_date > BULK_END)
# The site's county object does not carry renter_occupied_housing_units (the
# rebuild sums it per row as the rate denominator). It is a per-county constant
# in the hybrid file (0 counties with >1 distinct value), so carry it forward
# from the county's existing rows; poverty_rate likewise.
cty_const <- hyb %>% arrange(fips, month_date) %>% group_by(fips) %>%
  summarise(renter_occupied_housing_units = last(na.omit(renter_occupied_housing_units)),
            poverty_rate = last(na.omit(poverty_rate)), .groups = "drop")
add <- add %>% select(-renter_occupied_housing_units, -poverty_rate) %>%
  left_join(cty_const, by = "fips")
cat(sprintf("renter denominator carried forward for %d of %d appended rows\n",
            sum(!is.na(add$renter_occupied_housing_units)), nrow(add)))
skipped_hist <- sum(!(key_s %in% key_h) & site$month_date <= BULK_END)
cat(sprintf("\nappending %d county-month rows after %s (%d earlier site-only keys skipped)\n",
            nrow(add), format(BULK_END, "%Y-%m"), skipped_hist))
print(add %>% count(state_short, sort = TRUE), n = 40)

write_csv(add %>% select(fips, name, state_short, month_date, filings_count,
                         percent_of_historical_average),
          sprintf("data/processed/lsc_site_append_%s.csv", STAMP))

# ---- Backup then append, existing lines untouched ---------------------------
bak <- sprintf("data/raw/deprecated/monthly_county_data_download_pre_lsc_site_%s.csv", STAMP)
dir.create(dirname(bak), showWarnings = FALSE)
if (!file.exists(bak)) file.copy(HYB, bak)
# Match the hybrid file's own date formatting ("2017-03-01 12:00:00") and
# column order; numeric columns as in the download.
new_lines <- add %>%
  transmute(fips, name, date = paste(format(month_date, "%Y-%m-%d"), "12:00:00"),
            filings_count, percent_of_historical_average,
            renter_occupied_housing_units, poverty_rate) %>%
  format_csv(na = "") %>% str_split("\n") %>% .[[1]] %>% .[-1] %>% .[nzchar(.)]
write_lines(c(hyb_raw[nzchar(hyb_raw)], new_lines), HYB)

chk <- read_csv(HYB, show_col_types = FALSE, col_types = cols(fips = col_character()))
stopifnot(nrow(chk) == nrow(hyb) + nrow(add),
          !anyDuplicated(paste(chk$fips, chk$date)))
cat(sprintf("\n%s: %d -> %d rows; backup at %s\n", HYB, nrow(hyb), nrow(chk), bak))
