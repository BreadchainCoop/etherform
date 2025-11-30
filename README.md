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

## Workflow Inputs

### `_ci.yml`

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `check-formatting` | boolean | `true` | Run `forge fmt --check` |
| `test-verbosity` | string | `'vvv'` | Test verbosity (`v`, `vv`, `vvv`, `vvvv`) |

### `_upgrade-safety.yml`

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `baseline-path` | string | `'test/upgrades/baseline'` | Path to baseline contracts |
| `fallback-path` | string | `'test/upgrades/previous'` | Fallback path if baseline missing |
| `validation-script` | string | `'script/upgrades/ValidateUpgrade.s.sol'` | Validation script path |

### `_deploy-testnet.yml`

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `deploy-script` | string | `'script/Deploy.s.sol:Deploy'` | Deployment script |
| `network-config-path` | string | `'.github/deploy-networks.json'` | Network config path |
| `network-index` | number | `0` | Index in testnets array |
| `indexing-wait` | number | `60` | Seconds to wait before verification |

### `_deploy-mainnet.yml`

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `deploy-script` | string | `'script/Deploy.s.sol:Deploy'` | Deployment script |
| `network-config-path` | string | `'.github/deploy-networks.json'` | Network config path |
| `network` | string | `''` | Specific network (empty = all) |
| `indexing-wait` | number | `60` | Seconds to wait before verification |
| `flatten-contracts` | boolean | `true` | Flatten and commit snapshots |
| `upgrades-path` | string | `'test/upgrades'` | Path for flattened snapshots |

## Example Project

See the [examples/foundry-counter](examples/foundry-counter) submodule for a complete working example.
