#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/scripts/release/create-release.sh"
FAILURES=0

echo "=== Testing scripts/release/create-release.sh ==="

# Helper: install a mock 'gh' on PATH that records its args and returns scripted exit codes.
# The mock is configured per-test via env vars:
#   MOCK_GH_VIEW_EXIT     — exit code for `gh release view` (default 1)
#   MOCK_GH_VIEW_OUTPUT   — stdout/stderr text for `gh release view` (default "release not found")
#   MOCK_GH_DELETE_EXIT   — exit code for `gh release delete` (default 0)
#   MOCK_GH_CREATE_EXIT   — exit code for `gh release create` (default 0)
# The mock writes one line per invocation to $MOCK_GH_LOG, e.g. "view testnet-pr-42".
install_mock_gh() {
  local bindir="$1"
  cat > "$bindir/gh" <<'MOCK_EOF'
#!/usr/bin/env bash
# Mock gh CLI for create-release.sh tests.
LOG="${MOCK_GH_LOG:-/dev/null}"
echo "$*" >> "$LOG"

if [[ "$1" == "release" && "$2" == "view" ]]; then
  echo "${MOCK_GH_VIEW_OUTPUT:-release not found}"
  exit "${MOCK_GH_VIEW_EXIT:-1}"
elif [[ "$1" == "release" && "$2" == "delete" ]]; then
  exit "${MOCK_GH_DELETE_EXIT:-0}"
elif [[ "$1" == "release" && "$2" == "create" ]]; then
  exit "${MOCK_GH_CREATE_EXIT:-0}"
fi

echo "mock gh: unhandled args: $*" >&2
exit 99
MOCK_EOF
  chmod +x "$bindir/gh"
}

setup_test() {
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  BIN="$TMPDIR/bin"
  mkdir -p "$BIN"
  install_mock_gh "$BIN"
  export PATH="$BIN:$PATH"
  export MOCK_GH_LOG="$TMPDIR/gh.log"
  : > "$MOCK_GH_LOG"

  echo "release body" > "$TMPDIR/body.md"
  export REPO="owner/repo"
  export TAG="testnet-pr-42"
  export TITLE="Testnet — PR #42"
  export BODY_FILE="$TMPDIR/body.md"
  export TARGET_SHA="abcdef1234567890abcdef1234567890abcdef12"
  export GITHUB_STEP_SUMMARY="$TMPDIR/summary.md"
  : > "$GITHUB_STEP_SUMMARY"
}

# Test 1: Tag does not exist — creates release directly
(
  setup_test
  export COLLISION_POLICY="replace"
  export MOCK_GH_VIEW_EXIT=1
  export MOCK_GH_VIEW_OUTPUT="release not found"

  bash "$SCRIPT" > /dev/null

  grep -q "^release view " "$MOCK_GH_LOG" || { echo "FAIL: did not call gh release view"; exit 1; }
  if grep -q "^release delete " "$MOCK_GH_LOG"; then
    echo "FAIL: should not have deleted when release does not exist"
    exit 1
  fi
  grep -q "^release create " "$MOCK_GH_LOG" || { echo "FAIL: did not call gh release create"; exit 1; }
  grep -q "Created \[\`testnet-pr-42\`\]" "$GITHUB_STEP_SUMMARY" || { echo "FAIL: step summary missing"; exit 1; }
  echo "PASS: creates release when tag is free"
) || { FAILURES=$((FAILURES + 1)); }

# Test 2: Tag exists + replace policy — deletes then creates
(
  setup_test
  export COLLISION_POLICY="replace"
  export MOCK_GH_VIEW_EXIT=0

  bash "$SCRIPT" > /dev/null

  grep -q "^release delete testnet-pr-42 --cleanup-tag --yes" "$MOCK_GH_LOG" \
    || { echo "FAIL: did not call gh release delete with cleanup-tag"; cat "$MOCK_GH_LOG"; exit 1; }
  grep -q "^release create " "$MOCK_GH_LOG" || { echo "FAIL: did not call gh release create"; exit 1; }
  echo "PASS: replace policy deletes then creates"
) || { FAILURES=$((FAILURES + 1)); }

# Test 3: Tag exists + skip policy — exits 0 without delete or create
(
  setup_test
  export COLLISION_POLICY="skip"
  export MOCK_GH_VIEW_EXIT=0

  bash "$SCRIPT" > /dev/null

  if grep -q "^release delete " "$MOCK_GH_LOG"; then
    echo "FAIL: should not have deleted on skip"
    exit 1
  fi
  if grep -q "^release create " "$MOCK_GH_LOG"; then
    echo "FAIL: should not have created on skip"
    exit 1
  fi
  grep -q "skipped per" "$GITHUB_STEP_SUMMARY" || { echo "FAIL: step summary missing skip note"; exit 1; }
  echo "PASS: skip policy exits cleanly"
) || { FAILURES=$((FAILURES + 1)); }

# Test 4: Tag exists + fail policy — exits non-zero
(
  setup_test
  export COLLISION_POLICY="fail"
  export MOCK_GH_VIEW_EXIT=0

  if bash "$SCRIPT" > /dev/null 2>&1; then
    echo "FAIL: should have exited non-zero on fail policy"
    exit 1
  fi
  if grep -q "^release create " "$MOCK_GH_LOG"; then
    echo "FAIL: should not have created on fail"
    exit 1
  fi
  echo "PASS: fail policy exits non-zero"
) || { FAILURES=$((FAILURES + 1)); }

# Test 5: gh release view fails for a reason other than "not found" — surface error, do not create
(
  setup_test
  export COLLISION_POLICY="replace"
  export MOCK_GH_VIEW_EXIT=1
  export MOCK_GH_VIEW_OUTPUT="HTTP 401: Bad credentials"

  if bash "$SCRIPT" > /dev/null 2>&1; then
    echo "FAIL: should have exited non-zero on auth error"
    exit 1
  fi
  if grep -q "^release create " "$MOCK_GH_LOG"; then
    echo "FAIL: must not create release after view error"
    exit 1
  fi
  echo "PASS: surfaces non-not-found view error"
) || { FAILURES=$((FAILURES + 1)); }

# Test 6: Invalid collision policy fails fast
(
  setup_test
  export COLLISION_POLICY="bogus"

  if bash "$SCRIPT" > /dev/null 2>&1; then
    echo "FAIL: should have rejected invalid policy"
    exit 1
  fi
  if [[ -s "$MOCK_GH_LOG" ]]; then
    echo "FAIL: should not have called gh on invalid policy"
    cat "$MOCK_GH_LOG"
    exit 1
  fi
  echo "PASS: rejects invalid collision policy"
) || { FAILURES=$((FAILURES + 1)); }

# Test 7: Missing BODY_FILE fails fast
(
  setup_test
  export COLLISION_POLICY="replace"
  export BODY_FILE="$TMPDIR/does-not-exist.md"

  if bash "$SCRIPT" > /dev/null 2>&1; then
    echo "FAIL: should have failed on missing body file"
    exit 1
  fi
  echo "PASS: fails on missing body file"
) || { FAILURES=$((FAILURES + 1)); }

# Test 8: Missing required env var fails fast
(
  setup_test
  export COLLISION_POLICY="replace"
  unset TAG

  if bash "$SCRIPT" > /dev/null 2>&1; then
    echo "FAIL: should have failed on missing TAG"
    exit 1
  fi
  echo "PASS: fails on missing TAG"
) || { FAILURES=$((FAILURES + 1)); }

TOTAL=8
echo "--- $((TOTAL - FAILURES))/$TOTAL tests passed ---"
exit $FAILURES
