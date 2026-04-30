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

  cp "$SCRIPT_DIR/tests/fixtures/coverage.lcov" lcov.info

  export GITHUB_OUTPUT="$TMPDIR/github-output.txt"
  export COVERAGE_SOURCE_PREFIX="src/"
  touch "$GITHUB_OUTPUT"

  bash "$SCRIPT_DIR/scripts/coverage/extract-summary.sh"

  grep -q "lines_pct=" "$GITHUB_OUTPUT" || { echo "FAIL: lines_pct not in output"; exit 1; }
  grep -q "stmts_pct=" "$GITHUB_OUTPUT" || { echo "FAIL: stmts_pct not in output (back-compat)"; exit 1; }
  grep -q "branch_pct=" "$GITHUB_OUTPUT" || { echo "FAIL: branch_pct not in output"; exit 1; }
  grep -q "funcs_pct=" "$GITHUB_OUTPUT" || { echo "FAIL: funcs_pct not in output"; exit 1; }

  # src-only totals: 11/15 lines = 73.33% (test/ excluded)
  LINES_PCT=$(grep "^lines_pct=" "$GITHUB_OUTPUT" | cut -d= -f2)
  if (( $(echo "$LINES_PCT > 80" | bc -l) )); then
    echo "FAIL: lines_pct=$LINES_PCT, test files likely included"
    exit 1
  fi
  if (( $(echo "$LINES_PCT < 70" | bc -l) )); then
    echo "FAIL: lines_pct=$LINES_PCT below expected ~73.33%"
    exit 1
  fi

  # stmts_pct must equal lines_pct (back-compat alias)
  STMTS_PCT=$(grep "^stmts_pct=" "$GITHUB_OUTPUT" | cut -d= -f2)
  [[ "$STMTS_PCT" == "$LINES_PCT" ]] || { echo "FAIL: stmts_pct ($STMTS_PCT) should equal lines_pct ($LINES_PCT)"; exit 1; }

  echo "PASS: extracts correct src-only percentages"
) || { FAILURES=$((FAILURES + 1)); }

# Test 2: Generates coverage-comment.md
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cd "$TMPDIR"

  cp "$SCRIPT_DIR/tests/fixtures/coverage.lcov" lcov.info

  export GITHUB_OUTPUT="$TMPDIR/github-output.txt"
  export COVERAGE_SOURCE_PREFIX="src/"
  touch "$GITHUB_OUTPUT"

  bash "$SCRIPT_DIR/scripts/coverage/extract-summary.sh"

  [[ -f coverage-comment.md ]] || { echo "FAIL: coverage-comment.md not created"; exit 1; }
  grep -q "Coverage Report" coverage-comment.md || { echo "FAIL: no title in comment"; exit 1; }
  grep -q "Lines" coverage-comment.md || { echo "FAIL: no Lines metric"; exit 1; }
  grep -q "MyToken" coverage-comment.md || { echo "FAIL: no per-file breakdown"; exit 1; }
  grep -q "MyToken.t.sol" coverage-comment.md && { echo "FAIL: test file leaked into comment"; exit 1; } || true

  echo "PASS: generates coverage-comment.md"
) || { FAILURES=$((FAILURES + 1)); }

# Test 3: Custom prefix excludes everything when nothing matches
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cd "$TMPDIR"

  cp "$SCRIPT_DIR/tests/fixtures/coverage.lcov" lcov.info

  export GITHUB_OUTPUT="$TMPDIR/github-output.txt"
  export COVERAGE_SOURCE_PREFIX="nomatch/"
  touch "$GITHUB_OUTPUT"

  bash "$SCRIPT_DIR/scripts/coverage/extract-summary.sh"

  # 0/0 should report 100.00%
  LINES_PCT=$(grep "^lines_pct=" "$GITHUB_OUTPUT" | cut -d= -f2)
  [[ "$LINES_PCT" == "100.00" ]] || { echo "FAIL: empty filter should yield 100.00, got $LINES_PCT"; exit 1; }

  echo "PASS: empty filter handled"
) || { FAILURES=$((FAILURES + 1)); }

# Test 4: Missing lcov file fails fast
(
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cd "$TMPDIR"

  export GITHUB_OUTPUT="$TMPDIR/github-output.txt"
  touch "$GITHUB_OUTPUT"

  if bash "$SCRIPT_DIR/scripts/coverage/extract-summary.sh" 2>/dev/null; then
    echo "FAIL: should have errored on missing lcov"
    exit 1
  fi

  echo "PASS: missing lcov file fails"
) || { FAILURES=$((FAILURES + 1)); }

echo "--- $((4 - FAILURES))/4 tests passed ---"
exit $FAILURES
