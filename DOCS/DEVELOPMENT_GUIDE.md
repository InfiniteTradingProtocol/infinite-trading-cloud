# Development Guide

This guide covers the complete development workflow for the Infinite Trading API, from local development to EC2 production deployment.

## 📋 Table of Contents

1. [Environment Setup](#environment-setup)
2. [Local Development](#local-development)
3. [Testing](#testing)
4. [Deployment Workflow](#deployment-workflow)
5. [Troubleshooting](#troubleshooting)

## 🔧 Environment Setup

### EC2 Production Environment

The production system runs on AWS EC2 with the following specifications:

- **Host:** `ec2-3-135-99-211.us-east-2.compute.amazonaws.com`
- **Node.js:** v22.18.0
- **npm:** v10.9.3
- **Redis:** v6.0.16
- **PM2:** v6.0.14
- **TypeScript:** v4.9.5 (via package.json)
- **Process Manager:** PM2 (replaces screen sessions)

### Local Development Environment

Your local environment should match production as closely as possible.

#### Required Software

1. **Node.js v22.18.0**
   ```bash
   # Using nvm (recommended)
   nvm install 22.18.0
   nvm use 22.18.0
   
   # Verify
   node --version  # Should show v22.18.0
   ```

2. **Redis Server**
   ```bash
   # macOS
   brew install redis
   brew services start redis
   
   # Verify
   redis-cli ping  # Should return PONG
   ```

3. **MySQL Client** (for database access)
   ```bash
   # macOS
   brew install mysql-client
   
   # Add to PATH (add to ~/.zshrc or ~/.bash_profile)
   echo 'export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"' >> ~/.zshrc
   source ~/.zshrc
   
   # Verify
   mysql --version
   
   # Test connection to production database
   mysql -urichard_clare -p -h3.135.99.211 infinitetrading -e "SELECT 1;"
   ```
   
   **Note:** MySQL is installed on EC2 (3.135.99.211) and accessible remotely. You can query the production database directly from your local machine without SSH tunneling.

4. **PM2 (Optional for local testing)**
   ```bash
   npm install -g pm2
   ```

#### Initial Setup

1. **Clone and setup**
   ```bash
   cd /path/to/infinite-trading-api/express
   ```

2. **Create .env file**
   ```bash
   # Create .env with required variables
   cat > .env << EOF
   PRIVATE_KEY=your_private_key_here
   INFURA_PROJECT_ID=your_infura_project_id
   # Add other environment variables as needed
   EOF
   ```

3. **Run setup script**
   ```bash
   ./scripts/local-setup.sh
   ```

   This script will:
   - ✓ Verify Node.js version matches EC2
   - ✓ Check Redis installation
   - ✓ Install npm dependencies
   - ✓ Build TypeScript
   - ✓ Run type checking
   - ✓ Verify build output

## 💻 Local Development

### ⚠️ Critical: Dual Environment Synchronization

**IMPORTANT:** When fixing issues on EC2, always check and fix the local environment too!

The local environment is an upgraded version of EC2 that we're migrating to, but we're still making changes on EC2. This means:

- ✅ **Fix on EC2 → Check local immediately**
- ✅ **Any bug fix must be applied to BOTH environments**
- ✅ **Test the fix works on both sides**
- ✅ **Keep environments in sync for smooth migration**

Common areas requiring dual fixes:
- Package versions (keras, tensorflow, R packages)
- Database connection parameters
- File paths and working directories
- Environment variables
- PM2 configurations

### Development Server

Start the development server with hot reload:

```bash
cd express
npm run start:watch
```

The server will run on `http://localhost:8000`

### Test Server

For testing without affecting production data:

```bash
npx ts-node src/index_test.ts
```

The test server runs on `http://localhost:8001`

### Making Changes

1. **Edit TypeScript files** in `src/`
2. **Hot reload** automatically picks up changes (with `start:watch`)
3. **Test endpoints** using curl or Postman
4. **Check logs** in the terminal

### Project Structure

```
express/
├── src/
│   ├── requests/           # API endpoint handlers
│   │   ├── trade.ts        # Main trading endpoints
│   │   ├── admin.ts        # Admin endpoints
│   │   ├── invest.ts       # Investment operations
│   │   └── lending.ts      # Lending/borrowing
│   ├── utils/              # Utility functions
│   │   ├── pool.ts         # Pool operations
│   │   ├── ERC20.ts        # Token interactions
│   │   ├── txOptions.ts    # Transaction builders
│   │   └── redis.ts        # Redis caching
│   ├── index.ts            # Main server (port 8000)
│   ├── index_test.ts       # Test server (port 8001)
│   ├── dhedge.ts           # dHEDGE SDK setup
│   ├── wallet.ts           # Wallet management
│   └── rpc.ts              # RPC providers
├── build/                  # Compiled JavaScript (gitignored)
├── logs/                   # Application logs
├── scripts/                # Deployment scripts
│   ├── local-setup.sh      # Local environment setup
│   └── deploy-to-ec2.sh    # EC2 deployment
├── package.json
├── tsconfig.json
└── ecosystem.config.js     # PM2 configuration
```

## 🧪 Testing

### Manual Testing

1. **Start local server**
   ```bash
   npm run start:watch
   ```

2. **Test trade endpoint**
   ```bash
   curl "http://localhost:8000/trade?network=polygon&pool=0xPoolAddress&from=0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174&to=0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619&platform=uniswapv3&slippage=0.5&amount=1000000&manager=infinitetrading"
   ```

3. **Check Redis connection**
   ```bash
   redis-cli
   > keys *
   > get some_key
   ```

### Database Testing

The production MySQL database (3.135.99.211) is accessible directly from your local machine:

```bash
# Check candles data completeness
mysql -urichard_clare -p -h3.135.99.211 infinitetrading -e "
SELECT 
    TABLE_NAME as 'Table',
    TABLE_ROWS as 'Row Count'
FROM information_schema.TABLES 
WHERE TABLE_SCHEMA = 'infinitetrading' 
AND TABLE_NAME LIKE 'coinbase_%'
ORDER BY TABLE_NAME;
"

# Validate specific pair data
mysql -urichard_clare -p -h3.135.99.211 infinitetrading -e "
SELECT 
    COUNT(*) as total,
    FROM_UNIXTIME(MIN(time)) as oldest,
    FROM_UNIXTIME(MAX(time)) as newest
FROM \`coinbase_BTC-USD_6h\`;
"

# Check for gaps in time series
mysql -urichard_clare -p -h3.135.99.211 infinitetrading -e "
SELECT t1.id, 
       FROM_UNIXTIME(t1.time) as candle_time,
       FROM_UNIXTIME(t2.time) as next_candle,
       (t2.time - t1.time) as gap_seconds
FROM \`coinbase_BTC-USD_6h\` t1
JOIN \`coinbase_BTC-USD_6h\` t2 ON t2.id = t1.id + 1
WHERE (t2.time - t1.time) > 21600
LIMIT 10;
"
```

**Database Credentials:**
- Host: `3.135.99.211`
- User: `richard_clare`
- Database: `infinitetrading`
- Port: `3306` (default)

**Note:** No SSH required - MySQL port 3306 is exposed on EC2 for remote access.

### Build Testing

Before deploying, always test the build:

```bash
# Clean build
rm -rf build/
npm run build

# Check for TypeScript errors
npx tsc --noEmit

# Test compiled output
node build/src/index.js
```

### Common Test Scenarios

1. **Verify asset addresses** - Full 0x addresses required
2. **Check slippage tolerance** - Reasonable values (0.1-5%)
3. **Test different networks** - polygon, optimism, arbitrum, base, ethereum
4. **Validate API responses** - Proper error handling

## 🚀 Deployment Workflow

### Overview

```
Local Development → Test Locally → Build & Verify → Deploy to EC2 → Verify Production
```

### Step-by-Step Deployment

#### 1. Pre-Deployment Checklist

- [ ] All changes tested locally
- [ ] No TypeScript errors (`npx tsc --noEmit`)
- [ ] Build succeeds (`npm run build`)
- [ ] .env file configured
- [ ] Redis running locally
- [ ] No uncommitted critical changes

#### 2. Run Local Setup

```bash
./scripts/local-setup.sh
```

Verify output shows:
- ✓ Node.js version matches EC2
- ✓ Build successful
- ✓ No TypeScript errors

#### 3. Deploy to EC2

```bash
./scripts/deploy-to-ec2.sh
```

The script will:
1. ✓ Test local build
2. ✓ Run TypeScript checks
3. ✓ Prompt for confirmation
4. ✓ Create backup on EC2
5. ✓ Sync files via rsync
6. ✓ Install dependencies on EC2
7. ✓ Build on EC2
8. ✓ Restart PM2 service
9. ✓ Verify deployment

#### 4. Post-Deployment Verification

```bash
# SSH to EC2
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# Check PM2 status
pm2 status

# View logs
pm2 logs infinitetrading-api --lines 50

# Monitor in real-time
pm2 monit
```

#### 5. Test Production Endpoints

Replace `localhost:8000` with EC2 public IP or domain to test production endpoints.

### Rollback Procedure

If deployment fails:

```bash
# SSH to EC2
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# Navigate to express directory
cd /home/ubuntu/infinitetrading_api/express

# List backups
ls -lh backups/

# Extract backup
tar -xzf backups/backup-YYYYMMDD-HHMMSS.tar.gz

# Rebuild
npm install
npm run build

# Restart
pm2 restart infinitetrading-api
```

## 🔍 Troubleshooting

### Common Issues

#### Build Failures

**Problem:** TypeScript compilation errors

**Solution:**
```bash
# Check for errors
npx tsc --noEmit

# Clean and rebuild
rm -rf build/ node_modules/
npm install
npm run build
```

#### Node Version Mismatch

**Problem:** Different Node.js version locally vs EC2

**Solution:**
```bash
# Install correct version
nvm install 22.18.0
nvm use 22.18.0

# Make it default
nvm alias default 22.18.0
```

#### Redis Connection Issues

**Problem:** Cannot connect to Redis

**Solution:**
```bash
# Check if Redis is running
redis-cli ping

# Start Redis (macOS)
brew services start redis

# Check Redis logs
brew services info redis
```

#### PM2 Service Not Starting

**Problem:** PM2 app shows "errored" status

**Solution:**
```bash
# SSH to EC2
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# Check logs for errors
pm2 logs infinitetrading-api --err

# Check if port is in use
sudo lsof -i :8000

# Restart with fresh state
pm2 delete infinitetrading-api
pm2 start ecosystem.config.js
```

#### File Sync Issues

**Problem:** rsync fails during deployment

**Solution:**
```bash
# Test SSH connection
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com "echo 'Connection OK'"

# Check file permissions
ls -la express/scripts/

# Manual sync (dry-run)
rsync -avzn --exclude 'node_modules' --exclude 'build' \
  -e "ssh -i ~/.ssh/macbook.pem" \
  ./express/ \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:/home/ubuntu/infinitetrading_api/express/
```

### Debugging Tips

1. **Check PM2 logs first**
   ```bash
   pm2 logs infinitetrading-api --lines 100
   ```

2. **Verify environment variables**
   ```bash
   # On EC2
   cd /home/ubuntu/infinitetrading_api/express
   cat .env | grep -v "PRIVATE_KEY"
   ```

3. **Test Redis connectivity**
   ```bash
   # On EC2
   redis-cli ping
   redis-cli info
   ```

4. **Check system resources**
   ```bash
   pm2 monit  # Shows CPU and memory usage
   ```

5. **Review build output**
   ```bash
   ls -lh build/src/
   cat build/src/index.js | head -20
   ```

## 🔧 SDK Customization

### dHEDGE v2 SDK - ODOS Referral Configuration

**Current Setup (as of SDK v2.1.5):**

The dHEDGE v2 SDK has hardcoded ODOS referral addresses. We've patched these to use our own referral address.

**Our Referral Address:** `0xb5dB6e5a301E595B76F40319896a8dbDc277CEfB`

**SDK Files Patched:**
- `node_modules/@dhedge/v2-sdk/dist/v2-sdk.esm.js` (line 4402)
- `node_modules/@dhedge/v2-sdk/dist/v2-sdk.cjs.production.min.js`

**What Changed in SDK v2.1.5:**
- **NEW:** `ODOS_API_KEY` environment variable required (previously optional)
- **NEW:** Hardcoded referral addresses (replaced dHEDGE's addresses with ours)
- **REMOVED:** Support for custom `ODOS_REFERAL_CODE` variable
- Referral fee: Fixed at 2 basis points (0.02%)

**Environment Variables:**
```bash
# .env file
ODOS_API_KEY="3381349474"  # Required for ODOS API authentication
```

**⚠️ Important:** These patches are applied to `node_modules` and will be lost if you run `npm install`. 

**To Reapply Patches After npm install:**

Local:
```bash
cd /Users/richardclare/infinite-trading-api/express
sed -i '' 's/0x090e7fbD87A673eE3D0B6ccACf0e1d94fB90DA59/0xb5dB6e5a301E595B76F40319896a8dbDc277CEfB/g' node_modules/@dhedge/v2-sdk/dist/v2-sdk.cjs.production.min.js
sed -i '' 's/0x813123A13d01d3F07d434673Fdc89cBBA523f14d/0xb5dB6e5a301E595B76F40319896a8dbDc277CEfB/g' node_modules/@dhedge/v2-sdk/dist/v2-sdk.cjs.production.min.js
sed -i '' 's/0xfbD2B4216f422DC1eEe1Cff4Fb64B726F099dEF5/0xb5dB6e5a301E595B76F40319896a8dbDc277CEfB/g' node_modules/@dhedge/v2-sdk/dist/v2-sdk.cjs.production.min.js
sed -i '' 's/0x5619AD05b0253a7e647Bd2E4C01c7f40CEaB0879/0xb5dB6e5a301E595B76F40319896a8dbDc277CEfB/g' node_modules/@dhedge/v2-sdk/dist/v2-sdk.cjs.production.min.js
```

EC2:
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
cd /home/ubuntu/infinitetrading_api/express
sed -i 's/0x090e7fbD87A673eE3D0B6ccACf0e1d94fB90DA59/0xb5dB6e5a301E595B76F40319896a8dbDc277CEfB/g' node_modules/@dhedge/v2-sdk/dist/v2-sdk.cjs.production.min.js
sed -i 's/0x813123A13d01d3F07d434673Fdc89cBBA523f14d/0xb5dB6e5a301E595B76F40319896a8dbDc277CEfB/g' node_modules/@dhedge/v2-sdk/dist/v2-sdk.cjs.production.min.js
sed -i 's/0xfbD2B4216f422DC1eEe1Cff4Fb64B726F099dEF5/0xb5dB6e5a301E595B76F40319896a8dbDc277CEfB/g' node_modules/@dhedge/v2-sdk/dist/v2-sdk.cjs.production.min.js
sed -i 's/0x5619AD05b0253a7e647Bd2E4C01c7f40CEaB0879/0xb5dB6e5a301E595B76F40319896a8dbDc277CEfB/g' node_modules/@dhedge/v2-sdk/dist/v2-sdk.cjs.production.min.js
pm2 restart ecosystem.config.js
```

**Networks Receiving Referral Fees:**
- Polygon
- Optimism  
- Arbitrum
- Base
- Ethereum
- PLASMA

---

## 🔄 Process Management: Screen to PM2 Migration

### Overview

All production services have been migrated from **screen sessions** to **PM2 process manager** for improved reliability, monitoring, and management.

**Migration Date:** February 17, 2026  
**Reason:** Centralized process management, automatic restarts, structured logging, resource monitoring

### Before: Screen-Based Management

Previously, 12+ services ran in separate screen sessions:
- **Trading:** `tradeBot` (trading.R)
- **Monitoring:** `gasMonitor`, `pools`, `prices`, `yields`
- **Strategies:** `ethEmaCrossover`, `aeroEmaCrossover`, `Velo1DBot`, `superTrend`, `cbBTC_probability_model`, `OP_probability_model`, `crossOvers`

**Limitations:**
- ❌ No centralized monitoring
- ❌ Manual restart required on crashes
- ❌ Difficult log management
- ❌ No resource usage visibility
- ❌ Hard to track process health

### After: PM2 Process Manager

All 19 services now run under PM2:

**API Services:**
- `infinitetrading-api` (port 8000) - Node.js trading API
- `api-gateway` (port 8003) - R gateway service
- `plumber-api` (port 8002) - R plumber API

**Data Collectors:**
- `candles-collector` - Python candle data collector
- `messages-collector` - Python message processor

**ML & Analytics:**
- `ml-models` - R machine learning models

**Trading & Monitoring:**
- `tradebot` - Main trading bot (monitors 5 networks: polygon, optimism, base, arbitrum, ethereum)
- `gas-monitor` - Gas price monitoring
- `pools-monitor` - Pool balance monitoring
- `prices-monitor` - Price data collection
- `yields-monitor` - Yield tracking

**Trading Strategies:**
- `strategy-eth-ema-crossover` - ETH EMA 11/33 crossover
- `strategy-aero-ema-crossover` - AERO EMA 11/33 crossover
- `strategy-velo1d-bot` - Velo 1D strategy
- `strategy-supertrend` - SuperTrend indicator
- `strategy-cbbtc-probability` - cbBTC probability model
- `strategy-op-probability` - OP probability model
- `strategy-crossovers` - Multi-pair crossover strategy

### PM2 Benefits

✅ **Automatic Restarts:** Services restart automatically on crashes  
✅ **Centralized Logs:** `pm2 logs [service-name]`  
✅ **Resource Monitoring:** CPU, memory usage visible via `pm2 monit`  
✅ **Health Tracking:** Restart count, uptime, status at a glance  
✅ **Log Rotation:** Automatic log file rotation (50MB max, 10 files retained, compressed)  
✅ **Process Persistence:** `pm2 save` ensures services restart on server reboot

### Configuration: ecosystem.config.js

Location: `/home/ubuntu/infinitetrading_api/ecosystem.config.js`

**Key Configuration Elements:**
```javascript
{
  name: "tradebot",
  script: "Rscript",
  args: "api/trading.R",
  cwd: "/home/ubuntu/infinitetrading/src",  // CRITICAL: Sets working directory for .env loading
  max_memory_restart: "1G",                   // Restart if memory exceeds 1GB
  autorestart: true,
  max_restarts: 100,
  min_uptime: "30s",                          // Must run 30s to count as successful start
  error_file: "logs/tradebot-error.log",
  out_file: "logs/tradebot-out.log",
  log_date_format: "YYYY-MM-DD HH:mm:ss Z",
  max_size: "50M",                            // Log rotation at 50MB
  retain: 10,                                 // Keep 10 old log files
  compress: true                              // Compress rotated logs
}
```

**Critical Setting: `cwd` (Current Working Directory)**

R scripts load environment variables from `.env` files using relative paths. The `cwd` setting ensures:
- `dotenv::load_dot_env("../.env")` or `source(".env")` works correctly
- Database credentials load properly
- API keys are accessible

**Working Directory by Service Type:**
- **R Scripts (infinitetrading/src):** `cwd: "/home/ubuntu/infinitetrading/src"`
- **Node.js API:** `cwd: "/home/ubuntu/infinitetrading_api/express"`
- **Python Scripts:** `cwd: "/home/ubuntu/infinitetrading/src"`

### Environment Variables

**R Services:** Load from `/home/ubuntu/infinitetrading/src/.env`
```bash
db_user="richard_clare"
db_password="..."
dbname="infinitetrading"
host="localhost"
cmc_apikey="..."
ITP_APIKEY="..."
COINGECKO_APIKEY="..."
TG_BOT="..."
TG_CHAT_ID="..."
ALCHEMY_BALANCES_APIKEY="..."
```

**Node.js Services:** Load from `/home/ubuntu/infinitetrading_api/express/.env`
```bash
INFURA_PROJECT_ID="..."
INFURA_SECRET="..."
PRIVATE_KEY="..."
ODOS_API_KEY="3381349474"
```

### Common PM2 Commands

**View All Services:**
```bash
pm2 list
```

**View Service Logs:**
```bash
pm2 logs tradebot              # Follow logs in real-time
pm2 logs tradebot --lines 100  # Show last 100 lines
pm2 logs --nostream            # Show recent logs, don't follow
```

**Restart Services:**
```bash
pm2 restart tradebot           # Restart single service
pm2 restart all                # Restart all services
pm2 reload ecosystem.config.js # Reload configuration
```

**Monitor Resources:**
```bash
pm2 monit                      # Interactive monitoring dashboard
```

**Service Details:**
```bash
pm2 info tradebot              # Detailed service information
pm2 env 12                     # Show environment variables (use ID from pm2 list)
```

**Stop/Delete Services:**
```bash
pm2 stop tradebot              # Stop but keep in process list
pm2 delete tradebot            # Remove from process list
pm2 stop all                   # Stop all services
```

**Save Configuration:**
```bash
pm2 save                       # Save current process list (for reboot persistence)
```

### Startup Script: startup.sh

Location: `/home/ubuntu/startup.sh`

**Purpose:** Executed on EC2 boot to start all services

**Current Implementation:**
```bash
#!/bin/bash
echo "Starting Infinitetrading Services"

# Start Redis
if ! pgrep -x "redis-server" > /dev/null; then
    redis-server --daemonize yes
fi

# Start all PM2 services
cd ~/infinitetrading_api
pm2 start ecosystem.config.js
pm2 save

pm2 list
```

**Previous screen launches are archived as comments** for reference.

### Migration Lessons Learned

#### 1. Working Directory (cwd) is Critical

**Problem:** Service fails with "cannot find .env" or "database connection failed"  
**Solution:** Set `cwd` in PM2 config to match where `.env` file is located

**Example:** `infinitetrading-api` was failing with "No INFURA_PROJECT_ID" because:
- PM2 `cwd` was `/home/ubuntu/infinitetrading_api`
- Code loaded `.env` from `./express/.env` (relative path)
- Fixed by setting `cwd: "/home/ubuntu/infinitetrading_api/express"`

#### 2. R Output Buffering in PM2

**Problem:** R script logs not showing in real-time  
**Solution:** Add `flush.console()` after print statements

```r
print("Processing trade...")
flush.console()  # Forces immediate log output to PM2
```

#### 3. Auto-Restart Replaces infinite.sh

**Previous:** All R scripts wrapped in `infinite.sh` (while loop with auto-restart)
```bash
#!/bin/bash
script=$1
while true; do
  Rscript "$script"
  sleep 2
done
```

**Now:** PM2 handles auto-restart automatically with better control:
- `autorestart: true` - Restart on crash
- `max_restarts: 100` - Prevent infinite restart loops
- `min_uptime: "30s"` - Must run 30s to count as successful

#### 4. Gradual Migration Strategy

**Recommended Approach:**
1. **Backup:** Create backups of `ecosystem.config.js` and `startup.sh`
2. **Test One Service:** Start tradebot only, monitor for 5-10 minutes
3. **Verify Logs:** Check logs show proper execution
4. **Check Database:** Verify database connections working
5. **Add More Services:** Gradually add monitors, then strategies
6. **Verify Stability:** All services show 0 restarts
7. **Save Config:** `pm2 save` for persistence
8. **Stop Screen Sessions:** Only after PM2 confirmed working
9. **Update startup.sh:** Remove screen launches, keep PM2 start
10. **Document Changes:** Update development guide

#### 5. Log Management

**Log Rotation Configuration:**
```javascript
max_size: "50M",      // Rotate when file reaches 50MB
retain: 10,           // Keep 10 old log files
compress: true        // Compress rotated logs (.gz)
```

**Log Locations:**
- Error logs: `/home/ubuntu/infinitetrading/src/logs/*-error.log`
- Output logs: `/home/ubuntu/infinitetrading/src/logs/*-out.log`
- PM2 metadata: `/home/ubuntu/.pm2/logs/`

#### 6. Memory Management

**Set memory limits to prevent OOM crashes:**
```javascript
max_memory_restart: "1G"  // Auto-restart if memory exceeds 1GB
```

**Memory Allocations by Service Type:**
- API Services: 500MB - 1GB
- Data Collectors: 200MB
- ML Models: 2GB (needs more for model training)
- Trading/Monitoring: 1GB
- Strategies: 1GB

### Troubleshooting PM2 Services

**Service Won't Start:**
1. Check PM2 logs: `pm2 logs [service-name] --lines 50`
2. Verify `cwd` is correct in `ecosystem.config.js`
3. Check `.env` file exists at expected location
4. Test script manually: `cd /home/ubuntu/infinitetrading/src && Rscript api/trading.R`

**Service Keeps Restarting:**
1. Check error logs: `pm2 logs [service-name] --err --lines 100`
2. Look for crash patterns (missing dependencies, config errors)
3. Increase `min_uptime` if startup is slow
4. Check `max_restarts` hasn't been exceeded

**Environment Variables Not Loading:**
1. Verify `.env` file path relative to `cwd`
2. Check file permissions: `ls -la /home/ubuntu/infinitetrading/src/.env`
3. Test manual load: `Rscript -e "dotenv::load_dot_env('.env'); Sys.getenv('db_user')"`

**High Restart Count:**
1. Check memory usage: `pm2 monit`
2. Review error logs for crash cause
3. Adjust `max_memory_restart` if OOM crashes
4. Fix underlying code issues causing crashes

### Screen vs PM2 Comparison

| Feature | Screen Sessions | PM2 Process Manager |
|---------|----------------|---------------------|
| Process Monitoring | Manual (`screen -ls`) | Automatic (`pm2 list`) |
| Auto-Restart | Manual (via infinite.sh wrapper) | Built-in (`autorestart: true`) |
| Log Management | Scattered in screen buffers | Centralized (`pm2 logs`) |
| Resource Monitoring | External tools only | Built-in (`pm2 monit`) |
| Health Tracking | Manual checks | Automatic (restart count, uptime) |
| Log Rotation | Manual setup | Automatic (size-based) |
| Startup Persistence | Manual in startup.sh | `pm2 save` + systemd |
| Process Grouping | By screen name | By PM2 config |
| Remote Management | SSH + screen commands | PM2 CLI + potential web UI |
| Learning Curve | Moderate | Low (better documentation) |

---

## 📚 Additional Resources

- [Express.js Documentation](https://expressjs.com/)
- [TypeScript Handbook](https://www.typescriptlang.org/docs/)
- [PM2 Documentation](https://pm2.keymetrics.io/docs/)
- [Redis Documentation](https://redis.io/docs/)
- [dHEDGE v2 SDK](https://docs.dhedge.org/)

## 🆘 Getting Help

If you encounter issues:

1. Check this troubleshooting guide
2. Review PM2 logs on EC2
3. Verify local environment matches EC2 specs
4. Check Git commit history for recent changes
5. Test with a minimal example endpoint

---

**Last Updated:** February 2026  
**Production Node Version:** v22.18.0  
**Production PM2 Version:** v6.0.14
