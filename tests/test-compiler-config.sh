#!/bin/bash
# Test cases for compiler config validation
# These tests ensure we catch all invalid configurations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VALIDATE_SCRIPT="$ROOT_DIR/scripts/validate-compiler-config.sh"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

PASSED=0
FAILED=0

# Helper function to run a test
run_test() {
  local name="$1"
  local fixture="$2"
  local expected_exit="$3"  # 0 = should pass, 1 = should fail

  echo -n "  $name... "

  if "$VALIDATE_SCRIPT" "$FIXTURES_DIR/$fixture" > /dev/null 2>&1; then
    actual_exit=0
  else
    actual_exit=1
  fi

  if [[ $actual_exit -eq $expected_exit ]]; then
    echo "PASS"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL (expected exit $expected_exit, got $actual_exit)"
    FAILED=$((FAILED + 1))
  fi
}

echo "Testing compiler config validation..."
echo ""

# Test cases that SHOULD PASS (exit 0)
echo "Tests that should PASS:"
run_test "Valid config" "foundry-valid.toml" 0

echo ""

# Test cases that SHOULD FAIL (exit 1)
echo "Tests that should FAIL (detect invalid config):"
run_test "Missing bytecode_hash" "foundry-missing-bytecode-hash.toml" 1
run_test "Missing cbor_metadata" "foundry-missing-cbor-metadata.toml" 1
run_test "Wrong bytecode_hash value" "foundry-wrong-bytecode-hash.toml" 1
run_test "Wrong cbor_metadata value" "foundry-wrong-cbor-metadata.toml" 1

echo ""
echo "================================"
echo "Results: $PASSED passed, $FAILED failed"

if [[ $FAILED -gt 0 ]]; then
  exit 1
fi
exit 0
