#!/usr/bin/env bash
set -euo pipefail
# Validate upgrade safety for contracts listed in upgrades.json.
# Contracts without an explicit reference are compared against the base branch.
# Contracts with an explicit reference are compared within the current build.
#
# Env inputs:
#   UPGRADES_CONFIG   — required, path to upgrades.json
#   BASE_BRANCH       — required, branch name to compare against
#   PACKAGE_MANAGER   — required, one of: none, npm, yarn, pnpm
#   CURRENT_BUILD     — optional, default "out/build-info"

: "${UPGRADES_CONFIG:?UPGRADES_CONFIG is required}"
: "${BASE_BRANCH:?BASE_BRANCH is required}"
: "${PACKAGE_MANAGER:?PACKAGE_MANAGER is required}"
CURRENT_BUILD="${CURRENT_BUILD:-out/build-info}"

# Check if config exists
if [[ ! -f "$UPGRADES_CONFIG" ]]; then
  echo "::error::No upgrades config found at $UPGRADES_CONFIG"
  {
    echo "## Upgrade Safety Validation"
    echo ""
    echo "> **Error:** No \`$UPGRADES_CONFIG\` found. Create the config file or disable upgrade safety."
  } >> "$GITHUB_STEP_SUMMARY"
  exit 1
fi

# Check that contracts field exists
if ! jq -e 'has("contracts")' "$UPGRADES_CONFIG" > /dev/null 2>&1; then
  echo "::error::Missing 'contracts' field in $UPGRADES_CONFIG — expected an array of contract entries"
  {
    echo "## Upgrade Safety Validation"
    echo ""
    echo "> **Error:** \`$UPGRADES_CONFIG\` is missing the \`contracts\` field."
  } >> "$GITHUB_STEP_SUMMARY"
  exit 1
fi

# Check for empty contracts array
CONTRACT_COUNT=$(jq '.contracts | length' "$UPGRADES_CONFIG")
if [[ "$CONTRACT_COUNT" -eq 0 ]]; then
  echo "::warning::No contracts defined in $UPGRADES_CONFIG — skipping upgrade safety validation"
  {
    echo "## Upgrade Safety Validation"
    echo ""
    echo "> No contracts defined in \`$UPGRADES_CONFIG\`. Skipping validation."
  } >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi

# Check if any contracts need base branch comparison (no explicit reference)
NEEDS_BASE=false
while IFS= read -r entry; do
  REF_VALUE=$(echo "$entry" | jq -c '.reference // empty')
  if [[ -z "$REF_VALUE" || "$REF_VALUE" == "null" ]]; then
    NEEDS_BASE=true
    break
  fi
done < <(jq -c '.contracts[]' "$UPGRADES_CONFIG")

# Build base branch in a worktree if needed
BASE_BUILD=""
BASE_DIR=""
if [[ "$NEEDS_BASE" == "true" ]]; then
  echo "Building base branch ($BASE_BRANCH) for comparison..."
  git fetch origin "$BASE_BRANCH" 2>/dev/null || true
  BASE_DIR=$(mktemp -d)

  if git worktree add --detach "$BASE_DIR" "origin/$BASE_BRANCH" 2>/dev/null; then
    (cd "$BASE_DIR" && { git submodule update --init --recursive 2>/dev/null || true; })

    # Install dependencies in base worktree if needed
    if [[ "$PACKAGE_MANAGER" != "none" ]]; then
      (cd "$BASE_DIR" && case "$PACKAGE_MANAGER" in
        npm)  npm ci ;;
        yarn) yarn --frozen-lockfile ;;
        pnpm) corepack enable && pnpm install --frozen-lockfile ;;
      esac) || echo "::warning::Failed to install dependencies in base branch"
    fi

    if (cd "$BASE_DIR" && forge build --build-info --extra-output storageLayout 2>&1); then
      mv "${BASE_DIR}/out/build-info" "${BASE_DIR}/out/base-build-info"
      BASE_BUILD="${BASE_DIR}/out/base-build-info"
      echo "Base branch built successfully"
    else
      echo "::warning::Failed to build base branch — contracts without explicit reference will be validated for upgradeability only"
    fi
  else
    echo "::warning::Could not checkout base branch '$BASE_BRANCH' — contracts without explicit reference will be validated for upgradeability only"
  fi
fi

PASSED=0
FAILED=0
SUMMARY=""

# Validate each contract
while IFS= read -r entry; do
  CONTRACT=$(echo "$entry" | jq -r '.contract')
  REF_VALUE=$(echo "$entry" | jq -c '.reference // empty')
  CONTRACT_PATH="${CONTRACT%%:*}"

  echo "::group::Validating $CONTRACT"

  if [[ -z "$REF_VALUE" || "$REF_VALUE" == "null" ]]; then
    # === Base branch comparison (default) ===
    if [[ -n "$BASE_BUILD" ]] && git show "origin/${BASE_BRANCH}:${CONTRACT_PATH}" > /dev/null 2>&1; then
      # Contract exists on base branch — compare storage layouts
      if OUTPUT=$(npx @openzeppelin/upgrades-core validate "$CURRENT_BUILD" \
          --contract "$CONTRACT" \
          --reference "base-build-info:${CONTRACT}" \
          --referenceBuildInfoDirs "$BASE_BUILD" 2>&1); then
        echo "$OUTPUT"
        SUMMARY="${SUMMARY}| \`${CONTRACT}\` | \`${BASE_BRANCH}\` branch | Pass |"$'\n'
        PASSED=$((PASSED + 1))
      else
        echo "$OUTPUT"
        SUMMARY="${SUMMARY}| \`${CONTRACT}\` | \`${BASE_BRANCH}\` branch | **FAIL** |"$'\n'
        FAILED=$((FAILED + 1))
      fi
    else
      # Contract doesn't exist on base branch or base build failed — validate upgradeability only
      echo "Contract not found on $BASE_BRANCH or base build unavailable, validating upgradeability only..."
      if OUTPUT=$(npx @openzeppelin/upgrades-core validate "$CURRENT_BUILD" \
          --contract "$CONTRACT" 2>&1); then
        echo "$OUTPUT"
        SUMMARY="${SUMMARY}| \`${CONTRACT}\` | (new contract) | Pass |"$'\n'
        PASSED=$((PASSED + 1))
      else
        echo "$OUTPUT"
        SUMMARY="${SUMMARY}| \`${CONTRACT}\` | (new contract) | **FAIL** |"$'\n'
        FAILED=$((FAILED + 1))
      fi
    fi

  elif echo "$REF_VALUE" | jq -e 'type == "string"' > /dev/null 2>&1; then
    # === Contract qualifier reference ===
    QUALIFIER=$(echo "$entry" | jq -r '.reference')
    if OUTPUT=$(npx @openzeppelin/upgrades-core validate "$CURRENT_BUILD" \
        --contract "$CONTRACT" \
        --reference "$QUALIFIER" 2>&1); then
      echo "$OUTPUT"
      SUMMARY="${SUMMARY}| \`${CONTRACT}\` | \`${QUALIFIER}\` | Pass |"$'\n'
      PASSED=$((PASSED + 1))
    else
      echo "$OUTPUT"
      SUMMARY="${SUMMARY}| \`${CONTRACT}\` | \`${QUALIFIER}\` | **FAIL** |"$'\n'
      FAILED=$((FAILED + 1))
    fi

  else
    echo "::error::Invalid reference format for $CONTRACT"
    SUMMARY="${SUMMARY}| \`${CONTRACT}\` | (invalid reference) | **FAIL** |"$'\n'
    FAILED=$((FAILED + 1))
  fi

  echo "::endgroup::"
done < <(jq -c '.contracts[]' "$UPGRADES_CONFIG")

# Clean up worktree
if [[ -n "$BASE_DIR" ]]; then
  git worktree remove "$BASE_DIR" --force 2>/dev/null || true
fi

# Write Step Summary
{
  echo "## Upgrade Safety Validation"
  echo ""
  echo "| Contract | Reference | Result |"
  echo "|----------|-----------|--------|"
  echo -n "$SUMMARY"
  echo ""
  echo "**${PASSED} passed, ${FAILED} failed**"
} >> "$GITHUB_STEP_SUMMARY"

if [[ "$FAILED" -gt 0 ]]; then
  echo "::error::${FAILED} contract(s) failed upgrade safety validation"
  exit 1
fi

echo "All contracts passed upgrade safety validation"
