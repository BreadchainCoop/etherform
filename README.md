# Etherform

Reusable GitHub Actions workflows for Foundry smart contract CI/CD with upgrade safety validation.

## Workflows

| Workflow | Description |
|----------|-------------|
| `_ci.yml` | Build, test, format check, coverage, Halmos, and commit lint |
| `_upgrade-safety.yml` | OpenZeppelin upgrade safety validation |
| `_deploy-testnet.yml` | Testnet deployment with Blockscout verification |
| `_deploy-mainnet.yml` | Mainnet deployment with matrix support and 3-tier snapshot rotation |
| `_foundry-cicd.yml` | All-in-one orchestrator combining all of the above |

## Usage

### Basic CI

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

### CI with Node.js dependencies and fork-based tests

```yaml
# .github/workflows/ci.yml
name: CI

on: [push, pull_request]

permissions:
  contents: read
  pull-requests: write

jobs:
  ci:
    uses: BreadchainCoop/etherform/.github/workflows/_ci.yml@main
    with:
      package-manager: yarn
      run-coverage: true
      coverage-min-threshold: 80
      run-halmos: true
      run-commitlint: true
    secrets:
      RPC_URL: ${{ secrets.RPC_URL }}
```

### Deploy pipeline

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  ci:
    uses: BreadchainCoop/etherform/.github/workflows/_ci.yml@main
    with:
      package-manager: yarn
    secrets:
      RPC_URL: ${{ secrets.RPC_URL }}

  deploy:
    needs: [ci]
    uses: BreadchainCoop/etherform/.github/workflows/_deploy-mainnet.yml@main
    with:
      package-manager: yarn
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

### Node.js Dependencies

If your Foundry project uses npm/yarn/pnpm for Solidity dependencies (e.g., OpenZeppelin via `node_modules`), set `package-manager` to your package manager. This installs Node.js and runs the appropriate install command before any `forge` operations.

> **Note:** If using the `_foundry-cicd.yml` all-in-one workflow with `skip-if-no-changes: true`, add `package.json` and your lock file (e.g., `yarn.lock`) to the `contract-paths` input so dependency changes trigger the workflow.

### Secrets

| Secret | Used by | Description |
|--------|---------|-------------|
| `PRIVATE_KEY` | Deploy workflows | Deployer wallet private key |
| `RPC_URL` | All workflows | Network RPC endpoint (also used for fork-based tests) |
| `GH_TOKEN` | `_deploy-mainnet.yml` | GitHub token for pushing snapshot commits |

## Workflow Inputs

### `_ci.yml`

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `check-formatting` | boolean | `true` | Run `forge fmt --check` |
| `test-verbosity` | string | `'vvv'` | Test verbosity (`v`, `vv`, `vvv`, `vvvv`) |
| `package-manager` | string | `'none'` | Package manager (`none`, `npm`, `yarn`, `pnpm`) |
| `node-version` | string | `'20'` | Node.js version for package installation |
| `run-slither` | boolean | `false` | Run Slither static analysis |
| `slither-fail-on` | string | `'high'` | Minimum severity to fail on (`low`, `medium`, `high`) |
| `slither-config` | string | `'slither.config.json'` | Path to slither.config.json |
| `run-coverage` | boolean | `false` | Run `forge coverage` and post PR comment |
| `coverage-exclude-paths` | string | `''` | Path pattern to exclude from coverage (`--no-match-path`) |
| `coverage-source-filter` | string | `' src/'` | Grep filter for source files in coverage report |
| `coverage-post-comment` | boolean | `true` | Post coverage summary as a sticky PR comment |
| `coverage-min-threshold` | number | `0` | Minimum coverage % to pass (0 = disabled) |
| `run-halmos` | boolean | `false` | Run Halmos symbolic execution |
| `run-commitlint` | boolean | `false` | Enforce conventional commit messages |

| Secret | Required | Description |
|--------|----------|-------------|
| `RPC_URL` | No | RPC endpoint for fork-based tests and coverage |

> **Note:** When `run-coverage` and `coverage-post-comment` are enabled, the calling workflow must have `pull-requests: write` permission for the sticky comment to be posted.

### `_upgrade-safety.yml`

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `baseline-path` | string | `'test/upgrades/baseline'` | Path to baseline contracts |
| `fallback-path` | string | `'test/upgrades/previous'` | Fallback path if baseline missing |
| `validation-script` | string | `'script/upgrades/ValidateUpgrade.s.sol'` | Validation script path |
| `package-manager` | string | `'none'` | Package manager (`none`, `npm`, `yarn`, `pnpm`) |
| `node-version` | string | `'20'` | Node.js version for package installation |

### `_deploy-testnet.yml`

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `deploy-script` | string | `'script/Deploy.s.sol:Deploy'` | Deployment script |
| `network-config-path` | string | `'.github/deploy-networks.json'` | Network config path |
| `network-index` | number | `0` | Index in testnets array |
| `indexing-wait` | number | `60` | Seconds to wait before verification |
| `verify-contracts` | boolean | `true` | Verify on Blockscout |
| `package-manager` | string | `'none'` | Package manager (`none`, `npm`, `yarn`, `pnpm`) |
| `node-version` | string | `'20'` | Node.js version for package installation |

### `_deploy-mainnet.yml`

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `deploy-script` | string | `'script/Deploy.s.sol:Deploy'` | Deployment script |
| `network-config-path` | string | `'.github/deploy-networks.json'` | Network config path |
| `network` | string | `''` | Specific network (empty = all) |
| `indexing-wait` | number | `60` | Seconds to wait before verification |
| `verify-contracts` | boolean | `true` | Verify on Blockscout |
| `flatten-contracts` | boolean | `true` | Flatten and commit snapshots |
| `upgrades-path` | string | `'test/upgrades'` | Path for flattened snapshots |
| `package-manager` | string | `'none'` | Package manager (`none`, `npm`, `yarn`, `pnpm`) |
| `node-version` | string | `'20'` | Node.js version for package installation |

### `_foundry-cicd.yml`

The all-in-one workflow accepts all inputs from the above workflows plus:

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `skip-if-no-changes` | boolean | `true` | Skip if no contract files changed |
| `contract-paths` | string | `src/**`, `script/**`, etc. | Paths to watch for changes |
| `main-branch` | string | `'main'` | Branch that triggers mainnet deployment |
| `deploy-on-pr` | boolean | `false` | Deploy to testnet on PR |
| `deploy-on-main` | boolean | `false` | Deploy to mainnet on push |

## Example Project

See the [examples/foundry-counter](examples/foundry-counter) submodule for a complete working example.
