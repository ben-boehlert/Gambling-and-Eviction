# FINDINGS.md — Current Truth

Curated, current-state-only. No history, no superseded numbers, no corrections narrative — those live in `RUN_LEDGER.md` and `docs/findings-archive/`. Every number below is checked against a primary artifact (output CSV or `quality_reports/` memo), not just against CLAUDE.md prose; artifact paths are given inline.

---

## 1. Headline Answers

- **No detectable effect of online sports-gambling legalization on eviction filings.** The current pretrends baseline (26 states, 17 treated / 9 never-treated) puts the overall CS-DiD ATT at **+0.020 log points (SE 0.057)** — not significant, and parallel trends is not rejected (joint Holm p = 0.170). [`output/pretrends_lottery_A_baseline/pretrends_summary.csv`]
- **The best state-level bound**, from the size-gate-first PAP decision rule, is an **MDE of 8.75% (vwatt) to 11.5% (ewatt), both wild bootstrap**, depending on which estimand the PAP commits to — see §2. Neither figure supports ruling out effects in the 5–10% range that the credit literature reports.
- **At county level, the calibrated workhorse is did2s (Gardner)** — well-calibrated (4% Type I, SE/SD 0.97) — while **CS-DiD is eliminated on power**: it has no finite MDE on the pre-registered grid (power curve is flat, never crosses the 80% target even at δ=0.20). [`output_blinded_power/county_cs_adaptive/size_gate.csv`, `mde_adaptive.csv`]
- **The one point estimate suggesting a possible effect**: county-level did2s restricted to pre-COVID-treated cohorts, NH excluded (a documented data artifact), gives **+9.1%** (coefficient +0.087, SE 0.045; 95% CI −0.001 to +0.175 **log points**, i.e. ≈ −0.1% to +19.1% in filings — the source memo's "+17.5%" upper bound is the raw log endpoint read as a percent) — borderline significant, and directionally consistent with Hollenbeck et al. (2025)'s credit-outcome findings. This is a robustness/exploratory result, not the pre-registered headline. [`output/border_diagnostic/HANDOFF.md`, Phase 7 table]
- Both readings are true at once: **the pooled/PAP-style test finds nothing, and a cohort-disaggregated exploratory cut finds a borderline-positive signal in 8 of 13 individual state cohorts** (+6% to +12% range). Neither dominates; report both.

---

## 2. PAP Decision Table (State-Level, Shift12, NV-Free, Spliced Window)

Decision rule: **size gate first** (any estimator whose null rejection rate is materially off 5% is disqualified), then MDE among survivors picks the spec.

| Arm | Size (2,000 reps, δ=0) | SE/SD | MDE (300 reps) | Estimand |
|---|---:|---:|---:|---|
| LP-DiD **vwatt** + wild | 0.0515 PASS | 1.14 | **0.0875** (CI 8.3–9.1%) | variance-weighted (Cengiz-style stack) |
| LP-DiD **ewatt** + wild | 0.0325 PASS | 0.67 | 0.115 | equally-weighted ATT (= CS's estimand) |
| TWFE analytic | 0.0495 PASS | 1.02–1.04 | 0.163–0.165 | TWFE pooled |
| LP-DiD ewatt analytic | 0.145 FAIL | 0.67 | n/a — fails gate | — |
| LP-DiD vwatt analytic | 0.097 borderline/fail | — | 0.075 (don't lead with it) | — |

Source: [`output_blinded_power/lpdid_shift12_gate_ewatt/oc_summary.csv`, `lpdid_shift12_gate_vwatt/oc_summary.csv`, `lpdid_shift12_mde_ewatt/mde_table.csv`, `lpdid_shift12_mde_vwatt/mde_table.csv`].

**Postcovid window (no COVID splice) is much weaker for both LP-DiD arms**: ewatt wild MDE 0.240, vwatt wild MDE 0.368 — the postcovid design simply has a much thinner (7 treated / 7 control) sample. [same files]

**Recommended state spec**: LP-DiD **vwatt + wild bootstrap, spliced window, NV excluded — MDE 8.75%**, if the PAP wants the tightest size-valid bound; **ewatt + wild — MDE 11.5%** if the PAP wants the estimand that matches CS/the credit literature exactly (both are honest, size-valid choices; pick by which estimand the PAP wants to defend).

**County verdict**: did2s is the calibrated workhorse (4% Type I, SE/SD 0.97 under the null — [`output/border_diagnostic/cs_calibration_multi_county/calibration_summary.csv`]). **CS-DiD is eliminated on power at county level**: analytic fails size (61.2% rejection vs 5% nominal), and the two size-valid bootstrap arms (boot 4.4%, boot_t 3.2%) have a power curve that is flat at ~5–7% all the way to δ=0.20 — no finite MDE exists on the pre-registered grid. [`output_blinded_power/county_cs_adaptive/size_gate.csv`, `mde_adaptive.csv`]

---

## 3. Pretrends Baseline

Panel: **26 states (17 treated, 9 never-treated), 16 cohorts, 91 months (2016–2024, COVID window 2020-03 to 2021-07 dropped), 2,366 obs.** Source: `data/raw/state_month_panel_with_treatment.csv` + repaired `sports_gambling_legalization_dates.csv`. [`output/pretrends_lottery_A_baseline/README.md`]

| Spec | CS ATT | SE | Joint pre-trend p (Holm) | Mean \|pre-ATT\| | Max \|pre-ATT\| |
|---|---:|---:|---:|---:|---:|
| A — unconditional | **+0.020** | 0.057 | 0.170 | 0.0285 | 0.0689 |
| B — conditional, lottery vintage (continuous) | +0.136 | 0.128 | 0.449 | 0.0602 | 0.2308 |
| C — conditional, lottery legal (binary) | +0.048 | 0.055 | 0.914 | 0.0285 | 0.0648 |

Source: `output/pretrends_lottery_{A_baseline,B_conditional,C_binary}/pretrends_summary.csv`.

Parallel trends is not rejected in any of the three specs. **Do not condition on lottery vintage as a continuous covariate** — spec B's SE inflation is concentrated at the two thinnest-control-pool event times (e = −2, −1) and is not a general problem with conditioning; the binary spec (C) conditions stably (identical mean \|pre-ATT\| to the unconditional baseline) and is preferred over B if conditioning is used at all.

---

## 4. Estimator Calibration Verdicts

| Estimator | Level | Inference | Size (target 5%) | SE/SD | Verdict |
|---|---|---|---:|---:|---|
| TWFE | county | analytic | 8% | 0.95 | mildly anti-conservative; wild bootstrap recommended |
| did2s (Gardner) | county | analytic | **4%** | **0.97** | **calibrated — recommended workhorse** |
| didimputation (BJS) | county | analytic | 14% | 0.73 | usable as robustness only |
| Sun-Abraham | county | analytic | 30% | 0.51 | broken — skip |
| CS analytic | county | analytic | 0% | 2.46 | over-corrects — skip |
| CS | county | boot / boot_t | **4.4% / 3.2%** | ~1.74 (uncalibrated) | size-valid but power curve flat — no finite MDE |
| LDAM | state | analytic | 57–70% (3 windows) | 0.18–0.27 | catastrophically miscalibrated — never quote |
| LDAM | state | jackknife | 1.0–3.7% (3 windows) | ~0.98–1.25 | **passes — use jackknife inference only** |
| LP-DiD (ewatt) | state | wild | 3.3% (spliced) | 0.67 | passes — SEs run small; wild bootstrap is what rescues size |
| LP-DiD (vwatt) | state | wild | 5.2% (spliced) | 1.14 | passes |
| TWFE | state | analytic | 5.0% (spliced) | 1.02–1.04 | passes |

Sources: county multi-estimator calibration `output/border_diagnostic/cs_calibration_multi_county/calibration_summary.csv`; CS adaptive `output_blinded_power/county_cs_adaptive/size_gate.csv`; LDAM `output_blinded_power/ldam_gate_noNV/oc_summary.csv`, `ldam_gate_keepcovid_noNV/oc_summary.csv`, `ldam_gate_postcovid_noNV/oc_summary.csv`; LP-DiD/TWFE state `output_blinded_power/lpdid_shift12_gate_{ewatt,vwatt}/oc_summary.csv`.

---

## 5. Standing Design Facts & Traps

- **The COVID splice breaks CS-DiD's contiguity assumption.** `att_gt` receives a consecutive rank index that treats the month before and after the COVID gap as adjacent — this is independent of estimator, and generalizes: CS calibration is far worse on spliced windows than on the clean post-COVID-only window (5.0% analytic size vs 18–25% on spliced/annual-aggregated windows).
- **NV must be excluded from every state-level control pool.** NV has legal sports betting since 1949 (pre-PASPA); it has no row in `sports_gambling_legalization_dates.csv` (absent, not NA) and is an always-treated state masquerading as a never-treated control. Use `utils/eviction_treatment_schedule.R`'s helpers — `EVICTION_STATE_UNIVERSE`, `PRE_PASPA_SPORTS_BETTING`, `eviction_adoption_outcomes()`, `eviction_control_states()`, `assert_no_pre_paspa_controls()` — do not re-derive the universe or the NV rule ad hoc. County-level work is immune (NV has no rows in `monthly_county_data_download.csv`).
- **Panel-era pairing rule.** The state panel was rebuilt 2026-08-20 ~01:26 to fix a 12-state double count. Never pair a pre-rebuild run (38 states — e.g. 23 treated / 15 never-treated in `lpdid_gate`'s metadata) with a post-rebuild run (33 states — 21 / 12 in `lpdid_mde_fixedpanel`) — a fresh `run_name` is required after any panel/schedule edit, since scenario ids hash settings, not data.
- **Basket-composition QA gate.** Every state-panel row now carries `n_counties` and `basket_share`; `data/processed/state_panel_coverage_qa.csv` grades each state's reporting-county composition stability. Censor the tail or fix the basket before citing any state-level long-difference or level estimate — composition churn (e.g., FL losing Miami-Dade/Lee at 2024-01, TX losing Harris at 2024-05) produces artifacts of up to ±1 log point.
- **`lpdid_weights` / `lpdid_pmd` knobs** (plumbed config → grid → spec → estimator): `lpdid_weights` is `ewatt` (default, equally-weighted ATT = CS's estimand) | `cellsize` (retired, dead estimand — pre-2026-08-24 default) | `vwatt` (variance-weighted, Cengiz-style stack). `lpdid_pmd` sets base-period width (default 3).
- **`cs_safe_patches` / `cs_faster_mode` flags** (`R/power/` CS runs). `cs_safe_patches: TRUE` is required to avoid uncatchable C-level process aborts from zero-row design matrices; `cs_faster_mode: FALSE` is required for CS to actually estimate on this design (the historical `TRUE` default failed on 100% of probed cells). Any pre-2026-08-17 CS run without both flags set correctly used a non-estimating code path and should not be cited.

---

## 6. Open Questions

- **Mortgage delinquency power sim**: `output/power_mortgage_delinquency/` exists and is complete, contradicting CLAUDE.md's own prose ("no formal power simulation exists for mortgage delinquency") — one of the two is stale; reconcile before citing either.
- **Mortgage pretrends NV re-run pending**: `output/deprecated/pretrends_mortgage_delinquency/` (moved in the 2026-08-25 cleanup) was flagged NV-affected (NV is necessarily in the 51-state, 27-never-treated mortgage panel) and is not in the completed NV re-run list — needs a fresh run before citing.
- **LDAM has no MDE run.** Only size-gate runs exist (`ldam_gate_noNV`, `ldam_gate_keepcovid_noNV`, `ldam_gate_postcovid_noNV`) — jackknife passes the gate but no MDE table has been produced under jackknife inference.
- **`boundary_B_2022_08` is an unfinalized partial** — 3,501-row partial CSV with a `.done_reps` marker, but no `oc_summary.csv`/`mde_table.csv`/`failures.csv`. Unclear whether abandoned or just never finalized.
- **TWFE staggered power sim (state-panel MDE = 5% claim) needs a re-run.** The saved run (`data/output/twfe_power_out_2024_with_me/`, 2026-07-23) is on the pre-schedule-repair treatment file (16 never-treated including ME/VT/KY/FL, which the repair moved to treated). The outcome data itself is county-sourced and not double-count contaminated, but the switcher/control composition has changed since this run and the MDE has not been recomputed against the repaired schedule. When re-running, also reconcile the PAP text: PAP §2.4 cites N = 2,867 state-months, which matches no saved run (current runs: 3,505 with ME / 3,397 without), and says the sample starts 2016-01 while the run panel starts 2012-01.

---

Maintained: update when a LIVE result changes; history lives in RUN_LEDGER.md and docs/findings-archive/.
