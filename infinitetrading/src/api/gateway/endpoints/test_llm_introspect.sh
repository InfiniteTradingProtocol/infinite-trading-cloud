#!/bin/bash
# Test script for the llmIntrospect endpoint
# This tests the new MCP-style API documentation endpoint

echo "Testing llmIntrospect endpoint..."
echo "================================"
echo ""

# Test local deployment (default port 8003)
LOCAL_URL="http://localhost:8003/llmIntrospect"
PROD_URL="https://api.infinitetrading.io/llmIntrospect"

# Try local first, then production
if curl -sf "$LOCAL_URL" > /dev/null 2>&1; then
    echo "Testing LOCAL endpoint: $LOCAL_URL"
    URL="$LOCAL_URL"
elif curl -sf "$PROD_URL" > /dev/null 2>&1; then
    echo "Testing PRODUCTION endpoint: $PROD_URL"
    URL="$PROD_URL"
else
    echo "❌ Error: Neither local nor production endpoint is available"
    exit 1
fi

echo ""
echo "Fetching API documentation..."

# Fetch and pretty-print the response
response=$(curl -s "$URL")

if [ $? -eq 0 ]; then
    echo "✅ Successfully fetched API documentation"
    echo ""
    
    # Check if jq is available for pretty printing
    if command -v jq &> /dev/null; then
        echo "API Info:"
        echo "$response" | jq '.api_info'
        echo ""
        echo "Available Categories:"
        echo "$response" | jq '.categories[].name'
        echo ""
        echo "Total Endpoints:"
        echo "$response" | jq '.endpoints | length'
        echo ""
        echo "Sample Endpoint (vaultTrade):"
        echo "$response" | jq '.endpoints[] | select(.name == "vaultTrade")'
        echo ""
        echo "Networks Supported:"
        echo "$response" | jq '.networks'
        echo ""
        echo "Protocols Supported:"
        echo "$response" | jq '.protocols'
        echo ""
        echo "Full response saved to: llm_introspect_response.json"
        echo "$response" | jq '.' > llm_introspect_response.json
    else
        echo "$response"
        echo ""
        echo "💡 Install jq for pretty-printed output: brew install jq"
    fi
else
    echo "❌ Error: Failed to fetch API documentation"
    exit 1
fi

echo ""
echo "Test complete!"
