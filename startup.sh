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

# ========================================
# ARCHIVED: Screen-based process management
# These screen launches have been migrated to PM2
# Kept here for reference only
# ========================================
# screen -dmS tradeBot -h 1000 bash -c 'cd ~/infinitetrading/src/api && ./infinite.sh trading.R'
# screen -dmS gasMonitor -h 1000 bash -c 'cd ~/infinitetrading/src/api && ./infinite.sh gasMonitor.R'
# screen -dmS pools -h 1000 bash -c 'cd ~/infinitetrading/src/tradebot && ./infinite.sh pools.R'
# screen -dmS prices -h 500 bash -c 'cd ~/infinitetrading/src && ./infinite.sh prices.R'
# screen -dmS yields -h 1000 bash -c 'cd ~/infinitetrading/src/api && ./infinite.sh yields.R'
# screen -dmS ethEmaCrossover -h 1000 bash -c 'cd ~/infinitetrading/src/strategies && ./infinite.sh eth_ema_11_33_crossover.R'
# screen -dmS aeroEmaCrossover -h 1000 bash -c 'cd ~/infinitetrading/src/strategies && ./infinite.sh aero_ema_11_33_crossover.R'
# screen -dmS Velo1DBot -h 1000 bash -c 'cd ~/infinitetrading/src/strategies && ./infinite.sh Velo1DBot.R'
# screen -dmS superTrend -h 1000 bash -c 'cd ~/infinitetrading/src/strategies && ./infinite.sh superTrend.R'
# screen -dmS cbBTC_probability_model -h 1000 bash -c 'cd ~/infinitetrading/src/strategies && ./infinite.sh cbBTC_probability_model.R'
# screen -dmS OP_probability_model -h 1000 bash -c 'cd ~/infinitetrading/src/strategies && ./infinite.sh OP_probability_model.R'
# screen -dmS crossOvers -h 1000 bash -c 'cd ~/infinitetrading/src/strategies && ./infinite.sh crossOvers.R'
