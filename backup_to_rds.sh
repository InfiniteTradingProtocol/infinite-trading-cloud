#!/bin/bash

# MySQL to RDS Backup Script
# Backs up local MySQL database to AWS RDS Aurora

echo "========================================="
echo "MySQL → RDS Backup Script"
echo "========================================="

# Local MySQL
LOCAL_HOST="localhost"
LOCAL_USER="richard_clare"
LOCAL_PASS="AxDWeW8E7w8dSXJKsXsdfASXaxAD279347"
LOCAL_DB="infinitetrading"

# RDS Aurora
RDS_HOST="infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com"
RDS_PORT="3306"
RDS_USER="admin"
RDS_PASS="NcwbBmT5Vxv9ZAx"
RDS_DB="infinitetrading"
RDS_SSL="/certs/global-bundle.pem"

BACKUP_FILE="/tmp/mysql_backup_$(date +%Y%m%d_%H%M%S).sql"

echo ""
echo "📦 Step 1: Creating backup from local MySQL..."
mysqldump -u${LOCAL_USER} -p${LOCAL_PASS} -h${LOCAL_HOST} ${LOCAL_DB} \
    --single-transaction \
    --quick \
    --lock-tables=false \
    --routines \
    --triggers \
    > ${BACKUP_FILE}

if [ $? -eq 0 ]; then
    SIZE=$(du -h ${BACKUP_FILE} | cut -f1)
    TABLES=$(grep -c "CREATE TABLE" ${BACKUP_FILE})
    echo "✅ Backup created: ${BACKUP_FILE}"
    echo "   Size: ${SIZE}"
    echo "   Tables: ${TABLES}"
else
    echo "❌ Failed to create backup"
    exit 1
fi

echo ""
echo "🔌 Step 2: Testing RDS connectivity..."
mysql -h${RDS_HOST} -P${RDS_PORT} -u${RDS_USER} -p"${RDS_PASS}" \
    --ssl-ca=${RDS_SSL} \
    -e "SELECT VERSION();" 2>&1 | head -5

if [ $? -eq 0 ]; then
    echo "✅ RDS connection successful"
else
    echo "❌ Cannot connect to RDS"
    echo ""
    echo "TROUBLESHOOTING:"
    echo "1. Check RDS security group allows your EC2 security group"
    echo "2. Verify EC2 instance: i-09c36a9715b715db6"
    echo "3. Verify RDS security group has inbound rule for port 3306"
    echo "4. Check AWS Console > RDS > infinitetrading > Connectivity"
    exit 1
fi

echo ""
echo "🗄️  Step 3: Creating database if not exists..."
mysql -h${RDS_HOST} -P${RDS_PORT} -u${RDS_USER} -p"${RDS_PASS}" \
    --ssl-ca=${RDS_SSL} \
    -e "CREATE DATABASE IF NOT EXISTS ${RDS_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

echo ""
echo "📥 Step 4: Importing backup to RDS..."
echo "   This may take several minutes..."
pv ${BACKUP_FILE} 2>/dev/null | mysql -h${RDS_HOST} -P${RDS_PORT} -u${RDS_USER} -p"${RDS_PASS}" \
    --ssl-ca=${RDS_SSL} ${RDS_DB} 2>&1 || \
mysql -h${RDS_HOST} -P${RDS_PORT} -u${RDS_USER} -p"${RDS_PASS}" \
    --ssl-ca=${RDS_SSL} ${RDS_DB} < ${BACKUP_FILE}

if [ $? -eq 0 ]; then
    echo "✅ Backup imported successfully"
else
    echo "❌ Failed to import backup"
    exit 1
fi

echo ""
echo "✓ Step 5: Verifying data..."
echo -n "   Local tables: "
mysql -u${LOCAL_USER} -p${LOCAL_PASS} -h${LOCAL_HOST} ${LOCAL_DB} \
    -sNe "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=;"

echo -n "   RDS tables: "
mysql -h${RDS_HOST} -P${RDS_PORT} -u${RDS_USER} -p"${RDS_PASS}" \
    --ssl-ca=${RDS_SSL} ${RDS_DB} \
    -sNe "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=;"

echo ""
echo "   Sample data check (candles):"
LOCAL_CANDLES=$(mysql -u${LOCAL_USER} -p${LOCAL_PASS} -h${LOCAL_HOST} ${LOCAL_DB} \
    -sNe "SELECT COUNT(*) FROM candles;" 2>/dev/null || echo "0")
RDS_CANDLES=$(mysql -h${RDS_HOST} -P${RDS_PORT} -u${RDS_USER} -p"${RDS_PASS}" \
    --ssl-ca=${RDS_SSL} ${RDS_DB} \
    -sNe "SELECT COUNT(*) FROM candles;" 2>/dev/null || echo "0")

echo "   Local candles: ${LOCAL_CANDLES}"
echo "   RDS candles: ${RDS_CANDLES}"

echo ""
echo "========================================="
echo "✅ Backup Complete!"
echo "========================================="
echo ""
echo "Backup file: ${BACKUP_FILE}"
echo "To delete: rm ${BACKUP_FILE}"
echo ""
echo "Connect to RDS:"
echo "mysql -h${RDS_HOST} -P${RDS_PORT} -u${RDS_USER} -p --ssl-ca=${RDS_SSL} ${RDS_DB}"
echo ""

