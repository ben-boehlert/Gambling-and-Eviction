#!/usr/bin/env bash
# Second pass launcher: reviewer amendments (R1/R2/R3/S1/Q3).
# See quality_reports/plans/2026-09-21_twfe_donorpath_power_sim.md
# "Review amendments" section + coordinator follow-up (2026-09-21).
#
# Does NOT touch pass-1 files or output/twfe_power_donorpath_v20260921/.
# All outputs go to output/twfe_power_donorpath_v20260921b/.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_BASE="output/twfe_power_donorpath_v20260921b"
mkdir -p "$OUT_BASE"
N_WORKERS="${N_WORKERS:-6}"
SEED=20260921

echo "=== [1/6] start202206 (PRIMARY): main, unscaled, R1+R2 fix, 2000 sims + 1000 wild ==="
SCENARIO=start202206 RUN_MODE=main RESCALE_DONORS=FALSE DROP_ALREADY_TREATED=TRUE \
  MIN_ELIGIBLE_COVERAGE=0.80 N_SIMS=2000 N_WILD_SIMS=1000 WILD_B=999 \
  N_WORKERS="$N_WORKERS" SEED=$SEED OUT_DIR="$OUT_BASE/start202206/unscaled" \
  Rscript analysis/main/power_simulation_twfe_donorpath_v2.R

echo "=== [2/6] start202206: S1 rescaled donor paths, 2000 sims + 1000 wild ==="
SCENARIO=start202206 RUN_MODE=main RESCALE_DONORS=TRUE DROP_ALREADY_TREATED=TRUE \
  MIN_ELIGIBLE_COVERAGE=0.80 MIN_DONOR_OWN_OBS=12 N_SIMS=2000 N_WILD_SIMS=1000 WILD_B=999 \
  N_WORKERS="$N_WORKERS" SEED=$SEED OUT_DIR="$OUT_BASE/start202206/s1_rescaled" \
  Rscript analysis/main/power_simulation_twfe_donorpath_v2.R

echo "=== [3/6] start202206: Q3 keep-already-treated, analytic only, 1000 sims ==="
SCENARIO=start202206 RUN_MODE=main RESCALE_DONORS=FALSE DROP_ALREADY_TREATED=FALSE \
  MIN_ELIGIBLE_COVERAGE=0.80 N_SIMS=1000 RUN_WILD=FALSE \
  N_WORKERS="$N_WORKERS" SEED=$SEED OUT_DIR="$OUT_BASE/start202206/q3_keep_already_treated" \
  Rscript analysis/main/power_simulation_twfe_donorpath_v2.R

echo "=== [4/6] start202206: R3 leave-one-eligible-donor-out, 400 sims x eligible donors, analytic only ==="
SCENARIO=start202206 RUN_MODE=loo RESCALE_DONORS=FALSE DROP_ALREADY_TREATED=TRUE \
  MIN_ELIGIBLE_COVERAGE=0.80 LOO_N_SIMS=400 N_SIMS=2000 RUN_WILD=FALSE \
  N_WORKERS="$N_WORKERS" SEED=$SEED OUT_DIR="$OUT_BASE/start202206/loo" \
  Rscript analysis/main/power_simulation_twfe_donorpath_v2.R

echo "=== [5/6] full (comparison row, cheap items only): main unscaled, R1+R2 ==="
echo "NOTE: full's 41-state window spans 2012-2026 with heavily staggered per-state"
echo "coverage start dates; at MIN_ELIGIBLE_COVERAGE=0.80 (as used for start202206)"
echo "zero never-treated donors reach 80% coverage of that whole window (max ~0.70)."
echo "Documented deviation: full is run at a relaxed MIN_ELIGIBLE_COVERAGE=0.60 so the"
echo "R2 ex-ante-eligible-set design is well-defined here; this is flagged, not silent."
SCENARIO=full RUN_MODE=main RESCALE_DONORS=FALSE DROP_ALREADY_TREATED=TRUE \
  MIN_ELIGIBLE_COVERAGE=0.60 N_SIMS=2000 N_WILD_SIMS=1000 WILD_B=999 \
  N_WORKERS="$N_WORKERS" SEED=$SEED OUT_DIR="$OUT_BASE/full/unscaled" \
  Rscript analysis/main/power_simulation_twfe_donorpath_v2.R

echo "=== [6/6] DONE. Outputs in $OUT_BASE ==="
