# 2026-09-17 — Value censor (UT, CO) and the hybrid-provenance relabel

**Status:** implemented; panel rebuilt to 42 states / **4,294 rows**. Vintage boundary 9 in RUN_LEDGER.md.

## 1. What started it

A blind-safe placebo diagnostic (`analysis/diagnostics/covid_window_variance_profile.R`) reported
North Carolina as by far the noisiest switcher under the K=7 inclusion rule: cross-control SD of the
long difference 0.329 against a set median of 0.151, and above the marginal-cluster break-even
threshold (0.311), i.e. NC was *degrading* the design's precision rather than adding to it.

It was not NC. It was one of NC's five controls.

## 2. UT 2023-11 and 2023-12 — a collection failure, not evictions

Utah's two months sit inside NC's inclusion-rule baseline window [2023-09, 2024-02].

| | 2023-10 | 2023-11 | 2023-12 | 2024-01 |
|---|---|---|---|---|
| Salt Lake filings | 413 | 24 | 47 | 432 |
| Reporting counties | 18 | 9 | 7 | 20 |
| Statewide % of LSC historical average | 115.0 | **9.1** | **16.2** | 111.1 |

Every Utah county collapses in the same two months and every one recovers. A fresh LSC pull on
2026-09-17 returns identical figures, so this is upstream at LSC, not an ingest bug.

Removing those two months takes NC's placebo long-difference SD from **0.329 to 0.054** — from the
noisiest switcher in the set to the quietest — and the design's pooled SE from **0.0731 to 0.0639**
(−13%), larger than the entire COVID-drop-window question that prompted the diagnostic.

## 3. CO 2023-11 — an uncensored trailing partial

CO's series ends 2023-11 at 12.7% of historical average. DATA_PROVENANCE.md recorded CO as *stale*
at 2023-11 but not that the final month is a fragment, and the 2026-09-14 trailing-partial censor
covered LA/MA/MO/NM only. Censored; CO now ends 2023-10.

## 4. Why nothing caught either

The fixed-basket rule emits a state-month only when **every** basket county reports. UT 2023-11 had
all 6 basket counties present at `basket_share` 1.00 — they simply reported collapsed counts. The
guard checks that counties REPORT, never that what they report is credible.

LSC ships `percent_of_historical_average`, its own plausibility measure, and every panel build
before today dropped the column at ingest. The evidence was in the source file the whole time.

**Fix:** `lsc_pct_of_hist_avg` (state filings over summed county historical averages — not a mean of
county percentages, which would weight a 1-filing county like Salt Lake) and `lsc_pct_coverage` are
now carried into the panel. `data/processed/state_panel_plausibility_flags.csv` lists uncensored
months below 40%. It currently flags VA 2022-01/02 and NY 2022-01 — genuine post-moratorium
recovery, deliberately **flagged and not censored**. Censoring stays a named, arguable decision in
`VALUE_CENSOR`; the QA block only surfaces candidates.

## 5. The provenance relabel — the recurring error

While diagnosing the above, a fresh LSC download (`monthly_county_data_download 9_17.csv`,
120,357 rows, max date 2025-09) was compared against the local file (124,325 rows, max 2026-06) and
the difference was read as **LSC retracting North Carolina and Maine**. It is not. The local file is
a **hybrid**: all 3,968 local-only keys are NC (3,600) and ME (368), merged in from court sources.
LSC's own NC series has always ended 2023-06 and its ME series 2023-12.

This was already documented — DATA_PROVENANCE.md §1 carries a 2026-09-14 correction stating it
explicitly, including "Re-downloading this file is destructive, not a refresh." It has still been
misread more than once.

**Proximate cause: the data asserted the wrong provenance.** NC and ME rows arrived through
`county_part` and inherited `panel_source = county_download_fixed_basket`, which the source table
maps to "LSC CCDI". The 2026-09-14 correction flagged the label as wrong but did not change it.

**Fix (structural, not prose):**
- `HYBRID_SOURCE` in `rebuild_state_month_panel.R` restamps NC 2023-07→ as `nc_aoc_summary_ejectment`
  (36 rows) and ME 2024-01→ as `me_judicial_branch_fed` (23 rows), and nulls their LSC QA columns.
- `CLAUDE.md` carries a blockquote at the panel-data bullet. Its line 82 previously said the file was
  "from the Eviction Tracking System" while line 17 said "LSC CCDI, not ETS" — the file contained
  both the correction and the error it corrected. Both now read correctly.
- `docs/STATE_SOURCES.md` NC and ME rows now name both providers with date ranges.

**Standing rule:** a fresh LSC pull lacking NC 2023-07+ or ME 2024-01+ is the absence of rows LSC
never had. It is never evidence of a retraction, and re-downloading the county file deletes a
switcher's entire outcome window.

## 5b. The plausibility band censor (Ben's decision, same day)

Named censoring does not scale, so the rule was generalised. Ben set two bands — **interior 50–150%, terminal 70–130%** — tighter at a series end because that is empirically where LSC series fail: of 27 LSC states the final month reads AR 194.1, MN 159.3, ND 154.6, TX 145.4, AZ 143.6, CT 62.9, OH 45.0, DE 44.1, against a median final-month reading of 95.4.

**What the bands apply to took three attempts, and the first two were wrong:**

| Baseline | Result |
|---|---|
| Raw LSC percentage | Deletes AR's entire post-2022 series (43 months) and 6 consecutive DE months. AR's median reading is 171, DE's 66 — **level offsets** against LSC's fixed historical baseline, not failures. |
| Same calendar month, all years | Deletes AR in **both** directions (pre-2022 at ~45%, post-2022 at ~160%) because it pools across AR's 2022 level shift. |
| **Local level × seasonal factor** (adopted) | 10 rows, 6 states. AR survives whole; NY's Julys survive. |

The adopted measure is a leave-one-out centred rolling median (±6 months, COVID excluded) multiplied by that calendar month's typical ratio to it in other years. The level half absorbs structural shifts, the seasonal half absorbs recurring months, and what fails both is a genuine local discontinuity. A rolling baseline alone flagged NY every July for four years (relative readings 192/177/194/218); NY simply files more in July. Months too sparse to judge get NA and are never censored.

**The band width also had to become breadth-aware.** A single band ignores how noisy a series structurally is. Per-state robust dispersion of the relative measure runs from 4.1 (PA, 58 counties) to 17.0 (MS, ONE county) — so a fixed ±50 band is about 3 state-sigmas in Mississippi and 12 in Pennsylvania. Eight of the ten months the fixed band removed were thin-basket states (MS 1 county, GA 2, DE 3, OH 4, CT 6), where a large deviation is expected rather than evidence of failure. The band is now **K times each state's own robust dispersion**, K = 7.0 interior and 4.2 terminal, chosen so that at median dispersion (s = 6.67) they reproduce Ben's 50–150% and 70–130% almost exactly. Dispersion is computed once on the uncensored panel — recomputing it inside the loop would shrink s as outliers are removed and the rule would ratchet — and clamped to [4, 15].

**The COVID exemption had to extend to 2022-06.** With the window closing 2021-12, the breadth-aware band flagged CT 2022-01/02, TX 2022-01/03, VA 2022-01/02/05, NY 2022-01, GA 2022-02, MN 2022-01/02 and NC 2022-01 — eleven states moving together in one direction in the same two quarters. That is a moratorium unwind, not eleven simultaneous collection failures, and the repo's own older specs used a 2022-03 COVID boundary for the same reason.

**Removed (7):** CO 2023-10 (z +4.24, terminal — CO's new series end once 2023-11 was censored by name; the tail degrades over two months); CT 2025-07 (−6.59); DE 2025-09 (−4.29); GA 2023-05 (−7.88); MN 2024-01 (−8.69); **MN 2025-09 (+11.17 — the trailing jump, 11 state-sigmas against Minnesota's own spread)**; OH 2025-06 (−6.36, Hamilton County's terminal fragment at 61 filings against ~1,050, which ends OH's series because the 4-county basket needs Hamilton while Cuyahoga and Lucas run on to 2025-09).

**Spared, correctly:** MS 2019-07 and 2022-07 (z ≈ 2.9 against Mississippi's own dispersion — a one-county series legitimately swings); DE 2025-08 (z −3.9, now on the watch list), which takes DE back to 8 usable outcome months, one clear of K.

**Effect:** switcher set unchanged at 10; pooled placebo SE 0.0731 → **0.0463** across the session. Across COVID windows: 0.0442 / 0.0463 / 0.0443. Note the earlier fixed-band figure of 0.0417 was **partly spurious** — it was bought by censoring genuine post-moratorium months that sit inside AR's baseline window.

**Standing design note (not fixed here):** AR's inclusion-rule baseline is [2021-09, 2022-02], squarely inside the moratorium unwind. The splice buffer excludes 2021-08..10 as *outcome* months for everyone, but the baseline test only requires the months to be observed. AR's is the noisiest long difference in the set (0.222) for that reason.

**Knobs:** `PLAUS_K_INTERIOR` 7.0, `PLAUS_K_TERMINAL` 4.2 (both env-overridable), `PLAUS_S_MIN` 4, `PLAUS_S_MAX` 15, `PLAUS_S_MIN_OBS` 24, `PLAUS_WINDOW` 6, `PLAUS_MIN_NEI` 5, `PLAUS_MIN_YEARS` 3, `PLAUS_MIN_COV` 0.5, COVID exemption 2020-03..2022-06. Output: `data/processed/state_panel_plausibility_censor.csv` (removed, with z and the state's band) and `..._flags.csv` (surviving, near an edge).

## 6. Artifacts

- Panel: `data/raw/state_month_panel_with_treatment.csv` (4,301 rows, 42 states)
- Pre-censor: `data/raw/deprecated/state_month_panel_with_treatment_pre_value_censor_2026-09-17.csv`
- QA: `data/processed/state_panel_plausibility_censor.csv` (what was removed and why), `data/processed/state_panel_plausibility_flags.csv` (surviving, near a band edge)
- Diagnostic: `analysis/diagnostics/covid_window_variance_profile.R`,
  `output/inclusion_rule/covid_window_variance_profile.csv`
- Fresh LSC pulls retained for comparison: `monthly_state_data_download 9_17.csv`,
  `monthly_county_data_download 9_17.csv` (do NOT overwrite the panel source with these)
