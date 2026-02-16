#!/bin/bash
# Local startup script using PM2 for all services

cd "$(dirname "$0")"

echo "🚀 Starting Infinite Trading Services with PM2..."
echo ""

# Check if PM2 is installed
if ! command -v pm2 &> /dev/null; then
    echo "❌ PM2 not installed!"
    echo "   Install with: npm install -g pm2"
    exit 1
fi

# Create logs directories
mkdir -p express/logs
mkdir -p plumber/logs
mkdir -p strategies/logs
mkdir -p tradebot/logs
mkdir -p data-collectors/logs

echo "📦 Building Express API..."
cd express
npm run build > logs/build.log 2>&1
if [ $? -ne 0 ]; then
    echo "❌ Express build failed! Check express/logs/build.log"
    exit 1
fi
cd ..
echo "✅ Build complete"
echo ""

echo "🔄 Stopping any existing PM2 processes..."
pm2 delete all 2>/dev/null || true
echo ""

echo "🚀 Starting all services with PM2..."
pm2 start ecosystem-local.config.js

echo ""
echo "⏳ Waiting for services to start up (10 seconds)..."
sleep 10

echo ""
echo "📊 PM2 Status:"
pm2 list

echo ""
echo "🧪 Testing core services..."

# Test Express
if curl -s http://localhost:8000/ > /dev/null 2>&1; then
    echo "✅ Express API (port 8000) is running"
else
    echo "❌ Express API (port 8000) failed to start"
    echo "   Check logs with: pm2 logs express-api"
fi

# Test Plumber
if curl -s http://localhost:8002/__docs__/ > /dev/null 2>&1; then
    echo "✅ Plumber API (port 8002) is running"
else
    echo "❌ Plumber API (port 8002) failed to start"
    echo "   Check logs with: pm2 logs plumber-api"
fi

# Test Gateway
if curl -s http://localhost:8003/__docs__/ > /dev/null 2>&1; then
    echo "✅ Gateway (port 8003) is running"
else
    echo "❌ Gateway (port 8003) failed to start"
    echo "   Check logs with: pm2 logs gateway"
fi

echo ""
echo "✅ All services started!"
echo ""
echo "📝 Service URLs:"
echo "   Express API:  http://localhost:8000"
echo "   Plumber API:  http://localhost:8002/__docs__/"
echo "   Gateway:      http://localhost:8003/__docs__/"
echo ""
echo "📊 Total processes: 22"
echo "   - 3 API services"
echo "   - 11 strategy bots"
echo "   - 6 tradebot threads"
echo "   - 2 data collectors (disabled by default)"
echo ""
echo "🛑 To stop all services:"
echo "   ./stop-local.sh"
echo "   OR: pm2 stop all"
echo ""
echo "📊 To view status:"
echo "   pm2 list"
echo "   pm2 monit"
echo ""
echo "📝 To view logs:"
echo "   pm2 logs              # All logs"
echo "   pm2 logs express-api  # Specific service"
echo "   pm2 logs --lines 100  # Last 100 lines"
echo ""
echo "🔄 To restart a service:"
echo "   pm2 restart express-api"
echo "   pm2 restart all"
echo ""