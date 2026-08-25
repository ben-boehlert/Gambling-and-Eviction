# RUN_LEDGER.md — Registry of Every Analysis Run

**Purpose.** This is the single place to answer "has X been run, and can I cite it?"
It merges four verified inventories built 2026-08-25 — [`quality_reports/cleanup_2026-08-25/inventory_output.md`](quality_reports/cleanup_2026-08-25/inventory_output.md),
[`inventory_blinded_power.md`](quality_reports/cleanup_2026-08-25/inventory_blinded_power.md),
[`inventory_configs.md`](quality_reports/cleanup_2026-08-25/inventory_configs.md), and
[`run_history.md`](quality_reports/cleanup_2026-08-25/run_history.md) — into one navigable
document. It does not re-derive any classification; every status below traces to one of
those four files (or to root [`CLAUDE.md`](CLAUDE.md), which the inventories were checked
against). Full evidence for any row lives in the linked inventory file, not repeated here.

## Status vocabulary

| Status | Meaning |
|---|---|
| **LIVE** | Current best number for its question. Citable as-is. |
| **SUPERSEDED** | Valid when run, replaced by a later run. Points to its replacement — never delete the row. |
| **CONTAMINATED** | Invalid due to a specific, named bug or stale input (see boundary dates below). Not just old — wrong. |
| **DEAD** | The number itself is invalid (a bug in the computation), or the run never produced a usable result (empty/abandoned). |
| **EXPLORATORY** | Completed, not contaminated, but not a headline/decision-relevant number — descriptive, a probe, or a one-off diagnostic. |
| **UNKNOWN** | No producing script found, or genuinely ambiguous status. Flagged for human review, not guessed at. |

## The five vintage boundary dates

Nearly every contamination reason below reduces to "this ran before one of these fixes":

1. **2026-07-23** — NH + ME court-source repairs (before this, ME is excluded or carries a zero-fill artifact; NH carries a −57% coverage artifact).
2. **2026-08-10 ~16:16** — treatment-schedule repair (ME, VT, KY, FL, DE, NC, MO gained online-legalization dates; before this they are misclassified as never-treated).
3. **2026-08-20 ~01:26** — state-panel double-count rebuild (`state_month_panel_with_treatment.csv` had summed county totals + an overlapping ETS state series for 12 states). Only `level: state` runs are affected — county-download-based runs are immune.
4. **2026-08-21 ~10–17h** — Nevada-exclusion audit (`PRE_PASPA_SPORTS_BETTING`). NV is always-treated since 1949 and absent from the schedule CSV, so it silently sat in the never-treated control pool of state-level D1 designs until this fix.
5. **2026-08-24** — LP-DiD reweighting fix. The pre-fix default (`cellsize` weights) was neither of Dube-Girardi-Jordà-Taylor's two named estimands (EWATT, VWATT). Every `lpdid`-estimator row computed before this date is a dead estimand, even where the same run's TWFE/did2s/LDAM rows remain valid.

## THE MAINTENANCE RULE

> **Every completed run appends one row to the matching table before the session ends.
> A superseded row is never deleted — its status changes and points to its replacement.**

See [Adding a row](#adding-a-row) at the bottom for the template.

---

## LIVE summary — every current-best run, one screen

| Run | Domain | Establishes | Output path |
|---|---|---|---|
| `pretrends_lottery_A_baseline` | Pretrends | Current headline pretrends baseline: CS ATT +0.020 (SE 0.057), joint pre-trend p=0.170, unconditional, 26 states | [`output/pretrends_lottery_A_baseline/`](output/pretrends_lottery_A_baseline/) |
| `pretrends_lottery_B_conditional` | Pretrends | Continuous lottery-vintage conditioning: ATT +0.136 (SE 0.128) — thin-cell inflation at e=-2/-1, do not lead with this spec | [`output/pretrends_lottery_B_conditional/`](output/pretrends_lottery_B_conditional/) |
| `pretrends_lottery_C_binary` | Pretrends | Binary lottery conditioning: ATT +0.048 (SE 0.055), stable — recommended conditioning spec | [`output/pretrends_lottery_C_binary/`](output/pretrends_lottery_C_binary/) |
| `border_diagnostic` | Diagnostics | **Project headline eviction-filings result**: did2s pre-COVID drop-NH ATT = +9.1%, CI [−0.10%, +17.5%]; county-sourced, immune to all 5 boundary dates | [`output/border_diagnostic/`](output/border_diagnostic/) |
| `statepanel_double_count` | Diagnostics | The audit that discovered the state-panel double count (891/916 overlap state-months, exact, 12 states) | [`output/statepanel_double_count/`](output/statepanel_double_count/) |
| `adoption_predictability` | Diagnostics | Pre-PASPA lottery maturity predicts adoption hazard: C=0.699 vs null 0.470, p<0.001; ever-adopt AUC 0.800 | [`output/adoption_predictability/`](output/adoption_predictability/) |
| `adoption_predictability_institutions` | Diagnostics | Region predicts ever-adopt (AUC 0.676, p=0.008); casino authorization and eviction history predict nothing | [`output/adoption_predictability_institutions/`](output/adoption_predictability_institutions/) |
| `adoption_selection` | Diagnostics | Adopter-vs-never level gap shrinks +0.64 → +0.24 log points once state size and the full 51-state universe are used | [`output/adoption_selection/`](output/adoption_selection/) |
| `covid_global_pt` | Diagnostics | Active COVID-splice investigation feeding the time-aggregation findings | [`output/covid_global_pt/`](output/covid_global_pt/) |
| `longdiff_2x2_pseudo` | Diagnostics | 2×2 pseudo-treatment MDE-80 = 0.2401 (+27.1% filings), NV-free | [`output/longdiff_2x2_pseudo/`](output/longdiff_2x2_pseudo/) |
| `longdiff_2x2_selection` | Diagnostics | Selection placebo holds, NV-free: τ = −0.30%, RI p = 0.976 | [`output/longdiff_2x2_selection/`](output/longdiff_2x2_selection/) |
| `longdiff_era_variance` | Diagnostics | Era-variance inflation factor, NV-free: median post/pre σ ratio 2.04 (strict set 2.73) | [`output/longdiff_era_variance/`](output/longdiff_era_variance/) |
| `cheap_power_sim` | Diagnostics | State-month C&S long-difference design "not viable for plausible effect sizes" | [`output/cheap_power_sim/`](output/cheap_power_sim/) |
| `shift_validation` | Diagnostics | Shift-mode sufficiency validated for TWFE (max discrepancy ~0.04) | [`output/shift_validation/`](output/shift_validation/) |
| `market_maturation` | Exploratory | Handle quintile-timing table (20/40/60/80/100% of peak: 4.8/10.3/16.9/29.3/46.3 months) | [`output/market_maturation/`](output/market_maturation/) |
| `lpdid_cs_equivalence` | Calibration | LP-DiD≈CS equivalence holds to 2.2e-16 on contiguous/staggered panels, breaks (0.11) on an interior time gap | [`output/lpdid_cs_equivalence/`](output/lpdid_cs_equivalence/) |
| `lpdid_cs_equivalence_keep` | Calibration | Real-panel covid-keep-window companion to the equivalence result | [`output/lpdid_cs_equivalence_keep/`](output/lpdid_cs_equivalence_keep/) |
| `lpdid_weights_compare` | Calibration | Verification of the 2026-08-24 LP-DiD weighting fix (paired ewatt/vwatt/cellsize) | [`output/lpdid_weights_compare/`](output/lpdid_weights_compare/) |
| `lpdid_weights_compare_mde` | Calibration | MDE-arm companion to the weighting-fix verification | [`output/lpdid_weights_compare_mde/`](output/lpdid_weights_compare_mde/) |
| `county_cs_adaptive` | Blinded power | County CS verdict: analytic fails size (61.2%); boot/boot_t size-valid but power curve flat — **no defensible finite county CS MDE** | [`output_blinded_power/county_cs_adaptive/`](output_blinded_power/county_cs_adaptive/) |
| `time_agg_covid_gates` | Blinded power | The COVID splice, not cohort count, drives CS/did2s miscalibration; CS passes size on the clean post-COVID monthly window | [`output_blinded_power/time_agg_covid_gates/`](output_blinded_power/time_agg_covid_gates/) |
| `boundary_A0_noNV_2021_08` | Blinded power | State D1 is structurally infeasible without NV at the 2021-08/A=0 boundary cell (3,600/3,600 reps fail) | [`output_blinded_power/boundary_A0_noNV_2021_08/`](output_blinded_power/boundary_A0_noNV_2021_08/) |
| `ldam_gate_noNV` | Blinded power | LDAM spliced gate: analytic 0.70 FAIL, jackknife 0.037 PASS (SE/SD 1.01) | [`output_blinded_power/ldam_gate_noNV/`](output_blinded_power/ldam_gate_noNV/) |
| `ldam_gate_keepcovid_noNV` | Blinded power | LDAM keep-COVID gate: analytic 0.69 FAIL, jackknife 0.03 PASS (SE/SD 0.98) | [`output_blinded_power/ldam_gate_keepcovid_noNV/`](output_blinded_power/ldam_gate_keepcovid_noNV/) |
| `ldam_gate_postcovid_noNV` | Blinded power | LDAM postcovid gate: analytic 0.57 FAIL, jackknife 0.01 PASS (SE/SD 1.25) | [`output_blinded_power/ldam_gate_postcovid_noNV/`](output_blinded_power/ldam_gate_postcovid_noNV/) |
| `lpdid_shift12_gate_ewatt` | Blinded power | **Current PAP decision-table row**: shift12/EWATT/wild, spliced size 0.0325 PASS (analytic 0.145 FAIL) | [`output_blinded_power/lpdid_shift12_gate_ewatt/`](output_blinded_power/lpdid_shift12_gate_ewatt/) |
| `lpdid_shift12_gate_vwatt` | Blinded power | **Current PAP decision-table row**: shift12/VWATT/wild, both windows PASS (spliced 0.0515, postcovid 0.0615) | [`output_blinded_power/lpdid_shift12_gate_vwatt/`](output_blinded_power/lpdid_shift12_gate_vwatt/) |
| `lpdid_shift12_mde_ewatt` | Blinded power | **Current PAP headline MDE (EWATT)**: spliced wild MDE 0.115 (CI 10.2–12.5%) | [`output_blinded_power/lpdid_shift12_mde_ewatt/`](output_blinded_power/lpdid_shift12_mde_ewatt/) |
| `lpdid_shift12_mde_vwatt` | Blinded power | **Current PAP headline MDE (VWATT)**: spliced wild MDE 0.0875 (CI 8.3–9.1%) — best state MDE among size-valid arms | [`output_blinded_power/lpdid_shift12_mde_vwatt/`](output_blinded_power/lpdid_shift12_mde_vwatt/) |

29 LIVE rows total (19 from `output/`, 10 from `output_blinded_power/`).

---

## Domain tables

### 1. Blinded power sims

Source: [`inventory_blinded_power.md`](quality_reports/cleanup_2026-08-25/inventory_blinded_power.md) (92 top-level entries in `output_blinded_power/`) + [`inventory_configs.md`](quality_reports/cleanup_2026-08-25/inventory_configs.md) (49 files in `config/`). `output_blinded_power/` is gitignored. ~24 ancillary `*.log` files and several empty/smoke-scale dev-probe directories (`_cs_probe_111/111b/333/444`, `_int_cs6/6b`, `_amde_county_smoke`, `_e2e_*_verify*`, `_smoke_ewatt`, `_smoke_parallel_realmods`, `boundary_SMOKE`, `e2e_smoke_validation`) are DEAD infrastructure noise and omitted from the table below — see the inventory for the full list.

| Run | Date | Config | Level / treat_def / weights / NV / vintage | Headline | Output path | Status |
|---|---|---|---|---|---|---|
| `boundary_A0_2021_08` | 2026-08-21 | `power_boundary_A0_2021_08.yml` | state / online / — / NV in / post-rebuild | WITH-NV contrast for the noNV cell below; did2s reject₀.₀₅=1.0 at δ=0 flagged anomalous | [`output_blinded_power/boundary_A0_2021_08/`](output_blinded_power/boundary_A0_2021_08/) | EXPLORATORY |
| `boundary_A0_noNV_2021_08` | 2026-08-21 | `power_boundary_A0_noNV_2021_08.yml` | state / online / — / NV out / post-rebuild | State D1 infeasible without NV at this boundary (3,600/3,600 fail) | [`output_blinded_power/boundary_A0_noNV_2021_08/`](output_blinded_power/boundary_A0_noNV_2021_08/) | LIVE |
| `boundary_A_2021_08` | 2026-08-21 | `power_boundary_A_2021_08.yml` | state / online / — / NV in / anticipation=6mo / post-rebuild | Anticipation-boundary sensitivity contrast vs A0; not cited by name | [`output_blinded_power/boundary_A_2021_08/`](output_blinded_power/boundary_A_2021_08/) | EXPLORATORY |
| `boundary_B_2022_08` | 2026-08-21 | `power_boundary_B_2022_08.yml` | state / online / — / boundary moved to 2022-08 | Never finalized — 3,501-row partial, no `oc_summary.csv` | [`output_blinded_power/boundary_B_2022_08/`](output_blinded_power/boundary_B_2022_08/) | UNKNOWN |
| `cheap` | 2026-08-10 | `power_cheap.yml` | county+state mixed / online / — / pre-rebuild | Framework validation only, never aggregated | [`output_blinded_power/cheap/`](output_blinded_power/cheap/) | CONTAMINATED (pre-rebuild) → targeted gate/MDE configs below |
| `county_cs` | 2026-08-17 | `power_county_cs.yml` | county / online / — / shift-mode CS | Shift-mode barred by 2026-08-18 Opus code review | [`output_blinded_power/county_cs/`](output_blinded_power/county_cs/) | SUPERSEDED → `county_cs_adaptive` |
| `county_cs_adaptive` | 2026-08-19 | `power_county_cs_adaptive.yml` | county / online / — / adaptive-grid CS, `faster_mode=FALSE`, `safe_patches=TRUE` | Analytic fails size 61.2%; boot/boot_t size-valid, power flat — no finite county CS MDE | [`output_blinded_power/county_cs_adaptive/`](output_blinded_power/county_cs_adaptive/) | **LIVE** |
| `cs_probe` | 2026-08-17 | `power_cs_probe.yml` | state / online / — / shift-mode validation / pre-rebuild | Answered shift-mode linearity question | [`output_blinded_power/cs_probe/`](output_blinded_power/cs_probe/) | CONTAMINATED (pre-rebuild) |
| `dose_tercile_gates` | 2026-08-19 | `power_dose_tercile_gates.yml` | county / online / cellsize | Gambling-intensity-by-tercile heterogeneity probe | [`output_blinded_power/dose_tercile_gates/`](output_blinded_power/dose_tercile_gates/) | SUPERSEDED (cellsize weights dead) |
| `ldam_gate` | 2026-08-21 11:01 | `power_ldam_gate.yml` | state / online / — / NV in / post-rebuild | superseded same day | [`output_blinded_power/ldam_gate/`](output_blinded_power/ldam_gate/) | CONTAMINATED (NV) → `ldam_gate_noNV` |
| `ldam_gate_keepcovid` | 2026-08-21 14:06 | `power_ldam_gate_keepcovid.yml` | state / online / — / NV in | superseded same day | [`output_blinded_power/ldam_gate_keepcovid/`](output_blinded_power/ldam_gate_keepcovid/) | CONTAMINATED (NV) → `ldam_gate_keepcovid_noNV` |
| `ldam_gate_keepcovid_noNV` | 2026-08-21 17:48 | `power_ldam_gate_keepcovid_noNV.yml` | state / online / — / NV out | did2s reject₀.₀₅=0.11; ldam analytic 0.69 FAIL; **ldam jackknife 0.03 PASS** (SE/SD 0.98) | [`output_blinded_power/ldam_gate_keepcovid_noNV/`](output_blinded_power/ldam_gate_keepcovid_noNV/) | **LIVE** |
| `ldam_gate_noNV` | 2026-08-21 17:36 | `power_ldam_gate_noNV.yml` | state / online / — / NV out | ldam analytic 0.70 FAIL; **ldam jackknife 0.037 PASS** (SE/SD 1.01) | [`output_blinded_power/ldam_gate_noNV/`](output_blinded_power/ldam_gate_noNV/) | **LIVE** |
| `ldam_gate_postcovid` | 2026-08-21 11:26 | `power_ldam_gate_postcovid.yml` | state / online / — / NV in | superseded same day | [`output_blinded_power/ldam_gate_postcovid/`](output_blinded_power/ldam_gate_postcovid/) | CONTAMINATED (NV) → `ldam_gate_postcovid_noNV` |
| `ldam_gate_postcovid_noNV` | 2026-08-21 17:54 | `power_ldam_gate_postcovid_noNV.yml` | state / online / — / NV out | ldam analytic 0.57 FAIL; **ldam jackknife 0.01 PASS** (SE/SD 1.25) | [`output_blinded_power/ldam_gate_postcovid_noNV/`](output_blinded_power/ldam_gate_postcovid_noNV/) | **LIVE** |
| `longdiff_power` | 2026-08-19 | `power_longdiff.yml` | state / online / — / pre-rebuild | Longdiff (LDAM-style) well-calibrated but underpowered (MDE 29.8–59.8% vs LP-DiD 8.1%) | [`output_blinded_power/longdiff_power/`](output_blinded_power/longdiff_power/) | CONTAMINATED (pre-rebuild) |
| `lpdid_anchor_probe` | 2026-08-21 15:54 | dev probe, no tracked config | state / ramp75 / cellsize / NV in | Anchor (event vs launch) diagnostic explaining the ramp75 vintage artifact | [`output_blinded_power/lpdid_anchor_probe/`](output_blinded_power/lpdid_anchor_probe/) | CONTAMINATED (NV) |
| `lpdid_gate` | 2026-08-15 | `power_lpdid_gate.yml` | state / online / — / NV in / pre-rebuild (38/17 clusters) | Chain start | [`output_blinded_power/lpdid_gate/`](output_blinded_power/lpdid_gate/) | CONTAMINATED (pre-rebuild) → `lpdid_gate_noNV` |
| `lpdid_gate_noNV` | 2026-08-21 | `power_lpdid_gate_noNV.yml` | state / online / cellsize / NV out / post-rebuild | Raw online-date LP-DiD structurally fails size everywhere | [`output_blinded_power/lpdid_gate_noNV/`](output_blinded_power/lpdid_gate_noNV/) | SUPERSEDED → ramp75 gate |
| `lpdid_gate_postcovid` | 2026-08-17 | `power_lpdid_gate_postcovid.yml` | state / online / — / NV in / pre-rebuild | | [`output_blinded_power/lpdid_gate_postcovid/`](output_blinded_power/lpdid_gate_postcovid/) | CONTAMINATED (pre-rebuild) → `lpdid_gate_postcovid_noNV` |
| `lpdid_gate_postcovid_noNV` | 2026-08-21 | `power_lpdid_gate_postcovid_noNV.yml` | state / online / cellsize / NV out | | [`output_blinded_power/lpdid_gate_postcovid_noNV/`](output_blinded_power/lpdid_gate_postcovid_noNV/) | SUPERSEDED → folded into shift12 postcovid scenario |
| `lpdid_mde` | 2026-08-17 | `power_lpdid_mde.yml` | state / online / — / NV in / pre-rebuild | Spliced LP-DiD MDE 8.1% (dead: estimand + panel) | [`output_blinded_power/lpdid_mde/`](output_blinded_power/lpdid_mde/) | CONTAMINATED (pre-rebuild) → `lpdid_mde_noNV` |
| `lpdid_mde_county` | 2026-08-17 | `power_lpdid_mde_county.yml` | county / online / — (NV n/a, county) | Only NV-free county LP-DiD attempt; abandoned at batch 5/12 (spliced), 7/30 (postcovid) | [`output_blinded_power/lpdid_mde_county/`](output_blinded_power/lpdid_mde_county/) | DEAD (abandoned, no successor) |
| `lpdid_mde_fixedpanel` | 2026-08-20 02:21 | ad hoc override, no tracked config | state / online / — / NV in / post-rebuild | Re-run right after the rebuild but NV not excluded | [`output_blinded_power/lpdid_mde_fixedpanel/`](output_blinded_power/lpdid_mde_fixedpanel/) | CONTAMINATED (NV) → `lpdid_mde_noNV` |
| `lpdid_mde_noNV` | 2026-08-21 | `power_lpdid_mde_noNV.yml` | state / online / cellsize / NV out | "state LP-DiD MDE ~6.0%, not 7.3%" correction (itself now superseded) | [`output_blinded_power/lpdid_mde_noNV/`](output_blinded_power/lpdid_mde_noNV/) | SUPERSEDED → ramp75/shift12 MDE |
| `lpdid_ramp75_anchor` | 2026-08-21 15:57 | `power_lpdid_ramp75_anchor.yml` | state / ramp75 / — | 8-scenario anchor-horizon diagnostic; never completed | [`output_blinded_power/lpdid_ramp75_anchor/`](output_blinded_power/lpdid_ramp75_anchor/) | DEAD (incomplete) — superseded by `lpdid_anchor_probe` |
| `lpdid_ramp75_gate` | 2026-08-20 19:04 | `power_lpdid_ramp75_gate.yml` (v1) | state / ramp75 / — | Incomplete — one partial cell | [`output_blinded_power/lpdid_ramp75_gate/`](output_blinded_power/lpdid_ramp75_gate/) | DEAD (incomplete) → redone as v2 (6 min later, no tracked config) |
| `lpdid_ramp75_gate_v2` | 2026-08-20 19:10 | `power_lpdid_ramp75_gate.yml` run under an ad hoc override, **no tracked v2 config file** | state / ramp75 / cellsize / NV in | With-NV comparator cited in the "SHIFT12 BEATS RAMP75" finding | [`output_blinded_power/lpdid_ramp75_gate_v2/`](output_blinded_power/lpdid_ramp75_gate_v2/) | CONTAMINATED (NV) → `lpdid_ramp75_gate_noNV` |
| `lpdid_ramp75_gate_noNV` | 2026-08-21 17:09 | `power_lpdid_ramp75_gate_noNV.yml` | state / ramp75 / cellsize / NV out | wild size 0.037–0.083, passes gate | [`output_blinded_power/lpdid_ramp75_gate_noNV/`](output_blinded_power/lpdid_ramp75_gate_noNV/) | SUPERSEDED (cellsize; ramp75 itself a vintage artifact) → shift12 ewatt/vwatt gate |
| `lpdid_ramp75_mde` | 2026-08-20 19:57 | `power_lpdid_ramp75_mde.yml` | state / ramp75 / cellsize / NV in | | [`output_blinded_power/lpdid_ramp75_mde/`](output_blinded_power/lpdid_ramp75_mde/) | CONTAMINATED (NV) → `lpdid_ramp75_mde_noNV` |
| `lpdid_ramp75_mde_noNV` | 2026-08-21 16:26 | `power_lpdid_ramp75_mde_noNV.yml` | state / ramp75 / cellsize / NV out | "ramp75 MDE 7.1%, not 7.3%" (now dead: cellsize + vintage artifact) | [`output_blinded_power/lpdid_ramp75_mde_noNV/`](output_blinded_power/lpdid_ramp75_mde_noNV/) | SUPERSEDED → shift12 ewatt/vwatt MDE |
| `lpdid_shift12_gate_noNV` | 2026-08-21 19:17 | `power_lpdid_shift12_gate_noNV.yml` | state / shift12 / cellsize (pre-fix default) / NV out | Spliced wild 0.058 — basis of the now-dead "6.3% MDE" headline; TWFE arm (0.0465 analytic) still valid | [`output_blinded_power/lpdid_shift12_gate_noNV/`](output_blinded_power/lpdid_shift12_gate_noNV/) | SUPERSEDED (LP-DiD rows dead estimand) → `_gate_ewatt` / `_gate_vwatt` |
| `lpdid_shift12_gate_ewatt` | 2026-08-24 16:27 | `power_lpdid_shift12_gate_ewatt.yml` | state / shift12 / **ewatt** / NV out | Spliced wild 0.0325 PASS (analytic 0.145 FAIL); postcovid wild 0.071 PASS | [`output_blinded_power/lpdid_shift12_gate_ewatt/`](output_blinded_power/lpdid_shift12_gate_ewatt/) | **LIVE** |
| `lpdid_shift12_gate_vwatt` | 2026-08-24 17:24 | `power_lpdid_shift12_gate_vwatt.yml` | state / shift12 / **vwatt** / NV out | Spliced wild 0.0515 PASS; postcovid wild 0.0615 PASS; SE/SD 1.14 | [`output_blinded_power/lpdid_shift12_gate_vwatt/`](output_blinded_power/lpdid_shift12_gate_vwatt/) | **LIVE** |
| `lpdid_shift12_mde_noNV` | 2026-08-21 19:28 | `power_lpdid_shift12_mde_noNV.yml` | state / shift12 / cellsize / NV out | "shift12 MDE 6.3%" (dead) | [`output_blinded_power/lpdid_shift12_mde_noNV/`](output_blinded_power/lpdid_shift12_mde_noNV/) | SUPERSEDED → `_mde_ewatt` / `_mde_vwatt` |
| `lpdid_shift12_mde_ewatt` | 2026-08-24 17:11 | `power_lpdid_shift12_mde_ewatt.yml` | state / shift12 / **ewatt** / NV out | Spliced wild MDE 0.115 (CI 10.2–12.5%); postcovid wild 0.240 | [`output_blinded_power/lpdid_shift12_mde_ewatt/`](output_blinded_power/lpdid_shift12_mde_ewatt/) | **LIVE** |
| `lpdid_shift12_mde_vwatt` | 2026-08-24 17:36 | `power_lpdid_shift12_mde_vwatt.yml` | state / shift12 / **vwatt** / NV out | Spliced wild MDE 0.0875 (CI 8.3–9.1%) | [`output_blinded_power/lpdid_shift12_mde_vwatt/`](output_blinded_power/lpdid_shift12_mde_vwatt/) | **LIVE** |
| `lpdid_wild_gate` | 2026-08-20 17:33 | `power_lpdid_wild_gate.yml` | state / online / cellsize / NV in | | [`output_blinded_power/lpdid_wild_gate/`](output_blinded_power/lpdid_wild_gate/) | CONTAMINATED (NV) → `lpdid_wild_gate_noNV` |
| `lpdid_wild_gate_noNV` | 2026-08-21 17:04 | `power_lpdid_wild_gate_noNV.yml` | state / online / cellsize / NV out | | [`output_blinded_power/lpdid_wild_gate_noNV/`](output_blinded_power/lpdid_wild_gate_noNV/) | SUPERSEDED — folded into shift12 configs (`lpdid_wild: true` bundled by default) |
| `postcovid_maturation` | 2026-08-19 10:25 | `power_postcovid_maturation.yml` | state / maturation50 vs online / — / pre-rebuild | BJS fails size (27–29%); maturation50 vs online is power-neutral | [`output_blinded_power/postcovid_maturation/`](output_blinded_power/postcovid_maturation/) | CONTAMINATED (pre-rebuild) |
| `postcovid_maturation_county` | 2026-08-19 11:07 | `power_postcovid_maturation_county.yml` | county / maturation50 / cellsize | County companion; superseded in spirit by `county_cs_adaptive`'s did2s-headline conclusion | [`output_blinded_power/postcovid_maturation_county/`](output_blinded_power/postcovid_maturation_county/) | EXPLORATORY |
| `postcovid_maturation_county_wild` | 2026-08-19 11:37 | `power_postcovid_maturation_county_wild.yml` | county / maturation50 / cellsize | County analytic arms all fail size; lpdid wild exactly nominal (5.0/4.7%) | [`output_blinded_power/postcovid_maturation_county_wild/`](output_blinded_power/postcovid_maturation_county_wild/) | EXPLORATORY |
| `primary` | 2026-07-23 | `power_primary.yml` | county+state / online / — / pre-repair, pre-rebuild | Della 12114571: S3 infeasible instantly, 5 county tasks OOM-killed ~42h, all work lost | [`output_blinded_power/primary/`](output_blinded_power/primary/) | DEAD (empty on disk; never resubmitted) |
| `sensitivity` | 2026-07-23 | `power_sensitivity.yml` | state / online / — | Never started; axes later covered piecemeal (`boundary_*`, `time_agg_covid_gates`, `dose_tercile_gates`, NV pairs) | [`output_blinded_power/sensitivity/`](output_blinded_power/sensitivity/) | DEAD (empty) |
| `smoke` | 2026-08-10 | `power_smoke.yml` | county+state / online / — / pre-rebuild | Della 12220717; pipeline plumbing validation only | [`output_blinded_power/smoke/`](output_blinded_power/smoke/) | CONTAMINATED (pre-rebuild, state cell) |
| `time_agg_covid_gates` | 2026-08-19 17:26 | `power_time_agg_covid_gates.yml` | state / online / — / `faster_mode=FALSE`, `safe_patches=TRUE` | COVID splice (not cohort count) drives CS/did2s miscalibration; CS passes size on clean post-COVID monthly (5.0%/6.0%/3.3%) | [`output_blinded_power/time_agg_covid_gates/`](output_blinded_power/time_agg_covid_gates/) | **LIVE** |
| `validation` | 2026-07-23 | `power_validation.yml` | state / synthetic S1 panel | PASS on all 4 engine checks (blindness, forbidden-path, zero-delta identity, count-aug non-negativity) | [`output_blinded_power/validation/`](output_blinded_power/validation/) | EXPLORATORY (infrastructure self-test) |
| `_cs_cty_111` / `_cs_cty_222` | 2026-08-03 | pre-flag era, no config match | county / online / — | CS ran under default `faster_mode=TRUE` (non-estimating code path, pre-dates the 08-17 flag system) | [`output_blinded_power/_cs_cty_111/`](output_blinded_power/_cs_cty_111/), [`_cs_cty_222/`](output_blinded_power/_cs_cty_222/) | CONTAMINATED (CS faster_mode) |
| `_cs_probe_222` | 2026-08-03 | no config match | state / online / — | Same `faster_mode=TRUE` issue | [`output_blinded_power/_cs_probe_222/`](output_blinded_power/_cs_probe_222/) | CONTAMINATED (CS faster_mode) |
| `_amde_state_check_adaptive` / `_amde_state_check_brute` | 2026-08-19 | `power_state_cs_adaptive_check.yml` (ran under overridden names) | state / online / — / `faster_mode=FALSE`, `safe_patches=TRUE` | Validated adaptive-grid CS is bit-identical to brute force (gate 6) | [`output_blinded_power/_amde_state_check_adaptive/`](output_blinded_power/_amde_state_check_adaptive/), [`_brute/`](output_blinded_power/_amde_state_check_brute/) | ONE-OFF, infrastructure |

**Never-run configs** (staged, no output directory exists): `power_addon1.yml`, `power_lpdid_gate_newpanel.yml`, `power_lpdid_gate_postcovid_newpanel.yml`, `power_lpdid_mde_newpanel.yml` — see [Config lineage](#config-lineage) below.

### 2. Pretrends

Source: [`inventory_output.md`](quality_reports/cleanup_2026-08-25/inventory_output.md), `domain: pretrends`.

| Run | Date | Script | Key facts | Headline | Output path | Status |
|---|---|---|---|---|---|---|
| `pretrends_lottery_A_baseline` | 2026-08-21 | `analysis/pretrends/pretrends_statepanel_template.R` | 26 states (17 treated/9 never), 16 cohorts, unconditional | CS ATT +0.020 (SE 0.057), joint p=0.170 | [`output/pretrends_lottery_A_baseline/`](output/pretrends_lottery_A_baseline/) | **LIVE** |
| `pretrends_lottery_B_conditional` | 2026-08-21 | same | continuous lottery-vintage covariate | ATT +0.136 (SE 0.128); harmful thin-cell inflation at e=-2/-1 | [`output/pretrends_lottery_B_conditional/`](output/pretrends_lottery_B_conditional/) | **LIVE** (do not use for conditioning) |
| `pretrends_lottery_C_binary` | 2026-08-21 | same | binary lottery covariate | ATT +0.048 (SE 0.055), stable, recommended conditioning spec | [`output/pretrends_lottery_C_binary/`](output/pretrends_lottery_C_binary/) | **LIVE** |
| `pretrends_fixedbasket` | 2026-08-20 01:02 | `scripts/run_pretrends_statepanel.sh` | post-integer-`g`-bugfix, 25 states/15 cohorts | ATT +0.022 | [`output/pretrends_fixedbasket/`](output/pretrends_fixedbasket/) | SUPERSEDED → `pretrends_lottery_A_baseline` (one day later, 26 states/16 cohorts) |
| `pretrends_rebuild_B_newpanel` | 2026-08-20 00:33 | same, rebuilt panel | integer-`g` bug silently dropped never-treated states | ATT +0.080 — **bug-inflated, not an estimate** | [`output/pretrends_rebuild_B_newpanel/`](output/pretrends_rebuild_B_newpanel/) | DEAD (bug) → `pretrends_lottery_A_baseline` (+0.020) |
| `pretrends_rebuild_A_oldpanel` | 2026-08-20 00:33 | same script, on the deprecated double-counted CSV | intentional "before" comparator | ATT +0.074, SE 0.130 | [`output/pretrends_rebuild_A_oldpanel/`](output/pretrends_rebuild_A_oldpanel/) | CONTAMINATED (double-count; kept intentionally as the before/after baseline) |
| `pretrends_statepanel_me_included` | 2026-07-23 14:08 | `scripts/run_pretrends_statepanel.sh` | pre-08-10 schedule repair (16 never incl. ME/VT/KY/FL) | ATT +0.011 (SE 0.163) | [`output/pretrends_statepanel_me_included/`](output/pretrends_statepanel_me_included/) | CONTAMINATED (stale schedule) → `pretrends_lottery_A_baseline` |
| `pretrends_eviction_postcovid` | 2026-02-13 | `scripts/run_pretrends_statepanel.sh` | pre-NH/ME repair, pre-schedule-repair, pre-double-count-fix | — | [`output/pretrends_eviction_postcovid/`](output/pretrends_eviction_postcovid/) | CONTAMINATED → `pretrends_lottery_A_baseline` |
| `pretrends_eviction_precovid` | 2026-02-13 | same | same, pre-COVID window | — | [`output/pretrends_eviction_precovid/`](output/pretrends_eviction_precovid/) | CONTAMINATED |
| `pretrends_statepanel_template` | 2026-02-13 12:37 | same script | ME excluded entirely, pre-all-repairs | — | [`output/pretrends_statepanel_template/`](output/pretrends_statepanel_template/) | CONTAMINATED |
| `pretrends_eviction_postcovid_handle50` | 2026-08-14 | `scripts/run_pretrends_statepanel.sh` on handle50 panel | handle-maturity treat_def | CS pretrends **REJECTS** (Holm min_p=0.0335) | [`output/pretrends_eviction_postcovid_handle50/`](output/pretrends_eviction_postcovid_handle50/) | EXPLORATORY |
| `pre2020_state_pretrends` | 2026-03-19 | `analysis/pretrends/plot_pre2020_state_pretrends.R` | county-aggregated, immune to double-count | descriptive pre-2020 pretrends plot | [`output/pre2020_state_pretrends/`](output/pre2020_state_pretrends/) | EXPLORATORY |
| `csdid_pretrends` (+`.log`) | 2026-01-23 | `scripts/run_csdid_pretrends.R` family | legacy `pretrends_modern.R` pipeline, CS section disabled | — | [`output/csdid_pretrends/`](output/csdid_pretrends/) | SUPERSEDED → `pretrends_statepanel_template.R` pipeline |
| `pretrends_evaluation` | 2026-02-04 | `analysis/pretrends/evaluate_pretrends_modern_methods.R` | legacy `pretrends_modern.R` family | — | [`output/pretrends_evaluation/`](output/pretrends_evaluation/) | SUPERSEDED |
| `pretrends_pre_post_covid` | 2026-01-17 | legacy `pretrends_modern.R` family | — | — | [`output/pretrends_pre_post_covid/`](output/pretrends_pre_post_covid/) | SUPERSEDED |
| `pretrends_statepanel_template_nocovid_smoketest{1–7}` | 2026-02-13 | same script, smoke-scale | 7 directories | — | `output/pretrends_statepanel_template_nocovid_smoketest{1-7}/` | DEAD (smoke precursors) |
| `state_month_coverage_by_state*.csv` (4 loose files) | 2026-02-13 | `cs_power_threshold_sweep_nocovid_small.R` byproduct | — | — | `output/*.csv` | SUPERSEDED |
| `threshold_covid_sample_size`, `threshold_covid_sample_size_online_only` | 2026-02-13 | same legacy family | — | — | `output/threshold_covid_sample_size*/` | SUPERSEDED |
| `pretrends_annual_statepanel_experiment` | 2026-02-13 | no producer found | — | — | [`output/pretrends_annual_statepanel_experiment/`](output/pretrends_annual_statepanel_experiment/) | **UNKNOWN** (Open item) |

### 3. Calibration

Source: [`inventory_output.md`](quality_reports/cleanup_2026-08-25/inventory_output.md), `domain: calibration` (+ `cs_state_sweep`, `power` domain but calibration in nature).

| Run | Date | Script | Key facts | Headline | Output path | Status |
|---|---|---|---|---|---|---|
| `lpdid_cs_equivalence` | 2026-08-24 16:12 | `analysis/diagnostics/lpdid_cs_equivalence.R` | toy decomposition: contiguous vs gapped panels | Contiguous/staggered diff ~2e-16/8e-16 (holds); 7-mo interior hole diff 0.11 (**breaks**) | [`output/lpdid_cs_equivalence/`](output/lpdid_cs_equivalence/) | **LIVE** |
| `lpdid_cs_equivalence_keep` | 2026-08-24 16:03 | same, covid-keep window | real-panel companion | median \|diff\| 0.0097, max 0.090 | [`output/lpdid_cs_equivalence_keep/`](output/lpdid_cs_equivalence_keep/) | **LIVE** |
| `lpdid_weights_compare` | 2026-08-24 16:27 | `analysis/diagnostics/lpdid_weights_paired_compare.R` | paired ewatt/vwatt/cellsize | Verification of the 08-24 weighting fix | [`output/lpdid_weights_compare/`](output/lpdid_weights_compare/) | **LIVE** |
| `lpdid_weights_compare_mde` | 2026-08-24 17:12 | same, MDE arm | | | [`output/lpdid_weights_compare_mde/`](output/lpdid_weights_compare_mde/) | **LIVE** |
| `lpdid_statepanel` | 2026-08-21 15:57 | `analysis/main/lpdid_statepanel.R` | cellsize weights (pre-08-24 fix) | Dead estimand per CLAUDE.md | [`output/lpdid_statepanel/`](output/lpdid_statepanel/) | CONTAMINATED (cellsize weights) → corrected via `R/power/run_estimators.R` ewatt/vwatt (see Blinded power table) |
| `cs_calibration_unified` (+ `_analytic`, `_analytic_100`, `_analytic_20_serial`, `_bootstrap`, `_bootstrap_25` — 6 variants) | 2026-04-09 | `analysis/diagnostics/cs_calibration_unified.R` | state panel, 24 states | TWFE 1%/1.14; SunAb 21%/0.58; CS 14%/0.67 | `output/cs_calibration_unified*/` | SUPERSEDED → county-level calibration (`cs_calibration_multi_estimator_county.R`, feeds `border_diagnostic`) |
| `cs_threshold_sweep_no_maine_2024_min5` | 2026-02-12 | `cs_power_threshold_sweep_nocovid_small.R` | legacy threshold-sweep design | — | [`output/cs_threshold_sweep_no_maine_2024_min5/`](output/cs_threshold_sweep_no_maine_2024_min5/) | SUPERSEDED (CLAUDE.md calls this legacy) |
| `csdid_dynamic_validation_sim` | 2026-02-12 | `analysis/diagnostics/validate_csdid_dynamic_sim.R` | real adoption timing, pre-08-10 schedule repair | — | [`output/csdid_dynamic_validation_sim/`](output/csdid_dynamic_validation_sim/) | CONTAMINATED (stale schedule) |
| `cs_state_sweep` | 2026-02-12 | `analysis/main/cs_state_count_sweep.R` | county-aggregated (double-count immune), pre-08-10 schedule repair | — | [`output/cs_state_sweep/`](output/cs_state_sweep/) | CONTAMINATED (stale schedule) |
| `csdid_plots` | 2026-01-23 | `scripts/generate_support_plots.R` | may underlie the "875 cells / 338 identifiable (38.6%)" stat CLAUDE.md still cites | — | [`output/csdid_plots/`](output/csdid_plots/) | **UNKNOWN** (Open item) |

### 4. Diagnostics

Source: [`inventory_output.md`](quality_reports/cleanup_2026-08-25/inventory_output.md), `domain: diagnostics` (+ `power`/`other` domain items placed here for lack of a separate output-level power table).

| Run | Date | Script | Key facts | Headline | Output path | Status |
|---|---|---|---|---|---|---|
| `border_diagnostic` | 2026-05-21/22 | county border-discontinuity diagnostic | county-sourced, immune to all 5 boundary dates | **did2s pre-COVID drop-NH ATT +9.1%, CI [−0.10%,+17.5%]** | [`output/border_diagnostic/`](output/border_diagnostic/) | **LIVE** — project headline |
| `statepanel_double_count` | 2026-08-20 00:25 | `analysis/diagnostics/statepanel_double_count_audit.R` | the audit that discovered the double-count bug | 891/916 overlap state-months exact double count, 12 states | [`output/statepanel_double_count/`](output/statepanel_double_count/) | **LIVE** |
| `adoption_predictability` | 2026-08-21 12:29 | `analysis/diagnostics/adoption_predictability_prepaspa.R` | post-Cox-null-bugfix | Lottery maturity C=0.699 vs null 0.470, p<0.001; ever-adopt AUC 0.800 | [`output/adoption_predictability/`](output/adoption_predictability/) | **LIVE** |
| `adoption_predictability_institutions` | 2026-08-21 12:23 | `analysis/diagnostics/adoption_predictability_institutions.R` | region/ideology/casino/eviction-history blocks | Region AUC 0.676 (p=0.008) predicts ever-adopt; casino/eviction history null | [`output/adoption_predictability_institutions/`](output/adoption_predictability_institutions/) | **LIVE** |
| `adoption_selection` | 2026-08-21 10:58 | `analysis/diagnostics/adoption_selection_levels_slopes.R` | 41-state substrate (absent-row trap fixed) | Adopter-never level gap +0.64→+0.24 log pts once size controlled | [`output/adoption_selection/`](output/adoption_selection/) | **LIVE** |
| `covid_global_pt` | 2026-08-24 15:44 | `analysis/diagnostics/covid_global_pt_diagnostic.R`, `postcovid_boundary_sweep.R` | active COVID-splice investigation | feeds time-aggregation findings | [`output/covid_global_pt/`](output/covid_global_pt/) | **LIVE** |
| `longdiff_2x2_pseudo` | 2026-08-21 15:21 | `analysis/diagnostics/longdiff_2x2_pseudo_power.R` | annual county-court panel, NV-free | MDE-80 = 0.2401 (+27.1%) | [`output/longdiff_2x2_pseudo/`](output/longdiff_2x2_pseudo/) | **LIVE** |
| `longdiff_2x2_selection` | 2026-08-21 14:39 | `analysis/diagnostics/longdiff_2x2_selection_placebo.R` | NV-free | τ = −0.30%, RI p = 0.976 | [`output/longdiff_2x2_selection/`](output/longdiff_2x2_selection/) | **LIVE** |
| `longdiff_era_variance` | 2026-08-21 14:39 | `analysis/diagnostics/longdiff_real_calendar_decomp.R` | NV-free; overwritten in place — pre-fix CSVs unrecoverable (untracked) | median post/pre σ ratio 2.04 (strict set 2.73) | [`output/longdiff_era_variance/`](output/longdiff_era_variance/) | **LIVE** |
| `cheap_power_sim` | 2026-08-14 | `analysis/cheap_sims/*.R` | state-month C&S long-difference design | `DECISION_MEMO.md`: "not viable for plausible effect sizes" | [`output/cheap_power_sim/`](output/cheap_power_sim/) | **LIVE** (still-current negative finding) |
| `shift_validation` | 2026-08-17 13:35 | `analysis/diagnostics/validate_shift_sufficiency.R` | TWFE arm | max discrepancy ~0.04 | [`output/shift_validation/`](output/shift_validation/) | **LIVE** |
| `shift_validation_cs` | 2026-08-17 16:33 | same, CS arm | | discrepancies up to 0.25 | [`output/shift_validation_cs/`](output/shift_validation_cs/) | SUPERSEDED (shift-mode CS barred by Opus review) → `R/power/adaptive_mde.R` |
| `ddd_power` | 2026-08-21 14:19 | `analysis/power/run_ddd_power.R`, `R/power/ddd_power.R` | county-level triple-diff, immune to double-count/NV | not yet a headline | [`output/ddd_power/`](output/ddd_power/) | EXPLORATORY |
| `eviction_stabilization` | 2026-08-21 11:50 | `analysis/diagnostics/eviction_stabilization_timing.R` | post-08-20 rebuild, post-08-21 NV window | descriptive filing-stabilization timing chart | [`output/eviction_stabilization/`](output/eviction_stabilization/) | EXPLORATORY |
| `permutation_placebo` | 2026-08-14 19:13 | `analysis/diagnostics/permutation_placebo_real_data.R` | pre-08-20 rebuild | did2s ~7.0% Type I, SE/SD 0.93 on spliced panel | [`output/permutation_placebo/`](output/permutation_placebo/) | CONTAMINATED (pre-rebuild) |
| `state_influence_loo`, `_postcovid`, `_precovid` | 2026-02-13 | `analysis/diagnostics/state_influence_loo.R` | pre-all-repairs | — | `output/state_influence_loo*/` | CONTAMINATED (pre-rebuild + pre-schedule-repair) |
| `timing_covid_recovery` | 2026-08-15 01:57 | `analysis/diagnostics/timing_covid_recovery_test.R` | pre-08-20 rebuild | — | [`output/timing_covid_recovery/`](output/timing_covid_recovery/) | CONTAMINATED (pre-rebuild) |
| `csdid_debug` | 2026-01-23/02-04 | `scripts/generate_support_plots.R` | DEAD-by-default per task convention | — | [`output/csdid_debug/`](output/csdid_debug/) | DEAD |
| `example_csdid` + 2 `.log` files | 2026-01-23 | no producer found | demo/example workflow output | — | `output/example_csdid/`, loose `.log`s | DEAD |
| `handle_maturity_check` | 2026-08-20 02:29 | none — empty directory | — | — | [`output/handle_maturity_check/`](output/handle_maturity_check/) | DEAD |
| `annual_data_usefulness` | 2026-02-13 | no producer found | — | — | [`output/annual_data_usefulness/`](output/annual_data_usefulness/) | **UNKNOWN** (Open item) |

### 5. Mortgage

Source: [`inventory_output.md`](quality_reports/cleanup_2026-08-25/inventory_output.md), `domain: mortgage` / `mortgage-power`.

| Run | Date | Script | Key facts | Headline | Output path | Status |
|---|---|---|---|---|---|---|
| `pretrends_mortgage_delinquency` | 2026-02-13 01:43 | `analysis/pretrends/pretrends_mortgage_delinquency.R`, `scripts/run_pretrends_mortgage.sh` | 51 states, NV-affected, **never re-run** | ATT +0.030pp (SE 0.043), n.s.; pretrends not rejected (Holm p=1.0); SunAb rejects | [`output/pretrends_mortgage_delinquency/`](output/pretrends_mortgage_delinquency/) | CONTAMINATED (NV) — flagged Open item, no NV-free re-run exists |
| `pretrends_mortgage_bjs` | 2026-04-17 14:22 | BJS/didimputation event-study check, no confirmed exact-name producer | one-off event-study check | — | [`output/pretrends_mortgage_bjs/`](output/pretrends_mortgage_bjs/) | EXPLORATORY |
| `honestdid_mortgage_bjs` | 2026-04-17 15:04 | `analysis/pretrends/honestdid_mortgage_bjs.R` | HonestDiD sensitivity, BJS/mortgage | — | [`output/honestdid_mortgage_bjs/`](output/honestdid_mortgage_bjs/) | EXPLORATORY |
| `hollenbeck_replication_mortgage` | 2026-04-17 18:01 | `analysis/main/hollenbeck_replication_mortgage.R` | literature-comparison exercise | — | [`output/hollenbeck_replication_mortgage/`](output/hollenbeck_replication_mortgage/) | EXPLORATORY |
| `gardner_spec_sweep_mortgage` | 2026-04-17 15:29 | `analysis/main/gardner_spec_sweep_mortgage.R` | did2s/Gardner spec sweep | — | [`output/gardner_spec_sweep_mortgage/`](output/gardner_spec_sweep_mortgage/) | EXPLORATORY |
| `cs_calibration_multi_mortgage` | 2026-04-17 14:59 | `analysis/diagnostics/cs_calibration_multi_estimator_mortgage.R` | not referenced in CLAUDE.md; unconfirmed NV exposure | — | [`output/cs_calibration_multi_mortgage/`](output/cs_calibration_multi_mortgage/) | **UNKNOWN** (Open item) |
| `power_mortgage_delinquency` | 2026-04-09 13:10 | `analysis/main/power_simulation_mortgage_delinquency.R` | **contradicts CLAUDE.md prose** ("No formal power simulation exists for mortgage delinquency") | complete power sim exists on disk | [`output/power_mortgage_delinquency/`](output/power_mortgage_delinquency/) | **UNKNOWN** (Open item — inconsistency) |
| `power_mortgage_cs_final`, `power_mortgage_cs_remaining`, `power_mortgage_test` | 2026-04-09 | no producer found | same family as above, likely early test harness | — | `output/power_mortgage_cs_final/`, `_cs_remaining/`, `_test/` | **UNKNOWN** (Open items) |

### 6. Exploratory

Source: [`inventory_output.md`](quality_reports/cleanup_2026-08-25/inventory_output.md), `domain: exploratory`.

| Run | Date | Script | Key facts | Headline | Output path | Status |
|---|---|---|---|---|---|---|
| `market_maturation` | 2026-08-14 | `analysis/exploratory/market_maturation_timing.R` | quintile-timing table matches CLAUDE.md exactly | 20/40/60/80/100% of peak: 4.8/10.3/16.9/29.3/46.3 months | [`output/market_maturation/`](output/market_maturation/) | **LIVE** |
| `exposure_curve` | 2026-08-14 | `analysis/exploratory/exposure_curve_model.R`, `cohort_ramp_lags.R` | handle-based cohort exposure curves | — | [`output/exposure_curve/`](output/exposure_curve/) | EXPLORATORY |
| `handle_cohort_support` | 2026-08-14 | `analysis/diagnostics/handle_legalization_cohort_support.R` | support diagnostics for the ramp75/handle-maturity family; legitimately includes NV (real betting market) | — | [`output/handle_cohort_support/`](output/handle_cohort_support/) | EXPLORATORY |
| `handle_four_quarters` | 2026-08-14 | `analysis/data_prep/make_fourq_dose.R` | dose/exposure construction diagnostics | — | [`output/handle_four_quarters/`](output/handle_four_quarters/) | EXPLORATORY |
| `postcovid_handle_ramp_support`, `postcovid_ramp_candidates` | 2026-08-14 | `analysis/diagnostics/postcovid_handle_ramp_support.R` | support diagnostics for ramp75 candidate states | — | `output/postcovid_handle_ramp_support/`, `postcovid_ramp_candidates/` | EXPLORATORY |
| `retail_vs_online` | 2026-07-23 | `analysis/exploratory/retail_vs_online_handle.R`, `retail_vs_online_gambling_growth.R` | descriptive handle comparison, pre-08-10 schedule repair (low materiality — regime labels only) | — | [`output/retail_vs_online/`](output/retail_vs_online/) | EXPLORATORY |
| `dose_response_iv` | 2026-02-16 18:31 | `analysis/main/dose_response_iv.R` | defaults to `state_month_panel_with_treatment.csv`, pre-08-10 **and** pre-08-20 | — | [`output/dose_response_iv/`](output/dose_response_iv/) | CONTAMINATED (stale schedule + double-count) |

---

## Config lineage

Reproduced from [`inventory_configs.md`](quality_reports/cleanup_2026-08-25/inventory_configs.md) §"Lineage chains", with a one-line "why this link exists" gloss added at each step. Bold = still current.

**State LP-DiD size gate (spliced window) — why each link exists:**
```
power_lpdid_gate.yml                         (baseline online-date gate, WITH NV, pre-rebuild panel)
  -> power_lpdid_gate_noNV.yml                (removes NV from the control pool)
     [power_lpdid_gate_newpanel.yml            staged to re-pair WITH-NV on the rebuilt panel — NEVER RUN,
      abandoned once shift12 made online_start_date obsolete]
  -> power_lpdid_ramp75_gate.yml              (tries handle-calibrated dating — no tracked v2 config;
                                                ran as ad hoc override "lpdid_ramp75_gate_v2")
     -> power_lpdid_ramp75_gate_noNV.yml      (NV-free ramp75; passes size, briefly the headline)
        -> power_lpdid_shift12_gate_noNV.yml  (isolates whether the +12mo LAG or the handle-specific
                                                dating drives ramp75's edge — answer: the lag)
           -> **power_lpdid_shift12_gate_ewatt.yml**  (corrected equal-weight estimand, matches CS)
           -> **power_lpdid_shift12_gate_vwatt.yml**  (corrected variance-weight estimand, Cengiz stack)
power_lpdid_wild_gate.yml / power_lpdid_wild_gate_noNV.yml   (adds wild-bootstrap inference)
  -> folded into the shift12 configs (lpdid_wild: true is now bundled by default)
```

**State LP-DiD MDE (mirrors the gate chain exactly):**
```
power_lpdid_mde.yml -> power_lpdid_mde_noNV.yml
  [power_lpdid_mde_newpanel.yml — staged, NEVER RUN]
  -> power_lpdid_ramp75_mde.yml -> power_lpdid_ramp75_mde_noNV.yml
     -> power_lpdid_shift12_mde_noNV.yml       (pre-2026-08-24 weighting bug — the dead "6.3%" run)
        -> **power_lpdid_shift12_mde_ewatt.yml**   (corrected: MDE 11.5%)
        -> **power_lpdid_shift12_mde_vwatt.yml**   (corrected: MDE 8.75%)
```

**County LP-DiD:** `power_lpdid_mde_county.yml` — the only NV-free county attempt, a single
branch off the state chain, abandoned mid-run (batch 5/12 spliced, 7/30 postcovid) on
2026-08-17; no successor config exists. `power_lpdid_ramp75_anchor.yml` is a side-branch
diagnostic off the ramp75 arm (anchor-point sensitivity, explaining *why* ramp75 is a
vintage artifact), also abandoned once ramp75 was superseded.

**CS-DiD:**
```
power_cs_probe.yml                 (state, shift-mode linearity validation)
power_county_cs.yml                (county, shift-mode) — barred by the 2026-08-18 code review
  -> **power_county_cs_adaptive.yml**   (adaptive-grid, genuine full estimates — the resolved verdict)
power_state_cs_adaptive_check.yml  (validates the adaptive machinery itself, gate 6; ran under
                                     overridden run_names `_amde_state_check_adaptive`/`_brute`)
```

**Run-ladder tiers** (`power_smoke.yml` → `power_cheap.yml` → `power_primary.yml` /
`power_sensitivity.yml` / `power_addon1.yml`) are a separate, earlier lineage built for the
Della cluster run ladder *before* the 2026-08-10 schedule repair and 2026-08-20 panel rebuild
existed. None were re-run after either fix — the project's live work moved to the targeted
single-cell gate/MDE configs above instead of re-running the broad grids. `power_addon1.yml`
itself is **NEVER-RUN**.

**L-DAM** (`power_ldam_gate.yml` and its 5 covid/NV variants), the **boundary probes**
(`power_boundary_*.yml`), and the **maturation50** treat_def
(`power_postcovid_maturation*.yml`) are each self-contained one-shot diagnostics with no
further chain — they answered one question each and were not iterated on. L-DAM+jackknife
in particular passes its size gate in all three windows but has no MDE follow-up (see Open
items).

---

## Open items

### The 9 UNKNOWNs

1. **`annual_data_usefulness`** (`output/`) — no producing script found anywhere in the repo via grep of `analysis/`, `scripts/`, `R/`, `data_prep/`.
2. **`cs_calibration_multi_mortgage`** (`output/`) — not referenced anywhere in CLAUDE.md; unconfirmed whether the mortgage panel's structural NV inclusion affects this specific calibration run.
3. **`csdid_plots`** (`output/`) — may underlie the "875 total (g,t) cells; 338 identifiable (38.6%)" support-structure statistic CLAUDE.md still cites as current, but the panel it was built on is stale (pre-all-repairs). Unclear whether that stat needs updating or is a different kind of claim (structural, not schedule-dependent).
4. **`power_mortgage_cs_final`** (`output/`) — no producing script found.
5. **`power_mortgage_cs_remaining`** (`output/`) — no producing script found.
6. **`power_mortgage_delinquency`** (`output/`) — a complete mortgage power simulation exists on disk, contradicting CLAUDE.md's own prose ("No formal power simulation exists for mortgage delinquency"). One of the two is stale — needs a human decision on which.
7. **`power_mortgage_test`** (`output/`) — no producing script found (likely an early test harness for #6).
8. **`pretrends_annual_statepanel_experiment`** (`output/`) — no producing script found via repo-wide grep.
9. **`boundary_B_2022_08`** (`output_blinded_power/`) — a 3,501-row partial CSV with a `.done_reps` marker but no finalized `oc_summary.csv`/`mde_table.csv`/`failures.csv`. Genuinely ambiguous whether abandoned mid-run or just never re-invoked to finalize; the smoke-scale precursor `boundary_SMOKE` (same `run_name`) suggests the full run was at least started in earnest.

### Flagged inconsistencies

- **Mortgage power sim exists on disk vs. CLAUDE.md prose.** `output/power_mortgage_delinquency/` (2026-04-09) is a complete run of `analysis/main/power_simulation_mortgage_delinquency.R`, but CLAUDE.md's "Power Analysis Results" section states "No formal power simulation exists for mortgage delinquency." Resolve by either updating CLAUDE.md to cite the run (after confirming it's still valid — check NV exposure first) or confirming it was superseded/abandoned and CLAUDE.md is correct.
- **Mortgage pretrends is NV-affected and has never been re-run.** CLAUDE.md's "NV FOOTPRINT SWEEP" section explicitly names mortgage delinquency pretrends as NV-affected (NV is one of 27 never-treated states in the 51-state mortgage panel), but it is absent from the "NV-AFFECTED RE-RUNS COMPLETE" list of four fixed analyses. The saved ATT (+0.030pp, SE 0.043) should not be cited as NV-clean.
- **LDAM has a passing gate but no MDE follow-up.** `ldam_gate_noNV`, `ldam_gate_keepcovid_noNV`, and `ldam_gate_postcovid_noNV` all show LDAM+jackknife passing its size gate cleanly (0.037/0.03/0.01, SE/SD ~1.0–1.25) — a real candidate estimator — but no `power_ldam_mde*.yml` config or MDE run exists anywhere in `config/` or `output_blinded_power/`. As of 2026-08-25 it sits entirely outside the shift12-based PAP decision table.
- **`lpdid_ramp75_gate_v2` and `lpdid_mde_fixedpanel` have no tracked config.** Both output directories are referenced by name in root CLAUDE.md and in the header comments of `power_lpdid_ramp75_mde.yml` / `power_lpdid_ramp75_mde_noNV.yml`, but neither has a corresponding saved `config/*.yml` file — they were manual `run_name:` overrides of `power_lpdid_ramp75_gate.yml` and `power_lpdid_mde.yml` respectively, run once (right after the 2026-08-20 panel rebuild) and never saved back as permanent configs. Reproducing either run today requires manually setting the override.

---

## Adding a row

Per the maintenance rule above: **every completed run appends one row to the matching
table before the session ends.** Never delete a superseded row — change its status and
add a `→ replacement` pointer.

Template for a domain table row:

```markdown
| `run_name` | YYYY-MM-DD | `config/script path` | level / treat_def / weights / NV / panel-vintage | one-line headline number or finding | [`output(_blinded_power)/run_name/`](relative/path/) | STATUS (→ replacement, if superseded/contaminated) |
```

If the new run is a current best number, also add it to the **LIVE summary table** at the
top. If it replaces an existing LIVE row, move that row down into its domain table with
`SUPERSEDED → new_run_name` and delete only its line from the LIVE summary (never from the
domain table). If the run answers one of the [Open items](#open-items), resolve the item —
strike it or replace it with the answer, and note the resolving run's name.
