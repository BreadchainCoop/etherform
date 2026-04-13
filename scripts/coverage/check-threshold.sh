#!/usr/bin/env bash
set -euo pipefail
# Check coverage percentages against a minimum threshold.
# Exits with code 1 if any metric falls below the threshold.
#
# Env inputs:
#   THRESHOLD  — required, minimum coverage percentage
#   LINES_PCT  — required
#   STMTS_PCT  — required
#   BRANCH_PCT — required
#   FUNCS_PCT  — required

: "${THRESHOLD:?THRESHOLD is required}"
: "${LINES_PCT:?LINES_PCT is required}"
: "${STMTS_PCT:?STMTS_PCT is required}"
: "${BRANCH_PCT:?BRANCH_PCT is required}"
: "${FUNCS_PCT:?FUNCS_PCT is required}"

FAILED=0
for metric in "Lines:$LINES_PCT" \
              "Statements:$STMTS_PCT" \
              "Branches:$BRANCH_PCT" \
              "Functions:$FUNCS_PCT"; do
  NAME="${metric%%:*}"
  VALUE="${metric#*:}"
  if (( $(echo "$VALUE < $THRESHOLD" | bc -l) )); then
    echo "::error::$NAME coverage ($VALUE%) is below threshold ($THRESHOLD%)"
    FAILED=1
  fi
done

if [[ $FAILED -eq 1 ]]; then
  exit 1
fi

echo "All coverage metrics meet the $THRESHOLD% threshold"
