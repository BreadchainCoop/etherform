#!/usr/bin/env bash
set -euo pipefail
# Parse forge coverage lcov output into summary percentages and a markdown comment.
#
# Env inputs:
#   COVERAGE_SOURCE_PREFIX — optional, path prefix to include (default: 'src/')
#   COVERAGE_LCOV_FILE     — optional, default 'lcov.info'
#
# Outputs (via $GITHUB_OUTPUT):
#   lines_pct, stmts_pct, branch_pct, funcs_pct
#   stmts_pct is set equal to lines_pct — lcov has no separate statements metric.
#
# Side effects:
#   Creates coverage-comment.md in the working directory.

COVERAGE_SOURCE_PREFIX="${COVERAGE_SOURCE_PREFIX:-src/}"
LCOV_FILE="${COVERAGE_LCOV_FILE:-lcov.info}"

if [[ ! -f "$LCOV_FILE" ]]; then
  echo "::error::lcov file not found at $LCOV_FILE"
  exit 1
fi

# Parse lcov into a totals file (1 line) and a per-file table.
awk -v prefix="$COVERAGE_SOURCE_PREFIX" '
  function reset() { sf=""; lh=0; lf=0; brh=0; brf=0; fnh=0; fnf=0; include=0 }
  BEGIN { reset(); TLH=TLF=TBRH=TBRF=TFNH=TFNF=0 }
  /^SF:/  { sf  = substr($0,4); include = (index(sf, prefix) == 1); next }
  /^LH:/  { lh  = substr($0,4) + 0; next }
  /^LF:/  { lf  = substr($0,4) + 0; next }
  /^BRH:/ { brh = substr($0,5) + 0; next }
  /^BRF:/ { brf = substr($0,5) + 0; next }
  /^FNH:/ { fnh = substr($0,5) + 0; next }
  /^FNF:/ { fnf = substr($0,5) + 0; next }
  /^end_of_record/ {
    if (include) {
      printf "%s\t%d\t%d\t%d\t%d\t%d\t%d\n", sf, lh, lf, brh, brf, fnh, fnf > "coverage-files.tsv"
      TLH+=lh; TLF+=lf; TBRH+=brh; TBRF+=brf; TFNH+=fnh; TFNF+=fnf
    }
    reset()
  }
  END {
    printf "%d\t%d\t%d\t%d\t%d\t%d\n", TLH, TLF, TBRH, TBRF, TFNH, TFNF > "coverage-totals.tsv"
  }
' "$LCOV_FILE"

[[ -f coverage-files.tsv ]] || : > coverage-files.tsv

read -r TLH TLF TBRH TBRF TFNH TFNF < coverage-totals.tsv

num_pct() { if [ "$2" -eq 0 ]; then echo "100.00"; else echo "scale=2; $1 * 100 / $2" | bc; fi; }
fmt_pct() { if [ "$2" -eq 0 ]; then echo "100.00% (0/0)"; else printf "%.2f%% (%d/%d)" "$(echo "scale=4; $1 * 100 / $2" | bc)" "$1" "$2"; fi; }

LINES_PCT=$(num_pct "$TLH" "$TLF")
BRANCH_PCT=$(num_pct "$TBRH" "$TBRF")
FUNCS_PCT=$(num_pct "$TFNH" "$TFNF")

{
  echo "lines_pct=$LINES_PCT"
  echo "stmts_pct=$LINES_PCT"
  echo "branch_pct=$BRANCH_PCT"
  echo "funcs_pct=$FUNCS_PCT"
} >> "$GITHUB_OUTPUT"

{
  echo "## Coverage Report"
  echo ""
  echo "| Metric | Coverage |"
  echo "|--------|----------|"
  echo "| Lines | $(fmt_pct "$TLH" "$TLF") |"
  echo "| Branches | $(fmt_pct "$TBRH" "$TBRF") |"
  echo "| Functions | $(fmt_pct "$TFNH" "$TFNF") |"
  echo ""
  echo "<details><summary>Coverage by file</summary>"
  echo ""
  echo "| File | Lines | Branches | Functions |"
  echo "|------|-------|----------|-----------|"
  while IFS=$'\t' read -r sf lh lf brh brf fnh fnf; do
    [[ -z "$sf" ]] && continue
    echo "| \`$sf\` | $(fmt_pct "$lh" "$lf") | $(fmt_pct "$brh" "$brf") | $(fmt_pct "$fnh" "$fnf") |"
  done < coverage-files.tsv
  echo ""
  echo "</details>"
} > coverage-comment.md
