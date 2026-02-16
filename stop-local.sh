#!/bin/bash
# Stop all PM2 services locally

cd "$(dirname "$0")"

echo "🛑 Stopping all PM2 services..."
echo ""

# Show current status
echo "Current PM2 processes:"
pm2 list

echo ""
echo "Stopping all processes..."
pm2 stop all

echo ""
echo "Deleting PM2 processes..."
pm2 delete all

echo ""
echo "✅ All services stopped and removed from PM2"
echo ""
echo "💡 To start again, run: ./start-local.sh"
echo ""
