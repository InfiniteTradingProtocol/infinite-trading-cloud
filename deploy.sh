#!/bin/bash

# Infinite Trading Cloud Deployment Script
# Usage: ./deploy.sh "commit message" [--restart-all|--restart-api|--restart-strategies]

set -e

EC2_HOST="ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com"
SSH_KEY="$HOME/.ssh/macbook.pem"
REMOTE_PATH="/home/ubuntu"
LOCAL_PATH="$PWD"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

if [ -z "$1" ]; then
    echo -e "${RED}Error: Commit message required${NC}"
    echo "Usage: ./deploy.sh \"commit message\" [--restart-all|--restart-api|--restart-strategies]"
    exit 1
fi

COMMIT_MSG="$1"
RESTART_MODE="${2:---restart-api}"

echo -e "${YELLOW}🚀 Starting deployment...${NC}"

# Step 1: Git operations
echo -e "${YELLOW}📝 Committing changes...${NC}"
git add -A
git commit -m "$COMMIT_MSG" || echo "No changes to commit"

echo -e "${YELLOW}⬆️  Pushing to GitHub...${NC}"
git push origin main

# Step 2: Sync files to EC2 using rsync
echo -e "${YELLOW}☁️  Syncing files to EC2...${NC}"
rsync -avz --delete \
    --exclude='node_modules' \
    --exclude='logs' \
    --exclude='.env*' \
    --exclude='*.log' \
    --exclude='build' \
    --exclude='.pm2' \
    --exclude='.cache' \
    --exclude='.git' \
    --exclude='DOCS' \
    --exclude='README.md' \
    --exclude='DEPLOYMENT_WORKFLOW.md' \
    --exclude='deploy.sh' \
    -e "ssh -i $SSH_KEY" \
    "$LOCAL_PATH/" "$EC2_HOST:$REMOTE_PATH/"

# Step 3: Install dependencies
echo -e "${YELLOW}📦 Installing dependencies...${NC}"
ssh -i "$SSH_KEY" "$EC2_HOST" << 'EOF'
    set -e
    cd /home/ubuntu/infinitetrading/src/express
    npm install --production 2>/dev/null || echo "Dependencies already installed"
EOF

# Step 3: Restart services based on mode
case "$RESTART_MODE" in
    --restart-all)
        echo -e "${YELLOW}🔄 Restarting all services...${NC}"
        ssh -i "$SSH_KEY" "$EC2_HOST" "pm2 restart all"
        ;;
    --restart-api)
        echo -e "${YELLOW}🔄 Restarting APIs...${NC}"
        ssh -i "$SSH_KEY" "$EC2_HOST" "pm2 restart plumber-api infinitetrading-api"
        ;;
    --restart-strategies)
        echo -e "${YELLOW}🔄 Restarting strategy bots...${NC}"
        ssh -i "$SSH_KEY" "$EC2_HOST" "pm2 restart strategy-aero-ema-crossover strategy-cbbtc-probability strategy-op-probability strategy-eth-ema-crossover strategy-supertrend"
        ;;
    *)
        echo -e "${RED}Invalid restart mode: $RESTART_MODE${NC}"
        exit 1
        ;;
esac

# Step 4: Verify deployment
echo -e "${YELLOW}✅ Checking PM2 status...${NC}"
ssh -i "$SSH_KEY" "$EC2_HOST" "pm2 status"

echo -e "${GREEN}✅ Deployment complete!${NC}"
echo -e "${GREEN}Repository: https://github.com/etherpilled/infinite-trading-cloud${NC}"
