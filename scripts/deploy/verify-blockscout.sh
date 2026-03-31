#!/usr/bin/env bash
set -euo pipefail
# Verify deployed contracts on Blockscout using a 2-phase approach:
# Phase 1: Submit all contracts for verification
# Phase 2: Poll Blockscout API for verification status with retries
#
# Env inputs:
#   BLOCKSCOUT_URL  — required
#   BROADCAST_FILE  — required, path to run-latest.json
#   MAX_CHECKS      — optional, default 10
#   CHECK_DELAY     — optional, default 30 (seconds between checks)
#   INITIAL_WAIT    — optional, default 60 (seconds to wait after submission)

: "${BLOCKSCOUT_URL:?BLOCKSCOUT_URL is required}"
: "${BROADCAST_FILE:?BROADCAST_FILE is required}"
MAX_CHECKS="${MAX_CHECKS:-10}"
CHECK_DELAY="${CHECK_DELAY:-30}"
INITIAL_WAIT="${INITIAL_WAIT:-60}"

# Validate Blockscout URL format
if [[ -z "$BLOCKSCOUT_URL" || "$BLOCKSCOUT_URL" == "null" ]]; then
  echo "::error::BLOCKSCOUT_URL is empty or not configured. Check deploy-networks.json."
  exit 1
fi
if [[ ! "$BLOCKSCOUT_URL" =~ ^https?:// ]]; then
  echo "::error::BLOCKSCOUT_URL has invalid format (got: '$BLOCKSCOUT_URL'). Must start with http:// or https://."
  exit 1
fi

# Collect all CREATE contracts
CONTRACTS=()
while read -r tx; do
  name=$(echo "$tx" | jq -r '.contractName')
  addr=$(echo "$tx" | jq -r '.contractAddress')
  CONTRACTS+=("${name}:${addr}")
done < <(jq -c '.transactions[] | select(.transactionType == "CREATE")' "$BROADCAST_FILE")

echo "Found ${#CONTRACTS[@]} contracts to verify"

# Phase 1: Submit all contracts for verification (no --watch)
for entry in "${CONTRACTS[@]}"; do
  CONTRACT_NAME="${entry%%:*}"
  CONTRACT_ADDR="${entry#*:}"
  echo "Submitting $CONTRACT_NAME ($CONTRACT_ADDR) for verification..."
  SUBMIT_OUTPUT=$(forge verify-contract "$CONTRACT_ADDR" "$CONTRACT_NAME" \
    --verifier blockscout \
    --verifier-url "${BLOCKSCOUT_URL}/api" \
    --guess-constructor-args 2>&1) || true
  echo "$SUBMIT_OUTPUT"
  if echo "$SUBMIT_OUTPUT" | grep -qi "already verified"; then
    echo "  -> already verified"
  fi
done

# Phase 2: Wait for Blockscout to process the verification queue
echo "Waiting ${INITIAL_WAIT}s for Blockscout to process submissions..."
sleep "$INITIAL_WAIT"

# Phase 3: Check verification status via API, retry unverified contracts
VERIFY_FAILED=0

for entry in "${CONTRACTS[@]}"; do
  CONTRACT_NAME="${entry%%:*}"
  CONTRACT_ADDR="${entry#*:}"

  VERIFIED=0
  for check in $(seq 1 "$MAX_CHECKS"); do
    # Query Blockscout API for verification status
    API_RESULT=$(curl -sf --connect-timeout 10 --max-time 30 "${BLOCKSCOUT_URL%/}/api?module=contract&action=getabi&address=${CONTRACT_ADDR}" 2>/dev/null) || true
    API_STATUS=$(echo "$API_RESULT" | jq -r '.status // "0"' 2>/dev/null) || API_STATUS="0"

    if [[ "$API_STATUS" == "1" ]]; then
      echo "Verified: $CONTRACT_NAME ($CONTRACT_ADDR)"
      VERIFIED=1
      break
    fi

    if [[ $check -lt $MAX_CHECKS ]]; then
      echo "  $CONTRACT_NAME not yet verified (check $check/$MAX_CHECKS), resubmitting and waiting ${CHECK_DELAY}s..."
      # Resubmit to ensure it's in the queue
      forge verify-contract "$CONTRACT_ADDR" "$CONTRACT_NAME" \
        --verifier blockscout \
        --verifier-url "${BLOCKSCOUT_URL}/api" \
        --guess-constructor-args 2>&1 || true
      sleep "$CHECK_DELAY"
    fi
  done

  if [[ $VERIFIED -eq 0 ]]; then
    echo "::error::Verification failed for $CONTRACT_NAME ($CONTRACT_ADDR) after $MAX_CHECKS checks"
    VERIFY_FAILED=1
  fi
done

if [[ $VERIFY_FAILED -eq 1 ]]; then
  echo "::error::One or more contracts failed verification"
  exit 1
fi

echo "All contracts verified successfully"
