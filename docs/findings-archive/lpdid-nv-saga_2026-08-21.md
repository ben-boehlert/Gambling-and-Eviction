> Archived verbatim from CLAUDE.md on 2026-08-25 (repo cleanup). Historical record — numbers here may be superseded; current truth lives in FINDINGS.md, statuses in RUN_LEDGER.md.

### NV-FREE LP-DiD QUEUE COMPLETE — HEADLINE MDE IS 7.1%, NOT 6.0% (2026-08-21)

7 gates + `lpdid_mde` re-run NV-free. **Correction to the earlier entry: the
state LP-DiD MDE to quote is the WILD arm at 0.0707, not the analytic 0.0597.**
Under size-gate-first the analytic arm does not qualify.

**ramp75 / spliced / LP-DiD size, pooling the gate and MDE runs (600 reps each):**

| inference | NV in | NV out | verdict |
|---|---|---|---|
| analytic | 0.0667 CI [0.048, 0.090] | 0.0733 CI [0.054, 0.097] | **BORDERLINE — CI straddles 0.075 either way** |
| wild | 0.0367 CI [0.023, 0.055] | 0.0367 CI [0.023, 0.055] | **PASS decisively** |

**300 reps cannot classify a cell near the 0.075 line** (MC SE = 0.0147 at p=0.07).
The gate and MDE runs of the IDENTICAL ramp75 config returned 0.083 and 0.063 —
independent draws, both consistent with ~0.073. Gate decisions on borderline
cells need ~2,000+ reps; do not classify off a single 300-rep run.

**Treatment definition matters more than NV.** `online_start_date` LP-DiD fails
size everywhere (spliced 0.103, postcovid 0.092 NV-free) and its low MDE (0.0487)
is the SEs-too-small artifact. Only `ramp75` yields a size-valid LP-DiD arm.

**LDAM: analytic inference is catastrophically miscalibrated** — size 0.67-0.71
with SE/SD 0.18-0.27 across all three gates. **LDAM+jackknife passes** (0.037,
0.030, 0.010; SE/SD ~1.0). Never quote LDAM analytic.

**Two gates still unpairable** (pre-rebuild baselines): `lpdid_gate`,
`lpdid_gate_postcovid`. `config/power_*_newpanel.yml` staged as queue B.

**shift12 has NO power run and is not a valid `treat_def`** in
`load_blinded_panel` (accepts only online/maturation50/ramp75). See the ramp75
vintage-artifact finding below — shift12 is the blind alternative worth testing.

### PANEL-ERA TRAP WHEN PAIRING POWER ARMS (2026-08-21)

**Before comparing any two blinded-power runs, check they were run on the same
panel.** The state panel was rebuilt 2026-08-20 01:26. Runs before that report
**38/17** treated+control clusters; runs after report **33/15**. Pairing across
the boundary attributes a panel change to whatever else differs.

| pre-rebuild (do NOT pair with new arms) | post-rebuild (safe to pair) |
|---|---|
| `lpdid_gate` (08-15), `lpdid_gate_postcovid` (08-17), `lpdid_mde` (08-17) | `lpdid_ramp75_mde`, `lpdid_wild_gate`, `lpdid_ramp75_gate_v2`, `lpdid_mde_fixedpanel` (08-20); `ldam_gate{,_keepcovid,_postcovid}` (08-21) |

**A plain resume does NOT fix a stale run.** Scenario ids hash the scenario
SETTINGS, not the data, so re-running an old config under its original run_name
reuses the pre-rebuild partials. Use a fresh `run_name` (see
`config/power_*_newpanel.yml`).

**The ramp75 MDE NV comparison above is unaffected** — both arms are post-rebuild
(33 vs 32 clusters) — and stands as reported. The `lpdid_gate` NV comparison is
NOT valid and is being re-based.

### LP-DiD POWER TESTS ARE NV-CONTAMINATED — AND NV WAS HURTING THEM (2026-08-21)

**Every completed LP-DiD/LDAM power result in this repo is state-level, hence
NV-contaminated.** 9 of 10 configs are `level: state` (`power_lpdid_{gate,
gate_postcovid,mde,ramp75_gate,ramp75_mde,wild_gate}.yml`, `power_ldam_gate*.yml`).
At state level the S2 panel carries NV (33 states) and under D1 any unassigned
state is a CONTROL — and NV, having no launch date, can never be gated out by the
hybrid launch-date control coding, so it is a permanently eligible control.
The only NV-free arm, `power_lpdid_mde_county.yml`, **was never finished**: it
stopped at batch 5/12 (spliced) and 7/30 (postcovid) on 2026-08-17 and has
`partials/` but no `mde_table.csv`/`oc_summary.csv`.

**Paired re-run of the headline ramp75 cell** (`power_lpdid_ramp75_mde_noNV.yml`,
300 reps x 13 deltas; `exclude_states` is conditionally hashed so ids do not
collide): **removing NV IMPROVES the state spliced cell materially.**

| cell / estimator | with NV | no NV |
|---|---|---|
| spliced LP-DiD analytic MDE | 0.0733 | **0.0597** |
| spliced LP-DiD wild MDE | 0.0933 | **0.0707** |
| spliced LP-DiD SE/SD | 0.860 | **0.979** |
| spliced LP-DiD size | 0.063 | 0.063 (still passes) |
| spliced TWFE analytic MDE | 0.1269 | **0.0797** |
| postcovid LP-DiD analytic MDE | 0.2120 | 0.2144 (flat) |
| postcovid TWFE analytic size | 0.040 | **0.097 — now FAILS the gate** |

Mechanism: an always-treated state in the control pool adds heterogeneity to the
controls, inflating estimator SD and depressing SE/SD. Dropping it tightens
calibration (0.86 -> 0.98) and shrinks the MDE ~19%. **The headline state LP-DiD
MDE should be ~6.0%, not 7.3%** — and NV was MASKING TWFE's post-COVID
miscalibration (size 4.0% -> 9.7% once removed).

**Correction to the 2026-08-21 note above:** state D1 is NOT generally infeasible
without NV. Placement succeeds 40/40 on both the spliced (32 states) and
post-COVID (14 states) panels. The 3,600/3,600 failure was specific to the
`boundary_A0` cell (loader anticipation A=0, 2021-08 boundary), not to state D1.

**Still to re-run NV-free:** `lpdid_gate`, `lpdid_gate_postcovid`, `lpdid_mde`,
`lpdid_wild_gate`, `lpdid_ramp75_gate`, `ldam_gate{,_keepcovid,_postcovid}`, and
the abandoned county arm.

