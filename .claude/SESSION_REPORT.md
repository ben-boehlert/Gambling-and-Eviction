
## 2026-07-23 13:57 — Repair Maine panel series from Maine Judicial Branch court source

**Operations:**
- Downloaded MEJIS "15-Year Monthly FED Filing Trends" (fed-monthly15yr-report.pdf, 12 pages, county×month×year 2012–2026)
- Parsed to data/raw/monthly_expansion/me_fed_county_month_year.csv (2880 rows) and me_fed_state_month_courtsource.csv (120 state-months, 2016–2025); county sums reconcile to printed statewide on all 180 cells
- data_prep/monthly_panel_expansion/07_repair_me_from_court_source.R — full-replace repair of ME in state_month_panel_with_treatment.csv
- Backup: data/raw/deprecated/state_month_panel_with_treatment_pre_me_repair_2026-07-23.csv

**Decisions:**
- Full replace (not NH-style splice) — ME court source diverges from ETS panel on 62/89 overlap months (mean|diff| 49.8, max 348, corr 0.698); splicing would seam two vintages. User approved full replace 2026-07-23.
- ME range 2016-01→2025-11 (panel envelope), never-treated control throughout.

**Results:**
- ME artifact identified: ETS recorded 2023-06..2023-12 as literal zeros (same defect as NH)
- ME: 96 → 119 months, 7 fabricated zeros removed, 23 months added (through 2025-11), 0 zeros, 0 NA
- Non-ME states untouched (only last-digit float re-serialization); 39 states, 0 duplicate keys

**Status:**
- Done: Maine data repaired + verified
- Pending: remove ME from EXCLUDE_STATES and re-run power sim / pretrends (intentionally not re-run, mirroring NH); commit

## 2026-07-23 14:14 — Include repaired Maine: county files, re-run power + pretrends

**Operations:**
- data_prep/monthly_panel_expansion/08_repair_me_in_county_files.R — propagated ME court source into combined_monthly_panel.csv and monthly_county_data_download.csv (ME 1536→1904 county rows each, 2016-01→2025-11); backups in data/raw/deprecated/
- Removed ME from EXCLUDE_STATES: scripts/run_pretrends_statepanel.sh, analysis/pretrends/pretrends_statepanel_template.R (default ME→""); new scripts/run_twfe_power_2024_with_me.sh
- Re-ran pretrends (output/pretrends_statepanel_me_included) and TWFE power sim (data/output/twfe_power_out_2024_with_me)

**Results:**
- Pretrends with ME: 26 states (was 24), parallel trends NOT rejected (CS Holm p=1); Sun-Abraham NO LONGER rejects (Holm p=0.357) post NH+ME repair; overall ATT +0.011 (SE 0.16), n.s.
- Power sim with ME: 38-state raw panel; MDE unchanged — power 0.828 at 5% (vs 0.835 without ME), Type I 0.065
- ME confirmed purely additive to balanced set (25→26 states; nothing dropped)

**Decisions:**
- County-level repair (not state-level substitution) to preserve combined_monthly_panel structure for all its consumers
- CS calibration (cs_calibration_multi_estimator.R) left with hardcoded ME exclusion — not in re-run scope

**Status:**
- Done: ME repaired across all 3 panel files, re-run, CLAUDE.md updated
- Pending: optionally re-run CS calibration with ME; patch pre-existing output/pretrends_statepanel_template if desired
