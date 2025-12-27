#!/bin/bash
# Test cases for baseline detection logic
# These tests ensure we correctly detect baseline directories and handle missing baselines

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DETECT_SCRIPT="$ROOT_DIR/scripts/detect-baseline.sh"

PASSED=0
FAILED=0

# Create temp directory for test fixtures
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Helper function to run a test
run_test() {
  local name="$1"
  local baseline_path="$2"
  local upgrades_path="$3"
  local expected_exit="$4"  # 0 = baseline found, 1 = no baseline
  local expected_output="$5"  # Expected output (baseline dir or NO_BASELINE)

  echo -n "  $name... "

  set +e
  actual_output=$("$DETECT_SCRIPT" "$baseline_path" "$upgrades_path" 2>/dev/null)
  actual_exit=$?
  set -e

  # Normalize paths for comparison
  if [[ "$expected_output" != "NO_BASELINE" ]]; then
    expected_output=$(echo "$expected_output" | sed 's|/$||')
    actual_output=$(echo "$actual_output" | sed 's|/$||')
  fi

  if [[ $actual_exit -eq $expected_exit ]] && [[ "$actual_output" == "$expected_output" ]]; then
    echo "PASS"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL"
    echo "    Expected: exit=$expected_exit, output='$expected_output'"
    echo "    Got:      exit=$actual_exit, output='$actual_output'"
    FAILED=$((FAILED + 1))
  fi
}

echo "Testing baseline detection..."
echo ""

# Setup: Create test directory structures
setup_baseline() {
  local dir="$1"
  mkdir -p "$dir"
  echo "// SPDX-License-Identifier: MIT" > "$dir/Counter.sol"
}

# Test 1: Baseline exists at primary path
CASE1_DIR="$TEMP_DIR/case1"
mkdir -p "$CASE1_DIR/test/upgrades"
setup_baseline "$CASE1_DIR/test/upgrades/baseline"

echo "Tests for baseline detection:"
run_test "Baseline at primary path" \
  "$CASE1_DIR/test/upgrades/baseline" \
  "$CASE1_DIR/test/upgrades" \
  0 \
  "$CASE1_DIR/test/upgrades/baseline"

# Test 2: Baseline missing, fallback to previous
CASE2_DIR="$TEMP_DIR/case2"
mkdir -p "$CASE2_DIR/test/upgrades"
setup_baseline "$CASE2_DIR/test/upgrades/previous"

run_test "Fallback to previous when baseline missing" \
  "$CASE2_DIR/test/upgrades/baseline" \
  "$CASE2_DIR/test/upgrades" \
  0 \
  "$CASE2_DIR/test/upgrades/previous"

# Test 3: Both baseline and previous exist (should prefer baseline)
CASE3_DIR="$TEMP_DIR/case3"
mkdir -p "$CASE3_DIR/test/upgrades"
setup_baseline "$CASE3_DIR/test/upgrades/baseline"
setup_baseline "$CASE3_DIR/test/upgrades/previous"

run_test "Prefer baseline over previous when both exist" \
  "$CASE3_DIR/test/upgrades/baseline" \
  "$CASE3_DIR/test/upgrades" \
  0 \
  "$CASE3_DIR/test/upgrades/baseline"

# Test 4: No baseline or previous (initial deployment)
CASE4_DIR="$TEMP_DIR/case4"
mkdir -p "$CASE4_DIR/test/upgrades"

run_test "No baseline found (initial deployment)" \
  "$CASE4_DIR/test/upgrades/baseline" \
  "$CASE4_DIR/test/upgrades" \
  1 \
  "NO_BASELINE"

# Test 5: Baseline dir exists but no .sol files
CASE5_DIR="$TEMP_DIR/case5"
mkdir -p "$CASE5_DIR/test/upgrades/baseline"
touch "$CASE5_DIR/test/upgrades/baseline/README.md"

run_test "Baseline dir exists but no .sol files" \
  "$CASE5_DIR/test/upgrades/baseline" \
  "$CASE5_DIR/test/upgrades" \
  1 \
  "NO_BASELINE"

echo ""
echo "================================"
echo "Results: $PASSED passed, $FAILED failed"

if [[ $FAILED -gt 0 ]]; then
  exit 1
fi
exit 0
