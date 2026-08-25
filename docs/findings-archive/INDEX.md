# Findings Archive — Index

Chronological findings, corrections, and dead numbers extracted verbatim from CLAUDE.md during the 2026-08-25 cleanup. **Nothing here is guaranteed current.** Current truth: [FINDINGS.md](../../FINDINGS.md). Run statuses: [RUN_LEDGER.md](../../RUN_LEDGER.md). The full pre-slim CLAUDE.md is preserved at `deprecated/CLAUDE_2026-08-25_pre-slim.md` and in git history (commit `b791dc0` and earlier).

New corrections and post-mortems get their own dated file here — CLAUDE.md no longer accumulates findings.

| File | Covers |
|---|---|
| [blinded-power-framework-notes_2026-08.md](blinded-power-framework-notes_2026-08.md) | Run-ladder status, Della job history (OOM at 42h, wildclusterboot archive, boottest memory bomb), D1 infeasibility diagnoses, the 2026-08-10 "reproducibility anomaly" resolution, panel-restricted template results |
| [calibration-history_2026-04_to_05.md](calibration-history_2026-04_to_05.md) | Original state-panel estimator calibration (CS 14% / SunAb 21%), the superseding county-level calibration table, legacy CS threshold-sweep behavior |
| [empirical-results-summary_pre-cleanup.md](empirical-results-summary_pre-cleanup.md) | Pre-cleanup eviction + mortgage results narrative, Hollenbeck et al. comparison, handle-maturation quintile table, old support-structure and power-results sections |
| [state-panel-rebuild_2026-08-20.md](state-panel-rebuild_2026-08-20.md) | The 12-state double count: discovery, rebuild, contaminated/immune lists, TWFE-power-sim exoneration, composition-churn caveats, provisional post-rebuild pretrends |
| [lpdid-weighting-and-cs-equivalence_2026-08-24.md](lpdid-weighting-and-cs-equivalence_2026-08-24.md) | The cellsize-estimand error (dead 6.3%/8.1% MDEs), corrected ewatt/vwatt runs, final PAP decision table derivation, DGJT footnote-23 equivalence and the contiguity break |
| [shift12-vs-ramp75_2026-08-21.md](shift12-vs-ramp75_2026-08-21.md) | shift12 treatment definition, the ramp75 vintage artifact (0.957 correlation with observation window), size-gate comparison |
| [lpdid-nv-saga_2026-08-21.md](lpdid-nv-saga_2026-08-21.md) | NV-free LP-DiD re-run queue, the 7.1%-not-6.0% correction, panel-era pairing trap, how NV entered state control pools |
| [nv-audit_2026-08-21.md](nv-audit_2026-08-21.md) | NV footprint sweep (build_state_panel fallback path), NV-affected re-runs table, state-D1 infeasibility without NV, era-variance revision |
| [pretrends-lottery-conditioning_2026-08-21.md](pretrends-lottery-conditioning_2026-08-21.md) | The +0.080 integer-g bug post-mortem, lottery-vintage conditioning specs A/B/C, the SunAb coefficient-mask fix |
| [adoption-universe_2026-08-21.md](adoption-universe_2026-08-21.md) | Absent-row trap in the legalization schedule, Nevada always-treated rule, canonical universe helpers |
| [cs-execution-and-county-verdict_2026-08.md](cs-execution-and-county-verdict_2026-08.md) | cs_safe_patches / cs_faster_mode flags (non-estimating code path), county CS adaptive-MDE verdict (no finite MDE) |
| [design-diagnostics_2026-08-19.md](design-diagnostics_2026-08-19.md) | Time aggregation vs the COVID splice, binary 2×2 long-difference pseudo-power verdict, era-variance findings (Idaho trap, averaging inertness) |
