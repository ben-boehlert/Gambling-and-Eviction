# Missing major counties, all 39 panel states (audited 2026-09-14)

Follow-on from [2026-09-14_colorado-monthly-fed-dashboard.md](2026-09-14_colorado-monthly-fed-dashboard.md).
Script: `analysis/diagnostics/missing_major_county_audit.R`. Outputs:
`data/processed/missing_major_county_audit.csv`, `..._excluded_top5.csv`, `..._absent_from_feed.csv`.

**Answer: yes — Denver is not the worst case. Florida and Texas are.**

## Two distinct failure modes

| Mode | What happens | Measurable offline? | Archetype |
|---|---|---|---|
| **Absent from the feed** | County never appears in `monthly_county_data_download.csv` at all | Names only — the feed carries no renter count for it | **CO → Denver** |
| **Excluded by the basket rule** | County is in the feed but misses a basket-window month, so the fixed-basket rule drops it | Yes, renters are in the feed | **FL → Miami-Dade**, **TX → Harris** |

## The retroactive mechanism (mode 2)

The basket window is 2016-01 → 2024-12, and a county enters its state's basket only by
reporting in **every** month the state reports. So a county that stops reporting *at any point
through 2024* is removed from that state's series **all the way back to 2016** — it was never in
the panel, not "lost at the dropout date."

Observed dropouts doing exactly this:

| County | Renters | Last month in feed | Effect |
|---|---:|---|---|
| Harris TX (Houston) | 781,714 | 2024-05 | out of TX's entire 2016+ series |
| Miami-Dade FL | 461,243 | 2023-12 | out of FL's entire 2016+ series |
| Lee FL | 83,155 | 2023-12 | same |
| Ada ID (Boise) | 56,346 | 2025-05 | out of ID's series (ID basket = 1 county) |
| Rutherford TN | 44,033 | 2024-02 | out of TN's series |
| Kanawha WV (Charleston) | 22,913 | 2025-09 | out of WV's series (interior gaps) |

FINDINGS.md §5 described "FL losing Miami-Dade/Lee at 2024-01" as composition churn. That framing
is incomplete: under the fixed basket those counties are not lost *at* 2024-01, they are absent
from the whole FL series. The fixed basket is doing its job — there is no within-series
discontinuity — but the resulting series is far narrower than "Partial" suggests.

## Worst states by basket share of FEED renters

(Feed renters, not state renters — the feed has no denominator for counties it omits. Run with
`ACS=TRUE` for true state shares.)

| State | Basket / feed / state counties | % of feed renters | Largest county missing | Treated? |
|---|---|---:|---|---|
| ID | 1 / 43 / 44 | 5.4% | Ada (Boise), excluded | never-legalizer |
| **FL** | **6 / 42 / 67** | **45.3%** | **Miami-Dade, excluded; Broward, Orange, Palm Beach never in feed** | **Dec 2023** |
| **TX** | **8 / 13 / 254** | **48.3%** | **Harris, excluded; Dallas and Bexar never in feed** | never-legalizer |
| TN | 3 / 37 / 95 | 54.3% | Rutherford, excluded (Shelby/Davidson/Hamilton are in) | Nov 2020 |
| WV | 25 / 55 / 55 | 60.1% | Kanawha (Charleston), excluded | Aug 2018 |
| AR | 12 / 75 / 75 | 60.7% | Sebastian (Pulaski is in) | Jul 2019 |
| GA | 2 / 3 / 159 | 67.7% | everything but Clayton + Columbia | never-legalizer |
| MT | 6 / 35 / 56 | 72.7% | Silver Bow — all six metros are in, fine | Mar 2020 |
| CO | 15 / 62 / 64 | 87.7% | **Denver, absent from feed** | May 2020 |
| VA | 87 / 124 / 134 | 95.9% | 10 absent are all small independent cities — fine | Jan 2021 |

Below CO the pattern is benign: KY, MN, UT, WI, CT, IN, PA, NY, SC all keep their largest
renter county and the excluded ones are small.

## The QA gate does not catch any of this

`data/processed/state_panel_coverage_qa.csv` marks **FL, TX, TN, GA, ID, WV and CO all
`composition_risk = ok`, `min_basket_share = 1`, 0 months below 90%.** That is correct on its own
terms — the gate measures whether a basket is *stable over time*, which is the artifact it was
built to catch. It says nothing about whether the basket *represents the state*. Those are two
different questions and only the first one is currently gated.

## What actually matters for the design

**FL is the one to worry about**: a treated switcher (Dec 2023) whose series is Tampa,
Jacksonville, St. Pete, Brevard, Manatee and Lake — no Miami, no Orlando, no Fort Lauderdale —
and whose two biggest counties leave the feed in the same month treatment begins. TX, GA and ID
are never-legalizers, so their narrowness costs control-pool representativeness, not identification.
ID is already in `exclude_states` for every spec. TN and WV are treated but their basket keeps the
principal metros.

## Open

- Run `CENSUS_API_KEY=... ACS=TRUE Rscript analysis/diagnostics/missing_major_county_audit.R`
  to replace "% of feed renters" with the true share of each state's renter households, and to
  rank the absent-from-feed counties by size.
- Decide whether `docs/STATE_SOURCES.md` should carry a renter-share column and name the largest
  missing county per state. It currently reports "6 of 67" for FL without naming Miami-Dade.
