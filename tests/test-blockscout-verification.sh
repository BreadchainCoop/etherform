#!/usr/bin/env bash
# Test Blockscout verification output parsing logic
set -euo pipefail

ERRORS=0

check_verification_output() {
  local output="$1"
  local expected="$2"  # "pass" or "fail"
  local desc="$3"

  local result="fail"
  if echo "$output" | grep -qiE "Contract successfully verified|Pass - Verified"; then
    result="pass"
  elif echo "$output" | grep -qi "Already Verified"; then
    result="pass"
  fi

  if [[ "$result" != "$expected" ]]; then
    echo "  FAIL: $desc (expected=$expected, got=$result)"
    ((ERRORS++))
  fi
}

# Test: False positive — Blockscout returns "Fail - Unable to verify" but exit code 0
check_verification_output \
  "Contract verification status:\nResponse: \`OK\`\nDetails: \`Fail - Unable to verify\`" \
  "fail" \
  "False positive: 'Fail - Unable to verify' should not pass"

# Test: Real success
check_verification_output \
  "Contract successfully verified" \
  "pass" \
  "Real success should pass"

# Test: Already verified
check_verification_output \
  "Contract source code already verified" \
  "pass" \
  "Already Verified should pass"

# Test: Pass - Verified
check_verification_output \
  "Response: \`OK\`\nDetails: \`Pass - Verified\`" \
  "pass" \
  "Pass - Verified should pass"

# Test: Network error
check_verification_output \
  "Error: connection refused" \
  "fail" \
  "Network error should fail"

# Test: Empty output
check_verification_output \
  "" \
  "fail" \
  "Empty output should fail"

# Test URL validation
validate_url() {
  local url="$1"
  echo "$url" | grep -qE '^https?://[a-zA-Z0-9.-]+'
}

if validate_url "https://eth-sepolia.blockscout.com"; then
  true
else
  echo "  FAIL: Valid URL rejected"
  ((ERRORS++))
fi

if validate_url "not-a-url"; then
  echo "  FAIL: Invalid URL accepted"
  ((ERRORS++))
fi

if validate_url ""; then
  echo "  FAIL: Empty URL accepted"
  ((ERRORS++))
fi

[[ $ERRORS -eq 0 ]]
