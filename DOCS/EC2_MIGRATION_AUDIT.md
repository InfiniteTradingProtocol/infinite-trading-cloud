# EC2 Migration Audit & Testing Report
**Date:** February 11, 2026  
**Status:** 🔴 CRITICAL ISSUES FOUND - DO NOT DEPLOY YET

---

## Executive Summary

### ✅ Working Locally:
- Express API (port 8000) - Running
- Plumber API (port 8002) - Running (with MySQL warnings)
- Gateway API (port 8003) - Running

### 🔴 Critical Issues Found:

1. **Hardcoded Old EC2 Paths** (21+ files affected)
2. **Missing `main.R` file** (strategies dependency)
3. **ecosystem.config.js points to non-existent files**
4. **MySQL connection issues** (expected locally, but need to verify on EC2)

---

## Detailed Findings

### 1. 🔴 CRITICAL: Hardcoded Path Issues

#### Files with `~/infinitetrading/src/` references:

**Strategies (11 files):**
- `strategies/strategies/superTrend.R` - Line 2
- `strategies/strategies/dht_ema_rsi.R` - Line 28
- `strategies/strategies/crossOvers.R` - Line 2
- `strategies/strategies/cbBTC_probability_model.R` - Line 27
- `strategies/strategies/cbBTC_probability_model_backtest.R` - Line 27
- `strategies/strategies/velo_ema_rsi.R` - Line 2
- `strategies/strategies/velo_rsi_14.R` - Line 28
- `strategies/strategies/Velo1DBot.R` - Line 1
- `strategies/strategies/aero_ema_11_33_crossover.R` - Line 27
- `strategies/strategies/ETHUSD1D_EMA_RSI.R` - Line 1
- `strategies/strategies/OP_probability_model.R` - Line 27

**Issue:** All source `~/infinitetrading/src/strategies/main.R`  
**Fix Required:** Change to relative path or use `wd` variable

**Tradebot (8 files):**
- `tradebot/tradebot/approvals.R` - Line 1: `wd = "~/infinitetrading/src/tradebot/"`
- `tradebot/tradebot/forever.R` - Line 2: `wd = "~/infinitetrading/src/"`
- `tradebot/tradebot/defi_thread.R` - Line 1: `source('~/infinitetrading/src/tradebot/tradebot.R')`
- `tradebot/tradebot/tradebot_with_stoploss.R` - Line 8: `wd = "~/infinitetrading/src/"`
- `tradebot/tradebot/tradebot_old.R` - Line 9: `wd = "~/infinitetrading/src/"`
- `tradebot/tradebot/pools.R` - Line 7: `source('~/infinitetrading/src/tradebot/defi_thread.R')`
- `tradebot/tradebot/defund_pools.R` - Line 1: `wd = "~/infinitetrading/src/"`
- `tradebot/tradebot/ccxt_tradebot.R` - Line 8: `wd = "~/infinitetrading/src/"`
- `tradebot/tradebot/index.R` - Lines 5-6: Multiple source statements

**Express (2 critical files):**
- `express/src/walletv2.ts` - Line 27: 
  ```typescript
  const scriptPath = path.resolve('/home/ubuntu/infinitetrading/src/api/encryption.R');
  ```
  **This will break on EC2!**

**strategies/main.R:**
- Line 7: `load_dot_env("~/infinitetrading/src/.env")`
- Line 12: `db_schema = "infinitetrading"`

---

### 2. 🔴 CRITICAL: Missing File

**File:** `strategies/strategies/main.R`  
**Impact:** All 11 strategy files depend on this  
**Status:** ❌ NOT FOUND in local repo  
**Location on EC2:** `/home/ubuntu/infinitetrading/src/strategies/main.R`

**Action Required:** Download from EC2 and adapt paths

---

### 3. 🔴 CRITICAL: ecosystem.config.js Issues

**Current Configuration:**
```javascript
{
  name: 'api-gateway',
  script: 'Rscript',
  args: '../plumber/api_gateway.R',  // ❌ FILE DOESN'T EXIST
  cwd: '/home/ubuntu/infinitetrading_api/express',
}
```

**Problems:**
- File is `plumber/gateway/gateway.R` NOT `plumber/api_gateway.R`
- CWD assumes EC2 path, won't work locally
- File is `plumber/api.R` NOT `plumber/plumber.R`

**Fixed Configuration Needed:**
```javascript
{
  name: 'api-gateway',
  script: 'Rscript',
  args: ['plumber/gateway/gateway.R'],
  cwd: process.env.NODE_ENV === 'production' 
    ? '/home/ubuntu/infinitetrading_api' 
    : process.cwd() + '/..',
}
```

---

### 4. ⚠️ .env Loading Issues (FIXED)

**Fixed Files:**
- ✅ `plumber/messaging.R` - Now uses `wd` variable
- ✅ `plumber/reporting.R` - Now uses `wd` variable

**Still Need Checking:**
- `strategies/strategies/main.R` - Hardcoded path to `.env`

---

### 5. ✅ Working Correctly

**Files with proper path detection:**
- ✅ `plumber/api.R` - Dynamically finds repo root
- ✅ `plumber/gateway/gateway.R` - Dynamically finds repo root
- ✅ `plumber/db.R` - Multiple fallback paths for `.env`
- ✅ `plumber/encryption.R` - Multiple fallback paths for `.env`
- ✅ `plumber/getGasBalances.R` - Multiple fallback paths for `.env`
- ✅ `tradebot/tradebot/defi.R` - Uses `wd` variable correctly

---

## Testing Results

### Local Environment Tests:

#### Services Status:
```bash
✅ Express (8000)  - PID 9531  - HTTP 404 (no root route - expected)
✅ Plumber (8002)  - PID 9549  - HTTP 200 on /__docs__/
✅ Gateway (8003)  - PID 18666 - HTTP 200 on /__docs__/
```

#### Endpoint Tests:
```bash
❌ Plumber: /getPoolComposition - 404
❌ Gateway: /api/getContract - 404
```

**Analysis:** Services are running but endpoints aren't registered correctly. This suggests:
1. Files may not be sourced properly
2. Path issues preventing endpoint registration
3. Possible errors during startup that were suppressed

#### Log Analysis:

**Plumber Warnings:**
```
Error in getWalletPools: Failed to connect: Can't connect to local server through socket '/tmp/mysql.sock' (2)
```
- Expected locally (no MySQL running)
- Should work on EC2 (MySQL is installed)

**Gateway:**
- Started successfully
- Mounted 30 endpoints
- No critical errors

---

## Files Requiring Changes for EC2 Migration

### Priority 1 - MUST FIX BEFORE DEPLOYMENT:

1. **ecosystem.config.js**
   - Fix R script paths
   - Make CWD dynamic (local vs production)

2. **express/src/walletv2.ts**
   - Change hardcoded `/home/ubuntu/infinitetrading/src/api/encryption.R`
   - Use relative path: `../plumber/encryption.R`

3. **strategies/strategies/main.R**
   - Download from EC2
   - Change `.env` path
   - Change `source()` statements to relative paths

4. **All 11 strategy files**
   - Change `source("~/infinitetrading/src/strategies/main.R")`
   - To: `source(paste0(wd, "strategies/strategies/main.R"))`

### Priority 2 - FIX BEFORE RUNNING STRATEGIES:

5. **All 8 tradebot files**
   - Replace `wd = "~/infinitetrading/src/"` 
   - With dynamic path detection (similar to api.R)

---

## EC2 Migration Path Analysis

### Current EC2 Structure:
```
/home/ubuntu/
├── infinitetrading/          # NOT in git (main R code)
│   └── src/
│       ├── api/             # Plumber + Gateway
│       ├── strategies/      # 9 bots
│       ├── tradebot/        # Core logic
│       ├── db/              # Data collectors
│       └── .env             # Config
│
└── infinitetrading_api/     # Git repo (Express only)
    └── express/
```

### Target EC2 Structure:
```
/home/ubuntu/infinitetrading_api/  # Single git repo
├── express/
├── plumber/
├── strategies/
├── tradebot/
├── data-collectors/
└── .env
```

### Migration Strategy:

**Option 1: Safe Gradual Migration (RECOMMENDED)**
1. Keep `infinitetrading/` as backup
2. Clone new repo structure to `infinitetrading_api_v2/`
3. Test thoroughly
4. Switch DNS/load balancer
5. Remove old structure after 1 week

**Option 2: In-Place Migration (RISKY)**
1. Stop all services
2. Backup everything
3. Move files to new structure
4. Update all paths
5. Restart services
6. Pray 🙏

---

## Pre-Deployment Checklist

### Before touching EC2:

- [ ] Download missing `main.R` from EC2
- [ ] Fix all hardcoded paths in local repo
- [ ] Test all endpoints work locally
- [ ] Fix ecosystem.config.js paths
- [ ] Update walletv2.ts encryption path
- [ ] Test strategies can load main.R
- [ ] Verify .env loads correctly in all contexts
- [ ] Test PM2 config locally (with adjusted paths)
- [ ] Create comprehensive rollback script
- [ ] Document which screen sessions are currently running

### On EC2 (in order):

- [ ] Create timestamped backup
- [ ] Test current services are all responding
- [ ] Document all running screen sessions
- [ ] Download all files not in git
- [ ] Create new repo directory
- [ ] Copy files to new structure
- [ ] Test new structure in parallel (different ports)
- [ ] Verify all endpoints work in new structure
- [ ] Switch PM2 to new structure
- [ ] Monitor for 1 hour
- [ ] Test all critical endpoints
- [ ] Keep old structure for 1 week

---

## Risk Assessment

### High Risk Areas:

1. **Strategies** - 11 files depend on missing `main.R`
2. **Encryption** - Hardcoded path in walletv2.ts
3. **Database** - Connection strings may need updating
4. **Cron Jobs** - May have old paths
5. **Startup Scripts** - May reference old locations

### Mitigation:

- Test everything locally first
- Keep old structure as fallback
- Use symlinks initially
- Gradual cutover with monitoring
- Have rollback script ready

---

## Next Steps

1. ✅ Audit complete
2. 🔄 Download missing `main.R` from EC2
3. 🔄 Fix all hardcoded paths
4. 🔄 Test locally end-to-end
5. ⏸️ Create EC2 backup script
6. ⏸️ Create migration script
7. ⏸️ Schedule migration window
8. ⏸️ Execute migration
9. ⏸️ Monitor and validate

---

## Recommendations

### DO NOT DEPLOY until:

1. All hardcoded paths are fixed
2. `main.R` is obtained and adapted
3. ecosystem.config.js is corrected
4. All endpoints test successfully locally
5. Rollback plan is documented and tested

### Estimated Time to Fix:

- Path fixes: 2-3 hours
- Testing: 2 hours
- EC2 migration: 1 hour
- Validation: 1 hour
- **Total: ~6 hours of careful work**

### Recommendation:

**Use Option 1 (Gradual Migration)** with parallel testing to minimize production impact.
