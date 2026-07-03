#!/usr/bin/env bash
set -euo pipefail
# Write the deployment artifact consumed by frontends:
#   deployments/<network>/deployment.json
# with schema {contracts: [{sourcePathAndName, address}]}.
#
# Collects top-level CREATE and CREATE2 transactions from the broadcast file.
#
# Env inputs:
#   BROADCAST_FILE — required, path to run-latest.json
#   NETWORK_NAME   — required, used as the deployments/ subdirectory
#   SOURCE_ROOT    — optional, source directory prefix (default: src)

: "${BROADCAST_FILE:?BROADCAST_FILE is required}"
: "${NETWORK_NAME:?NETWORK_NAME is required}"
SOURCE_ROOT="${SOURCE_ROOT:-src}"

mkdir -p "deployments/$NETWORK_NAME"

jq --arg root "$SOURCE_ROOT" '{
  contracts: [
    .transactions[]
    | select(.transactionType == "CREATE" or .transactionType == "CREATE2")
    | select(.contractName != null)
    | {
        sourcePathAndName: "\($root)/\(.contractName).sol:\(.contractName)",
        address: .contractAddress
      }
  ]
}' "$BROADCAST_FILE" > "deployments/$NETWORK_NAME/deployment.json"

echo "Wrote deployments/$NETWORK_NAME/deployment.json:"
cat "deployments/$NETWORK_NAME/deployment.json"
