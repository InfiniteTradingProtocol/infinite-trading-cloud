# Infinite Trading API

A comprehensive Express.js API for DeFi trading operations, built with TypeScript and integrated with the dHEDGE v2 SDK. This API enables automated trading, liquidity management, and portfolio operations across multiple blockchain networks.

## 🏗️ Architecture Overview

```
infinitetrading_api/
├── express/
│   ├── src/
│   │   ├── requests/           # API endpoints
│   │   │   ├── trade.ts        # Trading operations (production)
│   │   │   ├── trade_fixed.ts  # Fixed version with dHEDGE v2 SDK updates
│   │   │   ├── trade_new.ts    # Alternative implementation
│   │   │   ├── admin.ts        # Administrative endpoints
│   │   │   ├── invest.ts       # Investment operations
│   │   │   └── lending.ts      # Lending/borrowing operations
│   │   ├── utils/              # Utility functions
│   │   │   ├── pool.ts         # Pool composition utilities
│   │   │   ├── txOptions.ts    # Transaction option builders
│   │   │   ├── ERC20.ts        # ERC20 token interactions
│   │   │   └── redis.ts        # Redis caching
│   │   ├── tests/              # Test files
│   │   ├── index.ts            # Main server (port 8000)
│   │   ├── index_test.ts       # Test server (port 8001)
│   │   ├── dhedge.ts           # dHEDGE SDK initialization
│   │   ├── wallet.ts           # Wallet management
│   │   ├── walletv2.ts         # Updated wallet management
│   │   ├── rpc.ts              # RPC provider configuration
│   │   └── txFees.ts           # Gas fee calculation
│   ├── package.json
│   └── tsconfig.json
└── startup.sh                  # System startup script
```

## 🚀 Quick Start

### Prerequisites
- Node.js v18+
- TypeScript 4.9+
- Redis server
- Screen (for process management)
- SSH access to EC2 instance

### Installation
```bash
cd /home/ubuntu/infinitetrading_api/express
npm install
```

### Build
```bash
npm run build
```

### Run Production Server
```bash
npm run start:watch  # Development with hot reload (port 8000)
npm run start        # Production (port 8000)
```

### Run Test Server
```bash
npx ts-node src/index_test.ts  # Test server (port 8001)
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

### Production Startup
The system uses `startup.sh` for initialization:
```bash
screen -dmS api -h 1000 bash -c 'cd ~/infinitetrading_api/express && npm run start:watch'
```

### View Logs
```bash
screen -r api
```
Detach: `Ctrl+A` then `D`

### Restart Service
```bash
screen -S api -X quit
cd ~/infinitetrading_api/express && npm run build
screen -dmS api -h 1000 bash -c 'cd ~/infinitetrading_api/express && npm run start:watch'
```

## 🔍 Monitoring

### Check Running Services
```bash
screen -ls
netstat -tulpn | grep :8000
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
