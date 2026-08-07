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
  rsync -av --exclude 'output_blinded_power' della_power_upload/ \
    bb1806@della8.princeton.edu:/scratch/gpfs/DESMOND/ben/eviction_gambling/della_power_upload/
  # any /scratch path works — nothing here hardcodes the location

  Use rsync, NOT `scp -r`: once the folder exists on Della, `scp -r <dir>
  host:<path>/` nests it as <path>/della_power_upload/della_power_upload. The
  trailing slashes above sync CONTENTS; --exclude preserves an existing run's
  output_blinded_power/.

  Host notes:
   - `della` alone is only an ~/.ssh/config alias — it does not resolve unless
     you have defined it. Use the full hostname, or add:
       Host della
         HostName della8.princeton.edu
         User <netid>
         ControlMaster auto
         ControlPath ~/.ssh/cm-%r@%h:%p
         ControlPersist 10m
     (ControlPersist reuses one authenticated connection, so you Duo once.)
   - `della.princeton.edu` round-robins across login nodes. If one is drained
     you get "Not allowed at this time" and the connection closes BEFORE
     authentication — that is a closed node, not a credential problem. Target
     a specific node (della8/della9) instead.
   - Browser alternative, no SSH at all: https://mydella.princeton.edu
     (Open OnDemand; VPN required off campus). Files -> upload a zip of this
     folder, then Clusters -> Della Shell Access to unzip and sbatch.

RUN (on Della, in order)
  1. bash setup.sh              # once, LOGIN node — installs CRAN packages
  2. bash run_validation.sh     # login node, ~5 min — tests + BHNS validation
  3. bash list_scenarios.sh config/power_primary.yml
                                # confirm the scenario count matches the
                                # --array range in run_primary.slurm
  4. sbatch run_primary.slurm   # ARRAY: 11 tasks x 8 cores, <24h each
  5. sbatch --dependency=afterok:<ARRAY_JOB_ID> run_aggregate.slurm
                                # writes the run-level summaries (see below)
  6. sbatch run_sensitivity.slurm                     # ARRAY: 26 tasks
     sbatch --dependency=afterok:<ID> run_aggregate.slurm sensitivity

  Each scenario is one array task. This replaced a single 32-core/72h job
  that timed out: the tasks are independent, fit the 24h short QOS, queue
  separately, and a failure costs one scenario instead of the whole run.

WHY THE SEPARATE AGGREGATE STEP
  Array tasks write ONLY their own partial
  (output_blinded_power/<run>/partials/<scenario_id>.csv). If each also wrote
  oc_summary.csv etc. they would race on the same files. run_aggregate.slurm
  stacks the partials and writes the run-level outputs. It also re-runs any
  scenario whose partial is missing, so it doubles as a completeness check.

  Two ways to run it:
    sbatch run_aggregate.slurm [primary|sensitivity]   # always safe
    bash run_aggregate.sh      [primary|sensitivity]   # login node

  The login-node version first verifies EVERY partial is complete and refuses
  to proceed otherwise — aggregating with a gap would recompute that scenario
  (~51 core-hours for a county scenario) on a shared login node. If it refuses,
  it names the missing scenarios; re-submit the array, then aggregate.

MONITOR
  squeue -u $USER
  sacct -j <ARRAY_JOB_ID> --format=JobID,State,Elapsed,MaxRSS   # per-task
  tail -f slurm-power-primary-<jobid>_<taskid>.out              # progress

RESUME AFTER TIMEOUT OR FAILURE
  Just sbatch the same script again. Completed scenarios are detected via
  output_blinded_power/<run>/partials/ and skipped; only missing or
  incomplete scenarios re-run. To rerun specific tasks only:
    sbatch --array=4,7 run_primary.slurm

  Scenario ids are content hashes of the scenario's own settings, so editing
  ONE block in a config does not invalidate any other scenario's partial.
  Changing anything that affects results (axes, estimators, effect grid,
  replication counts, base_seed) yields a new id and a clean re-run.
  IMPORTANT: if a config edit changes the SCENARIO COUNT, update the
  --array range to match (list_scenarios.sh prints the correct value).

RESULTS (copy back to your laptop)
  output_blinded_power/primary/      oc_summary.csv, mde_table.csv,
  output_blinded_power/sensitivity/  pretrend_summary.csv, results_raw.csv.gz,
                                     failures.csv, run_metadata.json,
                                     scenario_truths.csv
  scp -r della:/scratch/.../della_power_upload/output_blinded_power <repo>/output_blinded_power_della

CONTENTS
  power_simulation_cs.R   repo-root MARKER only (not the legacy script)
  setup.sh                one-time CRAN install (login node)
  run_validation.sh       tests + BHNS validation (login node)
  list_scenarios.sh       expanded scenario table + the correct --array range
  run_primary.slurm       array job, one task per primary scenario
  run_sensitivity.slurm   array job, one task per sensitivity scenario
  run_aggregate.slurm     post-array pass that writes the run-level summaries
  run_aggregate.sh        same, on the login node; refuses if a partial is
                          incomplete (would recompute it there)
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
