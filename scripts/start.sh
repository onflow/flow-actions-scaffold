#!/usr/bin/env bash
set -euo pipefail

FLOW_BIN="${FLOW_BIN:-flow}"
NETWORK="${NETWORK:-emulator}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}$1${NC}"; }
log_success() { echo -e "${GREEN}$1${NC}"; }
log_warning() { echo -e "${YELLOW}$1${NC}"; }
log_error() { echo -e "${RED}$1${NC}"; }
log_detail() { echo -e "${GRAY}$1${NC}"; }
log_highlight() { echo -e "${WHITE}$1${NC}"; }

if ! command -v "$FLOW_BIN" >/dev/null 2>&1; then
  log_error "❌ Error: flow CLI not found. Install from https://developers.flow.com/tools/flow-cli/install"
  exit 1
fi

log_info "🚀 Starting Flow emulator..."

# Start the emulator in the background
"$FLOW_BIN" emulator &
EMULATOR_PID=$!
cleanup() {
  exit_code=$1
  if [ "$exit_code" -ne 0 ]; then
    log_warning "⚠️  Error occurred (exit code: $exit_code). Allowing emulator to flush logs for 2s..."
    sleep 2
  fi
  log_info "🛑 Stopping emulator..."
  kill $EMULATOR_PID 2>/dev/null || true
  wait $EMULATOR_PID 2>/dev/null || true
}
trap 'cleanup $?' EXIT INT TERM

# Wait for the emulator to be ready (up to 30 seconds)
for i in {1..60}; do
  if (echo > /dev/tcp/127.0.0.1/3569) >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

# Check if the emulator started successfully
if ! (echo > /dev/tcp/127.0.0.1/3569) >/dev/null 2>&1; then
  log_error "❌ Error: Flow emulator failed to start on port 3569"
  kill $EMULATOR_PID 2>/dev/null || true
  wait $EMULATOR_PID 2>/dev/null || true
  exit 1
fi

log_success "✅ Emulator started on localhost:3569"

echo ""
log_info "📦 Installing Flow dependencies..."
"$FLOW_BIN" deps install || true
log_info "🚀 Deploying contracts to $NETWORK..."
"$FLOW_BIN" project deploy --network "$NETWORK" || true

echo ""
log_highlight "🔧 Setting up Increment Fi Infrastructure..."

# Deploy swap pair template
log_detail "   📋 Deploying swap pair template..."
"$FLOW_BIN" transactions send \
  --signer emulator-account \
  --network emulator \
  "$(pwd)/scripts/transactions/increment-fi/deploy_swap_pair.cdc" > /dev/null
log_detail "   ✓ Swap pair template deployed"

# Create a pair with the staking pool
log_detail "   🔗 Creating TokenA-TokenB swap pair..."
"$FLOW_BIN" transactions send \
  --signer emulator-account \
  --network emulator \
  "$(pwd)/scripts/transactions/increment-fi/create_swap_pair.cdc" \
  --args-json '[
    {
      "type": "String",
      "value": "A.f8d6e0586b0a20c7.TokenA.Vault"
    },
    {
      "type": "String",
      "value": "A.f8d6e0586b0a20c7.TokenB.Vault"
    },
    {
      "type": "Bool",
      "value": false
    }
  ]' > /dev/null
log_detail "   ✓ TokenA-TokenB swap pair created"

echo ""
log_highlight "🪙 Setting up Tokens..."

# Setup vaults for TokenA and TokenB on the emulator account
log_detail "   💰 Setting up TokenA vault..."
"$FLOW_BIN" transactions send \
  --signer emulator-account \
  --network emulator \
  "$(pwd)/scripts/transactions/fungible-tokens/setup_generic_vault.cdc" \
  --args-json '[
    {
      "type": "String",
      "value": "A.f8d6e0586b0a20c7.TokenA.Vault"
    }
  ]' > /dev/null
log_detail "   ✓ TokenA vault ready"

# Setup vault for TokenB on the emulator account
log_detail "   💰 Setting up TokenB vault..."
"$FLOW_BIN" transactions send \
  --signer emulator-account \
  --network emulator \
  "$(pwd)/scripts/transactions/fungible-tokens/setup_generic_vault.cdc" \
  --args-json '[
    {
      "type": "String",
      "value": "A.f8d6e0586b0a20c7.TokenB.Vault"
    }
  ]' > /dev/null
log_detail "   ✓ TokenB vault ready"

# Mint TokenA to the emulator account
log_detail "   🪙 Minting 1,000,000 TokenA..."
"$FLOW_BIN" transactions send \
  --signer emulator-account \
  --network emulator \
  "$(pwd)/scripts/transactions/fungible-tokens/mint_tokens.cdc" \
  --args-json '[
    {
      "type": "Address",
      "value": "0xf8d6e0586b0a20c7"
    },
    {
      "type": "UFix64",
      "value": "1000000.00000000"
    },
    {
      "type": "Path",
      "value": { "domain": "storage", "identifier": "tokenAAdmin" }
    },
    {
      "type": "Path",
      "value": { "domain": "public", "identifier": "tokenAReceiver" }
    }
  ]' > /dev/null
log_detail "   ✓ TokenA minted (1,000,000)"

# Mint TokenB to the emulator account
log_detail "   🪙 Minting 1,000,000 TokenB..."
"$FLOW_BIN" transactions send \
  --signer emulator-account \
  --network emulator \
  "$(pwd)/scripts/transactions/fungible-tokens/mint_tokens.cdc" \
  --args-json '[
    {
      "type": "Address",
      "value": "0xf8d6e0586b0a20c7"
    },
    {
      "type": "UFix64",
      "value": "1000000.00000000"
    },
    {
      "type": "Path",
      "value": { "domain": "storage", "identifier": "tokenBAdmin" }
    },
    {
      "type": "Path",
      "value": { "domain": "public", "identifier": "tokenBReceiver" }
    }
  ]' > /dev/null
log_detail "   ✓ TokenB minted (1,000,000)"

echo ""
log_highlight "🏊 Creating Increment Fi Liquidity Pool..."

# Add liquidity to the pool for LP tokens
log_detail "   🏊 Adding liquidity (100k TokenA + 100k TokenB)..."
"$FLOW_BIN" transactions send \
  --signer emulator-account \
  --network emulator \
  "$(pwd)/scripts/transactions/increment-fi/add_liquidity.cdc" \
  --args-json '[
    {
      "type": "String",
      "value": "A.f8d6e0586b0a20c7.TokenA"
    },
    {
      "type": "String",
      "value": "A.f8d6e0586b0a20c7.TokenB"
    },
    {
      "type": "UFix64",
      "value": "100000.00000000"
    },
    {
      "type": "UFix64",
      "value": "100000.00000000"
    },
    {
      "type": "UFix64",
      "value": "0.00000000"
    },
    {
      "type": "UFix64",
      "value": "0.00000000"
    },
    {
      "type": "UFix64",
      "value": "184467440737.09551615"
    },
    {
      "type": "Path",
      "value": { "domain": "storage", "identifier": "tokenAVault" }
    },
    {
      "type": "Path",
      "value": { "domain": "storage", "identifier": "tokenBVault" }
    },
    {
      "type": "Bool",
      "value": false
    }
  ]' > /dev/null
log_detail "   ✓ Liquidity pool created (100k each)"

echo ""
log_highlight "🎯 Setting up Increment Fi Staking..."

# Create an example staking pool
log_detail "   🎯 Creating staking pool #0..."
"$FLOW_BIN" transactions send \
  --signer emulator-account \
  --network emulator \
  "$(pwd)/scripts/transactions/increment-fi/create_staking_pool.cdc" \
  --args-json '[
    {
      "type": "UFix64",
      "value": "184467440737.09551615"
    },
    {
      "type": "Type",
      "value": {
        "staticType": {
          "kind": "Resource",
          "typeID": "A.179b6b1cb6755e31.SwapPair.Vault",
          "fields": [],
          "initializers": [],
          "type": ""
        }
      }
    },
    {
      "type": "Array",
      "value": [
        {
          "type": "Struct",
          "value": {
            "id": "A.f8d6e0586b0a20c7.Staking.RewardInfo",
            "fields": [
              { "name": "startTimestamp",   "value": { "type": "UFix64", "value": "0.00000000" } },
              { "name": "endTimestamp",     "value": { "type": "UFix64", "value": "0.00000000" } },
              { "name": "rewardPerSession", "value": { "type": "UFix64", "value": "1.00000000" } },
              { "name": "sessionInterval",  "value": { "type": "UFix64", "value": "1.00000000" } },
              { "name": "rewardTokenKey",   "value": { "type": "String", "value": "A.f8d6e0586b0a20c7.TokenA" } },
              { "name": "totalReward",      "value": { "type": "UFix64", "value": "0.00000000" } },
              { "name": "lastRound",        "value": { "type": "UInt64", "value": "0" } },
              { "name": "totalRound",       "value": { "type": "UInt64", "value": "0" } },
              { "name": "rewardPerSeed",    "value": { "type": "UFix64", "value": "0.00000000" } }
            ]
          }
        }
      ]
    },
    {
      "type": "Optional",
      "value": {
        "type": "Path",
        "value": { "domain": "storage", "identifier": "tokenAVault" }
      }
    },
    {
      "type": "Optional",
      "value": {
        "type": "UFix64",
        "value": "10000.00000000"
      }
    }
  ]' > /dev/null
log_detail "   ✓ Staking pool #0 created (funded with 10,000 TokenA rewards)"


# Setup staking certificate for the user
log_detail "   📄 Setting up staking certificate..."
"$FLOW_BIN" transactions send \
  --signer emulator-account \
  --network emulator \
  "$(pwd)/scripts/transactions/increment-fi/setup_staking_certificate.cdc" > /dev/null
log_detail "   ✓ Staking certificate ready"

# Stake 50k LP tokens in the staking pool
log_detail "   📈 Staking 50,000 LP tokens in pool #0..."
"$FLOW_BIN" transactions send \
  --signer emulator-account \
  --network emulator \
  "$(pwd)/scripts/transactions/increment-fi/deposit_staking_pool.cdc" \
  --args-json '[
    {
      "type": "UInt64", 
      "value": "0"
    },
    {
      "type": "UFix64",
      "value": "50000.00000000"
    },
    {
      "type": "Type",
      "value": {
        "staticType": {
          "kind": "Resource",
          "typeID": "A.179b6b1cb6755e31.SwapPair.Vault",
          "fields": [],
          "initializers": [],
          "type": ""
        }
      }
    }
  ]' > /dev/null
log_detail "   ✓ Staked 50,000 LP tokens"

echo ""
log_highlight "🎉 Increment Fi Environment Ready!"
echo ""
log_success "📊 Available Assets:"
log_detail "   ├─ ${CYAN}TokenA${NC}: ${WHITE}890,000${NC} (100k in LP, 10k in staking rewards)"
log_detail "   └─ ${CYAN}TokenB${NC}: ${WHITE}900,000${NC} (100k in LP)"
echo ""
log_success "🏊 Increment Fi Liquidity Pool:"
log_detail "   ├─ Pair: ${CYAN}TokenA-TokenB${NC} (${WHITE}100k${NC} each)"
log_detail "   └─ Type: ${YELLOW}Standard${NC} (non-stable)"
echo ""
log_success "🎯 Increment Fi Staking Pool #${WHITE}0${NC}:"
log_detail "   ├─ LP Token: ${CYAN}TokenA-TokenB${NC}"
log_detail "   ├─ Rewards: ${YELLOW}TokenA${NC} (10,000 funded)"
log_detail "   ├─ Staked: ${WHITE}50,000${NC} LP tokens"
log_detail "   └─ Status: ${GREEN}Active${NC}"
echo ""
log_info "🌐 Network Endpoints:"
log_detail "   ├─ gRPC: ${GREEN}localhost:3569${NC} (Flow CLI, SDKs)"
log_detail "   └─ REST: ${GREEN}localhost:8888${NC} (HTTP API)"
log_warning "📝 Press Ctrl+C to stop"

# Wait for the emulator process to finish (keep it running in the foreground)
wait $EMULATOR_PID