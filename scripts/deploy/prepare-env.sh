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

    # Expect KEY=VALUE; fail on malformed lines
    if [[ "$line" != *=* ]]; then
      echo "::error::Malformed DEPLOY_ENV_VARS line (no '='): $line"
      return 1 2>/dev/null || exit 1
    fi

    key=${line%%=*}
    value=${line#*=}

    # Validate KEY against a safe variable-name pattern
    if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      echo "::error::Invalid variable name in DEPLOY_ENV_VARS: $key"
      return 1 2>/dev/null || exit 1
    fi

    export "$key=$value"
  done <<< "$DEPLOY_ENV_VARS"
fi
