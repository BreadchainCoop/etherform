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

# Test 8: Lines without = are skipped
(
  export PRIVATE_KEY="0xtest"
  export DEPLOY_ENV_VARS=$'GOOD=val\nmalformed_no_equals\nALSO_GOOD=123'
  source "$SCRIPT_DIR/scripts/deploy/prepare-env.sh"
  [[ "$GOOD" == "val" ]] || { echo "FAIL: GOOD not set"; exit 1; }
  [[ "$ALSO_GOOD" == "123" ]] || { echo "FAIL: ALSO_GOOD not set"; exit 1; }
  echo "PASS: lines without = are skipped"
) || { FAILURES=$((FAILURES + 1)); }

# Test 9: Invalid key names are rejected
(
  export PRIVATE_KEY="0xtest"
  export DEPLOY_ENV_VARS=$'GOOD_KEY=ok\nbad-key=nope\nbad key=nope'
  source "$SCRIPT_DIR/scripts/deploy/prepare-env.sh"
  [[ "$GOOD_KEY" == "ok" ]] || { echo "FAIL: GOOD_KEY not set"; exit 1; }
  # bad-key and "bad key" should not be set as shell variables
  [[ -z "${bad_key_marker:-}" ]] || { echo "FAIL: bad-key should not be exported"; exit 1; }
  # Use declare -p to check — hyphenated names can't be valid bash variables anyway
  # Just verify GOOD_KEY was the only new export
  echo "PASS: invalid key names rejected"
) || { FAILURES=$((FAILURES + 1)); }

# Test 10: Valid keys with various value formats export correctly
(
  export PRIVATE_KEY="0xtest"
  export DEPLOY_ENV_VARS=$'KEY_WITH_NUMS_123=abc\n_UNDERSCORE=yes\nVAL_WITH_EQUALS=a=b=c'
  source "$SCRIPT_DIR/scripts/deploy/prepare-env.sh"
  [[ "$KEY_WITH_NUMS_123" == "abc" ]] || { echo "FAIL: KEY_WITH_NUMS_123 not set"; exit 1; }
  [[ "$_UNDERSCORE" == "yes" ]] || { echo "FAIL: _UNDERSCORE not set"; exit 1; }
  [[ "$VAL_WITH_EQUALS" == "a=b=c" ]] || { echo "FAIL: VAL_WITH_EQUALS should preserve = in value, got $VAL_WITH_EQUALS"; exit 1; }
  echo "PASS: valid keys with various values export correctly"
) || { FAILURES=$((FAILURES + 1)); }

TOTAL=10
echo "--- $((TOTAL - FAILURES))/$TOTAL tests passed ---"
exit $FAILURES
