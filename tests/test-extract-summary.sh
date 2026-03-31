#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0

echo "=== Testing scripts/coverage/extract-summary.sh ==="

# Test 1: Extracts coverage percentages for src/ files only
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cd "$TMPDIR"

  cp "$SCRIPT_DIR/tests/fixtures/coverage-raw.txt" .

  export GITHUB_OUTPUT="$TMPDIR/github-output.txt"
  export COVERAGE_SOURCE_FILTER=" src/"
  touch "$GITHUB_OUTPUT"

  bash "$SCRIPT_DIR/scripts/coverage/extract-summary.sh"

  grep -q "lines_pct=" "$GITHUB_OUTPUT" || { echo "FAIL: lines_pct not in output"; exit 1; }
  grep -q "stmts_pct=" "$GITHUB_OUTPUT" || { echo "FAIL: stmts_pct not in output"; exit 1; }
  grep -q "branch_pct=" "$GITHUB_OUTPUT" || { echo "FAIL: branch_pct not in output"; exit 1; }
  grep -q "funcs_pct=" "$GITHUB_OUTPUT" || { echo "FAIL: funcs_pct not in output"; exit 1; }

  # Verify test/ files are excluded (11/15 = 73.33, not 100)
  LINES_PCT=$(grep "lines_pct=" "$GITHUB_OUTPUT" | cut -d= -f2)
  if (( $(echo "$LINES_PCT > 80" | bc -l) )); then
    echo "FAIL: lines_pct=$LINES_PCT, test files likely included"
    exit 1
  fi

  echo "PASS: extracts correct src-only percentages"
) || { FAILURES=$((FAILURES + 1)); }

# Test 2: Generates coverage-comment.md
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cd "$TMPDIR"

  cp "$SCRIPT_DIR/tests/fixtures/coverage-raw.txt" .

  export GITHUB_OUTPUT="$TMPDIR/github-output.txt"
  export COVERAGE_SOURCE_FILTER=" src/"
  touch "$GITHUB_OUTPUT"

  bash "$SCRIPT_DIR/scripts/coverage/extract-summary.sh"

  [[ -f coverage-comment.md ]] || { echo "FAIL: coverage-comment.md not created"; exit 1; }
  grep -q "Coverage Report" coverage-comment.md || { echo "FAIL: no title in comment"; exit 1; }
  grep -q "Lines" coverage-comment.md || { echo "FAIL: no Lines metric"; exit 1; }
  grep -q "MyToken" coverage-comment.md || { echo "FAIL: no per-file breakdown"; exit 1; }

  echo "PASS: generates coverage-comment.md"
) || { FAILURES=$((FAILURES + 1)); }

echo "--- $((2 - FAILURES))/2 tests passed ---"
exit $FAILURES
