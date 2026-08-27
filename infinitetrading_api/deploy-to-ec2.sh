#!/bin/bash

# Deployment script for infinite-trading-cloud to EC2
# This script ensures consistent deployments and prevents common issues

set -e  # Exit on any error

# Configuration
EC2_HOST="ec2-3-135-99-211.us-east-2.compute.amazonaws.com"
EC2_USER="ubuntu"
PEM_KEY="$HOME/.ssh/macmini.pem"
REMOTE_DIR="infinitetrading_api/express"
PM2_APP="infinitetrading-api"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Infinite Trading API Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Step 1: Verify local environment
echo -e "${YELLOW}[1/8] Verifying local environment...${NC}"
if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ Node.js not found. Please install Node.js v22.18.0${NC}"
    exit 1
fi

NODE_VERSION=$(node --version)
if [[ ! "$NODE_VERSION" =~ ^v22\. ]]; then
    echo -e "${YELLOW}⚠️  Warning: Node.js version is $NODE_VERSION (expected v22.x)${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi
echo -e "${GREEN}✓ Node.js version: $NODE_VERSION${NC}"

# Step 2: Check if we're in the right directory
echo -e "${YELLOW}[2/8] Checking directory...${NC}"
if [ ! -f "package.json" ]; then
    echo -e "${RED}❌ package.json not found. Please run from infinitetrading_api/express directory${NC}"
    exit 1
fi
echo -e "${GREEN}✓ In correct directory${NC}"

# Step 3: Run TypeScript checks
echo -e "${YELLOW}[3/8] Running TypeScript checks...${NC}"
if ! npx tsc --noEmit; then
    echo -e "${RED}❌ TypeScript errors found. Please fix before deploying.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ No TypeScript errors${NC}"

# Step 4: Test local build
echo -e "${YELLOW}[4/8] Testing local build...${NC}"
if ! npm run build; then
    echo -e "${RED}❌ Build failed. Please fix errors before deploying.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Local build successful${NC}"

# Step 5: Confirm deployment
echo ""
echo -e "${YELLOW}Ready to deploy to EC2:${NC}"
echo "  Host: $EC2_HOST"
echo "  Target: $REMOTE_DIR"
echo "  PM2 App: $PM2_APP"
echo ""
read -p "Deploy to production? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Deployment cancelled${NC}"
    exit 0
fi

# Step 6: Sync files to EC2
echo -e "${YELLOW}[5/8] Syncing files to EC2...${NC}"
echo "  Syncing src/ directory..."
rsync -avz --delete \
    -e "ssh -i $PEM_KEY" \
    src/ \
    ${EC2_USER}@${EC2_HOST}:${REMOTE_DIR}/src/

echo "  Syncing package.json and tsconfig.json..."
rsync -avz \
    -e "ssh -i $PEM_KEY" \
    package.json tsconfig.json \
    ${EC2_USER}@${EC2_HOST}:${REMOTE_DIR}/

echo -e "${GREEN}✓ Files synced${NC}"

# Step 7: Build and restart on EC2
echo -e "${YELLOW}[6/8] Building on EC2...${NC}"
ssh -i "$PEM_KEY" ${EC2_USER}@${EC2_HOST} << 'ENDSSH'
set -e
cd infinitetrading_api/express

echo "Installing dependencies..."
npm install --production=false

echo "Building TypeScript..."
npm run build

echo "Checking build output..."
if [ ! -d "build/src" ]; then
    echo "ERROR: Build directory not created"
    exit 1
fi

echo "Build successful!"
ENDSSH

echo -e "${GREEN}✓ EC2 build complete${NC}"

# Step 8: Restart PM2
echo -e "${YELLOW}[7/8] Restarting PM2 service...${NC}"
ssh -i "$PEM_KEY" ${EC2_USER}@${EC2_HOST} << ENDSSH
pm2 restart ${PM2_APP}
echo "Waiting for service to stabilize..."
sleep 3
pm2 status ${PM2_APP}
ENDSSH

echo -e "${GREEN}✓ PM2 restarted${NC}"

# Step 9: Verify deployment
echo -e "${YELLOW}[8/8] Verifying deployment...${NC}"
echo "Recent logs:"
ssh -i "$PEM_KEY" ${EC2_USER}@${EC2_HOST} "pm2 logs ${PM2_APP} --lines 20 --nostream" | tail -20

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✓ Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Monitor logs with:"
echo "  ssh -i $PEM_KEY ${EC2_USER}@${EC2_HOST} 'pm2 logs ${PM2_APP}'"
echo ""
echo "Check status with:"
echo "  ssh -i $PEM_KEY ${EC2_USER}@${EC2_HOST} 'pm2 status'"
echo ""
