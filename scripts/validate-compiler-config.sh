#!/bin/bash
# Validate compiler config in foundry.toml
# This script is extracted from _foundry-ci.yml for local testing
#
# Usage: ./scripts/validate-compiler-config.sh [path/to/foundry.toml]
# Returns: 0 on success, 1 on failure

set -euo pipefail

FOUNDRY_TOML="${1:-foundry.toml}"

if [[ ! -f "$FOUNDRY_TOML" ]]; then
  echo "Error: $FOUNDRY_TOML not found"
  exit 1
fi

ERRORS=0

# Check bytecode_hash = "none" (excluding comments)
if grep -v '^\s*#' "$FOUNDRY_TOML" | grep -q 'bytecode_hash\s*=\s*"none"'; then
  echo "✓ bytecode_hash = \"none\""
else
  echo "✗ foundry.toml must set bytecode_hash = \"none\" for deterministic bytecode"
  ERRORS=1
fi

# Check cbor_metadata = false (excluding comments)
if grep -v '^\s*#' "$FOUNDRY_TOML" | grep -q 'cbor_metadata\s*=\s*false'; then
  echo "✓ cbor_metadata = false"
else
  echo "✗ foundry.toml must set cbor_metadata = false for deterministic bytecode"
  ERRORS=1
fi

if [[ $ERRORS -eq 1 ]]; then
  echo ""
  echo "Required foundry.toml settings for CI/CD:"
  echo "  [profile.default]"
  echo "  bytecode_hash = \"none\""
  echo "  cbor_metadata = false"
  exit 1
fi

echo "Compiler config validated successfully"
exit 0
