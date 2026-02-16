# 🔄 EC2 Rollback Instructions

## If Deployment Fails - Two Rollback Options

---

## Option 1: Quick Rollback from Backup Directory (5 minutes)

**When to use**: Minor issues, services won't start, file corruption

### Steps:

```bash
# SSH into EC2
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# Stop all services
pm2 stop all
forever stopall
pkill -f "Rscript"

# Find your backup (look for latest timestamp)
ls -lh /home/ubuntu/backup_*

# Set backup directory (replace with your actual backup timestamp)
BACKUP_DIR="/home/ubuntu/backup_20260212_153045"

# Restore files
rm -rf /home/ubuntu/infinite-trading-api
cp -r $BACKUP_DIR/infinitetrading_api_backup /home/ubuntu/infinitetrading_api
cp -r $BACKUP_DIR/infinitetrading_src_backup /home/ubuntu/infinitetrading/src

# Restore .env files
cp $BACKUP_DIR/home/ubuntu/.env /home/ubuntu/
cp $BACKUP_DIR/home/ubuntu/infinitetrading/src/.env /home/ubuntu/infinitetrading/src/

# Restart services
cd /home/ubuntu/infinitetrading_api/express
pm2 start ecosystem.config.js
pm2 save
```

**Time**: ~5 minutes  
**Downtime**: ~5 minutes  
**Risk**: Low - just copying files back

---

## Option 2: Full Rollback from AMI Snapshot (15 minutes)

**When to use**: Major corruption, system instability, can't fix with file restore

### Steps:

#### 1. Prepare Information (1 minute)

Before starting, note down:
- Current instance ID: `i-xxxxxxxxxxxxx`
- Elastic IP (if you have one): `3.135.99.211`
- Security group ID: `sg-xxxxxxxxxxxxx`
- Key pair name: `macbook`
- AMI snapshot name: `prod-backup-20260212`

#### 2. Launch New Instance from AMI (10 minutes)

```bash
# Go to AWS Console → EC2 → AMIs
# Find your snapshot: prod-backup-20260212
# Right-click → Launch instance from AMI

# Configure:
Instance type: t3.medium (or whatever you were using)
Key pair: macbook
Security group: Same as old instance
Storage: Keep same size

# Launch instance → Wait for it to be "Running"
```

#### 3. Reassign Elastic IP (2 minutes)

```bash
# If you have an Elastic IP:
# AWS Console → EC2 → Elastic IPs
# Select your IP (3.135.99.211)
# Actions → Disassociate address (from old instance)
# Actions → Associate address → Select new instance
```

#### 4. Test New Instance (2 minutes)

```bash
# SSH into new instance
ssh -i ~/.ssh/macbook.pem ubuntu@<NEW_INSTANCE_IP>

# Check services
pm2 status
pm2 logs

# Test API
curl http://localhost:3001/health

# Test bots
ps aux | grep Rscript
```

#### 5. Terminate Old Instance (1 minute)

```bash
# Only after confirming new instance works!
# AWS Console → EC2 → Instances
# Select old (broken) instance
# Instance state → Terminate instance
```

**Time**: ~15 minutes  
**Downtime**: ~15 minutes (can be 0 if you have load balancer)  
**Risk**: Very low - complete system restore

---

## Quick Rollback Commands (Copy-Paste)

### Stop Everything
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com << 'EOF'
pm2 stop all
forever stopall
pkill -f "Rscript"
pkill -f "node.*infinite"
EOF
```

### Restore from Backup Directory
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com << 'EOF'
BACKUP_DIR=$(ls -dt /home/ubuntu/backup_* | head -1)
echo "Restoring from: $BACKUP_DIR"

rm -rf /home/ubuntu/infinite-trading-api
cp -r $BACKUP_DIR/infinitetrading_api_backup /home/ubuntu/infinitetrading_api
cp -r $BACKUP_DIR/infinitetrading_src_backup /home/ubuntu/infinitetrading/src

# Restore configs
cp $BACKUP_DIR/home/ubuntu/.env /home/ubuntu/ 2>/dev/null || true
cp $BACKUP_DIR/ecosystem.config.js /home/ubuntu/infinitetrading_api/express/ 2>/dev/null || true

# Restart
cd /home/ubuntu/infinitetrading_api/express
pm2 start ecosystem.config.js
pm2 save
pm2 status
EOF
```

---

## Prevention Tips

### Before Deployment:
1. ✅ Create AMI snapshot (AWS Console)
2. ✅ Note down instance details
3. ✅ Test deployment script locally first
4. ✅ Deploy during low-traffic hours

### During Deployment:
1. 👁️ Watch logs in real-time: `pm2 logs`
2. 👁️ Monitor system resources: `htop`
3. 👁️ Check for errors immediately after restart

### After Deployment:
1. ⏰ Wait 10 minutes before declaring success
2. 📊 Monitor trading bots for 1 hour
3. 🧪 Test all critical endpoints
4. 💾 Keep backup for 7 days before deleting

---

## Emergency Contacts & Resources

- **AWS Console**: https://console.aws.amazon.com/ec2
- **PM2 Docs**: https://pm2.keymetrics.io/docs/usage/quick-start/
- **Backup Location**: `/home/ubuntu/backup_YYYYMMDD_HHMMSS/`
- **Logs Location**: 
  - Express: `pm2 logs`
  - Plumber: `/home/ubuntu/infinite-trading-api/plumber/logs/gateway.log`
  - Strategies: `/home/ubuntu/infinite-trading-api/strategies/logs/`

---

## Testing Checklist After Rollback

- [ ] SSH connection works
- [ ] PM2 shows all processes running (`pm2 status`)
- [ ] Express API responding (`curl http://localhost:3001/health`)
- [ ] Trading bots running (`ps aux | grep Rscript`)
- [ ] Database connection working
- [ ] No errors in logs (`pm2 logs`, `tail -f plumber/logs/gateway.log`)
- [ ] Check Slack/Telegram for bot messages
- [ ] Verify trades are being executed (check DB)

---

**Remember**: The AMI snapshot is your safety net. As long as you create it before deployment, you can always recover! 🛡️
