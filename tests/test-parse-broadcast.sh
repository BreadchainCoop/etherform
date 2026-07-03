#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0

echo "=== Testing scripts/deploy/parse-broadcast.sh ==="

# Test 1: Parses broadcast file and extracts chain ID (from the chain field)
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

# Test 2: Summary includes CREATE and CREATE2, excludes CALL and unnamed
# nested deployments (additionalContracts)
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cp -r "$SCRIPT_DIR/tests/fixtures/broadcast" "$TMPDIR/"
  cd "$TMPDIR"

  export GITHUB_OUTPUT="$TMPDIR/github-output.txt"
  touch "$GITHUB_OUTPUT"

  bash "$SCRIPT_DIR/scripts/deploy/parse-broadcast.sh" > /dev/null

  [[ $(wc -l < deployment-summary.txt) -eq 3 ]] || { echo "FAIL: expected 3 lines, got $(wc -l < deployment-summary.txt)"; cat deployment-summary.txt; exit 1; }
  grep -q "MyToken" deployment-summary.txt || { echo "FAIL: MyToken not found"; exit 1; }
  grep -q "MyProxy" deployment-summary.txt || { echo "FAIL: MyProxy not found"; exit 1; }
  grep -q "MyFactory" deployment-summary.txt || { echo "FAIL: MyFactory (CREATE2) not found"; exit 1; }
  grep -q "0x9999999999999999999999999999999999999999" deployment-summary.txt && { echo "FAIL: unnamed nested deployment should be excluded"; exit 1; }

  echo "PASS: deployment-summary.txt has CREATE and CREATE2 entries only"
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

# Test 4: Fails on ambiguous broadcasts (multiple run-latest.json, no scoping)
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cp -r "$SCRIPT_DIR/tests/fixtures/broadcast" "$TMPDIR/"
  cd "$TMPDIR"
  mkdir -p broadcast/Other.s.sol/1
  cp broadcast/Deploy.s.sol/31337/run-latest.json broadcast/Other.s.sol/1/run-latest.json

  export GITHUB_OUTPUT="$TMPDIR/github-output.txt"
  touch "$GITHUB_OUTPUT"

  if bash "$SCRIPT_DIR/scripts/deploy/parse-broadcast.sh" > /dev/null 2>&1; then
    echo "FAIL: should have exited with error on ambiguous broadcasts"
    exit 1
  fi

  echo "PASS: fails on ambiguous broadcast files"
) || { FAILURES=$((FAILURES + 1)); }

# Test 5: DEPLOY_SCRIPT scopes the search when multiple broadcasts exist
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cp -r "$SCRIPT_DIR/tests/fixtures/broadcast" "$TMPDIR/"
  cd "$TMPDIR"
  mkdir -p broadcast/Other.s.sol/1
  cp broadcast/Deploy.s.sol/31337/run-latest.json broadcast/Other.s.sol/1/run-latest.json

  export GITHUB_OUTPUT="$TMPDIR/github-output.txt"
  export DEPLOY_SCRIPT="script/Deploy.s.sol:Deploy"
  touch "$GITHUB_OUTPUT"

  bash "$SCRIPT_DIR/scripts/deploy/parse-broadcast.sh" > /dev/null

  grep -q "broadcast_file=broadcast/Deploy.s.sol/31337/run-latest.json" "$GITHUB_OUTPUT" \
    || { echo "FAIL: DEPLOY_SCRIPT did not scope the search"; cat "$GITHUB_OUTPUT"; exit 1; }

  echo "PASS: DEPLOY_SCRIPT scopes the broadcast search"
) || { FAILURES=$((FAILURES + 1)); }

echo "--- $((5 - FAILURES))/5 tests passed ---"
exit $FAILURES
