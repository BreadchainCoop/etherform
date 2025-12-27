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
│   └── test.yml                   # Run workflow logic tests
├── scripts/                       # Extracted workflow logic
│   ├── validate-compiler-config.sh
│   └── detect-baseline.sh
├── tests/                         # Test suites
│   ├── fixtures/                  # Test fixtures (valid/invalid configs)
│   ├── test-compiler-config.sh
│   ├── test-baseline-detection.sh
│   └── run-all.sh
└── docs/
    └── specs/                     # Design specifications
```

## Testing Approach

The workflow logic is tested by **extracting testable shell functions** into standalone scripts, then running them against test fixtures that cover success and failure cases.

### Why This Approach?

1. **No external dependencies**: Tests run locally without needing a real Foundry project
2. **Fast feedback**: Shell scripts run instantly vs. waiting for GitHub Actions
3. **Complete coverage**: Can test failure cases that would be hard to trigger in integration tests
4. **Reproducible**: Same tests run locally and in CI

### Running Tests Locally

```bash
# Run all tests
./tests/run-all.sh

# Run specific test suite
./tests/test-compiler-config.sh
./tests/test-baseline-detection.sh
```

### What Gets Tested

| Test Suite | Validates |
|------------|-----------|
| `test-compiler-config.sh` | `bytecode_hash` and `cbor_metadata` validation |
| `test-baseline-detection.sh` | Baseline directory detection and fallback logic |

### Test Fixtures

Test fixtures are in `tests/fixtures/`:

| Fixture | Purpose |
|---------|---------|
| `foundry-valid.toml` | Valid config (should pass) |
| `foundry-missing-bytecode-hash.toml` | Missing required setting (should fail) |
| `foundry-missing-cbor-metadata.toml` | Missing required setting (should fail) |
| `foundry-wrong-bytecode-hash.toml` | Wrong value (should fail) |
| `foundry-wrong-cbor-metadata.toml` | Wrong value (should fail) |

## Development Workflow

### Making Workflow Changes

1. **Create a branch**:
   ```bash
   git checkout -b feature/my-workflow-change
   ```

2. **Make changes** to workflow files in `.github/workflows/`

3. **If adding new logic**, extract it to `scripts/` and add tests in `tests/`

4. **Run tests locally**:
   ```bash
   ./tests/run-all.sh
   ```

5. **Push and create PR**:
   ```bash
   git push -u origin feature/my-workflow-change
   ```

6. **CI runs tests automatically** via `.github/workflows/test.yml`

### Adding New Tests

1. Create a test fixture in `tests/fixtures/` if needed
2. Extract the workflow logic to a script in `scripts/`
3. Create a test script in `tests/test-<feature>.sh`
4. Add the test to `tests/run-all.sh`

Example test structure:
```bash
#!/bin/bash
# tests/test-my-feature.sh

run_test() {
  local name="$1"
  local expected_exit="$2"
  # ... run script and check result
}

echo "Testing my feature..."
run_test "Valid case" 0
run_test "Invalid case" 1
```

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

This allows consumers with non-root Foundry projects (monorepos) to use these workflows.

### Why Extract Logic to Scripts?

Extracting logic to standalone scripts enables:
- **Unit testing**: Test each piece of logic in isolation
- **Reuse**: Same logic used in workflows and tests
- **Debugging**: Run scripts locally to debug issues
