#!/usr/bin/env bash
set -euo pipefail
# Parse forge coverage output into summary percentages and a markdown comment.
#
# Env inputs:
#   COVERAGE_SOURCE_FILTER — optional, grep filter for source files (default: ' src/')
#
# File inputs:
#   coverage-raw.txt must exist in the working directory
#
# Outputs (via $GITHUB_OUTPUT):
#   lines_pct, stmts_pct, branch_pct, funcs_pct
#
# Side effects:
#   Creates coverage-comment.md in the working directory

COVERAGE_SOURCE_FILTER="${COVERAGE_SOURCE_FILTER:- src/}"

# Extract the final summary table (box-drawing characters)
awk '/^╭/,/^╰/' coverage-raw.txt > coverage-table.txt

# Filter to only source files and compute totals from raw counts
grep '^|' coverage-table.txt | grep "$COVERAGE_SOURCE_FILTER" > src-rows.txt || true

# Sum up hit/total for each metric across source files
total_lines_hit=0; total_lines_all=0
total_stmts_hit=0; total_stmts_all=0
total_branch_hit=0; total_branch_all=0
total_funcs_hit=0; total_funcs_all=0

while IFS='|' read -r _ file lines stmts branches funcs _; do
  extract() { echo "$1" | grep -oP '\(\K[0-9]+/[0-9]+' | tr '/' ' '; }
  read -r lh lt <<< "$(extract "$lines")"
  read -r sh st <<< "$(extract "$stmts")"
  read -r bh bt <<< "$(extract "$branches")"
  read -r fh ft <<< "$(extract "$funcs")"
  total_lines_hit=$((total_lines_hit + lh)); total_lines_all=$((total_lines_all + lt))
  total_stmts_hit=$((total_stmts_hit + sh)); total_stmts_all=$((total_stmts_all + st))
  total_branch_hit=$((total_branch_hit + bh)); total_branch_all=$((total_branch_all + bt))
  total_funcs_hit=$((total_funcs_hit + fh)); total_funcs_all=$((total_funcs_all + ft))
done < src-rows.txt

pct() { [ "$2" -eq 0 ] && echo "100.00% (0/0)" || printf "%.2f%% (%d/%d)" "$(echo "scale=4; $1 * 100 / $2" | bc)" "$1" "$2"; }

# Compute numeric percentages for threshold checking
num_pct() { if [ "$2" -eq 0 ]; then echo "100.00"; else echo "scale=2; $1 * 100 / $2" | bc; fi; }
{
  echo "lines_pct=$(num_pct $total_lines_hit $total_lines_all)"
  echo "stmts_pct=$(num_pct $total_stmts_hit $total_stmts_all)"
  echo "branch_pct=$(num_pct $total_branch_hit $total_branch_all)"
  echo "funcs_pct=$(num_pct $total_funcs_hit $total_funcs_all)"
} >> "$GITHUB_OUTPUT"

# Build the markdown comment
{
  echo "## Coverage Report"
  echo ""
  echo "| Metric | Coverage |"
  echo "|--------|----------|"
  echo "| Lines | $(pct $total_lines_hit $total_lines_all) |"
  echo "| Statements | $(pct $total_stmts_hit $total_stmts_all) |"
  echo "| Branches | $(pct $total_branch_hit $total_branch_all) |"
  echo "| Functions | $(pct $total_funcs_hit $total_funcs_all) |"
  echo ""
  echo "<details><summary>Coverage by file</summary>"
  echo ""
  echo "| File | Lines | Statements | Branches | Functions |"
  echo "|------|-------|------------|----------|-----------|"
  while IFS='|' read -r _ file lines stmts branches funcs _; do
    file=$(echo "$file" | xargs)
    lines=$(echo "$lines" | xargs)
    stmts=$(echo "$stmts" | xargs)
    branches=$(echo "$branches" | xargs)
    funcs=$(echo "$funcs" | xargs)
    echo "| \`$file\` | $lines | $stmts | $branches | $funcs |"
  done < src-rows.txt
  echo ""
  echo "</details>"
} > coverage-comment.md
