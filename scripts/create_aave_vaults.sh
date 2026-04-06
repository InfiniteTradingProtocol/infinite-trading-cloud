#!/bin/bash
# Create vaults for AAVE-optimized crossover strategies
# This script creates 6 new vaults (one per strategy pair) using curl

API_BASE="https://api.infinitetrading.io"
API_KEY="da586db798b805914362612017ceda607bbcb592915b60c118a06382535160b5cea57c19cc5af319ac33d2e41bf9d34522ffea91e68995e8ce0f35fd27ad24ea"
GAS_WALLET="0x8893Ca7295Dfb55260Ee0db7FAa03AC8dCD8F5f5"

echo "================================================================================"
echo "CREATING AAVE-OPTIMIZED VAULTS"
echo "================================================================================"
echo ""


# Strategy configurations
declare -a NETWORKS=("base" "optimism" "base" "optimism" "base" "optimism")
declare -a PAIRS=("MORPHO-USDC" "SNX-USDC" "AERO-USDC" "AAVE-USDC" "cbBTC-USDC" "WETH-USDC")
declare -a POOL_NAMES=("ITP MORPHO/USDC EMA Crossover + AAVE" "ITP SNX/USDC EMA Crossover + AAVE" "ITP AERO/USDC EMA Crossover + AAVE" "ITP AAVE/USDC EMA Crossover + AAVE" "ITP cbBTC/USDC EMA Crossover + AAVE" "ITP WETH/USDC EMA Crossover + AAVE")
declare -a SYMBOLS=("ITPMOR" "ITPSNX" "ITPAERO" "ITPAAVE" "ITPCBTC" "ITPWETH")

# Asset addresses per network
# Base assets
BASE_USDC="0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
BASE_MORPHO="0x47c031236e19d024b42f8AE6780E44A573170703"
BASE_AERO="0x940181a94A35A4569E4529A3CDfB74e38FD98631"
BASE_CBBTC="0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf"

# Optimism assets
OPT_USDC="0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85"
OPT_SNX="0x8700dAec35aF8Ff88c16BdF0418774CB3D7599B4"
OPT_AAVE="0x76FB31fb4af56892A25e32cFC43De717950c9278"
OPT_WETH="0x4200000000000000000000000000000000000006"

# Create vaults
declare -a VAULT_ADDRESSES=()

for i in {0..5}; do
  NETWORK="${NETWORKS[$i]}"
  PAIR="${PAIRS[$i]}"
  POOL_NAME="${POOL_NAMES[$i]}"
  SYMBOL="${SYMBOLS[$i]}"
  
  echo "[$((i+1))/6] Creating vault for ${PAIR} on ${NETWORK}..."
  
  # Build supported assets JSON based on network
  # SupportedAsset type is [string, boolean] tuple
  if [ "$NETWORK" == "base" ]; then
    if [ "$PAIR" == "MORPHO-USDC" ]; then
      ASSETS="[[\"${BASE_USDC}\",true],[\"${BASE_MORPHO}\",true]]"
    elif [ "$PAIR" == "AERO-USDC" ]; then
      ASSETS="[[\"${BASE_USDC}\",true],[\"${BASE_AERO}\",true]]"
    elif [ "$PAIR" == "cbBTC-USDC" ]; then
      ASSETS="[[\"${BASE_USDC}\",true],[\"${BASE_CBBTC}\",true]]"
    fi
  else # optimism
    if [ "$PAIR" == "SNX-USDC" ]; then
      ASSETS="[[\"${OPT_USDC}\",true],[\"${OPT_SNX}\",true]]"
    elif [ "$PAIR" == "AAVE-USDC" ]; then
      ASSETS="[[\"${OPT_USDC}\",true],[\"${OPT_AAVE}\",true]]"
    elif [ "$PAIR" == "WETH-USDC" ]; then
      ASSETS="[[\"${OPT_USDC}\",true],[\"${OPT_WETH}\",true]]"
    fi
  fi
  
  # Create vault
  RESPONSE=$(curl -s -X POST "${API_BASE}/createPool?network=${NETWORK}&apiKey=${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
      \"managerName\": \"Infinite Trading Bot\",
      \"poolName\": \"${POOL_NAME}\",
      \"symbol\": \"${SYMBOL}\",
      \"supportedAssets\": ${ASSETS},
      \"fee\": \"200\"
    }")
  
  # Debug: show raw response
  echo "  Response: $RESPONSE"
  
  # Check if response is valid JSON
  if ! echo "$RESPONSE" | jq . >/dev/null 2>&1; then
    echo "  ✗ API returned invalid JSON"
    VAULT_ADDRESSES+=("")
    echo ""
    continue
  fi
  
  STATUS=$(echo "$RESPONSE" | jq -r '.status // "unknown"')
  
  if [ "$STATUS" == "success" ]; then
    VAULT_ADDRESS=$(echo "$RESPONSE" | jq -r '.msg')
    VAULT_ADDRESSES+=("$VAULT_ADDRESS")
    echo "  ✓ Vault created: ${VAULT_ADDRESS}"
    
    # Wait for transaction
    sleep 10
    
    # Set trader
    echo "  → Setting trader to ${GAS_WALLET}..."
    TRADER_RESPONSE=$(curl -s -X POST "${API_BASE}/setTrader?network=${NETWORK}&pool=${VAULT_ADDRESS}&apiKey=${API_KEY}" \
      -H "Content-Type: application/json" \
      -d "{\"traderAccount\": \"${GAS_WALLET}\"}")
    
    TRADER_STATUS=$(echo "$TRADER_RESPONSE" | jq -r '.status // "unknown"')
    if [ "$TRADER_STATUS" == "success" ]; then
      echo "  ✓ Trader set successfully"
    else
      ERROR_MSG=$(echo "$TRADER_RESPONSE" | jq -r '.msg // .message // "Unknown error"')
      echo "  ✗ Failed to set trader: ${ERROR_MSG}"
    fi
    
    sleep 5
  else
    VAULT_ADDRESSES+=("")
    ERROR_MSG=$(echo "$RESPONSE" | jq -r '.msg // .message // "Unknown error"')
    echo "  ✗ Failed to create vault: ${ERROR_MSG}"
  fi
  
  echo ""
done

# Print summary
echo "================================================================================"
echo "VAULT CREATION SUMMARY"
echo "================================================================================"
echo ""

for i in {0..5}; do
  PAIR="${PAIRS[$i]}"
  VAULT="${VAULT_ADDRESSES[$i]}"
  if [ -n "$VAULT" ]; then
    printf "%-15s  %s\n" "$PAIR" "$VAULT"
  else
    printf "%-15s  FAILED\n" "$PAIR"
  fi
done

# Save to R file
OUTPUT_FILE="infinitetrading/src/strategies/aave_vault_addresses.R"
echo ""
echo ""
echo "Saving vault addresses to ${OUTPUT_FILE}..."

cat > "$OUTPUT_FILE" << EOF
# AAVE-Optimized Vault Addresses
# Generated on $(date)

AAVE_VAULT_ADDRESSES <- list(
  "MORPHO-USDC" = "${VAULT_ADDRESSES[0]}",
  "SNX-USDC" = "${VAULT_ADDRESSES[1]}",
  "AERO-USDC" = "${VAULT_ADDRESSES[2]}",
  "AAVE-USDC" = "${VAULT_ADDRESSES[3]}",
  "cbBTC-USDC" = "${VAULT_ADDRESSES[4]}",
  "WETH-USDC" = "${VAULT_ADDRESSES[5]}"
)
EOF

echo "✓ Vault addresses saved!"
echo ""
echo "Next steps:"
echo "1. Fund the vaults with initial USDC"
echo "2. Run crossOversAndAAVE.R strategy"
echo "3. Monitor PM2 logs: pm2 logs strategy-crossovers-aave"
echo ""
