#!/usr/bin/env bash
set -euo pipefail
# Resolve Blockscout URL and network name from chain ID.
# Validates that the Blockscout API is reachable.
#
# Env inputs:
#   CHAIN_ID        — required
#   NETWORK_CONFIG  — required, path to deploy-networks.json
#
# Outputs (via $GITHUB_OUTPUT):
#   blockscout_url
#   network_name

: "${CHAIN_ID:?CHAIN_ID is required}"
: "${NETWORK_CONFIG:?NETWORK_CONFIG is required}"

# Search testnets array for a matching chain_id
BLOCKSCOUT_URL=$(jq -r --argjson cid "$CHAIN_ID" '
  (.testnets // [])
  | map(select(.chain_id == $cid))
  | first
  | .blockscout_url // empty
' "$NETWORK_CONFIG" 2>/dev/null) || true

if [[ -z "$BLOCKSCOUT_URL" || "$BLOCKSCOUT_URL" == "null" ]]; then
  echo "::warning::No Blockscout URL found for chain ID $CHAIN_ID in $NETWORK_CONFIG. Falling back to testnets[0]."
  BLOCKSCOUT_URL=$(jq -r '.testnets[0].blockscout_url' "$NETWORK_CONFIG")
fi

NETWORK_NAME=$(jq -r --argjson cid "$CHAIN_ID" '
  (.testnets // [])
  | map(select(.chain_id == $cid))
  | first
  | .name // "unknown"
' "$NETWORK_CONFIG" 2>/dev/null) || NETWORK_NAME="unknown"

# Validate Blockscout API
BLOCKSCOUT_API="${BLOCKSCOUT_URL%/}/api/"
echo "Checking Blockscout API at: $BLOCKSCOUT_API"

RESPONSE=$(curl -sS --max-time 10 \
  "${BLOCKSCOUT_API}?module=block&action=eth_block_number" || true)

STATUS=$(echo "$RESPONSE" | jq -r '.jsonrpc // empty' 2>/dev/null || true)

if [[ "$STATUS" != "2.0" ]]; then
  echo "::error::Invalid Blockscout API URL: $BLOCKSCOUT_API"
  echo "Response was:"
  echo "$RESPONSE"
  exit 1
fi

echo "Blockscout API looks valid"

echo "blockscout_url=$BLOCKSCOUT_URL" >> "$GITHUB_OUTPUT"
echo "network_name=$NETWORK_NAME" >> "$GITHUB_OUTPUT"
echo "Resolved Blockscout URL for chain $CHAIN_ID: $BLOCKSCOUT_URL ($NETWORK_NAME)"
