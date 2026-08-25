> Archived verbatim from CLAUDE.md on 2026-08-25 (repo cleanup). Historical record — numbers here may be superseded; current truth lives in FINDINGS.md, statuses in RUN_LEDGER.md.

## Blinded Power-Simulation Framework (Pre-Analysis Plan)

Blinded (untreated-data-only) calibration + power simulation supporting the Arnold Ventures
pre-analysis plan. Code: `R/power/` (9 modules). Configs: `config/power_*.yml`. Methodology:
`docs/methodology/POWER_SIMULATION_{DESIGN,BLINDNESS_PROTOCOL,CODE_AUDIT}.md`. Cluster package:
`della_power_upload/`, rebuilt by `scripts/make_della_power_upload.sh`; runs on Princeton Della at
`/scratch/gpfs/DESMOND/ben/eviction_gambling/della_power_upload/` (see `scripts/della_power/README.txt`
for upload/run/monitor commands).

**Purpose in the PAP** (decided 2026-08-07/08-10): estimator and aggregation-level selection is
pre-registered as a *decision rule*, not a named estimator — (1) size gate: any estimator × level
cell whose δ=0 rejection is materially off nominal is disqualified; (2) MDE among survivors picks
the headline spec. This converts the post-hoc-looking did2s choice (CS/SunAb are miscalibrated on
this design; see calibration tables above) into a blinded, pre-committed selection. AV guidance
(`AV_Pre-Analysis_Plan_Guidance_202507.pdf`): QED checklist, ≤6 pages, MDEs in real-world terms.

**Run ladder** (validate cheap before spending on CS — `att_gt` is the cost driver, ~2,750 fits
per county scenario):

| Run | Config | Scenarios | Estimators | Cost | Status |
|-----|--------|-----------|-----------|------|--------|
| smoke | `power_smoke.yml` | 2 (county+state headline) | twfe, did2s; 50 reps × 4 δ | ~1h county, <1 min state | run 12220717, 2026-08-10 |
| cheap | `power_cheap.yml` | 8 (4 county, 4 state) | twfe, did2s; 500 reps × 11 δ | ~28–30h county tasks | ready |
| primary | `power_primary.yml` | 11 (S3 blocks infeasible → effectively 9) | + cs (250 reps) | 50–63h per county task | partial (see below) |
| sensitivity | `power_sensitivity.yml` | 26 (one axis at a time) | varies | state-level baseline | not started |

Key mechanics:
- `seed_rep = base_seed + 10007*rep + 101*scenario` with `base_seed = 20260723` shared across all
  configs → a later CS-only run sees the identical simulated panels rep-for-rep (paired comparisons
  across runs).
- Scenario ids are content hashes of the scenario's own settings → resubmitting skips completed
  partials; editing one config block never invalidates another's partial. Config edits that change
  the scenario COUNT require updating `--array` in the matching `run_*.slurm`.
- `est_anticipation` is a CS-only knob (`att_gt` argument; `R/power/run_estimators.R`) — pointless
  in CS-free runs.

**S3 × D1 infeasibility (diagnosed 2026-08-10).** D1 (cohort-preserving reassignment) places the
*full* real online template — 18 cohorts, ~24 treated states, 55-month span — but S3 (never-treated
sample) has only 12 (county) / 14 (state) states. Structurally infeasible; no `min_pre`/`min_post`
relaxation helps. The two S3 primary tasks fail in ~10 s at startup. Resolution: S3 dropped from D1
blocks (done in `power_cheap.yml`; pending in `power_primary.yml`); the never-treated comparison
belongs to design D4, which scales cohort counts proportionally (sensitivity `alt_designs`; consider
promoting a D4 block to primary). The PAP should report this infeasibility explicitly.

**First primary run (Della job 12114571, submitted 2026-08-08).** 4 state scenarios completed
(6–13h each); 2 S3 tasks failed instantly (above); 5 county tasks were **OOM-killed at ~42h**
(exit 0:125, `sacct` state OUT_OF_MEMORY — NOT walltime): the runner accumulates every batch in
RAM and writes the partial CSV only after all 20 batches, so CS's 13–19k-row batches climbed into
the 16G ceiling and **all work was lost** (no batch-level checkpointing; the per-batch log lines
are progress display only). Pacing facts: county twfe+did2s ≈ 1.5h per 25-rep batch (11 δ);
CS batches ≈ 4–5h; county+CS needs ~50–63h total. Before resubmitting the CS arm: add per-batch
checkpoint/resume (fixes both the OOM and the loss-on-death), raise `--time` to ~72h, and raise
`--mem`.

**2026-08-10 evening findings (smoke-ladder debugging — read before touching the framework):**
- **`fwildclusterboot` is ARCHIVED from CRAN.** Della's setup silently skipped it → every wild
  row of the first smoke run failed. Fixed: `setup.sh` now installs from the s3alfisc r-universe
  repo and hard-fails if absent.
- **boottest memory bomb, fixed.** `boottest()` without `fe = "id"` dummy-expands ~1,200 county
  FEs → ~1.8 GB peak per worker → 8×16G OOM in 2 min (job 12223288). `run_estimators.R` now
  passes `fe = "id"`: ~0.6 GB, 5× faster, identical p-value.
- **D1 on county/S2 is deterministically infeasible under the current code+data** (verified
  50/50 rep failures with the runner's exact seed path, reproduced identically on laptop and
  Della). The national 24-state template into the ~29-state county-S2 pool with per-state
  coverage windows does not place.
- **REPRODUCIBILITY "ANOMALY" — RESOLVED (2026-08-10 ~23:45).** The mid-day feasibility flip
  was caused by commit `2be0bd0` (16:16, a CONCURRENT session's deliberate data repair):
  `sports_gambling_legalization_dates.csv` had frozen ~early 2023 and was repaired to add
  online dates for DE, NC, KY, ME, FL, VT, MO (verified vs regulators/LSR). The online
  template grew ~24 → ~31 states, tipping national-D1 placement into infeasibility. Runs
  before the repair reached Della (old CSV) succeeded; runs after the 19:15 rsync failed; all
  local checks compared against a HEAD that had already moved. No nondeterminism ever existed.
  **Lesson: when deterministic code changes behavior, check `git log` (including concurrent
  sessions' commits) before anything else.** Pre-repair smoke partial (old schedule + harsher
  national template — the source of the spurious "did2s 31% Type I" reading) preserved at
  `output_blinded_power/smoke_prewildfix/` on Della; old CSV in `data/raw/deprecated/`.
- **Schedule repair ripple (IMPORTANT, beyond the sims):** ME, VT, KY, FL are **no longer
  never-treated controls** (online Nov 2023 / Jan 2024 / Sep 2023 / Dec 2023; MO Dec 2025 is
  post-panel). The pretrends headline results above ("26 states, 12 treated, 14 never-treated,
  ME included as control") predate the repair and are STALE — re-run the pretrends pipeline
  with the repaired schedule. FL's voided 2021 online launch (West Flagler) needs a PAP flag.
- **Panel-restricted template — IMPLEMENTED (2026-08-10 ~22:30), first results good.**
  `template: panel` config axis (D1 places treated-states-in-panel; 17 county cohort states
  under the repaired schedule); per-rep schedule infeasibility now yields failure rows instead
  of aborting the scenario. National-template ids unchanged (conditionally hashed). Smoke on
  the corrected design: **county did2s 4.1% Type I / SE-SD 0.96; county TWFE-wild 4.0%; state
  did2s 23-29% Type I (disqualified); TWFE analytic ~10% county (wild fixes it)**. Local Mac
  reproduces Della's analytic numbers bit-for-bit (wild differs 1-2 reps: bootstrap RNG layer;
  did2s convergence 48 vs 49/50: BLAS). Full 500-rep state cheap results (local): did2s
  disqualified; TWFE-wild calibrated but MDE > 20% under the count_nb DGP — far above the
  application's old "5% state MDE" claim; county (Della job 12248328, ~Tue) is the headline.
  Mac is ~6x faster per rep than a Della node — use local runs for smoke-scale work.

- Pre-COVID period (2016-2020) has better parallel trends than the full sample
- Idaho is excluded from annual analyses due to data quality issues
- Maine: was excluded for a late-2023 zero-fill data artifact; **repaired 2026-07-23** from the Maine Judicial Branch court source (`data_prep/monthly_panel_expansion/07_repair_me_from_court_source.R`, `08_repair_me_in_county_files.R`) and now included as a never-treated control
- **UPDATED 2026-05-21**: Main finding has been substantially revised after a session-long methodological diagnostic. See `output/border_diagnostic/HANDOFF.md` for the full reframing. Headline points:
  - The state-panel "MDE = 5%" claim is wrong as a precision constraint. Going from state aggregates to county-level data with state clustering shrinks the simulated cluster-robust SE by ~5× (Sim D in the 4-way decomposition).
  - Under a homogeneous-effect DGP, the all-county TWFE MDE is ~2%. Under realistic cohort heterogeneity, the actual real-data SE is ~10× larger; the realistic MDE is ~8–10%.
  - The pooled null was masking substantial cohort heterogeneity. Per-state did2s ATTs range from −57% (NH, a data artifact) to +34% (AR). 8 of 13 states show statistically significant positive ATTs in the +6% to +12% range.
  - **New recommended headline: did2s on pre-COVID-treated cohorts excluding NH = +9.1%, CI [−0.10%, +17.5%]** (borderline significant, consistent with Hollenbeck et al. 2025).
  - The previous "5% MDE TWFE state-panel" spec stays as a robustness check, not the headline.
- See `output/border_diagnostic/HANDOFF.md` for the complete narrative of the diagnostic and recommended next steps.

