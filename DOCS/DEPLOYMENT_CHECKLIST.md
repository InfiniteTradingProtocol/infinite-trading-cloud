# EC2 Deployment Checklist
**Date Prepared:** February 11, 2026  
**Status:** 🔴 DO NOT DEPLOY - PREREQUISITES REQUIRED

---

## ⚠️ CRITICAL: Complete These Steps BEFORE Deployment

### 1. Download Missing Files from EC2

Run this script from your local machine:

```bash
cd /Users/richardclare/infinite-trading-api
./express/scripts/download-missing-files.sh
```

**Expected Output:**
- `/tmp/ec2_downloads/main.R` - Strategies dependency
- `/tmp/ec2_downloads/slack.R` - Optional messaging
- `/tmp/ec2_downloads/file_list.txt` - Complete file inventory

**Manual Actions Required:**
1. Review `main.R` content
2. Update all hardcoded paths in `main.R`:
   - Change `~/infinitetrading/src/` to use `wd` variable
   - Change `.env` path to `paste0(wd, ".env")`
3. Copy to `strategies/strategies/main.R`
4. Test locally

---

### 2. Fix Hardcoded Paths (CRITICAL)

#### Files Already Fixed ✅:
- `express/src/walletv2.ts` - Now uses relative path
- `express/ecosystem.config.js` - Now uses repo root paths
- `plumber/messaging.R` - Now uses `wd` variable
- `plumber/reporting.R` - Now uses `wd` variable

#### Files Still Need Fixing ❌:

**A. All Strategy Files (11 files):**

Files to update:
- `strategies/strategies/superTrend.R`
- `strategies/strategies/dht_ema_rsi.R`
- `strategies/strategies/crossOvers.R`
- `strategies/strategies/cbBTC_probability_model.R`
- `strategies/strategies/cbBTC_probability_model_backtest.R`
- `strategies/strategies/velo_ema_rsi.R`
- `strategies/strategies/velo_rsi_14.R`
- `strategies/strategies/Velo1DBot.R`
- `strategies/strategies/aero_ema_11_33_crossover.R`
- `strategies/strategies/ETHUSD1D_EMA_RSI.R`
- `strategies/strategies/OP_probability_model.R`

**Find:** `source("~/infinitetrading/src/strategies/main.R")`  
**Replace with:**
```r
# Determine repo root
if (exists("ofile") && !is.null(ofile <- sys.frame(1)$ofile)) {
  script_dir = dirname(normalizePath(ofile))
} else {
  script_dir = normalizePath(".")
}
wd = paste0(dirname(dirname(script_dir)), "/")
source(paste0(wd, "strategies/strategies/main.R"))
```

**B. Tradebot Files (8 files):**

Files to update:
- `tradebot/tradebot/approvals.R`
- `tradebot/tradebot/forever.R`
- `tradebot/tradebot/defi_thread.R`
- `tradebot/tradebot/tradebot_with_stoploss.R`
- `tradebot/tradebot/tradebot_old.R`
- `tradebot/tradebot/pools.R`
- `tradebot/tradebot/defund_pools.R`
- `tradebot/tradebot/ccxt_tradebot.R`
- `tradebot/tradebot/index.R`

**Find:** `wd = "~/infinitetrading/src/"`  
**Replace with:**
```r
# Determine repo root dynamically
if (exists("ofile") && !is.null(ofile <- sys.frame(1)$ofile)) {
  script_dir = dirname(normalizePath(ofile))
} else {
  script_dir = normalizePath(".")
}
# Navigate up to repo root from tradebot/tradebot/
wd = paste0(dirname(dirname(script_dir)), "/")
```

**C. main.R (After downloading from EC2):**

In `strategies/strategies/main.R`:

**Find:** `load_dot_env("~/infinitetrading/src/.env")`  
**Replace with:**
```r
# Use wd if set (from parent), otherwise find repo root
if (!exists("wd")) {
  if (exists("ofile") && !is.null(ofile <- sys.frame(1)$ofile)) {
    script_dir = dirname(normalizePath(ofile))
  } else {
    script_dir = normalizePath(".")
  }
  wd = paste0(dirname(dirname(script_dir)), "/")
}
env_path = paste0(wd, ".env")
if (file.exists(env_path)) {
  load_dot_env(env_path)
} else {
  warning(paste0("Warning: .env not found at ", env_path))
}
```

---

### 3. Test Locally (MANDATORY)

#### A. Rebuild Express:
```bash
cd /Users/richardclare/infinite-trading-api/express
npm run build
```

#### B. Restart All Services:
```bash
# Stop current services
lsof -i :8000,8002,8003 -sTCP:LISTEN -t | xargs kill 2>/dev/null

# Start with start-local.sh
cd /Users/richardclare/infinite-trading-api
./start-local.sh
```

#### C. Test Endpoints:
```bash
# Express
curl http://localhost:8000/

# Plumber - test a few endpoints
curl 'http://localhost:8002/getPoolComposition?pool=0x6fd1ddde8e0e2f45fb285ae7aebe2cb1ae1f6945&network=optimism'

# Gateway - test a few endpoints
curl 'http://localhost:8003/api/getContract?asset=WETH&network=base'
curl 'http://localhost:8003/api/getGasBalance?wallet=0x...'
```

#### D. Test Encryption (Critical for walletv2):
```bash
cd /Users/richardclare/infinite-trading-api/express
node -e "
const { walletv2 } = require('./build/src/walletv2');
walletv2('optimism', 'your_test_api_key', null, null)
  .then(() => console.log('✅ Encryption working'))
  .catch(err => console.error('❌ Encryption failed:', err));
"
```

**Expected:** Should resolve encryption.R path correctly

---

### 4. Commit Changes to Git

```bash
cd /Users/richardclare/infinite-trading-api

git add .
git commit -m "Fix: Update all hardcoded paths for new monorepo structure

- Fixed ecosystem.config.js paths
- Fixed walletv2.ts encryption path
- Fixed all strategy file paths
- Fixed all tradebot file paths
- Added main.R with updated paths
- Fixed .env loading in all files"

git push origin main
```

---

### 5. Prepare EC2

#### A. Test Current EC2 State:
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# Test all services are responding
curl http://localhost:8000/
curl http://localhost:8002/__docs__/
curl http://localhost:8003/__docs__/

# Document running processes
screen -ls
ps aux | grep -E "(node|Rscript)" | grep -v grep

# Exit
exit
```

#### B. Upload Migration Scripts:
```bash
# From local machine
cd /Users/richardclare/infinite-trading-api

# The scripts will be in Git, so just pull on EC2
```

---

## Deployment Day Checklist

### Pre-Deployment (10 minutes before):

- [ ] All local tests passing
- [ ] All code pushed to Git
- [ ] EC2 current services all responding
- [ ] Backup script ready
- [ ] Rollback script tested
- [ ] Team notified of deployment window
- [ ] Monitoring dashboard open

### Deployment Steps:

#### Step 1: SSH to EC2
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
```

#### Step 2: Run Migration Script
```bash
cd ~/infinitetrading_api/express
./scripts/migrate-ec2.sh
```

**Expected Duration:** 5-10 minutes  
**Downtime:** ~30 seconds (during service restart)

#### Step 3: Monitor
```bash
# Watch PM2 status
pm2 monit

# Watch logs in real-time
pm2 logs

# Check all services
curl http://localhost:8000/
curl http://localhost:8002/__docs__/
curl http://localhost:8003/__docs__/
```

### Post-Deployment Validation (30 minutes):

- [ ] All services show "online" in PM2
- [ ] Express responds to health checks
- [ ] Plumber API docs accessible
- [ ] Gateway API docs accessible
- [ ] Test critical endpoints:
  - [ ] `/api/vaultTrade` (Gateway)
  - [ ] `/getPoolComposition` (Plumber)
  - [ ] Express trade endpoints
- [ ] Check PM2 logs for errors
- [ ] Monitor memory usage
- [ ] Monitor CPU usage

### If Problems Occur:

**Option A: Quick Fix**
```bash
pm2 restart all
pm2 logs --lines 100
```

**Option B: Rollback**
```bash
cd ~/infinitetrading_api/express
./scripts/rollback-migration.sh
```

---

## Post-Migration Tasks

### After 1 Hour of Stable Operation:

- [ ] Test a real trade (small amount)
- [ ] Verify database connections
- [ ] Test strategy execution
- [ ] Verify message sending (Telegram/Discord)
- [ ] Check all cron jobs still work

### After 24 Hours:

- [ ] Review all logs for anomalies
- [ ] Check error rates
- [ ] Verify no memory leaks
- [ ] Performance comparison vs. screen sessions

### After 1 Week:

- [ ] Remove old `~/infinitetrading/` directory
- [ ] Update any external scripts/crons with new paths
- [ ] Document any issues encountered
- [ ] Update team on new structure

---

## Rollback Plan

If migration fails or causes issues:

### Immediate Rollback (< 1 hour):
```bash
cd ~/infinitetrading_api/express
./scripts/rollback-migration.sh
```

### Delayed Rollback (> 1 hour):
```bash
# Stop PM2
pm2 stop all
pm2 delete all

# Restore from backup
BACKUP_DIR=~/backups/migration_YYYYMMDD_HHMMSS
cd ~
tar -xzf $BACKUP_DIR/infinitetrading_backup.tar.gz
tar -xzf $BACKUP_DIR/infinitetrading_api_backup.tar.gz

# Restart with screen
screen -dmS api -h 1000 bash -c 'cd ~/infinitetrading_api/express && npm run start:watch'
screen -dmS gateway -h 1000 Rscript ~/infinitetrading/src/api/gateway/gateway.R
screen -dmS plumber -h 1000 Rscript ~/infinitetrading/src/api/api.R
```

---

## Emergency Contacts

- **Developer:** [Your contact]
- **System Admin:** [Contact]
- **Backup Person:** [Contact]

---

## Risk Level: 🔴 MEDIUM-HIGH

**Why:**
- Multiple file path changes
- Production service restart required
- Database connections involved
- ~30 seconds of downtime

**Mitigation:**
- Comprehensive testing locally
- Automated rollback script ready
- Backup of entire current state
- Gradual validation process

---

## Final Pre-Flight Check

Before running `migrate-ec2.sh`, verify:

- [ ] ✅ All local tests pass
- [ ] ✅ `main.R` downloaded and fixed
- [ ] ✅ All 19+ hardcoded paths fixed
- [ ] ✅ ecosystem.config.js paths correct
- [ ] ✅ walletv2.ts encryption path correct
- [ ] ✅ Git repo up to date
- [ ] ✅ EC2 current services healthy
- [ ] ✅ Rollback script ready
- [ ] ✅ Monitoring ready
- [ ] ✅ Team notified

---

## Deployment Window Recommendation

**Best Time:**
- Low traffic period
- Team available for 2 hours
- Not Friday/Holiday
- Morning hours (easier rollback if needed)

**Duration:**
- Planned: 30 minutes
- Buffer: 2 hours for issues
- Monitoring: 24 hours post-deployment

---

**Last Updated:** February 11, 2026  
**Next Review:** Before deployment execution
