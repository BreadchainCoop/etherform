#!/usr/bin/env bash
set -euo pipefail
# Parse Foundry broadcast artifacts after deployment.
# Finds run-latest.json, extracts chain ID, writes deployment-summary.txt.
#
# Deployments are collected from top-level CREATE and CREATE2 transactions.
# Contracts deployed by other contracts (additionalContracts) have no name in
# the broadcast artifact; they are listed in the log but excluded from the
# summary since they cannot be labeled or verified.
#
# Env inputs:
#   DEPLOY_SCRIPT — optional, deploy script spec (e.g. script/Deploy.s.sol:Deploy);
#                   scopes the broadcast search to that script's directory
#
# Outputs (via $GITHUB_OUTPUT):
#   broadcast_file  — path to the broadcast JSON
#   chain_id        — chain ID from the artifact (directory name as fallback)

SEARCH_DIR="broadcast"
if [[ -n "${DEPLOY_SCRIPT:-}" ]]; then
  # script/Deploy.s.sol:Deploy -> broadcast/Deploy.s.sol
  SCRIPT_FILE=$(basename "${DEPLOY_SCRIPT%%:*}")
  if [[ -d "broadcast/$SCRIPT_FILE" ]]; then
    SEARCH_DIR="broadcast/$SCRIPT_FILE"
  fi
fi

BROADCAST_FILES=$(find "$SEARCH_DIR" -name "run-latest.json" -type f 2>/dev/null | sort)
if [[ -z "$BROADCAST_FILES" ]]; then
  echo "::error::No broadcast file found under $SEARCH_DIR"
  exit 1
fi

FILE_COUNT=$(echo "$BROADCAST_FILES" | wc -l | tr -d ' ')
if [[ "$FILE_COUNT" -gt 1 ]]; then
  echo "::error::Found $FILE_COUNT broadcast files under $SEARCH_DIR — cannot determine which deployment to use:"
  echo "$BROADCAST_FILES"
  echo "Set DEPLOY_SCRIPT to scope the search, or clean up stale broadcast directories."
  exit 1
fi
BROADCAST_FILE="$BROADCAST_FILES"
echo "broadcast_file=$BROADCAST_FILE" >> "$GITHUB_OUTPUT"

# Prefer the chain field in the artifact; fall back to the directory name
# (broadcast/<script>/<chain_id>/run-latest.json)
CHAIN_ID=$(jq -r '.chain // empty' "$BROADCAST_FILE")
if [[ -z "$CHAIN_ID" ]]; then
  CHAIN_ID=$(echo "$BROADCAST_FILE" | sed -E 's|.*/([0-9]+)/run-latest\.json$|\1|')
fi
echo "chain_id=$CHAIN_ID" >> "$GITHUB_OUTPUT"
echo "Deployed to chain ID: $CHAIN_ID"

# Warn about unnamed nested deployments so they are not silently dropped
UNNAMED_COUNT=$(jq '[.transactions[].additionalContracts // [] | .[]] | length' "$BROADCAST_FILE")
if [[ "$UNNAMED_COUNT" -gt 0 ]]; then
  echo "::warning::$UNNAMED_COUNT contract(s) were deployed by other contracts (additionalContracts). They have no name in the broadcast artifact and are excluded from the summary and verification:"
  jq -r '.transactions[].additionalContracts // [] | .[] | "  \(.transactionType) at \(.address)"' "$BROADCAST_FILE"
fi

jq -r '.transactions[]
  | select(.transactionType == "CREATE" or .transactionType == "CREATE2")
  | select(.contractName != null)
  | "\(.contractName): \(.contractAddress)"' "$BROADCAST_FILE" | tee deployment-summary.txt
