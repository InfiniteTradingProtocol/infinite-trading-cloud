# 🚀 Complete EC2 Deployment Instructions

**Date**: February 12, 2026  
**Deployment Type**: In-place update with AMI backup  
**Estimated Time**: 30-45 minutes  
**Downtime**: 15-20 minutes

---

## Prerequisites Checklist

- [ ] AWS Console access
- [ ] SSH key: `~/.ssh/macbook.pem`
- [ ] EC2 instance: `ec2-3-135-99-211.us-east-2.compute.amazonaws.com`
- [ ] Local repository up to date: `/Users/richardclare/infinite-trading-api`
- [ ] All local .env files present (✅ Already downloaded from EC2)

---

## Phase 1: Create AMI Snapshot (10 minutes)

### Step 1.1: Navigate to EC2 Console

1. Open AWS Console: https://console.aws.amazon.com/ec2
2. Make sure you're in the correct region: **US East (Ohio) us-east-2**
3. Click **Instances** in the left sidebar

### Step 1.2: Locate Your Instance

1. Find instance with IP: `3.135.99.211`
2. Note the **Instance ID** (something like `i-0123456789abcdef0`)
3. Verify instance state is **Running**

### Step 1.3: Create AMI Snapshot

1. **Select your instance** (click the checkbox)
2. Click **Actions** dropdown (top right)
3. Navigate to: **Image and templates** → **Create image**

4. **Fill in the form:**
   ```
   Image name: prod-backup-2026-02-12
   Image description: Backup before monorepo migration and directory restructure
   No reboot: ☐ (leave UNCHECKED for data consistency)
   ```

5. **Click "Create image"**

6. **Wait for AMI to become available:**
   - Click **AMIs** in left sidebar (under Images)
   - Find your AMI: `prod-backup-2026-02-12`
   - Status will show: `pending` → `available` (5-10 minutes)
   - ⚠️ **DO NOT PROCEED until status is "available"**

### Step 1.4: Verify AMI Creation

```bash
# Optional: Verify via AWS CLI
aws ec2 describe-images --owners self --filters "Name=name,Values=prod-backup-2026-02-12" --region us-east-2
```

---

## Phase 2: Prepare Local Environment (2 minutes)

### Step 2.1: Verify All Files Present

```bash
cd /Users/richardclare/infinite-trading-api

# Check deployment script
ls -lh deploy-to-ec2-clean.sh

# Make executable
chmod +x deploy-to-ec2-clean.sh

# Verify .env files
ls -lh .env express/.env express/src/sugar/.env plumber/.env data-collectors/.env
```

**Expected output:**
```
-rw-r--r--  4394 .env
-rw-r--r--  1085 express/.env
-rw-r--r--  8904 express/src/sugar/.env
-rw-r--r--   310 plumber/.env
-rw-r--r--   665 data-collectors/.env
```

### Step 2.2: Test SSH Connection

```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com "echo 'SSH connection successful'"
```

---

## Phase 3: Run Deployment (15-20 minutes)

### Step 3.1: Execute Deployment Script

```bash
cd /Users/richardclare/infinite-trading-api
./deploy-to-ec2-clean.sh
```

### Step 3.2: Confirm AMI Creation

The script will prompt:
```
⚠️  MANUAL STEP REQUIRED:
   1. Go to AWS Console → EC2 → Instances
   2. Select your instance
   3. Actions → Image and templates → Create image
   4. Name: 'prod-backup-20260212'
   5. Wait for AMI to be 'available' (5-10 min)

Have you created the AMI snapshot? (yes/no):
```

**Type:** `yes` (only if AMI status is "available")

### Step 3.3: Monitor Deployment

The script will:
1. ✅ Stop all running services (PM2, forever, R processes)
2. ✅ Create timestamped backup on EC2
3. ✅ Clone fresh git repository
4. ✅ Sync local files to EC2
5. ✅ Restore all .env files to correct locations
6. ✅ Install Node/R/Python dependencies
7. ✅ Configure PM2
8. ✅ Test services
9. ✅ Start all services

**Watch for these confirmations:**
- `✅ All services stopped`
- `✅ Backup created at: /home/ubuntu/backup_YYYYMMDD_HHMMSS`
- `✅ Git repository cloned`
- `✅ Files synced to EC2`
- `✅ Credentials restored to new monorepo structure`
- `✅ Dependencies installed`
- `✅ Services tested`
- `✅ All services started`

---

## Phase 4: Verify Deployment (5 minutes)

### Step 4.1: Check PM2 Services

```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com "pm2 status"
```

**Expected output:**
```
┌─────┬──────────┬─────────┬─────────┬───────┐
│ id  │ name     │ status  │ restart │ uptime│
├─────┼──────────┼─────────┼─────────┼───────┤
│ 0   │ express  │ online  │ 0       │ 2m    │
└─────┴──────────┴─────────┴─────────┴───────┘
```

### Step 4.2: Check API Health

```bash
# Test Express API
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com "curl -s http://localhost:3001/health"

# Test Plumber Gateway
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com "curl -s http://localhost:8003/health || echo 'Plumber may be starting...'"
```

### Step 4.3: Check Trading Bots

```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com "ps aux | grep -E 'Rscript.*(cbBTC|OP_probability)' | grep -v grep"
```

**Should see processes like:**
```
ubuntu    12345  ... Rscript strategies/cbBTC_probability_model.R
ubuntu    12346  ... Rscript strategies/OP_probability_model.R
```

### Step 4.4: Check Logs

```bash
# PM2 logs (last 50 lines)
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com "pm2 logs --lines 50 --nostream"

# Plumber gateway log
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com "tail -50 /home/ubuntu/infinite-trading-api/plumber/logs/gateway.log"

# Strategy logs
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com "ls -lh /home/ubuntu/infinite-trading-api/strategies/logs/"
```

### Step 4.5: Verify New Directory Structure

```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com << 'EOF'
cd /home/ubuntu/infinite-trading-api
echo "=== Verifying flattened structure ==="
ls -ld strategies tradebot plumber data-collectors express
echo ""
echo "=== No nested directories should exist ==="
! test -d strategies/strategies && echo "✅ strategies/strategies REMOVED" || echo "❌ strategies/strategies STILL EXISTS"
! test -d tradebot/tradebot && echo "✅ tradebot/tradebot REMOVED" || echo "❌ tradebot/tradebot STILL EXISTS"
EOF
```

---

## Phase 5: Monitor for 30 Minutes

### What to Watch

1. **PM2 Status** (every 5 minutes):
   ```bash
   ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com "pm2 status"
   ```
   - All processes should remain **online**
   - Restart count should be **0** (or very low)

2. **Error Logs** (every 10 minutes):
   ```bash
   ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com "pm2 logs --err --lines 20 --nostream"
   ```

3. **Trading Activity** (check Slack/Telegram):
   - Bot messages should appear normally
   - No error messages

4. **Database Activity**:
   ```bash
   ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com "mysql -u richard_clare -p infinitetrading -e 'SELECT COUNT(*) as recent_signals FROM signals WHERE created_at > NOW() - INTERVAL 30 MINUTE;'"
   ```

---

## 🚨 Rollback Procedures (If Something Goes Wrong)

### Option A: Quick Rollback from Backup Directory (5 minutes)

```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com << 'EOF'
# Stop everything
pm2 stop all
forever stopall
pkill -f "Rscript"

# Find latest backup
BACKUP_DIR=$(ls -dt /home/ubuntu/backup_* | head -1)
echo "Rolling back from: $BACKUP_DIR"

# Restore files
rm -rf /home/ubuntu/infinite-trading-api
cp -r $BACKUP_DIR/infinitetrading_api_backup /home/ubuntu/infinitetrading_api
cp -r $BACKUP_DIR/infinitetrading_src_backup /home/ubuntu/infinitetrading/src

# Restore .env files
cp $BACKUP_DIR/env_files/home/ubuntu/.env /home/ubuntu/ 2>/dev/null || true
cp $BACKUP_DIR/env_files/home/ubuntu/infinitetrading/src/.env /home/ubuntu/infinitetrading/src/ 2>/dev/null || true

# Restart
cd /home/ubuntu/infinitetrading_api/express
pm2 start ecosystem.config.js
pm2 save

echo "✅ Rollback complete"
EOF
```

### Option B: Full Rollback from AMI Snapshot (15 minutes)

**Only use if Option A fails**

1. **Go to AWS Console → EC2 → AMIs**
2. **Find:** `prod-backup-2026-02-12`
3. **Right-click → Launch instance from AMI**
4. **Configure:**
   - Instance type: Same as current (check old instance details)
   - Key pair: `macbook`
   - Security group: Same as current
   - Storage: Same size as current
5. **Launch instance**
6. **Wait for instance to be Running** (2-3 minutes)
7. **Reassign Elastic IP** (if you have one):
   - EC2 → Elastic IPs
   - Select your IP
   - Actions → Disassociate (from old instance)
   - Actions → Associate → Select new instance
8. **Test new instance:**
   ```bash
   ssh -i ~/.ssh/macbook.pem ubuntu@<NEW_IP> "pm2 status"
   ```
9. **Terminate old instance** (only after confirming new one works)

---

## Post-Deployment Checklist

- [ ] All PM2 processes online
- [ ] Express API responding (`/health` endpoint)
- [ ] Plumber gateway responding
- [ ] Trading bots running (check `ps aux | grep Rscript`)
- [ ] No errors in logs for 30 minutes
- [ ] Bot messages appearing in Slack/Telegram
- [ ] Database receiving new signals
- [ ] No nested directories (`strategies/strategies`, `tradebot/tradebot`)
- [ ] All .env files in correct locations
- [ ] Git repository set up (`cd /home/ubuntu/infinite-trading-api && git status`)

---

## Future Updates (After Successful Migration)

Now that the monorepo is set up, future deployments are simpler:

```bash
# SSH into EC2
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# Navigate to repo
cd /home/ubuntu/infinite-trading-api

# Pull latest changes
git pull origin main

# Restart services
pm2 restart all

# Or rebuild if needed
cd express
npm install
npm run build
pm2 restart all
```

---

## Troubleshooting

### Issue: AMI creation taking too long
**Solution:** AMI creation can take 10-20 minutes for large instances. Wait patiently.

### Issue: "Have you created the AMI snapshot? (yes/no):" prompt
**Solution:** Only type "yes" after verifying AMI status is "available" in AWS Console

### Issue: PM2 processes not starting
**Solution:** 
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
cd /home/ubuntu/infinite-trading-api/express
pm2 logs  # Check for errors
npm install  # Reinstall dependencies if needed
npm run build
pm2 restart all
```

### Issue: Trading bots not running
**Solution:**
```bash
# Check if R packages are installed
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
Rscript -e "library(quantmod); library(TTR); library(httr)"

# Manually test a bot
cd /home/ubuntu/infinite-trading-api/strategies
Rscript main.R  # Should load without errors
```

### Issue: .env files missing after deployment
**Solution:** The deployment script backs them up and restores them. Check:
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
ls -lh /home/ubuntu/infinite-trading-api/.env
ls -lh /home/ubuntu/infinite-trading-api/express/.env
ls -lh /home/ubuntu/infinite-trading-api/express/src/sugar/.env
```

### Issue: Path errors in R scripts
**Solution:** The deployment already fixed the nested paths. Verify:
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
grep -n "dirname(dirname" /home/ubuntu/infinite-trading-api/strategies/*.R
# Should return NOTHING (all should be single dirname)
```

---

## Emergency Contacts

- **AWS Support:** If AMI issues
- **Your Team:** If trading strategy issues
- **Database Admin:** If MySQL connection issues

---

## Backup Information

- **AMI Name:** `prod-backup-2026-02-12`
- **File Backup Location:** `/home/ubuntu/backup_YYYYMMDD_HHMMSS/`
- **Backup Retention:** Keep for 7 days minimum
- **Git Repository:** https://github.com/etherpilled/infinite-trading-api

---

## Summary

This deployment will:
1. ✅ Create safety snapshot (AMI)
2. ✅ Backup all files on EC2
3. ✅ Setup git monorepo structure
4. ✅ Flatten nested directories (strategies/strategies → strategies)
5. ✅ Add missing components (plumber/, data-collectors/)
6. ✅ Preserve all .env credentials
7. ✅ Test everything before restarting
8. ✅ Enable git pull for future updates

**Total Downtime:** 15-20 minutes  
**Safety:** High (AMI + file backup)  
**Rollback Time:** 5 minutes (file restore) or 15 minutes (AMI restore)

---

**Ready to deploy? Follow the steps above carefully!** 🚀
