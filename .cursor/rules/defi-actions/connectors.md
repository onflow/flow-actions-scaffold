# Connectors

## Quick Reference (Restaking)
- Rewards Source: `IncrementFiStakingConnectors.PoolRewardsSource(userCertificate, pid, uniqueID?)`
- Zapper (to LP): `IncrementFiPoolLiquidityConnectors.Zapper(token0Type, token1Type, stableMode, uniqueID?)`
- Swap wrapper: `SwapConnectors.SwapSource(swapper, source, uniqueID?)`
- Staking Sink: `IncrementFiStakingConnectors.PoolSink(pid, staker, uniqueID?)`

Jump to: [`workflows/restaking-workflow.md`](./workflows/restaking-workflow.md)

---

> Note on inheritance: When a connector type says `struct X : DeFiActions.Source`, X must implement all members of `Source` plus the required members of `IdentifiableStruct` because `Source` extends `IdentifiableStruct`. You do NOT list `IdentifiableStruct` again. See [`interface-inheritance.md`](./interface-inheritance.md) for exact required fields and method shapes.

## Helpers (IncrementFi)
- `IncrementFiStakingConnectors.borrowPool(pid: UInt64): &{Staking.PoolPublic}?`
- `IncrementFiStakingConnectors.borrowPairPublicByPid(pid: UInt64): &{SwapInterfaces.PairPublic}?`
- `IncrementFiStakingConnectors.tokenTypeIdentifierToVaultType(_ tokenKey: String): Type`

## FungibleTokenConnectors

### VaultSource
**Purpose**: Withdraws tokens from FungibleToken vault with minimum balance protection.  
**Type**: `struct VaultSource : DeFiActions.Source`  
**Constructor**:
```cadence
FungibleTokenConnectors.VaultSource(
    min: UFix64?,
    withdrawVault: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>,
    uniqueID: DeFiActions.UniqueIdentifier?
)
```

### VaultSink
**Purpose**: Deposits tokens into FungibleToken vault with capacity limits.  
**Type**: `struct VaultSink : DeFiActions.Sink`  
**Constructor**:
```cadence
FungibleTokenConnectors.VaultSink(
    max: UFix64?,
    depositVault: Capability<&{FungibleToken.Vault}>,
    uniqueID: DeFiActions.UniqueIdentifier?
)
```

### VaultSinkAndSource
```cadence
FungibleTokenConnectors.VaultSinkAndSource(
    min: UFix64,
    max: UFix64?,
    vault: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>,
    uniqueID: DeFiActions.UniqueIdentifier?
)
```

## SwapConnectors

### SwapSource
```cadence
SwapConnectors.SwapSource(
    swapper: {DeFiActions.Swapper},
    source: {DeFiActions.Source},
    uniqueID: DeFiActions.UniqueIdentifier?
)
```
Tips:
- Size withdraws by the target sink’s capacity: `withdrawAvailable(maxAmount: sink.minimumCapacity())`.
- `minimumAvailable()` returns an estimate based on `swapper.quoteOut(forProvided: source.minimumAvailable())`.

### SwapSink
```cadence
SwapConnectors.SwapSink(
    swapper: {DeFiActions.Swapper},
    sink: {DeFiActions.Sink},
    uniqueID: DeFiActions.UniqueIdentifier?
)
```
Notes:
- `getSinkType()` is the swapper’s `inType()`.
- `minimumCapacity()` uses `swapper.quoteIn(forDesired: sink.minimumCapacity())`.

### MultiSwapper
```cadence
SwapConnectors.MultiSwapper(
    inVault: Type,
    outVault: Type,
    swappers: [{DeFiActions.Swapper}],
    uniqueID: DeFiActions.UniqueIdentifier?
)
```
Notes:
- Routes to the optimal inner swapper; `quoteIn/quoteOut(reverse:)` and `swap/swapBack` accept a generic Quote or will self-quote.

## IncrementFi Connectors

### Helper: borrowPool
**Purpose**: Retrieve a reference to a staking pool without requiring a pool collection address parameter.  
**Signature**:
```cadence
IncrementFiStakingConnectors.borrowPool(pid: UInt64): &{Staking.PoolPublic}?
```
**Notes**:
- Use this helper to minimize transaction parameters when targeting a known IncrementFi pool.
- Returns `nil` if the pool is not found or not accessible.

### PoolSink
```cadence
IncrementFiStakingConnectors.PoolSink(
    pid: UInt64,
    staker: Address,
    uniqueID: DeFiActions.UniqueIdentifier?
)
```

### PoolRewardsSource
```cadence
IncrementFiStakingConnectors.PoolRewardsSource(
    userCertificate: Capability<&Staking.UserCertificate>,
    pid: UInt64,
    uniqueID: DeFiActions.UniqueIdentifier?
)
```
Notes:
- Assumes a single reward token type for the pool; reverts if multiple are defined.
- May stake an empty vault to update unclaimed rewards, due to protocol limitations.

### PoolSource
> Not implemented in `IncrementFiStakingConnectors.cdc`.

## IncrementFi Pool Liquidity Connectors

### Zapper
```cadence
IncrementFiPoolLiquidityConnectors.Zapper(
    token0Type: Type,
    token1Type: Type,
    stableMode: Bool,
    uniqueID: DeFiActions.UniqueIdentifier?
)
```
Notes:
- `inType()` is token0; `outType()` is the LP vault type.
- `quoteOut(reverse: false)` estimates LP from token0; `reverse: true` estimates token0 from LP.
- `quoteIn` currently only supports `UFix64.max` as a placeholder.
- `swapBack(quote:residual:)` converts LP back to token0 (the `inType`).
- **Token Ordering**: When using with a source, check if `source.getSourceType() != token0Type`. If true, reverse the token order so the source token becomes token0 (the input token to the zapper). Zapper takes token0 as input and pairs it with token1 to create token0:token1 LP tokens.

---

## Observed usage patterns (from code/tests)
- **Claim → Zap → Restake**: Size withdraws by sink capacity; compute `expectedStakeIncrease = zapper.quoteOut(forProvided: rewards.minimumAvailable(), reverse: false).outAmount` and assert post.
- **SwapSource sizing**: `withdrawAvailable(maxAmount: sink.minimumCapacity())` keeps operations graceful and avoids reverts.
- **MultiSwapper**: When no quote provided to `swap/swapBack`, it computes an optimal inner swapper and proceeds.
- **Testing mocks**: When mocking `Source`/`Sink`/`Swapper`, include `IdentifiableStruct` members (`uniqueID`, `getComponentInfo`, `copyID`, `setID`).
