#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0

echo "=== Testing scripts/coverage/check-threshold.sh ==="

# Test 1: All metrics above threshold — passes
(
  export THRESHOLD=50
  export LINES_PCT=80.00
  export STMTS_PCT=75.00
  export BRANCH_PCT=60.00
  export FUNCS_PCT=90.00

  bash "$SCRIPT_DIR/scripts/coverage/check-threshold.sh" > /dev/null 2>&1
  echo "PASS: passes when all metrics above threshold"
) || { FAILURES=$((FAILURES + 1)); }

# Test 2: One metric below threshold — fails
(
  export THRESHOLD=50
  export LINES_PCT=80.00
  export STMTS_PCT=75.00
  export BRANCH_PCT=30.00
  export FUNCS_PCT=90.00

  if bash "$SCRIPT_DIR/scripts/coverage/check-threshold.sh" > /dev/null 2>&1; then
    echo "FAIL: should have exited with error"
    exit 1
  fi
  echo "PASS: fails when a metric is below threshold"
) || { FAILURES=$((FAILURES + 1)); }

# Test 3: Exactly at threshold — passes
(
  export THRESHOLD=80
  export LINES_PCT=80.00
  export STMTS_PCT=80.00
  export BRANCH_PCT=80.00
  export FUNCS_PCT=80.00

  bash "$SCRIPT_DIR/scripts/coverage/check-threshold.sh" > /dev/null 2>&1
  echo "PASS: passes when metrics exactly at threshold"
) || { FAILURES=$((FAILURES + 1)); }

# Test 4: Zero threshold always passes
(
  export THRESHOLD=0
  export LINES_PCT=0
  export STMTS_PCT=0
  export BRANCH_PCT=0
  export FUNCS_PCT=0

  bash "$SCRIPT_DIR/scripts/coverage/check-threshold.sh" > /dev/null 2>&1
  echo "PASS: zero threshold always passes"
) || { FAILURES=$((FAILURES + 1)); }

echo "--- $((4 - FAILURES))/4 tests passed ---"
exit $FAILURES
