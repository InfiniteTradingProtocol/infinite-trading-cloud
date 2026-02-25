#!/bin/bash

###########################################
###                                     ###
### Local Development Environment Setup ###
### Replicates EC2 Production           ###
###                                     ###
###########################################

set -e  # Exit on error

echo "=========================================="
echo "Setting up local development environment"
echo "to match EC2 production"
echo "=========================================="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# EC2 Production Environment Specs
REQUIRED_NODE_VERSION="22.18.0"
REQUIRED_NPM_VERSION="10.9.3"
REQUIRED_REDIS_VERSION="6.0"
REQUIRED_PM2_VERSION="6.0.14"

# Check Node.js version
echo -e "\n${YELLOW}Checking Node.js version...${NC}"
CURRENT_NODE_VERSION=$(node --version | sed 's/v//')
if [ "$CURRENT_NODE_VERSION" != "$REQUIRED_NODE_VERSION" ]; then
    echo -e "${RED}⚠️  Node.js version mismatch!${NC}"
    echo "   Current: $CURRENT_NODE_VERSION"
    echo "   Required (EC2): $REQUIRED_NODE_VERSION"
    echo ""
    echo "Please install Node.js v$REQUIRED_NODE_VERSION"
    echo "You can use nvm: nvm install $REQUIRED_NODE_VERSION && nvm use $REQUIRED_NODE_VERSION"
    exit 1
else
    echo -e "${GREEN}✓ Node.js version matches EC2: v$CURRENT_NODE_VERSION${NC}"
fi

# Check npm version
echo -e "\n${YELLOW}Checking npm version...${NC}"
CURRENT_NPM_VERSION=$(npm --version)
NPM_MAJOR=$(echo $CURRENT_NPM_VERSION | cut -d. -f1)
REQUIRED_NPM_MAJOR=$(echo $REQUIRED_NPM_VERSION | cut -d. -f1)
if [ "$NPM_MAJOR" != "$REQUIRED_NPM_MAJOR" ]; then
    echo -e "${YELLOW}⚠️  npm version mismatch (non-critical)${NC}"
    echo "   Current: $CURRENT_NPM_VERSION"
    echo "   EC2: $REQUIRED_NPM_VERSION"
else
    echo -e "${GREEN}✓ npm version compatible: $CURRENT_NPM_VERSION${NC}"
fi

# Check Redis
echo -e "\n${YELLOW}Checking Redis...${NC}"
if command -v redis-cli &> /dev/null; then
    REDIS_VERSION=$(redis-cli --version | awk '{print $2}')
    echo -e "${GREEN}✓ Redis installed: $REDIS_VERSION${NC}"
    
    # Check if Redis is running
    if redis-cli ping &> /dev/null; then
        echo -e "${GREEN}✓ Redis server is running${NC}"
    else
        echo -e "${YELLOW}⚠️  Redis is installed but not running${NC}"
        echo "   Start Redis with: brew services start redis (macOS)"
    fi
else
    echo -e "${RED}⚠️  Redis not found${NC}"
    echo "   Install with: brew install redis (macOS)"
    echo "   EC2 uses Redis $REQUIRED_REDIS_VERSION"
fi

# Check PM2
echo -e "\n${YELLOW}Checking PM2...${NC}"
if command -v pm2 &> /dev/null; then
    PM2_VERSION=$(pm2 --version)
    echo -e "${GREEN}✓ PM2 installed: $PM2_VERSION${NC}"
else
    echo -e "${YELLOW}⚠️  PM2 not found (optional for local dev)${NC}"
    echo "   Install with: npm install -g pm2"
    echo "   EC2 uses PM2 $REQUIRED_PM2_VERSION"
fi

# Navigate to express directory
cd "$(dirname "$0")/.."
EXPRESS_DIR=$(pwd)
echo -e "\n${YELLOW}Working directory: $EXPRESS_DIR${NC}"

# Check if .env exists
echo -e "\n${YELLOW}Checking .env file...${NC}"
if [ ! -f ".env" ]; then
    echo -e "${RED}⚠️  .env file not found!${NC}"
    echo "   Create .env file with required variables:"
    echo "   - PRIVATE_KEY"
    echo "   - INFURA_PROJECT_ID"
    echo "   (and any other EC2 environment variables)"
    exit 1
else
    echo -e "${GREEN}✓ .env file exists${NC}"
fi

# Install dependencies
echo -e "\n${YELLOW}Installing dependencies...${NC}"
npm install

# Build TypeScript
echo -e "\n${YELLOW}Building TypeScript...${NC}"
npm run build

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Build successful!${NC}"
else
    echo -e "${RED}✗ Build failed!${NC}"
    exit 1
fi

# Verify build output
echo -e "\n${YELLOW}Verifying build output...${NC}"
if [ -d "build/src" ] && [ -f "build/src/index.js" ]; then
    echo -e "${GREEN}✓ Build output verified${NC}"
    echo "   Main file: build/src/index.js"
else
    echo -e "${RED}✗ Build output incomplete${NC}"
    exit 1
fi

# Run TypeScript check
echo -e "\n${YELLOW}Running TypeScript type check...${NC}"
npx tsc --noEmit
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ No TypeScript errors${NC}"
else
    echo -e "${RED}✗ TypeScript errors found${NC}"
    echo "   Fix errors before deploying to EC2"
    exit 1
fi

echo -e "\n${GREEN}=========================================="
echo "✓ Local environment setup complete!"
echo "==========================================${NC}"
echo ""
echo "Your local environment matches EC2 production:"
echo "  • Node.js v$CURRENT_NODE_VERSION"
echo "  • npm v$CURRENT_NPM_VERSION"
echo "  • TypeScript compiled successfully"
echo "  • Build output verified"
echo ""
echo "Next steps:"
echo "  1. Test locally: npm run start:watch"
echo "  2. When ready, deploy: ./scripts/deploy-to-ec2.sh"
echo ""
