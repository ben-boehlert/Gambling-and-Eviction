#!/bin/bash
#SBATCH --job-name=cs_power_sim
#SBATCH --output=cs_power_%j.out
#SBATCH --error=cs_power_%j.err
#SBATCH --time=24:00:00
#SBATCH --cpus-per-task=20
#SBATCH --mem=64G
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=bb1806@princeton.edu

# Load R module (check with: module avail R)
module load R

# Set working directory to wherever the script is submitted from
cd $SLURM_SUBMIT_DIR

# Environment variables
export DATA_FILE=combined_monthly_panel.csv
export TREAT_FILE=state_month_panel_with_treatment.csv
export OUT_DIR=cs_reg_power_out
export N_SIMS=2000
export EFFECT_PCTS="0,0.05,0.10,0.15,0.20"
export N_WORKERS=20
export ALPHA=0.05
export SEED=123

# Date windows
export EXCLUDE_START=2020-03-01
export EXCLUDE_END=2021-07-01

# Progress tracking
export PROGRESS_BATCHES=cs_reg_power_out/progress_batches.csv

# DID options (defaults match main analysis)
export DID_CONTROL_GROUP=notyettreated
export DID_BSTRAP=TRUE
export DID_BITERS=199

# Error mode
export ERR_MODE=iid_month

# Run simulation
Rscript power_simulation_cs_reg_statepanel_staggered_parallel_REVISED.R

echo "Simulation complete. Check cs_reg_power_out/ for results."
