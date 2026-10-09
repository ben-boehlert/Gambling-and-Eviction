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

### 2026-08-25 12:35 — Orchestrator (repo cleanup)
**Phase:** Infrastructure
**Target:** RUN_LEDGER.md, FINDINGS.md, CLAUDE.md, MOVES.md, docs/findings-archive/
**Score:** Opus audit: 1 BLOCKER + 3 SHOULD-FIX + 6 NOTE, all resolved
**Verdict:** Repo reorganized around a run registry + current-truth doc; 124 artifacts deprecated by move; CLAUDE.md no longer accumulates findings
**Report:** quality_reports/cleanup_2026-08-25/ (inventories), quality_reports/plans/2026-08-25_repo-cleanup-run-ledger.md

### 2026-09-04 — coder (feasibility probe)
**Phase:** Execution
**Target:** clean-anchor LP-DiD on state mortgage delinquency
**Score:** N/A (no estimation performed)
**Verdict:** Design is runnable in levels, not in logs; the binding choice is the COVID splice (24 / 13 / 7 contributing switchers under keep / eviction-window / forbearance-extended). Forbearance-extended is not viable.
**Report:** `output/mortgage_lpdid_feasibility/`, script `analysis/diagnostics/mortgage_lpdid_feasibility_probe.R`

### 2026-09-06 22:54 — coder (parity harness)
**Phase:** Execution (pre-unblinding check)
**Target:** `analysis/main/lpdid_statepanel.R` vs `R/power/run_estimators.R::.re_lpdid` under the headline PAP config
**Score:** N/A (diagnostic)
**Verdict:** Estimator identical to machine precision on six simulated panels; the script's sample construction (max-coverage balancing, 2024-12 date cap, no exclusion knob) breaks the spec and must be changed before the real run. Pre-trend block is empty under shift12.
**Report:** `quality_reports/parity_check_lpdid_statepanel_2026-09-06.md`, `output/lpdid_statepanel_parity/`

### 2026-09-14 — session: panel audit + design review
**Phase:** Execution / Strategy (PAP design)
**Target:** state panel vintage, clean-anchor design, COVID window
**Score:** N/A (diagnostics + data build, no estimation)
**Verdict:** Panel rebuilt to a new 2026-09-14 vintage and Oregon added (switchers 13 -> 16, 40 states); three COVID-window alternatives tested and all rejected; eligibility window found mis-specified with 8 of 24 D1 cohort slots structurally impossible; 4 latent bugs fixed. 11 of my own intermediate conclusions were overturned and are logged — including the session's opening finding about which missing states are viable.
**Report:** quality_reports/session_2026-09-14_panel_audit_and_design_review.md

### 2026-09-14 — session: WA + MI panel addition
**Phase:** Execution (data build)
**Target:** `data/raw/state_month_panel_with_treatment.csv`
**Score:** N/A (panel construction + diagnostics, no estimation)
**Verdict:** Panel 40 → 42 states (WA = Tacoma/Pierce, never-treated control, 113 clean months; MI = JDW statewide, 68 of 89 months, NOT a clean-anchor switcher on either headline treat_def). Found and fixed a live defect: five extract-sourced series carried a partial final month, three of which were producing spurious non-COVID level breaks. County and state declared co-equal main specs; county arm untouched since neither new state is in LSC.
**Report:** docs/findings-archive/2026-09-14_wa-mi-panel-addition.md

### 2026-09-16 11:05 — sonnet-researcher
**Phase:** Peer Review (implementation audit)
**Target:** R/power LP-DiD engine + month restrictions under config/power_lpdid_clean_gate_ewatt_pmd6_v20260914.yml
**Score:** N/A
**Verdict:** 14-question line-cited code map; no contradictions with FINDINGS §5.
**Report:** quality_reports/lpdid_sim_implementation_review_2026-09-16.md

### 2026-09-16 11:05 — opus-reviewer
**Phase:** Peer Review (implementation audit)
**Target:** .re_lpdid() event_clean / ewatt / wild vs PI memo + Dube et al. (JAE 2025)
**Score:** A,B,C,F,G(√w) CORRECT; E,D,G(df),I CONCERN; H design decision
**Verdict:** Estimator and windows implemented as specified; recentering covers only α=0.05; analytic df counts all panel states; anticipation floor vs baseline placement is an unresolved estimand choice.
**Report:** quality_reports/lpdid_sim_implementation_review_2026-09-16.md

### 2026-09-16 11:54 — sonnet-executor
**Phase:** Execution (fix from implementation review item G)
**Target:** R/power/run_estimators.R .re_lpdid() analytic df; tests/testthat/test-estimators.R
**Score:** PASS (test-estimators 18/18, test-oc pass; test-grid has a pre-existing unrelated failure)
**Verdict:** Analytic t df now = contributing clusters − 1; regression test added; wild rows unchanged.
**Report:** docs/findings-archive/2026-09-16_lpdid-analytic-df-correction.md

### 2026-09-16 12:06 — orchestrator (Fable) diagnosis
**Phase:** Execution (debugging)
**Target:** tests/testthat/test-grid.R "exclude_states drops the states from the simulated panel"
**Score:** N/A (diagnosis only, no fix applied)
**Verdict:** Test reads an unconverged placement row; national template saturates the rebuilt panel (base 3/100 seeds fail, exclude-TX 43/100); bisect flips at fad95a6; headline configs (template: panel) unaffected.
**Report:** docs/findings-archive/2026-09-16_test-grid-exclude-states-failure.md

### 2026-09-16 12:20 — orchestrator (Fable) design diagnosis
**Phase:** Strategy (design review, blind-safe)
**Target:** county vs state LP-DiD arm; `analysis/diagnostics/county_vs_state_dispersion_decomposition.R`
**Score:** N/A (diagnostic)
**Verdict:** County arm's 24% tighter SD is implicit LSC-county-count reweighting of states (C 0.92x), not information (equal-state county means are 1.20x noisier); unweighted county ewatt is not a pre-registrable estimand.
**Report:** docs/findings-archive/2026-09-16_county-arm-renter-weights.md

### 2026-09-16 12:34 — coder (Fable) implementation
**Phase:** Execution
**Target:** R/power/run_estimators.R (`lpdid_unit_weights`, `.re_lpdid_wcr_weighted`), R/power/run_scenario_grid.R (knob + conditional hash), tests, config `power_lpdid_clean_gate_county_ewatt_pmd6_wild_rw_v20260914.yml`
**Score:** PASS (test-estimators 112/112; test-grid new knob test passes, 1 pre-existing unrelated failure)
**Verdict:** Renter weights added; exact weighted WCR reproduces boottest fe= (constant w) and dummy-expanded WLS (varying w) p-values to 1e-8. County rw gate (2,000 x 2) and post-rebuild state comparator (1,000 x 2) launched locally.
**Report:** docs/findings-archive/2026-09-16_county-arm-renter-weights.md

### 2026-09-16 13:30 — orchestrator (Fable) run results
**Phase:** Execution (blinded size gates)
**Target:** `lpdid_clean_gate_county_ewatt_pmd6_wild_rw_v20260914`, `lpdid_clean_gate_ewatt_pmd6_v20260914`, `_w126` twins
**Score:** PASS (0 failure rows in all runs)
**Verdict:** County renter-weighted wild gate passes size (0.011, conservative), null center −0.0005, SD 0.050; postcovid fails. State p42 comparator SD 0.063 under (18,0) vs 0.034 under (12,6) — the eligibility window, not the rebuild, is the noise source. FINDINGS §2/§5, ESTIMATOR_MATRIX §2, RUN_LEDGER updated.
**Report:** docs/findings-archive/2026-09-16_county-arm-renter-weights.md

### 2026-09-16 14:47 — coder (Fable) inclusion rule
**Phase:** Execution (design rule → code)
**Target:** R/power/inclusion_rule.R (new), make_pseudo_schedules.R (presence eligibility, cohort dropping, template_states), run_estimators.R (lpdid_min_horizons / excluded months), run_scenario_grid.R (knobs + hashes), analysis/main/lpdid_statepanel.R (MIN_HORIZONS / SPLICE_BUFFER parity), tests (+3 files), configs `_k7`
**Score:** PASS (inclusion-rule 18/18, schedules 26/26, estimators 120/120, grid: only the pre-existing exclude_states failure)
**Verdict:** Ben's rule (K = 7, 3-month splice buffer) implemented once and applied in placement, estimation, and the real-data script. 10 of 26 launched states qualify. Both k7 gates launched (state 1,000×2; county rw 2,000×2).
**Report:** docs/findings-archive/2026-09-16_county-arm-renter-weights.md (addendum pending results)

### 2026-09-16 17:05 — orchestrator (Fable) handoff
**Phase:** Execution → decision pending
**Target:** quality_reports/handoff_2026-09-16_county_arm_and_inclusion_rule.md
**Score:** N/A
**Verdict:** Session closed for context reset. Open decision: option A/B/C for placing the inclusion-rule design on the blinded panel (FINDINGS §5). Nothing committed past 9ab8741.
**Report:** quality_reports/handoff_2026-09-16_county_arm_and_inclusion_rule.md

### 2026-09-18 17:00 — Documentation sweep (orchestrator + 3 Sonnet readers)
**Phase:** Strategy / Execution (PAP design)
**Target:** FINDINGS.md, CLAUDE.md, ESTIMATOR_MATRIX.md, RUN_LEDGER.md
**Score:** N/A (documentation, no artifact scored)
**Verdict:** The 6–18 month outcome window, 3-month baseline and June 2022 sample start are now written into the docs as a RECOMMENDED-NOT-ADOPTED design switch, with the evidence, the honest caveats, and the decision Ben and Carl still owe. Estimator comparison (did2s/BJS/SunAb fail size; jackknife repairs it but erases their power advantage) recorded in ESTIMATOR_MATRIX §1. Two documentation gaps flagged in RUN_LEDGER: the TWFE weight diagnostic and the June-2022 justification both lack a committed script.
**Report:** SESSION_REPORT.md, entry 2026-09-18 17:00

### 2026-09-21 12:00 — Coder (simplified mode, no critic)
**Phase:** Execution (PAP power section)
**Target:** scripts/run_twfe_power_rerun_v20260921.sh, analysis/main/prep_twfe_power_rerun_inputs.R
**Score:** N/A
**Verdict:** Application-era naive TWFE power sim re-run on the boundary-11 panel, NV out, repaired schedule: MDE ≈ 3% under its original iid-by-month shocks, ≈ 6.5–7% under AR(1) (ρ = 0.721). The application's 5% was an artifact of erasing serial correlation and is not the Black et al. method; do not cite. EXPLORATORY.
**Report:** RUN_LEDGER.md §1 row `twfe_power_rerun_v20260921`; SESSION_REPORT.md entry 2026-09-21 12:00

### 2026-09-21 15:30 — Coder (simplified mode, no critic)
**Phase:** Execution (design diagnostic)
**Target:** analysis/diagnostics/idaho_ada_canyon_decomposition.R
**Score:** N/A
**Verdict:** Idaho's statewide drift is overwhelmingly Ada+Canyon (79% of 2021→2025 growth on 45% of the 2021 base; other 42 counties trend 3.7%/yr full-span and 0.9%/yr from 2022-06). But the accelerate-after-expiry prior is refuted and reversed: Ada's mean YoY growth falls 37.8% → 3.5% across the 2023-11 marker. The episode is bounded 2022-12..2023-10. Canyon tracking Ada argues Boise MSA, not an Ada-County-specific program. No design change; dropping the two counties would be selection on the realized outcome.
**Report:** RUN_LEDGER.md §4 row `idaho_ada_canyon_decomposition`; SESSION_REPORT.md entry 2026-09-21 15:30

### 2026-09-22 14:30 — coder (diagnostic)
**Phase:** Execution
**Target:** `analysis/diagnostics/lpdid_ri_post2022.R` — RI calibration of the post-June-2022 LP-DiD analytic SE
**Score:** N/A (diagnostic run)
**Verdict:** SE/SD 0.956 over 1,000 permutations; the analytic SE is calibrated in the real post-2022 era and the blinded precovid correction transfers. The `postcovid` arm's 0.67 is a 6-cluster artifact, not an era effect.
**Report:** `output/lpdid_ri_post2022/ri_summary.csv`; RUN_LEDGER.md §4

### 2026-09-29 — coder (Opus 5.5 executor)
**Phase:** Execution
**Target:** data_prep/bartik/build_bartik_cfpl_replication.R (CFPL Bartik replication)
**Score:** N/A (V1 check: reconciliation to Lutz's values)
**Verdict:** CBP bartik cor 0.994 (not exact; residual from suppressed-cell fill); QCEW bartik.qcew cor 0.916 (unresolved). Stats re-verified in main session.
**Report:** quality_reports/plans/2026-09-29_bartik_replication_cfpl.md

### 2026-09-29 — strategist-critic (round 1)
**Phase:** Strategy
**Target:** quality_reports/specs/2026-09-29_bartik_eviction_design_memo.md (v1; separate labor-demand/eviction paper)
**Score:** 68/100
**Verdict:** Revise: incomplete-shares control, no pre-period, LP shock persistence, AKM clustering, monthly zero-row misread. Data claims re-verified; v2 written.
**Report:** inline in session; v1 preserved in quality_reports/specs/deprecated/

### 2026-09-29 — strategist-critic (rounds 2–3)
**Phase:** Strategy
**Target:** quality_reports/specs/2026-09-29_bartik_eviction_design_memo.md (v2 → v3 → v3.1)
**Score:** 78/100 (v2), 81/100 (v3, PASS)
**Verdict:** Pass. Must-fix items applied in v3.1: gate (a) at NAICS-3 plus a max-weight cap, AKM0-based MDE, directional stacked housing-switch test, unconditional shock balance, raw-g sign split. Gate numbers still PROPOSED pending Ben.
**Report:** inline in session; prior versions in quality_reports/specs/deprecated/

### 2026-09-29 19:05 — coder (Opus 5.5) + opus-reviewer, Labor-Demand-and-Eviction repo
**Phase:** Execution (pre-estimation)
**Target:** ../Labor-Demand-and-Eviction: builds 02–06, analysis/code/01_gate.R, 02_power_comparison.R
**Score:** gate PASS (non-housing RF, all eras); opus-reviewer: no verdict flips, 7 fixes applied (2b57d4a)
**Verdict:** Era 1 is the credible headline (elasticity MDE about 1.0–1.3); Era 2 fails conditional balance; tradable switch inoperative
**Report:** quality_reports/handoff_2026-09-29_bartik_labor_demand.md

### 2026-10-09 — Main session (Fable 5.1) + 6 sonnet-researcher extractions
**Phase:** Discovery (literature)
**Target:** Hull (2026) TWFE-vs-modern reanalysis, applied as a printed-estimate comparison to the six sports-betting papers in `Literature/`
**Score:** N/A (EXPLORATORY extraction)
**Verdict:** 64 TWFE-vs-modern pairs across Baker, Guo, McCarthy, Arnesen (Hollenbeck and Goss & Mangrum print none): 1 sign reversal (null vs null), 13 independent-SE significant gaps, 10 of them a Baker clustering artifact; SE ratios 0.5–4.3, not comparable across papers. No paper varies the sample window, so nothing on COVID. ETWFE explained from Wooldridge (2021 WP) and Goss & Mangrum §4.2.
**Report:** `quality_reports/hull_style_gambling_lit_comparison_2026-10-09.md`, `quality_reports/hull_style_gambling_lit_pairs_2026-10-09.csv`, `analysis/exploratory/hull_style_lit_pairs.R`

### 2026-10-09 — main session (Fable 5.1)
**Phase:** Strategy (mortgage arm pre-analysis)
**Target:** `analysis/pretrends/pretrends_mortgage_twfe_controls.R`, `output/pretrends_mortgage3089_twfe_controls/`
**Score:** N/A
**Verdict:** 30–89 day TWFE pre-trends with the locked 2019 controls show a relative decline into launch on the spliced window, driven by post-COVID launchers; absent pre-COVID; controls do not remove it. Mortgage design still awaits four decisions and covariate support in the LP-DiD pipeline.
**Report:** RUN_LEDGER.md §5 row `pretrends_mortgage3089_twfe_controls`; FINDINGS.md §2
