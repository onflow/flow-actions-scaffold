# Transaction Templates

> **NOTE**: The canonical end-to-end restake transaction lives in [workflows/restaking-workflow.md](./workflows/restaking-workflow.md). This page focuses on reusable, generic templates; see the workflow doc for the complete flow and rationale.

> Implementers: When creating new connectors used by these templates, ensure you implement inherited members from `IdentifiableStruct`. See [`interface-inheritance.md`](./interface-inheritance.md).

## Basic Transfer Template

### Vault to Vault Transfer
```cadence
import "FungibleToken"
import "FungibleTokenConnectors"

transaction(
    sourceStoragePath: StoragePath,
    targetVaultCap: Capability<&{FungibleToken.Vault}>,
    amount: UFix64,
    maxCapacity: UFix64
) {
    let source: FungibleTokenConnectors.VaultSource
    let sink: FungibleTokenConnectors.VaultSink

    prepare(acct: auth(BorrowValue) &Account) {
        let sourceCap = acct.capabilities.storage
            .issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(sourceStoragePath)
        
        self.source = FungibleTokenConnectors.VaultSource(
            min: 0.0,
            withdrawVault: sourceCap,
            uniqueID: nil
        )

        self.sink = FungibleTokenConnectors.VaultSink(
            max: maxCapacity,
            depositVault: targetVaultCap,
            uniqueID: nil
        )
    }

    pre {
        amount > 0.0: "Amount must be positive"
    }

    execute {
        let vault <- self.source.withdrawAvailable(maxAmount: self.sink.minimumCapacity())
        self.sink.depositCapacity(
            from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
        )
        assert(vault.balance == 0.0, message: "Transfer incomplete")
        destroy vault
    }
}

## Staking Templates

### Stake Tokens
```cadence
import "FungibleToken"
import "FungibleTokenConnectors"
import "IncrementFiStakingConnectors"

transaction(
    sourceStoragePath: StoragePath,
    staker: Address,
    pid: UInt64,
    amount: UFix64
) {
    let source: FungibleTokenConnectors.VaultSource
    let sink: IncrementFiStakingConnectors.PoolSink

    prepare(acct: auth(BorrowValue) &Account) {
        let sourceCap = acct.capabilities.storage
            .issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(sourceStoragePath)
        
        self.source = FungibleTokenConnectors.VaultSource(
            min: 0.0,
            withdrawVault: sourceCap,
            uniqueID: nil
        )

        self.sink = IncrementFiStakingConnectors.PoolSink(
            pid: pid,
            staker: staker,
            uniqueID: nil
        )
    }

    pre {
        amount > 0.0: "Stake amount must be positive"
        pid > 0: "Pool ID must be valid"
    }

    execute {
        let vault <- self.source.withdrawAvailable(maxAmount: self.sink.minimumCapacity())
        self.sink.depositCapacity(
            from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
        )
        assert(vault.balance == 0.0, message: "Staking incomplete")
        destroy vault
    }
}

### Claim Rewards
```cadence
import "FungibleToken"
import "FungibleTokenConnectors"
import "IncrementFiStakingConnectors"
import "Staking"

transaction(
    pid: UInt64,
    targetVaultCap: Capability<&{FungibleToken.Vault}>
) {
    let userCertificateCap: Capability<&Staking.UserCertificate>
    let rewardSource: IncrementFiStakingConnectors.PoolRewardsSource
    let sink: FungibleTokenConnectors.VaultSink

    prepare(acct: auth(BorrowValue, SaveValue) &Account) {
        self.userCertificateCap = acct.capabilities.storage
            .issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)

        self.rewardSource = IncrementFiStakingConnectors.PoolRewardsSource(
            userCertificate: self.userCertificateCap,
            pid: pid,
            uniqueID: nil
        )

        self.sink = FungibleTokenConnectors.VaultSink(
            max: nil,
            depositVault: targetVaultCap,
            uniqueID: nil
        )
    }

    execute {
        let vault <- self.rewardSource.withdrawAvailable(maxAmount: UFix64.max)
        self.sink.depositCapacity(
            from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
        )
        assert(vault.balance == 0.0, message: "Reward claim incomplete")
        destroy vault
    }
}

## Swap Templates

### Single Token Swap
```cadence
import "FungibleToken"
import "FungibleTokenConnectors"
import "SwapConnectors"

transaction(
    sourceStoragePath: StoragePath,
    targetVaultCap: Capability<&{FungibleToken.Vault}>,
    swapper: {DeFiActions.Swapper},
    amount: UFix64
) {
    let swapSource: SwapConnectors.SwapSource
    let sink: FungibleTokenConnectors.VaultSink

    prepare(acct: auth(BorrowValue) &Account) {
        let sourceCap = acct.capabilities.storage
            .issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(sourceStoragePath)
        
        let source = FungibleTokenConnectors.VaultSource(
            min: 0.0,
            withdrawVault: sourceCap,
            uniqueID: nil
        )

        self.swapSource = SwapConnectors.SwapSource(
            swapper: swapper,
            source: source,
            uniqueID: nil
        )

        self.sink = FungibleTokenConnectors.VaultSink(
            max: nil,
            depositVault: targetVaultCap,
            uniqueID: nil
        )
    }

    pre {
        amount > 0.0: "Swap amount must be positive"
    }

    execute {
        let vault <- self.swapSource.withdrawAvailable(maxAmount: self.sink.minimumCapacity())
        self.sink.depositCapacity(
            from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
        )
        assert(vault.balance == 0.0, message: "Swap incomplete")
        destroy vault
    }
}

### Zap to LP Tokens
```cadence
import "FungibleToken"
import "FungibleTokenConnectors"
import "SwapConnectors"
import "IncrementFiPoolLiquidityConnectors"

transaction(
    sourceStoragePath: StoragePath,
    targetVaultCap: Capability<&{FungibleToken.Vault}>,
    token0Type: Type,
    token1Type: Type,
    stableMode: Bool,
    amount: UFix64
) {
    let swapSource: SwapConnectors.SwapSource
    let sink: FungibleTokenConnectors.VaultSink

    prepare(acct: auth(BorrowValue) &Account) {
        let sourceCap = acct.capabilities.storage
            .issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(sourceStoragePath)
        
        let source = FungibleTokenConnectors.VaultSource(
            min: 0.0,
            withdrawVault: sourceCap,
            uniqueID: nil
        )

        // Note: When token types are explicitly provided as parameters, use them directly
        // The reverse logic is only needed when deriving tokens from a source and pair
        let zapper = IncrementFiPoolLiquidityConnectors.Zapper(
            token0Type: token0Type,
            token1Type: token1Type,
            stableMode: stableMode,
            uniqueID: nil
        )

        self.swapSource = SwapConnectors.SwapSource(
            swapper: zapper,
            source: source,
            uniqueID: nil
        )

        self.sink = FungibleTokenConnectors.VaultSink(
            max: nil,
            depositVault: targetVaultCap,
            uniqueID: nil
        )
    }

    pre {
        amount > 0.0: "Zap amount must be positive"
    }

    execute {
        let vault <- self.swapSource.withdrawAvailable(maxAmount: self.sink.minimumCapacity())
        self.sink.depositCapacity(
            from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
        )
        assert(vault.balance == 0.0, message: "Zap incomplete")
        destroy vault
    }
}

## AutoBalancer Templates

### Create AutoBalancer
```cadence
import "DeFiActions"
import "MockOracle"

transaction(
    vaultType: String,
    lowerThreshold: UFix64,
    upperThreshold: UFix64,
    storagePath: StoragePath,
    publicPath: PublicPath
) {
    prepare(signer: auth(SaveValue, IssueStorageCapabilityController, PublishCapability) &Account) {
        let tokenType = CompositeType(vaultType) 
            ?? panic("Invalid vault type: ".concat(vaultType))
        
        let oracle = MockOracle.PriceOracle(nil)
        
        let autoBalancer <- DeFiActions.createAutoBalancer(
            oracle: oracle,
            vaultType: tokenType,
            lowerThreshold: lowerThreshold,
            upperThreshold: upperThreshold,
            rebalanceSink: nil,
            rebalanceSource: nil,
            uniqueID: nil
        )
        
        signer.storage.save(<-autoBalancer, to: storagePath)
        let cap = signer.capabilities.storage.issue<&DeFiActions.AutoBalancer>(storagePath)
        signer.capabilities.publish(cap, at: publicPath)
    }

    pre {
        lowerThreshold > 0.0 && lowerThreshold < 1.0: "Lower threshold must be between 0 and 1"
        upperThreshold > 1.0: "Upper threshold must be greater than 1"
        lowerThreshold < upperThreshold: "Lower threshold must be less than upper"
    }
}

### Use AutoBalancer as Source
```cadence
import "FungibleToken"
import "FungibleTokenConnectors"
import "DeFiActions"

transaction(
    autoBalancerAddress: Address,
    autoBalancerPath: PublicPath,
    targetVaultCap: Capability<&{FungibleToken.Vault}>,
    amount: UFix64
) {
    let autoBalancerSource: DeFiActions.AutoBalancerSource
    let sink: FungibleTokenConnectors.VaultSink

    prepare(acct: auth(BorrowValue) &Account) {
        let autoBalancerCap = getAccount(autoBalancerAddress).capabilities
            .borrow<&DeFiActions.AutoBalancer>(autoBalancerPath)
            ?? panic("Could not access AutoBalancer")

        self.autoBalancerSource = DeFiActions.AutoBalancerSource(
            autoBalancer: autoBalancerCap,
            uniqueID: nil
        )

        self.sink = FungibleTokenConnectors.VaultSink(
            max: nil,
            depositVault: targetVaultCap,
            uniqueID: nil
        )
    }

    pre {
        amount > 0.0: "Amount must be positive"
    }

    execute {
        let vault <- self.autoBalancerSource.withdrawAvailable(maxAmount: self.sink.minimumCapacity())
        self.sink.depositCapacity(
            from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
        )
        assert(vault.balance == 0.0, message: "AutoBalancer withdrawal incomplete")
        destroy vault
    }
}

## Complex Workflow Templates

### Complete Restaking Workflow
```cadence
import "FungibleToken"
import "DeFiActions"
import "SwapConnectors"
import "IncrementFiStakingConnectors"
import "IncrementFiPoolLiquidityConnectors"
import "Staking"

transaction(
    pid: UInt64
) {
    let userCertificateCap: Capability<&Staking.UserCertificate>
    let pool: &{Staking.PoolPublic}
    let startingStake: UFix64
    let swapSource: SwapConnectors.SwapSource
    let expectedStakeIncrease: UFix64
    
    prepare(acct: auth(BorrowValue, SaveValue, IssueStorageCapabilityController) &Account) {
        self.userCertificateCap = acct.capabilities.storage
            .issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)
        
        self.pool = IncrementFiStakingConnectors.borrowPool(pid: pid)
            ?? panic("Pool with ID \(".concat(pid.toString()).concat(") not found or not accessible"))
        
        self.startingStake = self.pool.getUserInfo(address: acct.address)?.stakingAmount 
            ?? panic("No user info found for address \(".concat(acct.address.toString()).concat(")"))

        let pair = IncrementFiStakingConnectors.borrowPairPublicByPid(pid: pid)
            ?? panic("Pair with ID \(pid) not found or not accessible")

        let operationID = DeFiActions.createUniqueIdentifier()

        // Derive token types from the pair
        let token0Type = IncrementFiStakingConnectors.tokenTypeIdentifierToVaultType(pair.getPairInfoStruct().token0Key)
        let token1Type = IncrementFiStakingConnectors.tokenTypeIdentifierToVaultType(pair.getPairInfoStruct().token1Key)
        
        let poolRewardsSource = IncrementFiStakingConnectors.PoolRewardsSource(
            userCertificate: self.userCertificateCap,
            pid: pid,
            uniqueID: operationID
        )
        
        // Check if we need to reverse token order: if reward token doesn't match token0, we reverse
        // so that the reward token becomes token0 (the input token to the zapper)
        let reverse = poolRewardsSource.getSourceType() != token0Type

        let zapper = IncrementFiPoolLiquidityConnectors.Zapper(
            token0Type: reverse ? token1Type : token0Type,  // input token (reward token)
            token1Type: reverse ? token0Type : token1Type,  // other pair token (zapper outputs token0:token1 LP)
            stableMode: pair.getPairInfoStruct().isStableswap,
            uniqueID: operationID
        )
        
        self.swapSource = SwapConnectors.SwapSource(
            swapper: zapper,
            source: poolRewardsSource,
            uniqueID: operationID
        )

        self.expectedStakeIncrease = zapper.quoteOut(
            forProvided: poolRewardsSource.minimumAvailable(),
            reverse: false
        ).outAmount
    }
    
    post {
        self.pool.getUserInfo(address: self.userCertificateCap.address)!.stakingAmount 
            >= self.startingStake + self.expectedStakeIncrease:
            "Restaking failed: restaked amount is below the expected amount"
    }
    
    execute {
        let poolSink = IncrementFiStakingConnectors.PoolSink(
            pid: pid,
            staker: self.userCertificateCap.address,
            uniqueID: operationID
        )
        
        let vault <- self.swapSource.withdrawAvailable(maxAmount: poolSink.minimumCapacity())
        poolSink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
        
        assert(vault.balance == 0.0, message: "Vault should be empty after withdrawal - restaking may have failed")
        destroy vault
    }
}

### Claim → Zap → Restake (Minimal Params)

This variant duplicates the complete workflow above. To avoid redundancy, see:
- Canonical workflow: [workflows/restaking-workflow.md](./workflows/restaking-workflow.md)

## Template Usage Guidelines

### Connector Instantiation Style
- **Always use explicit instantiation**: Create each connector separately with descriptive variable names and comments.
- **Avoid nested construction**: This makes debugging difficult and reduces readability.
- **Add comments**: Explain the purpose of each connector and how it fits in the chain.

### Parameter Naming Convention
- Use descriptive parameter names
- Include units in parameter names when relevant
- Use consistent naming across templates

### Error Messages
- Include context in error messages
- Use consistent error message format
- Provide actionable information when possible

### Pre/Post Conditions
- Always validate input parameters
- Use meaningful error messages
- Keep conditions as single expressions
- For generic swap/transfer templates, prefer user-provided minimum expected change (e.g., `minimumReceivedAmount`). For the canonical restake workflow, compute `expectedStakeIncrease` from connector quotes and assert against it (no extra parameter).

### Resource Handling
- Always verify complete transfers
- Use assert statements for critical validations
- Destroy vaults only after verification
