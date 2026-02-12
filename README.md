# Etherform

Reusable GitHub Actions workflows for Foundry smart contract CI/CD with upgrade safety validation.

## Workflows

| Workflow | Description |
|----------|-------------|
| `_ci.yml` | Build, test, format check, and optional Slither analysis |
| `_upgrade-safety.yml` | OpenZeppelin upgrade safety validation |
| `_deploy-testnet.yml` | Testnet deployment with Blockscout verification |
| `_deploy-mainnet.yml` | Mainnet deployment with matrix support and 3-tier snapshot rotation |
| `_foundry-cicd.yml` | All-in-one CI/CD pipeline (recommended) |

## Quick Start

### Option 1: All-in-one workflow (recommended)

```yaml
# .github/workflows/cicd.yml
name: CI/CD

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  pipeline:
    uses: BreadchainCoop/etherform/.github/workflows/_foundry-cicd.yml@main
    with:
      deploy-on-pr: true        # Deploy to testnet on PRs
      deploy-on-main: true      # Deploy to mainnet on merge
      verify-contracts: true    # Verify on Blockscout
      run-slither: true         # Optional static analysis
      foundry-profile: ''       # Use specific Foundry profile (optional)
    secrets:
      PRIVATE_KEY: ${{ secrets.PRIVATE_KEY }}
      RPC_URL: ${{ secrets.RPC_URL }}
      ADMIN_ADDRESS: ${{ secrets.ADMIN_ADDRESS }}  # Optional
```

### Option 2: Individual workflows

```yaml
# .github/workflows/ci.yml
name: CI

on: [push, pull_request]

jobs:
  ci:
    uses: BreadchainCoop/etherform/.github/workflows/_ci.yml@main
    with:
      check-formatting: true
      test-verbosity: 'vvv'
      run-slither: true
      slither-fail-on: 'medium'
```

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  ci:
    uses: BreadchainCoop/etherform/.github/workflows/_ci.yml@main

  deploy:
    needs: [ci]
    uses: BreadchainCoop/etherform/.github/workflows/_deploy-mainnet.yml@main
    with:
      verify-contracts: true
      foundry-profile: 'production'
    secrets:
      PRIVATE_KEY: ${{ secrets.PRIVATE_KEY }}
      RPC_URL: ${{ secrets.RPC_URL }}
      ADMIN_ADDRESS: ${{ secrets.ADMIN_ADDRESS }}
```

## Configuration

### Network Configuration

Create `.github/deploy-networks.json` in your repository:

```json
{
  "testnets": [
    {
      "name": "sepolia",
      "chain_id": 11155111,
      "blockscout_url": "https://eth-sepolia.blockscout.com",
      "environment": "testnet"
    }
  ],
  "mainnets": [
    {
      "name": "ethereum",
      "chain_id": 1,
      "blockscout_url": "https://eth.blockscout.com",
      "environment": "production-ethereum"
    }
  ]
}
```

> **Tip:** To skip Blockscout verification for a specific network, omit the `blockscout_url` field or set it to `""`.

### Deployment Script Convention

CI expects a canonical entry point:

```
script/Deploy.s.sol:Deploy
```

Your deploy script can read these environment variables (provided by the workflow):
- `PRIVATE_KEY` — deployer wallet private key
- `RPC_URL` — network RPC endpoint
- `ADMIN_ADDRESS` — optional admin address for upgradeable contracts

### Foundry Profiles

Use the `foundry-profile` input to specify a Foundry profile for deployment builds. This is useful when your test profile uses different optimizer settings than production:

```toml
# foundry.toml
[profile.default]
optimizer = false

[profile.production]
optimizer = true
optimizer_runs = 200
bytecode_hash = "none"
cbor_metadata = false
```

```yaml
jobs:
  pipeline:
    uses: BreadchainCoop/etherform/.github/workflows/_foundry-cicd.yml@main
    with:
      foundry-profile: 'production'
```

### Secrets

| Secret | Required | Description |
|--------|----------|-------------|
| `PRIVATE_KEY` | Yes (for deploy) | Deployer wallet private key |
| `RPC_URL` | Yes (for deploy) | Network RPC endpoint |
| `ADMIN_ADDRESS` | No | Admin address for upgradeable contract deploy scripts |
| `GH_TOKEN` | No | GitHub token for pushing snapshot commits (defaults to `GITHUB_TOKEN`) |

## Workflow Inputs Reference

### `_ci.yml`

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `check-formatting` | boolean | `true` | Run `forge fmt --check` |
| `test-verbosity` | string | `'vvv'` | Test verbosity (`v`, `vv`, `vvv`, `vvvv`) |
| `foundry-profile` | string | `''` | Foundry profile for build/test |
| `run-slither` | boolean | `false` | Run Slither static analysis |
| `slither-fail-on` | string | `'medium'` | Slither severity to fail on |
| `slither-config` | string | `'slither.config.json'` | Slither config file path |

### `_upgrade-safety.yml`

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `baseline-path` | string | `'test/upgrades/baseline'` | Path to baseline contracts |
| `fallback-path` | string | `'test/upgrades/previous'` | Fallback path if baseline missing |
| `validation-script` | string | `'script/upgrades/ValidateUpgrade.s.sol'` | Validation script path |
| `foundry-profile` | string | `''` | Foundry profile |

### `_deploy-testnet.yml`

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `deploy-script` | string | `'script/Deploy.s.sol:Deploy'` | Deployment script |
| `network-config-path` | string | `'.github/deploy-networks.json'` | Network config path |
| `network-index` | number | `0` | Index in testnets array |
| `indexing-wait` | number | `60` | Seconds to wait before verification |
| `verify-contracts` | boolean | `true` | Run Blockscout verification |
| `foundry-profile` | string | `''` | Foundry profile for deployment |

### `_deploy-mainnet.yml`

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `deploy-script` | string | `'script/Deploy.s.sol:Deploy'` | Deployment script |
| `network-config-path` | string | `'.github/deploy-networks.json'` | Network config path |
| `network` | string | `''` | Specific network (empty = all) |
| `indexing-wait` | number | `60` | Seconds to wait before verification |
| `verify-contracts` | boolean | `true` | Run Blockscout verification |
| `flatten-contracts` | boolean | `true` | Flatten and commit snapshots |
| `upgrades-path` | string | `'test/upgrades'` | Path for flattened snapshots |
| `foundry-profile` | string | `''` | Foundry profile for deployment |

### `_foundry-cicd.yml` (all-in-one)

Combines all the above plus:

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `skip-if-no-changes` | boolean | `true` | Skip if no contract files changed |
| `contract-paths` | string | `src/** script/** ...` | Paths to watch for changes |
| `deploy-on-pr` | boolean | `false` | Deploy to testnet on PR |
| `deploy-on-main` | boolean | `false` | Deploy to mainnet on push to main |
| `run-slither` | boolean | `false` | Run Slither static analysis |
| `run-upgrade-safety` | boolean | `true` | Run upgrade safety validation |

## Blockscout Verification

Verification uses `forge verify-contract` with Blockscout. The workflow:

1. **Validates the Blockscout URL** — fails fast on malformed URLs instead of looping
2. **Checks actual verification status** — parses output for "Contract successfully verified" or "Pass - Verified" instead of trusting the exit code (which can return 0 even on failure)
3. **Retries with backoff** — 3 attempts with 30s/60s/90s delays
4. **Times out** — each attempt has a 120s timeout to prevent hanging
5. **Is optional** — set `verify-contracts: false` to skip, or omit `blockscout_url` from network config

## Deployment Summary

After deployment, the workflow generates a GitHub Step Summary containing:

- **Contract table** with name, address, constructor arguments, and explorer link
- **Method calls** (collapsible) showing all `initialize()`, `grantRoles()`, etc. calls with their arguments

## Testing

Run the workflow logic tests locally:

```bash
./tests/run-all.sh
```

Tests validate:
- Blockscout verification output parsing (false positive detection, URL validation)
- Baseline detection logic for upgrade safety
