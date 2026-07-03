# Etherform

Reusable GitHub Actions workflows for Foundry smart contract CI/CD with upgrade safety validation.

## Workflows

| Workflow | Description |
|----------|-------------|
| `_ci.yml` | Build, test, format check, coverage, and Halmos |
| `_upgrade-safety.yml` | OpenZeppelin upgrade safety validation |
| `_deploy-testnet.yml` | Testnet deployment with Blockscout verification |
| `_foundry-cicd.yml` | All-in-one orchestrator combining all of the above |

## Getting Started

Etherform's job is to make Solidity CI safe by default — including for repos where most contributors don't write Solidity day-to-day. You add **one workflow file** pointing at `_foundry-cicd.yml`, and every PR is checked for the things that catch Solidity-specific bugs (compile errors, broken upgrades, dropped coverage, deploy failures) before review.

This guide walks through the minimum setup and then layers each optional feature.

### What you get

With `_foundry-cicd.yml` (the recommended entry point), every PR is checked for:

- **Compilation and tests** — `forge build` and `forge test` must pass.
- **Formatting** — `forge fmt --check`, on by default.
- **Upgrade safety** *(opt-in)* — for contracts behind upgradeable proxies, OpenZeppelin's upgrades-core compares the PR against `main` and fails if the storage layout, initializers, or proxy semantics change in a way that would brick a live upgrade. Storage-layout regressions are the most common way to brick a proxy, and the type checker and tests will not catch them.
- **Coverage threshold** *(opt-in)* — sticky PR comment with coverage; configurable threshold blocks PRs that drop below it.
- **Static analysis & symbolic execution** *(opt-in)* — Slither and Halmos.
- **Testnet deploy on PR** *(opt-in)* — every PR is deployed to a testnet with Blockscout verification, so end-to-end behavior is exercised before merge.

You don't need to understand how any of these tools work to get value from them — defaults are conservative, and Solidity-specific failure modes surface as plain pass/fail PR checks.

### Step 1 — Minimum viable CI

Create `.github/workflows/cicd.yml` in your repo:

```yaml
name: CI/CD
on: [push, pull_request]

permissions:
  contents: read
  pull-requests: write

concurrency:
  group: cicd-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  cicd:
    uses: BreadchainCoop/etherform/.github/workflows/_foundry-cicd.yml@main
```

That's it. Push the file and PRs will run `forge build`, `forge test`, and `forge fmt --check`. No secrets or extra config files are needed yet.

`pull-requests: write` is granted up front so the coverage PR comment works once you turn coverage on; it's harmless while coverage is off. The `concurrency` block cancels superseded CI runs when you push to a PR in quick succession (deploys are additionally serialized inside etherform and never cancelled mid-flight).

When you enable features that need secrets later, pass them explicitly:

```yaml
    secrets:
      RPC_URL: ${{ secrets.RPC_URL }}
      PRIVATE_KEY: ${{ secrets.PRIVATE_KEY }}
```

(`secrets: inherit` also works, but enumerating keeps the workflow's access explicit.)

### Step 2 — Node-managed Solidity dependencies (e.g. OpenZeppelin)

If your contracts import OpenZeppelin (or anything else) via `node_modules`, tell the workflow which package manager to use:

```yaml
    with:
      package-manager: yarn   # or npm, pnpm
```

The workflow installs Node and runs the corresponding install command before `forge build`.

> **Watch out:** `_foundry-cicd.yml` defaults to `skip-if-no-changes: true`, so dependency-only PRs are skipped unless you also add `package.json` and your lockfile to `contract-paths`. See [Configuration → Node.js Dependencies](#nodejs-dependencies).

### Step 3 — Upgrade safety

Use this if any of your contracts are deployed behind upgradeable proxies. It is the highest-leverage feature in this library: it stops a contributor from merging a change that would brick a live deployment.

**3a.** Enable storage-layout output in `foundry.toml`:

```toml
build_info = true
extra_output = ["storageLayout"]
```

**3b.** List your upgradeable contracts in `.github/upgrades.json`:

```json
{
  "contracts": [
    { "contract": "src/Token.sol:Token" },
    { "contract": "src/Greeter.sol:Greeter" }
  ]
}
```

Each contract is compared against the version on `main`. `_foundry-cicd.yml` runs the check automatically whenever `.github/upgrades.json` exists — no additional input needed. Without the file, the upgrade-safety job is skipped.

For the rarer "compare a V2 against a V1 kept in the same repo" case, and for guidance on intentionally removing entries, see the [Upgrade Safety](#upgrade-safety) section below.

### Step 4 — Testnet deploy on PR

Deploy every PR to a testnet so end-to-end deployment behavior is validated before merge.

**4a.** List your testnets in `.github/deploy-networks.json`:

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

**4b.** Add repo secrets in **Settings → Secrets and variables → Actions**:

| Secret | Value |
|--------|-------|
| `PRIVATE_KEY` | Deployer wallet private key — use a dedicated, low-balance testnet wallet |
| `RPC_URL` | Testnet RPC endpoint |

**4c.** Turn on the deploy:

```yaml
    with:
      deploy-on-pr: true
```

The deploy job verifies the contracts on Blockscout, writes a `deployments/<network>/deployment.json` artifact for frontends, and posts a deployment summary in the run. Deploys only run for pull requests from the same repository (fork PRs have no access to secrets), and are serialized per branch so two pushes can't interleave deployments.

### Step 5 — Coverage threshold and static analysis (optional)

```yaml
    with:
      run-coverage: true
      coverage-min-threshold: 80   # fail if coverage drops below 80%
      run-slither: true
      run-halmos: true
```

### Step 6 — Mainnet deploys on merge (optional)

The deploy workflow is network-agnostic: the chain is whatever your `RPC_URL` points at, and the chain ID from the broadcast is matched against `deploy-networks.json` for the explorer link. For mainnet, call `_deploy-testnet.yml` directly from a workflow that triggers on merge to `main`, and put it behind a [protected GitHub Environment](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment) so the deploy waits for a required reviewer:

```yaml
# .github/workflows/deploy-mainnet.yml
name: Deploy Mainnet
on:
  push:
    branches: [main]

permissions:
  contents: read
  pull-requests: write

jobs:
  deploy:
    uses: BreadchainCoop/etherform/.github/workflows/_deploy-testnet.yml@main
    with:
      environment: production   # protected GitHub Environment
    secrets:
      PRIVATE_KEY: ${{ secrets.MAINNET_PRIVATE_KEY }}
      RPC_URL: ${{ secrets.MAINNET_RPC_URL }}
```

Add the mainnet entry (name, `chain_id`, `blockscout_url`) to the `testnets` array in `deploy-networks.json` so the explorer link resolves.

### Common pitfalls

- **One workflow file, not several.** `_foundry-cicd.yml` already covers CI, upgrade safety, and deploy. Don't also add separate `_ci.yml` or `_upgrade-safety.yml` wrappers — every PR will run everything twice.
- **Pin your ref.** `@main` tracks etherform's latest commit. For reproducible CI, pin `uses:` to a tag or commit SHA. The bash scripts are automatically checked out at the same commit as the workflow you call (via `job.workflow_sha`), so a single pin covers both; `etherform-ref` only needs to be set to override that (rarely needed).
- **`403 Resource not accessible by integration`.** Permissions are granted by the calling workflow, not at the org level. Start with the `permissions:` block in step 1 and grow it if a feature you turn on later requires more.

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

Alternatively, pass extra flags to the OZ validate CLI per contract via `options` in `upgrades.json` (useful when you can't annotate the source, e.g. vendored contracts):

```json
{
  "contracts": [
    {
      "contract": "src/Token.sol:Token",
      "options": ["--unsafeAllowRenames"]
    }
  ]
}
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
| `test-verbosity` | string | `'vvv'` | Test verbosity (`v`, `vv`, `vvv`, `vvvv`, `vvvvv`) |
| `package-manager` | string | `'none'` | Package manager (`none`, `npm`, `yarn`, `pnpm`) |
| `node-version` | string | `'22'` | Node.js version for package installation |
| `foundry-version` | string | `'stable'` | Foundry version (`stable`, `nightly`, or a specific version) |
| `working-directory` | string | `'.'` | Directory containing the Foundry project (for monorepos) |
| `run-slither` | boolean | `false` | Run Slither static analysis |
| `slither-fail-on` | string | `'high'` | Minimum severity to fail on (`low`, `medium`, `high`) |
| `slither-config` | string | `'slither.config.json'` | Path to slither.config.json |
| `run-coverage` | boolean | `false` | Run `forge coverage` and post PR comment |
| `coverage-exclude-paths` | string | `''` | Path pattern to exclude from coverage (`--no-match-path`) |
| `coverage-source-filter` | string | `' src/'` | Grep filter for source files in coverage report |
| `coverage-post-comment` | boolean | `true` | Post coverage summary as a sticky PR comment |
| `coverage-min-threshold` | number | `0` | Minimum coverage % to pass (0 = disabled) |
| `run-halmos` | boolean | `false` | Run Halmos symbolic execution |
| `halmos-version` | string | `''` | Halmos version to install (empty = latest) |
| `etherform-ref` | string | `''` | Git ref for etherform scripts checkout (default: the ref this workflow was called at) |

| Secret | Required | Description |
|--------|----------|-------------|
| `RPC_URL` | No | RPC endpoint for fork-based tests and coverage |

> **Note:** When `run-coverage` and `coverage-post-comment` are enabled, the calling workflow must have `pull-requests: write` permission for the sticky comment to be posted.

### `_upgrade-safety.yml`

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `package-manager` | string | `'none'` | Package manager (`none`, `npm`, `yarn`, `pnpm`) |
| `node-version` | string | `'22'` | Node.js version for package installation |
| `foundry-version` | string | `'stable'` | Foundry version (`stable`, `nightly`, or a specific version) |
| `upgrades-config` | string | `'.github/upgrades.json'` | Path to upgrade safety config |
| `base-branch` | string | `'main'` | Base branch for upgrade safety comparison |
| `oz-upgrades-core-version` | string | `'1.44.2'` | Version of `@openzeppelin/upgrades-core` used for validation |
| `etherform-ref` | string | `''` | Git ref for etherform scripts checkout (default: the ref this workflow was called at) |

### `_deploy-testnet.yml`

Despite the historical name, this workflow deploys to whatever network `RPC_URL` points at (see [Step 6](#step-6--mainnet-deploys-on-merge-optional) for mainnet). The chain ID from the broadcast artifact is matched against the network config to resolve the network name and explorer URL.

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `deploy-script` | string | `'script/Deploy.s.sol:Deploy'` | Deployment script |
| `network-config-path` | string | `'.github/deploy-networks.json'` | Network config path |
| `indexing-wait` | number | `60` | Seconds to wait before verification |
| `verify-contracts` | boolean | `true` | Verify on Blockscout |
| `environment` | string | `''` | GitHub Environment to deploy under (empty = none); use a protected environment for mainnet |
| `package-manager` | string | `'none'` | Package manager (`none`, `npm`, `yarn`, `pnpm`) |
| `node-version` | string | `'22'` | Node.js version for package installation |
| `foundry-version` | string | `'stable'` | Foundry version (`stable`, `nightly`, or a specific version) |
| `etherform-ref` | string | `''` | Git ref for etherform scripts checkout (default: the ref this workflow was called at) |

### `_foundry-cicd.yml`

The all-in-one workflow accepts all inputs from the above workflows (except `environment`) plus:

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `skip-if-no-changes` | boolean | `true` | Skip if no contract files changed |
| `contract-paths` | string | `src/**`, `script/**`, etc. | Paths to watch for changes |
| `deploy-on-pr` | boolean | `false` | Deploy to testnet on PR |
| `main-branch` | string | `''` | **Deprecated** alias for `base-branch`; when set it overrides `base-branch`. Emits a warning. Prefer `base-branch`. |

Internally it calls `_ci.yml`, `_upgrade-safety.yml`, and `_deploy-testnet.yml` as nested reusable workflows, so check names appear as e.g. `CI/CD / ci / Build & Test`. The upgrade-safety job runs only when the `upgrades-config` file exists; deploys run only for same-repo pull requests.

> **Deprecation:** the upgrade-safety base branch input was renamed `main-branch` → `base-branch` for consistency with `_upgrade-safety.yml`. `main-branch` still works (it overrides `base-branch` and logs a deprecation warning), so existing callers are not broken; migrate when convenient.

All workflows also accept `etherform-ref` to override which etherform ref the bash scripts are checked out from. By default the scripts come from the same commit as the workflow you call (`job.workflow_sha`), so this is only needed for unusual setups.

## Scripts

Shared logic is extracted into modular bash scripts under `scripts/`. Workflows check out these scripts (and the shared setup action) at runtime via a sparse `actions/checkout` of etherform pinned to the same commit as the workflow. The scripts are independently testable.

| Directory | Scripts | Purpose |
|-----------|---------|---------|
| `scripts/deploy/` | `prepare-env.sh`, `parse-broadcast.sh`, `resolve-network.sh`, `write-deployment-json.sh`, `deployment-summary.sh`, `deployment-comment.sh`, `verify-blockscout.sh` | Deployment helpers |
| `scripts/coverage/` | `extract-summary.sh`, `check-threshold.sh` | Coverage reporting |
| `scripts/upgrade-safety/` | `validate-config.sh`, `validate.sh` | Upgrade safety validation |

Run tests locally: `for t in tests/test-*.sh; do bash "$t"; done`

## Repo CI

Etherform tests itself: `test.yml` runs actionlint, ShellCheck, and the unit tests for every script, and `e2e.yml` runs the real `_foundry-cicd.yml` against the fixture Foundry project in `tests/fixtures/project` on every PR — exercising change detection, build/test/format, coverage extraction and thresholds, and the graceful upgrade-safety skip.
