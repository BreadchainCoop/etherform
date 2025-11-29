# Technical Spec — Auto CI/CD: Testnet & Mainnet Deployments (Foundry + Blockscout)

## 1. Background

### Problem Statement: What hurts today?

* Manual, inconsistent deployments of smart contracts across environments.
* Frontend team might be blocked by contract deployment details.
* Risky upgrades without automated safety checks.
* Fragmented verification (Etherscan vs Blockscout) and inconsistent artifacts/summaries.

### Context / History

* Current repo uses Foundry for build/test and deployment (`forge`, `cast`, `forge script`).
* Reference workflows provided for:

  * **Testnet**: deploy on PR to `main`.
  * **Mainnet (configurable)**: deploy on push/merge to `main` under a protected environment.
  * **Upgrade safety validation** via flattened previous/current contracts and `script/upgrades/ValidateUpgrade.s.sol`.
  * **Flattening** On pushes to dev only (after tests and upgrade-safety pass), CI flattens all contracts listed in `broadcast/**/run-latest.json` to `upgrades/snapshots/current/`, then backs up that snapshot to `upgrades/snapshots/previous/` and auto-commits the changes. The set of contracts to flatten is derived only from Foundry’s broadcast artifact `broadcast/**/run-latest.json`. This file is the authoritative source of truth for flattening paths and for deployment address summaries.
* Direction: **adopt Blockscout verification** and **drop Etherscan** support.
* Intended to be reused across multiple repos; not for continuous auto-upgrades of production, but to guarantee end-to-end deployability and unblock frontends.
* **Reusable composite GitHub Action:** All CI/CD steps (build/test, upgrade-safety, deploy, verify, summarize, artifacts) are consumed via a single composite action. Workflows become thin wrappers that invoke the action with network-specific inputs.
* **Per-repo triggers configurable:** Each repo chooses its own triggers (`pull_request`, `push`, `release`, `workflow_dispatch`) and networks via workflow inputs.

### Standardized Deployment Script

To make workflows reusable across repos, CI expects a **canonical wrapper**:

- **Entry point (name):** `script/Deploy.s.sol:Deploy`
- **Invocation (canonical):**
  ```bash
  forge script script/Deploy.s.sol:Deploy \
    --rpc-url "$RPC_URL" \
    --broadcast \
    --slow \
    -vvvv
  ```

**Env mapping (CI):** the workflow must export `PRIVATE_KEY` from the environment-specific secret, e.g. `PRIVATE_KEY=$TESTNET_PRIVATE_KEY` on testnet and `PRIVATE_KEY=$MAINNET_PRIVATE_KEY` on mainnet.

**Deployment artifact schema (output)** CI will parse the Foundry broadcast artifact to extract deployed addresses.

  ```json
  {
    "contracts": [
      { "sourcePathAndName": "src/Greeter.sol:Greeter", "address": "0x..." }
    ]
  }
  ```

This is the output written to `deployments/{network}/deployment.json`, derived by parsing Foundry’s `broadcast/**/run-latest.json`.

* **Deploy script (example):**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Greeter} from "src/Greeter.sol";

contract Deploy is Script {
  function run() external {
        // Minimal assumption: a PRIVATE_KEY is provided to broadcast
        uint256 pk = vm.envUint("PRIVATE_KEY");
        require(pk != 0, "PRIVATE_KEY required");

        vm.startBroadcast(pk);

        ProxyAdmin admin = new ProxyAdmin();
        console2.log("ProxyAdmin", address(admin));

        Greeter impl = new Greeter();
        console2.log("Greeter_Implementation", address(impl));

        bytes memory initData = abi.encodeWithSelector(Greeter.initialize.selector, "Hello, world!");

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(admin), initData);
        console2.log("Greeter_Proxy", address(proxy));

        vm.stopBroadcast();
  }
}

```


**Compiler configuration (repo-level requirement)**

The repository’s `foundry.toml` must set:

- `bytecode_hash = "none"`
- `cbor_metadata = false`

These settings are required for deterministic bytecode and constructor-arg extraction. CI will validate that builds use this configuration and fail otherwise.


### Stakeholders

* **Smart Contracts Team** — authors of contracts and deployment scripts.
* **DevOps** — maintain GitHub Actions, secrets, and environment protections.

---

## 2. Motivation

### Goals & Success Stories

* **On every PR to `main`:** build, test, upgrade-safety validate, deploy to **testnet**, verify on **Blockscout**, publish addresses + explorer links in **PR comment** and **Step Summary**, and upload **deployment artifacts**.
* **On merge/push to `main`:** run the same pipeline against **mainnet (configurable)** under a protected environment. The job must not change the production proxy’s implementation. It deploys a new implementation only. All production upgrades remain manual and explicit.
* **Upgrade-safety validation** runs on every pull request. Snapshot formatting & tracking (flatten → baseline) happens only after a push to `dev`.
* **Repeatability & Reusability:** all CI/CD steps are packaged into a reusable composite GitHub Action. Repos only need thin YAML wrappers that call this action with network/environment inputs.
* **Artifact schema:** every deployment emits one JSON containing, per contract:`sourcePathAndName`, `address`.
* **Secrets & environments (per-repo):** Each repository owns its GitHub Environments and secrets.

---

## 3. Scope and Approaches

### Non-Goals

* Automatic continuous upgrades of production on every commit (we deploy on `main` merges, not continuously).
* Updating the production proxy implementation automatically on every merge. Production upgrades remain manual/explicit.
* Extensive security auditing (we only include upgrade-safety & verification checks here).
* Custom proxy logic or upgrade frameworks — we rely directly on **OpenZeppelin (OZ) libraries** for ProxyAdmin and TransparentUpgradeableProxy patterns.
* Changing ProxyAdmin ownership or production proxy state via CI (out of scope).
* On-chain migrations or data transforms (out of scope).
* UUPS proxy pattern is out of scope. Only Transparent Proxy is supported.
* On testnet, current behavior is to re-deploy fresh proxies and implementations on each PR to `main`. Upgrade-in-place for testnet may be introduced later as a configurable option but is out of scope for this MVP.

### Technical Functionality / Off-Scope Reasoning / Tradeoffs

| Technical Functionality      | Reasoning for being off scope                           | Tradeoffs                                              |
| ---------------------------- | ------------------------------------------------------- | ------------------------------------------------------ |
| Automated prod rollback      | Requires on-chain state awareness and migration tooling | Manual rollback plan only (documented below)           |
| Canary/mainnet shadow deploy | Adds cost & complexity                                  | Keep pipeline lean; rely on testnet for pre-prod       |
| Multi-network matrix         | Increases flakiness and runtime                         | Start with two networks, expand later                  |
| Etherscan verification       | Etherscan/Etherscan based explorers are inconsistent and require API keys | No API key needed and all EVM chains supported through one API that's open source and self hostable |

### Value Proposition

| Technical Functionality      | Value                                   | Tradeoffs                                    |
| ---------------------------- | --------------------------------------- | -------------------------------------------- |
| Upgrade-safety validation    | Prevents breaking upgrades              | Requires keeping flattened snapshots current |
| Auto-deploy on PR (testnet)  | Frontend unblock, end-to-end validation | Funds & RPC cost on testnet                  |
| Auto-deploy on main (configurable) | Consistent prod releases                | Needs strong environment protection & keys   |
| Blockscout verification      | Public, fast verification               | Blockscout indexing variability              |
| Deployment artifacts (JSON)  | Single source of truth for frontends    | Must keep schema stable                      |
| PR comments + step summary   | High visibility, easy review            | Slightly more CI scripting                   |
| Upgradeable deployments (proxy)   | Safe, repeatable upgrades; production proxy untouched by default | Additional moving parts (proxy admin, impl); stricter validation needed |

### Alternative Approaches

| Approach                                     | Pros                   | Cons                                          |
| -------------------------------------------- | ---------------------- | --------------------------------------------- |
| Single monolithic workflow with conditionals | Fewer files            | Harder to read/maintain; more branching logic |
| Hardhat instead of Foundry                   | Familiar to some teams | Slower builds; mixed tooling                  |
| Keep Etherscan for testnet                   | Familiar UX            | Split verification logic; higher maintenance  |
| Manual-only deploys                          | Safety                 | Slower feedback, prone to human error         |

---

## 4. Step-by-Step Flow

### 4.0 Upgrade-Safety & Snapshot Policy (Authoritative)

**Triggers**

* **Upgrade-safety job runs on**:

  * `workflow_dispatch`
  * any `push`
  * `pull_request` where **base** ∈ {`dev`,`main`} **or** `head`/`base` contains `'release'`
* **Flatten & auto-commit job runs only on**:

  * `push` to `dev` (not PRs, not `main`), **after** tests and upgrade-safety pass

**Upgrade-safety behavior**

1. `forge clean && forge build`
2. Build current snapshot (contracts from `run-latest.json`) into `upgrades/snapshots/current/*.sol`. The list of contracts to snapshot/flatten is read from `broadcast/**/run-latest.json`. 
3. If `upgrades/snapshots/baseline/*.sol` exists, run `script/upgrades/ValidateUpgrade.s.sol`.
   Else → mark Baseline Missing and follow the init policy below.

On push to `dev` (after build/tests pass), if baseline is missing:

* Copy `upgrades/snapshots/current/*` → `upgrades/snapshots/baseline/*`
* Auto-commit: `chore: init upgrade baseline [skip ci]`
* On PRs when baseline is missing: don't fail; warning in the Step Summary ("Baseline missing — will auto-init on first merge to dev").


**Snapshot/flatten behavior (dev-only)**

1. Flatten -> `upgrades/snapshots/current/*.sol` (contracts from `run-latest.json`)
2. Promote baseline:
   - If baseline exists: copy baseline -> previous
   - Copy current -> baseline
3. **Auto-commit** changes under `upgrades/snapshots/**/*.sol` with message
   `chore: auto-flatten contracts after validation passes [skip ci]`

### 4.1 Main (“Happy”) Paths

#### Path A — PR to `main` (Testnet)

**Pre-condition:** PR opened or updated targeting `main`; secrets configured; deploy wallet funded on the selected **testnet**.

1. **CI triggers** on `pull_request` to `main`.
2. **Checkout repo**; install Foundry; forge install; build; test
3. **Upgrade-safety validation** runs (`forge build`; check `upgrades/snapshots/previous`; run `script/upgrades/ValidateUpgrade.s.sol` if present).
4. **Deploy (upgradeable, re-deploy fresh)** via `forge script` (entry: `script/Deploy.s.sol:Deploy`) to the selected testnet. Current behavior: each run creates a new ProxyAdmin, implementation, and proxy (fresh addresses). Secrets: `TESTNET_PRIVATE_KEY`, `TESTNET_RPC_URL`.
5. **Parse deployed addresses** from Foundry’s broadcast artifact.
6. **Verify** each contract on **Blockscout** (**testnet**) with correct compiler metadata & constructor args; wait for indexing (sleep with backoff).
7. **Summarize** in `$GITHUB_STEP_SUMMARY` (Markdown table with explorer links).
8. **Save artifacts** to `deployments/testnet/deployment.json` including, for each contract: `sourcePathAndName`, `address`.
9. **Comment on PR** with addresses + links.
   **Post-condition:** PR contains validated, verified testnet deployment with artifacts.

**Fail-fast policy:** Any failure in build, tests, upgrade-safety, deploy, verify, or artifact steps fails the workflow and blocks subsequent dependent jobs.

#### Path B — Push/Merge to `main` (Mainnet)

**Pre-condition:** Protected `production` environment (optional manual approval); deploy wallet funded on the selected **mainnet**.

1. **CI triggers** on `push` to `main`.
2. Same steps 2–3 as Path A.
3. **Deploy (implementation-only)** via `forge script` (entry: `script/Deploy.s.sol:Deploy`) to deploy a new implementation contract on mainnet. Do not deploy/upgrade any proxy and do not modify ProxyAdmin. Output the implementation address only.
4. **Parse broadcast artifact** (`run-latest.json`) for addresses, **verify on Blockscout (mainnet)**, **summarize**, and write `deployments/mainnet/deployment.json` with `{ sourcePathAndName, address }` per contract.

#### Upgrade-safety — Required checks (must pass)

All upgrade-safety validations are inherited directly from the **OpenZeppelin Upgrades Foundry plugin**  
(`@openzeppelin/foundry-upgrades`). The CI simply runs these checks to ensure storage layout compatibility,
initializer safety, and transparent proxy semantics before deployment.

### 4.2 Alternate / Error Paths

| #  | Condition                       | System Action                | Suggested Handling                                                                                |
| -- | ------------------------------- | ---------------------------- | ------------------------------------------------------------------------------------------------- |
| A1 | Missing secrets                 | Job fails early              | Fail fast with clear log; doc required secrets                                                    |
| A2 | RPC outage / rate limit         | Deploy/verify step fails     | Auto-retry (limited), otherwise fail with guidance                                                |
| A3 | Blockscout indexing slow        | Verify timeouts              | Bounded backoff (e.g., 3 attempts). If still pending, mark “Verification pending” in summary and succeed the job. |
| A4 | Upgrade-safety fails            | Block deploy jobs            | Mark PR red; link to diff and validator logs                                                      |
| A5 | Foundry toolchain install error | Build step fails             | Re-run workflow; pin known-good versions                                                          |
| A6 | Parsing broadcast artifact fails| Missing addresses in outputs | Fail with a clear message and attach `broadcast/*/run-latest.json`                                |
| A7 | Artifact upload fails           | Missing artifacts in run     | Re-upload step; store to workspace before upload                                                  |
| A8 | No `upgrades/snapshots/baseline/*.sol` baseline | Validator skipped | Log as “initial deployment”; baseline will be set on next successful `dev` push                  |
| A9 | Creation bytecode prefix mismatch | Constructor-arg extraction fails | Ensure CI uses `bytecode_hash="none"` and `cbor_metadata=false`; recompile and retry |

---

## 5. UML Diagrams

```mermaid
sequenceDiagram
  autonumber
  participant Dev as Developer
  participant GH as GitHub Actions
  participant RPC as RPC (testnet/mainnet)
  participant BS as Blockscout API

  Dev->>GH: Open PR to main / Push to main / Push to dev
  GH->>GH: Checkout, Install Foundry, Build, Test
  GH->>GH: Upgrade Safety Validation (build + check snapshots)
  alt previous snapshots present
    GH->>GH: forge script script/upgrades/ValidateUpgrade.s.sol
    note right of GH: OpenZepplin upgrade safety plugin validations
    alt validation OK
      GH-->>GH: status = pass
    else validation FAIL
      GH-->>GH: status = fail (block deployment)
    end
  else no snapshots (initial deployment)
    GH-->>GH: skip validator (log message)
  end

  opt Push to dev (not PR/main) & checks passed
    GH->>GH: Parse broadcast/**/run-latest.json (authoritative contract list)
    GH->>GH: Flatten listed contracts to upgrades/snapshots/current/*.sol
    GH->>GH: Copy baseline to previous
    GH->>GH: Copy current to baseline
    GH-->>Dev: Auto-commit snapshots [skip ci]
  end

  alt PR -> Testnet
    GH->>RPC: forge script --broadcast (Testnet)
  else Push -> Mainnet
    note over GH: Implementation-only (no proxy/ProxyAdmin changes)
    GH->>RPC: forge script --broadcast
  end

  GH->>GH: Parse broadcast/**/run-latest.json to {sourcePathAndName, address}
  GH->>BS: verify-contract (per module) with constructor args
  BS-->>GH: Verification OK / pending (bounded backoff)
  GH-->>Dev: PR Comment / Step Summary with explorer links
```

```mermaid
stateDiagram-v2
  [*] --> Flatten
  [*] --> Deploy : PR to main OR Push to main

  Flatten: Read broadcast/**/run-latest.json<br/>Derive contract list<br/>Flatten to upgrades/snapshots/current/*.sol
  Flatten --> Promote : baseline exists
  Flatten --> InitBaseline : baseline missing

  Promote: prepare baseline replacement
  Promote --> CopyPrev : copy baseline to previous
  CopyPrev --> ReplaceBaseline : copy current to baseline
  ReplaceBaseline --> CommitUpdate
  CommitUpdate: auto-flatten after validation (skip ci)
  CommitUpdate --> [*]

  InitBaseline: init baseline from current
  InitBaseline --> CommitInit
  CommitInit: init upgrade baseline (skip ci)
  CommitInit --> [*]

  Deploy: Deploy via forge script<br/>to testnet/mainnet
  Deploy --> Verify
  Verify: Blockscout verification<br/>write deployments/{network}/deployment.json<br/>PR comment + step summary
  Verify --> [*]
```

---

## 6. Edge cases and concessions

* **Blockscout indexing lag**: we add waits/backoff. Verification may be marked as “pending” in summary and retried by re-running workflow.
* CI compiles with `bytecode_hash = "none"` and `cbor_metadata = false` to avoid metadata-hash drift. These must also be the repo’s compiler settings. As part of the pipeline, we validate that the artifact bytecode is a prefix of the deployment input; if not, the job fails with a metadata-mismatch hint and CI/CD is marked failed.
* **Gas handling**: rely on provider-estimated gas and use `--slow` to avoid nonce/rate issues. No manual gas-price override in MVP.

---

## 7. Glossary / References

* **Foundry** — Ethereum toolkit: `forge` (build/test/deploy/verify) and `cast` (RPC/ABI).
  Docs: [Foundry Book – Deploying](https://getfoundry.sh/forge/deploying).

* **OpenZeppelin (OZ)**

  * Libraries: [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) (see TransparentUpgradeableProxy & ProxyAdmin).
  * Foundry upgrades plugin: [@openzeppelin/foundry-upgrades](https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades) (we inherit its checks).

* **Blockscout** — Open-source explorer & verification API used for testnet/mainnet verification.
  Repo: [blockscout/blockscout](https://github.com/blockscout/blockscout)

* **Upgrade-safety validation** — We inherit checks from OZ Foundry Upgrades.
  Example in our org: Breadchain workflow reference (validator step):
  [https://github.com/BreadchainCoop/breadchain/blob/fa7dfc15fd8cc2424d28ce8c659c53551ade6174/.github/workflows/test.yml#L50](https://github.com/BreadchainCoop/breadchain/blob/fa7dfc15fd8cc2424d28ce8c659c53551ade6174/.github/workflows/test.yml#L50)

* **Reference CI templates** — Real-world workflows that (a) deploy to testnet on PR, (b) mainnet on merge to `main`, and (c) verify contracts:
  [https://github.com/communetxyz/commune-os-sc/tree/main/.github/workflows](https://github.com/communetxyz/commune-os-sc/tree/main/.github/workflows)

* **Deployment artifacts** — Canonical JSON stored under `deployments/{network}/deployment.json` with per-contract metadata used by frontends.

* **GitHub Environments** — Protected contexts (`testnet`, `production`) holding secrets (RPC URLs, private keys) and optional manual approvals.
