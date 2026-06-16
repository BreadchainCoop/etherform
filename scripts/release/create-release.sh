#!/usr/bin/env bash
set -euo pipefail
# Create a GitHub release, handling tag collisions per policy.
#
# Env inputs:
#   REPO              — required, owner/name (e.g. GITHUB_REPOSITORY)
#   TAG               — required, e.g. testnet-pr-42
#   TITLE             — required
#   BODY_FILE         — required, path to release notes markdown
#   TARGET_SHA        — required, commit the release tag should point at
#   COLLISION_POLICY  — required, one of: replace | skip | fail
#   GH_TOKEN          — required (consumed by gh CLI)

: "${REPO:?REPO is required}"
: "${TAG:?TAG is required}"
: "${TITLE:?TITLE is required}"
: "${BODY_FILE:?BODY_FILE is required}"
: "${TARGET_SHA:?TARGET_SHA is required}"
: "${COLLISION_POLICY:?COLLISION_POLICY is required}"

case "$COLLISION_POLICY" in
  replace|skip|fail) ;;
  *)
    echo "::error::Invalid COLLISION_POLICY: $COLLISION_POLICY (expected replace|skip|fail)"
    exit 1
    ;;
esac

if [[ ! -f "$BODY_FILE" ]]; then
  echo "::error::Body file not found: $BODY_FILE"
  exit 1
fi

# Probe whether the release already exists. Distinguish "not found" from auth/network errors
# so we don't silently treat a 401 as "tag is free."
EXISTS=0
if VIEW_OUTPUT=$(gh release view "$TAG" --repo "$REPO" 2>&1); then
  EXISTS=1
else
  if echo "$VIEW_OUTPUT" | grep -qi "release not found\|not found"; then
    EXISTS=0
  else
    echo "::error::Failed to query release '$TAG' on $REPO:"
    echo "$VIEW_OUTPUT"
    exit 1
  fi
fi

if [[ "$EXISTS" -eq 1 ]]; then
  case "$COLLISION_POLICY" in
    replace)
      echo "Release '$TAG' already exists — deleting per replace policy"
      gh release delete "$TAG" --cleanup-tag --yes --repo "$REPO"
      ;;
    skip)
      echo "Release '$TAG' already exists — skipping per skip policy"
      {
        echo "## Release"
        echo ""
        echo "> Release \`$TAG\` already exists; skipped per \`release-on-collision: skip\`."
      } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
      exit 0
      ;;
    fail)
      echo "::error::Release '$TAG' already exists and collision policy is 'fail'"
      exit 1
      ;;
  esac
fi

gh release create "$TAG" \
  --repo "$REPO" \
  --title "$TITLE" \
  --notes-file "$BODY_FILE" \
  --target "$TARGET_SHA"

RELEASE_URL="https://github.com/${REPO}/releases/tag/${TAG}"
{
  echo "## Release"
  echo ""
  echo "Created [\`${TAG}\`](${RELEASE_URL})."
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

echo "Created release $TAG at $RELEASE_URL"
