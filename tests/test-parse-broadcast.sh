#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0

echo "=== Testing scripts/deploy/parse-broadcast.sh ==="

# Test 1: Parses broadcast file and extracts chain ID
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cp -r "$SCRIPT_DIR/tests/fixtures/broadcast" "$TMPDIR/"
  cd "$TMPDIR"

  export GITHUB_OUTPUT="$TMPDIR/github-output.txt"
  touch "$GITHUB_OUTPUT"

  bash "$SCRIPT_DIR/scripts/deploy/parse-broadcast.sh" > /dev/null

  grep -q "broadcast_file=" "$GITHUB_OUTPUT" || { echo "FAIL: broadcast_file not in output"; exit 1; }
  grep -q "chain_id=31337" "$GITHUB_OUTPUT" || { echo "FAIL: chain_id not 31337"; cat "$GITHUB_OUTPUT"; exit 1; }

  echo "PASS: extracts broadcast_file and chain_id"
) || { FAILURES=$((FAILURES + 1)); }

# Test 2: Logs CREATE entries to stdout
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cp -r "$SCRIPT_DIR/tests/fixtures/broadcast" "$TMPDIR/"
  cd "$TMPDIR"

  export GITHUB_OUTPUT="$TMPDIR/github-output.txt"
  touch "$GITHUB_OUTPUT"

  OUTPUT=$(bash "$SCRIPT_DIR/scripts/deploy/parse-broadcast.sh")

  echo "$OUTPUT" | grep -q "MyToken" || { echo "FAIL: MyToken not logged"; exit 1; }
  echo "$OUTPUT" | grep -q "MyProxy" || { echo "FAIL: MyProxy not logged"; exit 1; }

  echo "PASS: logs CREATE entries"
) || { FAILURES=$((FAILURES + 1)); }

# Test 3: Fails when no broadcast file exists
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cd "$TMPDIR"

  export GITHUB_OUTPUT="$TMPDIR/github-output.txt"
  touch "$GITHUB_OUTPUT"

  if bash "$SCRIPT_DIR/scripts/deploy/parse-broadcast.sh" > /dev/null 2>&1; then
    echo "FAIL: should have exited with error"
    exit 1
  fi

  echo "PASS: fails when no broadcast file"
) || { FAILURES=$((FAILURES + 1)); }

echo "--- $((3 - FAILURES))/3 tests passed ---"
exit $FAILURES
