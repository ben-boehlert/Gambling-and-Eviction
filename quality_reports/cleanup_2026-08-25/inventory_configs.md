# Config Inventory — `config/power_*.yml` (2026-08-25)

Cross-reference ledger for all 49 files in `config/`. Read against root `CLAUDE.md`
(esp. "Blinded Power-Simulation Framework", the LP-DiD reweighting fix
2026-08-24, "SHIFT12 BEATS RAMP75" 2026-08-21, the NV-exclusion notes
2026-08-21, and the panel rebuild 2026-08-20). No files were moved or deleted;
this document only reads `config/*.yml` and `output_blinded_power/*` — it does
not modify either.

**This is the only file this task wrote.**

## Counts by relevance

| Relevance | Count |
|---|---|
| CURRENT | 5 |
| SUPERSEDED | 19 |
| ONE-OFF | 21 |
| NEVER-RUN | 4 |
| **Total** | **49** |

**CURRENT configs** (live PAP decision path):
- `config/power_lpdid_shift12_gate_ewatt.yml`
- `config/power_lpdid_shift12_gate_vwatt.yml`
- `config/power_lpdid_shift12_mde_ewatt.yml`
- `config/power_lpdid_shift12_mde_vwatt.yml`
- `config/power_county_cs_adaptive.yml`

## How "ran?" was checked

For each config's `run_name`, I looked for `output_blinded_power/<run_name>/`.
"Full results" = the directory has top-level `mde_table.csv` + `oc_summary.csv`
(or the adaptive/validation equivalents). "Partial only" = the directory
exists but holds only a `partials/` subfolder (batches started, never
aggregated, or the run failed/was abandoned before finishing). "Missing" =
no directory at all → NEVER-RUN. Two configs (`power_validation.yml`,
`power_state_cs_adaptive_check.yml`) were run under an output name that
differs from their `run_name:` field or lack one; noted inline.

---

## 1. Foundational run-ladder tiers

| config | run_name(s) | what it tests | output dir | ran? | current relevance |
|---|---|---|---|---|---|
| `power_smoke.yml` | `smoke` | county+state headline cells, twfe+did2s, 50 reps × 4δ — pipeline plumbing smoke test | `output_blinded_power/smoke/` | Yes, full results (Della job 12220717, 2026-08-10) | SUPERSEDED — pre-dates the 2026-08-10 schedule repair and the 2026-08-20 panel rebuild; validated the pipeline, not a citable operating characteristic. No single successor; superseded in spirit by the whole post-rebuild body of targeted gate/MDE configs below. |
| `power_cheap.yml` | `cheap` | county+state, twfe+did2s only (cs dropped for cost), 8 scenarios, 500 reps × 11δ, no S3 | `output_blinded_power/cheap/` | Partial only (`partials/`, never aggregated) | SUPERSEDED — pre-repair/pre-rebuild panel; run ladder table calls it "ready" but it never finished. Superseded by the targeted post-rebuild gate/MDE configs (lpdid_*, ldam_*, shift12_*). |
| `power_primary.yml` | `primary` | county+state, 11 scenario families (9 after S3 drop), + cs, full candidate set | `output_blinded_power/primary/` | Partial only | SUPERSEDED — Della job 12114571 (2026-08-08) predates the 2026-08-10 schedule repair (comment in the file itself says these partials "MUST be deleted before resubmission") AND the 2026-08-20 panel rebuild; county CS arm was also OOM-killed at ~42h. Never resubmitted; superseded by `power_county_cs_adaptive.yml` (CS) and the state gate/MDE chain. |
| `power_sensitivity.yml` | `sensitivity` | state, 12 one-axis-at-a-time sensitivity families (sample, calendar, designs, mechanisms, shapes, outcomes, quarterly, treat_def, never-treated controls, loader anticipation, est_anticipation sweep, SunAb diagnostic) | `output_blinded_power/sensitivity/` | Partial only | SUPERSEDED / not started — CLAUDE.md run ladder marks it "not started." Individual axes it would have covered were later run piecemeal as standalone diagnostics instead: `power_boundary_*` (calendar/anticipation), `power_time_agg_covid_gates.yml` (aggregation), `power_dose_tercile_gates.yml` (dose), the NV-exclusion pairs (never-treated controls). |
| `power_addon1.yml` | `addon1` | county, twfe+did2s, intensity-ramp shape + cohort-heterogeneity DGP add-on scenarios, meant to run after `cheap` | none | **NEVER-RUN** | NEVER-RUN — no evidence in `SESSION_REPORT.md` or the research journal that this executed; built for the Della upload (`scripts/make_della_power_upload.sh`, `run_aggregate.sh`) but no output directory exists. |
| `power_validation.yml` | *(no `run_name:` field; falls back to the framework's `validation` default)* | state, twfe only, 25 reps × 2δ — the CI/quick-smoke schema tier shared with `power_primary.yml`/`power_sensitivity.yml` | `output_blinded_power/validation/` | Yes — `validation_results.csv` present | ONE-OFF — infrastructure/schema check for tests and quick smoke runs, not a substantive PAP finding; timeless utility, not part of the estimator-selection narrative. |

## 2. CS-DiD arms

| config | run_name(s) | what it tests | output dir | ran? | current relevance |
|---|---|---|---|---|---|
| `power_county_cs.yml` | `county_cs` | county, cs+twfe+did2s, shift-mode CS (the first config where CS could estimate at all, post the safe-patches/faster_mode fixes) | `output_blinded_power/county_cs/` | Partial only | SUPERSEDED by `power_county_cs_adaptive.yml` — shift-mode was barred for the headline CS MDE by an Opus code review (`quality_reports/sufficient_statistics_shift_mode_code_review.md`, 2026-08-18). Partial preserved untouched. |
| `power_county_cs_adaptive.yml` | `county_cs_adaptive` | county, CS only, adaptive-grid MDE search (`run_adaptive_mde()`), 250 reps, `cs_faster_mode: false`, `cs_safe_patches: true` — genuine full estimates, not shift-mode synthesis | `output_blinded_power/county_cs_adaptive/` (`mde_adaptive.csv`, `size_gate.csv`, `oc_summary.csv`) | Yes, full results | **CURRENT** — the resolved county CS verdict: analytic fails size (61.2%), boot/boot_t are size-valid but the power curve is flat everywhere (never crosses 80% power) → "no defensible finite county CS MDE." This is what eliminates CS from county power consideration and keeps did2s as the county workhorse in the live PAP. |
| `power_cs_probe.yml` | `cs_probe` | state, cs+twfe+did2s, small (50 reps × 4δ) shift-mode linearity/loading validation probe for CS | `output_blinded_power/cs_probe/` | Yes, full results | ONE-OFF — answered its question (CS shift-mode behavior) and was superseded in approach by the adaptive-grid method above; the probe itself is not reused. |
| `power_state_cs_adaptive_check.yml` | `state_cs_adaptive_check` in the file, but the driver script overrides it to `_amde_state_check_adaptive` / `_amde_state_check_brute` (`analysis/diagnostics/adaptive_vs_brute_state_check.R`) | state, real CS estimator, gate-6 validation that `run_adaptive_mde()` and brute-force `run_scenario_grid()` produce bit-identical overlapping cells and the same MDE verdict | `output_blinded_power/_amde_state_check_adaptive/`, `output_blinded_power/_amde_state_check_brute/` (both full results); no directory literally named `state_cs_adaptive_check` | Yes, full results (under overridden names) | ONE-OFF — validated the adaptive-search machinery itself (gate 6 of the adaptive-MDE plan), not a substantive calibration result. |

## 3. LP-DiD baseline chain (`online_start_date`, pre-shift12)

| config | run_name(s) | what it tests | output dir | ran? | current relevance |
|---|---|---|---|---|---|
| `power_lpdid_gate.yml` | `lpdid_gate` | state, twfe+did2s+lpdid size gate (δ=0,0.05), spliced window, WITH NV, `online_start_date` | `output_blinded_power/lpdid_gate/` | Yes, full results | SUPERSEDED — pre-dates both the NV-exclusion fix and the 2026-08-20 panel rebuild (reports 38/17 clusters vs the current 33/15). Chain continues → `lpdid_gate_noNV` → ramp75 → shift12. |
| `power_lpdid_gate_newpanel.yml` | `lpdid_gate_newpanel` | same as `lpdid_gate.yml` but intended as a WITH-NV re-run on the rebuilt panel, to pair apples-to-apples against `lpdid_gate_noNV.yml` | none | **NEVER-RUN** | NEVER-RUN — staged 2026-08-20 as "queue B" re-basing; abandoned once `power_lpdid_shift12_*` made the whole `online_start_date` gate obsolete. |
| `power_lpdid_gate_noNV.yml` | `lpdid_gate_noNV` | same cell, NV excluded (auto-generated 2026-08-21, naturally on the current/rebuilt panel data) | `output_blinded_power/lpdid_gate_noNV/` | Yes, full results | SUPERSEDED — the treat_def itself (`online_start_date`) was later shown structurally inferior: "shift12 dominates ramp75" and ramp75/shift12 both beat raw online dating on size. Superseded by `power_lpdid_ramp75_gate_noNV.yml` → `power_lpdid_shift12_gate_{ewatt,vwatt}.yml`. |
| `power_lpdid_gate_postcovid.yml` | `lpdid_gate_postcovid` | same as `lpdid_gate.yml` but post-COVID-only window (7 treated / 10 never, WITH NV) | `output_blinded_power/lpdid_gate_postcovid/` | Yes, full results | SUPERSEDED — same panel-rebuild/NV issues as `lpdid_gate.yml`; superseded by `lpdid_gate_postcovid_noNV` and ultimately the postcovid scenario block inside the shift12 configs. |
| `power_lpdid_gate_postcovid_newpanel.yml` | `lpdid_gate_postcovid_newpanel` | WITH-NV re-run of the postcovid gate on the rebuilt panel | none | **NEVER-RUN** | NEVER-RUN — same "queue B" re-basing that was abandoned in favor of shift12. |
| `power_lpdid_gate_postcovid_noNV.yml` | `lpdid_gate_postcovid_noNV` | postcovid gate, NV excluded | `output_blinded_power/lpdid_gate_postcovid_noNV/` | Yes, full results | SUPERSEDED — same reasoning; the postcovid window is now covered as scenario B inside `power_lpdid_shift12_{gate,mde}_{ewatt,vwatt}.yml`. |
| `power_lpdid_mde.yml` | `lpdid_mde` | state, MDE curves (13-point grid) for both windows, WITH NV, `online_start_date` | `output_blinded_power/lpdid_mde/` | Yes, full results | SUPERSEDED — same chain as the gate configs; superseded by `lpdid_mde_noNV` → ramp75 → shift12. |
| `power_lpdid_mde_newpanel.yml` | `lpdid_mde_newpanel` | WITH-NV MDE re-run on the rebuilt panel | none | **NEVER-RUN** | NEVER-RUN — "queue B," abandoned. |
| `power_lpdid_mde_noNV.yml` | `lpdid_mde_noNV` | MDE curves, NV excluded — this is the run that produced the "state LP-DiD MDE should be ~6.0%, not 7.3%" correction | `output_blinded_power/lpdid_mde_noNV/` | Yes, full results | SUPERSEDED — treat_def superseded by ramp75/shift12 (the 6.0%/7.3% numbers themselves are also since superseded by the shift12 6.3%→11.5% corrections). |
| `power_lpdid_mde_county.yml` | `lpdid_mde_county` | county-level LP-DiD size gate + MDE, both COVID windows, the one NV-free arm that could have tested whether county disaggregation changes the state verdict | `output_blinded_power/lpdid_mde_county/` | Partial only — stopped at batch 5/12 (spliced) and 7/30 (postcovid) on 2026-08-17; no `mde_table.csv`/`oc_summary.csv` ever produced | ONE-OFF (abandoned/incomplete) — CLAUDE.md flags this explicitly as never finished. The only NV-free county LP-DiD attempt; no re-run exists. |

## 4. LP-DiD ramp75 chain (handle-calibrated dating — flagged as a vintage/blindness artifact)

| config | run_name(s) | what it tests | output dir | ran? | current relevance |
|---|---|---|---|---|---|
| `power_lpdid_ramp75_gate.yml` | `lpdid_ramp75_gate` | state, size gate using `ramp75_schedule.csv` (handle reaches 75% of state's own peak), WITH NV | `output_blinded_power/lpdid_ramp75_gate/` | Partial only (`partials/`, not aggregated under this name) | SUPERSEDED — the completed/corrected version of this cell was captured under an ad hoc override run_name `lpdid_ramp75_gate_v2` (see §7 below; no tracked config file matches it exactly), itself referenced in `power_lpdid_ramp75_mde.yml`'s header. Further superseded by `lpdid_ramp75_gate_noNV.yml` and then shift12. |
| `power_lpdid_ramp75_gate_noNV.yml` | `lpdid_ramp75_gate_noNV` | same, NV excluded | `output_blinded_power/lpdid_ramp75_gate_noNV/` | Yes, full results | SUPERSEDED by `power_lpdid_shift12_gate_{ewatt,vwatt}.yml` — CLAUDE.md's 2026-08-21 finding shows ramp75's size-gate edge over raw online dating comes purely from the +lag, not the handle-specific timing, and ramp75's lag is a vintage artifact (0.957 correlation with months of post-launch handle observed) plus a blindness violation (handle is post-treatment/outcome-adjacent). shift12 reproduces the lag with none of that contamination. |
| `power_lpdid_ramp75_mde.yml` | `lpdid_ramp75_mde` | MDE curve for the ramp75 cell that passed the size gate (`lpdid_ramp75_gate_v2`), WITH NV | `output_blinded_power/lpdid_ramp75_mde/` | Yes, full results | SUPERSEDED — same vintage-artifact reasoning; superseded by `lpdid_ramp75_mde_noNV` then shift12. |
| `power_lpdid_ramp75_mde_noNV.yml` | `lpdid_ramp75_mde_noNV` | MDE curve, NV excluded — produced the "ramp75 dominates online dating, MDE 7.1% not 7.3%" headline that stood before shift12 | `output_blinded_power/lpdid_ramp75_mde_noNV/` | Yes, full results | SUPERSEDED by `power_lpdid_shift12_mde_{ewatt,vwatt}.yml` per the "SHIFT12 BEATS RAMP75" finding (2026-08-21): shift12 has a better MDE (6.3% vs 7.1% at the time), better SE/SD, passes the postcovid cell ramp75's analytic arm didn't, and needs no outcome data (ramp75 does). |
| `power_lpdid_ramp75_anchor.yml` | `lpdid_ramp75_anchor` | 8-scenario diagnostic: does the LP-DiD cell **anchor** (event vs launch vs event_clean, horizons 12-24) change the ramp75 MDE? | `output_blinded_power/lpdid_ramp75_anchor/` | Partial only | ONE-OFF — a diagnostic probe into ramp75's baseline-contamination mechanism; served its purpose (explaining WHY ramp75 is a vintage artifact) but not re-run to completion, and moot now that shift12 replaced ramp75 entirely. |

## 5. LP-DiD shift12 chain — the current headline (state, blind treat_def)

| config | run_name(s) | what it tests | output dir | ran? | current relevance |
|---|---|---|---|---|---|
| `power_lpdid_shift12_gate_noNV.yml` | `lpdid_shift12_gate_noNV` | state, size gate, `shift12_start_date` (online launch + 12mo uniform), NV excluded, twfe+lpdid, `lpdid_wild: true`, no `lpdid_weights` override (ran under the OLD default weighting) | `output_blinded_power/lpdid_shift12_gate_noNV/` | Yes, full results | SUPERSEDED — this is the "SHIFT12 BEATS RAMP75" 2026-08-21 headline (wild 0.0580 spliced, TWFE 0.0465), but its LP-DiD numbers ran under the pre-2026-08-24 `.re_lpdid` weighting bug (neither VWATT nor EWATT — CLAUDE.md: "every LP-DiD number ... was computed on the `cellsize` estimand"). Its TWFE arm is unaffected by the bug and is what the final PAP decision table's "TWFE analytic" row is drawn from. LP-DiD estimand superseded by `power_lpdid_shift12_gate_{ewatt,vwatt}.yml`. |
| `power_lpdid_shift12_mde_noNV.yml` | `lpdid_shift12_mde_noNV` | same, MDE curve — produced the (now dead) "shift12 MDE = 6.3%" headline | `output_blinded_power/lpdid_shift12_mde_noNV/` | Yes, full results | SUPERSEDED — same cellsize-weighting bug; corrected by `power_lpdid_shift12_mde_{ewatt,vwatt}.yml`. TWFE arm still valid/quoted. |
| `power_lpdid_shift12_gate_ewatt.yml` | `lpdid_shift12_gate_ewatt` | identical to `lpdid_shift12_gate_noNV.yml` except `lpdid_weights: ewatt` (the corrected 1/(1-D̄_cell) weighting = Dube-Girardi-Jordà-Taylor's equally-weighted ATT, matching what CS estimates) | `output_blinded_power/lpdid_shift12_gate_ewatt/` | Yes, full results | **CURRENT** — part of the "Final PAP decision table." EWATT+wild passes size (0.0325 vs the analytic 0.145 fail); EWATT inherits CS-like miscalibration because it puts full weight on thin late-cohort/long-horizon cells. |
| `power_lpdid_shift12_gate_vwatt.yml` | `lpdid_shift12_gate_vwatt` | identical, `lpdid_weights: vwatt` (plain OLS on the stack = the Cengiz et al. 2019 stacked-regression estimand) | `output_blinded_power/lpdid_shift12_gate_vwatt/` | Yes, full results | **CURRENT** — part of the decision table. VWATT+wild passes decisively in both windows (spliced 0.0515, postcovid 0.0615; SE/SD 1.14). |
| `power_lpdid_shift12_mde_ewatt.yml` | `lpdid_shift12_mde_ewatt` | EWATT MDE curve | `output_blinded_power/lpdid_shift12_mde_ewatt/` | Yes, full results | **CURRENT** — decision table row "LP-DiD ewatt + wild": size 0.0325, MDE 11.5% (the corrected headline that replaced the dead 6.3%). |
| `power_lpdid_shift12_mde_vwatt.yml` | `lpdid_shift12_mde_vwatt` | VWATT MDE curve | `output_blinded_power/lpdid_shift12_mde_vwatt/` | Yes, full results | **CURRENT** — decision table row "LP-DiD vwatt + wild": size 0.0515, MDE 8.75% — currently the best state MDE among size-valid arms. |

## 6. LP-DiD wild-bootstrap gate (pre-shift12, `online_start_date`)

| config | run_name(s) | what it tests | output dir | ran? | current relevance |
|---|---|---|---|---|---|
| `power_lpdid_wild_gate.yml` | `lpdid_wild_gate` | state, adds the wild-cluster-bootstrap inference arm to the LP-DiD size gate, WITH NV, `online_start_date`, post-rebuild panel | `output_blinded_power/lpdid_wild_gate/` | Yes, full results | SUPERSEDED — superseded by `lpdid_wild_gate_noNV` and then made redundant entirely: every `power_lpdid_shift12_*` config already bundles `lpdid_wild: true`. |
| `power_lpdid_wild_gate_noNV.yml` | `lpdid_wild_gate_noNV` | same, NV excluded | `output_blinded_power/lpdid_wild_gate_noNV/` | Yes, full results | SUPERSEDED — same reasoning; folded into the shift12 configs. |

## 7. L-DAM estimator gate (Antonelli et al. 2026 — candidate, not yet in the decision table)

| config | run_name(s) | what it tests | output dir | ran? | current relevance |
|---|---|---|---|---|---|
| `power_ldam_gate.yml` | `ldam_gate` | state, spliced window, size gate for twfe+did2s+lpdid+ldam, WITH NV | `output_blinded_power/ldam_gate/` | Yes, full results | ONE-OFF — L-DAM analytic is "catastrophically miscalibrated" (size 0.67-0.71, SE/SD 0.18-0.27); L-DAM+jackknife passes (size ~0.037, SE/SD ~1.0). A completed diagnostic; not adopted into the shift12-based decision table and has no MDE follow-up. |
| `power_ldam_gate_keepcovid.yml` | `ldam_gate_keepcovid` | same, but the full panel INCLUDING COVID months (tests whether L-DAM's AR conditioning absorbs state-specific COVID paths that break did2s), WITH NV | `output_blinded_power/ldam_gate_keepcovid/` | Yes, full results | ONE-OFF — novel-cell diagnostic; served its purpose, no follow-up. |
| `power_ldam_gate_keepcovid_noNV.yml` | `ldam_gate_keepcovid_noNV` | same, NV excluded (auto-generated 2026-08-21) | `output_blinded_power/ldam_gate_keepcovid_noNV/` | Yes, full results | ONE-OFF — NV-free pairing arm for the above; no follow-up. |
| `power_ldam_gate_noNV.yml` | `ldam_gate_noNV` | NV-free pairing arm for `ldam_gate.yml` | `output_blinded_power/ldam_gate_noNV/` | Yes, full results | ONE-OFF — no follow-up MDE run exists for any L-DAM cell. |
| `power_ldam_gate_postcovid.yml` | `ldam_gate_postcovid` | postcovid window (7 treated/10 never), WITH NV | `output_blinded_power/ldam_gate_postcovid/` | Yes, full results | ONE-OFF — no follow-up. |
| `power_ldam_gate_postcovid_noNV.yml` | `ldam_gate_postcovid_noNV` | postcovid window, NV excluded | `output_blinded_power/ldam_gate_postcovid_noNV/` | Yes, full results | ONE-OFF — no follow-up. L-DAM+jackknife is a real candidate the PAP could still promote, but as of 2026-08-25 it sits outside the shift12-based decision table entirely. |

## 8. Boundary / calendar-definition probes

| config | run_name(s) | what it tests | output dir | ran? | current relevance |
|---|---|---|---|---|---|
| `power_boundary_A_2021_08.yml` | `boundary_A_2021_08` | state, size gate at the framework's default post-COVID boundary (2021-08), twfe+did2s+lpdid, A=6mo anticipation | `output_blinded_power/boundary_A_2021_08/` | Yes, full results | ONE-OFF — paired against `boundary_B_2022_08` to price moving the boundary to the empirical stabilization median; served its purpose. |
| `power_boundary_B_2022_08.yml` | `boundary_B_2022_08` | same, boundary moved to 2022-08 (empirical filing-stabilization median) | `output_blinded_power/boundary_B_2022_08/` | Partial only | ONE-OFF (incomplete) — the comparison arm; never finished aggregating. |
| `power_boundary_A0_2021_08.yml` | `boundary_A0_2021_08` | same 2021-08 boundary, but loader `anticipation_months` (blindness buffer) set to 0 instead of 6, WITH NV | `output_blinded_power/boundary_A0_2021_08/` | Yes, full results | ONE-OFF — tests the pre-registered A∈{0,3,12} sensitivity space; recovers AZ/CT/LA/MD/WI vs A=6. Served its purpose. |
| `power_boundary_A0_noNV_2021_08.yml` | `boundary_A0_noNV_2021_08` | same, NV excluded | `output_blinded_power/boundary_A0_noNV_2021_08/` | Yes, full results | ONE-OFF — isolates NV's contribution at A=0; this is the cell CLAUDE.md's "NV-affected re-runs" section reports as D1-infeasible at 3,600/3,600 reps for the general (non-boundary-A0) case, but note this specific A=0 cell IS feasible (the general state-D1-infeasibility finding was specific to a different boundary probe). Served its purpose. |

## 9. Miscellaneous one-off diagnostics

| config | run_name(s) | what it tests | output dir | ran? | current relevance |
|---|---|---|---|---|---|
| `power_dose_tercile_gates.yml` | `dose_tercile_gates` | county, spliced window, δ=0 only, size gates (did2s+lpdid) for the four-quarters dose-response spec: pooled dose sample + top/bottom handle-per-adult terciles | `output_blinded_power/dose_tercile_gates/` | Yes, full results | ONE-OFF — feeds `quality_reports/strategy_memo_fourq_dose_response.md`; a calibration prerequisite for a possible dose-response robustness spec, not part of the headline MDE chain. |
| `power_time_agg_covid_gates.yml` | `time_agg_covid_gates` | state, CS calibration crossed over time aggregation (month/quarter/year) × COVID handling (drop/post/keep), δ=0, 13 feasible cells | `output_blinded_power/time_agg_covid_gates/` | Yes, full results | ONE-OFF — fully written up in CLAUDE.md ("Time Aggregation Does NOT Fix CS"): the COVID splice, not cohort granularity, drives CS's miscalibration; CS actually passes size on the clean post-COVID monthly window. Definitive negative result; no further runs planned. |
| `power_longdiff.yml` | `longdiff_power` | state, cohort-specific long-differences design ("Ben's estimator"), 4 scenarios ({spliced,keep} × {all states, excl NY}), twfe+lpdid benchmarks | `output_blinded_power/longdiff_power/` | Yes, full results | ONE-OFF — feeds the era-variance / 2×2 long-difference narrative (CLAUDE.md "Era Variance," "Binary 2x2 Long Difference" sections), not the shift12-based headline power spec. |
| `power_postcovid_maturation.yml` | `postcovid_maturation` | state, postcovid window, twfe+did2s+bjs+lpdid, compares `maturation50_start_date` (handle reaches 50% of peak) vs `online_start_date` | `output_blinded_power/postcovid_maturation/` | Yes, full results | ONE-OFF — exploratory alternative treatment definition; not adopted (shift12 became the blind state definition of choice instead). |
| `power_postcovid_maturation_county.yml` | `postcovid_maturation_county` | county companion, did2s+lpdid only (bjs failed the state gate) | `output_blinded_power/postcovid_maturation_county/` | Yes, full results | ONE-OFF — same reasoning; superseded in spirit by `power_county_cs_adaptive.yml`'s did2s-remains-headline conclusion. |
| `power_postcovid_maturation_county_wild.yml` | `postcovid_maturation_county_wild` | county, lpdid only, wild-bootstrap arm (all county-postcovid analytic arms failed the size gate: did2s 21.5-23.9%, lpdid 11.7-14.0%) | `output_blinded_power/postcovid_maturation_county_wild/` | Yes, full results | ONE-OFF — completed the maturation-treat_def exploration; not carried forward. |

---

## Lineage chains

Reading top-to-bottom = chronological supersession. Bold = still current.

**State LP-DiD size gate (spliced window):**
```
power_lpdid_gate.yml (online, WITH NV, pre-rebuild)
  -> power_lpdid_gate_noNV.yml (online, NV-free)
     [power_lpdid_gate_newpanel.yml staged to re-pair WITH-NV on rebuilt panel — NEVER RUN]
  -> power_lpdid_ramp75_gate.yml (ramp75, WITH NV) [ran only as ad hoc override "lpdid_ramp75_gate_v2", no tracked config]
     -> power_lpdid_ramp75_gate_noNV.yml (ramp75, NV-free)
        -> power_lpdid_shift12_gate_noNV.yml (shift12, NV-free, pre-2026-08-24 weighting bug)
           -> **power_lpdid_shift12_gate_ewatt.yml** (corrected equal-weight)
           -> **power_lpdid_shift12_gate_vwatt.yml** (corrected variance-weight)
power_lpdid_wild_gate.yml / power_lpdid_wild_gate_noNV.yml
  -> folded into the shift12 configs (lpdid_wild: true is now bundled by default)
```

**State LP-DiD MDE (mirrors the gate chain exactly):**
```
power_lpdid_mde.yml -> power_lpdid_mde_noNV.yml
  [power_lpdid_mde_newpanel.yml staged — NEVER RUN]
  -> power_lpdid_ramp75_mde.yml -> power_lpdid_ramp75_mde_noNV.yml
     -> power_lpdid_shift12_mde_noNV.yml (pre-fix weighting)
        -> **power_lpdid_shift12_mde_ewatt.yml**
        -> **power_lpdid_shift12_mde_vwatt.yml**
```

**County LP-DiD:** `power_lpdid_mde_county.yml` — a single branch off the state
chain, abandoned mid-run (batch 5/12 spliced, 7/30 postcovid) on 2026-08-17;
no successor config exists. `power_lpdid_ramp75_anchor.yml` is a side-branch
diagnostic off the ramp75 arm (anchor-point sensitivity), also abandoned once
ramp75 itself was superseded.

**CS-DiD:**
```
power_cs_probe.yml (shift-mode validation, state)
power_county_cs.yml (shift-mode, county) — barred by 2026-08-18 code review
  -> **power_county_cs_adaptive.yml** (adaptive-grid, genuine full estimates)
power_state_cs_adaptive_check.yml — validates the adaptive machinery itself (gate 6), ran under overridden names
```

**Run-ladder tiers** (`power_smoke.yml` → `power_cheap.yml` → `power_primary.yml`
/ `power_sensitivity.yml` / `power_addon1.yml`) are a separate, earlier lineage:
built for the Della cluster run ladder before the schedule repair (2026-08-10)
and panel rebuild (2026-08-20) existed. None were re-run after either fix;
the project's live work moved to the targeted single-cell gate/MDE configs
documented above instead of re-running the broad grids.

**L-DAM** (`power_ldam_gate.yml` and its 5 covid/NV variants) and the
**boundary probes** (`power_boundary_*.yml`) and **maturation50** treat_def
(`power_postcovid_maturation*.yml`) are each self-contained one-shot
diagnostics with no further chain — they answered one question each and were
not iterated on.

**Ad hoc output directories with no matching tracked config file** (found by
cross-referencing `output_blinded_power/*` against every `run_name:` in
`config/*.yml`): `lpdid_ramp75_gate_v2` and `lpdid_mde_fixedpanel`, both
referenced by name in root `CLAUDE.md` and in the header comments of
`power_lpdid_ramp75_mde.yml` / `power_lpdid_ramp75_mde_noNV.yml`. Both appear
to be manual `run_name:` overrides of `power_lpdid_ramp75_gate.yml` and
`power_lpdid_mde.yml` respectively, run once right after the 2026-08-20 panel
rebuild and never saved back as permanent config files.
