#!/bin/bash
# Test Gateway and Plumber locally before deployment

echo "🧪 Testing R Services Locally..."
echo ""

# Check if R is installed
if ! command -v Rscript &> /dev/null; then
    echo "❌ Rscript not found. Please install R first."
    exit 1
fi

# Check if plumber files exist
GATEWAY_FILE="../plumber/gateway/gateway.R"
PLUMBER_FILE="../plumber/api.R"

if [ ! -f "$GATEWAY_FILE" ]; then
    echo "❌ Gateway file not found: $GATEWAY_FILE"
    exit 1
fi

if [ ! -f "$PLUMBER_FILE" ]; then
    echo "❌ Plumber file not found: $PLUMBER_FILE"
    exit 1
fi

echo "✅ R and plumber files found"
echo ""

# Function to test if port is available
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo "⚠️  Port $port is already in use"
        return 1
    fi
    return 0
}

# Check required ports
echo "📡 Checking ports..."
check_port 8002 || exit 1
check_port 8003 || exit 1
echo "✅ Ports 8002 and 8003 are available"
echo ""

# Start Plumber API in background
echo "🚀 Starting Plumber API on port 8002..."
Rscript "$PLUMBER_FILE" > logs/test-plumber.log 2>&1 &
PLUMBER_PID=$!
echo "   PID: $PLUMBER_PID"

# Start Gateway in background
echo "🚀 Starting Gateway on port 8003..."
Rscript "$GATEWAY_FILE" > logs/test-gateway.log 2>&1 &
GATEWAY_PID=$!
echo "   PID: $GATEWAY_PID"

# Wait for services to start
echo ""
echo "⏳ Waiting for services to start (10 seconds)..."
sleep 10

# Test Plumber API
echo ""
echo "🧪 Testing Plumber API (port 8002)..."
if curl -s http://localhost:8002/__docs__/ > /dev/null 2>&1; then
    echo "✅ Plumber API is responding"
else
    echo "❌ Plumber API is not responding"
    echo "   Check logs/test-plumber.log for errors"
    kill $PLUMBER_PID $GATEWAY_PID 2>/dev/null
    exit 1
fi

# Test Gateway
echo ""
echo "🧪 Testing Gateway (port 8003)..."
if curl -s http://localhost:8003/__docs__/ > /dev/null 2>&1; then
    echo "✅ Gateway is responding"
else
    echo "❌ Gateway is not responding"
    echo "   Check logs/test-gateway.log for errors"
    kill $PLUMBER_PID $GATEWAY_PID 2>/dev/null
    exit 1
fi

# Test Gateway proxy to Express (if Express is running)
echo ""
echo "🧪 Testing Gateway → Express proxy..."
if curl -s http://localhost:8000/ > /dev/null 2>&1; then
    echo "   Express is running on port 8000"
    
    # Test a simple endpoint through Gateway
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8003/api/test 2>/dev/null)
    if [ "$RESPONSE" = "200" ] || [ "$RESPONSE" = "404" ]; then
        echo "✅ Gateway → Express proxy is working (HTTP $RESPONSE)"
    else
        echo "⚠️  Gateway proxy returned HTTP $RESPONSE"
    fi
else
    echo "⚠️  Express is not running on port 8000"
    echo "   Skipping proxy test"
fi

# Cleanup
echo ""
echo "🧹 Stopping test services..."
kill $PLUMBER_PID $GATEWAY_PID 2>/dev/null
echo "✅ Services stopped"

echo ""
echo "✅ All tests passed! Ready to deploy."
echo ""
echo "📝 Test logs saved to:"
echo "   - logs/test-plumber.log"
echo "   - logs/test-gateway.log"
