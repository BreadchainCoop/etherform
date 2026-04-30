# Etherform

Reusable GitHub Actions workflows for Foundry smart contract CI/CD with upgrade safety validation.

## Workflows

| Workflow | Description |
|----------|-------------|
| `_ci.yml` | Build, test, format check, coverage, and Halmos |
| `_upgrade-safety.yml` | OpenZeppelin upgrade safety validation |
| `_deploy-testnet.yml` | Testnet deployment with Blockscout verification |
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
    secrets:
      RPC_URL: ${{ secrets.RPC_URL }}
```

## Upgrade Safety

Etherform validates upgrade safety using the [OpenZeppelin upgrades-core CLI](https://www.npmjs.com/package/@openzeppelin/upgrades-core), which checks storage layout compatibility, initializer safety, and proxy semantics.

### How it works

1. **On PR**: The upgrade-safety job checks out the base branch via git worktree, builds it, and compares each contract's storage layout against the current branch using the OZ CLI
2. **Next PR**: Validates against the latest base branch

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
| Omitted / `null` | Compare against the same contract on the base branch (default) |
| `"src/V1.sol:V1"` | Compare against another contract in the same build |

**Minimal** — validate against the base branch (most common):

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

#### Removing entries

By default, removing a contract from `upgrades.json` is a hard error — without this guard, deletions could silently bypass the upgrade-safety check. To intentionally drop entries (e.g. retiring a contract), set the top-level `"dangerous": true` flag in the same PR:

```json
{
  "dangerous": true,
  "contracts": [
    { "contract": "src/Greeter.sol:Greeter" }
  ]
}
```

Removals will be reported as a warning instead. Reset the flag back to `false` (or drop it) in a follow-up PR.

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

On the first run, contracts are validated for upgradeability only.

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
| `DEPLOY_ENV_VARS` | Deploy workflows | Optional; newline-separated `KEY=VALUE` pairs exported as environment variables before running the deploy script |

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
| `coverage-source-prefix` | string | `'src/'` | Path prefix for source files included in the lcov-based coverage summary |
| `coverage-post-comment` | boolean | `true` | Post coverage summary as a sticky PR comment |
| `coverage-min-threshold` | number | `0` | Minimum coverage % to pass (0 = disabled) |
| `run-halmos` | boolean | `false` | Run Halmos symbolic execution |
| `etherform-ref` | string | `'main'` | Git ref for etherform scripts checkout |

| Secret | Required | Description |
|--------|----------|-------------|
| `RPC_URL` | No | RPC endpoint for fork-based tests and coverage |

> **Note:** When `run-coverage` and `coverage-post-comment` are enabled, the calling workflow must have `pull-requests: write` permission for the sticky comment to be posted.

### `_upgrade-safety.yml`

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `package-manager` | string | `'none'` | Package manager (`none`, `npm`, `yarn`, `pnpm`) |
| `node-version` | string | `'20'` | Node.js version for package installation |
| `upgrades-config` | string | `'.github/upgrades.json'` | Path to upgrade safety config |
| `base-branch` | string | `'main'` | Base branch for upgrade safety comparison |
| `etherform-ref` | string | `'main'` | Git ref for etherform scripts checkout |

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
| `etherform-ref` | string | `'main'` | Git ref for etherform scripts checkout |

### `_foundry-cicd.yml`

The all-in-one workflow accepts all inputs from the above workflows plus:

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `skip-if-no-changes` | boolean | `true` | Skip if no contract files changed |
| `contract-paths` | string | `src/**`, `script/**`, etc. | Paths to watch for changes |
| `main-branch` | string | `'main'` | Base branch for upgrade safety comparison |
| `deploy-on-pr` | boolean | `false` | Deploy to testnet on PR |

All workflows also accept `etherform-ref` (default: `'main'`) to control which etherform branch the scripts are checked out from. Override this when testing against an unreleased etherform branch.

## Scripts

Shared logic is extracted into modular bash scripts under `scripts/`. Workflows check out these scripts at runtime via `actions/checkout`. The scripts are independently testable.

| Directory | Scripts | Purpose |
|-----------|---------|---------|
| `scripts/deploy/` | `prepare-env.sh`, `parse-broadcast.sh`, `resolve-network.sh`, `deployment-summary.sh`, `verify-blockscout.sh` | Deployment helpers |
| `scripts/coverage/` | `extract-summary.sh`, `check-threshold.sh` | Coverage reporting |
| `scripts/upgrade-safety/` | `validate.sh` | Upgrade safety validation |

Run tests locally: `bash tests/test-*.sh`
