#!/usr/bin/env bash
set -euo pipefail
# Write a deployment summary to $GITHUB_STEP_SUMMARY from a Foundry
# broadcast run-latest.json file: deployed contracts (with constructor args)
# and post-deploy method calls.
#
# Env inputs:
#   BLOCKSCOUT_URL  — required
#   BROADCAST_FILE  — required, path to run-latest.json
#   SUMMARY_TITLE   — optional, defaults to "Deployment Summary"

: "${BLOCKSCOUT_URL:?BLOCKSCOUT_URL is required}"
: "${BROADCAST_FILE:?BROADCAST_FILE is required}"
: "${GITHUB_STEP_SUMMARY:?GITHUB_STEP_SUMMARY is required}"
TITLE="${SUMMARY_TITLE:-Deployment Summary}"

if [[ ! -f "$BROADCAST_FILE" ]]; then
  echo "::error::BROADCAST_FILE not found: $BROADCAST_FILE"
  exit 1
fi

# Format a JSON arguments array (read from stdin) into a markdown-friendly cell.
# Pipe characters are escaped so they don't break the table layout.
format_args() {
  jq -r '
    if . == null or . == [] then "_(none)_"
    else (map("`" + (. | tostring) + "`") | join(", "))
    end
  ' | sed 's/|/\\|/g'
}

{
  echo "## $TITLE"
  echo ""
  echo "| Contract | Address | Constructor Args | Explorer |"
  echo "|----------|---------|------------------|----------|"
  while IFS=$'\t' read -r CONTRACT ADDRESS ARGS_JSON; do
    ARGS=$(printf '%s' "$ARGS_JSON" | format_args)
    echo "| ${CONTRACT:-?} | \`$ADDRESS\` | $ARGS | [View](${BLOCKSCOUT_URL}/address/$ADDRESS) |"
  done < <(jq -r '
    .transactions[]
    | select(.transactionType == "CREATE" or .transactionType == "CREATE2")
    | [(.contractName // ""), .contractAddress, (.arguments // [] | tojson)]
    | @tsv
  ' "$BROADCAST_FILE")

  CALL_COUNT=$(jq '[.transactions[] | select(.transactionType == "CALL")] | length' "$BROADCAST_FILE")
  if [[ "$CALL_COUNT" -gt 0 ]]; then
    echo ""
    echo "<details>"
    echo "<summary>Method Calls ($CALL_COUNT)</summary>"
    echo ""
    echo "| Contract | Address | Method | Arguments |"
    echo "|----------|---------|--------|-----------|"
    while IFS=$'\t' read -r CONTRACT ADDRESS FUNCTION ARGS_JSON; do
      ARGS=$(printf '%s' "$ARGS_JSON" | format_args)
      echo "| ${CONTRACT:-?} | \`$ADDRESS\` | \`${FUNCTION:-?}\` | $ARGS |"
    done < <(jq -r '
      .transactions[]
      | select(.transactionType == "CALL")
      | [(.contractName // ""), .contractAddress, (.function // ""), (.arguments // [] | tojson)]
      | @tsv
    ' "$BROADCAST_FILE")
    echo "</details>"
  fi
} >> "$GITHUB_STEP_SUMMARY"
