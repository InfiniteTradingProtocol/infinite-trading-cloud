# Quick Reference - Development & Deployment

## 🎯 TL;DR

```bash
# 1. Setup local environment (first time only)
cd express
./scripts/local-setup.sh

# 2. Develop locally
npm run start:watch

# 3. Deploy to EC2 when ready
./scripts/deploy-to-ec2.sh
```

## 📦 Environment Requirements

| Component | Version | Notes |
|-----------|---------|-------|
| Node.js | v22.18.0 | **Must match EC2** |
| npm | v10.9.3+ | Any 10.x should work |
| Redis | v6.0+ | Must be running locally |
| TypeScript | v4.9.5 | Via package.json |
| PM2 | v6.0.14+ | Optional for local dev |

## 🚀 Common Commands

### Local Development
```bash
npm run start:watch       # Dev server with hot reload (port 8000)
npx ts-node src/index_test.ts  # Test server (port 8001)
npm run build             # Build TypeScript
npx tsc --noEmit          # Type check only
```

### EC2 Operations
```bash
# SSH to EC2
ssh -i ~/.ssh/macmini.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# PM2 commands (on EC2)
pm2 status                        # Check status
pm2 logs infinitetrading-api      # View logs
pm2 restart infinitetrading-api   # Restart service
pm2 monit                         # Real-time monitoring
```

### Testing API Endpoints
```bash
# Pool composition
curl "http://localhost:8000/poolComposition?network=optimism&pool=0x86729853f9cca4c1ec0c160792f36e1bf97d58c3&provider=alchemy"

# Trade (UniswapV3)
curl "http://localhost:8000/trade?network=polygon&pool=POOL_ADDRESS&from=TOKEN_A&to=TOKEN_B&platform=uniswapv3&fee=500&slippage=1&amount=1000000&manager=infinitetrading"

# Trade (Toros - Bull/Bear tokens)
curl "http://localhost:8000/trade?network=optimism&pool=POOL_ADDRESS&from=USDC_ADDRESS&to=TOROS_TOKEN&platform=toros&slippage=1&amount=1000000&manager=infinitetrading"

# Toros withdrawal (2-step process)
curl "http://localhost:8000/trade?network=optimism&pool=POOL_ADDRESS&from=TOROS_TOKEN&to=USDC_ADDRESS&platform=toros&slippage=1&amount=1000000&withdrawal=true&manager=infinitetrading"
```

### Deployment
```bash
./scripts/local-setup.sh      # Verify local environment
./scripts/deploy-to-ec2.sh    # Deploy to production
```

## 🔧 Quick Fixes

### Node Version Mismatch
```bash
nvm install 22.18.0
nvm use 22.18.0
nvm alias default 22.18.0
```

### Redis Not Running
```bash
brew services start redis
redis-cli ping  # Should return PONG
```

### Build Errors
```bash
rm -rf build/ node_modules/
npm install
npm run build
```

### EC2 Service Down
```bash
ssh -i ~/.ssh/macmini.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
cd /home/ubuntu/infinitetrading_api/express
pm2 logs infinitetrading-api --err
pm2 restart infinitetrading-api
```

## 📝 Workflow Checklist

- [ ] Local environment matches EC2 (run `./scripts/local-setup.sh`)
- [ ] Changes tested locally
- [ ] Build succeeds locally (`npm run build`)
- [ ] No TypeScript errors (`npx tsc --noEmit`)
- [ ] Deploy to EC2 (`./scripts/deploy-to-ec2.sh`)
- [ ] Verify on EC2 (`pm2 status`)

## 🌐 API Endpoints

**Base URLs:**
- Local: `http://localhost:8000`
- Test: `http://localhost:8001`
- Production: EC2 instance

**Example Trade:**
```bash
curl "http://localhost:8000/trade?network=polygon&pool=0x...&from=0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174&to=0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619&platform=uniswapv3&slippage=0.5&amount=1000000&manager=infinitetrading"
```

## 📚 Documentation

- Full workflow: [DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md)
- Deployment details: [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
- API endpoints: [README.md](../README.md)

## 🔗 EC2 Details

- **Host:** `ec2-3-135-99-211.us-east-2.compute.amazonaws.com`
- **User:** `ubuntu`
- **SSH Key:** `~/.ssh/macmini.pem`
- **Path:** `/home/ubuntu/infinitetrading_api/express`
- **PM2 App:** `infinitetrading-api`
- **Port:** 8000
