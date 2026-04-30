#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$SCRIPT_DIR/tests/fixtures/broadcast/Deploy.s.sol/31337/run-latest.json"
FAILURES=0

echo "=== Testing scripts/deploy/deployment-summary.sh ==="

# Test 1: Generates deployed-contracts table with constructor args + explorer
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT

  export BLOCKSCOUT_URL="https://eth-sepolia.blockscout.com"
  export BROADCAST_FILE="$FIXTURE"
  export GITHUB_STEP_SUMMARY="$TMPDIR/summary.md"
  touch "$GITHUB_STEP_SUMMARY"

  bash "$SCRIPT_DIR/scripts/deploy/deployment-summary.sh"

  grep -q "Deployment Summary" "$GITHUB_STEP_SUMMARY" || { echo "FAIL: no title"; exit 1; }
  grep -q "Constructor Args" "$GITHUB_STEP_SUMMARY" || { echo "FAIL: header missing"; exit 1; }
  grep -q "MyToken" "$GITHUB_STEP_SUMMARY" || { echo "FAIL: MyToken not found"; exit 1; }
  grep -q "MyProxy" "$GITHUB_STEP_SUMMARY" || { echo "FAIL: MyProxy not found"; exit 1; }
  grep -q "0xAdminAdminAdminAdminAdminAdminAdminAdmin0001" "$GITHUB_STEP_SUMMARY" \
    || { echo "FAIL: constructor arg not rendered"; exit 1; }
  grep -q "_(none)_" "$GITHUB_STEP_SUMMARY" \
    || { echo "FAIL: empty-args placeholder not rendered"; exit 1; }
  grep -q "View" "$GITHUB_STEP_SUMMARY" || { echo "FAIL: explorer link missing"; exit 1; }

  echo "PASS: deployed-contracts table renders"
) || { FAILURES=$((FAILURES + 1)); }

# Test 2: Method calls section appears with function + args
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT

  export BLOCKSCOUT_URL="https://eth-sepolia.blockscout.com"
  export BROADCAST_FILE="$FIXTURE"
  export GITHUB_STEP_SUMMARY="$TMPDIR/summary.md"
  touch "$GITHUB_STEP_SUMMARY"

  bash "$SCRIPT_DIR/scripts/deploy/deployment-summary.sh"

  grep -q "<details>" "$GITHUB_STEP_SUMMARY" || { echo "FAIL: <details> missing"; exit 1; }
  grep -q "Method Calls" "$GITHUB_STEP_SUMMARY" || { echo "FAIL: Method Calls header missing"; exit 1; }
  grep -q "initialize(address,uint256)" "$GITHUB_STEP_SUMMARY" \
    || { echo "FAIL: function signature missing"; exit 1; }
  grep -q "1000000000000000000" "$GITHUB_STEP_SUMMARY" \
    || { echo "FAIL: call argument missing"; exit 1; }

  echo "PASS: method calls section renders"
) || { FAILURES=$((FAILURES + 1)); }

# Test 3: Method calls section is omitted when there are no CALLs
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT

  cat > "$TMPDIR/run-latest.json" <<'EOF'
{
  "transactions": [
    {
      "transactionType": "CREATE",
      "contractName": "OnlyContract",
      "contractAddress": "0x1111111111111111111111111111111111111111",
      "arguments": null
    }
  ]
}
EOF

  export BLOCKSCOUT_URL="https://eth-sepolia.blockscout.com"
  export BROADCAST_FILE="$TMPDIR/run-latest.json"
  export GITHUB_STEP_SUMMARY="$TMPDIR/summary.md"
  touch "$GITHUB_STEP_SUMMARY"

  bash "$SCRIPT_DIR/scripts/deploy/deployment-summary.sh"

  grep -q "OnlyContract" "$GITHUB_STEP_SUMMARY" || { echo "FAIL: contract row missing"; exit 1; }
  if grep -q "Method Calls" "$GITHUB_STEP_SUMMARY"; then
    echo "FAIL: Method Calls section should be omitted when no CALLs"
    exit 1
  fi

  echo "PASS: omits method calls section when none"
) || { FAILURES=$((FAILURES + 1)); }

# Test 4: Custom title via SUMMARY_TITLE
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT

  export BLOCKSCOUT_URL="https://eth-sepolia.blockscout.com"
  export BROADCAST_FILE="$FIXTURE"
  export SUMMARY_TITLE="Testnet Deployment Summary"
  export GITHUB_STEP_SUMMARY="$TMPDIR/summary.md"
  touch "$GITHUB_STEP_SUMMARY"

  bash "$SCRIPT_DIR/scripts/deploy/deployment-summary.sh"

  grep -q "Testnet Deployment Summary" "$GITHUB_STEP_SUMMARY" \
    || { echo "FAIL: custom title not found"; exit 1; }

  echo "PASS: custom title works"
) || { FAILURES=$((FAILURES + 1)); }

# Test 5: Fails when BROADCAST_FILE is missing
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT

  export BLOCKSCOUT_URL="https://eth-sepolia.blockscout.com"
  export BROADCAST_FILE="$TMPDIR/does-not-exist.json"
  export GITHUB_STEP_SUMMARY="$TMPDIR/summary.md"
  touch "$GITHUB_STEP_SUMMARY"

  if bash "$SCRIPT_DIR/scripts/deploy/deployment-summary.sh" > /dev/null 2>&1; then
    echo "FAIL: should have exited with error"
    exit 1
  fi

  echo "PASS: fails on missing broadcast file"
) || { FAILURES=$((FAILURES + 1)); }

echo "--- $((5 - FAILURES))/5 tests passed ---"
exit $FAILURES
