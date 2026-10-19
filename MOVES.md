# MOVES.md — 2026-08-25 repo cleanup

Every artifact relocated by the cleanup, old → new. Classifications and evidence:
`quality_reports/cleanup_2026-08-25/inventory_*.md`; statuses: `RUN_LEDGER.md`.
Nothing was deleted. Reversal is `mv` back.

| old path | new path | reason |
|---|---|---|
| — (Oregon added, nothing displaced) | `data/raw/state_month_panel_with_treatment.csv` | 2026-09-14: OR added from OJD PDFs (2018-01..2019-12) + Evicted in Oregon dashboard (2020-01..2026-07); 39 → 40 states |
| `data/raw/state_month_panel_with_treatment.csv` (pre-ramp-censor vintage) | `data/raw/deprecated/state_month_panel_with_treatment_pre_ramp_censor_2026-09-14.csv` | 2026-09-14 series-start ramp censor: CT 2016-01/02 and NH 2018-12 removed as incomplete-at-ingest reporting; superseded vintage preserved |
| `data/raw/state_month_panel_with_treatment.csv` (pre-single-series-rebuild vintage) | `data/raw/deprecated/state_month_panel_with_treatment_pre_single_series_rebuild_2026-09-14.csv` | 2026-09-14 single-series rebuild: LA MA MO NM NV RI rebuilt from `ets_county_month.csv`; superseded vintage preserved, not deleted |
| `output/_audit_tmp_fasterFALSE` | `output/deprecated/_audit_tmp_fasterFALSE` | per inventory_output.md |
| `output/cs_calibration_unified` | `output/deprecated/cs_calibration_unified` | per inventory_output.md |
| `output/cs_calibration_unified_analytic` | `output/deprecated/cs_calibration_unified_analytic` | per inventory_output.md |
| `output/cs_calibration_unified_analytic_100` | `output/deprecated/cs_calibration_unified_analytic_100` | per inventory_output.md |
| `output/cs_calibration_unified_analytic_20_serial` | `output/deprecated/cs_calibration_unified_analytic_20_serial` | per inventory_output.md |
| `output/cs_calibration_unified_bootstrap` | `output/deprecated/cs_calibration_unified_bootstrap` | per inventory_output.md |
| `output/cs_calibration_unified_bootstrap_25` | `output/deprecated/cs_calibration_unified_bootstrap_25` | per inventory_output.md |
| `output/cs_state_sweep` | `output/deprecated/cs_state_sweep` | per inventory_output.md |
| `output/cs_threshold_sweep_no_maine_2024_min5` | `output/deprecated/cs_threshold_sweep_no_maine_2024_min5` | per inventory_output.md |
| `output/csdid_debug` | `output/deprecated/csdid_debug` | per inventory_output.md |
| `output/csdid_dynamic_validation_sim` | `output/deprecated/csdid_dynamic_validation_sim` | per inventory_output.md |
| `output/csdid_pretrends` | `output/deprecated/csdid_pretrends` | per inventory_output.md |
| `output/csdid_pretrends_run.log` | `output/deprecated/csdid_pretrends_run.log` | per inventory_output.md |
| `output/dose_response_iv` | `output/deprecated/dose_response_iv` | per inventory_output.md |
| `output/example_csdid` | `output/deprecated/example_csdid` | per inventory_output.md |
| `output/example_workflow.log` | `output/deprecated/example_workflow.log` | per inventory_output.md |
| `output/example_workflow_run.log` | `output/deprecated/example_workflow_run.log` | per inventory_output.md |
| `output/handle_maturity_check` | `output/deprecated/handle_maturity_check` | per inventory_output.md |
| `output/lpdid_statepanel` | `output/deprecated/lpdid_statepanel` | per inventory_output.md |
| `output/permutation_placebo` | `output/deprecated/permutation_placebo` | per inventory_output.md |
| `output/pretrends_evaluation` | `output/deprecated/pretrends_evaluation` | per inventory_output.md |
| `output/pretrends_eviction_postcovid` | `output/deprecated/pretrends_eviction_postcovid` | per inventory_output.md |
| `output/pretrends_eviction_precovid` | `output/deprecated/pretrends_eviction_precovid` | per inventory_output.md |
| `output/pretrends_fixedbasket` | `output/deprecated/pretrends_fixedbasket` | per inventory_output.md |
| `output/pretrends_mortgage_delinquency` | `output/deprecated/pretrends_mortgage_delinquency` | per inventory_output.md |
| `output/pretrends_pre_post_covid` | `output/deprecated/pretrends_pre_post_covid` | per inventory_output.md |
| `output/pretrends_rebuild_A_oldpanel` | `output/deprecated/pretrends_rebuild_A_oldpanel` | per inventory_output.md |
| `output/pretrends_rebuild_B_newpanel` | `output/deprecated/pretrends_rebuild_B_newpanel` | per inventory_output.md |
| `output/pretrends_statepanel_me_included` | `output/deprecated/pretrends_statepanel_me_included` | per inventory_output.md |
| `output/pretrends_statepanel_template` | `output/deprecated/pretrends_statepanel_template` | per inventory_output.md |
| `output/pretrends_statepanel_template_nocovid_smoketest` | `output/deprecated/pretrends_statepanel_template_nocovid_smoketest` | per inventory_output.md |
| `output/pretrends_statepanel_template_nocovid_smoketest2` | `output/deprecated/pretrends_statepanel_template_nocovid_smoketest2` | per inventory_output.md |
| `output/pretrends_statepanel_template_nocovid_smoketest3` | `output/deprecated/pretrends_statepanel_template_nocovid_smoketest3` | per inventory_output.md |
| `output/pretrends_statepanel_template_nocovid_smoketest4` | `output/deprecated/pretrends_statepanel_template_nocovid_smoketest4` | per inventory_output.md |
| `output/pretrends_statepanel_template_nocovid_smoketest5` | `output/deprecated/pretrends_statepanel_template_nocovid_smoketest5` | per inventory_output.md |
| `output/pretrends_statepanel_template_nocovid_smoketest6` | `output/deprecated/pretrends_statepanel_template_nocovid_smoketest6` | per inventory_output.md |
| `output/pretrends_statepanel_template_nocovid_smoketest7` | `output/deprecated/pretrends_statepanel_template_nocovid_smoketest7` | per inventory_output.md |
| `output/shift_validation_cs` | `output/deprecated/shift_validation_cs` | per inventory_output.md |
| `output/state_influence_loo` | `output/deprecated/state_influence_loo` | per inventory_output.md |
| `output/state_influence_loo_postcovid` | `output/deprecated/state_influence_loo_postcovid` | per inventory_output.md |
| `output/state_influence_loo_precovid` | `output/deprecated/state_influence_loo_precovid` | per inventory_output.md |
| `output/state_month_coverage_by_state.csv` | `output/deprecated/state_month_coverage_by_state.csv` | per inventory_output.md |
| `output/state_month_coverage_by_state_2016_2024.csv` | `output/deprecated/state_month_coverage_by_state_2016_2024.csv` | per inventory_output.md |
| `output/state_month_coverage_gaps_2016plus.csv` | `output/deprecated/state_month_coverage_gaps_2016plus.csv` | per inventory_output.md |
| `output/state_month_missing_months_vs_global.csv` | `output/deprecated/state_month_missing_months_vs_global.csv` | per inventory_output.md |
| `output/threshold_covid_sample_size` | `output/deprecated/threshold_covid_sample_size` | per inventory_output.md |
| `output/threshold_covid_sample_size_online_only` | `output/deprecated/threshold_covid_sample_size_online_only` | per inventory_output.md |
| `output/timing_covid_recovery` | `output/deprecated/timing_covid_recovery` | per inventory_output.md |
| `output_blinded_power/_amde_county_smoke` | `output_blinded_power/deprecated/_amde_county_smoke` | per inventory_blinded_power.md |
| `output_blinded_power/_amde_county_smoke.log` | `output_blinded_power/deprecated/_amde_county_smoke.log` | per inventory_blinded_power.md |
| `output_blinded_power/_amde_state_check.log` | `output_blinded_power/deprecated/_amde_state_check.log` | per inventory_blinded_power.md |
| `output_blinded_power/_amde_state_check_adaptive` | `output_blinded_power/deprecated/_amde_state_check_adaptive` | per inventory_blinded_power.md |
| `output_blinded_power/_amde_state_check_brute` | `output_blinded_power/deprecated/_amde_state_check_brute` | per inventory_blinded_power.md |
| `output_blinded_power/_cs_cty_111` | `output_blinded_power/deprecated/_cs_cty_111` | per inventory_blinded_power.md |
| `output_blinded_power/_cs_cty_222` | `output_blinded_power/deprecated/_cs_cty_222` | per inventory_blinded_power.md |
| `output_blinded_power/_cs_probe_111` | `output_blinded_power/deprecated/_cs_probe_111` | per inventory_blinded_power.md |
| `output_blinded_power/_cs_probe_111b` | `output_blinded_power/deprecated/_cs_probe_111b` | per inventory_blinded_power.md |
| `output_blinded_power/_cs_probe_222` | `output_blinded_power/deprecated/_cs_probe_222` | per inventory_blinded_power.md |
| `output_blinded_power/_cs_probe_333` | `output_blinded_power/deprecated/_cs_probe_333` | per inventory_blinded_power.md |
| `output_blinded_power/_cs_probe_444` | `output_blinded_power/deprecated/_cs_probe_444` | per inventory_blinded_power.md |
| `output_blinded_power/_e2e_brute_verify` | `output_blinded_power/deprecated/_e2e_brute_verify` | per inventory_blinded_power.md |
| `output_blinded_power/_e2e_shift_verify` | `output_blinded_power/deprecated/_e2e_shift_verify` | per inventory_blinded_power.md |
| `output_blinded_power/_e2e_shift_verify2` | `output_blinded_power/deprecated/_e2e_shift_verify2` | per inventory_blinded_power.md |
| `output_blinded_power/_int_cs6` | `output_blinded_power/deprecated/_int_cs6` | per inventory_blinded_power.md |
| `output_blinded_power/_int_cs6b` | `output_blinded_power/deprecated/_int_cs6b` | per inventory_blinded_power.md |
| `output_blinded_power/_int_subset` | `output_blinded_power/deprecated/_int_subset` | per inventory_blinded_power.md |
| `output_blinded_power/_smoke_ewatt` | `output_blinded_power/deprecated/_smoke_ewatt` | per inventory_blinded_power.md |
| `output_blinded_power/_smoke_parallel_realmods` | `output_blinded_power/deprecated/_smoke_parallel_realmods` | per inventory_blinded_power.md |
| `output_blinded_power/boundary_SMOKE` | `output_blinded_power/deprecated/boundary_SMOKE` | per inventory_blinded_power.md |
| `output_blinded_power/cheap` | `output_blinded_power/deprecated/cheap` | per inventory_blinded_power.md |
| `output_blinded_power/county_cs` | `output_blinded_power/deprecated/county_cs` | per inventory_blinded_power.md |
| `output_blinded_power/county_cs_adaptive_run.log` | `output_blinded_power/county_cs_adaptive/county_cs_adaptive_run.log` | log kept with its LIVE/EXPLORATORY run |
| `output_blinded_power/county_cs_adaptive_run2.log` | `output_blinded_power/county_cs_adaptive/county_cs_adaptive_run2.log` | log kept with its LIVE/EXPLORATORY run |
| `output_blinded_power/county_cs_adaptive_run3_finalize.log` | `output_blinded_power/county_cs_adaptive/county_cs_adaptive_run3_finalize.log` | log kept with its LIVE/EXPLORATORY run |
| `output_blinded_power/county_cs_run.log` | `output_blinded_power/deprecated/county_cs_run.log` | per inventory_blinded_power.md |
| `output_blinded_power/cs_probe` | `output_blinded_power/deprecated/cs_probe` | per inventory_blinded_power.md |
| `output_blinded_power/cs_probe_run.log` | `output_blinded_power/deprecated/cs_probe_run.log` | per inventory_blinded_power.md |
| `output_blinded_power/dose_tercile_gates` | `output_blinded_power/deprecated/dose_tercile_gates` | per inventory_blinded_power.md |
| `output_blinded_power/dose_tercile_gates_run.log` | `output_blinded_power/deprecated/dose_tercile_gates_run.log` | per inventory_blinded_power.md |
| `output_blinded_power/e2e_smoke_validation` | `output_blinded_power/deprecated/e2e_smoke_validation` | per inventory_blinded_power.md |
| `output_blinded_power/ldam_gate` | `output_blinded_power/deprecated/ldam_gate` | per inventory_blinded_power.md |
| `output_blinded_power/ldam_gate_keepcovid` | `output_blinded_power/deprecated/ldam_gate_keepcovid` | per inventory_blinded_power.md |
| `output_blinded_power/ldam_gate_postcovid` | `output_blinded_power/deprecated/ldam_gate_postcovid` | per inventory_blinded_power.md |
| `output_blinded_power/longdiff_power` | `output_blinded_power/deprecated/longdiff_power` | per inventory_blinded_power.md |
| `output_blinded_power/longdiff_power_run.log` | `output_blinded_power/deprecated/longdiff_power_run.log` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_anchor_probe` | `output_blinded_power/deprecated/lpdid_anchor_probe` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_gate` | `output_blinded_power/deprecated/lpdid_gate` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_gate_noNV` | `output_blinded_power/deprecated/lpdid_gate_noNV` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_gate_postcovid` | `output_blinded_power/deprecated/lpdid_gate_postcovid` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_gate_postcovid_noNV` | `output_blinded_power/deprecated/lpdid_gate_postcovid_noNV` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_gate_postcovid_run.log` | `output_blinded_power/deprecated/lpdid_gate_postcovid_run.log` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_gate_run.log` | `output_blinded_power/deprecated/lpdid_gate_run.log` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_mde` | `output_blinded_power/deprecated/lpdid_mde` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_mde_county` | `output_blinded_power/deprecated/lpdid_mde_county` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_mde_county_run.log` | `output_blinded_power/deprecated/lpdid_mde_county_run.log` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_mde_county_run2.log` | `output_blinded_power/deprecated/lpdid_mde_county_run2.log` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_mde_fixedpanel` | `output_blinded_power/deprecated/lpdid_mde_fixedpanel` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_mde_noNV` | `output_blinded_power/deprecated/lpdid_mde_noNV` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_mde_run.log` | `output_blinded_power/deprecated/lpdid_mde_run.log` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_ramp75_anchor` | `output_blinded_power/deprecated/lpdid_ramp75_anchor` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_ramp75_gate` | `output_blinded_power/deprecated/lpdid_ramp75_gate` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_ramp75_gate_noNV` | `output_blinded_power/deprecated/lpdid_ramp75_gate_noNV` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_ramp75_gate_v2` | `output_blinded_power/deprecated/lpdid_ramp75_gate_v2` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_ramp75_mde` | `output_blinded_power/deprecated/lpdid_ramp75_mde` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_ramp75_mde_noNV` | `output_blinded_power/deprecated/lpdid_ramp75_mde_noNV` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_shift12_gate_ewatt_run.log` | `output_blinded_power/lpdid_shift12_gate_ewatt/lpdid_shift12_gate_ewatt_run.log` | log kept with its LIVE/EXPLORATORY run |
| `output_blinded_power/lpdid_shift12_gate_noNV` | `output_blinded_power/deprecated/lpdid_shift12_gate_noNV` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_shift12_gate_vwatt_run.log` | `output_blinded_power/lpdid_shift12_gate_vwatt/lpdid_shift12_gate_vwatt_run.log` | log kept with its LIVE/EXPLORATORY run |
| `output_blinded_power/lpdid_shift12_mde_ewatt_run.log` | `output_blinded_power/lpdid_shift12_mde_ewatt/lpdid_shift12_mde_ewatt_run.log` | log kept with its LIVE/EXPLORATORY run |
| `output_blinded_power/lpdid_shift12_mde_noNV` | `output_blinded_power/deprecated/lpdid_shift12_mde_noNV` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_shift12_mde_vwatt_run.log` | `output_blinded_power/lpdid_shift12_mde_vwatt/lpdid_shift12_mde_vwatt_run.log` | log kept with its LIVE/EXPLORATORY run |
| `output_blinded_power/lpdid_wild_gate` | `output_blinded_power/deprecated/lpdid_wild_gate` | per inventory_blinded_power.md |
| `output_blinded_power/lpdid_wild_gate_noNV` | `output_blinded_power/deprecated/lpdid_wild_gate_noNV` | per inventory_blinded_power.md |
| `output_blinded_power/postcovid_maturation` | `output_blinded_power/deprecated/postcovid_maturation` | per inventory_blinded_power.md |
| `output_blinded_power/postcovid_maturation_county_run.log` | `output_blinded_power/postcovid_maturation_county/postcovid_maturation_county_run.log` | log kept with its LIVE/EXPLORATORY run |
| `output_blinded_power/postcovid_maturation_county_wild_run.log` | `output_blinded_power/postcovid_maturation_county_wild/postcovid_maturation_county_wild_run.log` | log kept with its LIVE/EXPLORATORY run |
| `output_blinded_power/postcovid_maturation_run.log` | `output_blinded_power/deprecated/postcovid_maturation_run.log` | per inventory_blinded_power.md |
| `output_blinded_power/primary` | `output_blinded_power/deprecated/primary` | per inventory_blinded_power.md |
| `output_blinded_power/sensitivity` | `output_blinded_power/deprecated/sensitivity` | per inventory_blinded_power.md |
| `output_blinded_power/smoke` | `output_blinded_power/deprecated/smoke` | per inventory_blinded_power.md |
| `output_blinded_power/time_agg_covid_gates_run.log` | `output_blinded_power/time_agg_covid_gates/time_agg_covid_gates_run.log` | log kept with its LIVE/EXPLORATORY run |
| `output_blinded_power/time_agg_covid_gates_run2.log` | `output_blinded_power/time_agg_covid_gates/time_agg_covid_gates_run2.log` | log kept with its LIVE/EXPLORATORY run |
| `output_blinded_power/time_agg_covid_gates_run3_serial.log` | `output_blinded_power/time_agg_covid_gates/time_agg_covid_gates_run3_serial.log` | log kept with its LIVE/EXPLORATORY run |
| `CLEANUP_SUMMARY.txt` | `deprecated/CLEANUP_SUMMARY.txt` | root relic (Jan-2026 status docs / stale artifacts) |
| `COPY_PASTE_FOR_PAPER.md` | `deprecated/COPY_PASTE_FOR_PAPER.md` | root relic (Jan-2026 status docs / stale artifacts) |
| `CSDID_STATE_COUNT.txt` | `deprecated/CSDID_STATE_COUNT.txt` | root relic (Jan-2026 status docs / stale artifacts) |
| `FINAL_DELIVERABLES_SUMMARY.md` | `deprecated/FINAL_DELIVERABLES_SUMMARY.md` | root relic (Jan-2026 status docs / stale artifacts) |
| `MISSION_ACCOMPLISHED.txt` | `deprecated/MISSION_ACCOMPLISHED.txt` | root relic (Jan-2026 status docs / stale artifacts) |
| `OUTPUT_SUMMARY.md` | `deprecated/OUTPUT_SUMMARY.md` | root relic (Jan-2026 status docs / stale artifacts) |
| `PAPER_CHECKLIST.md` | `deprecated/PAPER_CHECKLIST.md` | root relic (Jan-2026 status docs / stale artifacts) |
| `PLOTS_FOUND.txt` | `deprecated/PLOTS_FOUND.txt` | root relic (Jan-2026 status docs / stale artifacts) |
| `PROJECT_STRUCTURE.txt` | `deprecated/PROJECT_STRUCTURE.txt` | root relic (Jan-2026 status docs / stale artifacts) |
| `READ_FIRST_INDEX.txt` | `deprecated/READ_FIRST_INDEX.txt` | root relic (Jan-2026 status docs / stale artifacts) |
| `WHERE_ARE_MY_OUTPUTS.txt` | `deprecated/WHERE_ARE_MY_OUTPUTS.txt` | root relic (Jan-2026 status docs / stale artifacts) |
| `WHERE_ARE_MY_PLOTS.txt` | `deprecated/WHERE_ARE_MY_PLOTS.txt` | root relic (Jan-2026 status docs / stale artifacts) |
| `START_HERE.md` | `deprecated/START_HERE.md` | root relic (Jan-2026 status docs / stale artifacts) |
| `QUICK_START.md` | `deprecated/QUICK_START.md` | root relic (Jan-2026 status docs / stale artifacts) |
| `Rplots.pdf` | `deprecated/Rplots.pdf` | root relic (Jan-2026 status docs / stale artifacts) |
| `monthly_county_data_download_8_20.csv` | `deprecated/monthly_county_data_download_8_20.csv` | root relic (Jan-2026 status docs / stale artifacts) |
| `della_upload.zip` | `deprecated/della_upload.zip` | root relic (Jan-2026 status docs / stale artifacts) |
| `della_power_upload.zip` | `deprecated/della_power_upload.zip` | root relic (Jan-2026 status docs / stale artifacts) |
| `Autor_Dube_McGrew_Nov-2023.pdf` | `Literature/Autor_Dube_McGrew_Nov-2023.pdf (copy); deprecated/Autor_Dube_McGrew_Nov-2023.pdf (original)` | reference PDF relocated to Literature/ |
| `Autoregressive models for panel data causal inference with application to state-level opioid policies.pdf` | `Literature/Autoregressive models for panel data causal inference with application to state-level opioid policies.pdf (copy); deprecated/Autoregressive models for panel data causal inference with application to state-level opioid policies.pdf (original)` | reference PDF relocated to Literature/ |
| `Difference-in-differences for mediation analysis using double machine learning.pdf` | `Literature/Difference-in-differences for mediation analysis using double machine learning.pdf (copy); deprecated/Difference-in-differences for mediation analysis using double machine learning.pdf (original)` | reference PDF relocated to Literature/ |
| `Improved Inference for CSDID Using the Cluster Jackknife.pdf` | `Literature/Improved Inference for CSDID Using the Cluster Jackknife.pdf (copy); deprecated/Improved Inference for CSDID Using the Cluster Jackknife.pdf (original)` | reference PDF relocated to Literature/ |
| `J of Applied Econometrics - 2025 - Dube - A Local Projections Approach to Difference‐in‐Differences.pdf` | `Literature/J of Applied Econometrics - 2025 - Dube - A Local Projections Approach to Difference‐in‐Differences.pdf (copy); deprecated/J of Applied Econometrics - 2025 - Dube - A Local Projections Approach to Difference‐in‐Differences.pdf (original)` | reference PDF relocated to Literature/ |
| `Sports Betting Across Borders Spatial Spillovers, Credit Distress, and Fiscal Externalities.pdf` | `Literature/Sports Betting Across Borders Spatial Spillovers, Credit Distress, and Fiscal Externalities.pdf (copy); deprecated/Sports Betting Across Borders Spatial Spillovers, Credit Distress, and Fiscal Externalities.pdf (original)` | reference PDF relocated to Literature/ |
| `Robust Signal Maximization in Spillover Experiments.pdf` | `Literature/Robust Signal Maximization in Spillover Experiments.pdf (copy); deprecated/Robust Signal Maximization in Spillover Experiments.pdf (original)` | reference PDF relocated to Literature/ |
| `w32902.pdf` | `Literature/w32902.pdf (copy); deprecated/w32902.pdf (original)` | reference PDF relocated to Literature/ |
| `output/cheap_power_sim` | `output/deprecated/cheap_power_sim` | status overturned LIVE→CONTAMINATED by 2026-08-25 Opus audit (pre-rebuild state panel) |
| `output/border_diagnostic/cs_calibration_multi_county/{calibration_summary,sim_results}.csv` (2026-05-21 run) | `output/border_diagnostic/deprecated/cs_calibration_multi_county_2026-05-21_sunab-na-bug_stale-vintage/` (copies; originals overwritten in place by the 2026-08-28 corrected re-run) | CONTAMINATED: SA arm ran with zero never-treated controls (sunab NA-cohort bug) AND the whole run predates the 08-10 schedule repair + 08-20 panel rebuild; see docs/findings-archive/sunab-attgt-encoding-bugs_2026-08-28.md |
| `data/raw/state_month_panel_with_treatment.csv` (2026-08-20 global-basket vintage) | `data/raw/deprecated/state_month_panel_with_treatment_globalbasket_2026-08-20.csv` (copy; canonical replaced by the 2026-08-28 per-state-basket rebuild) | vintage boundary: per-state basket starts add CO/HI/MS/NY/SC (34→39 states); prior state-months unchanged bit-for-bit |
| `output_blinded_power/lpdid_launch_h1824_gate_ewatt/` (+ `_run.log`) | `output_blinded_power/deprecated/lpdid_launch_h1824_gate_ewatt_prebasket_partial/` | DEAD partial: 2,000-rep gate started locally on the pre-basket panel, killed after ~1 min (Della redirect); must not be resumed on the 39-state panel — configs now use `_p39` run_names |
| `output_blinded_power/lpdid_shift12_sdprobe_clean_noID_vwatt_pmd6/` | `output_blinded_power/deprecated/lpdid_shift12_sdprobe_clean_noID_vwatt_pmd6_ACTUALLY_EWATT/` | MISLABELED: a sed pattern anchored `ewatt$` missed the trailing-comment line, so this "vwatt" probe (and the first cut of the clean_{gate,mde}_vwatt_pmd6 configs, fixed in place 2026-08-29) ran EWATT; results are duplicates of the ewatt pmd6 probe, never ledgered. Della's `lpdid_shift12_clean_{gate,mde}_vwatt_pmd6` dirs from the 2026-08-29 run carry the same ewatt-spec partials and must be rm'd before rerunning the corrected configs |

## 2026-09-14 — county-arm timing probe (option C)

| Old path | New path | Why |
|---|---|---|
| `config/power_lpdid_shift12_clean_gate_county_ewatt_pmd6_timing.yml` | `config/deprecated/power_lpdid_shift12_clean_gate_county_ewatt_pmd6_timing.yml` | 5-rep timing probe used only to size the real run; superseded by `config/power_lpdid_shift12_clean_gate_county_ewatt_pmd6.yml` |
| `output_blinded_power/lpdid_shift12_clean_county_ewatt_pmd6_timing/` | `output_blinded_power/deprecated/lpdid_shift12_clean_county_ewatt_pmd6_timing/` | its output; 5 reps, never citable |

## 2026-09-14 — WA + MI panel addition and trailing-partial censor

| Old path | New path | Why |
|---|---|---|
| `data/raw/state_month_panel_with_treatment.csv` (40-state post-Oregon vintage) | `data/raw/deprecated/state_month_panel_with_treatment_pre_wa_mi_2026-09-14.csv` (copy; canonical replaced in place) | vintage boundary 8: adds WA (Tacoma/Pierce, 113 months, never-treated control) and MI (JDW statewide, 68 of 89 months) → 42 states, and censors the trailing partial month of LA/MA/MO/NM. Pre-existing rows are unchanged apart from those four removals; see [`docs/findings-archive/2026-09-14_wa-mi-panel-addition.md`](docs/findings-archive/2026-09-14_wa-mi-panel-addition.md) |

## 2026-09-14 — clean-design window audit supersedes the hand-clocked sweep

| Old path | New path | Why |
|---|---|---|
| `analysis/diagnostics/covid_end_monthly_sweep.R` | `analysis/diagnostics/deprecated/covid_end_monthly_sweep.R` | Superseded by `analysis/diagnostics/clean_design_window_audit.R`. The deprecated script hardcoded month offsets (first on the shift12 clock, which placed both windows 12 months too late, then patched to the launch clock) and inherited `n_norm >= 2`, which silently dropped LA/NH/NY from the drift metric — exactly the states an earlier boundary admits, so the cost of moving the boundary read as zero when it was merely unmeasured. The replacement derives the windows from `config/power_lpdid_clean_gate_ewatt_pmd6_v20260914.yml` and asserts them. |

## 2026-09-29 — Bartik–eviction design memo split to its own repo

| Old path | New path | Why |
|---|---|---|
| `quality_reports/specs/2026-09-29_bartik_eviction_design_memo.md` (v3.1) | `quality_reports/specs/deprecated/2026-09-29_bartik_eviction_design_memo_v3.1.md` | The labor-demand/eviction paper moved to `~/Documents/GitHub Doc/Labor-Demand-and-Eviction` (initial commit `6395e26`); the live memo is `docs/design/design_memo.md` there. v1–v3 were already in the same `deprecated/` folder. `data_prep/bartik/build_bartik_cfpl_replication.R` stays here because RUN_LEDGER row `cfpl_bartik_replication` points to it. |

## 2026-10-09 — Stale 90+ mortgage panel replaced

| Old path | New path | Why |
|---|---|---|
| `data/processed/mortgage_treatment_panel.csv` (2026-01-23 build) | `data/processed/deprecated/mortgage_treatment_panel_pre-schedule-repair_2026-01-23.csv` | Treatment column predated the 2026-08-10 schedule repair (DE FL KY ME NC VT MO missing). Rebuilt in place on the current schedule by `data_prep/build_mortgage3089_panel.R` with `MORT_FILE`/`OUT_FILE`; rates bit-identical. See `docs/findings-archive/2026-10-09_stale-90plus-panel-correction.md`. |

## 2026-10-19 — Maine FED report re-parsed and spliced through 2026-08

| Old path | New path | Why |
|---|---|---|
| `fed-monthly15yr-report.pdf` (repo root, added by Ben) | `data/raw/monthly_expansion/me_raw/fed-monthly15yr-report_ref20260918.pdf` (working copy); root original kept at `deprecated/fed-monthly15yr-report_root-copy_2026-10-19.pdf` | Raw input belongs with the other Maine files |
| `data/raw/state_month_panel_with_treatment.csv` (4,429 rows) | `data/raw/deprecated/state_month_panel_pre_me_court_extension_2026-10-19.csv` | Pre-splice backup; current file has 4,444 rows |
| `data/raw/monthly_expansion/me_fed_state_month_fyfixed.csv` | copy at `data/raw/monthly_expansion/deprecated/me_fed_state_month_fyfixed_pre_2026-10-19.csv` (original left in place, no longer written) | Superseded by `me_fed_state_month_ref20260918.csv` |
| `data_prep/add_me_to_state_panel.R` (2026-09-17, Jun–Dec relabel) | `data_prep/deprecated/add_me_to_state_panel_jun-dec-relabel_2026-09-17.R` | Script now reads the per-page-header parse with no relabel |


## 2026-10-19 — Public-repo cleanup and root tidy

Plan: `quality_reports/plans/2026-10-19_public-repo-cleanup.md`. The unpushed history of
`power-cs-arm-and-shift-mode` was rewritten with `git filter-repo` (origin/main untouched; pre-rewrite
backup branch `backup/pre-public-cleanup-2026-10-19`). Every stripped file is still on disk and is now
gitignored.

| Old path | New path | Why |
|---|---|---|
| `data/raw/ny_oca/oca_index.csv` (tracked) | same path, untracked; `data/raw/ny_oca/README.md` documents it | 494 MB public case-level NYC housing-court index; over GitHub's limit; unused |
| `ets_county_month.csv` (tracked) | same path, untracked | Eviction Lab internal extract, not for public release; scripts still read it here |
| `Literature/*.pdf` (tracked) | same path, untracked; `Literature/INDEX.md` lists them | Copyrighted papers |
| `Arnold Housing Loss Gambling - Application.docx`, `preanalysis plan v1.docx`, `preanalysis plan v1.1.docx`, `model gambling.docx`, `AV_Pre-Analysis_Plan_Guidance_202507.pdf` (root, tracked) | `private/` (gitignored) | Grant and PAP drafts, third-party guidance |
| `LP DiD Justification.docx`, `CO Court Website.png` (root, untracked) | `private/` | Private working documents |
| `A Crisis of Missed Opportunities.pdf`, `ghanem-et-al-2026-…pdf`, `roth-2022-…pdf`, `Robust Signal Maximization in Spillover Experiments.pdf` (root) | `Literature/` | Papers |
| `Table-of-Contents-for-Web-2025.pdf` | `data/raw/kansas/kansas_courts_annual_report_fy2025_toc.pdf` | Kansas Courts FY2025 annual report (public court document) |
| `lt-writ-data-2014-2019-by-circuit_0.pdf` | `data/raw/new_hampshire/lt-writ-data-2014-2019-by-circuit_0.pdf` | NH landlord/tenant writ source document |
| `County.csv`, `JusticeCivil_1336701014.csv` | `data/raw/misc/` (README there) | Unreferenced exports with unrecorded provenance |
| `County Court Data Methodology Report.md` | `docs/County Court Data Methodology Report.md` | Documentation belongs in docs/; references updated |
| `monthly_county_data_download.csv` (root copy, tracked) | `deprecated/root_cleanup_2026-10-19/monthly_county_data_download_root-copy.csv` | Stale copy of the 2026-09-17 bulk download; scripts read `data/raw/` |
| `monthly_county_data_download 9_17.csv`, `monthly_state_data_download 9_17.csv` | `deprecated/root_cleanup_2026-10-19/` | The 2026-09-17 LSC bulk downloads (stale; see CLAUDE.md hybrid box) |
| `WI/`, `2018CasesFiled.pdf`, `2019CasesFiled.pdf`, `Cluster-robust inference A guide to empirical practice.pdf` | `deprecated/root_cleanup_2026-10-19/` | Byte-identical copies of files already in `data/raw/monthly_expansion/{wi_raw,or_raw}/` and `Literature/` |
| `judicial_regime_assessment/` (root, untracked) | `deprecated/root_cleanup_2026-10-19/` | Stray output; the script writes to `output/judicial_regime_assessment/` |
| `Rplots.pdf`, `~$eanalysis plan v1.docx` | `deprecated/root_cleanup_2026-10-19/` | R device default output; Word lock file |
| compiled `*.o`, `tmp/`, `.claude/worktrees/` | untracked in place | Build artifacts and scratch |
