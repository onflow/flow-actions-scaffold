# Quick Checklist

## Imports
- Use `import "ContractName"` format only.
- Include all required contract imports.

## Transaction Order (readability)
- **CRITICAL**: Write blocks in this order: `prepare` → `pre` → `post` → `execute`. Never use `prepare` → `execute` → `post`.
- Let reviewers grasp setup and guarantees before execution logic.

## Preconditions/Postconditions
- Single boolean expression per pre/post block.
- Use `assert()` for multi-step validation in execute.

## Capabilities & Addresses
- Validate capabilities before use.
- Pass addresses as parameters only when you must resolve third-party capabilities directly.
- Prefer connector helpers (e.g., `borrowPool(pid:)`) over manual address resolution.

## Resource Safety
- Always ensure `vault.balance == 0.0` before `destroy`.
- Use `withdrawAvailable` and `depositCapacity` (never raw deposit paths).

## Build the Chain (Restake)
- **Instantiate explicitly**: Create each connector separately with descriptive names and comments.
- Source: `PoolRewardsSource(userCertificate, pid)`
- Swapper: `Zapper(token0Type: derived token0 from pair, token1Type: derived token1 from pair, stableMode: pair.isStableswap)` **Note**: Reverse token order if `rewardsSource.getSourceType() != token0Type` (reward token should be token0, the input)
- Wrap: `SwapConnectors.SwapSource(swapper, source)`
- Sink: `PoolSink(pid: pid, staker: userAddress)`
- Unique ID: Create once (`operationID = DeFiActions.createUniqueIdentifier()`) and pass to all components.

## Validate
- `source.minimumAvailable() > 0.0`
- `sink.minimumCapacity() > 0.0`
- Post: `newStake >= startingStake + expectedStakeIncrease`

## Inheritance sanity (for new connectors)
- If implementing `Source`, `Sink`, or `Swapper`, include:
  - `access(contract) var uniqueID: DeFiActions.UniqueIdentifier?`
  - `access(all) fun getComponentInfo(): DeFiActions.ComponentInfo`
  - `access(contract) view fun copyID(): DeFiActions.UniqueIdentifier?`
  - `access(contract) fun setID(_ id: DeFiActions.UniqueIdentifier?)`
- Reference: [`interface-inheritance.md`](./interface-inheritance.md)

## Test
- Zero amounts and `UFix64.max`
- Invalid capabilities
- Inactive pool
- Post-condition using computed `expectedStakeIncrease`

## Links
- Restake Workflow: [`workflows/restaking-workflow.md`](./workflows/restaking-workflow.md)
- Transaction Template: [`transaction-templates.md`](./transaction-templates.md#complete-restaking-workflow)
- Connectors: [`connectors.md`](./connectors.md)
- Agent Guide: [`ai-generation-guide.md`](./ai-generation-guide.md)
