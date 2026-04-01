#!/bin/bash

# Test script for CEX API endpoints

echo "==================================="
echo "Testing getAllCEXSubaccounts"
echo "==================================="

# Test with proper authentication (you'll need to provide valid values)
MANAGER_WALLET="0xYourManagerWallet"
SIGNATURE="0xYourSignature"
TIMESTAMP=$(date +%s)000

echo ""
echo "1. Checking if payment_network is included in response:"
echo ""

curl -s "https://api.infinitetrading.io/getAllCEXSubaccounts" \
  -H "Content-Type: application/json" \
  -d "{\"manager_wallet\":\"$MANAGER_WALLET\",\"signature\":\"$SIGNATURE\",\"timestamp\":$TIMESTAMP}" \
  | jq '.[0] | {id, name, gas_wallet, payment_network, balance_usd}' 2>/dev/null

echo ""
echo "==================================="
echo "2. Checking all CEX subaccounts balances:"
echo ""

curl -s "https://api.infinitetrading.io/getAllCEXSubaccounts" \
  -H "Content-Type: application/json" \
  -d "{\"manager_wallet\":\"$MANAGER_WALLET\",\"signature\":\"$SIGNATURE\",\"timestamp\":$TIMESTAMP}" \
  | jq '.[] | {name, balance_usd, gas_wallet, payment_network}' 2>/dev/null

echo ""
echo "==================================="
echo "Test complete!"
echo "==================================="
