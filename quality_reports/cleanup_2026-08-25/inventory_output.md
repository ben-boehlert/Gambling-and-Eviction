# Inventory of `output/` — 2026-08-25

89 entries classified (85 directories + 4 loose files at `output/` root; `.DS_Store` excluded).

## Counts by status

| Status | Count |
|---|---|
| LIVE | 19 |
| SUPERSEDED | 19 |
| CONTAMINATED | 15 |
| DEAD | 14 |
| EXPLORATORY | 14 |
| UNKNOWN | 8 |
| **Total** | **89** |

`move? = yes`: 48 entries (all SUPERSEDED + CONTAMINATED + DEAD). LIVE (19), EXPLORATORY (14), and UNKNOWN (8) = 41 entries never move.

## Methodology / heuristics applied

Root CLAUDE.md documents five hard boundary dates that gate contamination. Rather than re-deriving these per file, every state-panel-based output is checked against them mechanically:

1. **2026-07-23** — NH + ME court-source repairs (before this, ME is excluded or carries a zero-fill artifact).
2. **2026-08-10** — treatment-schedule repair (ME/VT/KY/FL/DE/NC/MO online dates added; before this, any output using the schedule mis-classifies those states).
3. **2026-08-20 ~01:26** — state-panel rebuild that fixed the 12-state double count in `state_month_panel_with_treatment.csv`. Any output reading that file with a *generation timestamp before this* is **CONTAMINATED (double-count panel)** per CLAUDE.md's explicit "STATE PANEL DOUBLE COUNT" section — regardless of which window it uses, since the section documents no exception.
4. **2026-08-21 ~10-15h** — NV audit / loader fix (`PRE_PASPA_SPORTS_BETTING` exclusion). State-level power/pretrends cells generated before this on the D1/S2 framework are flagged NV-affected only where CLAUDE.md names the specific analysis; I did not extrapolate NV-contamination onto un-named analyses.
5. **2026-08-24** — LP-DiD reweighting fix (`cellsize` estimand retired for `ewatt`/`vwatt`). Any `lpdid_statepanel.R`-family output generated before this date is **CONTAMINATED (cellsize weights)** per CLAUDE.md's explicit statement that "every LP-DiD number... `lpdid_statepanel.R` outputs — was computed on the cellsize estimand."

County-level outputs (built from `monthly_county_data_download.csv` or `combined_monthly_panel.csv` via county aggregation) are immune to double-count and NV per CLAUDE.md's explicit "Immune" list, and are not reclassified here even when old.

Outputs with no producing script found via repo-wide grep of `analysis/`, `scripts/`, `R/`, `data_prep/` are marked UNKNOWN rather than guessed.

---

## Full inventory

| dir | last modified | producing script (best guess) | domain | status | status evidence | move? |
|---|---|---|---|---|---|---|
| `_audit_tmp_fasterFALSE` | 2026-08-20 00:53 | `scripts/run_pretrends_statepanel.sh` | pretrends | DEAD | Task instructions mark `_audit_tmp_*` scratch dirs DEAD by default; also generated 33 min before the 08-20 01:26 panel rebuild, so it additionally reads the double-counted panel | yes |
| `adoption_predictability` | 2026-08-21 12:29 | `analysis/diagnostics/adoption_predictability_prepaspa.R` | diagnostics | LIVE | Post-dates the 08-21 NV audit; filename ("prepaspa") shows NV-aware design; not named in any CLAUDE.md contamination list | no |
| `adoption_predictability_institutions` | 2026-08-21 12:23 | `analysis/diagnostics/adoption_predictability_institutions.R` | diagnostics | LIVE | Companion to the above, same date/logic | no |
| `adoption_selection` | 2026-08-21 10:58 | `analysis/diagnostics/adoption_selection_levels_slopes.R` | diagnostics | LIVE | CLAUDE.md "Trap 1" section names this exact script as fixed 2026-08-21 ("substrate A 29 → 41 states, adopter-never gap +0.64 → +0.24") | no |
| `annual_data_usefulness` | 2026-02-13 | not found | other | UNKNOWN | No producing script found for `annual_basic_2016_2025.csv` etc. via repo-wide grep — flag for review | no |
| `border_diagnostic` | 2026-05-22 (HANDOFF.md) | County border-discontinuity diagnostic, per own README | diagnostics | LIVE | CLAUDE.md: "Immune: ... border diagnostic"; underlies the current recommended +9.1% did2s headline | no |
| `cheap_power_sim` | 2026-08-14 14:26 | `analysis/cheap_sims/*.R` | power | CONTAMINATED | ~~LIVE~~ Overturned by the 2026-08-25 Opus audit: `analysis/cheap_sims/00_common.R:50` reads the double-counted `state_month_panel_with_treatment.csv` and the run predates the 2026-08-20 rebuild; the pre-slim CLAUDE.md contaminated list names "cheap_sims grid" explicitly. (The original call had applied the SUPERSEDED test, not the CONTAMINATED test.) | yes |
| `covid_global_pt` | 2026-08-24 15:44 | `analysis/diagnostics/covid_global_pt_diagnostic.R`, `postcovid_boundary_sweep.R` | diagnostics | LIVE | Most recent file dated same day as the LP-DiD fix session; active COVID-splice investigation feeding the time-aggregation findings | no |
| `cs_calibration_multi_mortgage` | 2026-04-17 14:59 | `analysis/diagnostics/cs_calibration_multi_estimator_mortgage.R` | calibration / mortgage | UNKNOWN | Not referenced anywhere in CLAUDE.md; mortgage panel structurally includes NV per the NV audit, but this specific file was never named in the NV sweep — flag for review | no |
| `cs_calibration_unified` | 2026-04-09 16:40 | `analysis/diagnostics/cs_calibration_unified.R` | calibration | SUPERSEDED | CLAUDE.md labels the entire "2026-04-09" state-panel calibration effort "SUPERSEDED 2026-05-21" by county-level calibration (`cs_calibration_multi_estimator_county.R`); also predates schedule repair and double-count fix | yes |
| `cs_calibration_unified_analytic` | 2026-04-09 16:37 | same | calibration | SUPERSEDED | Same as above (analytic-inference variant of the same sweep) | yes |
| `cs_calibration_unified_analytic_100` | 2026-04-09 16:20 | same | calibration | SUPERSEDED | Same (100-rep variant) | yes |
| `cs_calibration_unified_analytic_20_serial` | 2026-04-09 16:13 | same | calibration | SUPERSEDED | Same (20-rep serial variant) | yes |
| `cs_calibration_unified_bootstrap` | 2026-04-09 16:16 | same | calibration | SUPERSEDED | Same (bootstrap-inference variant) | yes |
| `cs_calibration_unified_bootstrap_25` | 2026-04-09 16:00 | same | calibration | SUPERSEDED | Same (25-rep variant) | yes |
| `cs_state_sweep` | 2026-02-12 | `analysis/main/cs_state_count_sweep.R` (`panel_choice="states_from_counties"`) | power | CONTAMINATED | County-aggregated so double-count immune, but generated before the 2026-08-10 treatment-schedule repair → stale schedule | yes |
| `cs_threshold_sweep_no_maine_2024_min5` | 2026-02-12 | `analysis/diagnostics/cs_power_threshold_sweep_nocovid_small.R` | calibration | SUPERSEDED | CLAUDE.md: "Previous CS threshold-sweep behavior (legacy, superseded by calibration test)" | yes |
| `csdid_debug` | 2026-01-23 / dir 2026-02-04 | `scripts/generate_support_plots.R` | diagnostics | DEAD | Task instructions name `csdid_debug` explicitly as DEAD-by-default | yes |
| `csdid_dynamic_validation_sim` | 2026-02-12 | `analysis/diagnostics/validate_csdid_dynamic_sim.R` | calibration | CONTAMINATED | CLAUDE.md "Critical Files" entry, but README states it "uses your real adoption timing (state-month + `treat_start`)"; generated before the 2026-08-10 schedule repair → stale schedule | yes |
| `csdid_plots` | 2026-01-23 | `scripts/generate_support_plots.R` | diagnostics | UNKNOWN | May underlie CLAUDE.md's still-cited "875 total (g,t) cells; 338 identifiable (38.6%)" support-structure stat, but the panel predates all repairs — ambiguous whether that stat is still meant to be current; flag for review | no |
| `csdid_pretrends` | 2026-01-19 | `scripts/run_csdid_pretrends.R` (+ family in `scripts/`) | pretrends | SUPERSEDED | CLAUDE.md: "Legacy script: `analysis/pretrends/pretrends_modern.R`... CS section disabled. Recommended pipeline: `pretrends_statepanel_template.R`"; predates NH/ME repairs entirely | yes |
| `csdid_pretrends_run.log` (loose file) | 2026-01-23 | companion log to `csdid_pretrends` | pretrends | SUPERSEDED | Companion artifact of the legacy run above | yes |
| `ddd_power` | 2026-08-21 14:19 | `analysis/power/run_ddd_power.R`, `R/power/ddd_power.R` | power | EXPLORATORY | County-level triple-diff power design (1,226–1,295 counties); immune to double-count/NV; not yet referenced in CLAUDE.md as a headline | no |
| `dose_response_iv` | 2026-02-16 18:31 | `analysis/main/dose_response_iv.R` | exploratory | CONTAMINATED | Script's `PANEL_FILE` defaults to `state_month_panel_with_treatment.csv`; predates both the 08-10 schedule repair and the 08-20 double-count fix | yes |
| `eviction_stabilization` | 2026-08-21 11:50 | `analysis/diagnostics/eviction_stabilization_timing.R` | diagnostics | EXPLORATORY | Uses `state_month_panel_with_treatment.csv` but post-dates the 08-20 rebuild (double-count clean) and the 08-21 NV window; descriptive timing chart, not named as contaminated | no |
| `example_csdid` | 2026-01-23 | legacy example workflow (no live script reference found) | other | DEAD | Demo/example output from the original workflow scripts; no longer referenced anywhere in the repo | yes |
| `example_workflow.log` (loose file) | 2026-01-23 | companion to `example_csdid` | other | DEAD | Companion log to the demo workflow | yes |
| `example_workflow_run.log` (loose file) | 2026-01-23 | companion to `example_csdid` | other | DEAD | Companion log to the demo workflow | yes |
| `exposure_curve` | 2026-08-14 18:31 | `analysis/exploratory/exposure_curve_model.R`, `cohort_ramp_lags.R` | exploratory | EXPLORATORY | Handle-based cohort exposure curves, descriptive, no contamination question | no |
| `gardner_spec_sweep_mortgage` | 2026-04-17 15:29 | `analysis/main/gardner_spec_sweep_mortgage.R` | mortgage | EXPLORATORY | did2s/Gardner spec sweep on the mortgage outcome; not referenced in CLAUDE.md, no contamination rule matches | no |
| `handle_cohort_support` | 2026-08-14 17:28 | `analysis/diagnostics/handle_legalization_cohort_support.R` | exploratory | EXPLORATORY | Support diagnostics feeding the ramp75/handle-maturity treatment-definition family | no |
| `handle_four_quarters` | 2026-08-14 17:55 | `analysis/data_prep/make_fourq_dose.R` | exploratory | EXPLORATORY | Dose/exposure construction diagnostics | no |
| `handle_maturity_check` | 2026-08-20 02:29 | none — directory is empty | other | DEAD | Directory contains zero files; no producing script found | yes |
| `hollenbeck_replication_mortgage` | 2026-04-17 18:01 | `analysis/main/hollenbeck_replication_mortgage.R` | mortgage | EXPLORATORY | Replication exercise referencing Hollenbeck et al. (2025); literature-comparison exercise, not a project headline | no |
| `honestdid_mortgage_bjs` | 2026-04-17 15:04 | `analysis/pretrends/honestdid_mortgage_bjs.R` | mortgage | EXPLORATORY | HonestDiD sensitivity check on the mortgage/BJS estimator | no |
| `longdiff_2x2_pseudo` | 2026-08-21 15:21 | `analysis/diagnostics/longdiff_2x2_pseudo_power.R` | diagnostics | LIVE | CLAUDE.md "NV-AFFECTED RE-RUNS COMPLETE" table cites this exact re-run (MDE-80 = 0.2401) | no |
| `longdiff_2x2_selection` | 2026-08-21 14:39 | `analysis/diagnostics/longdiff_2x2_selection_placebo.R` | diagnostics | LIVE | Same "NV-AFFECTED RE-RUNS COMPLETE" table (tau = −0.30%, RI p = 0.976) | no |
| `longdiff_era_variance` | 2026-08-21 14:39 | `analysis/diagnostics/longdiff_real_calendar_decomp.R` | diagnostics | LIVE | Same NV re-run table (median ratio 2.04). CLAUDE.md flags a "PROCESS MISS: overwritten in place, untracked, pre-fix CSVs are gone" — no separate pre-fix copy exists to move | no |
| `lpdid_cs_equivalence` | 2026-08-24 16:12 | `analysis/diagnostics/lpdid_cs_equivalence.R` | calibration | LIVE | CLAUDE.md's "THE CS EQUIVALENCE IS REAL..." section (2026-08-24) cites this exact toy-decomposition table (diffs of 2.2e-16 to 1.1e-01) | no |
| `lpdid_cs_equivalence_keep` | 2026-08-24 16:03 | `analysis/diagnostics/lpdid_cs_equivalence.R` (keep-window arm) | calibration | LIVE | Companion "covid-keep window" arm of the run above | no |
| `lpdid_statepanel` | 2026-08-21 15:57 | `analysis/main/lpdid_statepanel.R` | calibration / power | CONTAMINATED | CLAUDE.md verbatim: "every LP-DiD number... `lpdid_statepanel.R` outputs — was computed on the cellsize estimand" (dead weighting scheme, fixed 2026-08-24) | yes |
| `lpdid_weights_compare` | 2026-08-24 16:27 | `analysis/diagnostics/lpdid_weights_paired_compare.R` | calibration | LIVE | Paired ewatt/vwatt/cellsize comparison produced by the 08-24 weighting fix | no |
| `lpdid_weights_compare_mde` | 2026-08-24 17:12 | same script, MDE arm | calibration | LIVE | Same fix-verification effort, MDE variant | no |
| `market_maturation` | 2026-08-14 17:45 | `analysis/exploratory/market_maturation_timing.R` | exploratory | LIVE | CLAUDE.md's "Gambling Market Maturation (Handle Quintile Timing)" table matches this output exactly (20/40/60/80/100% quintile means) | no |
| `permutation_placebo` | 2026-08-14 19:13 | `analysis/diagnostics/permutation_placebo_real_data.R` | diagnostics | CONTAMINATED | Uses `state_month_panel_with_treatment.csv`, generated before the 08-20 01:26 rebuild → double-count panel | yes |
| `postcovid_handle_ramp_support` | 2026-08-14 17:54 | `analysis/diagnostics/postcovid_handle_ramp_support.R` | exploratory | EXPLORATORY | Support diagnostics for ramp75/handle-maturity candidate states | no |
| `postcovid_ramp_candidates` | 2026-08-14 17:45 | companion to `postcovid_handle_ramp_support` (no direct script match) | exploratory | EXPLORATORY | Companion candidate-state profiling output | no |
| `power_mortgage_cs_final` | 2026-04-09 | not found | mortgage / power | UNKNOWN | No grep match in `analysis/`, `scripts/`, `R/` for this directory name — flag for review | no |
| `power_mortgage_cs_remaining` | 2026-04-09 | not found | mortgage / power | UNKNOWN | Same — no confirmed producer | no |
| `power_mortgage_delinquency` | 2026-04-09 13:10 | `analysis/main/power_simulation_mortgage_delinquency.R` | mortgage / power | UNKNOWN | Contradicts CLAUDE.md's own text ("No formal power simulation exists for mortgage delinquency") — that CLAUDE.md line appears stale since this dir is a complete mortgage power sim; also the mortgage panel structurally includes NV (unconfirmed whether re-run) — flag for review | no |
| `power_mortgage_test` | 2026-04-09 12:48 | not found (likely early test harness for the above) | mortgage / power | UNKNOWN | Same family, no confirmed producer | no |
| `pre2020_state_pretrends` | 2026-03-19 13:24 | `analysis/pretrends/plot_pre2020_state_pretrends.R` | pretrends | EXPLORATORY | Uses `combined_monthly_panel.csv` (county-aggregated) — immune to the double-count rule | no |
| `pretrends_annual_statepanel_experiment` | 2026-02-13 | not found | pretrends | UNKNOWN | No producing script found via repo-wide grep — flag for review | no |
| `pretrends_evaluation` | 2026-02-04 | `analysis/pretrends/evaluate_pretrends_modern_methods.R` | pretrends | SUPERSEDED | Part of the legacy `pretrends_modern.R` family CLAUDE.md calls superseded by `pretrends_statepanel_template.R` | yes |
| `pretrends_eviction_postcovid` | 2026-02-13 12:06 | `scripts/run_pretrends_statepanel.sh` (`state_month_panel_with_treatment.csv`, excl. ME) | pretrends | CONTAMINATED | Predates NH/ME repairs, the 08-10 schedule repair, and the 08-20 double-count fix | yes |
| `pretrends_eviction_postcovid_handle50` | 2026-08-14 17:23 | `scripts/run_pretrends_statepanel.sh` on `data/processed/state_month_panel_handle50_treatment.csv` | pretrends | EXPLORATORY | Alternative handle-maturity-based treatment-date pretrends run; CS pretrends actually REJECTS here (Holm min_p = 0.0335) — not cited as a headline anywhere in CLAUDE.md | no |
| `pretrends_eviction_precovid` | 2026-02-13 13:07 | `scripts/run_pretrends_statepanel.sh`, excl. ME | pretrends | CONTAMINATED | Same reasoning as `pretrends_eviction_postcovid` (pre-COVID window) | yes |
| `pretrends_fixedbasket` | 2026-08-20 01:02 | `scripts/run_pretrends_statepanel.sh` | pretrends | SUPERSEDED | Same config as `pretrends_rebuild_B_newpanel` (25 states/15 cohorts) but ATT +0.022 (generated after the integer-`g` bug fix, same session); one day later `pretrends_lottery_A_baseline` reruns the identical spec at 26 states/16 cohorts once the schedule gained one more state | yes |
| `pretrends_lottery_A_baseline` | 2026-08-21 13:44 | `analysis/pretrends/pretrends_statepanel_template.R` | pretrends | LIVE | Named explicitly as the current headline by the task brief and CLAUDE.md ("+0.020 baseline... is current") | no |
| `pretrends_lottery_B_conditional` | 2026-08-21 13:55 | same | pretrends | LIVE | Part of the current documented 3-spec table (CLAUDE.md 2026-08-21 lottery-vintage section) | no |
| `pretrends_lottery_C_binary` | 2026-08-21 14:04 | same | pretrends | LIVE | Same table; the binary-conditioning spec CLAUDE.md recommends over the continuous one | no |
| `pretrends_mortgage_bjs` | 2026-04-17 14:22 | BJS/didimputation event-study check on mortgage (no confirmed producer via exact-name grep) | mortgage | EXPLORATORY | One-off BJS event-study check on the mortgage outcome | no |
| `pretrends_mortgage_delinquency` | 2026-02-13 01:43 | `analysis/pretrends/pretrends_mortgage_delinquency.R`, `scripts/run_pretrends_mortgage.sh` | mortgage / pretrends | CONTAMINATED | CLAUDE.md "NV FOOTPRINT SWEEP" explicitly flags "Mortgage delinquency pretrends" as NV-affected, and it is **not** in the "NV-AFFECTED RE-RUNS COMPLETE" list of 4 fixed analyses | yes |
| `pretrends_pre_post_covid` | 2026-01-17 14:04 | legacy `pretrends_modern.R` family | pretrends | SUPERSEDED | Same legacy-pipeline reasoning as `pretrends_evaluation` | yes |
| `pretrends_rebuild_A_oldpanel` | 2026-08-20 00:33 | `analysis/pretrends/pretrends_statepanel_template.R`, pointed at the deprecated CSV | pretrends | CONTAMINATED | Literally reads `data/raw/deprecated/state_month_panel_with_treatment_double_counted_2026-08-20.csv` — the double-count rule by name; kept intentionally by CLAUDE.md as the "before" side of a before/after comparison, but still contaminated data | yes |
| `pretrends_rebuild_B_newpanel` | 2026-08-20 00:33 | same script, rebuilt panel | pretrends | DEAD | CLAUDE.md verbatim: "The +0.080 provisional headline is DEAD — it was a bug, not an estimate" (integer-`g` truncation bug) | yes |
| `pretrends_statepanel_me_included` | 2026-07-23 14:08 | `scripts/run_pretrends_statepanel.sh` | pretrends | CONTAMINATED | CLAUDE.md verbatim: "the saved run is 2026-07-23 and uses the PRE-repair schedule (16 never-treated, incl. ME/VT/KY/FL): re-run before citing" | yes |
| `pretrends_statepanel_template` | 2026-02-13 12:37 | `analysis/pretrends/pretrends_statepanel_template.R` | pretrends | CONTAMINATED | Predates the ME repair (07-23), the 08-10 schedule repair, and the 08-20 double-count fix; ME excluded entirely | yes |
| `pretrends_statepanel_template_nocovid_smoketest` | 2026-02-13 01:40 | `analysis/pretrends/pretrends_statepanel_template.R` | pretrends | DEAD | Task instructions mark this smoketest family DEAD by default | yes |
| `pretrends_statepanel_template_nocovid_smoketest2` | 2026-02-13 01:45 | same | pretrends | DEAD | Same | yes |
| `pretrends_statepanel_template_nocovid_smoketest3` | 2026-02-13 01:47 | same | pretrends | DEAD | Same | yes |
| `pretrends_statepanel_template_nocovid_smoketest4` | 2026-02-13 01:47 | same | pretrends | DEAD | Same | yes |
| `pretrends_statepanel_template_nocovid_smoketest5` | 2026-02-13 01:49 | same | pretrends | DEAD | Same | yes |
| `pretrends_statepanel_template_nocovid_smoketest6` | 2026-02-13 01:49 | same | pretrends | DEAD | Same | yes |
| `pretrends_statepanel_template_nocovid_smoketest7` | 2026-02-13 01:58 | same | pretrends | DEAD | Same | yes |
| `retail_vs_online` | 2026-07-23 13:58 | `analysis/exploratory/retail_vs_online_handle.R`, `retail_vs_online_gambling_growth.R` | exploratory | EXPLORATORY | Descriptive handle-data comparison (not filings-based), reads only `lsr_sports_betting_handle_revenue_by_state_month.csv` — immune to double-count; predates the 08-10 schedule repair so DE/NC/KY/ME/FL/VT/MO regime labels may be off, but low materiality for a descriptive chart | no |
| `shift_validation` | 2026-08-17 13:35 | `analysis/diagnostics/validate_shift_sufficiency.R` (TWFE arm) | power | LIVE | Validates shift-mode sufficiency for TWFE (max discrepancy ~0.04); foundational to the shift-mode framework still in active use | no |
| `shift_validation_cs` | 2026-08-17 16:33 | same script, CS arm | power | SUPERSEDED | Large discrepancies (up to 0.25) for CS; CLAUDE.md: "Shift mode was barred for the headline CS MDE by an Opus review... the replacement is `R/power/adaptive_mde.R`" | yes |
| `state_influence_loo` | 2026-02-13 | `analysis/diagnostics/state_influence_loo.R` | diagnostics | CONTAMINATED | Uses `state_month_panel_with_treatment.csv`, predates all repairs and the double-count fix | yes |
| `state_influence_loo_postcovid` | 2026-02-13 | same | diagnostics | CONTAMINATED | Same | yes |
| `state_influence_loo_precovid` | 2026-02-13 | same | diagnostics | CONTAMINATED | Same | yes |
| `state_month_coverage_by_state.csv` (loose file) | 2026-02-13 | `analysis/diagnostics/cs_power_threshold_sweep_nocovid_small.R` | pretrends | SUPERSEDED | Byproduct of the legacy threshold-sweep script CLAUDE.md calls superseded | yes |
| `state_month_coverage_by_state_2016_2024.csv` (loose file) | 2026-02-13 | same | pretrends | SUPERSEDED | Same | yes |
| `state_month_coverage_gaps_2016plus.csv` (loose file) | 2026-02-13 | same | pretrends | SUPERSEDED | Same | yes |
| `state_month_missing_months_vs_global.csv` (loose file) | 2026-02-13 | same | pretrends | SUPERSEDED | Same | yes |
| `statepanel_double_count` | 2026-08-20 00:25 | `analysis/diagnostics/statepanel_double_count_audit.R` | diagnostics | LIVE | This is the audit that discovered and documents the double-count bug — the direct evidentiary basis for CLAUDE.md's "STATE PANEL DOUBLE COUNT" section | no |
| `threshold_covid_sample_size` | 2026-02-13 | probable `analysis/diagnostics/cs_power_threshold_sweep_nocovid_small.R` family (no exact-name match) | pretrends | SUPERSEDED | Same legacy threshold-sweep family by date/output shape; CLAUDE.md calls the family superseded | yes |
| `threshold_covid_sample_size_online_only` | 2026-02-13 | same | pretrends | SUPERSEDED | Same | yes |
| `timing_covid_recovery` | 2026-08-15 01:57 | `analysis/diagnostics/timing_covid_recovery_test.R` | diagnostics | CONTAMINATED | Uses `state_month_panel_with_treatment.csv`, generated before the 08-20 01:26 rebuild → double-count panel | yes |

---

## UNKNOWNs flagged for human review (8)

1. `annual_data_usefulness` — no producing script found anywhere in the repo.
2. `cs_calibration_multi_mortgage` — not referenced in CLAUDE.md; unconfirmed NV exposure.
3. `csdid_plots` — may underlie a support-structure stat CLAUDE.md still cites as current, but the panel is stale; unclear if that stat needs updating.
4. `power_mortgage_cs_final` — no producing script found.
5. `power_mortgage_cs_remaining` — no producing script found.
6. `power_mortgage_delinquency` — a complete mortgage power sim exists on disk, but CLAUDE.md's prose says "No formal power simulation exists for mortgage delinquency" — one of these is stale.
7. `power_mortgage_test` — no producing script found.
8. `pretrends_annual_statepanel_experiment` — no producing script found.
