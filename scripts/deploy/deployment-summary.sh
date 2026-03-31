#!/usr/bin/env bash
set -euo pipefail
# Write a deployment summary table to $GITHUB_STEP_SUMMARY.
#
# Env inputs:
#   BLOCKSCOUT_URL  — required
#   SUMMARY_TITLE   — optional, defaults to "Deployment Summary"
#
# File inputs:
#   deployment-summary.txt must exist in the working directory

: "${BLOCKSCOUT_URL:?BLOCKSCOUT_URL is required}"
TITLE="${SUMMARY_TITLE:-Deployment Summary}"

echo "## $TITLE" >> "$GITHUB_STEP_SUMMARY"
echo "" >> "$GITHUB_STEP_SUMMARY"
echo "| Contract | Address | Explorer |" >> "$GITHUB_STEP_SUMMARY"
echo "|----------|---------|----------|" >> "$GITHUB_STEP_SUMMARY"

while read -r line; do
  CONTRACT=$(echo "$line" | cut -d: -f1)
  ADDRESS=$(echo "$line" | cut -d: -f2 | tr -d ' ')
  echo "| $CONTRACT | \`$ADDRESS\` | [View](${BLOCKSCOUT_URL}/address/$ADDRESS) |" >> "$GITHUB_STEP_SUMMARY"
done < deployment-summary.txt
