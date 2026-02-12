#!/usr/bin/env bash
# Run all etherform workflow logic tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0

run_test() {
  local test_file="$1"
  echo "Running $(basename "$test_file")..."
  if bash "$test_file"; then
    echo "  ✓ PASSED"
    PASS=$((PASS + 1))
  else
    echo "  ✗ FAILED"
    FAIL=$((FAIL + 1))
  fi
}

for test_file in "$SCRIPT_DIR"/test-*.sh; do
  if [[ -f "$test_file" ]]; then
    run_test "$test_file"
  fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
