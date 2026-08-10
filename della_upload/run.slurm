#!/bin/bash
#SBATCH --job-name=cs_calib
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=04:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=bb1806@princeton.edu
#SBATCH --output=slurm-%j.out

set -e

module purge
module load R/4.4.2

cd /scratch/gpfs/DESMOND/ben/eviction_gambling/della_upload

# Install packages (skips if already installed)
Rscript -e 'install.packages(c("dplyr", "readr", "tibble", "fixest", "glue"), repos="https://cloud.r-project.org", lib=Sys.getenv("R_LIBS_USER"))'
R CMD INSTALL fastglm-master/
R CMD INSTALL DRDID-master/
R CMD INSTALL did/

# Run calibration
export N_SIMS=200
export N_CORES=${SLURM_CPUS_PER_TASK}
export OUT_DIR=output/cs_calibration_unified

Rscript analysis/diagnostics/cs_calibration_unified.R
