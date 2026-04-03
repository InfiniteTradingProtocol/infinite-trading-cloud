# System Architecture

## Production Environment

**EC2 Server:** `ec2-3-135-99-211.us-east-2.compute.amazonaws.com`

### Stack
- **OS:** Ubuntu
- **Node.js:** v22.18.0
- **npm:** v10.9.3
- **Redis:** v6.0.16
- **MySQL:** 8.0 (remotely accessible on port 3306)
- **PM2:** v6.0.14
- **TypeScript:** v4.9.5

### Services Running on PM2

```
infinitetrading-api      # Main Express API (port 8000)
candles-collector        # Candle data collection
cex-tradebot            # Centralized exchange trading
gas-monitor             # Gas price monitoring
pools-monitor           # Pool state monitoring
prices-monitor          # Price tracking
strategy-*              # Multiple trading strategies
tradebot                # DeFi trading bot
yields-monitor          # Yield tracking
```

## Directory Structure

```
infinite-trading-cloud/
├── infinitetrading_api/          # Main API
│   ├── express/                  # ⚠️ NOT IN GIT ON EC2!
│   │   ├── src/                  # TypeScript source
│   │   ├── build/                # Compiled JS (gitignored)
│   │   ├── logs/                 # Application logs
│   │   └── ecosystem.config.js   # PM2 config
│   └── deploy-to-ec2.sh          # Deployment script
│
├── infinitetrading/              # R-based strategies
│   ├── src/                      # R source code
│   └── defi/                     # DeFi integration (Python)
│
├── infinitetrading-sdk/          # Vault interaction SDK
│   └── index.ts                  # Main SDK
│
└── .github/                      # AI context & guides
    ├── AI_CONTEXT.md             # Main AI context
    └── guides/                   # Detailed guides
```

## Data Flow

```
User Request → Express API → dHEDGE SDK → Blockchain
                     ↓
                  Redis Cache (vault guards, quotes)
                     ↓
                  MySQL DB (logs, analytics)
```

## Network Support

- **Ethereum** - Mainnet
- **Optimism** - Layer 2
- **Base** - Coinbase L2
- **Polygon** - Sidechain
- **Arbitrum** - Layer 2

## Key Components

### API (Express/TypeScript)
- Trade execution via dHEDGE vaults
- DEX aggregation (ODOS, 1inch, Kyberswap, Uniswap)
- Gas optimization
- Slippage protection
- Guard validation (cached)

### Cache Layer (Redis)
- Vault guard whitelists (24h TTL)
- Quote caching
- Rate limit tracking
- DEX ban management

### Database (MySQL)
- Transaction logs
- Analytics
- Candle data (Coinbase pairs)
- Strategy signals

## Deployment Architecture

⚠️ **CRITICAL:** EC2's `express/` directory is NOT git-tracked!

```
Local Development
    ↓
rsync sync → EC2
    ↓
npm run build on EC2
    ↓
pm2 restart
    ↓
Production Live
```

**Never use `git pull` on EC2 for the express directory!**
