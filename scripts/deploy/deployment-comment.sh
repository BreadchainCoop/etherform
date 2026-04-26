#!/usr/bin/env bash
set -euo pipefail
# Render the deployment address table as a sticky-PR-comment markdown file.
#
# Env inputs:
#   BLOCKSCOUT_URL  — required
#   NETWORK_NAME    — optional, included in the title when set
#   OUTPUT_FILE     — optional, defaults to deployment-comment.md
#
# File inputs:
#   deployment-summary.txt must exist in the working directory

: "${BLOCKSCOUT_URL:?BLOCKSCOUT_URL is required}"
NETWORK_NAME="${NETWORK_NAME:-}"
OUTPUT_FILE="${OUTPUT_FILE:-deployment-comment.md}"

if [[ -n "$NETWORK_NAME" ]]; then
  TITLE="Testnet Deployment — $NETWORK_NAME"
else
  TITLE="Testnet Deployment"
fi

{
  echo "## $TITLE"
  echo ""
  echo "| Contract | Address | Explorer |"
  echo "|----------|---------|----------|"

  while read -r line; do
    CONTRACT=$(echo "$line" | cut -d: -f1)
    ADDRESS=$(echo "$line" | cut -d: -f2 | tr -d ' ')
    echo "| $CONTRACT | \`$ADDRESS\` | [View](${BLOCKSCOUT_URL}/address/$ADDRESS) |"
  done < deployment-summary.txt
} > "$OUTPUT_FILE"
