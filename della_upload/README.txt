CS Calibration — Della Upload
=============================

1. Upload this entire folder to Della:
   scp -r della_upload della:/scratch/gpfs/bb1806/cs_calibration/

2. SSH in and set up (one time):
   ssh della
   cd /scratch/gpfs/bb1806/cs_calibration
   bash setup.sh

3. Submit the job:
   sbatch run.slurm

4. Check status:
   squeue -u bb1806

5. Output appears in:
   output/cs_calibration_unified/calibration_summary.csv
   output/cs_calibration_unified/sim_results.csv
   output/cs_calibration_unified/panel_summary.csv

To change settings (e.g., more sims), edit the exports in run.slurm.
All env vars are documented at the top of analysis/diagnostics/cs_calibration_unified.R.
