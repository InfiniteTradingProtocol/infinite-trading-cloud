#!/bin/bash
# Migrate R services from screen sessions to PM2 on EC2

echo "🚀 Migrating R Services to PM2..."
echo ""

# Check if running on EC2
if [ ! -f "/home/ubuntu/infinitetrading_api/express/ecosystem.config.js" ]; then
    echo "❌ This script must be run on EC2"
    exit 1
fi

cd /home/ubuntu/infinitetrading_api/express

echo "📋 Current screen sessions:"
screen -ls
echo ""

echo "⏸️  Step 1: Stopping Gateway screen session..."
screen -S gateway -X quit 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Gateway screen session stopped"
else
    echo "⚠️  Gateway screen session not found (already stopped?)"
fi

echo ""
echo "⏸️  Step 2: Stopping Plumber screen session..."
screen -S plumber -X quit 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Plumber screen session stopped"
else
    echo "⚠️  Plumber screen session not found (already stopped?)"
fi

echo ""
echo "🔍 Step 3: Verifying ports are free..."
sleep 2

# Check port 8002
if lsof -Pi :8002 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "❌ Port 8002 is still in use!"
    echo "   Run: lsof -i :8002 to investigate"
    exit 1
fi

# Check port 8003
if lsof -Pi :8003 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "❌ Port 8003 is still in use!"
    echo "   Run: lsof -i :8003 to investigate"
    exit 1
fi

echo "✅ Ports 8002 and 8003 are free"

echo ""
echo "🚀 Step 4: Starting all services with PM2..."
pm2 restart ecosystem.config.js

echo ""
echo "⏳ Waiting for services to start (10 seconds)..."
sleep 10

echo ""
echo "📊 Step 5: Checking PM2 status..."
pm2 status

echo ""
echo "🧪 Step 6: Testing services..."

# Test Express
if curl -s http://localhost:8000/ > /dev/null 2>&1; then
    echo "✅ Express API (port 8000) is responding"
else
    echo "❌ Express API (port 8000) is NOT responding"
fi

# Test Plumber
if curl -s http://localhost:8002/__docs__/ > /dev/null 2>&1; then
    echo "✅ Plumber API (port 8002) is responding"
else
    echo "❌ Plumber API (port 8002) is NOT responding"
fi

# Test Gateway
if curl -s http://localhost:8003/__docs__/ > /dev/null 2>&1; then
    echo "✅ Gateway (port 8003) is responding"
else
    echo "❌ Gateway (port 8003) is NOT responding"
fi

echo ""
echo "💾 Step 7: Saving PM2 configuration..."
pm2 save

echo ""
echo "✅ Migration complete!"
echo ""
echo "📝 Useful commands:"
echo "   pm2 status                     # View all services"
echo "   pm2 logs                       # View all logs"
echo "   pm2 logs api-gateway           # Gateway logs only"
echo "   pm2 logs plumber-api           # Plumber logs only"
echo "   pm2 logs infinitetrading-api   # Express logs only"
echo "   pm2 restart api-gateway        # Restart Gateway"
echo "   pm2 restart plumber-api        # Restart Plumber"
echo "   pm2 restart all                # Restart everything"
echo ""
echo "⚠️  Remember to update startup.sh if needed!"
