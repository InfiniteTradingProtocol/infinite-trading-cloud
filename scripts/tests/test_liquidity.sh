#!/bin/bash
# Test script for addLiquidity and removeLiquidity endpoints
# Usage: ./test_liquidity.sh [gateway|express]

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ─── Config ────────────────────────────────────────────────────────────────────
TARGET="${1:-gateway}"

if [ "$TARGET" = "express" ]; then
  BASE_URL="http://localhost:8000"
else
  BASE_URL="http://ec2-3-135-99-211.us-east-2.compute.amazonaws.com:8003"
fi

# Replace with your actual test values
API_KEY="${API_KEY:-YOUR_API_KEY_HERE}"
VAULT="${VAULT:-0xb1569ec05aba57fd9256ba3816ae9221f23306ee}"  # BTC yield vault (Base)
NETWORK="base"

# Base network token addresses
WETH="0x4200000000000000000000000000000000000006"
USDC="0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
CBBTC="0xcbb7C0000aB88B473b1f5aFd9ef808440eed33Bf"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Liquidity Endpoints Test  ($TARGET)                ${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo -e "  Base URL : ${BLUE}${BASE_URL}${NC}"
echo -e "  Vault    : ${BLUE}${VAULT}${NC}"
echo -e "  Network  : ${BLUE}${NETWORK}${NC}"
echo ""

# ─── Helper ────────────────────────────────────────────────────────────────────
run_test() {
  local desc="$1"; local url="$2"; local expected_field="$3"
  echo -e "${YELLOW}▶ ${desc}${NC}"
  RESP=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "$url")
  BODY=$(echo "$RESP" | sed -e 's/HTTP_STATUS\:.*//g')
  STATUS=$(echo "$RESP" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')
  echo "  HTTP $STATUS"
  echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
  if echo "$BODY" | grep -q "\"$expected_field\""; then
    echo -e "  ${GREEN}✅ Contains expected field: $expected_field${NC}"
  else
    echo -e "  ${RED}❌ Missing expected field: $expected_field${NC}"
  fi
  echo ""
}

# ─── 1. Validation tests (should return 400 with clear errors) ────────────────
echo -e "${BLUE}── Validation tests (expect 400 errors) ──${NC}"
echo ""

run_test \
  "Missing required params" \
  "${BASE_URL}/addLiquidity?network=${NETWORK}&pool=${VAULT}&apiKey=${API_KEY}" \
  "error_type"

run_test \
  "Invalid asset1 address" \
  "${BASE_URL}/addLiquidity?network=${NETWORK}&pool=${VAULT}&apiKey=${API_KEY}&asset1=not-an-address&asset2=${USDC}&input_asset=${USDC}" \
  "error_type"

run_test \
  "Invalid fee_tier" \
  "${BASE_URL}/addLiquidity?network=${NETWORK}&pool=${VAULT}&apiKey=${API_KEY}&asset1=${WETH}&asset2=${USDC}&input_asset=${USDC}&fee_tier=1234" \
  "error_type"

run_test \
  "lower_price >= upper_price" \
  "${BASE_URL}/addLiquidity?network=${NETWORK}&pool=${VAULT}&apiKey=${API_KEY}&asset1=${WETH}&asset2=${USDC}&input_asset=${USDC}&lower_price=2000&upper_price=1000" \
  "error_type"

run_test \
  "removeLiquidity missing token_id" \
  "${BASE_URL}/removeLiquidity?network=${NETWORK}&pool=${VAULT}&apiKey=${API_KEY}&asset1=${WETH}&asset2=${USDC}" \
  "error_type"

run_test \
  "removeLiquidity invalid token_id (non-integer)" \
  "${BASE_URL}/removeLiquidity?network=${NETWORK}&pool=${VAULT}&apiKey=${API_KEY}&asset1=${WETH}&asset2=${USDC}&token_id=abc" \
  "error_type"

run_test \
  "removeLiquidity invalid output_asset" \
  "${BASE_URL}/removeLiquidity?network=${NETWORK}&pool=${VAULT}&apiKey=${API_KEY}&asset1=${WETH}&asset2=${USDC}&token_id=12345&output_asset=not-an-address" \
  "error_type"

# ─── 2. Live tests (require real API key and funded vault) ────────────────────
if [ "$API_KEY" = "YOUR_API_KEY_HERE" ]; then
  echo -e "${YELLOW}⚠  Set API_KEY env var to run live tests:${NC}"
  echo -e "  ${BLUE}API_KEY=your_key ./test_liquidity.sh${NC}"
  echo ""
  exit 0
fi

echo -e "${BLUE}── Live tests ──${NC}"
echo ""

# Full-range WETH/USDC position using 5% of USDC balance
echo -e "${YELLOW}▶ addLiquidity: full-range WETH/USDC, 5% of USDC (input_asset=USDC)${NC}"
curl -s -X POST \
  "${BASE_URL}/addLiquidity?network=${NETWORK}&pool=${VAULT}&apiKey=${API_KEY}&asset1=${WETH}&asset2=${USDC}&input_asset=${USDC}&fee_tier=3000&share=5&slippage=1" \
  | python3 -m json.tool 2>/dev/null
echo ""

# NOTE: If the above succeeds, take the tx hash, look up the token_id on-chain,
# then use it for the removeLiquidity test below.

# Example remove (replace TOKEN_ID with the actual position NFT token ID)
TOKEN_ID="${TOKEN_ID:-}"
if [ -n "$TOKEN_ID" ]; then
  echo -e "${YELLOW}▶ removeLiquidity: remove 100% of position, output both tokens${NC}"
  curl -s -X POST \
    "${BASE_URL}/removeLiquidity?network=${NETWORK}&pool=${VAULT}&apiKey=${API_KEY}&asset1=${WETH}&asset2=${USDC}&token_id=${TOKEN_ID}&amount=100&output_asset=both" \
    | python3 -m json.tool 2>/dev/null
  echo ""

  echo -e "${YELLOW}▶ removeLiquidity: remove 50%, consolidate to USDC${NC}"
  curl -s -X POST \
    "${BASE_URL}/removeLiquidity?network=${NETWORK}&pool=${VAULT}&apiKey=${API_KEY}&asset1=${WETH}&asset2=${USDC}&token_id=${TOKEN_ID}&amount=50&output_asset=${USDC}&slippage=1" \
    | python3 -m json.tool 2>/dev/null
  echo ""
else
  echo -e "${YELLOW}⚠  Set TOKEN_ID env var to test removeLiquidity with a real position${NC}"
  echo -e "  ${BLUE}TOKEN_ID=12345 ./test_liquidity.sh${NC}"
fi

echo -e "${GREEN}✅ Test run complete${NC}"
