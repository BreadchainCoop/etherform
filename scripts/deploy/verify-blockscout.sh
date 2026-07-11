#!/usr/bin/env bash
set -euo pipefail
# Verify deployed contracts on Blockscout using a 2-phase approach:
# Phase 1: Submit all contracts for verification
# Phase 2: Poll Blockscout API for verification status with retries
#
# Constructor args are derived offline from the broadcast file (creation tx
# input minus the compiled creation bytecode), so no RPC access is needed —
# `--guess-constructor-args` hard-fails without one, which silently broke
# every submission for callers that don't export ETH_RPC_URL.
#
# Env inputs:
#   BLOCKSCOUT_URL  — required
#   BROADCAST_FILE  — required, path to run-latest.json
#   MAX_CHECKS      — optional, default 10 (status-poll rounds across ALL contracts)
#   CHECK_DELAY     — optional, default 30 (seconds between poll rounds)
#   INITIAL_WAIT    — optional, default 60 (seconds to wait after submission)
#
# Worst-case runtime is bounded by INITIAL_WAIT + MAX_CHECKS * CHECK_DELAY
# (plus submission time), independent of the number of contracts.

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

# Normalize URL once (strip trailing slash) to avoid double-slash in API calls
BLOCKSCOUT_URL="${BLOCKSCOUT_URL%/}"

# Some Blockscout deployments 301 to a canonical host (e.g.
# optimism.blockscout.com → explorer.optimism.io). forge's verification POSTs
# don't survive that redirect (re-issued as GET, dropping the payload), so
# resolve the final host up front and use it everywhere.
EFFECTIVE_URL=$(curl -sL -o /dev/null -w '%{url_effective}' --connect-timeout 10 --max-time 30 "${BLOCKSCOUT_URL}/api?module=stats&action=ethsupply" 2>/dev/null) || EFFECTIVE_URL=""
if [[ "$EFFECTIVE_URL" =~ ^(https?://[^/]+) ]]; then
  EFFECTIVE_HOST="${BASH_REMATCH[1]}"
  if [[ "$EFFECTIVE_HOST" != "$BLOCKSCOUT_URL" ]]; then
    echo "Blockscout redirects to ${EFFECTIVE_HOST} — using it for verification"
    BLOCKSCOUT_URL="$EFFECTIVE_HOST"
  fi
fi

# Collect all named CREATE/CREATE2 contracts. Nested deployments
# (additionalContracts) have no contract name in the broadcast artifact and
# cannot be verified by name — parse-broadcast.sh warns about them.
CONTRACTS=()
while read -r tx; do
  name=$(echo "$tx" | jq -r '.contractName')
  addr=$(echo "$tx" | jq -r '.contractAddress')
  CONTRACTS+=("${name}:${addr}")
done < <(jq -c '.transactions[]
  | select(.transactionType == "CREATE" or .transactionType == "CREATE2")
  | select(.contractName != null)' "$BROADCAST_FILE")

echo "Found ${#CONTRACTS[@]} contracts to verify"

if [[ ${#CONTRACTS[@]} -eq 0 ]]; then
  echo "::warning::No named CREATE/CREATE2 deployments found in $BROADCAST_FILE — nothing to verify"
  exit 0
fi

# Phase 1: Submit all contracts for verification (no --watch)
for entry in "${CONTRACTS[@]}"; do
  CONTRACT_NAME="${entry%%:*}"
  CONTRACT_ADDR="${entry#*:}"

  # Constructor args = creation tx input minus the compiled creation bytecode
  # (same build, so the artifact is an exact prefix). If the prefix doesn't
  # match (e.g. library placeholders), omit the flag — Blockscout can extract
  # the args from the creation tx on its own.
  ARGS_FLAG=()
  TX_INPUT=$(jq -r --arg addr "$CONTRACT_ADDR" '[.transactions[]
    | select(.contractAddress == $addr)
    | .transaction.input][0] // ""' "$BROADCAST_FILE")
  CREATION_CODE=$(forge inspect "$CONTRACT_NAME" bytecode 2>/dev/null) || CREATION_CODE=""
  if [[ -n "$CREATION_CODE" && "$TX_INPUT" == "$CREATION_CODE"* && "$TX_INPUT" != "$CREATION_CODE" ]]; then
    ARGS_FLAG=(--constructor-args "0x${TX_INPUT#"$CREATION_CODE"}")
  fi

  # A bare contract name carries no compiler version — read it from the build
  # artifact, or forge errors with "Compiler version has to be set".
  VERSION_FLAG=()
  COMPILER_VERSION=$(forge inspect "$CONTRACT_NAME" metadata 2>/dev/null | jq -r '.compiler.version // ""') || COMPILER_VERSION=""
  if [[ -n "$COMPILER_VERSION" ]]; then
    VERSION_FLAG=(--compiler-version "$COMPILER_VERSION")
  fi

  echo "Submitting $CONTRACT_NAME ($CONTRACT_ADDR) for verification..."
  SUBMIT_OUTPUT=$(forge verify-contract "$CONTRACT_ADDR" "$CONTRACT_NAME" \
    --verifier blockscout \
    --verifier-url "${BLOCKSCOUT_URL}/api" \
    "${VERSION_FLAG[@]}" \
    "${ARGS_FLAG[@]}" 2>&1) || true
  # Some Blockscout instances echo the full standard-json back — truncate to
  # keep logs readable.
  echo "${SUBMIT_OUTPUT:0:400}"
  if echo "$SUBMIT_OUTPUT" | grep -qi "already verified"; then
    echo "  -> already verified"
  fi
done

# Phase 2: Wait for Blockscout to process the verification queue
echo "Waiting ${INITIAL_WAIT}s for Blockscout to process submissions..."
sleep "$INITIAL_WAIT"

# Phase 3: Poll verification status via API in rounds across ALL pending
# contracts (a per-contract retry loop would take up to
# MAX_CHECKS * CHECK_DELAY seconds PER CONTRACT and blow any step timeout).
PENDING=("${CONTRACTS[@]}")

for check in $(seq 1 "$MAX_CHECKS"); do
  STILL_PENDING=()
  for entry in "${PENDING[@]}"; do
    CONTRACT_NAME="${entry%%:*}"
    CONTRACT_ADDR="${entry#*:}"

    # Query Blockscout API for verification status. -L: some instances 301 to
    # a canonical host (e.g. optimism.blockscout.com → explorer.optimism.io).
    API_RESULT=$(curl -sfL --connect-timeout 10 --max-time 30 "${BLOCKSCOUT_URL}/api?module=contract&action=getabi&address=${CONTRACT_ADDR}" 2>/dev/null) || true
    API_STATUS=$(echo "$API_RESULT" | jq -r '.status // "0"' 2>/dev/null) || API_STATUS="0"

    if [[ "$API_STATUS" == "1" ]]; then
      echo "Verified: $CONTRACT_NAME ($CONTRACT_ADDR)"
    else
      STILL_PENDING+=("$entry")
    fi
  done

  PENDING=()
  if [[ ${#STILL_PENDING[@]} -gt 0 ]]; then
    PENDING=("${STILL_PENDING[@]}")
  fi

  if [[ ${#PENDING[@]} -eq 0 ]]; then
    break
  fi
  if [[ $check -lt $MAX_CHECKS ]]; then
    echo "  ${#PENDING[@]} contract(s) not yet verified (check $check/$MAX_CHECKS), waiting ${CHECK_DELAY}s..."
    sleep "$CHECK_DELAY"
  fi
done

if [[ ${#PENDING[@]} -gt 0 ]]; then
  for entry in "${PENDING[@]}"; do
    echo "::error::Verification failed for ${entry%%:*} (${entry#*:}) after $MAX_CHECKS checks"
  done
  echo "::error::One or more contracts failed verification"
  exit 1
fi

echo "All contracts verified successfully"
