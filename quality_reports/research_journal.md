# Research Journal — Gambling and Eviction

### 2026-08-17 12:45 — coder (Sonnet 5)
**Phase:** Execution
**Target:** analysis/diagnostics/validate_shift_sufficiency.R (new)
**Score:** N/A (worker)
**Verdict:** Built shift-sufficiency validation harness against completed cheap-run partials; first run found deterministic-step exact, count_nb ramp/delayed discrepancies up to 0.21 under L=1 assumption.
**Report:** output/shift_validation/

### 2026-08-17 13:05 — coder-critic (Opus 4.8, round 1)
**Phase:** Execution (SEVERITY: HIGH)
**Target:** analysis/diagnostics/validate_shift_sufficiency.R
**Score:** 72/100 — below gate, strike 1
**Verdict:** Engine correct (df recovery an algebraic identity; delta=0 exact); interpretation conflated TWFE loading≠1 on non-constant shapes with mechanism noise. Required loading decomposition, paired-sample actual, wild-rule disclosure, NA-truth guard, MDE comparison.
**Report:** (inline agent report)

### 2026-08-17 13:20 — coder (Sonnet 5, round 2)
**Phase:** Execution
**Target:** analysis/diagnostics/validate_shift_sufficiency.R (revision)
**Score:** N/A (worker)
**Verdict:** All six fixes applied. L̂: twfe 0.746 (ramp) / 0.826 (delayed) vs did2s ≈1.02–1.04 on same reps — confirms loading artifact. Post-L̂ residuals 0.014–0.039; county headline MDE gaps +0.001 to +0.007.
**Report:** output/shift_validation/ (shift_vs_actual_power.csv, discrepancy_summary.csv, mde_comparison.csv)

### 2026-08-17 13:30 — coder-critic (Opus 4.8, round 2)
**Phase:** Execution (SEVERITY: HIGH)
**Target:** analysis/diagnostics/validate_shift_sufficiency.R
**Score:** 83/100 — PASSES 80 gate
**Verdict:** All fixes verified against code and regenerated CSVs. Defensible conclusion: shift mode exact for delta=0 size gate; county headline power reproduced to 0.03 points, MDE to within 0.005. Advisory (non-blocking): per-delta L̂ diagnostic; mde_actual on paired sample; MDE coverage note (3/15 cells).
**Report:** (inline agent report)

### 2026-08-17 18:15 — coder (Sonnet 5) + coder-critic (Opus 4.8), rounds 1-3
**Phase:** Execution (SEVERITY: HIGH)
**Target:** shift mode — R/power/{run_scenario_grid,config,summarize_operating_characteristics}.R, tests/testthat/test-shift-mode.R
**Score:** 52 → 71 → **93/100 (CLEARED, no escalation)**
**Verdict:** delta-grid shortcut implemented and validated. Blockers fixed across rounds: pooled loading replaced by per-delta fit (removed a 6-20% MDE bias); wild-arm NA-p corruption (deflated believable_share ~10x, incompatible mde/mde_ci rules) fixed via level-gated CI-membership fallback; non-atomic partial rewrite made atomic. 5.5x estimator saving; delta=0 size gate provably unaffected.
**Report:** docs/methodology/POWER_SIMULATION_DESIGN.md §16b

### 2026-08-19 09:45 — Fable (overnight autonomous) + Opus (reviewer x2)
**Phase:** Execution
**Target:** R/power/adaptive_mde.R; output_blinded_power/county_cs_adaptive/
**Score:** Opus production gate: no unresolved CRITICAL/MAJOR
**Verdict:** County CS: analytic invalid (61.2% size); boot arms size-valid but flat power
curve → never_crosses_target; no finite CS MDE on the pre-registered grid; CS eliminated
on power. Report: quality_reports/adaptive_cs_mde_report_2026-08-19.md
**Report:** quality_reports/adaptive_sim_overnight_log.md

### 2026-08-19 10:30 — Fable (coder+analyst)
**Phase:** Execution
**Target:** config/power_postcovid_maturation.yml; R/power/run_estimators.R (bjs)
**Score:** N/A (diagnostic run)
**Verdict:** Post-COVID maturation-market power: gate-passing MDEs 28–31% (lpdid/twfe/did2s);
BJS disqualified on size (27–29%, SE/SD 0.55) in both blocks; maturation vs legalization
treatment ≈ power-neutral. Memo: quality_reports/postcovid_maturation_power_memo_2026-08-19.md
**Report:** quality_reports/postcovid_maturation_power_memo_2026-08-19.md

### 2026-08-19 11:45 — Fable (coder+analyst)
**Phase:** Execution
**Target:** county post-COVID power; lpdid_wild plumbing
**Score:** N/A (diagnostic run)
**Verdict:** County analytic arms all fail size (did2s 22–24%, lpdid 12–14%); lpdid wild
exactly nominal (5.0%/4.7%) → valid county post-COVID MDE-80: 23.9% legalization /
31.7% maturation-only. County does not rescue post-COVID power; did2s disqualified there.
**Report:** quality_reports/postcovid_maturation_power_memo_2026-08-19.md

### 2026-08-19 12:15 — Fable (diagnostic)
**Phase:** Execution
**Target:** analysis/diagnostics/nevertreated_trends_pre_post_covid.R (+ rerun of covid_global_pt_diagnostic.R)
**Score:** N/A (descriptive diagnostic, real untreated data)
**Verdict:** Never-treated state effects shift SD 0.47 log pts across COVID, but placebo splits
show SD 0.42 (pre) / 0.30 (post) — drift is generic, COVID adds modestly; post-COVID segment is
the most stable. Supports "global PT more tolerable post-COVID" for did2s; ID pre-trend (+85%/yr)
is a likely data artifact worth a control-set robustness check.
**Report:** output/covid_global_pt/

### 2026-08-19 13:00 — Fable (strategist sketch)
**Phase:** Strategy
**Target:** quality_reports/strategy_memo_fourq_dose_response.md
**Score:** N/A (sketch, not yet critic-reviewed)
**Verdict:** Four-quarters (NY Fed) dose-response spec sketched for the spliced window:
tercile-contrast primary + continuous-slope secondary; dose vector built
(data/processed/fourq_dose_per_adult.csv, 22 states, IQR $26-69/adult-mo). Key threat:
dose is strongly increasing in launch date (singleton cohorts → no within-cohort dose
contrast); mitigations + placebo specified. Power-validation plan uses a new dose_step
shape with the realized dose vector — requires a documented blindness-protocol amendment.
**Report:** quality_reports/strategy_memo_fourq_dose_response.md

### 2026-08-19 13:45 — Fable (gates)
**Phase:** Execution
**Target:** output_blinded_power/dose_tercile_gates/ (config power_dose_tercile_gates.yml)
**Score:** N/A (size gates)
**Verdict:** Dose-spec gates: lpdid-wild PASSES all three designs (pooled 3.7%, T3 3.0%,
T1 5.7%); every analytic arm fails the tercile subdesigns; did2s analytic fails even the
pooled county spliced design (13.6%, SE/SD 0.63, 300 reps) — contradicts the 50-rep smoke
(4.1%), needs re-verification before the PAP repeats the "did2s calibrated county" claim.
New framework axis: exclude_states (hashed, tested).
**Report:** quality_reports/strategy_memo_fourq_dose_response.md (§6.2 addendum)

### 2026-08-19 16:15 — Fable (framework + calibration)
**Phase:** Execution
**Target:** R/power/load_blinded_panel.R (time_agg, complete_periods_only); config/power_time_agg_covid_gates.yml
**Score:** N/A (size gates, 6/13 complete)
**Verdict:** NEGATIVE result for the singleton-cohort hypothesis: aggregation collapses
cohorts 21→7 but CS size worsens (18.3%→24.7% annual). COVID splice dominates — monthly
post-COVID CS passes the gate (5.0/6.0/3.3%) for the first time. LP-DiD 0/300 at coarse
aggregation. Spliced + complete-periods = D1-infeasible.
**Report:** quality_reports/time_agg_covid_calibration_memo_2026-08-19.md

### 2026-08-20 01:30 — data-engineer
**Phase:** Execution
**Target:** NC eviction coverage gap (ETS ends 2023-06; online betting starts 2024-03)
**Score:** N/A
**Verdict:** Extended NC to 2026-06 from NC AOC Civil Issue Filings (SUME), validated at corr 1.0000 vs ETS over 90 overlap months. NC goes from 0 rows in the rebuilt state panel to 126 months with 28 treated. Only NC changed; existing rows byte-identical.
**Report:** SESSION_REPORT.md entry 2026-08-20 01:30

### 2026-08-21 10:15 — coder (direct, no agent dispatch)
**Phase:** Execution (diagnostic)
**Target:** `analysis/diagnostics/adoption_selection_levels_slopes.R`
**Score:** N/A (diagnostic)
**Verdict:** Gambling legalization timing is unrelated to pre-legalization eviction SLOPES on both substrates (24 tests, none significant, signs flip). The recurring LEVEL association (adopters higher, adopt sooner) collapses once log(renters) enters the Cox model — it is state size, not eviction risk. Cross-state levels are also court-practice contaminated (MD = 852 filings/1k renters).
**Report:** `output/adoption_selection/` (selection_tests.csv, cox_with_size_control.csv, adoption_timing_vs_pretrend.png, run_log.txt)

### 2026-08-21 10:35 — Coder (L-DAM estimator implementation)
**Phase:** Execution
**Target:** R/power/run_estimators.R (.re_ldam), config/power_ldam_gate{,_postcovid,_keepcovid}.yml, tests/testthat/test-estimators.R
**Score:** tests 44/44 PASS
**Verdict:** L-DAM (Antonelli et al. AOAS 2026, debiased linear autoregression) wired into the blinded framework as profiled NLS (Proposition 1 objective; optimize over theta, one feols per evaluation). The naive fixed-point iteration (theta <- coef(A) given adjusted lag) is provably NOT the paper's estimator and was badly biased toward zero at beta ~ 0.97 — caught by the unit-FE toy test; do not reintroduce it. Two inference arms: analytic (conditions on theta-hat; smoke run shows it ~7x smaller than jack on the real skeleton) and delete-one-state jackknife over the full profiled NLS. Three size-gate configs launched (covid: drop / post / keep; 300 reps, base_seed 20260723, twfe+did2s+lpdid alongside for rep-paired comparison).
**Report:** quality_reports/plans/2026-08-21_ldam-estimator-size-gate.md

### 2026-08-21 11:40 — coder (direct)
**Phase:** Execution (diagnostic)
**Target:** `analysis/diagnostics/adoption_predictability_prepaspa.R`
**Score:** N/A (diagnostic)
**Verdict:** Adoption and adoption timing are essentially UNPREDICTABLE from pre-repeal covariates. Best CV AUC for ever-adopt 0.60 vs permutation null 0.49 (p=0.16); CV R-squared for timing NEGATIVE in every model; Cox concordance sits on the null (p>=0.47). Only 2016-17 mortgage 90+ delinquency shows out-of-sample skill (CV AUC 0.689, p=0.008, the only positive Brier skill anywhere) — and it is a judicial-foreclosure/region proxy (NJ NY DE CT MD RI high & early; ND SD ID AK NE MN UT low & never). Eviction level/slope add NOTHING: macro-only 0.600 -> macro+eviction 0.574.
**Two corrections made this session:** (1) schedule-CSV join was deleting 13 genuine never-adopters (absent rows, not NA rows) — substrate A goes 29 -> 41 states and the earlier level contrast weakens from +0.64 to +0.24 log points; (2) LOO AUC is structurally biased toward 0 at this N (training base rate moves against the held-out outcome) — replaced with repeated stratified 5-fold CV, which restores a ~0.49 null.
**Report:** `output/adoption_predictability/`

### 2026-08-21 12:55 — coder (direct)
**Phase:** Execution (infrastructure + audit)
**Target:** `utils/eviction_treatment_schedule.R`, `docs/methodology/ADOPTION_UNIVERSE_AUDIT.md`, `CLAUDE.md`
**Score:** N/A
**Verdict:** Hard-coded the adoption universe and the Nevada exception in the shared utility (`EVICTION_STATE_UNIVERSE`, `PRE_PASPA_SPORTS_BETTING`, `eviction_adoption_outcomes()`, `eviction_control_states()`, `assert_no_pre_paspa_controls()`); della copy synced. Audited all 81 first-party schedule-referencing scripts by tracing data paths, not filenames. The absent-row trap was live in exactly ONE script (my own selection diagnostic, fixed); the prevailing `setdiff(panel_states, ever)` idiom is safe. The Nevada defect is the wider one: NV is in the never-treated pool of the 2x2 pseudo-power, the 2x2 selection placebo, era-variance, and the STATE blinded-power cells. Verified immune: all county-download work (NV absent from the file) and all balanced-panel work (NV has 46 non-COVID months vs a 91-month threshold, so it drops).
**Report:** `docs/methodology/ADOPTION_UNIVERSE_AUDIT.md`

### 2026-08-21 14:10 — coder (direct)
**Phase:** Execution (diagnostic)
**Target:** `analysis/diagnostics/adoption_predictability_institutions.R`, `utils/cv_predictability.R`, `docs/methodology/ADOPTION_PREDICTORS_FEASIBILITY.md`
**Score:** N/A
**Verdict:** The premise's antecedent is NOT met on timing. Region predicts WHETHER a state adopted (CV AUC 0.676, p=0.008, the only positive Brier skill) but NOTHING predicts WHEN: every block — region, pre-PASPA ideology, macro, eviction — has negative CV R-squared on months-to-adoption and sits on its permutation null for Cox concordance. Pre-PASPA ideology (Berry et al. 1991) is weak even on the ever margin (0.561, p=0.249). Orthogonality is imperfect: ideo_govt x ev_slope r=0.291 (p=0.069) and reg_West x ev_slope r=-0.343 (p=0.030), so "assignment runs on institutions" would not by itself imply independence from eviction trends. Six of eight requested blocks are not in the workspace and were NOT fabricated; acquisition targets documented with sources.
**Report:** `output/adoption_predictability_institutions/`

### 2026-08-21 12:25 — coder (direct, no subagent)
**Phase:** Execution / diagnostics
**Target:** post-COVID window boundary + anticipation exclusion
**Score:** N/A (diagnostic)
**Verdict:** Median state stabilization 2022-07, but stabilization (within-state) is not parallel trends (cross-state) — later boundary is NOT more stable. Real lever is the 6-month blindness anticipation buffer: A=0 raises treated clusters 7->12 at the current boundary and is already pre-registered (protocol §4).
**Report:** output/eviction_stabilization/, output/covid_global_pt/postcovid_boundary_fixedlen.csv, output_blinded_power/boundary_A_2021_08/

### 2026-08-21 15:30 — coder (direct)
**Phase:** Execution (data acquisition + diagnostic)
**Target:** `data_prep/build_gambling_institutions_prepaspa.R`, `analysis/diagnostics/adoption_predictability_institutions.R`, `utils/cv_predictability.R`
**Score:** N/A
**Verdict:** RESULT REVERSED for the timing model, on two counts. (1) Acquired real pre-PASPA lottery and commercial-casino data from external sources (provenance: `data/raw/gambling_institutions/SOURCES.md`). (2) Found and fixed a bug in the Cox permutation null — it re-ran the model on UNPERMUTED data, so every Cox p-value reported earlier this session was a non-test centred on the observed value. With both fixes: **pre-PASPA lottery maturity predicts the adoption hazard strongly, C = 0.699 vs null 0.470, p < 0.001**, and ever-adoption at CV AUC 0.800, Brier skill +0.287 — the strongest predictor found anywhere in this project. Casino authorization predicts NOTHING (C = 0.517, p = 0.224). Eviction history predicts nothing on any margin (C = 0.446, p = 0.712). Timing CONDITIONAL on adopting remains unpredictable (all CV R-squared <= 0.001).
**Report:** `output/adoption_predictability_institutions/`

### 2026-08-21 16:20 — coder (direct)
**Phase:** Execution (pretrends)
**Target:** `analysis/pretrends/pretrends_statepanel_template.R`, `output/pretrends_lottery_{A,B,C}*`
**Score:** N/A
**Verdict:** Added COVARIATES conditioning to the pretrends template and re-ran. Baseline ATT is **+0.020 (SE 0.057)**, NOT the saved +0.080 — that was the documented g/Inf never-treated-dropping bug. Conditioning on lottery vintage CONTINUOUS is harmful and must not be used: max abs pre-ATT 0.069 -> 0.231, ATT SE 0.057 -> 0.128, with the damage concentrated at e=-2/-1 where control pools are thinnest. Conditioning on the BINARY lottery indicator is stable (mean abs pre-ATT identical at 0.0285, ATT +0.048, SE 0.055). No detectable effect under any of the three specs.
**Report:** `output/pretrends_lottery_A_baseline`, `_B_conditional`, `_C_binary`

### 2026-08-21 17:45 — coder (direct)
**Phase:** Execution (NV re-runs)
**Target:** three longdiff diagnostics + `R/power/load_blinded_panel.R`
**Score:** N/A
**Verdict:** 2x2 pseudo-power MDE-80 unchanged (0.241 -> 0.2401); selection placebo holds and gets cleaner (tau -1.4% -> -0.30%, RI p 0.976); era-variance ratios drop materially (median 2.67 -> 2.04, strict set 3.86 -> 2.73) because NV was the outlier inflating post-era sigma; state power cells are NOT re-runnable — excluding NV makes D1 structurally infeasible (3,600/3,600 rep failures). Audit correction: `never_treated` is read only in the D4 branch and all state configs are D1, so no completed run consumed it; NV's actual route was as an unassigned D1 control in the S2 panel.
**Report:** `output/longdiff_2x2_pseudo/`, `output/longdiff_2x2_selection/`, `output/longdiff_era_variance/`, `output_blinded_power/boundary_A0_noNV_2021_08/failures.csv`

### 2026-08-21 18:40 — coder (direct)
**Phase:** Execution (audit sweep)
**Target:** `docs/methodology/ADOPTION_UNIVERSE_AUDIT.md` (addendum), CLAUDE.md
**Score:** N/A
**Verdict:** Swept 102 output CSVs + all data substrates for NV. Two estimation samples missed by the first audit: the **TWFE staggered power sim (MDE=5% claim)**, where NV is one of the 16 never-treated, and the **mortgage delinquency pretrends** (one of 27 never-treated). Mechanism: `combined_monthly_panel.csv` carries a state-level NV series as lowercase `nevada` with NO fips, entering via `build_state_panel()`'s state fallback; a fips/case-sensitive check misses it, and `fips 05099` = Nevada County, Arkansas is a false positive. Magnitude measured and non-uniform: era variance large, state D1 fatal, LOO influence small (TWFE 0.51%/SunAb 3.81%), 2x2 negligible.
**Report:** `docs/methodology/ADOPTION_UNIVERSE_AUDIT.md`

### 2026-08-21 19:20 — coder (direct)
**Phase:** Execution (LP-DiD NV audit + re-run)
**Target:** `config/power_lpdid_ramp75_mde_noNV.yml`, `output_blinded_power/lpdid_ramp75_mde_noNV/`
**Score:** N/A
**Verdict:** All 9 state-level LP-DiD/LDAM power configs are NV-contaminated; the only NV-free arm (county) was abandoned mid-run on 2026-08-17 with no summary. Paired re-run of the headline ramp75 cell shows NV was HURTING the result: spliced LP-DiD analytic MDE 0.0733 -> 0.0597, wild 0.0933 -> 0.0707, SE/SD 0.860 -> 0.979, size unchanged 0.063. TWFE spliced MDE 0.1269 -> 0.0797. On postcovid, TWFE size degrades 0.040 -> 0.097 and now FAILS the gate — NV was masking its miscalibration. Also corrected an over-generalization: state D1 is feasible without NV (40/40); the 3,600/3,600 failure was specific to the boundary_A0 cell.
**Report:** `output_blinded_power/lpdid_ramp75_mde_noNV/`

### 2026-08-21 20:05 — coder (direct)
**Phase:** Execution (NV-free LP-DiD queue)
**Target:** `config/power_*_noNV.yml` (8), `config/power_*_newpanel.yml` (3)
**Score:** N/A
**Verdict:** Queued 7 NV-free gates then the MDE curve. Gate 1 (lpdid_gate) completed in 16.6 min, but its comparison is INVALID: the with-NV baseline dates from 2026-08-15 and reports 38 clusters against the current panel's 33 — it predates the 2026-08-20 state-panel rebuild. Three baselines are pre-rebuild (lpdid_gate, lpdid_gate_postcovid, lpdid_mde) and need with-NV re-runs on the current panel under fresh run_names, because scenario ids hash settings not data, so a plain resume would reuse stale partials. The 2026-08-21 ramp75 MDE comparison IS valid (both arms post-rebuild, 33 vs 32 clusters) and stands.
**Report:** `/tmp/nv_queue.log`, `output_blinded_power/lpdid_gate_noNV/`

### 2026-08-21 20:50 — coder (direct)
**Phase:** Execution (diagnostic)
**Target:** `data/processed/ramp75_schedule.csv` vs LSR handle vintage
**Score:** N/A
**Verdict:** **ramp75 is a data-vintage artifact.** The ramp75 lag past online launch correlates **0.957** with how many months of post-launch handle we happen to observe (slope 0.257 months of lag per month of observation, t=17.4). Median lag by observation window: <2yr -> 0.0mo, 2-4yr -> 10.1, 4-6yr -> 18.0, 6yr+ -> 22.0. Mechanism: "75% of peak" uses peak = MAX OBSERVED handle, so longer observation raises the peak and pushes the crossing later. Because observation length is a deterministic function of launch date, ramp75 redates early cohorts later and late cohorts earlier — contaminating event time along exactly the cohort dimension a staggered DiD identifies off. Also a blindness violation: handle is post-treatment and outcome-adjacent. No shift12 MDE exists; `load_blinded_panel` does not accept shift12 as a treat_def.
**Report:** this entry

### 2026-08-21 21:30 — coder (direct)
**Phase:** Execution (NV-free LP-DiD queue complete)
**Target:** 7 gate runs + `lpdid_mde_noNV`
**Score:** N/A
**Verdict:** Queue A complete (queue died at exit 144 during the last scenario; resumed, spliced partial survived). **Correction: the state LP-DiD MDE is 0.0707 (wild), not 0.0597 (analytic)** — pooling gate+MDE runs (600 reps) the ramp75 spliced analytic size is 0.0733 with CI [0.054, 0.097], straddling 0.075, so analytic is unclassifiable; wild is 0.0367 CI [0.023, 0.055] and passes decisively. 300 reps cannot classify a borderline cell (MC SE 0.0147) — the identical ramp75 config returned 0.083 (gate) and 0.063 (MDE) as independent draws. online_start_date LP-DiD fails size everywhere (0.103 spliced) with an artifactually low MDE 0.0487. LDAM analytic is catastrophically miscalibrated (size 0.67-0.71, SE/SD 0.18-0.27); LDAM+jackknife passes.
**Report:** `output_blinded_power/*_noNV/`

### 2026-08-21 22:15 — coder (direct)
**Phase:** Execution (shift12 test)
**Target:** `data_prep/build_shift12_schedule.R`, `R/power/load_blinded_panel.R`, `config/power_lpdid_shift12_{gate,mde}_noNV.yml`
**Score:** N/A
**Verdict:** **shift12 dominates ramp75.** Gate at 2,000 reps NV-free: LP-DiD wild size 0.0580 CI [0.0482, 0.0692] PASS; MDE 0.0628 vs ramp75's 0.0707. Also passes the post-COVID cell (0.053/0.040) where ramp75 analytic was borderline. Answers the design question: raw online LP-DiD fails size (0.103) while BOTH lagged defs pass under wild — so ramp75's advantage is the LAG, not the handle-based timing, and shift12 gets it without any outcome data. Recommended state spec: shift12 + LP-DiD + wild, spliced, NV-free, MDE 6.3%.
**Report:** `output_blinded_power/lpdid_shift12_{gate,mde}_noNV/`
