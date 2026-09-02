#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Test AAVEv3 Lend Endpoint                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

VAULT="0x6a18000ebd71b79d345f9f9753253ae4fff84e27"
NETWORK="optimism"
ASSET="USDC"
SHARE="100"  # 100% of USDC balance
API_KEY="da586db798b805914362612017ceda607bbcb592915b60c118a06382535160b5cea57c19cc5af319ac33d2e41bf9d34522ffea91e68995e8ce0f35fd27ad24ea"
API_URL="http://ec2-3-135-99-211.us-east-2.compute.amazonaws.com:8003"

echo -e "${BLUE}Vault:${NC} $VAULT"
echo -e "${BLUE}Network:${NC} $NETWORK"
echo -e "${BLUE}Asset:${NC} $ASSET"
echo -e "${BLUE}Share:${NC} ${SHARE}%"
echo ""

echo "Calling /aaveV3/lend endpoint..."

RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  "${API_URL}/aaveV3/lend?vault=${VAULT}&network=${NETWORK}&asset=${ASSET}&share=${SHARE}&apiKey=${API_KEY}")

HTTP_BODY=$(echo "$RESPONSE" | sed -e 's/HTTP_STATUS\:.*//g')
HTTP_STATUS=$(echo "$RESPONSE" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')

echo -e "${BLUE}HTTP Status:${NC} $HTTP_STATUS"
echo ""
echo -e "${BLUE}Response:${NC}"
echo "$HTTP_BODY" | jq '.' 2>/dev/null || echo "$HTTP_BODY"
echo ""

if [ "$HTTP_STATUS" -eq 200 ]; then
    echo -e "${GREEN}✅ Lend request successful${NC}"
    echo ""
    echo "Waiting 10 seconds for transaction to confirm..."
    sleep 10
    echo ""
    echo -e "${BLUE}Checking supplied balance with /aaveV3/getSupplied...${NC}"
    
    SUPPLIED=$(curl -s "${API_URL}/aaveV3/getSupplied?vault=${VAULT}&network=${NETWORK}&asset=${ASSET}&apiKey=${API_KEY}")
    echo "$SUPPLIED" | jq '.' 2>/dev/null || echo "$SUPPLIED"
else
    echo -e "${RED}❌ Lend request failed${NC}"
fi
