# Technical Spec — Auto CI/CD: Testnet & Mainnet Deployments (Foundry + Blockscout)

## 1. Background

### Problem Statement: What hurts today?

* Manual, inconsistent deployments of smart contracts across environments.
* Frontend team might be blocked by contract deployment details.
* Risky upgrades without automated safety checks.
* Fragmented verification (Etherscan vs Blockscout) and inconsistent artifacts/summaries.

### Context / History

* Current repo uses Foundry for build/test and deploy scripts (`forge script`).
* Reference workflows provided for:

  * **Holesky Testnet** deploy on PR to `main`.
  * **Gnosis Mainnet** deploy on push to `main`.
  * **Upgrade safety validation** via flattened previous/current contracts and `script/upgrades/ValidateUpgrade.s.sol`.
  * **Flattening** step to persist contract snapshots to `test/upgrades/previous`.
  * Deployment scripts are standardized around `script/Deploy.s.sol` (entry point).
* Direction: **adopt Blockscout verification** and **drop Etherscan** support.
* Intended to be reused across multiple repos; not for continuous auto-upgrades of production, but to guarantee end-to-end deployability and unblock frontends.

### Stakeholders

* **Smart Contracts Team** — authors of contracts and deployment scripts.
* **Frontend Team** — consume deployed addresses and ABIs; should not manage deployment complexity.
* **DevOps** — maintain GitHub Actions, secrets, and environment protections.

---

## 2. Motivation

### Goals & Success Stories

* **On every PR to `main`:** build, test, upgrade-safety validate, deploy to **Holesky**, verify on **Blockscout**, publish addresses + explorer links in **PR comment** and **Step Summary**, and upload **deployment artifacts**.
* **On merge/push to `main`:** run the same pipeline against Gnosis mainnet under a protected environment. The job must not change the production proxy’s implementation. It may deploy a new implementation or a separate staging proxy for validation. All production upgrades remain manual and explicit.
* **Upgrade-safety validation** runs on pushes to dev/main, PRs to/from branches with 'release' or to dev/main, or manual trigger. This is to prevent unsafe upgrades before they hit production.
* **Frontend enablement:** a single, consistent JSON artifact + step summary table so frontends can spin up with new addresses automatically.
* **Repeatability:** workflows are copy/paste-able across repos with minimal variable changes.
* **Artifact schema:** every deployment emits one JSON containing, per contract: `name`, `address`, `sourcePath`, `kind` (`proxy` | `implementation` | `standalone`), and `{ "proxyAdmin": "...", "implementation": "...", "txHash": "...", "chainId": number }`.

---

## 3. Scope and Approaches

### Non-Goals

* Automatic continuous upgrades of production on every commit (we deploy on `main` merges, not continuously).
* Updating the production proxy implementation automatically on every merge. Production upgrades remain manual/explicit.
* Extensive security auditing (we only include upgrade-safety & verification checks here).
* Changing ProxyAdmin ownership or production proxy state via CI (out of scope).
* On-chain migrations or data transforms (out of scope).

### Technical Functionality / Off-Scope Reasoning / Tradeoffs

| Technical Functionality      | Reasoning for being off scope                           | Tradeoffs                                              |
| ---------------------------- | ------------------------------------------------------- | ------------------------------------------------------ |
| Automated prod rollback      | Requires on-chain state awareness and migration tooling | Manual rollback plan only (documented below)           |
| Canary/mainnet shadow deploy | Adds cost & complexity                                  | Keep pipeline lean; rely on Holesky for pre-prod       |
| Multi-network matrix         | Increases flakiness and runtime                         | Start with two networks, expand later                  |
| Etherscan verification       | Direction is Blockscout standardization                 | One verifier reduces variance; Etherscan features lost |

### Value Proposition

| Technical Functionality      | Value                                   | Tradeoffs                                    |
| ---------------------------- | --------------------------------------- | -------------------------------------------- |
| Foundry build/test on CI     | Early failure detection                 | Longer CI runtime                            |
| Upgrade-safety validation    | Prevents breaking upgrades              | Requires keeping flattened snapshots current |
| Auto-deploy on PR (Holesky)  | Frontend unblock, end-to-end validation | Funds & RPC cost on testnet                  |
| Auto-deploy on main (Gnosis) | Consistent prod releases                | Needs strong environment protection & keys   |
| Blockscout verification      | Public, fast verification               | Blockscout indexing variability              |
| Deployment artifacts (JSON)  | Single source of truth for frontends    | Must keep schema stable                      |
| PR comments + step summary   | High visibility, easy review            | Slightly more CI scripting                   |
| Upgradeable deployments (proxy)   | Safe, repeatable upgrades; production proxy untouched by default | Additional moving parts (proxy admin, impl); stricter validation needed |

### Alternative Approaches

| Approach                                     | Pros                   | Cons                                          |
| -------------------------------------------- | ---------------------- | --------------------------------------------- |
| Single monolithic workflow with conditionals | Fewer files            | Harder to read/maintain; more branching logic |
| Hardhat instead of Foundry                   | Familiar to some teams | Slower builds; mixed tooling                  |
| Keep Etherscan for Holesky                   | Familiar UX            | Split verification logic; higher maintenance  |
| Manual-only deploys                          | Safety                 | Slower feedback, prone to human error         |

### Relevant Metrics

* **Pipeline success rate** (per workflow).
* **Median deploy + verify time** (per network).
* **Verification success rate** (Blockscout API).
* **Incidents: failed upgrade-safety checks** (trend).
* **Artifact adoption** (downloads/references by frontend).
* **Flakiness**: rerun rate on CI.

---

## 4. Step-by-Step Flow

### 4.1 Main (“Happy”) Paths

#### Path A — PR to `main` (Holesky Testnet)

**Pre-condition:** PR opened or updated targeting `main`; secrets configured; deploy wallet funded on Holesky.

1. **CI triggers** on `pull_request` to `main`.
2. **Checkout** repo with submodules; **Install Foundry**; **forge install**; **forge build**; **forge test -vvv**.
3. **Upgrade-safety validation** runs (`forge build`; check `test/upgrades/previous`; run `script/upgrades/ValidateUpgrade.s.sol` if present).
4. **Deploy (upgradeable)** via `forge script` (entry: `script/Deploy.s.sol:DeployScript`) using a proxy pattern (UUPS/Transparent). Create or upgrade a testnet proxy but never touch mainnet production proxy. Secrets: `TESTNET_PRIVATE_KEY`, `HOLESKY_RPC_URL`.
5. **Parse deployed addresses** from script output into `GITHUB_OUTPUT`.
6. **Verify** each contract on **Blockscout** (Holesky) with correct compiler metadata & constructor args; wait for indexing (sleep with backoff).
7. **Summarize** in `$GITHUB_STEP_SUMMARY` (Markdown table with explorer links).
8. **Save artifacts** to `deployments/holesky/deployment.json` including, for each contract: `address`, `contractName`, `sourcePath`.
9. **Comment on PR** with addresses + links.
   **Post-condition:** PR contains validated, verified Holesky deployment with artifacts.

#### Path B — Push/Merge to `main` (Gnosis Mainnet)

**Pre-condition:** Protected `production` environment (optional manual approval); deploy wallet funded on Gnosis.

1. **CI triggers** on `push` to `main`.
2. Same steps 2–3 as Path A.
3. **Deploy (non-disruptive & upgradeable)** via `forge script` (entry: `script/Deploy.s.sol:DeployScript`) to Gnosis with `GNOSIS_PRIVATE_KEY`, `GNOSIS_RPC_URL`. Deploy a staging proxy+implementation or deploy a new implementation only for upgrade validation. Do not point the production proxy to the new implementation automatically.
4. **Parse outputs**, **verify on Blockscout (Gnosis)**, **summarize**, and write `deployments/gnosis/deployment.json` with `address`, `contractName`, `sourcePath` per contract.

### 4.2 Alternate / Error Paths

| #  | Condition                       | System Action                | Suggested Handling                                                                                |
| -- | ------------------------------- | ---------------------------- | ------------------------------------------------------------------------------------------------- |
| A1 | Missing secrets                 | Job fails early              | Fail fast with clear log; doc required secrets                                                    |
| A2 | RPC outage / rate limit         | Deploy/verify step fails     | Auto-retry (limited), otherwise fail with guidance                                                |
| A3 | Blockscout indexing slow        | Verify timeouts              | Bounded backoff (e.g., 3 attempts). If still pending, mark “Verification pending” in summary and succeed the job. |
| A4 | Upgrade-safety fails            | Block deploy jobs            | Mark PR red; link to diff and validator logs                                                      |
| A5 | Foundry toolchain install error | Build step fails             | Re-run workflow; pin known-good versions                                                          |
| A6 | Submodule fetch error           | Checkout fails               | Ensure `submodules: recursive`; fallback to `fetch-depth: 0`                                      |
| A7 | Gas/nonce issues                | Broadcast fails              | Use `--slow` and clean nonce; document funding and nonce hygiene                                  |
| A8 | Parsing deploy output fails     | Missing addresses in outputs | Fail with a clear message and dump raw `forge script` output for triage.                          |
| A9 | Artifact upload fails           | Missing artifacts in run     | Re-upload step; store to workspace before upload                                                  |

---

## 5. UML Diagrams

```mermaid
sequenceDiagram
   autonumber
   participant Dev as Developer
   participant GH as GitHub Actions
   participant RPC as RPC (Holesky/Gnosis)
   participant BS as Blockscout API
   participant ART as Artifact Store

   Dev->>GH: Open PR to main / Push to main
   GH->>GH: Checkout, Install Foundry, Build, Test
   GH->>GH: Upgrade Safety Validation
   alt PR -> Holesky
     GH->>RPC: forge script --broadcast (Holesky)
   else Push -> Gnosis
     GH->>RPC: forge script --broadcast (Gnosis)
   end
   RPC-->>GH: Tx receipts + contract addresses
   GH->>BS: verify-contract (per module)
   BS-->>GH: Verification OK
   GH->>ART: Upload deployment.json
   GH-->>Dev: PR Comment / Step Summary with links
```

```mermaid
stateDiagram
   [*] --> Pending
   Pending --> Building : checkout/install/build/test
   Building --> Validating : upgrade-safety
   Validating --> Deploying : ok
   Validating --> Failed : validation error
   Deploying --> Verifying : addresses parsed
   Deploying --> Failed : broadcast error
   Verifying --> Publishing : verification OK/partial
   Verifying --> Publishing : continue-on-error (flagged)
   Publishing --> Succeeded
   Failed --> [*]
   Succeeded --> [*]
```

```mermaid
classDiagram
class DeploymentArtifact {
  +network: string
  +chainId: number
  +timestamp: ISO8601
  +deployer: string
  +gitCommit: string
  +contracts: ContractEntry[]
}
class ContractEntry {
  +contractName: string
  +sourcePath: string  // e.g. "src/CommuneOS.sol:CommuneOS"
  +address: address
  +kind: string        // "proxy" | "implementation" | "standalone"
}
class UpgradeSnapshots {
  +previous: /test/upgrades/previous/*.sol
  +current:  /test/upgrades/current/*.sol
}
DeploymentArtifact --> ContractEntry : includes
DeploymentArtifact --> UpgradeSnapshots : produced after validation
```

---

## 5. Edge cases and concessions

* **Blockscout indexing lag**: we add waits/backoff. Verification may be marked as “pending” in summary and retried by re-running workflow.
* **Constructor args**: pulled via `cast abi-encode` from network config (`config/holesky.json`, `config/gnosis.json`). Any schema drift breaks verification.
* **Compiler version**: must extract from artifact metadata to avoid “bytecode mismatch”.
* **Flatten snapshots**: Only top-level contracts in `src/`. Nested contracts or libs require explicit inclusion if needed by validator.
* **Gas spikes**: `--slow` and realistic gas price; can add `--with-gas-price` override via env if necessary.
* **Multiple repos**: Paths and names must be parameterized; we’ll centralize runner snippets where possible.

---

## 6. Open Questions

1. **Environment protections**: Do we require manual approval for `production`? Who are approvers?
2. **Wallet management**: Custody of `GNOSIS_PRIVATE_KEY` & `TESTNET_PRIVATE_KEY` (rotation cadence, funding, policy)?
3. **RPC providers**: Which providers (rate limits/SLA)? Fallback RPC?
4. **Artifact schema**: Do frontends need ABI pointers/hashes in `deployment.json`? Add `abiPaths`?
5. **Partial verification**: If some modules verify and others are pending, do we block the run or allow success with warnings?
6. **Static analysis**: Do we integrate `slither`/`solhint` gates now or later?
7. **Upgrade validator inputs**: Any proxies/initializers that require special handling in `ValidateUpgrade.s.sol`?
8. **Proxy pattern:** Use Transparent Proxy for now (UUPS allowed per-repo but must pass the same upgrade-safety checks)?
9. **Staging vs production separation:** Default to deploying a staging proxy or new impl address on mainnet without wiring it to the production proxy?
10. **Artifact granularity:** do we store both proxy and implementation entries for every upgrade, with kind?

---

## 7. Glossary / References

* **Foundry** — Ethereum development toolkit providing `forge` (build, test, deploy, verify) and `cast` (RPC and ABI utilities).
* **Blockscout** — Open-source block explorer and verification API used for both Holesky and Gnosis networks (replaces Etherscan in CI/CD).
* **Upgrade-safety validation** — CI step that compares flattened previous vs current contract sources and runs `script/upgrades/ValidateUpgrade.s.sol` to detect unsafe storage or proxy changes before deployment.
* **Deployment artifacts** — Canonical JSON outputs stored under `deployments/{network}/deployment.json`, containing deployed contract addresses, source paths, and metadata consumed by frontends.
* **GitHub Environments** — Protected configuration contexts (`testnet`, `production`) that store secrets (RPC URLs, private keys) and can require manual approvals for mainnet deployments.