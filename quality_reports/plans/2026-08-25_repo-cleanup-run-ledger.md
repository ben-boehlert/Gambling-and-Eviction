# Plan: Repo cleanup — run ledger, findings doc, CLAUDE.md slim, stale-output moves

**Status:** APPROVED (Ben, 2026-08-25; design discussed in-session)
**Orchestration:** Fable session orchestrates; Sonnet subagents execute; one Opus review pass at the end (per `model-routing` skill).

## Scope (user-selected)
1. **Run registry** — `RUN_LEDGER.md` (root), markdown tables per domain. One row per run: name, date, config/script, panel vintage (pre/post 2026-08-20 rebuild), schedule vintage (pre/post 2026-08-10 repair), NV in/out, LP-DiD weights where relevant, headline number, output path, status.
   - Statuses: `LIVE`, `SUPERSEDED (→ x)`, `CONTAMINATED (reason)`, `DEAD`, `EXPLORATORY`, `UNKNOWN` (flagged for human review).
2. **FINDINGS.md** (root) — current truth only: PAP decision table, recommended specs, live calibration verdicts, standing traps. No history.
3. **CLAUDE.md slimmed** — keeps structure/data/conventions/how-to-run + pointers; chronological findings entries move to `docs/findings-archive/` split by topic. Nothing deleted.
4. **Move + index** — only SUPERSEDED/DEAD/CONTAMINATED output dirs move to `output/deprecated/` and `output_blinded_power/deprecated/`; root relics to `deprecated/`; paper PDFs to `Literature/` (originals to `deprecated/`). All moves recorded in `MOVES.md` (old → new). LIVE dirs never move.

**Out of scope:** branch reconciliation/pruning (git hygiene) — except one pre-cleanup snapshot commit.

## Key vintage boundaries (classification rules; full detail in CLAUDE.md)
- 2026-08-10: treatment-schedule repair (ME/VT/KY/FL → treated)
- 2026-08-20 01:26: state-panel rebuild (double-count fix); pre-rebuild state-panel results contaminated per CLAUDE.md list
- 2026-08-21: NV exclusion audit
- 2026-08-24: LP-DiD weights fix (cellsize → ewatt/vwatt); all prior LP-DiD MDEs on dead estimand
- Pretrends `+0.080` figure dead (integer-g bug); current baseline `+0.020` (A: unconditional)

## Phases
0. Snapshot commit of tracked changes (untracked outputs stay untracked — no 500MB commit).
1. Four parallel Sonnet agents produce inventories in `quality_reports/cleanup_2026-08-25/`:
   - `inventory_output.md` (89 dirs in `output/`)
   - `inventory_blinded_power.md` (92 entries in `output_blinded_power/`)
   - `inventory_configs.md` (49 files in `config/`, mapped to run_names/outputs)
   - `run_history.md` (mined from SESSION_REPORT.md, quality_reports/, git log)
2. Sonnet merges → `RUN_LEDGER.md`. Checkpoint: orchestrator sanity-check before moves.
3. Sonnet writes `FINDINGS.md`; splits CLAUDE.md history → `docs/findings-archive/`; slims CLAUDE.md; adds ledger-maintenance rule to CLAUDE.md.
4. Scripted moves from ledger classification; `MOVES.md` written.
5. Opus review (high effort): ledger statuses vs sources, FINDINGS.md numbers vs source files, CLAUDE.md slim didn't lose load-bearing rules.
6. Commit(s); SESSION_REPORT.md entry.

## Verification
- Every non-LIVE status cites its rule/evidence (V2 trail).
- FINDINGS.md numbers traced to source CSVs/memos, not memory.
- After moves: `Rscript -e 'source(...)'` spot-check that no LIVE pipeline references a moved path.
