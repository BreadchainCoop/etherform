# Etherform

Reusable GitHub Actions workflows for Foundry smart contract CI/CD with upgrade safety validation.

## Workflows

| Workflow | Description |
|----------|-------------|
| `_ci.yml` | Build, test, and format check |
| `_upgrade-safety.yml` | OpenZeppelin upgrade safety validation |
| `_deploy-testnet.yml` | Testnet deployment with Blockscout verification |
| `_deploy-mainnet.yml` | Mainnet deployment with matrix support and 3-tier snapshot rotation |

## Usage

Reference the reusable workflows in your Foundry project:

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
    secrets:
      PRIVATE_KEY: ${{ secrets.PRIVATE_KEY }}
      RPC_URL: ${{ secrets.RPC_URL }}
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

### Secrets Required

| Secret | Description |
|--------|-------------|
| `PRIVATE_KEY` | Deployer wallet private key |
| `RPC_URL` | Network RPC endpoint |

## Deployment Profiles

Use `deployment-foundry-profile` to specify a Foundry profile for deployments while keeping CI tests on the default profile. This is useful when tests fail with high optimizer settings but production needs maximum optimization.

```yaml
jobs:
  deploy:
    uses: BreadchainCoop/etherform/.github/workflows/_deploy-mainnet.yml@main
    with:
      deployment-foundry-profile: 'production'
    secrets:
      PRIVATE_KEY: ${{ secrets.PRIVATE_KEY }}
      RPC_URL: ${{ secrets.RPC_URL }}
```

Define profiles in your `foundry.toml`:

```toml
[profile.default]
optimizer = false

[profile.production]
optimizer = true
optimizer_runs = 1000000
```

The profile applies to deployment, upgrade safety, verification, and flattening steps. CI tests run with the default profile.

## Workflow Inputs

### `_ci.yml`

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `deployment-foundry-profile` | string | `''` | Foundry profile (optional, for standalone use) |
| `check-formatting` | boolean | `true` | Run `forge fmt --check` |
| `test-verbosity` | string | `'vvv'` | Test verbosity (`v`, `vv`, `vvv`, `vvvv`) |

### `_upgrade-safety.yml`

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `deployment-foundry-profile` | string | `''` | Foundry profile for deployment |
| `baseline-path` | string | `'test/upgrades/baseline'` | Path to baseline contracts |
| `fallback-path` | string | `'test/upgrades/previous'` | Fallback path if baseline missing |
| `validation-script` | string | `'script/upgrades/ValidateUpgrade.s.sol'` | Validation script path |

### `_deploy-testnet.yml`

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `deployment-foundry-profile` | string | `''` | Foundry profile for deployment |
| `deploy-script` | string | `'script/Deploy.s.sol:Deploy'` | Deployment script |
| `network-config-path` | string | `'.github/deploy-networks.json'` | Network config path |
| `network-index` | number | `0` | Index in testnets array |
| `indexing-wait` | number | `60` | Seconds to wait before verification |

### `_deploy-mainnet.yml`

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `deployment-foundry-profile` | string | `''` | Foundry profile for deployment |
| `deploy-script` | string | `'script/Deploy.s.sol:Deploy'` | Deployment script |
| `network-config-path` | string | `'.github/deploy-networks.json'` | Network config path |
| `network` | string | `''` | Specific network (empty = all) |
| `indexing-wait` | number | `60` | Seconds to wait before verification |
| `flatten-contracts` | boolean | `true` | Flatten and commit snapshots |
| `upgrades-path` | string | `'test/upgrades'` | Path for flattened snapshots |

## Example Project

See the [examples/foundry-counter](examples/foundry-counter) submodule for a complete working example.
