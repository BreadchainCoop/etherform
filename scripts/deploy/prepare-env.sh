#!/usr/bin/env bash
# Prepare deployment environment variables.
# Must be SOURCED (not executed) — modifies the caller's environment.
#
# Env inputs:
#   PRIVATE_KEY      — optional, adds 0x prefix if missing
#   DEPLOY_ENV_VARS  — optional, newline-separated KEY=VALUE pairs (# comments and blanks skipped)

if [[ -n "${PRIVATE_KEY:-}" && "$PRIVATE_KEY" != 0x* ]]; then
  export PRIVATE_KEY="0x$PRIVATE_KEY"
fi

if [[ -n "${DEPLOY_ENV_VARS:-}" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    export "${line?}"
  done <<< "$DEPLOY_ENV_VARS"
fi
