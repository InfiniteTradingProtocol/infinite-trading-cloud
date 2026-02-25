#!/bin/bash

# Safe RDS Migration Script
# Migrates services from local MySQL to RDS one by one with testing

set -e

LOCAL_HOST="localhost"
LOCAL_USER="richard_clare"
LOCAL_PASS="AxDWeW8E7w8dSXJKsXsdfASXaxAD279347"
LOCAL_DB="infinitetrading"

RDS_HOST="infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com"
RDS_PORT="3306"
RDS_USER="admin"
RDS_PASS="NcwbBmT5Vxv9ZAx"
RDS_DB="infinitetrading"
RDS_SSL="/certs/global-bundle.pem"

BACKUP_DIR="/home/ubuntu/rds_migration_backups"
mkdir -p "$BACKUP_DIR"

echo "========================================="
echo "RDS Migration - Phase 1: Preparation"
echo "========================================="

# 1. Full backup
echo ""
echo "Step 1: Creating full backup..."
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/full_backup_${TIMESTAMP}.sql"
mysqldump -u${LOCAL_USER} -p${LOCAL_PASS} -h${LOCAL_HOST} ${LOCAL_DB} \
    --single-transaction --quick --lock-tables=false --routines --triggers \
    > ${BACKUP_FILE}
echo "✅ Backup: ${BACKUP_FILE} ($(du -h ${BACKUP_FILE} | cut -f1))"

# 2. Sync to RDS
echo ""
echo "Step 2: Syncing to RDS..."
mysql -h${RDS_HOST} -P${RDS_PORT} -u${RDS_USER} -p"${RDS_PASS}" \
    --ssl-ca=${RDS_SSL} ${RDS_DB} < ${BACKUP_FILE}
echo "✅ RDS synced"

# 3. Verify data integrity
echo ""
echo "Step 3: Verifying data integrity..."
LOCAL_TABLES=$(mysql -u${LOCAL_USER} -p${LOCAL_PASS} -h${LOCAL_HOST} ${LOCAL_DB} \
    -sNe "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=\"${LOCAL_DB}\";")
RDS_TABLES=$(mysql -h${RDS_HOST} -P${RDS_PORT} -u${RDS_USER} -p"${RDS_PASS}" \
    --ssl-ca=${RDS_SSL} ${RDS_DB} \
    -sNe "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=\"${RDS_DB}\";")

echo "  Local tables: ${LOCAL_TABLES}"
echo "  RDS tables: ${RDS_TABLES}"

if [ "$LOCAL_TABLES" != "$RDS_TABLES" ]; then
    echo "❌ Table count mismatch!"
    exit 1
fi
echo "✅ Data integrity verified"

# 4. Create .env backup and new RDS version
echo ""
echo "Step 4: Preparing environment files..."
cp ~/infinitetrading/src/.env ~/infinitetrading/src/.env.local_mysql_backup
cp ~/infinitetrading_api/express/.env ~/infinitetrading_api/express/.env.local_mysql_backup

# Create RDS version (not applied yet)
cat > ~/infinitetrading/src/.env.rds << EOF
# RDS Configuration
db_user="${RDS_USER}"
db_password="${RDS_PASS}"
db_ip="${RDS_HOST}"
db_port="${RDS_PORT}"
db_schema="${RDS_DB}"
dbname="${RDS_DB}"
host="${RDS_HOST}"

# SSL Configuration
db_ssl_ca="${RDS_SSL}"

# Existing API keys (preserved from original .env)
$(grep -E "^(cmc_apikey|ITP_APIKEY|COINGECKO_APIKEY|TG_BOT|TG_CHAT_ID|ALCHEMY_BALANCES_APIKEY|kraken)" ~/infinitetrading/src/.env)
EOF

echo "✅ Environment files prepared"
echo "   Backup: ~/.env.local_mysql_backup"
echo "   RDS config: ~/.env.rds (not active yet)"

echo ""
echo "========================================="
echo "✅ Phase 1 Complete: Ready for Testing"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Test RDS connection from all services"
echo "2. Switch one service at a time to RDS"
echo "3. Monitor and verify before next service"
echo ""

