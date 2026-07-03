#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0

echo "=== Testing scripts/deploy/write-deployment-json.sh ==="

# Test 1: Writes deployment.json with CREATE and CREATE2 contracts
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cp -r "$SCRIPT_DIR/tests/fixtures/broadcast" "$TMPDIR/"
  cd "$TMPDIR"

  export BROADCAST_FILE="broadcast/Deploy.s.sol/31337/run-latest.json"
  export NETWORK_NAME="sepolia"

  bash "$SCRIPT_DIR/scripts/deploy/write-deployment-json.sh" > /dev/null

  [[ -f deployments/sepolia/deployment.json ]] || { echo "FAIL: deployment.json not created"; exit 1; }

  COUNT=$(jq '.contracts | length' deployments/sepolia/deployment.json)
  [[ "$COUNT" -eq 3 ]] || { echo "FAIL: expected 3 contracts, got $COUNT"; exit 1; }

  jq -e '.contracts[] | select(.sourcePathAndName == "src/MyToken.sol:MyToken" and .address == "0x1234567890abcdef1234567890abcdef12345678")' \
    deployments/sepolia/deployment.json > /dev/null || { echo "FAIL: MyToken entry wrong"; exit 1; }
  jq -e '.contracts[] | select(.sourcePathAndName == "src/MyFactory.sol:MyFactory")' \
    deployments/sepolia/deployment.json > /dev/null || { echo "FAIL: CREATE2 contract missing"; exit 1; }

  echo "PASS: writes deployment.json with CREATE and CREATE2 entries"
) || { FAILURES=$((FAILURES + 1)); }

# Test 2: Fails when required env vars are missing
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cd "$TMPDIR"

  if BROADCAST_FILE="" NETWORK_NAME="" bash "$SCRIPT_DIR/scripts/deploy/write-deployment-json.sh" > /dev/null 2>&1; then
    echo "FAIL: should have exited with error"
    exit 1
  fi

  echo "PASS: fails when env vars missing"
) || { FAILURES=$((FAILURES + 1)); }

echo "--- $((2 - FAILURES))/2 tests passed ---"
exit $FAILURES
