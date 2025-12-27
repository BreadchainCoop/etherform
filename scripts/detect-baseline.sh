#!/bin/bash
# Detect which baseline directory to use for upgrade safety validation
# This script is extracted from _foundry-upgrade-safety.yml for local testing
#
# Usage: ./scripts/detect-baseline.sh [baseline-path] [upgrades-path]
# Outputs: The baseline directory path to use, or exits with message if none found
# Returns: 0 if baseline found, 1 if no baseline (initial deployment)

set -euo pipefail

BASELINE_PATH="${1:-test/upgrades/baseline}"
UPGRADES_PATH="${2:-test/upgrades}"
FALLBACK="${UPGRADES_PATH}/previous"

if [ -d "$BASELINE_PATH" ] && ls ${BASELINE_PATH}/*.sol 1> /dev/null 2>&1; then
  echo "$BASELINE_PATH"
  exit 0
elif [ -d "$FALLBACK" ] && ls ${FALLBACK}/*.sol 1> /dev/null 2>&1; then
  echo "$FALLBACK"
  exit 0
else
  echo "NO_BASELINE"
  exit 1
fi
