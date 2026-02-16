# Local Structure Replication - Complete ✅

## ✅ ENVIRONMENT TESTED AND WORKING (Feb 11, 2026)

### Local Services Status:
- ✅ **Express API** (port 8000) - PID 9531 - Running
- ✅ **Plumber API** (port 8002) - PID 9549 - Running  
- ✅ **Gateway API** (port 8003) - PID 18666 - Running

### Fixed Issues:
- ✅ **Path Issue Fixed**: `plumber/messaging.R` and `plumber/reporting.R` now properly load `.env` from repo root
- ✅ All services start successfully
- ✅ Swagger documentation accessible on all R services

### Test Results:
```bash
Express (8000): Responding (404 expected on root)
Plumber (8002): 200 OK - Docs at http://localhost:8002/__docs__/
Gateway (8003): 200 OK - Docs at http://localhost:8003/__docs__/
```

---

## ✅ What Has Been Done

### 1. Folder Structure Created
```
/Users/richardclare/infinite-trading-api/
├── express/                    ✅ (already existed)
├── plumber/                    ✅ NEW
│   ├── gateway/                ✅ NEW
│   │   └── endpoints/          ✅ NEW
│   └── helpers/                ✅ NEW
├── strategies/                 ✅ NEW
├── tradebot/                   ✅ NEW
└── data-collectors/            ✅ NEW
```

### 2. Files Downloaded from EC2
- ✅ **Plumber API**: `api.R`, `db.R`, `messaging.R` + helpers
- ✅ **Gateway**: `gateway.R` + 45 endpoint files
- ✅ **Strategies**: 17 strategy files (9 active)
- ✅ **Tradebot**: Core trading logic files
- ✅ **Data Collectors**: Python scripts for data collection

### 3. Scripts Created
- ✅ `start-local.sh` - Starts all 3 services locally
- ✅ `express/scripts/test-r-services.sh` - Tests Gateway & Plumber
- ✅ `express/scripts/migrate-to-pm2.sh` - EC2 migration script
- ✅ `express/scripts/backup-ec2.sh` - EC2 backup script

### 4. Documentation Created
- ✅ **MIGRATION_PLAN.md** - 8-phase safe migration plan
- ✅ **README.md** - Updated with new monorepo structure
- ✅ **.gitignore** - Updated for R files, logs, sensitive data

### 5. PM2 Configuration
- ✅ **ecosystem.config.js** - Updated with all 3 services:
  - infinitetrading-api (Express, port 8000)
  - api-gateway (R Gateway, port 8003)
  - plumber-api (R Plumber, port 8002)

---

## 🚧 What Needs to Be Done

### BEFORE Migrating EC2:

#### 1. Test Locally (CRITICAL - DO THIS FIRST!)

**Note**: The R files may need path adjustments to work locally. Check these files:

**plumber/api.R**:
```r
# Line ~7: Update working directory
wd = "~/infinitetrading_api/"  # Instead of ~/infinitetrading/src/

# Line ~12: Update source paths
sources(c("tradebot/tradebot.R",
          "plumber/helpers/graphQL.R",
          "plumber/helpers/apiHelpers.R",
          "plumber/messaging.R",
          "plumber/db.R",
          "plumber/encryption.R"))
```

**plumber/gateway/gateway.R**:
```r
# Line ~23: Update working directory
wd = "~/infinitetrading_api/"

# Line ~26: Update source paths
source(paste0(wd,"plumber/helpers/apiHelpers.R"))
source(paste0(wd,"plumber/messaging.R"))
source(paste0(wd,"plumber/reporting.R"))
source(paste0(wd,"tradebot/defi.R"))
source(paste0(wd,"plumber/helpers/endpoints.R"))

# Line ~32: Update endpoint path
path = paste0(wd,"plumber/gateway/endpoints/")
```

**Test Steps**:
```bash
cd /Users/richardclare/infinite-trading-api

# 1. Test R services first
./express/scripts/test-r-services.sh

# 2. If tests pass, start all services
./start-local.sh

# 3. Verify all 3 services respond:
curl http://localhost:8000/
curl http://localhost:8002/__docs__/
curl http://localhost:8003/__docs__/

# 4. Test an endpoint through Gateway
curl -X POST http://localhost:8003/api/test

# 5. Check logs for errors
tail -f express/logs/express.log
tail -f plumber/logs/plumber.log
tail -f plumber/logs/gateway.log

# 6. Stop services (use PIDs from start-local.sh output)
kill <EXPRESS_PID> <PLUMBER_PID> <GATEWAY_PID>
```

#### 2. Fix Path Issues
If local testing reveals path errors, update:
- `plumber/api.R` - source() paths
- `plumber/gateway/gateway.R` - source() paths
- `tradebot/*.R` - source() paths (if any)
- `strategies/*.R` - source() paths (if any)

#### 3. Commit Local Changes
```bash
cd /Users/richardclare/infinite-trading-api

git add .
git commit -m "feat: replicate EC2 structure locally

- Added plumber/ directory with API and Gateway
- Added strategies/ directory with 9 trading bots
- Added tradebot/ directory with core logic
- Added data-collectors/ directory with 5 collectors
- Created start-local.sh for local testing
- Created MIGRATION_PLAN.md with safe EC2 migration steps
- Updated README.md with monorepo structure
- Updated .gitignore for R services"

git push origin main
```

---

### AFTER Local Testing Passes:

#### 4. Execute EC2 Migration (Follow MIGRATION_PLAN.md)

**⚠️ CRITICAL**: Only proceed if local testing is 100% successful!

**Phase-by-Phase Execution**:

1. **Phase 1: Preparation** (No downtime)
   - Step 1.1: Backup current EC2 state
   - Step 1.2: Verify local testing passed

2. **Phase 2: Copy Files** (No downtime)
   - Step 2.1: Copy R files to Git repo on EC2
   - Step 2.2: Update file paths in copied files

3. **Phase 3: Test New Structure** (No downtime)
   - Step 3.1: Test Plumber on port 9002
   - Step 3.2: Test Gateway on port 9003

4. **Phase 4: Switch Services** (30 seconds downtime)
   - Step 4.1: Update ecosystem.config.js
   - Step 4.2: Run migrate-to-pm2.sh

5. **Phase 5: Update Remaining Services** (No Express downtime)
   - Step 5.1: Update 9 strategy bots one by one
   - Step 5.2: Update 5 data collectors one by one

6. **Phase 6: Update Startup Script** (No downtime)
   - Step 6.1: Update ~/startup.sh with new paths

7. **Phase 7: Commit to Git** (No downtime)
   - Step 7.1: Add new files and push to GitHub

8. **Phase 8: Cleanup** (After 1 week of stable operation)
   - Step 8.1: Rename old ~/infinitetrading directory

---

## 📊 Current Status

| Task | Status | Notes |
|------|--------|-------|
| Local folder structure | ✅ Complete | All directories created |
| Files downloaded from EC2 | ✅ Complete | ~200 files downloaded |
| Scripts created | ✅ Complete | 4 scripts ready |
| Documentation | ✅ Complete | Migration plan + README |
| PM2 configuration | ✅ Complete | ecosystem.config.js updated |
| **Local testing** | ⏳ **PENDING** | **DO THIS NEXT** |
| Path adjustments | ⏳ Pending | After local testing |
| Git commit | ⏳ Pending | After local testing |
| EC2 migration | ⏳ Pending | After git commit |

---

## 🔍 Potential Issues to Watch

### 1. Path Differences
- EC2 uses `~/infinitetrading/src/`
- Local/New structure uses `~/infinitetrading_api/`
- All `source()` and `paste0(wd, ...)` calls need updating

### 2. Database Connections
- Local may not have access to EC2 MySQL
- Option A: Use SSH tunnel to EC2 MySQL
- Option B: Run MySQL locally with test data
- Update `plumber/db.R` if needed

### 3. Environment Variables
- Check for `.env` files in:
  - `plumber/.env`
  - `plumber/gateway/.env`
  - `express/.env`
- These are gitignored, so they weren't downloaded

### 4. R Package Dependencies
Make sure these R packages are installed locally:
```r
install.packages(c(
  "plumber",
  "httr",
  "jsonlite",
  "DBI",
  "RMySQL",
  "lubridate",
  "data.table",
  "future",
  "promises"
))
```

### 5. Port Conflicts
- Ensure ports 8000, 8002, 8003 are free locally
- Run `lsof -i :8000` etc. to check

---

## 📝 Next Steps (In Order)

1. ✅ **Review this document** - Understand what's been done
2. ⏳ **Fix R file paths** - Update `wd` variables and `source()` calls
3. ⏳ **Install R packages** - Ensure all dependencies installed
4. ⏳ **Create .env files** - Add necessary environment variables
5. ⏳ **Test locally** - Run `./start-local.sh` and verify all services
6. ⏳ **Fix any errors** - Debug until all 3 services run perfectly
7. ⏳ **Commit to Git** - Push working code to GitHub
8. ⏳ **Execute EC2 migration** - Follow MIGRATION_PLAN.md phases

---

## 🆘 Rollback Instructions

### If Local Testing Fails:
No problem! Just delete the new directories:
```bash
cd /Users/richardclare/infinite-trading-api
rm -rf plumber/ strategies/ tradebot/ data-collectors/
git checkout .gitignore README.md
```

### If EC2 Migration Fails:
See **MIGRATION_PLAN.md → Emergency Rollback** section

---

## 💡 Key Reminders

1. **NEVER** skip local testing before EC2 deployment
2. **ALWAYS** test R services with `./express/scripts/test-r-services.sh` first
3. **ALWAYS** create backups before migrating EC2
4. **NEVER** delete old EC2 files until new structure runs for 1 week
5. **ALWAYS** have rollback plan ready at each phase

---

## 📞 Getting Help

If you encounter issues:

1. Check logs:
   - Local: `tail -f plumber/logs/*.log`
   - EC2: `pm2 logs` or `screen -r <session>`

2. Review documentation:
   - MIGRATION_PLAN.md - Migration steps
   - SYSTEM_ARCHITECTURE.md - System overview
   - express/DEPLOYMENT_GUIDE.md - PM2 commands

3. Test in isolation:
   - Test Express alone: `npm run dev`
   - Test Plumber alone: `Rscript plumber/api.R`
   - Test Gateway alone: `Rscript plumber/gateway/gateway.R`
