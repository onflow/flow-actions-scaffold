# Cursor Agent Rules

> NOTE: Extended reference for agents and reviewers. The single canonical entry point is [`ai-generation-entrypoint.mdc`](./ai-generation-entrypoint.mdc). Start there for generation; use this page for deeper rationale and expanded guidance.

These rules guide AI agents to generate correct, safe Cadence transactions using DeFiActions connectors.

## Quick Entry
- Pasteable rules for `.cursor/rules`: [ai-generation-entrypoint.mdc](./ai-generation-entrypoint.mdc)
- Canonical restake workflow: [workflows/restaking-workflow.md](./workflows/restaking-workflow.md)
- Connectors overview: [connectors.md](./connectors.md)
- Composition patterns: [composition.md](./composition.md)
- Transaction templates: [transaction-templates.md](./transaction-templates.md)
- Checklist: [quick-checklist.md](./quick-checklist.md) • Safety: [safety-rules.md](./safety-rules.md)
- Inheritance reference: [interface-inheritance.md](./interface-inheritance.md)

## Goal Translation
- Map prompts to a connector chain.
  - Restake rewards: `PoolRewardsSource -> SwapSource(Zapper) -> PoolSink`.
- Derive token types and mode from the staking pool pair; do not add parameters:
  - Use `IncrementFiStakingConnectors.borrowPairPublicByPid(pid)` and `tokenTypeIdentifierToVaultType`.
  - Use `pair.getPairInfoStruct().isStableswap` for `stableMode`.
- For direct pool prompts (e.g., “restake for pool #198”), you may hardcode `let PID: UInt64 = 198` in the transaction and use it consistently for auditability.

## Imports
Always use string imports:
```cadence
import "FungibleToken"
import "DeFiActions"
import "SwapConnectors"
import "IncrementFiStakingConnectors"
import "IncrementFiPoolLiquidityConnectors"
import "Staking"
```

## Transaction Block Order
- **CRITICAL**: Write in this physical order for readability: `prepare` → `pre` → `post` → `execute`. Never use `prepare` → `execute` → `post`.
- Readers can audit inputs and guarantees before scanning execution logic.

## Required Params (Restake)
- `pid: UInt64`

## Transaction Skeleton
- Prepare:
  - Issue `Capability<&Staking.UserCertificate>`.
  - Borrow pool via `IncrementFiStakingConnectors.borrowPool(pid:)` and record `startingStake`.
  - Create `operationID = DeFiActions.createUniqueIdentifier()`.
  - Borrow pair via `IncrementFiStakingConnectors.borrowPairPublicByPid(pid:)` and construct `Zapper` using derived token types and `stableMode`, with `uniqueID: operationID`. **Important**: Check if `rewardsSource.getSourceType() != token0Type` and reverse token order if true (reward token should be token0, the input).
  - Create `PoolRewardsSource(userCertificate, pid, uniqueID: operationID)` and wrap with `SwapConnectors.SwapSource(..., uniqueID: operationID)`.
  - Compute `expectedStakeIncrease` via `zapper.quoteOut(forProvided: rewards.minimumAvailable(), reverse: false)`.
- Execute:
  - `PoolSink(pid: pid, staker: userAddress, uniqueID: operationID)`.
  - Size withdraws by the target sink’s capacity: `withdrawAvailable(maxAmount: poolSink.minimumCapacity())`.
  - Deposit, assert vault empty, destroy.
- Post:
  - Ensure `newStake >= startingStake + expectedStakeIncrease`.

## Safety Invariants
- Pre/post blocks contain single boolean expressions only.
- Use `depositCapacity` and `withdrawAvailable` for graceful handling.
- Verify `vault.balance == 0.0` before `destroy`.
- Do not resolve protocol addresses in transactions if a connector provides helpers.
- Use a single `uniqueID` across composed connectors for traceability.

## Connector Facts
- `IncrementFiStakingConnectors.PoolSink(pid, staker, uniqueID?)` infers `vaultType` from pool.
- `IncrementFiStakingConnectors.PoolRewardsSource(userCertificate, pid, uniqueID?)` outputs inferred reward `vaultType`.
- `IncrementFiPoolLiquidityConnectors.Zapper` is a `Swapper`; use `swap(quote:inVault:)` and `swapBack` as needed. There is no separate `UnZapper` type. **Token Ordering**: When using with a source, ensure the source token becomes token0 (the input) by reversing token order if `source.getSourceType() != token0Type`. Zapper takes token0 as input and pairs it with token1 to create token0:token1 LP tokens.
- `SwapConnectors.SwapSource(swapper, source, uniqueID?)` exposes post-conversion as a `Source`.
- Observed: `Zapper.quoteIn` only supports `UFix64.max`; prefer capacity-driven sizing via `quoteOut` and sink capacities.
- Observed: `MultiSwapper.swap/swapBack` will self-quote if given a non-MultiSwapper quote or `nil`.

## Common Pitfall: Inherited members
- If a struct implements `Source`, `Sink`, or `Swapper`, it inherits from `IdentifiableStruct`. You must implement:
  - `access(contract) var uniqueID: DeFiActions.UniqueIdentifier?`
  - `access(all) fun getComponentInfo(): DeFiActions.ComponentInfo`
  - `access(contract) view fun copyID(): DeFiActions.UniqueIdentifier?`
  - `access(contract) fun setID(_ id: DeFiActions.UniqueIdentifier?)`
- See details and skeletons: [interface-inheritance.md](./interface-inheritance.md)

## Common Variations
- Stable pool: set `stableMode` from pair info.
- Quote-driven caps: prefer `sink.minimumCapacity()`/`source.minimumAvailable()`; avoid manual slippage math.

## Prompt-to-Params Examples
- “Claim stFLOW rewards, swap to FLOW-stFLOW LP, and restake” →
  - `pid = 42`
  - Tokens and `stableMode` are derived from the pool pair; no extra params.

## Code Style
- Use named arguments.
- Keep variable names descriptive: `poolRewardsSource`, `zapper`, `lpTokenPoolRewardsSource`, `poolSink`.
- **Prefer explicit instantiation over nested construction**: Create each connector separately with descriptive names and comments rather than nesting constructors.
- Prefer early returns and minimal nesting inside connector implementations (transactions use assertions instead).
- Write for humans first: add brief comments at the start of each block (`prepare`, `pre`, `post`, `execute`) and before key steps (connector construction, withdraw/deposit, assertions) to explain intent and safety.
- Keep comments focused on "why" and safety context (not restating code mechanics).

## Sanity Checklist
- Imports present and string-based.
- Capability issuance and borrows succeed or `panic` with context.
- Connector inputs/outputs types align: `source.getSourceType()` == `swapper.inType()`, `swapper.outType()` == `sink.getSinkType()` (or rely on `SwapSource` construction preconditions).
- Post-condition guards the intended outcome using computed `expectedStakeIncrease`.

---
See also: [`connectors.md`](./connectors.md), [`composition.md`](./composition.md), [`quick-checklist.md`](./quick-checklist.md), [`workflows/restaking-workflow.md`](./workflows/restaking-workflow.md) 