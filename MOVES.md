# MOVES.md — 2026-08-25 repo cleanup

Every artifact relocated by the cleanup, old → new. Classifications and evidence:
`quality_reports/cleanup_2026-08-25/inventory_*.md`; statuses: `RUN_LEDGER.md`.
Nothing was deleted. Reversal is `mv` back.

| old path | new path | reason |
|---|---|---|
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
