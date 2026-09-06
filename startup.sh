#!/bin/bash

# Infinitetrading Startup Script
# Updated: 2026-02-17
# Migration: Screen sessions → PM2 process manager
# All trading, monitoring, and strategy processes now managed by PM2

echo "==================================="
echo "Starting Infinitetrading Services"
echo "==================================="

# Check and start Redis
if ! pgrep -x "redis-server" > /dev/null; then
    echo "Starting Redis..."
    redis-server --daemonize yes
else
    echo "Redis already running"
fi

# Give Redis time to start
sleep 2

# Start all services via PM2
echo "Starting PM2 services..."
cd ~/infinitetrading_api
pm2 start ecosystem.config.js
pm2 save

echo "==================================="
echo "All services started successfully!"
echo "==================================="
echo ""
echo "Monitor services with: pm2 list"
echo "View logs with: pm2 logs [service-name]"
echo "Restart service: pm2 restart [service-name]"
echo ""

# Display PM2 status
pm2 list
