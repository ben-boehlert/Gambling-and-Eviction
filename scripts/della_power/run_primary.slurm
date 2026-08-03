#!/bin/bash
#SBATCH --job-name=power_primary
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=64G
#SBATCH --time=71:59:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=bb1806@princeton.edu
#SBATCH --output=slurm-power-primary-%j.out

# Primary scenario grid of the blinded power simulation
# (config/power_primary.yml). Resume-safe: if the job times out, just
# `sbatch run_primary.slurm` again — completed scenarios are skipped via
# their partials in output_blinded_power/primary/partials/.

set -e
module purge
module load R/4.4.2

# No hardcoded scratch path: run from wherever this folder was uploaded.
cd "$SLURM_SUBMIT_DIR"

export N_WORKERS="${SLURM_CPUS_PER_TASK}"

Rscript --vanilla -e '
  source("R/power/config.R");  source("R/power/blindness_checks.R")
  source("R/power/load_blinded_panel.R"); source("R/power/make_pseudo_schedules.R")
  source("R/power/summarize_operating_characteristics.R")
  source("R/power/run_scenario_grid.R")
  run_scenario_grid("config/power_primary.yml",
                    resume   = TRUE,
                    workers  = as.integer(Sys.getenv("N_WORKERS")),
                    run_name = "primary")
'
