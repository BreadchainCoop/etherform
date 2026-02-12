#!/usr/bin/env bash
# Test baseline detection logic used in upgrade safety
set -euo pipefail

ERRORS=0
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

check_baseline() {
  local baseline_path="$1"
  local fallback_path="$2"
  local expected="$3"  # "baseline", "fallback", or "skip"
  local desc="$4"

  local result="skip"
  if [ -d "$baseline_path" ] && ls "$baseline_path"/*.sol 1>/dev/null 2>&1; then
    result="baseline"
  elif [ -d "$fallback_path" ] && ls "$fallback_path"/*.sol 1>/dev/null 2>&1; then
    result="fallback"
  fi

  if [[ "$result" != "$expected" ]]; then
    echo "  FAIL: $desc (expected=$expected, got=$result)"
    ((ERRORS++))
  fi
}

# Setup test dirs
mkdir -p "$TMPDIR/baseline" "$TMPDIR/previous" "$TMPDIR/empty"
echo "// SPDX" > "$TMPDIR/baseline/Test.sol"
echo "// SPDX" > "$TMPDIR/previous/Test.sol"

check_baseline "$TMPDIR/baseline" "$TMPDIR/previous" "baseline" "Baseline exists"
check_baseline "$TMPDIR/nonexistent" "$TMPDIR/previous" "fallback" "Fallback when no baseline"
check_baseline "$TMPDIR/nonexistent" "$TMPDIR/nonexistent2" "skip" "Skip when neither exists"
check_baseline "$TMPDIR/empty" "$TMPDIR/previous" "fallback" "Fallback when baseline empty"

[[ $ERRORS -eq 0 ]]
