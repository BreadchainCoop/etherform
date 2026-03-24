# Etherform

Reusable GitHub Actions workflows for Foundry smart contract CI/CD with upgrade safety validation.

## Workflows

| Workflow | Description |
|----------|-------------|
| `_ci.yml` | Build, test, format check, and coverage report |
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

```yaml
# .github/workflows/ci.yml (with coverage)
name: CI

on: [push, pull_request]

permissions:
  contents: read
  pull-requests: write

jobs:
  ci:
    uses: BreadchainCoop/etherform/.github/workflows/_ci.yml@main
    with:
      check-formatting: true
      run-coverage: true
      coverage-exclude-paths: 'test/fork/**'
```

## Upgrade Safety

Etherform validates upgrade safety using the [OpenZeppelin upgrades-core CLI](https://www.npmjs.com/package/@openzeppelin/upgrades-core), which checks storage layout compatibility, initializer safety, and proxy semantics.

### How it works

1. **On PR**: The upgrade-safety job compares each contract against its committed **flattened baseline** (the last deployed version) using the OZ CLI
2. **On mainnet deploy**: The `flatten-snapshots` job flattens deployed contracts and rotates snapshots (`current/` → `baseline/` → `previous/`), auto-committing to the repo
3. **Next PR**: Validates against the updated baseline

This ensures the reference is always the **last deployed version**, not just the latest code on main.

### Setup

#### 1. Add `foundry.toml` settings

```toml
build_info = true
extra_output = ["storageLayout"]
```

#### 2. Create `.github/upgrades.json`

Each entry specifies a contract to validate. The `reference` field controls what to compare against:

| `reference` value | Behavior |
|---|---|
| Omitted / `null` | Compare against the committed flattened baseline (default) |
| `"src/V1.sol:V1"` | Compare against another contract in the same build |

**Minimal** — validate against flattened baselines (most common):

```json
{
  "contracts": [
    { "contract": "src/Greeter.sol:Greeter" },
    { "contract": "src/Token.sol:Token" }
  ]
}
```

**With explicit contract reference** — compare against a V1 contract kept in the repo:

```json
{
  "contracts": [
    {
      "contract": "src/GreeterV2.sol:GreeterV2",
      "reference": "src/GreeterV1.sol:GreeterV1"
    }
  ]
}
```

#### 3. Use the workflow

```yaml
# .github/workflows/ci.yml
name: CI

on: [push, pull_request]

jobs:
  ci:
    uses: BreadchainCoop/etherform/.github/workflows/_ci.yml@main

  upgrade-safety:
    needs: [ci]
    uses: BreadchainCoop/etherform/.github/workflows/_upgrade-safety.yml@main
```

On the first run (no baselines yet), contracts are validated for upgradeability only. Baselines are initialized automatically after the first mainnet deploy.

### Unsafe-allow overrides

Use NatSpec annotations in your Solidity source:

```solidity
/// @custom:oz-upgrades-unsafe-allow delegatecall
contract MyContract is Initializable {
    // ...
}
```

See the [OpenZeppelin docs](https://docs.openzeppelin.com/upgrades-plugins/writing-upgradeable) for all supported annotations.

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
| `run-slither` | boolean | `false` | Run Slither static analysis |
| `slither-fail-on` | string | `'high'` | Minimum severity to fail on (`low`, `medium`, `high`) |
| `slither-config` | string | `'slither.config.json'` | Path to slither.config.json |
| `run-coverage` | boolean | `false` | Run `forge coverage` and post PR comment |
| `coverage-exclude-paths` | string | `''` | Path pattern to exclude from coverage (`--no-match-path`) |
| `coverage-source-filter` | string | `' src/'` | Grep filter for source files in coverage report |
| `coverage-post-comment` | boolean | `true` | Post coverage summary as a sticky PR comment |

> **Note:** When `run-coverage` and `coverage-post-comment` are enabled, the calling workflow must have `pull-requests: write` permission for the sticky comment to be posted.

### `_upgrade-safety.yml`

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `upgrades-config` | string | `'.github/upgrades.json'` | Path to upgrade safety config |
| `baseline-path` | string | `'test/upgrades/baseline'` | Path to flattened baseline contracts |

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
