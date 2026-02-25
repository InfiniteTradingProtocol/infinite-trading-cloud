# RDS Migration Guide

Complete guide for migrating from local MySQL to AWS RDS Aurora.

## 📊 Current Status

**Date:** February 17, 2026  
**Local Database:** MySQL 8.0.45 on EC2 (localhost)  
**RDS Database:** MariaDB 11.4.8 Aurora (infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com)

### Database Stats

| Metric | Value |
|--------|-------|
| **Size** | 1.36 MB |
| **Tables** | 56 |
| **Query Rate** | ~81 queries/second |
| **Active Connections** | 41 concurrent |
| **Uptime** | 30 hours |
| **Total Queries** | 8.67 million |

## ❓ Your Questions Answered

### 1. SSL Certificate Auto-Renewal

✅ **YES** - AWS RDS SSL certificates auto-renew

- **Current Certificate:** Valid until **May 19, 2061** (35+ years!)
- **Location:** `/certs/global-bundle.pem` on EC2
- **AWS manages renewal:** You don't need to update the certificate
- **Download URL:** https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

**Action Required:** None - AWS handles this automatically

### 2. Automated 5-Minute Backup

✅ **CONFIGURED** - PM2 service created

**Script Location:** `/home/ubuntu/backup_to_rds_incremental.sh`

**Features:**
- Runs every 5 minutes via PM2
- Incremental backups (only changed data)
- Lock file prevents overlapping backups
- Automatic cleanup of backup files
- Logs to `/home/ubuntu/infinitetrading/src/logs/rds-backup-*.log`

**Start the backup service:**
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@3.135.99.211 'cd /home/ubuntu/infinitetrading_api && pm2 start ecosystem.config.js --only rds-backup && pm2 save'
```

**Monitor backups:**
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@3.135.99.211 'pm2 logs rds-backup --lines 50'
```

**Stop backups:**
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@3.135.99.211 'pm2 stop rds-backup'
```

### 3. Database Comparison

⚠️ **MINOR DIFFERENCES** - Row counts differ (new data added to local)

**Tables Match:** ✅ Both have 56 tables  
**Schema Match:** ✅ Structure is identical  
**Data Differences:** A few tables have different row counts due to new data since backup

**Compare databases:**
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@3.135.99.211 '
echo "=== Local MySQL ==="
mysql -urichard_clare -pAxDWeW8E7w8dSXJKsXsdfASXaxAD279347 infinitetrading \
  -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=\"infinitetrading\";"

echo "=== RDS Aurora ==="
mysql -h infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com \
  -P 3306 -u admin -p"NcwbBmT5Vxv9ZAx" --ssl-ca=/certs/global-bundle.pem infinitetrading \
  -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=\"infinitetrading\";"
'
```

### 4. RDS Capacity Assessment

⚠️ **UPGRADE RECOMMENDED**

**Current Load:**
- **81 queries/second** (6,900 queries/minute)
- **41 concurrent connections**
- **19 PM2 services** all hitting database

**Your Current RDS (Estimated):**
- Instance Type: db.t3.micro or db.t4g.micro
- vCPUs: 2
- Memory: 1 GB
- Max Connections: ~80-100
- Cost: ~$12/month

**Recommended Upgrade:**

| Instance | vCPU | RAM | Max Connections | QPS Capacity | Cost/Month | Use Case |
|----------|------|-----|-----------------|--------------|------------|----------|
| **db.t3.small** | 2 | 2 GB | ~150 | ~200 QPS | ~$25 | Minimum for production |
| **db.t3.medium** ⭐ | 2 | 4 GB | ~300 | ~500 QPS | ~$50 | **Recommended** |
| **db.t3.large** | 2 | 8 GB | ~600 | ~1000 QPS | ~$100 | High traffic |
| **Aurora Serverless v2** | Auto | 0.5-16 GB | Auto | Auto | $45-300 | Variable load ⭐ |

**Why Upgrade:**
- You're at **50% connection capacity** (41/80)
- Query rate will increase as trading activity grows
- No headroom for spikes
- Better performance for complex queries

**How to Upgrade (AWS Console):**
1. Go to RDS > Databases > infinitetrading
2. Click "Modify"
3. Change "DB instance class" to db.t3.medium
4. Choose "Apply immediately" or during maintenance window
5. Click "Modify DB instance"

## 🧪 Local Testing Strategy

### Prerequisites

You don't have MySQL installed locally. Here's how to test:

#### Option 1: Install MySQL Locally (Recommended)

```bash
# Install MySQL
brew install mysql

# Start MySQL service
brew services start mysql

# Secure installation
mysql_secure_installation

# Create database
mysql -uroot -p -e "CREATE DATABASE infinitetrading CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# Create user
mysql -uroot -p -e "CREATE USER 'richard_clare'@'localhost' IDENTIFIED BY 'AxDWeW8E7w8dSXJKsXsdfASXaxAD279347';"
mysql -uroot -p -e "GRANT ALL PRIVILEGES ON infinitetrading.* TO 'richard_clare'@'localhost';"
mysql -uroot -p -e "FLUSH PRIVILEGES;"
```

#### Option 2: Docker MySQL (Easier)

```bash
# Run MySQL in Docker
docker run --name mysql-local \
  -e MYSQL_ROOT_PASSWORD=root \
  -e MYSQL_DATABASE=infinitetrading \
  -e MYSQL_USER=richard_clare \
  -e MYSQL_PASSWORD=AxDWeW8E7w8dSXJKsXsdfASXaxAD279347 \
  -p 3306:3306 \
  -d mysql:8.0

# Test connection
docker exec -it mysql-local mysql -urichard_clare -p infinitetrading
```

#### Option 3: Use RDS Directly (No local MySQL needed)

You can skip local MySQL and point your local development directly to RDS:

```bash
# Test RDS connection from local machine
mysql -h infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com \
  -P 3306 -u admin -p"NcwbBmT5Vxv9ZAx" \
  --ssl-ca=<(curl -s https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem) \
  infinitetrading
```

### Local Migration Testing Steps

1. **Download EC2 backup to local machine:**
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@3.135.99.211 'mysqldump -urichard_clare -pAxDWeW8E7w8dSXJKsXsdfASXaxAD279347 infinitetrading --single-transaction --quick > /tmp/local_backup.sql'

scp -i ~/.ssh/macbook.pem ubuntu@3.135.99.211:/tmp/local_backup.sql ~/Downloads/
```

2. **Import to local MySQL:**
```bash
# If using Docker:
docker exec -i mysql-local mysql -urichard_clare -pAxDWeW8E7w8dSXJKsXsdfASXaxAD279347 infinitetrading < ~/Downloads/local_backup.sql

# If using Homebrew MySQL:
mysql -urichard_clare -pAxDWeW8E7w8dSXJKsXsdfASXaxAD279347 infinitetrading < ~/Downloads/local_backup.sql
```

3. **Test RDS connection from local:**
```bash
# Download SSL certificate
curl -o ~/Downloads/rds-ca-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

# Test connection
mysql -h infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com \
  -P 3306 -u admin -p"NcwbBmT5Vxv9ZAx" \
  --ssl-ca=~/Downloads/rds-ca-bundle.pem \
  infinitetrading \
  -e "SHOW TABLES;"
```

4. **Update local .env files to use RDS:**
```bash
# Update express/.env
cat >> express/.env << EOF

# RDS Configuration (testing)
DB_HOST=infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com
DB_PORT=3306
DB_USER=admin
DB_PASSWORD=NcwbBmT5Vxv9ZAx
DB_NAME=infinitetrading
DB_SSL_CA=/path/to/rds-ca-bundle.pem
EOF
```

5. **Test application with RDS:**
```bash
cd /Users/richardclare/infinite-trading-api/express
npm run dev
# Test your API endpoints
```

6. **Monitor RDS performance:**
- Go to AWS Console > RDS > infinitetrading > Monitoring
- Watch CPU, connections, and query throughput
- Ensure no bottlenecks

7. **Once verified locally, migrate EC2:**
```bash
# Update EC2 to use RDS instead of localhost
ssh -i ~/.ssh/macbook.pem ubuntu@3.135.99.211 'cd ~/infinitetrading/src && sed -i.backup "s/host=\"localhost\"/host=\"infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com\"/" .env'

# Restart all PM2 services
ssh -i ~/.ssh/macbook.pem ubuntu@3.135.99.211 'pm2 restart all'

# Monitor logs
ssh -i ~/.ssh/macbook.pem ubuntu@3.135.99.211 'pm2 logs --lines 100'
```

## 🔐 RDS Credentials

**Stored in:**
- `/home/ubuntu/infinitetrading/src/.env` (R scripts)
- `/home/ubuntu/infinitetrading_api/express/.env` (Node.js)

**Environment Variables:**
```bash
# R Format
rds_endpoint="infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com"
rds_port="3306"
rds_user="admin"
rds_password="NcwbBmT5Vxv9ZAx"
rds_database="infinitetrading"
rds_ssl_ca="/certs/global-bundle.pem"

# Node.js Format
RDS_ENDPOINT=infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com
RDS_PORT=3306
RDS_USER=admin
RDS_PASSWORD=NcwbBmT5Vxv9ZAx
RDS_DATABASE=infinitetrading
RDS_SSL_CA=/certs/global-bundle.pem
```

## 📋 Migration Checklist

### Before Migration

- [x] SSL certificate downloaded to EC2
- [x] RDS credentials added to .env files
- [x] Backup script created and tested
- [x] Initial full backup completed (56 tables)
- [x] PM2 automated backup configured
- [ ] RDS instance upgraded to db.t3.medium
- [ ] Local MySQL installed (Docker or Homebrew)
- [ ] Local testing with RDS connection
- [ ] Application tested locally with RDS
- [ ] Performance monitoring enabled

### During Migration

- [ ] Enable RDS automated backups (AWS Console)
- [ ] Set backup retention to 7 days
- [ ] Update all .env files to use RDS host
- [ ] Restart all PM2 services
- [ ] Monitor logs for connection errors
- [ ] Test all API endpoints
- [ ] Verify trading operations work
- [ ] Check strategy execution

### After Migration

- [ ] Stop local MySQL on EC2 (if migrating fully)
- [ ] Update startup.sh to use RDS
- [ ] Document RDS connection strings
- [ ] Set up CloudWatch alarms for RDS
- [ ] Test failover scenarios
- [ ] Update development guide

## 🚨 Rollback Plan

If RDS migration fails:

1. **Revert .env files:**
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@3.135.99.211 'cd ~/infinitetrading/src && cp .env.backup .env'
```

2. **Restart PM2 services:**
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@3.135.99.211 'pm2 restart all'
```

3. **Verify local MySQL is running:**
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@3.135.99.211 'systemctl status mysql'
```

## 📈 Monitoring RDS

### Key Metrics to Watch

1. **CPU Utilization** - Should stay < 70%
2. **Database Connections** - Should be < 50% of max
3. **Freeable Memory** - Should not hit zero
4. **Read/Write IOPS** - Ensure within burst credits
5. **Network Throughput** - Monitor for bottlenecks

### CloudWatch Alarms (Recommended)

```bash
# Set up in AWS Console > CloudWatch > Alarms
- CPUUtilization > 80% for 5 minutes
- DatabaseConnections > 70 for 5 minutes
- FreeableMemory < 500 MB for 5 minutes
- WriteLatency > 100ms for 5 minutes
- ReadLatency > 100ms for 5 minutes
```

## 🔧 Troubleshooting

### Connection Refused
- Check security group allows EC2 security group
- Verify RDS is publicly accessible or in same VPC
- Test with `telnet infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com 3306`

### Slow Queries
- Check RDS instance size
- Enable slow query log
- Review indexes on tables
- Consider upgrading to larger instance

### Too Many Connections
- Reduce PM2 service connection pooling
- Upgrade RDS instance
- Enable connection pooling in application

### SSL Certificate Issues
- Re-download certificate
- Verify file permissions
- Check certificate path in .env

## 📚 Additional Resources

- [AWS RDS Documentation](https://docs.aws.amazon.com/rds/)
- [Aurora MySQL Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.BestPractices.html)
- [RDS Monitoring Guide](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Monitoring.html)

---

**Last Updated:** February 17, 2026  
**Status:** Ready for local testing, then EC2 migration
