# 2026-09-17 — Maine's COURT-SOURCE parse is shifted a year; repaired from LSC, and ME leaves the switcher set

**Status:** repaired. County download and state panel rebuilt. Switcher set 9 → 8. Vintage boundary 10 in RUN_LEDGER.md.

## CORRECTION (same day, after the first write-up)

The first version of this memo blamed **LSC**. That was wrong, and the correction matters because it
changes where the bug is and how to fix it.

The displaced Maine series is `data/raw/monthly_expansion/me_fed_state_month_courtsource.csv` — the
**Maine Judicial Branch** 15-Year Monthly FED Filing Trends parse. The repo's ME rows matched that
file on **119 of 119 months (100%)**; they were never an LSC vintage at all. They entered via
`07_repair_me_from_court_source.R` on 2026-07-23, which replaced Maine's series wholesale and
carried `panel_source = county_download_fixed_basket` only because the values were merged into the
county file.

**The displacement is almost certainly a fiscal-year mislabel.** Maine's judicial fiscal year runs
1 July – 30 June, so FY *YYYY* spans Jul *YYYY−1* through Jun *YYYY*. A parser that writes the FY
label as the calendar year displaces exactly July–December by twelve months. The evidence matches
that signature precisely: court[Jun–Dec of YYYY] equals live LSC[Jun–Dec of YYYY−1] (6/7, 7/7, 7/7,
7/7 for 2017–2020, degrading to 3–4 of 7 for 2021–2023 as LSC's own small revisions accumulate),
while **January–May never matches the lagged LSC — 0 of 40.**

The 2026-07-23 script's own header recorded the divergence and explained it away: the two sources
"agree on early-in-year months but diverge (by up to ~200 filings) on later months, because the ETS
pull captured a staler MEJIS snapshot." Agreeing early in the year and diverging later is the
fiscal-year signature, not staleness.

**Consequence not yet addressed:** ME's 2024-01..2025-11 tail, which this repair KEPT, comes from
the same parse. Its June–December months are therefore likely displaced too, which also means the
"missing" 2023-06..12 values may simply be sitting in the panel mislabelled as 2024-06..12. The real
fix is to re-parse `fed-monthly15yr-report.pdf` with the correct fiscal-year mapping, not to patch
month ranges. Open for Ben.

## The corruption as originally observed

`data/raw/monthly_county_data_download.csv` carried a Maine series in which **June through December of every year from 2016 to 2023 held the PREVIOUS year's values.**

| Calendar month | Months comparable to the live LSC file | Matching |
|---|---|---|
| Jan–May | 40 | 27 |
| **Jun–Dec** | **49** | **0** |

Not one Jun–Dec month in any year matched. They matched the live file at a **12-month lag** instead, exactly, in 37 verified month-pairs: repo 2017-06 = LSC 2016-06 = 543, repo 2018-06 = LSC 2017-06 = 588, and so on.

The symptom that makes it unmistakable is the moratorium. The repo showed Maine with **no COVID suppression at all** — 2020-06/07/08 read 424 / 502 / 546, which are 2019's figures — and then a moratorium-shaped collapse a year late at 2021-06/07/08 = 76 / 175 / 221, which are 2020's actual figures.

| Month | Repo (corrupt) | Live LSC |
|---|---|---|
| 2020-06 | 424 | 76 |
| 2020-07 | 502 | 175 |
| 2020-08 | 546 | 221 |
| 2021-06 | 76 | 371 |
| 2021-07 | 175 | 325 |

**Maine was the only state affected.** Across all 94,167 county-months both vintages cover, every other state is 100% identical; Maine was 47% — because Maine's rows had been overwritten with the court parse and no other state's had.

## The exclusion that caught it, and did not say so

`.read_state_panel()` in `R/power/load_blinded_panel.R` has carried a bare `filter(state_abb != "ME")` since the framework's first commit (`12725a5`, 2026-08-03), with no comment. It was **right** — but because the reason was never recorded, it read as arbitrary, and on 2026-09-17 it was nearly removed on the argument that ME's data looked fine. The ledger's boundary-1 note ("before this, ME is excluded or carries a zero-fill artifact") was pointing at this and was not connected to the filter.

The filter is now heavily commented and **deliberately left in place**: removing it takes the blinded panel 39 → 40 states, a vintage boundary for every power run, which should be a deliberate decision rather than a side effect of a data repair. ME's untreated window (2016-01..2023-04) is now correct and usable whenever that decision is taken.

## The repair

From the live 2026-09-17 LSC download:

| ME range | Action | Why |
|---|---|---|
| 2016-01..2023-05 | **Replaced** with live LSC | 89/89 months now match LSC exactly; the moratorium is visible (2020-04 = 62, 2020-05 = 49, 2020-06 = 76) |
| 2023-06..2023-12 | **Dropped** (112 county-rows) | LSC publishes zeros there and the repo values were the corrupted prior-year figures — neither is usable |
| 2024-01..2025-11 | **Kept** | Maine Judicial Branch FED, a separate source, untouched |

Every non-ME row is byte-identical to the pre-repair file (verified). County download 124,325 → 124,213 rows. State panel 4,294 → **4,287 rows, 42 states**; ME now spans 2016-01..2025-11 with a seven-month interior gap at 2023-06..2023-12.

Pre-repair copies: `data/raw/deprecated/monthly_county_data_download_pre_me_repair_2026-09-17.csv`, `data/raw/deprecated/state_month_panel_with_treatment_pre_me_repair_2026-09-17.csv`.

## Consequence: ME leaves the switcher set

ME launched 2023-11, so its inclusion-rule baseline is [2023-05, 2023-10] — five of those six months are now the gap. `baseline_ok` is FALSE and ME fails the rule on the data, not on a judgement call.

**Switcher set 9 → 8: KS MA MD NC OH KY VT DE.** Pooled placebo SE 0.0443 → **0.0483**, the honest cost of a lost cluster.

One thing improves: ME was the single switcher absent from the framework panel, so the D1 template was 8 cohorts against a 9-switcher real design. The simulated and real designs now match exactly at 8.

## Final state: Maine is LSC-only

Per Ben (2026-09-17), Maine's series is now **entirely LSC**: the court-parse tail (2024-01..2025-11,
368 county-rows) was dropped along with the 2023-06..12 gap. ME is **89 clean months,
2016-01..2023-05, no interior gaps**, matching the live LSC download exactly.

Nothing analytical is lost. ME launched 2023-11, so the discarded months are all post-launch, and
under the inclusion rule a launched state that fails the rule is dirty — never a switcher (ME's
baseline is unavailable) and never a control (controls must remain unlaunched). ME's entire
*untreated* window, 2016-01..2023-04, is covered by LSC with no gap.

County file 124,213 → **123,845 rows**; state panel 4,287 → **4,264 rows, 42 states**. Switcher set
unchanged at 8 and pooled placebo SE unchanged at 0.0483 — ME had already left the set.

Pre-change copies: `data/raw/deprecated/monthly_county_data_download_pre_me_lsconly_2026-09-17.csv`,
`data/raw/deprecated/state_month_panel_with_treatment_pre_me_lsconly_2026-09-17.csv`.

**Open, and now the only thing blocking it is a decision:** the loader's `filter(state_abb != "ME")`
is no longer justified by anything. ME would contribute **88 untreated months (71 after the COVID
drop, 50 of them pre-COVID)**, all with denominators. Removing it takes the blinded panel 39 → 40
states — a vintage boundary for every power run, which is why it has not been done as a side effect.
Those 50 pre-COVID months land exactly where option A wants to place the template.

## Standing caution

A key-level comparison cannot detect this class of error. The 2026-09-14 provenance correction compared the local and live county files **by key** and concluded the live file was a strict subset — true, and it masked the fact that 53% of Maine's shared keys carried different values. Compare values, not just keys.
