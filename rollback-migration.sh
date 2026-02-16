#!/bin/bash
# EC2 Rollback Script
# Rollback to screen-based services if PM2 migration fails
# Usage: ./rollback-migration.sh [BACKUP_DIR]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  EC2 Rollback to Previous State${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

BACKUP_DIR=$1

if [ -z "$BACKUP_DIR" ]; then
    # Find most recent backup
    BACKUP_DIR=$(ls -td ~/backups/migration_* 2>/dev/null | head -1)
    if [ -z "$BACKUP_DIR" ]; then
        echo -e "${RED}❌ No backup directory specified and no backups found!${NC}"
        echo "Usage: ./rollback-migration.sh [BACKUP_DIR]"
        exit 1
    fi
    echo -e "${YELLOW}⚠️  Using most recent backup: $BACKUP_DIR${NC}"
fi

if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}❌ Backup directory not found: $BACKUP_DIR${NC}"
    exit 1
fi

echo ""
echo "Backup directory: $BACKUP_DIR"
echo ""
read -p "Are you sure you want to rollback? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Rollback cancelled"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 1: Stop PM2 Services"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

pm2 stop all 2>/dev/null || true
pm2 delete all 2>/dev/null || true

echo -e "${GREEN}✅ PM2 services stopped${NC}"

# Wait for ports to be free
echo "⏳ Waiting for ports to be released..."
sleep 5

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 2: Restart with Screen Sessions"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check old structure exists
if [ ! -d ~/infinitetrading ]; then
    echo -e "${RED}❌ ~/infinitetrading not found!${NC}"
    echo "Cannot rollback - old structure missing"
    exit 1
fi

# Start Express with screen
echo "🚀 Starting Express (screen)..."
cd ~/infinitetrading_api/express
screen -dmS api -h 1000 bash -c 'npm run start:watch'

# Start Gateway with screen
echo "🚀 Starting Gateway (screen)..."
screen -dmS gateway -h 1000 Rscript ~/infinitetrading/src/api/gateway/gateway.R

# Start Plumber with screen
echo "🚀 Starting Plumber (screen)..."
screen -dmS plumber -h 1000 Rscript ~/infinitetrading/src/api/api.R

echo "⏳ Waiting for services to start (15 seconds)..."
sleep 15

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 3: Verify Services"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

SERVICES_OK=true

# Test Express
if curl -s http://localhost:8000/ > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Express (8000) responding${NC}"
else
    echo -e "${RED}❌ Express (8000) not responding${NC}"
    SERVICES_OK=false
fi

# Test Gateway  
if curl -s http://localhost:8003/__docs__/ > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Gateway (8003) responding${NC}"
else
    echo -e "${RED}❌ Gateway (8003) not responding${NC}"
    SERVICES_OK=false
fi

# Test Plumber
if curl -s http://localhost:8002/__docs__/ > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Plumber (8002) responding${NC}"
else
    echo -e "${RED}❌ Plumber (8002) not responding${NC}"
    SERVICES_OK=false
fi

echo ""
echo "Screen sessions:"
screen -ls

if [ "$SERVICES_OK" = true ]; then
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ✅ ROLLBACK SUCCESSFUL${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Services restored to screen sessions"
    echo ""
    echo "Access screen sessions:"
    echo "  screen -r api      # Express"
    echo "  screen -r gateway  # Gateway"
    echo "  screen -r plumber  # Plumber"
else
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}  ❌ ROLLBACK FAILED${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Check screen sessions with:"
    echo "  screen -ls"
    echo "  screen -r api"
    exit 1
fi
