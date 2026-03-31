#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$SCRIPT_DIR/tests/fixtures"
FAILURES=0

echo "=== Testing scripts/deploy/resolve-network.sh (jq parsing only) ==="

# Test 1: Finds matching chain ID
(
  RESULT=$(jq -r --argjson cid 31337 '
    (.testnets // [])
    | map(select(.chain_id == $cid))
    | first
    | .blockscout_url // empty
  ' "$FIXTURES/deploy-networks.json")

  [[ "$RESULT" == "http://localhost:4000" ]] || { echo "FAIL: expected http://localhost:4000, got $RESULT"; exit 1; }
  echo "PASS: finds matching chain ID"
) || { FAILURES=$((FAILURES + 1)); }

# Test 2: Finds network name
(
  RESULT=$(jq -r --argjson cid 11155111 '
    (.testnets // [])
    | map(select(.chain_id == $cid))
    | first
    | .name // "unknown"
  ' "$FIXTURES/deploy-networks.json")

  [[ "$RESULT" == "sepolia" ]] || { echo "FAIL: expected sepolia, got $RESULT"; exit 1; }
  echo "PASS: finds network name"
) || { FAILURES=$((FAILURES + 1)); }

# Test 3: Returns empty for unknown chain ID
(
  RESULT=$(jq -r --argjson cid 99999 '
    (.testnets // [])
    | map(select(.chain_id == $cid))
    | first
    | .blockscout_url // empty
  ' "$FIXTURES/deploy-networks.json")

  [[ -z "$RESULT" || "$RESULT" == "null" ]] || { echo "FAIL: expected empty, got $RESULT"; exit 1; }
  echo "PASS: returns empty for unknown chain ID"
) || { FAILURES=$((FAILURES + 1)); }

# Test 4: Fallback to testnets[0]
(
  RESULT=$(jq -r '.testnets[0].blockscout_url' "$FIXTURES/deploy-networks.json")

  [[ "$RESULT" == "https://eth-sepolia.blockscout.com" ]] || { echo "FAIL: expected sepolia URL, got $RESULT"; exit 1; }
  echo "PASS: fallback to testnets[0] works"
) || { FAILURES=$((FAILURES + 1)); }

echo "--- $((4 - FAILURES))/4 tests passed ---"
exit $FAILURES
