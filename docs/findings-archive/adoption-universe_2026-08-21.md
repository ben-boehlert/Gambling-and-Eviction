> Archived verbatim from CLAUDE.md on 2026-08-25 (repo cleanup). Historical record — numbers here may be superseded; current truth lives in FINDINGS.md, statuses in RUN_LEDGER.md.

### ADOPTION UNIVERSE: absent-row trap + Nevada (2026-08-21)

Full audit: `docs/methodology/ADOPTION_UNIVERSE_AUDIT.md`. Canonical helpers at the
bottom of `utils/eviction_treatment_schedule.R` (della copy kept identical):
`EVICTION_STATE_UNIVERSE`, `PRE_PASPA_SPORTS_BETTING`, `eviction_adoption_outcomes()`,
`eviction_control_states()`, `assert_no_pre_paspa_controls()`. Use them; do not
re-derive the universe or the NV rule in a script.

**Trap 1 — absent rows.** `sports_gambling_legalization_dates.csv` has a row ONLY for
states that legalized something; never-legalizers are ABSENT, not NA. So
`inner_join(features, schedule)` and `schedule %>% pull(state_abb)` silently delete
13 states: AL AK CA GA HI ID MN NE NV OK SC TX UT. `setdiff(panel_states, ever)` and
`%in% ever_online` are SAFE because the universe comes from the panel. Scan of 81
first-party scripts: the trap was live in exactly one place,
`analysis/diagnostics/adoption_selection_levels_slopes.R` (fixed; substrate A 29 → 41
states, and the adopter-never level gap fell +0.64 → +0.24 log points as a result).
`R/power/load_blinded_panel.R:262-264` already documented and avoided it.

**Trap 2 — Nevada is always-treated, not never-treated.** Legal sports betting since
1949; absent from the schedule because there was no post-PASPA event to record. DE/OR/MT
carry explicit post-2018 dates and are NOT part of this exception.

**NV-affected (re-run before citing):** 2x2 pseudo-power MDE-80 = 0.241 (+27%) and its
size/Type-M tables (`output/longdiff_2x2_pseudo/`); the 2x2 selection placebo
(tau = -1.4%, RI p = 0.90) — NV sits in its 17-state "never" arm, which is the arm the
test is about; era-variance ratios, especially the strict-never-set 3.86, where NV is
both a member and the flagged `outlier_state`; state-level blinded-power cells
(`attr(panel,"never_treated")` contains NV — a second reason on top of the double count).
`analysis/cheap_sims/11_exposure_time_vs_intensity.R` already drops NV but ad hoc via an
inline `state_abb != "NV"`; migrate it to the shared constant.

**NV-immune (verified, not assumed):** everything on the county download — NV is not in
`monthly_county_data_download.csv` at all (county calibration, border diagnostic, +9.1%
did2s headline, county blinded-power cells, `longdiff_real_calendar_decomp.R`); and every
balanced-panel result — NV has 46 non-COVID months against a 91-month balance threshold,
so it drops before estimation (pretrends headline, CS/SunAb calibration).

