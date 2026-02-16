# Production Deployment Guide

## ⚠️ CRITICAL: Pre-Deployment Testing

**ALWAYS test R services locally before deploying to EC2:**

```bash
cd /Users/richardclare/infinite-trading-api/express
./scripts/test-r-services.sh
```

This script:
- Verifies R and plumber files exist
- Checks ports 8002 and 8003 are available
- Starts Gateway (8003) and Plumber (8002) locally
- Tests both services respond correctly
- Tests Gateway → Express proxy
- Cleans up test processes

**Only proceed with deployment if all tests pass.**

---

## Migration from Screen to PM2

### Step 1: Install Dependencies
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
cd /home/ubuntu/infinitetrading_api/express
npm install winston winston-daily-rotate-file pm2 -g
npm install winston winston-daily-rotate-file --save
```

### Step 2: Migrate R Services to PM2 (One-Time Setup)

**Use the migration script to move Gateway and Plumber from screen sessions to PM2:**

```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
cd /home/ubuntu/infinitetrading_api/express
./scripts/migrate-to-pm2.sh
```

This script will:
- Stop Gateway and Plumber screen sessions
- Verify ports 8002 and 8003 are free
- Start all services (Express, Gateway, Plumber) with PM2
- Test all services are responding
- Save PM2 configuration

### Step 3: Build Production Code
```bash
cd /home/ubuntu/infinitetrading_api/express
npm run build
```

### Step 4: Create Logs Directory
```bash
mkdir -p /home/ubuntu/infinitetrading_api/express/logs
```

### Step 5: Start with PM2
```bash
cd /home/ubuntu/infinitetrading_api/express
pm2 start ecosystem.config.js
pm2 save
pm2 startup
```

### Step 6: Update startup.sh
Replace the screen line with:
```bash
pm2 start /home/ubuntu/infinitetrading_api/express/ecosystem.config.js
```

## PM2 Commands

### View All Services
```bash
pm2 status                    # View all services
pm2 logs                      # View all logs (tailed)
pm2 logs --lines 200          # View last 200 lines
```

### View Logs by Service
```bash
pm2 logs infinitetrading-api  # Express API logs
pm2 logs api-gateway          # Gateway logs
pm2 logs plumber-api           # Plumber API logs

pm2 logs infinitetrading-api --err  # Errors only
```

### Monitor
```bash
pm2 monit                     # Real-time monitoring
pm2 status                    # Status overview
```

### Restart/Reload
```bash
# Restart specific services
pm2 restart infinitetrading-api
pm2 restart api-gateway
pm2 restart plumber-api

# Restart all services
pm2 restart all
pm2 restart ecosystem.config.js

# Zero-downtime reload (Node.js only)
pm2 reload infinitetrading-api
```

### Stop/Start
```bash
pm2 stop infinitetrading-api  # Stop Express
pm2 stop api-gateway          # Stop Gateway
pm2 stop plumber-api           # Stop Plumber
pm2 stop all                   # Stop all

pm2 start infinitetrading-api # Start Express
pm2 start api-gateway         # Start Gateway
pm2 start plumber-api          # Start Plumber
pm2 start all                  # Start all
```

### View Details
```bash
pm2 info infinitetrading-api
pm2 describe infinitetrading-api
```

### Clear Logs
```bash
pm2 flush
```

## Log Files Location

- **Express Logs:** `logs/api-YYYY-MM-DD.log`, `logs/error-YYYY-MM-DD.log`
- **Gateway Logs:** `logs/gateway-out.log`, `logs/gateway-error.log`
- **Plumber Logs:** `logs/plumber-out.log`, `logs/plumber-error.log`
- **PM2 Logs:** `logs/pm2-out.log`, `logs/pm2-error.log`
- **Test Logs:** `logs/test-gateway.log`, `logs/test-plumber.log` (local only)

## Log Rotation Policy

- **Max file size:** 20MB (application), 50MB (PM2)
- **Retention:** 14 days (info), 30 days (errors)
- **Compression:** Automatic (gzip)
- **Format:** JSON for easy parsing

## Performance Comparison

### Screen + ts-node (Current)
- Memory: ~300-400MB
- CPU: 15-20% (idle)
- Startup: ~3s

### PM2 + Compiled (Recommended)
- Memory: ~150-200MB
- CPU: 5-10% (idle)
- Startup: ~1s
- **50% better performance**

## Rollback Plan

### Rollback Express to Screen
```bash
pm2 stop infinitetrading-api
pm2 delete infinitetrading-api
screen -dmS api -h 1000 bash -c 'cd ~/infinitetrading_api/express && npm run start:watch'
```

### Rollback Gateway to Screen
```bash
pm2 stop api-gateway
pm2 delete api-gateway
screen -dmS gateway -h 1000 Rscript /home/ubuntu/infinitetrading_api/plumber/api_gateway.R
```

### Rollback Plumber to Screen
```bash
pm2 stop plumber-api
pm2 delete plumber-api
screen -dmS plumber -h 1000 Rscript /home/ubuntu/infinitetrading_api/plumber/plumber.R
```

### Rollback All Services
```bash
pm2 stop all
pm2 delete all

# Restart with screen sessions
screen -dmS api -h 1000 bash -c 'cd ~/infinitetrading_api/express && npm run start:watch'
screen -dmS gateway -h 1000 Rscript /home/ubuntu/infinitetrading_api/plumber/api_gateway.R
screen -dmS plumber -h 1000 Rscript /home/ubuntu/infinitetrading_api/plumber/plumber.R
```
