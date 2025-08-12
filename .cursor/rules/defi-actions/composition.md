# Component Composition

## Basic Composition Rules

### Source → Sink (Direct)
```cadence
let source = ComponentSource(...)
let sink = ComponentSink(...)

let vault <- source.withdrawAvailable(maxAmount: sink.minimumCapacity())
sink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
assert(vault.balance == 0.0, message: "Transfer incomplete")
destroy vault
```

### Source → Swapper → Sink (Manual)
```cadence
let source = ComponentSource(...)
let swapper = ComponentSwapper(...)
let sink = ComponentSink(...)

// Prefer cap-driven sizing. For manual swaps, compute input via quoteIn for sink.minimumCapacity().
let inputVault <- source.withdrawAvailable(maxAmount: source.minimumAvailable())
let outputVault <- swapper.swap(quote: nil, inVault: <-inputVault)
sink.depositCapacity(from: &outputVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
assert(outputVault.balance == 0.0, message: "Transfer incomplete")
destroy outputVault
```

## Composite Components

### SwapSource (Source + Swapper)
```cadence
let swapSource = SwapConnectors.SwapSource(
    swapper: tokenSwapper,    // {Swapper}
    source: basicSource,      // {Source}
    uniqueID: operationID     // DeFiActions.UniqueIdentifier?
)

// Usage: Acts as enhanced Source
let vault <- swapSource.withdrawAvailable(maxAmount: amount)
```

### SwapSink (Swapper + Sink)
```cadence
let swapSink = SwapConnectors.SwapSink(
    swapper: tokenSwapper,    // {Swapper}
    sink: basicSink,          // {Sink}
    uniqueID: operationID     // DeFiActions.UniqueIdentifier?
)

// Usage: Acts as enhanced Sink
swapSink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
```

## Multi-Level Composition

### Explicit SwapSource Chaining (Preferred)
```cadence
// Step 1: Create base vault source
let baseSource = FungibleTokenConnectors.VaultSource(...)

// Step 2: Create first swapper for initial conversion  
let firstSwapper = SomeSwapper(...)

// Step 3: Create first swap source (base → intermediate)
let firstSwapSource = SwapConnectors.SwapSource(
    swapper: firstSwapper,
    source: baseSource,
    uniqueID: operationID
)

// Step 4: Create second swapper for final conversion
let secondSwapper = AnotherSwapper(...)

// Step 5: Create final swap source (intermediate → final)
let complexSource = SwapConnectors.SwapSource(
    swapper: secondSwapper,
    source: firstSwapSource,
    uniqueID: operationID
)
```

### Chain: Vault → Swap → Swap → Stake
```cadence
// Step 1: Base vault source
let vaultSource = FungibleTokenConnectors.VaultSource(
    min: 10.0,
    withdrawVault: userVaultCap,
    uniqueID: operationID
)

// Step 2: First swap (Token A → Token B)
let firstSwapSource = SwapConnectors.SwapSource(
    swapper: tokenAToTokenBSwapper,
    source: vaultSource,
    uniqueID: operationID
)

// Step 3: Second swap (Token B → LP Tokens)
let lpSwapSource = SwapConnectors.SwapSource(
    swapper: tokenBToLPSwapper,
    source: firstSwapSource,
    uniqueID: operationID
)

// Step 4: Staking sink
let stakingSink = IncrementFiStakingConnectors.PoolSink(
    pid: poolId,
    staker: userAddress,
    uniqueID: operationID
)

// Execute complete chain
let vault <- lpSwapSource.withdrawAvailable(maxAmount: stakingSink.minimumCapacity())
stakingSink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
```

## AutoBalancer Integration

### AutoBalancer as Source
```cadence
let autoBalancerSource = DeFiActions.AutoBalancerSource(
    autoBalancer: autoBalancerCap,  // Capability<&DeFiActions.AutoBalancer>
    uniqueID: operationID
)
let autoBalancerSink = DeFiActions.AutoBalancerSink(
    autoBalancer: autoBalancerCap,
    uniqueID: operationID
)

// Can be used in any Source position
let vault <- autoBalancerSource.withdrawAvailable(maxAmount: autoBalancerSink.minimumCapacity())
```

### AutoBalancer as Sink
```cadence
let autoBalancerSink = DeFiActions.AutoBalancerSink(
    autoBalancer: autoBalancerCap,  // Capability<&DeFiActions.AutoBalancer>
    uniqueID: operationID
)

// Can be used in any Sink position
autoBalancerSink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
```

### AutoBalancer in Chain
```cadence
// Create each component explicitly for readability and debugging
let rewardSource = PoolRewardsSource(
    userCertificate: userCertificateCap,
    pid: pid,
    uniqueID: operationID
)

// Check if we need to reverse token order based on the reward source type
let reverse = rewardSource.getSourceType() != token0Type

let zapper = IncrementFiPoolLiquidityConnectors.Zapper(
    token0Type: reverse ? token1Type : token0Type,  // input token (reward token)
    token1Type: reverse ? token0Type : token1Type,  // other pair token (zapper outputs token0:token1 LP)
    stableMode: stableMode,
    uniqueID: operationID
)

let swapSource = SwapConnectors.SwapSource(
    swapper: zapper,
    source: rewardSource,
    uniqueID: operationID
)

let autoBalancerSink = DeFiActions.AutoBalancerSink(
    autoBalancer: balancerCap,
    uniqueID: operationID
)

// Execute the chain
let vault <- swapSource.withdrawAvailable(maxAmount: autoBalancerSink.minimumCapacity())
autoBalancerSink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
```

## Composition Best Practices

### Prefer Explicit Instantiation Over Nesting
```cadence
// ✅ PREFERRED: Explicit instantiation - readable, debuggable, commentable
let rewardsSource = IncrementFiStakingConnectors.PoolRewardsSource(
    userCertificate: userCertificateCap,
    pid: pid,
    uniqueID: operationID
)

// Check if we need to reverse token order based on the reward source type
let reverse = rewardsSource.getSourceType() != token0Type

let zapper = IncrementFiPoolLiquidityConnectors.Zapper(
    token0Type: reverse ? token1Type : token0Type,  // input token (reward token)
    token1Type: reverse ? token0Type : token1Type,  // other pair token (zapper outputs token0:token1 LP)
    stableMode: stableMode,
    uniqueID: operationID
)

let swapSource = SwapConnectors.SwapSource(
    swapper: zapper,
    source: rewardsSource,
    uniqueID: operationID
)

// ❌ AVOID: Nested construction - hard to read, debug, and comment
let swapSource = SwapConnectors.SwapSource(
    swapper: IncrementFiPoolLiquidityConnectors.Zapper(...),
    source: IncrementFiStakingConnectors.PoolRewardsSource(...),
    uniqueID: operationID
)
```

### Use Consistent UniqueIDs
```cadence
let operationID = DeFiActions.createUniqueIdentifier()

// All components in same operation should use same ID
let source = ComponentSource(..., uniqueID: operationID)
let swapper = ComponentSwapper(..., uniqueID: operationID)
let sink = ComponentSink(..., uniqueID: operationID)
```

### Validate Component Compatibility
```cadence
// Ensure type compatibility
assert(source.getSourceType() == swapper.inType(), message: "Source/Swapper type mismatch")
assert(swapper.outType() == sink.getSinkType(), message: "Swapper/Sink type mismatch")
```

### Check Capacity Before Execution
```cadence
let available = source.minimumAvailable()
let capacity = sink.minimumCapacity()

assert(available > 0.0, message: "No tokens available")
assert(capacity >= available, message: "Insufficient sink capacity")
```
