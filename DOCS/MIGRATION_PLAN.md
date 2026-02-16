# EC2 Production Migration Plan

## ⚠️ CRITICAL: This is a PRODUCTION environment - proceed with extreme caution!

## Current EC2 Structure (AS-IS)

```
/home/ubuntu/
├── infinitetrading/          # Main R codebase (NOT in Git repo)
│   └── src/
│       ├── api/
│       │   ├── api.R          # Plumber API (port 8002)
│       │   ├── gateway/
│       │   │   └── gateway.R   # Gateway (port 8003)
│       │   ├── helpers/
│       │   ├── db.R
│       │   ├── messaging.R
│       │   └── [other files]
│       ├── strategies/         # 9 trading bots
│       ├── tradebot/          # Core trading logic
│       └── db/                # 5 data collectors
└── infinitetrading_api/      # Git repo (Express only)
    └── express/              # Express API (port 8000)
```

## Target Structure (TO-BE)

```
/home/ubuntu/infinitetrading_api/  # Single Git repo
├── express/                    # Express API (port 8000)
│   ├── src/
│   ├── build/
│   ├── logs/
│   └── ecosystem.config.js     # PM2 config for all 3 services
├── plumber/                    # Plumber API (port 8002)
│   ├── api.R
│   ├── helpers/
│   ├── db.R
│   ├── messaging.R
│   ├── logs/
│   └── gateway/                # Gateway (port 8003)
│       ├── gateway.R
│       ├── endpoints/
│       └── logs/
├── strategies/                 # 9 trading bots
│   ├── eth_ema_11_33_crossover.R
│   ├── aero_ema_11_33_crossover.R
│   ├── Velo1DBot.R
│   ├── superTrend.R
│   ├── cbBTC_probability_model.R
│   ├── OP_probability_model.R
│   ├── crossOvers.R
│   ├── infinite.sh
│   └── logs/
├── tradebot/                   # Core trading logic
│   ├── tradebot.R
│   ├── defi.R
│   ├── pools.R
│   └── logs/
├── data-collectors/            # 5 data collectors
│   ├── candles.py
│   ├── candles.sh
│   ├── messages.py
│   ├── messages.sh
│   └── logs/
└── README.md
```

## Benefits

1. **Single Git Repository**: All code versioned together
2. **Unified Deployment**: Deploy everything from one place
3. **PM2 Management**: All Node.js and R services managed by PM2
4. **Better Organization**: Clear separation of concerns
5. **Easier Collaboration**: One repo to clone/fork
6. **Consistent Logs**: All logs in predictable locations

---

## Migration Steps (SAFE ROLLBACK AT EACH STEP)

### Phase 1: Preparation (NO DOWNTIME)

#### Step 1.1: Backup Current State
```bash
# SSH to EC2
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# Create backup directory
mkdir -p ~/backups/$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=~/backups/$(date +%Y%m%d_%H%M%S)

# Backup infinitetrading directory
tar -czf $BACKUP_DIR/infinitetrading_backup.tar.gz ~/infinitetrading/

# Backup current git repo
tar -czf $BACKUP_DIR/infinitetrading_api_backup.tar.gz ~/infinitetrading_api/

# Backup screen sessions list
screen -ls > $BACKUP_DIR/screen_sessions.txt

# Backup startup script
cp ~/startup.sh $BACKUP_DIR/startup.sh.backup

echo "✅ Backup saved to: $BACKUP_DIR"
ls -lh $BACKUP_DIR
```

**Rollback**: Backups exist, no changes made yet

---

#### Step 1.2: Test Locally FIRST
```bash
# On your MacBook
cd /Users/richardclare/infinite-trading-api

# Run the test script
./start-local.sh

# Verify all 3 services work:
# - http://localhost:8000  (Express)
# - http://localhost:8002  (Plumber)
# - http://localhost:8003  (Gateway)

# Stop local services
# (Use the kill command from start-local.sh output)
```

**DO NOT PROCEED** until local testing is 100% successful!

---

### Phase 2: Copy Files to Git Repo (NO DOWNTIME)

#### Step 2.1: Copy R Files to Git Repo
```bash
# SSH to EC2
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# Navigate to git repo
cd ~/infinitetrading_api/

# Create new directories
mkdir -p plumber/gateway/endpoints
mkdir -p plumber/helpers
mkdir -p strategies
mkdir -p tradebot
mkdir -p data-collectors

# Copy Plumber API files
cp ~/infinitetrading/src/api/api.R plumber/
cp ~/infinitetrading/src/api/db.R plumber/
cp ~/infinitetrading/src/api/messaging.R plumber/
cp ~/infinitetrading/src/api/encryption.R plumber/
cp ~/infinitetrading/src/api/getGasBalances.R plumber/
cp ~/infinitetrading/src/api/executeTrades.R plumber/
cp ~/infinitetrading/src/api/gasMonitor.R plumber/
cp ~/infinitetrading/src/api/trading.R plumber/
cp ~/infinitetrading/src/api/yields.R plumber/

# Copy helpers
cp -r ~/infinitetrading/src/api/helpers/* plumber/helpers/

# Copy Gateway files
cp ~/infinitetrading/src/api/gateway/gateway.R plumber/gateway/
cp -r ~/infinitetrading/src/api/gateway/endpoints/* plumber/gateway/endpoints/

# Copy strategies
cp ~/infinitetrading/src/strategies/*.R strategies/
cp ~/infinitetrading/src/strategies/infinite.sh strategies/

# Copy tradebot
cp ~/infinitetrading/src/tradebot/*.R tradebot/
cp ~/infinitetrading/src/tradebot/infinite.sh tradebot/

# Copy data collectors
cp ~/infinitetrading/src/db/*.py data-collectors/
cp ~/infinitetrading/src/db/*.sh data-collectors/
cp ~/infinitetrading/src/db/*.R data-collectors/

# Create log directories
mkdir -p plumber/logs
mkdir -p strategies/logs
mkdir -p tradebot/logs
mkdir -p data-collectors/logs

echo "✅ Files copied to Git repo"
```

**Rollback**: Just delete the new directories, no services affected

---

#### Step 2.2: Update File Paths in Copied Files
```bash
# Still on EC2
cd ~/infinitetrading_api/

# Update api.R to use new paths
sed -i 's|wd = "~/infinitetrading/src/"|wd = "~/infinitetrading_api/"|g' plumber/api.R
sed -i 's|/api/|/plumber/|g' plumber/api.R

# Update gateway.R to use new paths
sed -i 's|wd = "~/infinitetrading/src/"|wd = "~/infinitetrading_api/"|g' plumber/gateway/gateway.R
sed -i 's|/api/|/plumber/|g' plumber/gateway/gateway.R

# Update strategies to use new paths (if they reference src/)
find strategies/ -name "*.R" -type f -exec sed -i 's|~/infinitetrading/src/|~/infinitetrading_api/|g' {} +

echo "✅ File paths updated"
```

**Rollback**: Just delete the new directories, no services affected

---

### Phase 3: Test New Structure (NO DOWNTIME)

#### Step 3.1: Test Plumber API with New Paths (on different port)
```bash
# Still on EC2
cd ~/infinitetrading_api/plumber/

# Start on test port 9002 (different from production 8002)
PORT=9002 Rscript api.R > logs/test.log 2>&1 &
TEST_PLUMBER_PID=$!

sleep 5

# Test if it works
curl -s http://localhost:9002/__docs__/ && echo "✅ Plumber test successful" || echo "❌ Plumber test failed"

# Check logs
tail -20 logs/test.log

# Stop test instance
kill $TEST_PLUMBER_PID
```

**Rollback**: Just kill the test process, production still running

---

#### Step 3.2: Test Gateway with New Paths (on different port)
```bash
# Still on EC2
cd ~/infinitetrading_api/plumber/gateway/

# Start on test port 9003 (different from production 8003)
PORT=9003 Rscript gateway.R > ../logs/gateway-test.log 2>&1 &
TEST_GATEWAY_PID=$!

sleep 5

# Test if it works
curl -s http://localhost:9003/__docs__/ && echo "✅ Gateway test successful" || echo "❌ Gateway test failed"

# Check logs
tail -20 ../logs/gateway-test.log

# Stop test instance
kill $TEST_GATEWAY_PID
```

**Rollback**: Just kill the test process, production still running

---

### Phase 4: Switch to New Structure (MINIMAL DOWNTIME)

#### Step 4.1: Update ecosystem.config.js
```bash
# Still on EC2
cd ~/infinitetrading_api/express/

# Backup current config
cp ecosystem.config.js ecosystem.config.js.backup

# ecosystem.config.js should already have the PM2 config for all 3 services
# from your earlier update. Verify it:
cat ecosystem.config.js
```

**Rollback**: `cp ecosystem.config.js.backup ecosystem.config.js`

---

#### Step 4.2: Stop Screen Sessions and Start PM2 (30 SECONDS DOWNTIME)
```bash
# Still on EC2

# CRITICAL: Run migration script
cd ~/infinitetrading_api/express/
./scripts/migrate-to-pm2.sh

# This script will:
# 1. Stop Gateway and Plumber screen sessions
# 2. Verify ports are free
# 3. Start all services with PM2
# 4. Test all services
# 5. Save PM2 config

# Check status
pm2 status
pm2 logs --lines 50
```

**Rollback if problems**:
```bash
# Stop PM2 services
pm2 stop all

# Restart old screen sessions
screen -dmS plumber -h 1000 bash -c 'cd ~/infinitetrading/src/api && ./infinite.sh api.R'
screen -dmS gateway -h 1000 bash -c 'cd ~/infinitetrading/src/api/gateway && ./infinite.sh gateway.R'

# Verify old sessions are running
screen -ls
curl http://localhost:8002/__docs__/
curl http://localhost:8003/__docs__/
```

---

### Phase 5: Update Remaining Services (NO EXPRESS/GATEWAY/PLUMBER DOWNTIME)

#### Step 5.1: Update Strategy Bots One by One
```bash
# Still on EC2

# For each strategy, update screen session one at a time:
# Example: ethEmaCrossover

# Stop old session
screen -S ethEmaCrossover -X quit

# Start from new location
screen -dmS ethEmaCrossover -h 1000 bash -c 'cd ~/infinitetrading_api/strategies && ./infinite.sh eth_ema_11_33_crossover.R'

# Verify it's running
screen -ls | grep ethEmaCrossover
```

Repeat for all 9 strategies:
- ethEmaCrossover
- aeroEmaCrossover
- Velo1DBot
- superTrend
- cbBTC_probability_model
- OP_probability_model
- crossOvers
- tradeBot
- gasMonitor

**Rollback for each**: Stop new session, restart old session from ~/infinitetrading/src/

---

#### Step 5.2: Update Data Collectors One by One
```bash
# Still on EC2

# For each data collector:
# Example: coinbase

# Stop old session
screen -S coinbase -X quit

# Start from new location
screen -dmS coinbase -h 1000 bash -c 'cd ~/infinitetrading_api/data-collectors && ./candles.sh'

# Verify it's running
screen -ls | grep coinbase
```

Repeat for all 5 data collectors:
- coinbase
- messages
- models
- yields
- pools
- prices

**Rollback for each**: Stop new session, restart old session from ~/infinitetrading/src/

---

### Phase 6: Update Startup Script (NO DOWNTIME)

#### Step 6.1: Update ~/startup.sh
```bash
# Still on EC2

# Backup current startup script
cp ~/startup.sh ~/startup.sh.backup

# Edit startup.sh to use new paths
vim ~/startup.sh
```

Update these lines:
```bash
# OLD:
screen -dmS plumber -h 1000 bash -c 'cd ~/infinitetrading/src/api && ./infinite.sh api.R'
screen -dmS gateway -h 1000 bash -c 'cd ~/infinitetrading/src/api/gateway && ./infinite.sh gateway.R'

# NEW: (commented out - PM2 handles these now)
# screen -dmS plumber -h 1000 bash -c 'cd ~/infinitetrading_api/plumber && Rscript api.R'
# screen -dmS gateway -h 1000 bash -c 'cd ~/infinitetrading_api/plumber/gateway && Rscript gateway.R'
# PM2 manages infinitetrading-api, api-gateway, plumber-api automatically on boot

# Update all strategy paths:
# OLD:
screen -dmS ethEmaCrossover -h 1000 bash -c 'cd ~/infinitetrading/src/strategies/ && ./infinite.sh eth_ema_11_33_crossover.R'

# NEW:
screen -dmS ethEmaCrossover -h 1000 bash -c 'cd ~/infinitetrading_api/strategies/ && ./infinite.sh eth_ema_11_33_crossover.R'

# (Repeat for all strategies and data collectors)
```

**Rollback**: `cp ~/startup.sh.backup ~/startup.sh`

---

### Phase 7: Commit to Git (NO DOWNTIME)

#### Step 7.1: Add New Files to Git
```bash
# Still on EC2
cd ~/infinitetrading_api/

# Add new directories
git add plumber/
git add strategies/
git add tradebot/
git add data-collectors/
git add start-local.sh
git add MIGRATION_PLAN.md

# Update .gitignore to exclude logs and sensitive files
echo "
# R service logs
plumber/logs/
strategies/logs/
tradebot/logs/
data-collectors/logs/

# Sensitive files
plumber/.env
plumber/gateway/.env
*.sqlite
*.swp
.Rhistory
.RData
" >> .gitignore

# Commit
git add .gitignore
git commit -m "feat: migrate R services into monorepo

- Added plumber/ directory with API and Gateway
- Added strategies/ directory with 9 trading bots
- Added tradebot/ directory with core logic
- Added data-collectors/ directory with 5 collectors
- Updated PM2 ecosystem.config.js to manage all services
- Added start-local.sh for local testing
- Updated .gitignore for R services"

# Push to GitHub
git push origin main
```

---

### Phase 8: Cleanup Old Files (AFTER 1 WEEK OF STABLE OPERATION)

**⚠️ ONLY do this after verifying everything works for at least 1 week!**

```bash
# SSH to EC2
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# Verify all services are running from new location
pm2 status
screen -ls

# Create final backup
mkdir -p ~/backups/final_before_delete
tar -czf ~/backups/final_before_delete/infinitetrading_final.tar.gz ~/infinitetrading/

# Rename old directory (don't delete yet!)
mv ~/infinitetrading ~/infinitetrading_OLD_$(date +%Y%m%d)

# Test everything still works
curl http://localhost:8000/
curl http://localhost:8002/__docs__/
curl http://localhost:8003/__docs__/

# If everything works for another week, then:
# rm -rf ~/infinitetrading_OLD_*
```

---

## Emergency Rollback (If Something Goes Wrong)

### Full Rollback to Original State
```bash
# SSH to EC2
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# Stop all PM2 services
pm2 stop all
pm2 delete all

# Restore original startup script
cp ~/startup.sh.backup ~/startup.sh

# Run original startup script
~/startup.sh

# Verify services are running
screen -ls
curl http://localhost:8000/
curl http://localhost:8002/__docs__/
curl http://localhost:8003/__docs__/
```

---

## Testing Checklist

After each phase, verify:

- [ ] Express API responds on port 8000
- [ ] Plumber API responds on port 8002
- [ ] Gateway responds on port 8003
- [ ] All 9 strategies are running (check screen -ls)
- [ ] All 5 data collectors are running (check screen -ls)
- [ ] Check PM2 status: `pm2 status`
- [ ] Check logs for errors: `pm2 logs --lines 100`
- [ ] Test a trade through Gateway
- [ ] Test an admin endpoint
- [ ] Monitor for 30 minutes to ensure stability

---

## Success Criteria

Migration is successful when:

1. ✅ All services running from new location
2. ✅ PM2 managing Express, Gateway, Plumber
3. ✅ All strategies running from new location
4. ✅ All data collectors running from new location
5. ✅ Git repo contains all code
6. ✅ Local testing works
7. ✅ Startup script updated
8. ✅ No errors in logs for 24 hours
9. ✅ Able to deploy updates via rsync + pm2 restart

---

## Notes

- **Downtime**: Total expected downtime < 1 minute (only during PM2 switch)
- **Risk Level**: Medium (production environment, but good rollback plan)
- **Duration**: 2-3 hours (including testing between phases)
- **Prerequisites**: Local testing 100% successful
- **Backup Strategy**: Multiple backups at each phase
- **Rollback**: Possible at every step

---

## Post-Migration Benefits

1. **Single Git Clone**: `git clone` gets everything
2. **Unified Deployment**: One command deploys all updates
3. **Better Process Management**: PM2 for all Node.js/R services
4. **Consolidated Logs**: All logs in predictable locations
5. **Easier Development**: Test locally before deploying
6. **Version Control**: All code changes tracked in Git
7. **Team Collaboration**: Everyone works from same repo
