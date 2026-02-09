# Development Guide

This guide covers the complete development workflow for the Infinite Trading API, from local development to EC2 production deployment.

## 📋 Table of Contents

1. [Environment Setup](#environment-setup)
2. [Local Development](#local-development)
3. [Testing](#testing)
4. [Deployment Workflow](#deployment-workflow)
5. [Troubleshooting](#troubleshooting)

## 🔧 Environment Setup

### EC2 Production Environment

The production system runs on AWS EC2 with the following specifications:

- **Host:** `ec2-3-135-99-211.us-east-2.compute.amazonaws.com`
- **Node.js:** v22.18.0
- **npm:** v10.9.3
- **Redis:** v6.0.16
- **PM2:** v6.0.14
- **TypeScript:** v4.9.5 (via package.json)
- **Process Manager:** PM2 (replaces screen sessions)

### Local Development Environment

Your local environment should match production as closely as possible.

#### Required Software

1. **Node.js v22.18.0**
   ```bash
   # Using nvm (recommended)
   nvm install 22.18.0
   nvm use 22.18.0
   
   # Verify
   node --version  # Should show v22.18.0
   ```

2. **Redis Server**
   ```bash
   # macOS
   brew install redis
   brew services start redis
   
   # Verify
   redis-cli ping  # Should return PONG
   ```

3. **PM2 (Optional for local testing)**
   ```bash
   npm install -g pm2
   ```

#### Initial Setup

1. **Clone and setup**
   ```bash
   cd /path/to/infinite-trading-api/express
   ```

2. **Create .env file**
   ```bash
   # Create .env with required variables
   cat > .env << EOF
   PRIVATE_KEY=your_private_key_here
   INFURA_PROJECT_ID=your_infura_project_id
   # Add other environment variables as needed
   EOF
   ```

3. **Run setup script**
   ```bash
   ./scripts/local-setup.sh
   ```

   This script will:
   - ✓ Verify Node.js version matches EC2
   - ✓ Check Redis installation
   - ✓ Install npm dependencies
   - ✓ Build TypeScript
   - ✓ Run type checking
   - ✓ Verify build output

## 💻 Local Development

### Development Server

Start the development server with hot reload:

```bash
cd express
npm run start:watch
```

The server will run on `http://localhost:8000`

### Test Server

For testing without affecting production data:

```bash
npx ts-node src/index_test.ts
```

The test server runs on `http://localhost:8001`

### Making Changes

1. **Edit TypeScript files** in `src/`
2. **Hot reload** automatically picks up changes (with `start:watch`)
3. **Test endpoints** using curl or Postman
4. **Check logs** in the terminal

### Project Structure

```
express/
├── src/
│   ├── requests/           # API endpoint handlers
│   │   ├── trade.ts        # Main trading endpoints
│   │   ├── admin.ts        # Admin endpoints
│   │   ├── invest.ts       # Investment operations
│   │   └── lending.ts      # Lending/borrowing
│   ├── utils/              # Utility functions
│   │   ├── pool.ts         # Pool operations
│   │   ├── ERC20.ts        # Token interactions
│   │   ├── txOptions.ts    # Transaction builders
│   │   └── redis.ts        # Redis caching
│   ├── index.ts            # Main server (port 8000)
│   ├── index_test.ts       # Test server (port 8001)
│   ├── dhedge.ts           # dHEDGE SDK setup
│   ├── wallet.ts           # Wallet management
│   └── rpc.ts              # RPC providers
├── build/                  # Compiled JavaScript (gitignored)
├── logs/                   # Application logs
├── scripts/                # Deployment scripts
│   ├── local-setup.sh      # Local environment setup
│   └── deploy-to-ec2.sh    # EC2 deployment
├── package.json
├── tsconfig.json
└── ecosystem.config.js     # PM2 configuration
```

## 🧪 Testing

### Manual Testing

1. **Start local server**
   ```bash
   npm run start:watch
   ```

2. **Test trade endpoint**
   ```bash
   curl "http://localhost:8000/trade?network=polygon&pool=0xPoolAddress&from=0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174&to=0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619&platform=uniswapv3&slippage=0.5&amount=1000000&manager=infinitetrading"
   ```

3. **Check Redis connection**
   ```bash
   redis-cli
   > keys *
   > get some_key
   ```

### Build Testing

Before deploying, always test the build:

```bash
# Clean build
rm -rf build/
npm run build

# Check for TypeScript errors
npx tsc --noEmit

# Test compiled output
node build/src/index.js
```

### Common Test Scenarios

1. **Verify asset addresses** - Full 0x addresses required
2. **Check slippage tolerance** - Reasonable values (0.1-5%)
3. **Test different networks** - polygon, optimism, arbitrum, base, ethereum
4. **Validate API responses** - Proper error handling

## 🚀 Deployment Workflow

### Overview

```
Local Development → Test Locally → Build & Verify → Deploy to EC2 → Verify Production
```

### Step-by-Step Deployment

#### 1. Pre-Deployment Checklist

- [ ] All changes tested locally
- [ ] No TypeScript errors (`npx tsc --noEmit`)
- [ ] Build succeeds (`npm run build`)
- [ ] .env file configured
- [ ] Redis running locally
- [ ] No uncommitted critical changes

#### 2. Run Local Setup

```bash
./scripts/local-setup.sh
```

Verify output shows:
- ✓ Node.js version matches EC2
- ✓ Build successful
- ✓ No TypeScript errors

#### 3. Deploy to EC2

```bash
./scripts/deploy-to-ec2.sh
```

The script will:
1. ✓ Test local build
2. ✓ Run TypeScript checks
3. ✓ Prompt for confirmation
4. ✓ Create backup on EC2
5. ✓ Sync files via rsync
6. ✓ Install dependencies on EC2
7. ✓ Build on EC2
8. ✓ Restart PM2 service
9. ✓ Verify deployment

#### 4. Post-Deployment Verification

```bash
# SSH to EC2
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# Check PM2 status
pm2 status

# View logs
pm2 logs infinitetrading-api --lines 50

# Monitor in real-time
pm2 monit
```

#### 5. Test Production Endpoints

Replace `localhost:8000` with EC2 public IP or domain to test production endpoints.

### Rollback Procedure

If deployment fails:

```bash
# SSH to EC2
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# Navigate to express directory
cd /home/ubuntu/infinitetrading_api/express

# List backups
ls -lh backups/

# Extract backup
tar -xzf backups/backup-YYYYMMDD-HHMMSS.tar.gz

# Rebuild
npm install
npm run build

# Restart
pm2 restart infinitetrading-api
```

## 🔍 Troubleshooting

### Common Issues

#### Build Failures

**Problem:** TypeScript compilation errors

**Solution:**
```bash
# Check for errors
npx tsc --noEmit

# Clean and rebuild
rm -rf build/ node_modules/
npm install
npm run build
```

#### Node Version Mismatch

**Problem:** Different Node.js version locally vs EC2

**Solution:**
```bash
# Install correct version
nvm install 22.18.0
nvm use 22.18.0

# Make it default
nvm alias default 22.18.0
```

#### Redis Connection Issues

**Problem:** Cannot connect to Redis

**Solution:**
```bash
# Check if Redis is running
redis-cli ping

# Start Redis (macOS)
brew services start redis

# Check Redis logs
brew services info redis
```

#### PM2 Service Not Starting

**Problem:** PM2 app shows "errored" status

**Solution:**
```bash
# SSH to EC2
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# Check logs for errors
pm2 logs infinitetrading-api --err

# Check if port is in use
sudo lsof -i :8000

# Restart with fresh state
pm2 delete infinitetrading-api
pm2 start ecosystem.config.js
```

#### File Sync Issues

**Problem:** rsync fails during deployment

**Solution:**
```bash
# Test SSH connection
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com "echo 'Connection OK'"

# Check file permissions
ls -la express/scripts/

# Manual sync (dry-run)
rsync -avzn --exclude 'node_modules' --exclude 'build' \
  -e "ssh -i ~/.ssh/macbook.pem" \
  ./express/ \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:/home/ubuntu/infinitetrading_api/express/
```

### Debugging Tips

1. **Check PM2 logs first**
   ```bash
   pm2 logs infinitetrading-api --lines 100
   ```

2. **Verify environment variables**
   ```bash
   # On EC2
   cd /home/ubuntu/infinitetrading_api/express
   cat .env | grep -v "PRIVATE_KEY"
   ```

3. **Test Redis connectivity**
   ```bash
   # On EC2
   redis-cli ping
   redis-cli info
   ```

4. **Check system resources**
   ```bash
   pm2 monit  # Shows CPU and memory usage
   ```

5. **Review build output**
   ```bash
   ls -lh build/src/
   cat build/src/index.js | head -20
   ```

## 📚 Additional Resources

- [Express.js Documentation](https://expressjs.com/)
- [TypeScript Handbook](https://www.typescriptlang.org/docs/)
- [PM2 Documentation](https://pm2.keymetrics.io/docs/)
- [Redis Documentation](https://redis.io/docs/)
- [dHEDGE v2 SDK](https://docs.dhedge.org/)

## 🆘 Getting Help

If you encounter issues:

1. Check this troubleshooting guide
2. Review PM2 logs on EC2
3. Verify local environment matches EC2 specs
4. Check Git commit history for recent changes
5. Test with a minimal example endpoint

---

**Last Updated:** February 2026  
**Production Node Version:** v22.18.0  
**Production PM2 Version:** v6.0.14
