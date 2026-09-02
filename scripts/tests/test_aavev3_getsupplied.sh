#!/bin/bash

# Test AAVEv3 endpoints
# Vault: 0x6a18000ebd71b79d345f9f9753253ae4fff84e27 (Optimism)

API_KEY="da586db798b805914362612017ceda607bbcb592915b60c118a06382535160b5cea57c19cc5af319ac33d2e41bf9d34522ffea91e68995e8ce0f35fd27ad24ea"
PROTOCOL="dhedge"
NETWORK="optimism"
POOL="0x6a18000ebd71b79d345f9f9753253ae4fff84e27"
ASSET="USDC"
BASE_URL="https://api.infinitetrading.io/aaveV3"

test_endpoint() {
    local endpoint=$1
    local method=$2
    local extra_params=$3
    
    echo ""
    echo "=========================================="
    echo "Testing: $endpoint ($method)"
    echo "=========================================="
    
    local url="${BASE_URL}${endpoint}?apiKey=${API_KEY}&protocol=${PROTOCOL}&network=${NETWORK}&pool=${POOL}&asset=${ASSET}${extra_params}"
    
    if [ "$method" = "POST" ]; then
        RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$url")
    else
        RESPONSE=$(curl -s -w "\n%{http_code}" "$url")
    fi
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    echo "HTTP Status: $HTTP_CODE"
    echo ""
    echo "Response:"
    echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
    echo ""
}

echo "╔════════════════════════════════════════════════════════╗"
echo "║         AAVEv3 Endpoint Testing Suite                 ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "Vault: $POOL"
echo "Network: $NETWORK"
echo "Asset: $ASSET"
echo ""

# Test 1: getSupplied
test_endpoint "/getSupplied" "GET" ""

# Test 2: getBorrowed
test_endpoint "/getBorrowed" "GET" ""

# Test 3: Try main /lend endpoint (not /aaveV3/lend)
echo ""
echo "=========================================="
echo "Testing MAIN /lend endpoint (not /aaveV3)"
echo "=========================================="
MAIN_LEND_URL="https://api.infinitetrading.io/lend?apiKey=${API_KEY}&protocol=${PROTOCOL}&network=${NETWORK}&pool=${POOL}&asset=${ASSET}&platform=aavev3&share=100"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$MAIN_LEND_URL")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')
echo "HTTP Status: $HTTP_CODE"
echo "Response:"
echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
echo ""

# Test 4: Now try /aaveV3/lend
echo ""
echo "=========================================="
echo "Testing /aaveV3/lend endpoint"
echo "=========================================="
test_endpoint "/lend" "POST" "&share=100"

# Test 5: Check supplied amount after lending
echo ""
echo "Verifying supplied amount after lending..."
sleep 5
test_endpoint "/getSupplied" "GET" ""

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║              All Tests Completed                       ║"
echo "╚════════════════════════════════════════════════════════╝"
