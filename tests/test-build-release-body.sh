#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/scripts/release/build-release-body.sh"
FIXTURES="$SCRIPT_DIR/tests/fixtures"
FAILURES=0

echo "=== Testing scripts/release/build-release-body.sh ==="

common_env() {
  export BLOCKSCOUT_URL="https://eth-sepolia.blockscout.com"
  export NETWORK_NAME="sepolia"
  export CHAIN_ID="11155111"
  export PR_NUMBER="42"
  export PR_TITLE="Add greeter contract"
  export PR_URL="https://github.com/owner/repo/pull/42"
  export MERGE_SHA="abcdef1234567890abcdef1234567890abcdef12"
  export RUN_URL="https://github.com/owner/repo/actions/runs/999"
}

# Test 1: Renders banner, PR link, commit, and contract table from fixture
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  common_env
  export BROADCAST_FILE="$FIXTURES/broadcast/Deploy.s.sol/31337/run-latest.json"
  export OUTPUT_FILE="$TMPDIR/body.md"

  bash "$SCRIPT" > /dev/null

  grep -q "Testnet deployment" "$OUTPUT_FILE" || { echo "FAIL: missing testnet banner"; exit 1; }
  grep -q "\`sepolia\`" "$OUTPUT_FILE" || { echo "FAIL: network name not in banner"; exit 1; }
  grep -q "chain \`11155111\`" "$OUTPUT_FILE" || { echo "FAIL: chain id not in banner"; exit 1; }
  grep -q "#42 Add greeter contract" "$OUTPUT_FILE" || { echo "FAIL: PR title/number missing"; exit 1; }
  grep -q "https://github.com/owner/repo/pull/42" "$OUTPUT_FILE" || { echo "FAIL: PR URL missing"; exit 1; }
  grep -q "Commit: \`abcdef1\`" "$OUTPUT_FILE" || { echo "FAIL: short SHA missing"; exit 1; }
  grep -q "MyToken" "$OUTPUT_FILE" || { echo "FAIL: MyToken row missing"; exit 1; }
  grep -q "MyProxy" "$OUTPUT_FILE" || { echo "FAIL: MyProxy row missing"; exit 1; }
  grep -q '`0x1234567890abcdef1234567890abcdef12345678`' "$OUTPUT_FILE" || { echo "FAIL: backticked address missing"; exit 1; }
  grep -q "https://eth-sepolia.blockscout.com/address/0x1234567890abcdef1234567890abcdef12345678" "$OUTPUT_FILE" || { echo "FAIL: explorer link missing"; exit 1; }
  grep -q "workflow run" "$OUTPUT_FILE" || { echo "FAIL: workflow run footer missing"; exit 1; }

  # Should NOT include CALL transactions — only 2 data rows (MyToken, MyProxy)
  # 1 header + 2 data rows = 3 lines starting with "| " (separator starts with "|-")
  CREATE_ROWS=$(grep -c '^| ' "$OUTPUT_FILE" || true)
  [[ "$CREATE_ROWS" -eq 3 ]] || { echo "FAIL: expected 3 table lines, got $CREATE_ROWS"; cat "$OUTPUT_FILE"; exit 1; }

  echo "PASS: renders banner, PR link, commit, and contract table"
) || { FAILURES=$((FAILURES + 1)); }

# Test 2: Omits deployer line when broadcast.transactions[0].from is null
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  common_env
  export BROADCAST_FILE="$FIXTURES/broadcast/Deploy.s.sol/31337/run-latest.json"
  export OUTPUT_FILE="$TMPDIR/body.md"

  bash "$SCRIPT" > /dev/null

  if grep -q "^Deployer:" "$OUTPUT_FILE"; then
    echo "FAIL: deployer line present despite null from"
    exit 1
  fi
  echo "PASS: omits deployer line when from is null"
) || { FAILURES=$((FAILURES + 1)); }

# Test 3: Includes deployer line and link when from is set
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  common_env
  cat > "$TMPDIR/run-latest.json" <<'EOF'
{
  "transactions": [
    {
      "transactionType": "CREATE",
      "contractName": "Greeter",
      "contractAddress": "0x1111111111111111111111111111111111111111",
      "from": "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
    }
  ]
}
EOF
  export BROADCAST_FILE="$TMPDIR/run-latest.json"
  export OUTPUT_FILE="$TMPDIR/body.md"

  bash "$SCRIPT" > /dev/null

  grep -q "Deployer: \[\`0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\`\]" "$OUTPUT_FILE" \
    || { echo "FAIL: deployer line missing or malformed"; cat "$OUTPUT_FILE"; exit 1; }
  grep -q "https://eth-sepolia.blockscout.com/address/0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "$OUTPUT_FILE" \
    || { echo "FAIL: deployer Blockscout link missing"; exit 1; }
  echo "PASS: includes deployer line and link"
) || { FAILURES=$((FAILURES + 1)); }

# Test 4: Renders empty placeholder when no CREATE transactions
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  common_env
  cat > "$TMPDIR/run-latest.json" <<'EOF'
{
  "transactions": [
    {
      "transactionType": "CALL",
      "contractName": "Greeter",
      "contractAddress": "0x1111111111111111111111111111111111111111",
      "from": "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
    }
  ]
}
EOF
  export BROADCAST_FILE="$TMPDIR/run-latest.json"
  export OUTPUT_FILE="$TMPDIR/body.md"

  bash "$SCRIPT" > /dev/null

  grep -q "_No contracts deployed in this run\._" "$OUTPUT_FILE" \
    || { echo "FAIL: empty placeholder missing"; cat "$OUTPUT_FILE"; exit 1; }
  if grep -q "^| Contract " "$OUTPUT_FILE"; then
    echo "FAIL: table header should not be present when empty"
    exit 1
  fi
  echo "PASS: empty case renders placeholder"
) || { FAILURES=$((FAILURES + 1)); }

# Test 5: Strips trailing slash from BLOCKSCOUT_URL so links don't double-slash
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  common_env
  export BLOCKSCOUT_URL="https://eth-sepolia.blockscout.com/"
  export BROADCAST_FILE="$FIXTURES/broadcast/Deploy.s.sol/31337/run-latest.json"
  export OUTPUT_FILE="$TMPDIR/body.md"

  bash "$SCRIPT" > /dev/null

  if grep -q "blockscout.com//address/" "$OUTPUT_FILE"; then
    echo "FAIL: double slash in explorer URL"
    exit 1
  fi
  grep -q "blockscout.com/address/" "$OUTPUT_FILE" \
    || { echo "FAIL: explorer URL malformed"; cat "$OUTPUT_FILE"; exit 1; }
  echo "PASS: trailing slash stripped from BLOCKSCOUT_URL"
) || { FAILURES=$((FAILURES + 1)); }

# Test 6: Fails when BROADCAST_FILE doesn't exist
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  common_env
  export BROADCAST_FILE="$TMPDIR/missing.json"
  export OUTPUT_FILE="$TMPDIR/body.md"

  if bash "$SCRIPT" > /dev/null 2>&1; then
    echo "FAIL: should have failed on missing broadcast file"
    exit 1
  fi
  echo "PASS: fails on missing broadcast file"
) || { FAILURES=$((FAILURES + 1)); }

# Test 7: Fails when a required env var is missing
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  common_env
  unset PR_NUMBER
  export BROADCAST_FILE="$FIXTURES/broadcast/Deploy.s.sol/31337/run-latest.json"
  export OUTPUT_FILE="$TMPDIR/body.md"

  if bash "$SCRIPT" > /dev/null 2>&1; then
    echo "FAIL: should have failed on missing PR_NUMBER"
    exit 1
  fi
  echo "PASS: fails on missing required env var"
) || { FAILURES=$((FAILURES + 1)); }

TOTAL=7
echo "--- $((TOTAL - FAILURES))/$TOTAL tests passed ---"
exit $FAILURES
