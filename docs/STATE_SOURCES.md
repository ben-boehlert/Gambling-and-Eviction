# State Sources — who collected it, and how much of the state it is

**Created:** 2026-09-03. **Refreshed 2026-09-14** (single-series rebuild, Oregon add, WA/MI add,
trailing-partial censor). Companion to [DATA_PROVENANCE.md](DATA_PROVENANCE.md), which covers
files; this one covers **states**. Source of truth for the rows below:
`data/raw/state_month_panel_with_treatment.csv`.

Three provider families supply the 42 states:

- **LSC CCDI** (29 states) — Legal Services Corporation Civil Court Data Initiative,
  `civilcourtdata.lsc.gov`. **Not** the Eviction Tracking System; see DATA_PROVENANCE.md §1.
- **Eviction Lab** (7 states: LA MA MO NM NV RI WA) — internal county-month extract. These carried
  no denominator until 2026-09-14; `data_prep/fetch_acs_renter_denominators.R` now fills each one
  from ACS B25003_003 **at the geography the numerator actually covers**, not statewide.
- **State courts and court-derived dashboards** (6 states) — MD Judiciary, NH Judicial Branch,
  WI Dept. of Administration, MI Courts Judicial Data Warehouse, Idaho Judicial Branch, and
  OR Judicial Department + Evicted in Oregon (PSU).

**How to read Scope.** `Statewide` = every county in the state. `Partial` = a fixed basket of
counties. `Metro only`, `One county`, `One city` = the series is a metro area wearing a state
label. County counts alone mislead in both directions — Arizona's 2 counties hold 746k renters
(Phoenix + Tucson, most of the state), while Georgia's 2 hold 61k and **exclude Fulton and
DeKalb**, i.e. Atlanta proper. Read the county count and the renter column together.

| State | Provider | Scope | What the series actually covers | Months | Window | Renters covered |
|---|---|---|---|---|---|---|
| **AK** | LSC CCDI | Partial | Anchorage, Fairbanks North Star, Matanuska-Susitna, Kenai Peninsula, Juneau — 5 of 29 | 116 | 2016-01–2025-09 | 72k |
| **AR** | LSC CCDI | Partial | 12 counties, largest: Pulaski, Washington, Benton, Faulkner, … — 12 of 75 | 114 | 2016-01–2025-09 | 245k |
| **AZ** | LSC CCDI | **Metro only** | Maricopa, Pima — 2 of 15 | 110 | 2016-01–2025-02 | 746k |
| **CO** | LSC CCDI | Partial | 15 counties, largest: El Paso, Arapahoe, Jefferson, Adams, … — 15 of 64 | 57 | 2019-01–2023-11 | 540k |
| **CT** | LSC CCDI | Partial | New Haven, Hartford, Fairfield, New London, Middlesex, Tolland — 6 of 8 | 113 | 2016-01–2025-07 | 440k |
| **DE** | LSC CCDI | Statewide | New Castle, Kent, Sussex — 3 of 3 | 115 | 2016-01–2025-09 | 110k |
| **FL** | LSC CCDI | Partial | Hillsborough, Duval, Pinellas, Brevard, Manatee, Lake — 6 of 67 | 112 | 2016-01–2025-04 | 659k |
| **GA** | LSC CCDI | **Metro only** | Clayton, Columbia — 2 of 159 | 112 | 2016-01–2025-04 | 61k |
| **HI** | LSC CCDI | Partial | Honolulu, Hawaii, Maui, Kauai — 4 of 5 | 33 | 2020-01–2022-09 | 183k |
| **ID** | Idaho Judicial Branch | Statewide | All 44 counties, A12 Unlawful Detainer/Eviction filings from the ID courts dashboard. **Replaced the Twin Falls LSC basket on 2026-09-14** (`data_prep/add_id_to_state_panel.R`) — a deliberate scope change AND shortening: the dashboard is a rolling five-year window, so pre-2021 is not available and was not spliced on. Twin Falls series preserved at `data/raw/deprecated/id_twin_falls_lsc_series_pre_2026-09-14.csv`. | 66 | 2021-01–2026-06 | 199k |
| **IN** | LSC CCDI | Partial | 59 counties, largest: Marion, Lake, Allen, Tippecanoe, … — 59 of 92 | 113 | 2016-01–2025-09 | 742k |
| **KS** | LSC CCDI | **One county** | Johnson — 1 of 105 | 110 | 2016-01–2025-02 | 77k |
| **KY** | LSC CCDI | Partial | 45 counties, largest: Jefferson, Fayette, Warren, Kenton, … — 45 of 120 | 110 | 2016-01–2025-09 | 463k |
| **LA** | Eviction Lab | **One city** | New Orleans only (Orleans Parish; First + Second City Court). Labelled `louisiana`, source tag `cities_aggregated`. | 84 | 2019-01–2026-02 | 76k |
| **MA** | Eviction Lab | **One city** | Boston only (Suffolk County). Labelled `massachusetts`, source tag `cities_aggregated`. | 77 | 2020-01–2026-05 | 208k |
| **MD** | MD Judiciary | Statewide | District Court of Maryland monthly Landlord/Tenant **complaint** filings, parsed from Judiciary annual statistics PDFs. | 174 | 2012-01–2026-06 | 730k |
| **ME** | LSC CCDI | Statewide | 16 counties, largest: Cumberland, York, Penobscot, Androscoggin, … — 16 of 16 | 119 | 2016-01–2025-11 | 153k |
| **MI** | MI Courts (JDW) | Statewide | Statewide monthly Landlord/Tenant new filings from the Judicial Data Warehouse PDF, **minus six jurisdictions** the report excludes (Berrien Co., Grand Rapids, Dearborn Hts, Center Line & Warren, N. Macomb Co., Grandville & Walker) — ~94% of the county dashboard's footprint, so the statewide denominator understates the rate ~6%. 21 interior gaps from 2023-02 (unlabelled bars in the source). | 68 | 2019-01–2026-05 | 1,092k |
| **MN** | LSC CCDI | Partial | 22 counties, largest: Hennepin, Ramsey, Dakota, Anoka, … — 22 of 87 | 100 | 2016-01–2025-09 | 519k |
| **MO** | Eviction Lab | Partial | Fixed basket from 2020-01, 29 of 115 counties — `basket_share` **0.34**, the thinnest in the panel. Scope changed from statewide to a basket in the 2026-09-14 rebuild; MO **levels are not statewide**. | 77 | 2020-01–2026-05 | 364k |
| **MS** | LSC CCDI | **One county** | Desoto — 1 of 82 | 99 | 2016-01–2024-03 | 15k |
| **MT** | LSC CCDI | Partial | Yellowstone, Missoula, Gallatin, Flathead, Cascade, Lewis And Clark — 6 of 56 | 116 | 2016-01–2025-09 | 92k |
| **NC** | LSC CCDI | Statewide | 100 counties, largest: Mecklenburg, Wake, Guilford, Durham, … — 100 of 100 | 126 | 2016-01–2026-06 | 1,408k |
| **ND** | LSC CCDI | Partial | Cass, Grand Forks, Burleigh, Ward, Williams, Stark — 6 of 53 | 113 | 2016-01–2025-05 | 88k |
| **NH** | NH Judicial Branch | Statewide | NH Judicial Branch monthly Landlord/Tenant **writ** filings. | 83 | 2019-01–2025-11 | 152k |
| **NM** | Eviction Lab | Partial | Fixed basket from 2020-01, 14 of 33 counties — `basket_share` **0.48**. Scope changed from statewide to a basket in the 2026-09-14 rebuild; NM **levels are not statewide**. | 77 | 2020-01–2026-05 | 222k |
| **NV** | Eviction Lab | **One city** | Las Vegas only (Clark County: Las Vegas, North Las Vegas, Henderson township courts). Labelled `nevada`, source tag `cities_aggregated`. NV is always-treated — excluded from control pools regardless. | 125 | 2016-01–2026-05 | 364k |
| **NY** | LSC CCDI | Partial | 53 counties, largest: Kings, New York, Queens, Bronx, … — 53 of 62 | 68 | 2019-01–2025-09 | 3,479k |
| **OH** | LSC CCDI | Partial | Cuyahoga, Hamilton, Summit, Lucas — 4 of 88 | 114 | 2016-01–2025-06 | 516k |
| **OK** | LSC CCDI | Partial | 33 counties, largest: Oklahoma, Tulsa, Cleveland, Comanche, … — 33 of 77 | 113 | 2016-01–2025-09 | 468k |
| **OR** | OR Judicial Dept + Evicted in Oregon | Statewide | OJD "Cases Filed" PDFs through 2019-12, then the Evicted in Oregon dashboard (Lisa Bates, PSU). Circuit courts only — justice-court filings in 13 counties are absent. The dashboard is **mutable**; the publisher revised it in Apr 2026. | 103 | 2018-01–2026-07 | 630k |
| **PA** | LSC CCDI | Partial | 58 counties, largest: Philadelphia, Allegheny, Montgomery, Delaware, … — 58 of 67 | 110 | 2016-01–2025-09 | 1,589k |
| **RI** | Eviction Lab | Statewide | Internal county extract, 4 of 5 RI counties reporting in every month (`basket_share` 1). | 130 | 2015-06–2026-05 | 149k |
| **SC** | LSC CCDI | Partial | 45 counties, largest: Greenville, Richland, Charleston, Horry, … — 45 of 46 | 85 | 2018-08–2025-09 | 591k |
| **TN** | LSC CCDI | **Metro only** | Shelby, Davidson, Hamilton — 3 of 95 | 117 | 2016-01–2025-09 | 364k |
| **TX** | LSC CCDI | Partial | 8 counties, largest: Tarrant, Travis, Williamson, Fort Bend, … — 8 of 254 | 117 | 2016-01–2025-09 | 825k |
| **UT** | LSC CCDI | Partial | Salt Lake, Utah, Davis, Weber, Washington, Tooele — 6 of 29 | 117 | 2016-01–2025-09 | 272k |
| **VA** | LSC CCDI | Partial | 87 counties, largest: Fairfax, Arlington, Virginia Beach City, Richmond City, … — 87 of 134 | 102 | 2016-01–2025-09 | 1,024k |
| **VT** | LSC CCDI | Partial | 9 counties, largest: Chittenden, Rutland, Washington, Windsor, … — 9 of 14 | 105 | 2016-01–2025-09 | 65k |
| **WA** | Eviction Lab | **One county** | Tacoma only (Pierce County, 53053) — the extract's sole WA site. WA **levels are not statewide**; the denominator is Pierce County renters. No online launch, so WA is a never-treated control under the headline definition. | 113 | 2017-01–2026-05 | 124k |
| **WI** | WI Dept. of Administration | Statewide | WI DOA Eviction Data Project county-month filings (CCAP/WCCA), all counties. | 81 | 2019-01–2025-10 | 777k |
| **WV** | LSC CCDI | Partial | 25 counties, largest: Monongalia, Cabell, Berkeley, Wood, … — 25 of 55 | 112 | 2016-01–2025-08 | 111k |

---

## The ones to watch

**Labelled a state, actually one city.** LA is New Orleans, MA is Boston, NV is Las Vegas.
All three come from the Eviction Lab `cities_aggregated` series, which carries a state name in
`location_std` while covering a single metro. Nothing in the panel row says so — the state
abbreviation is all you see. NV is excluded anyway as always-treated; LA and MA are not.

**Labelled a state, actually one county.** KS is Johnson County. MS is Desoto County. These
are LSC states where only one county reports in every month, so the fixed-basket rule reduces the
"state" to it. (ID used to be on this list as Twin Falls, 10k renters, 1 of 44 counties; since
2026-09-14 it is the statewide Idaho Judicial Branch series, 2021-01 onward — see the table.)
**WA joins this list from a different direction** — the Eviction Lab extract's only WA site is
Tacoma, so WA is Pierce County (124k renters, 1 of 39).

**Thin metro baskets.** GA (Clayton + Columbia, 61k renters, no Atlanta core) and TN
(Davidson, Hamilton, Shelby) and OH (Cuyahoga, Hamilton, Lucas, Summit) are all small-basket
states where a state-level interpretation is a stretch.

**Short windows.** HI has 33 months, CO 57 (ends 2023-11), NY 68 (starts 2019-01),
MI 68 of a 89-month span, MO and NM 77 each (start 2020-01), MA 77 (starts 2020-01).

**Interior gaps.** MI is the only state with a substantial gap field — 21 of its 89 calendar
months are unrecoverable from the source PDF, all from 2023-02 onward, longest run 8 months. MI
is complete 2019-01 → 2023-01. CS-DiD consecutive-indexes months and will not accept the gapped
span; LP-DiD tolerates it. The other gaps in the panel are single months (KY, MN, VA ×2, WI, WV).

**Trailing partial months, censored 2026-09-14.** The Eviction Lab extract cuts each site at its
own collection date, leaving a partial final month. LA 2026-03 (0.31 of its prior-6 median), MA
2026-06 (0.53), MO 2026-06 (0.26), NM 2026-06 (0.16) and WA 2026-06 (0.38) were dropped by
`data_prep/censor_trailing_partial_months.R`. Re-check this after every extract refresh.

**Known cross-source conflict.** CT's LSC series runs ~23–25% below Connecticut's own
published summary process counts, with a wedge that moves across the treatment window.
See DATA_PROVENANCE.md §4 before using CT.

---

## How the basket was determined

For the 30 LSC states, a county enters its state's basket if it reports in **every month that
state reports at all** within 2016-01 → 2024-12, excluding the COVID drop 2020-03 → 2021-07
(`data_prep/rebuild_state_month_panel.R`, lines 122–147). A state-month is emitted only when
the whole basket reports. This rule was re-derived independently on 2026-09-03 and reproduces
the panel's `n_counties` exactly for all 30 states.

County names and renter counts come from `monthly_county_data_download.csv`; state county
totals from `data/raw/county_adjacency_census.txt` (Census adjacency file). Counties are
listed largest-renter-first.

Rebuild this table after any panel rebuild. The Months / Window / Renters columns are derived
straight from the panel; Provider, Scope and the description column are hand-maintained — there is
no generator script, so they drift unless edited deliberately. Last reconciled 2026-09-14.
