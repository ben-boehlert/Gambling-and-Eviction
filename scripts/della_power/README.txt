BLINDED POWER-SIMULATION FRAMEWORK — DELLA UPLOAD PACKAGE
=========================================================

Self-contained upload of the blinded power-simulation framework
(Gambling-and-Eviction project). Built by scripts/make_della_power_upload.sh
in the main repository; do not edit files here — edit the repo and rebuild.

WHAT THIS RUNS
  Simulated power analysis on UNTREATED eviction data only, with known
  imposed effects (Black et al. 2022 style, adapted to staggered adoption).
  See docs/methodology/POWER_SIMULATION_DESIGN.md and
  POWER_SIMULATION_BLINDNESS_PROTOCOL.md (both included).

UPLOAD (from your laptop)
  scp -r della_power_upload della:/scratch/gpfs/DESMOND/ben/eviction_gambling/
  # any /scratch path works — nothing here hardcodes the location

RUN (on Della, in order)
  1. bash setup.sh              # once, LOGIN node — installs CRAN packages
  2. bash run_validation.sh     # login node, ~5 min — tests + BHNS validation
  3. sbatch run_primary.slurm       # 16 cores, <24h; resume-safe
  4. sbatch run_sensitivity.slurm   # 16 cores, <48h; run after primary

MONITOR
  squeue -u $USER
  tail -f slurm-power-primary-<jobid>.out   # per-scenario progress lines

RESUME AFTER TIMEOUT
  Just sbatch the same script again. Completed scenarios are detected via
  output_blinded_power/<run>/partials/ and skipped; only the interrupted
  scenario re-runs.

RESULTS (copy back to your laptop)
  output_blinded_power/primary/      oc_summary.csv, mde_table.csv,
  output_blinded_power/sensitivity/  pretrend_summary.csv, results_raw.csv.gz,
                                     failures.csv, run_metadata.json,
                                     scenario_truths.csv
  scp -r della:/scratch/.../della_power_upload/output_blinded_power <repo>/output_blinded_power_della

CONTENTS
  power_simulation_cs.R   repo-root MARKER only (not the legacy script)
  R/power/                the 9 framework modules
  config/                 power_validation / power_primary / power_sensitivity.yml
  tests/                  testthat suite (run via tests/run_tests.R)
  utils/                  eviction_treatment_schedule.R (shared loader)
  data/raw/               the ONLY three files the blinded loader may read
  docs/methodology/       blindness protocol + simulation design

NOTES
  - No patched did/DRDID/fastglm needed: est_method = "reg" never enters the
    DRDID/fastglm path. Stock CRAN packages only.
  - All outputs stay inside output_blinded_power/ (enforced by the code).
  - R module: 4.4.2 (framework developed on 4.5.2; no version-specific code).
