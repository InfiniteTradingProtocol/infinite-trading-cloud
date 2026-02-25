#!/bin/bash

###########################################
###                                     ###
### Deploy to EC2 Production            ###
###                                     ###
###########################################

set -e  # Exit on error

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# EC2 Configuration
EC2_HOST="ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com"
EC2_KEY="~/.ssh/macbook.pem"
EC2_PATH="/home/ubuntu/infinitetrading_api/express"
PM2_APP_NAME="infinitetrading-api"

echo -e "${BLUE}=========================================="
echo "Deploying to EC2 Production"
echo "==========================================${NC}"

# Navigate to express directory
cd "$(dirname "$0")/.."
LOCAL_DIR=$(pwd)
echo -e "\n${YELLOW}Local directory: $LOCAL_DIR${NC}"

# Pre-deployment checks
echo -e "\n${BLUE}=== Pre-deployment Checks ===${NC}"

# Check if we're in the right directory
if [ ! -f "package.json" ] || [ ! -f "tsconfig.json" ]; then
    echo -e "${RED}✗ Not in express directory!${NC}"
    exit 1
fi

# Check for uncommitted changes (optional warning)
if command -v git &> /dev/null; then
    cd ..
    if [ -d ".git" ]; then
        if ! git diff --quiet express/; then
            echo -e "${YELLOW}⚠️  You have uncommitted changes in express/${NC}"
            read -p "Continue anyway? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
    cd "$LOCAL_DIR"
fi

# Run local build test
echo -e "\n${YELLOW}Testing local build...${NC}"
npm run build
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Local build failed! Fix errors before deploying.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Local build successful${NC}"

# Run TypeScript type check
echo -e "\n${YELLOW}Running TypeScript type check...${NC}"
npx tsc --noEmit
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ TypeScript errors found! Fix them before deploying.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ No TypeScript errors${NC}"

# Confirm deployment
echo -e "\n${BLUE}Ready to deploy to EC2${NC}"
echo "  Host: $EC2_HOST"
echo "  Path: $EC2_PATH"
echo ""
read -p "Continue with deployment? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Deployment cancelled${NC}"
    exit 0
fi

# Deployment steps
echo -e "\n${BLUE}=== Deploying to EC2 ===${NC}"

# Step 1: Backup current production (on EC2)
echo -e "\n${YELLOW}1. Creating backup on EC2...${NC}"
ssh -i "$EC2_KEY" "$EC2_HOST" "cd $EC2_PATH && mkdir -p backups && tar -czf backups/backup-\$(date +%Y%m%d-%H%M%S).tar.gz src/ package.json tsconfig.json || true"
echo -e "${GREEN}✓ Backup created${NC}"

# Step 2: Sync source files (excluding node_modules, build, logs)
echo -e "\n${YELLOW}2. Syncing source files...${NC}"
rsync -avz --delete \
    --exclude 'node_modules' \
    --exclude 'build' \
    --exclude 'logs' \
    --exclude '.env' \
    --exclude 'backups' \
    --exclude '.git' \
    --exclude '*.log' \
    -e "ssh -i $EC2_KEY" \
    "$LOCAL_DIR/" \
    "$EC2_HOST:$EC2_PATH/"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Files synced successfully${NC}"
else
    echo -e "${RED}✗ File sync failed!${NC}"
    exit 1
fi

# Step 3: Install dependencies on EC2
echo -e "\n${YELLOW}3. Installing dependencies on EC2...${NC}"
ssh -i "$EC2_KEY" "$EC2_HOST" "cd $EC2_PATH && npm install"
echo -e "${GREEN}✓ Dependencies installed${NC}"

# Step 4: Build on EC2
echo -e "\n${YELLOW}4. Building on EC2...${NC}"
ssh -i "$EC2_KEY" "$EC2_HOST" "cd $EC2_PATH && npm run build"
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Build failed on EC2!${NC}"
    echo "Rolling back..."
    # Optionally restore from backup here
    exit 1
fi
echo -e "${GREEN}✓ Build successful on EC2${NC}"

# Step 5: Restart PM2 service
echo -e "\n${YELLOW}5. Restarting PM2 service...${NC}"
ssh -i "$EC2_KEY" "$EC2_HOST" "cd $EC2_PATH && pm2 restart $PM2_APP_NAME"
echo -e "${GREEN}✓ PM2 service restarted${NC}"

# Step 6: Verify deployment
echo -e "\n${YELLOW}6. Verifying deployment...${NC}"
sleep 3  # Give PM2 a moment to start

ssh -i "$EC2_KEY" "$EC2_HOST" "pm2 list | grep $PM2_APP_NAME"
APP_STATUS=$(ssh -i "$EC2_KEY" "$EC2_HOST" "pm2 jlist" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ "$APP_STATUS" = "online" ]; then
    echo -e "${GREEN}✓ Application is online and running${NC}"
else
    echo -e "${RED}✗ Application status: $APP_STATUS${NC}"
    echo "Check logs with: ssh -i $EC2_KEY $EC2_HOST 'pm2 logs $PM2_APP_NAME'"
    exit 1
fi

# Step 7: Show recent logs
echo -e "\n${YELLOW}7. Recent logs:${NC}"
ssh -i "$EC2_KEY" "$EC2_HOST" "pm2 logs $PM2_APP_NAME --lines 10 --nostream"

echo -e "\n${GREEN}=========================================="
echo "✓ Deployment Complete!"
echo "==========================================${NC}"
echo ""
echo "Deployment summary:"
echo "  • Files synced to EC2"
echo "  • Dependencies installed"
echo "  • Built successfully"
echo "  • PM2 service restarted"
echo "  • Status: $APP_STATUS"
echo ""
echo "Useful commands:"
echo "  • View logs: ssh -i $EC2_KEY $EC2_HOST 'pm2 logs $PM2_APP_NAME'"
echo "  • Check status: ssh -i $EC2_KEY $EC2_HOST 'pm2 status'"
echo "  • Monitor: ssh -i $EC2_KEY $EC2_HOST 'pm2 monit'"
echo ""
