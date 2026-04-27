#!/usr/bin/env bash
set -euo pipefail
# Validate that no contracts were removed from the upgrades config compared to the base branch.
# Compares by .contract field only. Prevents bypassing upgrade safety by removing entries.
#
# Set top-level "dangerous": true in upgrades.json to opt out of the removal guard for that PR
# (removals are reported as a warning instead of an error).
#
# Env inputs:
#   UPGRADES_CONFIG   — required, path to upgrades.json
#   BASE_BRANCH       — required, branch name to compare against

: "${UPGRADES_CONFIG:?UPGRADES_CONFIG is required}"
: "${BASE_BRANCH:?BASE_BRANCH is required}"

if [[ ! -f "$UPGRADES_CONFIG" ]]; then
  echo "::error::No upgrades config found at $UPGRADES_CONFIG"
  exit 1
fi

# Fetch the base branch
if ! git fetch origin "$BASE_BRANCH" 2>/dev/null; then
  echo "::error::Failed to fetch base branch $BASE_BRANCH — cannot validate config changes"
  exit 1
fi

# Read base branch config
if ! git show "origin/${BASE_BRANCH}:${UPGRADES_CONFIG}" > /dev/null 2>&1; then
  echo "No $UPGRADES_CONFIG on base branch — nothing to compare against"
  exit 0
fi

BASE_CONFIG=$(git show "origin/${BASE_BRANCH}:${UPGRADES_CONFIG}") || {
  echo "::error::Failed to read $UPGRADES_CONFIG from base branch $BASE_BRANCH"
  exit 1
}

CURRENT_CONTRACTS=$(jq -r '[.contracts[].contract]' "$UPGRADES_CONFIG")
BASE_CONTRACTS=$(echo "$BASE_CONFIG" | jq -r '[.contracts[].contract]')
DANGEROUS=$(jq -r '.dangerous == true' "$UPGRADES_CONFIG")

# Find base branch contracts missing from current config
REMOVED=$(jq -n --argjson base "$BASE_CONTRACTS" --argjson current "$CURRENT_CONTRACTS" \
  '[$base[] | select(. as $b | $current | index($b) | not)]')

REMOVED_COUNT=$(echo "$REMOVED" | jq 'length')

if [[ "$REMOVED_COUNT" -gt 0 ]]; then
  REMOVED_LIST=$(echo "$REMOVED" | jq -r '.[]')
  if [[ "$DANGEROUS" == "true" ]]; then
    echo "::warning::$REMOVED_COUNT contract(s) removed from $UPGRADES_CONFIG compared to base branch ($BASE_BRANCH) — allowed by \"dangerous\": true:"
    echo "$REMOVED_LIST"
    {
      echo "## Upgrade Config Validation"
      echo ""
      echo "> **Warning:** $REMOVED_COUNT contract(s) were removed from \`$UPGRADES_CONFIG\` — allowed by \`\"dangerous\": true\`:"
      echo ""
      echo "$REMOVED_LIST" | while read -r c; do echo "- \`$c\`"; done
    } >> "$GITHUB_STEP_SUMMARY"
  else
    echo "::error::$REMOVED_COUNT contract(s) removed from $UPGRADES_CONFIG compared to base branch ($BASE_BRANCH):"
    echo "$REMOVED_LIST"
    {
      echo "## Upgrade Config Validation"
      echo ""
      echo "> **Error:** $REMOVED_COUNT contract(s) were removed from \`$UPGRADES_CONFIG\`:"
      echo ""
      echo "$REMOVED_LIST" | while read -r c; do echo "- \`$c\`"; done
      echo ""
      echo "> Set top-level \`\"dangerous\": true\` in \`$UPGRADES_CONFIG\` to allow this removal."
    } >> "$GITHUB_STEP_SUMMARY"
    exit 1
  fi
fi

CURRENT_COUNT=$(echo "$CURRENT_CONTRACTS" | jq 'length')
BASE_COUNT=$(echo "$BASE_CONTRACTS" | jq 'length')
echo "Config validation passed: $CURRENT_COUNT contracts (base branch has $BASE_COUNT)"
