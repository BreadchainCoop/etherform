#!/usr/bin/env bash
set -euo pipefail
# Parse Foundry broadcast artifacts after deployment.
# Finds run-latest.json and extracts the chain ID.
#
# Outputs (via $GITHUB_OUTPUT):
#   broadcast_file  — path to the broadcast JSON
#   chain_id        — chain ID extracted from directory structure

BROADCAST_FILE=$(find broadcast -name "run-latest.json" -type f | head -1)
if [[ -z "$BROADCAST_FILE" ]]; then
  echo "No broadcast file found"
  exit 1
fi
echo "broadcast_file=$BROADCAST_FILE" >> "$GITHUB_OUTPUT"

# Extract chain ID from path: broadcast/<script>/<chain_id>/run-latest.json
CHAIN_ID=$(echo "$BROADCAST_FILE" | sed -E 's|.*/([0-9]+)/run-latest\.json$|\1|')
echo "chain_id=$CHAIN_ID" >> "$GITHUB_OUTPUT"
echo "Deployed to chain ID: $CHAIN_ID"

jq -r '.transactions[] | select(.transactionType == "CREATE") | "\(.contractName): \(.contractAddress)"' "$BROADCAST_FILE"
