#!/bin/bash
# Repo cleanup 2026-08-25: move SUPERSEDED/CONTAMINATED/DEAD artifacts to deprecated/.
# Derived from movelist_output.txt + movelist_blinded.txt (extracted from the verified
# inventories) plus the root-relic list. Every move appends a line to MOVES.md.
# Nothing is deleted; mv -n refuses to clobber.
set -euo pipefail
cd "/Users/bb1806/Documents/GitHub Doc/Gambling-and-Eviction"
CLEAN=quality_reports/cleanup_2026-08-25
MOVES=MOVES.md

mkdir -p output/deprecated output_blinded_power/deprecated deprecated Literature

log_move() { echo "| \`$1\` | \`$2\` | $3 |" >> "$MOVES"; }

# --- MOVES.md header ---
cat > "$MOVES" <<'EOF'
# MOVES.md — 2026-08-25 repo cleanup

Every artifact relocated by the cleanup, old → new. Classifications and evidence:
`quality_reports/cleanup_2026-08-25/inventory_*.md`; statuses: `RUN_LEDGER.md`.
Nothing was deleted. Reversal is `mv` back.

| old path | new path | reason |
|---|---|---|
EOF

# --- 1. output/ moves (48 entries, all statuses in inventory_output.md) ---
while read -r d; do
  if [ -e "output/$d" ]; then
    mv -n "output/$d" "output/deprecated/$d"
    log_move "output/$d" "output/deprecated/$d" "per inventory_output.md"
  else
    echo "WARN missing: output/$d" >&2
  fi
done < "$CLEAN/movelist_output.txt"

# --- 2. output_blinded_power/: logs of LIVE/EXPLORATORY runs go INTO their run dir ---
declare -a KEEPLOG_SRC=(
  "county_cs_adaptive_run.log:county_cs_adaptive"
  "county_cs_adaptive_run2.log:county_cs_adaptive"
  "county_cs_adaptive_run3_finalize.log:county_cs_adaptive"
  "time_agg_covid_gates_run.log:time_agg_covid_gates"
  "time_agg_covid_gates_run2.log:time_agg_covid_gates"
  "time_agg_covid_gates_run3_serial.log:time_agg_covid_gates"
  "lpdid_shift12_gate_ewatt_run.log:lpdid_shift12_gate_ewatt"
  "lpdid_shift12_gate_vwatt_run.log:lpdid_shift12_gate_vwatt"
  "lpdid_shift12_mde_ewatt_run.log:lpdid_shift12_mde_ewatt"
  "lpdid_shift12_mde_vwatt_run.log:lpdid_shift12_mde_vwatt"
  "postcovid_maturation_county_run.log:postcovid_maturation_county"
  "postcovid_maturation_county_wild_run.log:postcovid_maturation_county_wild"
)
declare -A REDIRECT
for pair in "${KEEPLOG_SRC[@]}"; do REDIRECT["${pair%%:*}"]="${pair##*:}"; done

while read -r d; do
  src="output_blinded_power/$d"
  if [ ! -e "$src" ]; then echo "WARN missing: $src" >&2; continue; fi
  if [ -n "${REDIRECT[$d]:-}" ]; then
    dest="output_blinded_power/${REDIRECT[$d]}/$d"
    mv -n "$src" "$dest"
    log_move "$src" "$dest" "log kept with its LIVE/EXPLORATORY run"
  else
    mv -n "$src" "output_blinded_power/deprecated/$d"
    log_move "$src" "output_blinded_power/deprecated/$d" "per inventory_blinded_power.md"
  fi
done < "$CLEAN/movelist_blinded.txt"

# --- 3. Root relics -> deprecated/ ---
ROOT_RELICS=(
  "CLEANUP_SUMMARY.txt" "COPY_PASTE_FOR_PAPER.md" "CSDID_STATE_COUNT.txt"
  "FINAL_DELIVERABLES_SUMMARY.md" "MISSION_ACCOMPLISHED.txt" "OUTPUT_SUMMARY.md"
  "PAPER_CHECKLIST.md" "PLOTS_FOUND.txt" "PROJECT_STRUCTURE.txt"
  "READ_FIRST_INDEX.txt" "WHERE_ARE_MY_OUTPUTS.txt" "WHERE_ARE_MY_PLOTS.txt"
  "START_HERE.md" "QUICK_START.md" "Rplots.pdf"
  "monthly_county_data_download_8_20.csv" "della_upload.zip" "della_power_upload.zip"
)
for f in "${ROOT_RELICS[@]}"; do
  if [ -e "$f" ]; then
    mv -n "$f" "deprecated/$f"
    log_move "$f" "deprecated/$f" "root relic (Jan-2026 status docs / stale artifacts)"
  else
    echo "WARN missing root relic: $f" >&2
  fi
done

# --- 4. Reference PDFs: copy to Literature/, original to deprecated/ ---
PDFS=(
  "Autor_Dube_McGrew_Nov-2023.pdf"
  "Autoregressive models for panel data causal inference with application to state-level opioid policies.pdf"
  "Difference-in-differences for mediation analysis using double machine learning.pdf"
  "Improved Inference for CSDID Using the Cluster Jackknife.pdf"
  "J of Applied Econometrics - 2025 - Dube - A Local Projections Approach to Difference‐in‐Differences.pdf"
  "Sports Betting Across Borders Spatial Spillovers, Credit Distress, and Fiscal Externalities.pdf"
  "Robust Signal Maximization in Spillover Experiments.pdf"
  "w32902.pdf"
)
for f in "${PDFS[@]}"; do
  if [ -e "$f" ]; then
    cp -n "$f" "Literature/$f"
    mv -n "$f" "deprecated/$f"
    log_move "$f" "Literature/$f (copy); deprecated/$f (original)" "reference PDF relocated to Literature/"
  else
    echo "WARN missing PDF: $f" >&2
  fi
done

echo "--- done; MOVES.md rows: $(grep -c '^|' "$MOVES")"
