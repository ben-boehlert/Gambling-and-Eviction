#!/usr/bin/env bash
# =============================================================================
# scripts/make_della_power_upload.sh
#
# Builds della_power_upload/ — a self-contained folder for running the blinded
# power-simulation framework (R/power/) on Princeton's Della cluster.
# Re-run any time framework code, configs, or data change; the folder is
# regenerable and gitignored.
#
# Usage:  bash scripts/make_della_power_upload.sh
# Then:   rsync -av --exclude 'output_blinded_power' della_power_upload/ \
#             della:/scratch/gpfs/DESMOND/ben/eviction_gambling/della_power_upload/
#
# Use rsync, not `scp -r`: once the folder exists on Della, `scp -r <dir> host:<path>/`
# nests it as <path>/della_power_upload/della_power_upload. The trailing slashes
# above sync CONTENTS, and --exclude keeps an existing run's outputs intact.
#         (or your own /scratch/gpfs/<netid>/ path — nothing inside hardcodes it)
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="della_power_upload"
rm -rf "$DEST"
mkdir -p "$DEST"/{R/power,config,tests,utils,data/raw,docs/methodology}

# --- Framework code, configs, tests, shared utility -------------------------
cp R/power/*.R                          "$DEST/R/power/"
cp config/power_validation.yml          "$DEST/config/"
cp config/power_primary.yml             "$DEST/config/"
cp config/power_sensitivity.yml         "$DEST/config/"
cp config/power_cheap.yml               "$DEST/config/"
cp config/power_smoke.yml               "$DEST/config/"
cp config/power_addon1.yml              "$DEST/config/"
cp tests/run_tests.R                    "$DEST/tests/"
cp -R tests/testthat                    "$DEST/tests/testthat"
cp utils/eviction_treatment_schedule.R  "$DEST/utils/"

# --- Data (the only three files the blinded loader may read) -----------------
cp data/raw/monthly_county_data_download.csv       "$DEST/data/raw/"
cp data/raw/state_month_panel_with_treatment.csv   "$DEST/data/raw/"
cp data/raw/sports_gambling_legalization_dates.csv "$DEST/data/raw/"

# --- Reference docs ----------------------------------------------------------
cp docs/methodology/POWER_SIMULATION_BLINDNESS_PROTOCOL.md "$DEST/docs/methodology/"
cp docs/methodology/POWER_SIMULATION_DESIGN.md             "$DEST/docs/methodology/"

# --- Della launchers (version-controlled templates in scripts/della_power/) --
cp scripts/della_power/setup.sh              "$DEST/"
cp scripts/della_power/run_validation.sh     "$DEST/"
cp scripts/della_power/list_scenarios.sh     "$DEST/"
cp scripts/della_power/run_primary.slurm     "$DEST/"
cp scripts/della_power/run_sensitivity.slurm "$DEST/"
cp scripts/della_power/run_cheap.slurm       "$DEST/"
cp scripts/della_power/run_smoke.slurm       "$DEST/"
cp scripts/della_power/run_addon1.slurm      "$DEST/"
cp scripts/della_power/run_aggregate.slurm   "$DEST/"
cp scripts/della_power/run_aggregate.sh      "$DEST/"
cp scripts/della_power/README.txt            "$DEST/"
chmod +x "$DEST/setup.sh" "$DEST/run_validation.sh" "$DEST/list_scenarios.sh" \
         "$DEST/run_aggregate.sh"

# --- Repo-root marker --------------------------------------------------------
# power_repo_root() locates the project root by finding a file with this name.
# This stub exists ONLY as that marker; it is not the legacy simulation script.
cat > "$DEST/power_simulation_cs.R" << 'EOF'
# Repo-root marker for the blinded power-simulation framework.
# power_repo_root() (R/power/config.R) walks up the directory tree until it
# finds a file with this name. In the full repository this is the legacy
# Family-P simulation library; in this Della upload it is only a marker.
# Do not delete or rename.
EOF

echo "Built $DEST/:"
du -sh "$DEST"
find "$DEST" -maxdepth 2 | sort
