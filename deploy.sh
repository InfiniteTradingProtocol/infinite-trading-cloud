#!/bin/bash

# Infinite Trading Cloud Deployment Script
# Usage: ./deploy.sh [--restart-all|--restart-api|--restart-strategies|--restart-gateway|--skip-push]

set -euo pipefail

EC2_HOST="ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com"
SSH_KEY="$HOME/.ssh/macmini.pem"
REMOTE_PATH="/home/ubuntu"
LOCAL_PATH="$PWD"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

RESTART_MODE="--restart-api"
PUSH_CHANGES=true

for arg in "$@"; do
    case "$arg" in
        --restart-all|--restart-api|--restart-strategies|--restart-gateway)
            RESTART_MODE="$arg"
            ;;
        --skip-push)
            PUSH_CHANGES=false
            ;;
        *)
            echo -e "${RED}Invalid argument: $arg${NC}"
            echo "Usage: ./deploy.sh [--restart-all|--restart-api|--restart-strategies|--restart-gateway|--skip-push]"
            exit 1
            ;;
    esac
done

echo -e "${YELLOW}🚀 Starting deployment...${NC}"

# Step 1: Git checks and optional push
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${RED}Working tree has uncommitted changes. Commit them before deploying.${NC}"
    git status --short
    exit 1
fi

if [ "$PUSH_CHANGES" = true ]; then
    CURRENT_BRANCH="$(git branch --show-current)"
    if [ -z "$CURRENT_BRANCH" ]; then
        echo -e "${RED}Unable to determine current branch.${NC}"
        exit 1
    fi

    if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        UPSTREAM_REMOTE="$(git config "branch.${CURRENT_BRANCH}.remote")"
        echo -e "${YELLOW}⬆️  Pushing ${CURRENT_BRANCH} to ${UPSTREAM_REMOTE}...${NC}"
        git push
    else
        echo -e "${YELLOW}⬆️  Publishing ${CURRENT_BRANCH} to origin...${NC}"
        git push -u origin HEAD
    fi
fi

# Step 2: Sync application files to EC2 using rsync
echo -e "${YELLOW}☁️  Syncing files to EC2...${NC}"
rsync -avz \
    --exclude='node_modules' \
    --exclude='logs' \
    --exclude='.env*' \
    --exclude='*.log' \
    --exclude='build' \
    --exclude='backups' \
    --exclude='.pm2' \
    --exclude='.cache' \
    --exclude='.git' \
    -e "ssh -i $SSH_KEY" \
    "$LOCAL_PATH/infinitetrading/" "$EC2_HOST:$REMOTE_PATH/infinitetrading/"

rsync -avz \
    --exclude='node_modules' \
    --exclude='logs' \
    --exclude='.env*' \
    --exclude='*.log' \
    --exclude='build' \
    --exclude='backups' \
    --exclude='.git' \
    -e "ssh -i $SSH_KEY" \
    "$LOCAL_PATH/infinitetrading_api/" "$EC2_HOST:$REMOTE_PATH/infinitetrading_api/"

# Step 3: Build TypeScript and install dependencies
echo -e "${YELLOW}📦 Building API...${NC}"
ssh -i "$SSH_KEY" "$EC2_HOST" << 'EOF'
    set -e
    cd /home/ubuntu/infinitetrading_api/express
    npm install --production 2>/dev/null || true
    npm run build
EOF

# Step 4: Restart services based on mode
case "$RESTART_MODE" in
    --restart-all)
        echo -e "${YELLOW}🔄 Restarting all services...${NC}"
        ssh -i "$SSH_KEY" "$EC2_HOST" "pm2 restart all"
        ;;
    --restart-api)
        echo -e "${YELLOW}🔄 Restarting APIs...${NC}"
        ssh -i "$SSH_KEY" "$EC2_HOST" "pm2 restart plumber-api infinitetrading-api api-gateway"
        ;;
    --restart-gateway)
        echo -e "${YELLOW}🔄 Restarting API gateway...${NC}"
        ssh -i "$SSH_KEY" "$EC2_HOST" "pm2 restart api-gateway"
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

# Step 5: Regenerate nginx endpoint allowlist from endpoints.R (source of truth,
# includes hidden_endpoints too) and reload — this keeps nginx's public
# endpoint list automatically in sync with whatever R actually mounts,
# instead of relying on a manually-committed static itp_endpoints.conf that
# can silently drift out of date as endpoints are added/removed in R.
echo -e "${YELLOW}🔒 Regenerating nginx endpoint allowlist from endpoints.R...${NC}"
ssh -i "$SSH_KEY" "$EC2_HOST" "bash /home/ubuntu/infinitetrading/src/api/gateway/deploy.sh"

# Step 6: Verify deployment
echo -e "${YELLOW}✅ Checking PM2 status...${NC}"
ssh -i "$SSH_KEY" "$EC2_HOST" "pm2 status"

echo -e "${GREEN}✅ Deployment complete!${NC}"
echo -e "${GREEN}Repository: https://github.com/etherpilled/infinite-trading-cloud${NC}"
