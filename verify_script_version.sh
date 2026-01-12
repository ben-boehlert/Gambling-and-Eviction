#!/bin/bash
# Verify which version of the script you're running

SCRIPT="power_simulation_cs_statepanel_staggered_parallel_merged.R"

echo "=== Verifying Script Version ==="
echo ""
echo "File: $SCRIPT"
echo "Location: $(pwd)/$SCRIPT"
echo "Modified: $(stat -f "%Sm" $SCRIPT 2>/dev/null || stat -c "%y" $SCRIPT 2>/dev/null)"
echo ""

echo "Checking for cband=FALSE:"
grep -n "cband = FALSE" "$SCRIPT" && echo "  ✓ Found cband=FALSE" || echo "  ✗ NOT FOUND - running old version!"
echo ""

echo "Checking for correct p-value calculation:"
grep -n "isTRUE(did_bstrap)" "$SCRIPT" && echo "  ✓ Found bootstrap p-value logic" || echo "  ✗ NOT FOUND - running old version!"
grep -n "pt(-abs(z), df = n_states - 1)" "$SCRIPT" && echo "  ✓ Found t-distribution p-value" || echo "  ✗ NOT FOUND - running old version!"
echo ""

echo "Checking for version marker:"
grep "Version: 2026-01-07-v3" "$SCRIPT" && echo "  ✓ Found v3 version marker" || echo "  ✗ NOT FOUND - running old version!"
echo ""

echo "MD5 checksum: $(md5sum $SCRIPT 2>/dev/null || md5 $SCRIPT)"
