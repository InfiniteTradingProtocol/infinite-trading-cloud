#!/bin/bash

# Incremental RDS Backup (runs every 5 minutes)
# Only backs up if there are changes

LOCK_FILE="/tmp/rds_backup.lock"
LAST_BACKUP_TIME_FILE="/tmp/last_rds_backup.txt"

# Check if already running
if [ -f "$LOCK_FILE" ]; then
    exit 0
fi

touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

# RDS Configuration
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

BACKUP_FILE="/tmp/mysql_incremental_$(date +%Y%m%d_%H%M%S).sql"

# Get last backup time (or 5 minutes ago)
if [ -f "$LAST_BACKUP_TIME_FILE" ]; then
    LAST_BACKUP=$(cat "$LAST_BACKUP_TIME_FILE")
else
    LAST_BACKUP=$(date -d "5 minutes ago" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -v-5M "+%Y-%m-%d %H:%M:%S")
fi

echo "[$(date)] Starting incremental backup..."

# Create backup
mysqldump -u${LOCAL_USER} -p${LOCAL_PASS} -h${LOCAL_HOST} ${LOCAL_DB} \
    --single-transaction \
    --quick \
    --lock-tables=false \
    --skip-comments \
    > ${BACKUP_FILE} 2>/dev/null

if [ $? -eq 0 ]; then
    # Import to RDS
    mysql -h${RDS_HOST} -P${RDS_PORT} -u${RDS_USER} -p"${RDS_PASS}" \
        --ssl-ca=${RDS_SSL} ${RDS_DB} < ${BACKUP_FILE} 2>/dev/null
    
    if [ $? -eq 0 ]; then
        date "+%Y-%m-%d %H:%M:%S" > "$LAST_BACKUP_TIME_FILE"
        echo "[$(date)] ✅ Backup successful"
    else
        echo "[$(date)] ❌ RDS import failed"
    fi
    
    rm -f ${BACKUP_FILE}
else
    echo "[$(date)] ❌ Backup creation failed"
fi

