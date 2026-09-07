#!/bin/zsh
# $1 = tag dir, $2 = script path, $3 = variant label
set -e
cd "$1"
ln -sfn "$REPO/utils" utils
ln -sf "$REPO/data/processed/cohort_ramp_lags.csv" data/processed/cohort_ramp_lags.csv
mkdir -p "out_$3"
TREAT_DEF=shift12 ANCHOR=event_clean PMD=6 POST=12 POST_MIN=0 PRE=2 BOOT_REPS=999 \
MAX_DATE=2030-12-31 LPDID_WEIGHTS=ewatt Rscript "$2" > "out_$3/log.txt" 2>&1 || echo "FAILED $1 $3" >> "out_$3/log.txt"
mv output/lpdid_statepanel/* "out_$3/" 2>/dev/null || true
echo "done $1 $3"
