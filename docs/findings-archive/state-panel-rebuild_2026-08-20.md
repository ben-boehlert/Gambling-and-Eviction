> Archived verbatim from CLAUDE.md on 2026-08-25 (repo cleanup). Historical record — numbers here may be superseded; current truth lives in FINDINGS.md, statuses in RUN_LEDGER.md.

### STATE PANEL DOUBLE COUNT — REBUILT 2026-08-20 (read before using any pre-rebuild state-level result)

`data/raw/state_month_panel_with_treatment.csv` was, until 2026-08-20, an exact double count
for 12 states: `filings_count = (county download sum) + (merged_ets_combined.csv ETS series)`,
verified to the unit on 891 of 916 overlap state-months (100% for all 12 affected states;
the other 25 are WI, already repaired by 08c and therefore not an exact addition)
(`analysis/diagnostics/statepanel_double_count_audit.R`; outputs in
`output/statepanel_double_count/`). The two sources cover the SAME filings. Because each ETS
series has its own span, the double count switched on/off mid-panel — a 1.2x-2.4x level break
with no eviction content: cities series START 2020-01 (AZ OH SC TN TX -> jump up), state_level
series END 2023-02 (CT DE IN MN PA VA -> drop), FL state series end 2020-01 (drop). No repo
script ever built this file; only the NH/ME/MD/WI patch scripts touched it.

**Rebuild** (`data_prep/rebuild_state_month_panel.R`): one consistent source per state —
county-download sums for all states in the download except NH/WI (court-source repairs kept),
MD carried as Judiciary monthly Landlord/Tenant COMPLAINT filings (NOT the superseded Socrata
post-judgment warrant extract),
NY trimmed to 2019+ (pre-2019 was a different-basket ETS series; NY now fails the 91-month
balance and DROPS from the balanced pretrends panel), MD/LA/MA/MO/NM/NV/RI single-source rows
carried over. `treat_start` recomputed from the repaired schedule. Old panel preserved at
`data/raw/deprecated/state_month_panel_with_treatment_double_counted_2026-08-20.csv`.
Provenance per state: `data/processed/state_panel_rebuild_source_table.csv`.

**Bias mechanism**: constant multiplicative inflation cancels in log outcomes with state FE;
only windows STRADDLING a break (2020-01 or 2023-02) are biased — which includes the standard
2016-2024-excl-COVID window for all 12 states, and the post-COVID window for the 2023-02 six.
This is what made TX (+0.785) and MN (-0.715) long differences fake (county file: -0.493/-0.024)
and inflated the real-calendar sigma 0.592 -> 0.327.

**Contaminated (state-panel-based; re-run before citing):** pretrends headline (re-run 2026-08-20,
see below), state calibration table (CS 14%/SunAb 21% — residual-pool DGP contained the breaks),
blinded-power STATE cells (did2s 23-29% Type I, TWFE-wild MDE>20%, time_agg/splice memo,
LP-DiD spliced-state MDE 8.1% synthesis, longdiff_power, cheap_sims grid),
handle50/post-COVID handle50 outputs (panel regenerated 2026-08-20;
downstream outputs stale), era-variance state-panel sigmas (county fixed-basket numbers stand).
**Immune:** everything county-download-based (county calibration incl. did2s 4%/0.97, county CS
adaptive MDE verdict, border diagnostic, +9.1% did2s headline), mortgage delinquency, 2x2
pseudo-power on the annual court panel, handle maturation stats, **TWFE staggered power sim
(MDE=5% claim)** — this entry was listed as contaminated until 2026-08-20; that was WRONG, see
below.

**TWFE staggered power sim is NOT double-count contaminated (corrected 2026-08-20).**
`analysis/main/power_simulation_twfe_statepanel_staggered_parallel_fixed.R` takes its OUTCOME
from `combined_monthly_panel.csv` via `build_state_panel()`, which aggregates county rows to
state totals and falls back to `geo_level == "state"` rows ONLY for states absent from the
county file (`filter(!(state_abb %in% county_states))`). Verified by replicating the build:
32 states enter by county aggregation; exactly 6 by fallback — LA, MA, MO, NM, NV, RI, which
are the legitimately single-source states. All 12 double-counted states (AZ OH SC TN TX /
CT DE IN MN PA VA / FL) have county rows and are therefore taken from the county path, so
their ETS state series is never added. Zero duplicate state-months.
`state_month_panel_with_treatment.csv` is read only as `TREAT_FILE` and is transmuted down to
`state_abb, month_date, treat_start, treated` — the schedule, never the filing counts.
**Lesson: this entry was added to the contaminated list by pattern-matching the file name, not
by reading the loader. Trace the actual data path before declaring a result contaminated —
same class of error as the 2026-08-10 "reproducibility anomaly."**

**It IS stale, for a different and narrower reason — the treatment schedule.** The saved run
(`data/output/twfe_power_out_2024_with_me/`, 2026-07-23) predates the 2026-08-10 schedule
repair. Its panel is 38 states / 22 switchers / **16 never-treated**, but the repair moved ME,
VT, KY and FL out of the never-treated pool, so the switcher-vs-control composition the power
calculation rests on has changed. Re-run against the repaired schedule before citing the MDE;
there is no known direction of bias, so do not describe the old number as inflated or deflated.

**REBUILT PANEL IS NOT YET ANALYSIS-READY — composition churn is unfixed (Codex review,
2026-08-20).** The rebuild removes the double count but a county-sum state total is still a
COMPOSITION-VARYING basket, and a state-month presence check does not catch it. Verified cases:
FL drops Miami-Dade and Lee at 2024-01 — one month after FL's own 2023-12 treatment date;
TN falls 36 -> 12 -> 3 reporting counties over 2024-03/04; TX loses Harris at 2024-05, cutting
its renter denominator 48%. Measured effect on the 2016-19 -> 2022-24 change in log filings:
artifacts of +1.02 (ID), -0.28 (FL), -0.16 (TX) log points; cross-state SD 0.249 as-reported vs
0.207 on a fixed basket. Every row now carries `n_counties` and `basket_share`, and
`data/processed/state_panel_coverage_qa.csv` grades each state — censor the tail or fix the
basket before any state-level estimate is cited. Also fixed in the same pass: zero renter
denominators were producing FABRICATED rates up to 6,934,000 per 1k renters (404 rows across
LA MA MO NM NV RI); rates are now NA where no denominator exists. The rebuild is idempotent and
the pre-fix panel is preserved once and never overwritten.

**Post-rebuild pretrends headline — PROVISIONAL, do not cite (2026-08-20, `output/pretrends_rebuild_B_newpanel/`):**
25 states (16 treated, 9 never-treated — schedule repair moved ME/VT/KY/FL to treated; NY out),
15 cohorts, 91 months. CS overall ATT **+0.080 log points (SE 0.088 analytic, 0.088 bootstrap)**
— not significant, CI ~[-0.09, +0.25]. Pre-trends NOT rejected (CS Holm p = 1.0; SunAb p = 1.0).
Vs the old panel run at the same schedule (`output/pretrends_rebuild_A_oldpanel/`: ATT +0.074,
SE 0.130): the fix leaves the point estimate nearly unchanged and cuts the CS SE by ~1/3;
mean |pre-ATT| halves (0.047 -> 0.029). The pre-rebuild published numbers (ATT +0.011, SE 0.163,
26 states 12 treated) are dead — they mixed the double count with the stale schedule.


