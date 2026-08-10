#!/bin/bash
# Run this ONCE after uploading to Della to install R packages.
# Usage: bash setup.sh

set -e

module purge
module load R/4.4.2

echo "Installing CRAN dependencies..."
Rscript -e 'install.packages(c("dplyr", "readr", "tibble", "fixest", "glue"), repos="https://cloud.r-project.org", lib=Sys.getenv("R_LIBS_USER"))'

echo "Installing patched fastglm..."
R CMD INSTALL fastglm-master/

echo "Installing patched DRDID..."
R CMD INSTALL DRDID-master/

echo "Installing patched did..."
R CMD INSTALL did/

echo "Done. Run: sbatch run.slurm"
