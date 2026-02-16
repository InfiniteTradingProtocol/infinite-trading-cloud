#!/bin/bash
# EC2 Backup Script - Run this on EC2 before migration

echo "🔒 Creating EC2 Backup..."
echo ""

# Create backup directory with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=~/backups/$TIMESTAMP
mkdir -p $BACKUP_DIR

echo "📁 Backup directory: $BACKUP_DIR"
echo ""

# Backup infinitetrading directory
echo "📦 Backing up ~/infinitetrading/ ..."
tar -czf $BACKUP_DIR/infinitetrading_backup.tar.gz ~/infinitetrading/ 2>&1 | grep -v "socket ignored"
if [ $? -eq 0 ]; then
    echo "✅ infinitetrading backed up"
else
    echo "❌ infinitetrading backup failed"
    exit 1
fi

# Backup git repo
echo "📦 Backing up ~/infinitetrading_api/ ..."
tar -czf $BACKUP_DIR/infinitetrading_api_backup.tar.gz ~/infinitetrading_api/ 2>&1 | grep -v "socket ignored"
if [ $? -eq 0 ]; then
    echo "✅ infinitetrading_api backed up"
else
    echo "❌ infinitetrading_api backup failed"
    exit 1
fi

# Backup screen sessions list
echo "📋 Saving screen sessions list..."
screen -ls > $BACKUP_DIR/screen_sessions.txt
echo "✅ Screen sessions saved"

# Backup startup script
echo "📋 Backing up startup script..."
cp ~/startup.sh $BACKUP_DIR/startup.sh.backup
echo "✅ Startup script backed up"

# Backup PM2 list
echo "📋 Saving PM2 status..."
pm2 list > $BACKUP_DIR/pm2_list.txt 2>&1 || echo "No PM2 processes"

# Backup MySQL databases (optional - uncomment if needed)
# echo "💾 Backing up MySQL databases..."
# mysqldump -u root -p infinitetrading > $BACKUP_DIR/infinitetrading_db.sql

# List backup contents
echo ""
echo "📊 Backup Summary:"
ls -lh $BACKUP_DIR/

# Calculate total size
TOTAL_SIZE=$(du -sh $BACKUP_DIR | cut -f1)
echo ""
echo "✅ Backup Complete!"
echo "   Location: $BACKUP_DIR"
echo "   Total Size: $TOTAL_SIZE"
echo ""
echo "📝 Restore Instructions:"
echo "   To restore infinitetrading:"
echo "   tar -xzf $BACKUP_DIR/infinitetrading_backup.tar.gz -C /"
echo ""
echo "   To restore infinitetrading_api:"
echo "   tar -xzf $BACKUP_DIR/infinitetrading_api_backup.tar.gz -C /"
echo ""
echo "   To restore startup script:"
echo "   cp $BACKUP_DIR/startup.sh.backup ~/startup.sh"
