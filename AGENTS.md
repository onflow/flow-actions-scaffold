# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, Cursor, Copilot, and others) working in
this repository. Loaded into agent context automatically — keep edits concise.

## Overview

Scaffold for building Cadence transactions with [Flow Actions](https://github.com/onflow/flips/pull/339)
(FLIP-338) and IncrementFi connectors. Ships one worked example — claim IncrementFi LP rewards,
zap them to LP tokens, and restake into the same pool — plus a minimal `DeFiActions.Sink`
connector (`ExampleConnectors.TokenSink`) and an automated emulator bootstrap that creates
mock tokens, a swap pair, and a staking pool. No Cadence test files exist in the repo yet.

## Build and Test Commands

All commands are defined in `Makefile` and `scripts/start.sh`. Run `flow deps install` once
after clone before any other command.

- `make start` (alias `make emulator`) — runs `scripts/start.sh`: starts emulator, deploys
  contracts, creates TokenA-TokenB pair (100k each), seeds staking pool `#0` with 50k LP
  tokens and 10k TokenA rewards. Blocks in foreground; Ctrl+C to stop.
- `make deploy` — `flow project deploy --network $(NETWORK)`. Override with
  `make deploy NETWORK=testnet` or `NETWORK=mainnet`. Default `NETWORK=emulator`.
- `make test` — `flow test`. Note: `cadence/tests/` does not exist yet; this runs zero tests
  until test files are added.
- `flow deps install` — install dependencies declared in `flow.json` (required after clone).

Example script/transaction invocations (from `README.md`):

```bash
flow scripts execute cadence/scripts/get_available_rewards.cdc --network emulator \
  --args-json '[{"type":"Address","value":"0xf8d6e0586b0a20c7"},{"type":"UInt64","value":"0"}]'

flow transactions send cadence/transactions/increment_fi_restake.cdc \
  --signer emulator-account --network emulator \
  --args-json '[{"type":"UInt64","value":"0"}]'
```

## Architecture

```
flow.json                                    Project config: contracts, deps, accounts, deployments
Makefile                                     start / emulator / deploy / test targets
scripts/start.sh                             Emulator + IncrementFi bootstrap orchestrator
scripts/transactions/                        Helper txs used by start.sh (not shipped contracts)
  deploy_contract.cdc
  fungible-tokens/{mint_tokens,setup_generic_vault}.cdc
  increment-fi/{add_liquidity,create_staking_pool,create_swap_pair,
                deploy_swap_pair,deposit_staking_pool,setup_staking_certificate}.cdc
cadence/contracts/ExampleConnectors.cdc      TokenSink — minimal DeFiActions.Sink impl
cadence/contracts/mock/{TokenA,TokenB,TestTokenMinter}.cdc   Emulator-only mock tokens
cadence/scripts/get_available_rewards.cdc    Reads PoolRewardsSource.minimumAvailable()
cadence/transactions/increment_fi_restake.cdc  Claim -> Zap -> Restake worked example
.cursor/rules/defi-actions/                  Authoring rules for Flow Actions composition
```

Mainnet and testnet `deployments` in `flow.json` ship only `ExampleConnectors` — all other
IncrementFi, DeFiActions, SwapConnectors, FlowEVMBridge, and token contracts are consumed via
`dependencies.aliases` from their canonical deployments. The emulator `deployments` list
re-deploys the full dependency set locally.

## Conventions and Gotchas

- **String-based imports only.** Transactions and contracts use `import "Name"` (see
  `cadence/transactions/increment_fi_restake.cdc` lines 1–6, `ExampleConnectors.cdc` lines
  13–14). Addresses come from `flow.json` — do not hard-code them in `.cdc` files.
- **Emulator service account is `0xf8d6e0586b0a20c7`** (`flow.json` → `accounts.emulator-account`).
  `scripts/start.sh` and example commands assume this.
- **`testing` network aliases are split**: DeFiActions/IncrementFi/bridge contracts use
  `0x0000000000000007`; Staking/Swap* core contracts use `0x0000000000000008`. See `flow.json`
  `dependencies.*.aliases.testing`. Keep this split when adding new dependencies for tests.
- **Restake transaction invariants** (pattern to follow when composing new Flow Actions txs,
  from `cadence/transactions/increment_fi_restake.cdc`): size withdrawals by sink capacity
  (`swapSource.withdrawAvailable(maxAmount: poolSink.minimumCapacity())`), assert residuals
  (`assert(vault.balance == 0.0, message: "Residual after deposit")`), and use a single
  `DeFiActions.createUniqueIdentifier()` threaded through every connector for tracing.
- **Restake post-condition** uses `zapper.quoteOut(...).outAmount` as the expected stake
  delta. Any new composed transaction should follow the same pre/post-check shape.
- **Pool ID `0`** is the pool `scripts/start.sh` creates on emulator; README examples assume
  it. Real testnet/mainnet pool IDs come from the IncrementFi Farms UI.
- **User certificate required** on testnet/mainnet before `increment_fi_restake.cdc` will
  work — README links the `run.dnz.dev` snippet to create `Staking.UserCertificate`.
- **Authoring rules** in `.cursor/rules/defi-actions/` (`core-framework.md`, `safety-rules.md`,
  `patterns.md`, `transaction-templates.md`, etc.) document the Flow Actions composition
  model. Consult them before generating new connectors or composed transactions.

## Files Not to Modify

- `*.pkey` (gitignored) — private key files; never commit.
- `imports/` (gitignored) — populated by `flow deps install`; regenerate, don't edit.
- `.emulator.log` — runtime log from `make start`.
- `cadence/contracts/mock/` — emulator-only mock tokens wired into `scripts/start.sh`
  with hard-coded storage paths (`tokenAAdmin`, `tokenAReceiver`, `tokenBAdmin`,
  `tokenBReceiver`); renaming breaks the bootstrap.
