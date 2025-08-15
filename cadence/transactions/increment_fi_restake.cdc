import "FungibleToken"
import "DeFiActions"
import "SwapConnectors"
import "IncrementFiStakingConnectors"
import "IncrementFiPoolLiquidityConnectors"
import "Staking"

/// Claims farm rewards from IncrementFi and restakes them into the same pool
/// This transaction follows the Claim → Zap → Stake workflow pattern
transaction(
    pid: UInt64
) {
    let userCertificateCap: Capability<&Staking.UserCertificate>
    let pool: &{Staking.PoolPublic}
    let startingStake: UFix64
    let swapSource: SwapConnectors.SwapSource
    let expectedStakeIncrease: UFix64
    let operationID: DeFiActions.UniqueIdentifier

    prepare(acct: auth(BorrowValue, SaveValue, IssueStorageCapabilityController) &Account) {
        // Get pool reference and validate it exists
        self.pool = IncrementFiStakingConnectors.borrowPool(pid: pid)
            ?? panic("Pool with ID \(pid) not found or not accessible")
        
        // Get starting stake amount for post-condition validation
        self.startingStake = self.pool.getUserInfo(address: acct.address)?.stakingAmount
            ?? panic("No user info for address \(acct.address)")
        
        // Issue capability for user certificate
        self.userCertificateCap = acct.capabilities.storage
            .issue<&Staking.UserCertificate>(Staking.UserCertificateStoragePath)

        // Create unique identifier for tracing this composed operation
        self.operationID = DeFiActions.createUniqueIdentifier()

        // Get pair info to determine token types and stable mode
        let pair = IncrementFiStakingConnectors.borrowPairPublicByPid(pid: pid)
            ?? panic("Pair with ID \(pid) not found or not accessible")

        // Derive token types from the pair
        let token0Type = IncrementFiStakingConnectors.tokenTypeIdentifierToVaultType(pair.getPairInfoStruct().token0Key)
        let token1Type = IncrementFiStakingConnectors.tokenTypeIdentifierToVaultType(pair.getPairInfoStruct().token1Key)
        
        // Create rewards source to claim staking rewards
        let rewardsSource = IncrementFiStakingConnectors.PoolRewardsSource(
            userCertificate: self.userCertificateCap,
            pid: pid,
            uniqueID: self.operationID
        )
        
        // Check if we need to reverse token order: if reward token doesn't match token0, we reverse
        // so that the reward token becomes token0 (the input token to the zapper)
        let reverse = rewardsSource.getSourceType() != token0Type
        
        // Create zapper to convert rewards to LP tokens
        let zapper = IncrementFiPoolLiquidityConnectors.Zapper(
            token0Type: reverse ? token1Type : token0Type,  // input token (reward token)
            token1Type: reverse ? token0Type : token1Type,  // other pair token (zapper outputs token0:token1 LP)
            stableMode: pair.getPairInfoStruct().isStableswap,
            uniqueID: self.operationID
        )
        
        // Wrap rewards source with zapper to convert rewards to LP tokens
        let lpSource = SwapConnectors.SwapSource(
            swapper: zapper,
            source: rewardsSource,
            uniqueID: self.operationID
        )

        self.swapSource = lpSource
        
        // Calculate expected stake increase for post-condition
        self.expectedStakeIncrease = zapper.quoteOut(
            forProvided: lpSource.minimumAvailable(),
            reverse: false
        ).outAmount
    }

    post {
        // Verify that staking amount increased by at least the expected amount
        self.pool.getUserInfo(address: self.userCertificateCap.address)!.stakingAmount
            >= self.startingStake + self.expectedStakeIncrease:
            "Restake below expected amount"
    }

    execute {
        // Create pool sink to receive LP tokens for staking
        let poolSink = IncrementFiStakingConnectors.PoolSink(
            pid: pid,
            staker: self.userCertificateCap.address,
            uniqueID: self.operationID
        )

        // Withdraw LP tokens from swap source (sized by sink capacity)
        let vault <- self.swapSource.withdrawAvailable(maxAmount: poolSink.minimumCapacity())
        
        // Deposit LP tokens into pool for staking
        poolSink.depositCapacity(from: &vault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault})
        
        // Ensure no residual tokens remain
        assert(vault.balance == 0.0, message: "Residual after deposit")
        destroy vault
    }
} 