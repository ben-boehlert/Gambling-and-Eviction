#!/bin/bash
# Quick sanity check — safe to run on a Della login node (~5 min, light).
# Runs the unit-test suite, then the small BHNS-style validation on real
# blinded data. Do this BEFORE submitting the SLURM jobs.
#
# Usage: bash run_validation.sh
set -e
cd "$(dirname "$0")"

module purge
module load R/4.4.2

echo "=== 1/2: unit tests ==="
Rscript tests/run_tests.R

echo ""
echo "=== 2/2: BHNS-style validation (25 reps) ==="
Rscript -e '
  source("R/power/config.R");  source("R/power/blindness_checks.R")
  source("R/power/load_blinded_panel.R"); source("R/power/make_pseudo_schedules.R")
  source("R/power/impose_effects.R");     source("R/power/run_estimators.R")
  source("R/power/summarize_operating_characteristics.R")
  source("R/power/validate_simulation.R")
  v <- validate_simulation(n_reps = 25L)
  print(v$checks)
  if (!isTRUE(v$pass)) stop("Validation FAILED — do not submit SLURM jobs.")
'

echo ""
echo "Validation passed. Submit with: sbatch run_primary.slurm"
