# Power-Simulation Blindness Protocol

**Date:** 2026-07-23
**Scope:** All work on the blinded power-simulation framework (`R/power/`, `config/power_*.yml`,
`output_blinded_power/`, `tests/`) and the pre-analysis-plan documents it supports.

## 1. Purpose

The power simulation exists to choose a primary specification for a pre-analysis plan **before**
looking at the actual estimated effect of sports-gambling legalization on evictions. If actual
post-treatment estimates influence the effect grid, the calibration sample, or the specification
choice, the pre-analysis plan loses its evidentiary value. This protocol defines what may and may
not be used, and the automated checks that enforce it.

## 2. Allowed inputs

- **Treatment schedule** (`data/raw/sports_gambling_legalization_dates.csv`): all legalization
  dates and treatment definitions (online / retail / first). Treatment timing is design
  information, not an outcome.
- **Untreated outcome data**, accessed **only** through `R/power/load_blinded_panel.R`:
  - state-months (and their county-months) strictly before the state's own treatment date minus
    the anticipation exclusion window (§4); and
  - all state-months of never-treated states.
- **Schemas and metadata** of any data file: variable names, types, row counts, date coverage,
  missingness, panel balance. (Not outcome values in treated periods.)
- **Active R code**: analysis scripts, package code, patches, shell runners.
- **Methodology documentation** that does not report actual treatment estimates.
- **Literature** (papers in `Literature/`, external replication code such as
  `hollina/power-analysis`), including *published* effect sizes from other studies — these anchor
  the effect grid.
- **Treatment-intensity data** (betting handle/revenue): structure and dates only, for designing
  intensity-proportional effect scenarios. Not merged against eviction outcomes.

## 3. Prohibited inputs

- `output/` — all contents (CSVs, logs, run logs, READMEs, HANDOFF documents).
- `figures/` and any generated PNG/PDF plots or regression tables.
- `output/border_diagnostic/HANDOFF.md` specifically.
- Any cached simulation output derived from the actual treatment analysis.
- Result/findings/estimates sections of `CLAUDE.md`, `AGENTS.md`, `README.md`, `START_HERE.md`,
  `QUICK_START.md`, `SESSION_REPORT.md`, `docs/DIAGNOSTIC_FINDINGS_SUMMARY.md`,
  `docs/literature_review_2026-07_estimation_strategy.md`, and any similar document.
- Actual post-legalization eviction outcomes for treated states (any transformation), and any
  statistic comparing treated post-periods to anything.
- The project's own estimated ATTs, event studies, pre-trend test results on real data, or
  per-state effect decompositions — in any file, including code comments. Where encountered
  incidentally, they are not recorded or used.

## 4. Outcome cutoffs and anticipation exclusions

- **Universal untreated cutoff:** 2018-05-31. First launch is Delaware retail 2018-06; first
  online launch is NJ/WV 2018-08. The strict universal calibration sample (S1) uses months
  2016-01 through 2018-04 (with 2018-05 optionally retained under retail definitions only if the
  loader's definition-specific cutoff allows it; default is to drop it).
- **State-specific cutoff (risk-set samples):** for state *s* with treatment date *g_s* under the
  chosen treatment definition, outcomes are usable only for months *t* ≤ *g_s − 1 − A* where *A*
  is the anticipation exclusion window in months. **Default A = 6**; sensitivity values
  A ∈ {0, 3, 12}. Never-treated states have no cutoff.
- **Treatment definition:** cutoffs are computed per definition (`online_start_date`,
  `retail_start_date`, `first_start_date`). The loader uses the **earliest** date across
  definitions (`first_start_date`) by default, so no sample is "untreated" under one definition
  while treated under another.
- **COVID windows:** untreated data are additionally partitioned into pre-COVID
  (before 2020-03), COVID (2020-03 to 2021-07 / 2022-03 sensitivity), and post-COVID segments so
  calibration can be run within homogeneous variance regimes. This partition affects which
  untreated months enter a calibration sample; it never re-admits treated months.

## 5. Automated enforcement (`R/power/blindness_checks.R`)

1. **Single point of entry.** All simulation code obtains outcome data via
   `load_blinded_panel()`. The loader joins the treatment schedule, applies the cutoffs in §4,
   and drops treated/anticipation rows *before* returning.
2. **Post-return assertion.** `assert_blinded(panel, schedule, anticipation)` re-verifies that no
   returned row violates the cutoff; it runs inside the loader and again inside
   `validate_simulation.R`. Violations are hard errors, not warnings.
3. **Prohibited-path guard.** `assert_no_forbidden_paths(path)` refuses to read any file whose
   normalized path falls under `output/`, `figures/`, or other prohibited locations; all file
   reads in `R/power/` go through it.
4. **Output isolation.** All framework outputs are written to `output_blinded_power/` only. The
   writer helper errors if the target resolves outside that directory. The directory contains
   only simulated operating characteristics, imposed truths, metadata, seeds, and logs.
5. **Metadata stamping.** Every simulation output records: calibration sample ID, cutoff dates,
   anticipation window, treatment definition, seed, and a flag confirming `assert_blinded`
   passed.
6. **Tests.** The testthat suite includes tests that the loader never returns a treated or
   anticipation-period observation and that no framework function reads from prohibited
   directories (see `tests/testthat/test-blindness.R`).

## 6. Human-process rules

- Effect grids, calibration-sample choices, and the specification decision rule are fixed in
  `POWER_SIMULATION_DESIGN.md` from policy benchmarks and **external** literature, with sources
  documented, before any operating characteristics are computed.
- No specification is selected because it maximizes power; the decision rule (design doc §
  "Selection rule") screens on size/coverage/stability first.
- Calibration-sample comparisons report **all** samples' results; none is dropped for being
  unfavorable.

## 7. Disclosure: known context exposures

- **Orchestrator and subagent exposure (2026-07-23).** The Claude Code session that built this
  framework had the project `CLAUDE.md` auto-loaded into context by the harness *before* the
  blinded task began, and the same harness behavior applies to implementation subagents.
  `CLAUDE.md` embeds some real-data headline estimates. Mitigations applied: (a) all
  subagents that read code/data were instructed never to open, quote, or use
  `CLAUDE.md`/`AGENTS.md`/`output/`, and reported no estimate values; (b) the effect grid and all design constants in
  `POWER_SIMULATION_DESIGN.md` are derived exclusively from external literature and policy
  benchmarks, each with a documented source; (c) no design choice in this framework references
  or is conditioned on the project's own estimates. Residual risk: the orchestrating model
  cannot verifiably "unsee" the exposure; a reader auditing the pre-analysis plan should check
  that every effect-grid value traces to its documented external source (they do — see design
  doc § "Effect-size grid, with sources").
- Several legacy simulation scripts print real-data ATT sanity-check lines when run; the new
  framework does not run those scripts, and their printed values were not recorded during the
  audit.

## 8. What blindness does NOT restrict

Simulation *operating characteristics* computed on untreated data with imposed known effects
(power, size, coverage, MDE, bias) are not "results" in the prohibited sense — they are the
product of this framework and may be freely inspected, reported, and used to choose the primary
specification. Similarly, prior *published* effect sizes from other papers are allowed anchors.

## Deviation log

### 2026-08-15 — LP-DiD real-data estimates produced mid-session

While evaluating LP-DiD (Dube, Girardi, Jorda & Taylor 2023) as a candidate
estimator, real-data treated-period estimates were produced
(`analysis/main/lpdid_statepanel.R`; pooled ATTs under two treatment-date
definitions, an event study, and pre-trend tests) and compared against the
project's existing headline estimate — both prohibited inputs under §3.

Mitigating facts, verified at the time of the deviation:
- The effect grid, calibration samples, and decision rule in
  `config/power_*.yml` were committed 2026-08-03 (`12725a5`) and have not been
  modified since; no framework parameter was set after exposure.
- The outputs live under `output/`, which §3 already designates prohibited.
- Estimator/level selection is a mechanical rule (size gate, then MDE among
  survivors), leaving no post-exposure judgment call in the selection itself.

Consequence for interpretation: the analyst is no longer blind. LP-DiD's
admission to the candidate set was motivated in part by its identifying
assumption (local, gap-respecting) and in part by the real-data work above;
its performance in the PAP is assessed exclusively by the blinded size gate
(`config/power_lpdid_gate.yml`) and MDE ladder on simulated outcomes over
untreated data. Any future deviation should be appended here rather than
left implicit.
