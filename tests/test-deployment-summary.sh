#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0

echo "=== Testing scripts/deploy/deployment-summary.sh ==="

# Test 1: Generates markdown table
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cd "$TMPDIR"

  cat > deployment-summary.txt <<'EOF'
MyToken: 0x1234567890abcdef1234567890abcdef12345678
MyProxy: 0xabcdefabcdefabcdefabcdefabcdefabcdefabcd
EOF

  export BLOCKSCOUT_URL="https://eth-sepolia.blockscout.com"
  export GITHUB_STEP_SUMMARY="$TMPDIR/summary.md"
  touch "$GITHUB_STEP_SUMMARY"

  bash "$SCRIPT_DIR/scripts/deploy/deployment-summary.sh"

  grep -q "Deployment Summary" "$GITHUB_STEP_SUMMARY" || { echo "FAIL: no title"; exit 1; }
  grep -q "MyToken" "$GITHUB_STEP_SUMMARY" || { echo "FAIL: MyToken not found"; exit 1; }
  grep -q "MyProxy" "$GITHUB_STEP_SUMMARY" || { echo "FAIL: MyProxy not found"; exit 1; }
  grep -q "View" "$GITHUB_STEP_SUMMARY" || { echo "FAIL: explorer link not found"; exit 1; }

  echo "PASS: generates markdown table"
) || { FAILURES=$((FAILURES + 1)); }

# Test 2: Custom title via SUMMARY_TITLE
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cd "$TMPDIR"

  cat > deployment-summary.txt <<'EOF'
MyToken: 0x1234567890abcdef1234567890abcdef12345678
EOF

  export BLOCKSCOUT_URL="https://eth-sepolia.blockscout.com"
  export SUMMARY_TITLE="Testnet Deployment Summary"
  export GITHUB_STEP_SUMMARY="$TMPDIR/summary.md"
  touch "$GITHUB_STEP_SUMMARY"

  bash "$SCRIPT_DIR/scripts/deploy/deployment-summary.sh"

  grep -q "Testnet Deployment Summary" "$GITHUB_STEP_SUMMARY" || { echo "FAIL: custom title not found"; exit 1; }

  echo "PASS: custom title works"
) || { FAILURES=$((FAILURES + 1)); }

echo "--- $((2 - FAILURES))/2 tests passed ---"
exit $FAILURES
