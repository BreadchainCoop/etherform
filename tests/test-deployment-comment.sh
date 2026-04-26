#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0

echo "=== Testing scripts/deploy/deployment-comment.sh ==="

# Test 1: Renders markdown table from deployment-summary.txt
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cd "$TMPDIR"

  cat > deployment-summary.txt <<'EOF'
MyToken: 0x1234567890abcdef1234567890abcdef12345678
MyProxy: 0xabcdefabcdefabcdefabcdefabcdefabcdefabcd
EOF

  export BLOCKSCOUT_URL="https://eth-sepolia.blockscout.com"

  bash "$SCRIPT_DIR/scripts/deploy/deployment-comment.sh"

  [[ -f deployment-comment.md ]] || { echo "FAIL: default output file not created"; exit 1; }
  grep -q "## Testnet Deployment" deployment-comment.md || { echo "FAIL: missing title"; exit 1; }
  grep -q "MyToken" deployment-comment.md || { echo "FAIL: MyToken row missing"; exit 1; }
  grep -q "MyProxy" deployment-comment.md || { echo "FAIL: MyProxy row missing"; exit 1; }
  grep -q "https://eth-sepolia.blockscout.com/address/0x1234567890abcdef1234567890abcdef12345678" deployment-comment.md \
    || { echo "FAIL: explorer link missing or wrong"; exit 1; }

  echo "PASS: renders markdown table"
) || { FAILURES=$((FAILURES + 1)); }

# Test 2: Includes network name in title when set
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cd "$TMPDIR"

  cat > deployment-summary.txt <<'EOF'
MyToken: 0x1234567890abcdef1234567890abcdef12345678
EOF

  export BLOCKSCOUT_URL="https://eth-sepolia.blockscout.com"
  export NETWORK_NAME="sepolia"

  bash "$SCRIPT_DIR/scripts/deploy/deployment-comment.sh"

  grep -q "## Testnet Deployment — sepolia" deployment-comment.md \
    || { echo "FAIL: network name not in title"; exit 1; }

  echo "PASS: network name appears in title"
) || { FAILURES=$((FAILURES + 1)); }

# Test 3: Omits network name from title when unset/empty
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cd "$TMPDIR"

  cat > deployment-summary.txt <<'EOF'
MyToken: 0x1234567890abcdef1234567890abcdef12345678
EOF

  export BLOCKSCOUT_URL="https://eth-sepolia.blockscout.com"
  export NETWORK_NAME=""

  bash "$SCRIPT_DIR/scripts/deploy/deployment-comment.sh"

  FIRST_LINE=$(head -1 deployment-comment.md)
  [[ "$FIRST_LINE" == "## Testnet Deployment" ]] \
    || { echo "FAIL: expected plain title, got: $FIRST_LINE"; exit 1; }

  echo "PASS: omits network name when unset"
) || { FAILURES=$((FAILURES + 1)); }

# Test 4: Honors OUTPUT_FILE
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cd "$TMPDIR"

  cat > deployment-summary.txt <<'EOF'
MyToken: 0x1234567890abcdef1234567890abcdef12345678
EOF

  export BLOCKSCOUT_URL="https://eth-sepolia.blockscout.com"
  export OUTPUT_FILE="custom-name.md"

  bash "$SCRIPT_DIR/scripts/deploy/deployment-comment.sh"

  [[ -f custom-name.md ]] || { echo "FAIL: custom OUTPUT_FILE not honored"; exit 1; }
  [[ ! -f deployment-comment.md ]] || { echo "FAIL: default file written despite OUTPUT_FILE"; exit 1; }

  echo "PASS: writes to custom OUTPUT_FILE"
) || { FAILURES=$((FAILURES + 1)); }

# Test 5: Fails when BLOCKSCOUT_URL is missing
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cd "$TMPDIR"

  cat > deployment-summary.txt <<'EOF'
MyToken: 0x1234567890abcdef1234567890abcdef12345678
EOF

  unset BLOCKSCOUT_URL || true

  if bash "$SCRIPT_DIR/scripts/deploy/deployment-comment.sh" 2>/dev/null; then
    echo "FAIL: expected non-zero exit when BLOCKSCOUT_URL missing"
    exit 1
  fi

  echo "PASS: fails fast when BLOCKSCOUT_URL missing"
) || { FAILURES=$((FAILURES + 1)); }

echo "--- $((5 - FAILURES))/5 tests passed ---"
exit $FAILURES
