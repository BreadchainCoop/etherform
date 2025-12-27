#!/bin/bash
# Run all etherform workflow tests
#
# Usage: ./tests/run-all.sh
# Returns: 0 if all tests pass, 1 if any test fails

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "Etherform Workflow Tests"
echo "========================================"
echo ""

TOTAL_PASSED=0
TOTAL_FAILED=0

run_test_suite() {
  local name="$1"
  local script="$2"

  echo "Running: $name"
  echo "----------------------------------------"

  if bash "$script"; then
    echo ""
  else
    echo ""
    ((TOTAL_FAILED++))
  fi
}

# Make scripts executable
chmod +x "$SCRIPT_DIR"/../scripts/*.sh
chmod +x "$SCRIPT_DIR"/*.sh

# Run all test suites
run_test_suite "Compiler Config Validation" "$SCRIPT_DIR/test-compiler-config.sh"
run_test_suite "Baseline Detection" "$SCRIPT_DIR/test-baseline-detection.sh"

echo "========================================"
echo "All Tests Complete"
echo "========================================"

if [[ $TOTAL_FAILED -gt 0 ]]; then
  echo "FAILED: $TOTAL_FAILED test suite(s) failed"
  exit 1
else
  echo "SUCCESS: All test suites passed"
  exit 0
fi
