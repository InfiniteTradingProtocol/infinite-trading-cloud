# Infinite Trading API - Monorepo

A comprehensive DeFi trading platform combining Express.js API (TypeScript), R-based Gateway/Plumber APIs, trading strategies, and data collectors. Enables automated trading, liquidity management, and portfolio operations across multiple blockchain networks.

## 📚 Documentation

- **[QUICKSTART.md](express/QUICKSTART.md)** - Quick reference for common commands and workflows
- **[DEVELOPMENT_GUIDE.md](express/DEVELOPMENT_GUIDE.md)** - Complete development workflow, testing, and troubleshooting
- **[DEPLOYMENT_GUIDE.md](express/DEPLOYMENT_GUIDE.md)** - PM2 configuration and production deployment details
- **[SYSTEM_ARCHITECTURE.md](SYSTEM_ARCHITECTURE.md)** - Complete system architecture, error codes, and infrastructure
- **[MIGRATION_PLAN.md](MIGRATION_PLAN.md)** - Safe migration plan to reorganize EC2 production environment

## 🏗️ Architecture Overview

```
infinitetrading_api/
├── express/                    # Express API (TypeScript, port 8000)
│   ├── src/
│   │   ├── requests/           # API endpoints
│   │   │   ├── trade.ts        # Trading operations (error codes 2000-2999)
│   │   │   ├── admin.ts        # Administrative endpoints (3000-3999)
│   │   │   ├── invest.ts       # Investment operations (4000-4999)
│   │   │   └── lending.ts      # Lending/borrowing operations (5000-5999)
│   │   ├── utils/              # Utility functions
│   │   ├── tests/              # Test files
│   │   ├── index.ts            # Main server
│   │   ├── dhedge.ts           # dHEDGE SDK initialization
│   │   ├── wallet.ts           # Wallet management
│   │   ├── rpc.ts              # RPC provider configuration
│   │   └── txFees.ts           # Gas fee calculation
│   ├── scripts/                # Deployment and testing scripts
│   │   ├── test-r-services.sh  # Test Gateway & Plumber locally
│   │   └── migrate-to-pm2.sh   # Migrate screen sessions to PM2
│   ├── logs/                   # Express logs
│   ├── package.json
│   ├── tsconfig.json
│   └── ecosystem.config.js     # PM2 config (Express + Gateway + Plumber)
├── plumber/                    # R Plumber API (port 8002)
│   ├── api.R                   # Main Plumber API
│   ├── db.R                    # Database operations
│   ├── messaging.R             # Telegram notifications
│   ├── helpers/                # Helper functions
│   │   ├── apiHelpers.R
│   │   ├── graphQL.R
│   │   └── endpoints.R
│   ├── logs/                   # Plumber logs
│   └── gateway/                # API Gateway (port 8003)
│       ├── gateway.R           # Main gateway (error codes 1000-1999)
│       ├── endpoints/          # 45+ gateway endpoints
│       └── logs/               # Gateway logs
├── strategies/                 # Trading Strategy Bots (9 bots)
│   ├── eth_ema_11_33_crossover.R
│   ├── aero_ema_11_33_crossover.R
│   ├── Velo1DBot.R
│   ├── superTrend.R
│   ├── cbBTC_probability_model.R
│   ├── OP_probability_model.R
│   ├── crossOvers.R
│   ├── infinite.sh             # Strategy runner script
│   └── logs/                   # Strategy logs
├── tradebot/                   # Core Trading Logic
│   ├── tradebot.R              # Main trading bot
│   ├── defi.R                  # DeFi integrations
│   ├── pools.R                 # Pool management
│   ├── allocations.R           # Asset allocation
│   ├── functions/              # Trading functions
│   └── logs/                   # Tradebot logs
├── data-collectors/            # Data Collection Scripts (5 collectors)
│   ├── candles.py              # Candle data (Coinbase)
│   ├── candles.sh              # Candle collector runner
│   ├── messages.py             # Message processor
│   ├── messages.sh             # Message runner
│   ├── db.py                   # Database utilities
│   └── logs/                   # Data collector logs
├── start-local.sh              # Local testing startup script
└── README.md
```

## 🚀 Quick Start

### Prerequisites

**Required:**
- Node.js v22.18.0 (to match EC2 production)
- npm v10.9.3+
- TypeScript 4.9.5
- R 4.2+ with packages: plumber, httr, jsonlite, DBI, RMySQL
- Redis 6.0+ (running locally or use EC2 DB)
- MySQL 8.0+ (running locally or use EC2 DB)

**Optional:**
- PM2 6.0.14+ (for local PM2 testing)
- SSH access to EC2 instance (for deployment)

### Local Development Workflow

**⚠️ ALWAYS test R services locally before deploying to EC2!**

The recommended workflow is: **Develop & Test Locally → Deploy to EC2**

#### 1. Test All Services Locally
```bash
cd /path/to/infinite-trading-api

# Test Gateway and Plumber first
./express/scripts/test-r-services.sh

# If tests pass, start all services
./start-local.sh
```

This will start:
- Express API on port 8000
- Plumber API on port 8002
- Gateway on port 8003

#### 2. Verify Services
```bash
# Express
curl http://localhost:8000/

# Plumber
curl http://localhost:8002/__docs__/

# Gateway
curl http://localhost:8003/__docs__/
```

#### 3. Development with Express
```bash
cd /path/to/infinite-trading-api/express

# Install dependencies
npm install

# Development mode (auto-reload)
npm run dev

# Build TypeScript
npm run build

# Run tests
npm test
```

This script will:
- Verify Node.js version matches EC2 (v22.18.0)
- Check for Redis installation and status
- Install dependencies
- Build TypeScript
- Run type checking
- Verify build output

#### 2. Local Development
```bash
# Start development server with hot reload (port 8000)
npm run start:watch

# Or run test server (port 8001)
npx ts-node src/index_test.ts
```

#### 3. Test Your Changes
- Test endpoints locally at `http://localhost:8000`
- Verify Redis connectivity
- Check logs for any errors
- Run build to ensure no TypeScript errors: `npm run build`

#### 4. Deploy to EC2 Production
```bash
# When everything works locally, deploy to EC2
./scripts/deploy-to-ec2.sh
```

The deployment script will:
- Run pre-flight checks (build, TypeScript validation)
- Create backup on EC2
- Sync source files via rsync
- Install dependencies on EC2
- Build on EC2
- Restart PM2 service
- Verify deployment status

### Manual EC2 Operations

```bash
# SSH to EC2
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# View logs
pm2 logs infinitetrading-api

# Check status
pm2 status

# Restart manually
cd /home/ubuntu/infinitetrading_api/express
pm2 restart infinitetrading-api
```

## 🌐 API Endpoints

### Base URL
- **Production:** `http://localhost:8000`
- **Test:** `http://localhost:8001`

### Trade Endpoints

#### `GET /trade`
Execute trades on various DEXs and protocols.

**Query Parameters:**
- `network` (required): Network name (polygon, optimism, arbitrum, base, ethereum)
- `pool` (required): Pool address (0x...)
- `from` (required): Source asset address (0x...)
- `to` (required): Destination asset address (0x...)
- `platform` (required): DEX/Protocol (uniswapv3, odos, toros, oneinch, 1inch)
- `slippage` (required): Slippage tolerance (e.g., 0.5 for 0.5%)
- `amount` or `share`: Trade amount in wei OR percentage share (0-100)
- `withdrawal` (optional): Boolean for Toros withdrawal completion (true/false)
- `manager` (optional): Manager name for wallet selection
- `apiKey` (optional): API key for authentication
- `provider` (optional): RPC provider (alchemy, infura, default: infura)
- `providerKey` (optional): Provider API key
- `feeAmount` (optional): UniswapV3 fee tier (500, 3000, 10000, default: 500)

**Example:**
```bash
curl "http://localhost:8000/trade?network=polygon&pool=0xPoolAddress&from=0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174&to=0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619&platform=uniswapv3&slippage=0.5&amount=1000000&manager=infinitetrading"
```

**Note:** Asset addresses are full 0x addresses:
- USDC on Polygon: `0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174`
- WETH on Polygon: `0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619`

**Response:**
```json
{
  "status": "success",
  "msg": ["0xtxhash1", "0xtxhash2"]
}
```

#### `POST /approve`
Approve tokens for trading on specified protocols.

**Query Parameters:**
- `network` (required): Network name
- `pool` (required): Pool address
- `platform` (required): Platform to approve for (uniswapv3, odos, aave, etc.)
- `manager` (optional): Manager name
- `apiKey` (optional): API key
- `provider` (optional): RPC provider
- `key` (optional): Provider key

**Body:**
```json
{
  "asset": "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174"
}
```

**Example:**
```bash
curl -X POST "http://localhost:8000/approve?network=polygon&pool=0xPoolAddress&platform=uniswapv3" \
  -H "Content-Type: application/json" \
  -d '{"asset":"0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174"}'
```

#### `GET /checkAllowance`
Check if a token is approved for a specific contract.

**Query Parameters:**
- `network` (optional): Network name (default: polygon)
- `asset` (required): Token address (0x...)
- `contract` (required): Contract address (0x...)
- `pool` (required): Pool address (0x...)
- `provider` (optional): RPC provider
- `key` (optional): Provider key

**Example:**
```bash
curl "http://localhost:8000/checkAllowance?network=polygon&asset=0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174&contract=0xDEXAddress&pool=0xPoolAddress"
```

### Admin Endpoints

#### `GET /poolComposition`
Get pool composition with asset balances.

**Query Parameters:**
- `network` (optional): Network name (default: polygon)
- `pool` (required): Pool address
- `manager` (optional): Manager name
- `apiKey` (optional): API key
- `provider` (optional): RPC provider
- `providerKey` (optional): Provider key

**Example:**
```bash
curl "http://localhost:8000/poolComposition?network=polygon&pool=0xPoolAddress"
```

**Response:**
```json
{
  "status": "success",
  "msg": [
    {
      "asset": "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
      "balance": "1000000000",
      "rate": "1000000000000000000",
      "isDeposit": true
    }
  ]
}
```

## 🔧 Configuration

### Environment Variables
Create a `.env` file in the `express/` directory:

```env
# RPC Providers
ALCHEMY_API_KEY=your_alchemy_key
INFURA_API_KEY=your_infura_key
ALCHEMY_BALANCES_KEY=your_balances_key

# Private Keys (stored securely)
INFINITETRADING_PRIVATE_KEY=0x...
MANAGER_PRIVATE_KEY=0x...

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# API
PORT=8000
```

### Network Configuration
Supported networks (defined in `dhedge.ts`):
- `polygon`: Polygon mainnet
- `optimism`: Optimism mainnet
- `arbitrum`: Arbitrum mainnet
- `base`: Base mainnet
- `ethereum`: Ethereum mainnet

### Supported Platforms
- **UniswapV3**: Advanced AMM with concentrated liquidity
- **ODOS**: DEX aggregator
- **Toros**: Yield optimization protocol
- **1Inch**: DEX aggregator
- **Aave**: Lending/borrowing protocol
- **Balancer**: Automated portfolio manager
- **Synthetix**: Synthetic assets

## 🔐 Wallet Management

### Wallet Types
1. **Standard Wallet** (`wallet.ts`): Basic ethers.js wallet
2. **V2 Wallet** (`walletv2.ts`): Enhanced with additional features

### Manager System
Managers are named wallet configurations:
- `infinitetrading`: Default production wallet
- Custom managers can be added in `wallet.ts`

## 🎯 dHEDGE v2 SDK Integration

### Key Updates (Fixed in `trade_fixed.ts`)
1. **Correct `estimateGas` Format:**
   ```typescript
   // ❌ OLD (incorrect)
   await pool.trade(dApp, assetA, assetB, amount, slippage, txOptions, true);
   
   // ✅ NEW (correct)
   await pool.trade(dApp, assetA, assetB, amount, slippage, txOptions, { estimateGas: true });
   ```

2. **Toros Withdrawal Process:**
   ```typescript
   // Step 1: Initiate withdrawal
   const tx1 = await pool.trade(Dapp.TOROS, torosToken, usdc, amount, slippage, txOptions);
   await tx1.wait();
   
   // Step 2: Complete withdrawal (if withdrawal flag is true)
   const tx2 = await pool.completeTorosWithdrawal(usdc, slippage, txOptions);
   ```

3. **Fixed `completeTorosWithdrawal` Signature:**
   ```typescript
   // ❌ OLD (incorrect)
   await pool.completeTorosWithdrawal(assetB, slippage, txOptions, false);
   
   // ✅ NEW (correct)
   await pool.completeTorosWithdrawal(assetB, slippage, txOptions, { estimateGas: false });
   ```

## 📊 Logging

### Trade Endpoint Logs
```
📌 Endpoint: /trade
🌐 Network: polygon
📊 Platform: uniswapv3
💱 Trade: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174 → 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619
💰 Amount: 1000000
📌 Pool: 0xPoolAddress
📉 Slippage: 0.5%
🔄 Withdrawal: false
🌐 Provider: infura
🗝️ API Key: Present
👤 Manager: infinitetrading
   ─────────────────────────────
```

### Pool Composition Logs
```
📌 Endpoint: /poolComposition
🌐 Network: polygon
📌 Pool Address: 0x...
🌐 Provider: alchemy
🗝️ Provider Key: ********
   ─────────────────────────────
```

## 🚨 Error Handling

### Common Issues

1. **Transaction Failed:**
   - Check gas estimation
   - Verify token approvals
   - Ensure sufficient balance

2. **Network Timeout:**
   - Switch RPC provider
   - Increase timeout in `txOptions.ts`

3. **Invalid Address:**
   - All addresses are validated before processing
   - Use checksummed addresses

## 🔄 Transaction Flow

### Standard Trade
1. Load pool using dHEDGE SDK
2. Get pool composition
3. Calculate trade amount
4. Estimate gas
5. Calculate gas fees with multiplier
6. Execute trade
7. Wait for confirmation
8. Process API payment (if applicable)
9. Return transaction hash(es)

### Toros Withdrawal
1. Execute initial trade (Step 1)
2. Wait for confirmation
3. If `withdrawal=true`, execute `completeTorosWithdrawal` (Step 2)
4. Return both transaction hashes

## 🧪 Testing

### Test Server
A separate test server runs on port 8001 with the fixed implementations:
```bash
npx ts-node src/index_test.ts
```

Test endpoints mirror production but use `trade_fixed.ts` instead of `trade.ts`.

### Manual Testing
```bash
# Test approve
curl -X POST "http://localhost:8001/approve?network=polygon&pool=0xPoolAddress&platform=uniswapv3" \
  -H "Content-Type: application/json" \
  -d '{"asset":"0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174"}'

# Test trade
curl "http://localhost:8001/trade?network=polygon&pool=0xPoolAddress&from=0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174&to=0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619&platform=odos&slippage=0.5&share=10"
```


## 📦 Deployment

### Production Process Manager (PM2)
The API runs under PM2 for production-grade process management with auto-restart, log rotation, and monitoring.

#### Start/Stop/Restart
```bash
pm2 start ecosystem.config.js    # Start the API
pm2 stop infinitetrading-api     # Stop the API
pm2 restart infinitetrading-api  # Restart the API
pm2 reload infinitetrading-api   # Zero-downtime reload
pm2 delete infinitetrading-api   # Remove from PM2
```

#### View Logs (Real-time)
```bash
pm2 logs infinitetrading-api              # Live tail (like screen -r)
pm2 logs infinitetrading-api --lines 100  # Last 100 lines + follow
pm2 logs infinitetrading-api --nostream   # Static output
```

#### Monitoring
```bash
pm2 status                        # Quick status overview
pm2 monit                        # Interactive dashboard (CPU, memory, logs)
pm2 info infinitetrading-api     # Detailed process info
```

#### System Startup
PM2 is configured to auto-start on system reboot:
```bash
pm2 startup systemd              # Configure auto-start (already done)
pm2 save                         # Save current process list
pm2 resurrect                    # Restore saved processes
```

### Legacy Screen Commands (Deprecated)
The system previously used screen. These are kept for reference:
```bash
# Old method (DO NOT USE)
screen -dmS api -h 1000 bash -c 'cd ~/infinitetrading_api/express && npm run start:watch'
screen -r api  # Attach to session
# Detach: Ctrl+A then D
```

### PM2 Configuration
Located in `ecosystem.config.js`:
- **Auto-restart:** Yes (on crash)
- **Memory limit:** 500MB (restarts if exceeded)
- **Log rotation:** 50MB max, keep 10 files
- **Error handling:** Automatic recovery
- **Startup:** Systemd integration

### Winston Log Files
Separate from PM2 logs, Winston handles application logging:
```bash
tail -f ~/infinitetrading_api/express/logs/api-*.log     # Application logs
tail -f ~/infinitetrading_api/express/logs/error-*.log   # Error logs
ls -lh ~/infinitetrading_api/express/logs/                # View all logs
```

**Log Rotation Settings:**
- Max file size: 20MB
- Retention: 14 days (info), 30 days (errors)
- Compression: gzip enabled
- Format: JSON with timestamps

## 🔍 Monitoring

### Check Running Services
```bash
pm2 status                        # PM2 managed processes
pm2 monit                         # Interactive monitoring
netstat -tulpn | grep :8000       # Port check
ps aux | grep infinitetrading     # Process check
```

### Process Health
```bash
pm2 info infinitetrading-api      # Memory, CPU, uptime, restarts
pm2 logs infinitetrading-api --lines 50  # Recent logs
```

### Redis Status
```bash
redis-cli ping
```

### Git Status
```bash
cd /home/ubuntu/infinitetrading_api
git status
git log --oneline -10
```

### System Resources
```bash
pm2 monit                         # Real-time resource usage
df -h                             # Disk space
free -h                           # Memory usage
```
## 🛠️ Development Workflow

### Local to EC2 Sync
```bash
# Download file from EC2
scp -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:/home/ubuntu/infinitetrading_api/express/src/requests/trade.ts ~/trade.ts

# Edit locally
# ...

# Upload back to EC2
scp -i ~/.ssh/macbook.pem ~/trade.ts ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:/home/ubuntu/infinitetrading_api/express/src/requests/trade.ts
```

### Git Sync
```bash
~/git-sync.sh "Your commit message"
```

### Backup Before Changes
```bash
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "cp /home/ubuntu/infinitetrading_api/express/src/requests/trade.ts \
     /home/ubuntu/infinitetrading_api/express/src/requests/trade.ts.backup"
```

## 📚 Dependencies

### Core
- `@dhedge/v2-sdk@^2.0.0`: dHEDGE protocol SDK
- `ethers@^5.7.2`: Ethereum library
- `express@^4.17.3`: Web framework
- `dotenv@^10.0.0`: Environment variables

### Database
- `redis@^5.8.2`: Caching
- `mysql@^2.18.1`: Database

### Development
- `typescript@^4.9.5`: TypeScript compiler
- `ts-node@^10.1.0`: TypeScript execution
- `nodemon@^2.0.12`: Auto-restart

## 🐛 Known Issues & Fixes

1. **Trade.ts Original Implementation:**
   - ❌ Uses boolean `true` instead of `{ estimateGas: true }`
   - ❌ Missing proper Toros withdrawal handling
   - ✅ Fixed in `trade_fixed.ts`

2. **Startup.sh:**
   - ❌ Uses `sudo` for npm (not recommended)
   - ✅ Should remove sudo for security

3. **CheckAllowance Endpoint:**
   - ❌ GET request trying to read from `req.body`
   - ✅ Should use `req.query` instead (fixed in `trade_fixed.ts`)

## 🔐 Security Notes

- Private keys stored securely (not in repo)
- API keys for RPC providers required
- Rate limiting recommended for production
- Always backup before changes
- Use test server (port 8001) for testing
- GitHub token stored separately (not in repo)

## 📞 Support & Maintenance

### Log Locations
- Application: `screen -r api`
- System: `/var/log/syslog`
- Redis: `/var/log/redis/`

### Useful Commands
```bash
# Check API health
curl http://localhost:8000/poolComposition?network=polygon&pool=0xPoolAddress

# Monitor screen session
watch -n 5 'screen -ls'

# Check git status
cd /home/ubuntu/infinitetrading_api && git status

# View recent commits
git log --oneline -10
```

## 🚀 Future Improvements

- [ ] Add rate limiting middleware
- [ ] Implement request logging to file
- [ ] Add health check endpoint
- [ ] Containerize with Docker
- [ ] Add CI/CD pipeline
- [ ] Implement comprehensive error tracking
- [ ] Add API documentation with Swagger
- [ ] Create admin dashboard
- [ ] Add websocket support for real-time updates
- [ ] Migrate all endpoints to use fixed SDK patterns

## 📄 License

Proprietary - Infinite Trading Protocol

## 👥 Contributors

- **etherpilled** - Initial work and maintenance
- Repository: https://github.com/etherpilled/infinite-trading-api

---

**Last Updated:** February 8, 2026
**Version:** 1.0.0
