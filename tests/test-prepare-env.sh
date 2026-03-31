#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0

echo "=== Testing scripts/deploy/prepare-env.sh ==="

# Test 1: PRIVATE_KEY without 0x gets prefix added
(
  export PRIVATE_KEY="abc123"
  unset DEPLOY_ENV_VARS 2>/dev/null || true
  source "$SCRIPT_DIR/scripts/deploy/prepare-env.sh"
  [[ "$PRIVATE_KEY" == "0xabc123" ]] || { echo "FAIL: expected 0xabc123, got $PRIVATE_KEY"; exit 1; }
  echo "PASS: adds 0x prefix"
) || { FAILURES=$((FAILURES + 1)); }

# Test 2: PRIVATE_KEY already with 0x is not doubled
(
  export PRIVATE_KEY="0xabc123"
  unset DEPLOY_ENV_VARS 2>/dev/null || true
  source "$SCRIPT_DIR/scripts/deploy/prepare-env.sh"
  [[ "$PRIVATE_KEY" == "0xabc123" ]] || { echo "FAIL: expected 0xabc123, got $PRIVATE_KEY"; exit 1; }
  echo "PASS: preserves existing 0x prefix"
) || { FAILURES=$((FAILURES + 1)); }

# Test 3: Empty PRIVATE_KEY stays empty
(
  export PRIVATE_KEY=""
  unset DEPLOY_ENV_VARS 2>/dev/null || true
  source "$SCRIPT_DIR/scripts/deploy/prepare-env.sh"
  [[ -z "$PRIVATE_KEY" || "$PRIVATE_KEY" == "0x" ]] || { echo "FAIL: expected empty or 0x, got $PRIVATE_KEY"; exit 1; }
  echo "PASS: empty key handled"
) || { FAILURES=$((FAILURES + 1)); }

# Test 4: DEPLOY_ENV_VARS are exported
(
  export PRIVATE_KEY="0xtest"
  export DEPLOY_ENV_VARS=$'FOO=bar\nBAZ=qux'
  source "$SCRIPT_DIR/scripts/deploy/prepare-env.sh"
  [[ "$FOO" == "bar" ]] || { echo "FAIL: FOO not set"; exit 1; }
  [[ "$BAZ" == "qux" ]] || { echo "FAIL: BAZ not set"; exit 1; }
  echo "PASS: DEPLOY_ENV_VARS exported"
) || { FAILURES=$((FAILURES + 1)); }

# Test 5: Comments and blank lines in DEPLOY_ENV_VARS are skipped
(
  export PRIVATE_KEY="0xtest"
  export DEPLOY_ENV_VARS=$'# comment\n\nFOO=bar\n# another\nBAZ=qux'
  source "$SCRIPT_DIR/scripts/deploy/prepare-env.sh"
  [[ "$FOO" == "bar" ]] || { echo "FAIL: FOO not set"; exit 1; }
  [[ "$BAZ" == "qux" ]] || { echo "FAIL: BAZ not set"; exit 1; }
  echo "PASS: comments and blanks skipped"
) || { FAILURES=$((FAILURES + 1)); }

# Test 6: No DEPLOY_ENV_VARS is fine
(
  export PRIVATE_KEY="0xtest"
  unset DEPLOY_ENV_VARS 2>/dev/null || true
  source "$SCRIPT_DIR/scripts/deploy/prepare-env.sh"
  echo "PASS: no DEPLOY_ENV_VARS ok"
) || { FAILURES=$((FAILURES + 1)); }

# Test 7: No PRIVATE_KEY is fine
(
  unset PRIVATE_KEY 2>/dev/null || true
  unset DEPLOY_ENV_VARS 2>/dev/null || true
  source "$SCRIPT_DIR/scripts/deploy/prepare-env.sh"
  echo "PASS: no PRIVATE_KEY ok"
) || { FAILURES=$((FAILURES + 1)); }

echo "--- $((7 - FAILURES))/7 tests passed ---"
exit $FAILURES
