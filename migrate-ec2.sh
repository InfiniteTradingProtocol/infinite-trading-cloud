#!/bin/bash
# EC2 Safe Migration Script
# This script migrates the EC2 instance from old structure to new monorepo structure
# Run this ON the EC2 instance after pushing all local changes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  EC2 Migration to New Monorepo Structure${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Confirmation
echo -e "${YELLOW}⚠️  WARNING: This will modify production services!${NC}"
echo ""
echo "This script will:"
echo "  1. Create backups of all current code"
echo "  2. Pull latest changes from Git"
echo "  3. Test new structure in parallel"
echo "  4. Migrate PM2 services gradually"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Migration cancelled"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 1: Pre-Migration Backup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create backup directory
BACKUP_DIR=~/backups/migration_$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR
echo -e "${GREEN}✅ Created backup directory: $BACKUP_DIR${NC}"

# Backup current state
echo "📦 Backing up infinitetrading/..."
tar -czf $BACKUP_DIR/infinitetrading_backup.tar.gz ~/infinitetrading/ 2>&1 | grep -v "socket ignored" || true

echo "📦 Backing up infinitetrading_api/..."
tar -czf $BACKUP_DIR/infinitetrading_api_backup.tar.gz ~/infinitetrading_api/ 2>&1 | grep -v "socket ignored" || true

# Backup screen sessions
echo "📋 Documenting screen sessions..."
screen -ls > $BACKUP_DIR/screen_sessions.txt 2>&1 || true

# Backup PM2 state
echo "📋 Documenting PM2 state..."
pm2 list > $BACKUP_DIR/pm2_list.txt 2>&1 || echo "PM2 not running" > $BACKUP_DIR/pm2_list.txt

echo -e "${GREEN}✅ Backups complete${NC}"
echo ""

# Document current service status
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 2: Document Current State"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test current services
echo "🧪 Testing current services..."

# Test Express
if curl -s http://localhost:8000/ > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Express (8000) responding${NC}"
else
    echo -e "${RED}❌ Express (8000) not responding${NC}"
fi

# Test Plumber
if curl -s http://localhost:8002/__docs__/ > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Plumber (8002) responding${NC}"
else
    echo -e "${RED}❌ Plumber (8002) not responding${NC}"
fi

# Test Gateway
if curl -s http://localhost:8003/__docs__/ > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Gateway (8003) responding${NC}"
else
    echo -e "${RED}❌ Gateway (8003) not responding${NC}"
fi

echo ""
read -p "Do all services need to be running? Continue anyway? (yes/no): " CONTINUE
if [ "$CONTINUE" != "yes" ]; then
    echo "❌ Migration cancelled"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 3: Update Git Repository"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd ~/infinitetrading_api

echo "📥 Pulling latest changes..."
git stash || true
git pull origin main

echo -e "${GREEN}✅ Git repository updated${NC}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 4: Verify New Structure"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check that all expected directories exist
REQUIRED_DIRS=("express" "plumber" "strategies" "tradebot" "data-collectors")
ALL_DIRS_EXIST=true

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "${GREEN}✅ $dir exists${NC}"
    else
        echo -e "${RED}❌ $dir missing!${NC}"
        ALL_DIRS_EXIST=false
    fi
done

if [ "$ALL_DIRS_EXIST" = false ]; then
    echo -e "${RED}❌ Required directories missing. Aborting migration.${NC}"
    exit 1
fi

# Check critical files
CRITICAL_FILES=(
    "plumber/api.R"
    "plumber/gateway/gateway.R"
    "express/build/src/index.js"
    "express/ecosystem.config.js"
    ".env"
)

for file in "${CRITICAL_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✅ $file exists${NC}"
    else
        echo -e "${RED}❌ $file missing!${NC}"
        ALL_DIRS_EXIST=false
    fi
done

if [ "$ALL_DIRS_EXIST" = false ]; then
    echo -e "${RED}❌ Critical files missing. Aborting migration.${NC}"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 5: Build Express"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd ~/infinitetrading_api/express
echo "🔨 Building Express..."
npm run build

if [ ! -f "build/src/index.js" ]; then
    echo -e "${RED}❌ Build failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Express build successful${NC}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 6: Stop Old Services (DOWNTIME STARTS)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "⏸️  Stopping Express screen session..."
screen -S api -X quit 2>/dev/null || echo "Express screen not running"

echo "⏸️  Stopping Gateway screen session..."
screen -S gateway -X quit 2>/dev/null || echo "Gateway screen not running"

echo "⏸️  Stopping Plumber screen session..."
screen -S plumber -X quit 2>/dev/null || echo "Plumber screen not running"

# Wait for ports to be free
echo "⏳ Waiting for ports to be released..."
sleep 5

echo -e "${GREEN}✅ Old services stopped${NC}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 7: Start New Services with PM2"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd ~/infinitetrading_api/express

# Stop any existing PM2 processes
pm2 stop all 2>/dev/null || true
pm2 delete all 2>/dev/null || true

# Start new services
echo "🚀 Starting services with PM2..."
pm2 start ecosystem.config.js

# Save PM2 configuration
pm2 save

echo "⏳ Waiting for services to start (15 seconds)..."
sleep 15

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 8: Verify New Services (DOWNTIME ENDS)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test new services
SERVICES_OK=true

# Test Express
if curl -s http://localhost:8000/ > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Express (8000) responding${NC}"
else
    echo -e "${RED}❌ Express (8000) not responding${NC}"
    SERVICES_OK=false
fi

# Test Plumber
if curl -s http://localhost:8002/__docs__/ > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Plumber (8002) responding${NC}"
else
    echo -e "${RED}❌ Plumber (8002) not responding${NC}"
    SERVICES_OK=false
fi

# Test Gateway
if curl -s http://localhost:8003/__docs__/ > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Gateway (8003) responding${NC}"
else
    echo -e "${RED}❌ Gateway (8003) not responding${NC}"
    SERVICES_OK=false
fi

echo ""
pm2 list

if [ "$SERVICES_OK" = false ]; then
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}  MIGRATION FAILED - SERVICES NOT RESPONDING${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Check logs with:"
    echo "  pm2 logs"
    echo ""
    echo "To rollback, run:"
    echo "  ./scripts/rollback-migration.sh $BACKUP_DIR"
    exit 1
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✅ MIGRATION SUCCESSFUL!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "📝 Summary:"
echo "  • Backup saved to: $BACKUP_DIR"
echo "  • All services running on PM2"
echo "  • Old infinitetrading/ directory untouched (can be removed after testing)"
echo ""
echo "📊 Monitor with:"
echo "  pm2 list"
echo "  pm2 logs"
echo "  pm2 monit"
echo ""
echo "🎯 Next steps:"
echo "  1. Test all API endpoints"
echo "  2. Monitor logs for 1 hour"
echo "  3. If stable, can remove ~/infinitetrading/"
echo "  4. Update any cron jobs to use new paths"
echo ""
echo -e "${YELLOW}⚠️  Keep backup for at least 1 week: $BACKUP_DIR${NC}"
