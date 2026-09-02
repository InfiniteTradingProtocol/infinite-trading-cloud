#!/bin/bash

# Approve USDC for AAVE v3
# AAVE v3 Pool Contract: 0x794a61358d6845594f94dc1db02a252b5b4814ad

API_KEY="da586db798b805914362612017ceda607bbcb592915b60c118a06382535160b5cea57c19cc5af319ac33d2e41bf9d34522ffea91e68995e8ce0f35fd27ad24ea"
PROTOCOL="dhedge"
NETWORK="optimism"
POOL="0x6a18000ebd71b79d345f9f9753253ae4fff84e27"
ASSET="USDC"
SPENDER="0x794a61358d6845594f94dc1db02a252b5b4814ad"

echo "╔════════════════════════════════════════════════════════╗"
echo "║         Approve USDC for AAVE v3                       ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "Vault: $POOL"
echo "Network: $NETWORK"
echo "Asset: $ASSET"
echo "Spender (AAVE v3): $SPENDER"
echo ""

# Use the approve endpoint with asset in body
APPROVE_URL="https://api.infinitetrading.io/approve?apiKey=${API_KEY}&protocol=${PROTOCOL}&network=${NETWORK}&pool=${POOL}&platform=aavev3"

echo "Calling approve endpoint..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$APPROVE_URL" \
  -H "Content-Type: application/json" \
  -d "{\"asset\": \"${ASSET}\"}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

echo "HTTP Status: $HTTP_CODE"
echo ""
echo "Response:"
echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
echo ""

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Approval request sent successfully"
    echo "⏳ Waiting 10 seconds for transaction to confirm..."
    sleep 10
    echo "✅ Ready to lend!"
else
    echo "❌ Approval failed"
fi
