#!/bin/bash
# Run this ONCE on a Della LOGIN node after uploading (compute nodes have no
# internet). Installs all CRAN dependencies of the blinded power framework
# into your user library. No patched local packages are needed: the framework
# uses stock CRAN `did` with est_method = "reg", which never enters the
# DRDID/fastglm code path (see docs/methodology/POWER_SIMULATION_CODE_AUDIT.md
# finding F4 in the main repository).
#
# Usage: bash setup.sh
set -e

module purge
module load R/4.4.2

echo "Installing CRAN dependencies (this can take ~10-20 min; fwildclusterboot compiles)..."
Rscript -e '
  pkgs <- c("dplyr", "tidyr", "readr", "tibble", "purrr", "rlang",
            "lubridate", "yaml", "jsonlite", "digest", "fixest", "did",
            "did2s", "fwildclusterboot", "furrr", "future", "testthat")
  lib <- Sys.getenv("R_LIBS_USER")
  dir.create(lib, recursive = TRUE, showWarnings = FALSE)
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    install.packages(missing, repos = "https://cloud.r-project.org", lib = lib)
  } else cat("All packages already installed.\n")
'

echo ""
echo "Setup done. Next steps:"
echo "  bash run_validation.sh        # quick check on the login node (~5 min)"
echo "  sbatch run_primary.slurm      # primary scenario grid"
echo "  sbatch run_sensitivity.slurm  # sensitivity grid (after primary)"
