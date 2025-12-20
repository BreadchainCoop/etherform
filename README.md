# Etherform

Reusable GitHub Actions workflows for Foundry smart contract CI/CD with upgrade safety validation.

## Quick Start

For most projects, use the all-in-one orchestrator workflow:

```yaml
# .github/workflows/cicd.yml
name: CI/CD

on:
  push:
    branches: [main]
  pull_request:

jobs:
  cicd:
    uses: BreadchainCoop/etherform/.github/workflows/_foundry-cicd.yml@main
    with:
      deploy-on-pr: true      # Deploy to testnet on PRs
      deploy-on-main: true    # Deploy to mainnet on merge
    secrets:
      PRIVATE_KEY: ${{ secrets.PRIVATE_KEY }}
      RPC_URL: ${{ secrets.RPC_URL }}
```

## Workflows

### All-in-One Orchestrator

| Workflow | Description |
|----------|-------------|
| `_foundry-cicd.yml` | Complete CI/CD pipeline orchestrating all sub-workflows |

### Modular Sub-Workflows

For granular control, import individual workflows:

| Workflow | Description |
|----------|-------------|
| `_foundry-detect-changes.yml` | Smart contract change detection |
| `_foundry-ci.yml` | Build, test, format check, compiler config validation |
| `_foundry-upgrade-safety.yml` | OpenZeppelin upgrade safety validation |
| `_foundry-deploy.yml` | Deploy with Blockscout verification |
| `_foundry-post-mainnet.yml` | Flatten snapshots and create GitHub release |

## Configuration

### Orchestrator Inputs (`_foundry-cicd.yml`)

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `skip-if-no-changes` | boolean | `true` | Skip if no contract files changed |
| `contract-paths` | string | `src/**\nscript/**\n...` | Paths to check for changes |
| `check-formatting` | boolean | `true` | Run `forge fmt --check` |
| `test-verbosity` | string | `'vvv'` | Test verbosity level |
| `run-upgrade-safety` | boolean | `true` | Run upgrade safety validation |
| `baseline-path` | string | `'test/upgrades/baseline'` | Baseline contracts path |
| `deploy-on-pr` | boolean | `false` | Deploy to testnet on PRs |
| `deploy-on-main` | boolean | `false` | Deploy to mainnet on merge |
| `deploy-script` | string | `'script/Deploy.s.sol:Deploy'` | Deployment script |
| `testnet-blockscout-url` | string | `'https://eth-sepolia.blockscout.com'` | Testnet explorer |
| `mainnet-blockscout-url` | string | `'https://eth-sepolia.blockscout.com'` | Mainnet explorer |
| `flatten-contracts` | boolean | `true` | Flatten snapshots after deploy |
| `create-release` | boolean | `true` | Create GitHub release |
| `working-directory` | string | `'.'` | Working directory for commands |

### Secrets

| Secret | Required | Description |
|--------|----------|-------------|
| `PRIVATE_KEY` | For deploy | Deployer wallet private key |
| `RPC_URL` | For deploy | Network RPC endpoint |
| `GH_TOKEN` | For commits | Token for pushing commits/releases |

## Upgrade Safety

The upgrade safety workflow validates that contract upgrades don't break storage layout:

1. **Baseline Detection**: Looks for flattened contracts in `test/upgrades/baseline/`
2. **Comparison**: Compares current contracts against baseline using OpenZeppelin's Foundry Upgrades
3. **3-Tier Rotation**: After mainnet deploy: `current` → `baseline` → `previous`

If no baseline exists, the check is skipped gracefully.

## Example Project

See [examples/foundry-counter](examples/foundry-counter) for a complete working example.

---

# Development

This section explains how to develop and test changes to etherform's workflows.

## Repository Structure

```
etherform/
├── .github/workflows/
│   ├── _foundry-cicd.yml          # All-in-one orchestrator
│   ├── _foundry-ci.yml            # Build, test, format
│   ├── _foundry-upgrade-safety.yml # Upgrade validation
│   ├── _foundry-detect-changes.yml # Change detection
│   ├── _foundry-deploy.yml        # Deployment
│   ├── _foundry-post-mainnet.yml  # Post-deploy tasks
│   └── integration-test.yml       # Integration tests
├── examples/
│   └── foundry-counter/           # Test fixture (git submodule)
└── docs/
    └── specs/                     # Design specifications
```

## How Integration Testing Works

The key insight: **workflow changes are tested BEFORE they affect external consumers**.

### The Problem

When consumers import workflows via `@main`:
```yaml
uses: BreadchainCoop/etherform/.github/workflows/_foundry-ci.yml@main
```

Any breaking change pushed to `main` immediately affects all downstream projects.

### The Solution

The `integration-test.yml` workflow uses **local references** (`./`) instead of `@main`:

```yaml
jobs:
  test-ci:
    uses: ./.github/workflows/_foundry-ci.yml  # Uses current branch!
    with:
      working-directory: 'examples/foundry-counter'
```

This means:
1. On a PR branch, tests run against the **PR's workflow files**
2. The `examples/foundry-counter` submodule provides a real Foundry project to test against
3. If tests pass, the workflow changes are validated before merging to `main`

### What Gets Tested

| Test | Validates |
|------|-----------|
| Build | Contract compilation works |
| Format Check | `forge fmt --check` execution |
| Unit Tests | `forge test` runs successfully |
| Compiler Config | `bytecode_hash`/`cbor_metadata` validation |
| Upgrade Safety | Baseline detection and storage layout validation |

**Not tested**: Deployment (requires real RPC/keys and costs gas)

### When Integration Tests Run

Tests trigger on changes to:
- `.github/workflows/_foundry-*.yml` - Any workflow file
- `.github/workflows/integration-test.yml` - The test workflow itself
- `examples/foundry-counter/**` - The test fixture

## Development Workflow

### Making Workflow Changes

1. **Create a branch**:
   ```bash
   git checkout -b feature/my-workflow-change
   ```

2. **Make changes** to workflow files in `.github/workflows/`

3. **Push and create PR**:
   ```bash
   git push -u origin feature/my-workflow-change
   ```

4. **Integration tests run automatically** against your branch's workflows

5. **If tests pass**, your changes are validated and safe to merge

### Working with the Submodule

The `examples/foundry-counter` directory is a git submodule pointing to:
`https://github.com/BreadchainCoop/foundry-upgradeable-counter-example`

**Clone with submodules**:
```bash
git clone --recursive https://github.com/BreadchainCoop/etherform.git
```

**Update submodule**:
```bash
git submodule update --remote examples/foundry-counter
```

**Make changes to the test fixture**:
```bash
cd examples/foundry-counter
# Make changes, commit, push to the submodule repo
cd ..
git add examples/foundry-counter
git commit -m "chore: update test fixture submodule"
```

### Testing Upgrade Safety Detection

To verify upgrade safety detection works:

1. In the submodule, add a storage variable BEFORE an existing one:
   ```solidity
   contract Counter {
       address public owner;     // NEW - breaks storage layout!
       uint256 public number;    // Was at slot 0, now at slot 1
   }
   ```

2. Push and the integration test should FAIL (expected behavior)

3. Revert the change to restore passing tests

## Architecture Decisions

### Why `working-directory` Input?

All sub-workflows accept a `working-directory` input:
```yaml
inputs:
  working-directory:
    type: string
    default: '.'

jobs:
  build:
    defaults:
      run:
        working-directory: ${{ inputs.working-directory }}
```

This allows:
- Testing against the submodule at `examples/foundry-counter`
- Consumers with non-root Foundry projects (monorepos)

### Why Local `./` References in Integration Tests?

Using `./` instead of `@main` means:
```yaml
# Tests current branch's workflow files
uses: ./.github/workflows/_foundry-ci.yml

# Would test main branch (not useful for validation)
# uses: BreadchainCoop/etherform/.github/workflows/_foundry-ci.yml@main
```

### Why a Git Submodule?

- **Real project**: Tests run against actual Foundry code, not mocks
- **Isolation**: Test fixture lives in its own repo
- **Versioning**: Can pin to specific commits if needed
