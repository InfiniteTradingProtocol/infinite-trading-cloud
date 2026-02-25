# Infinite Trading Cloud

Cloud-based automated cryptocurrency trading system with DeFi pool management, ML-based strategies, and multi-chain support.

## 📁 Repository Structure

This repository mirrors the production EC2 environment at `/home/ubuntu/`:

```
infinite-trading-cloud/
├── ubuntu/
│   └── infinitetrading/         # Main trading system
│       ├── src/
│       │   ├── api/             # Plumber API (R) - Port 8002
│       │   │   ├── api.R        # Main API endpoints
│       │   │   ├── db.R         # Database operations
│       │   │   ├── db_pool.R    # Connection pooling
│       │   │   ├── executeTrades.R
│       │   │   ├── gasMonitor.R
│       │   │   └── getGasBalances.R
│       │   │
│       │   ├── express/         # Express API (TypeScript) - Port 8000
│       │   │   ├── src/
│       │   │   │   ├── routes/
│       │   │   │   │   └── trade.ts    # Trade execution endpoint
│       │   │   │   └── index.ts
│       │   │   ├── package.json
│       │   │   └── tsconfig.json
│       │   │
│       │   ├── strategies/      # Trading strategy bots
│       │   │   ├── aero_ema_11_33_crossover.R
│       │   │   ├── cbBTC_probability_model.R
│       │   │   ├── op_probability_model.R
│       │   │   └── ...
│       │   │
│       │   ├── data-collectors/ # Market data collection
│       │   ├── tradebot/        # Core trading logic
│       │   ├── ml/              # Machine learning models
│       │   └── scripts/         # Utility scripts
│       │
│       ├── ecosystem_prod.config.js  # PM2 configuration
│       └── .env.production      # Environment variables (not in repo)
│
└── DOCS/                        # Documentation
    ├── DEPLOYMENT_GUIDE.md
    ├── SYSTEM_ARCHITECTURE.md
    ├── QUICK_START.md
    └── ...
```

## 🚀 Quick Start

### Prerequisites

- **EC2 Instance**: Ubuntu 20.04+ with 8GB+ RAM
- **Database**: MySQL 8.0+ (RDS recommended)
- **Runtime**: Node.js 18+, R 4.0+
- **Process Manager**: PM2

### Local Development Setup

1. **Clone repository:**
```bash
git clone https://github.com/etherpilled/infinite-trading-cloud.git
cd infinite-trading-cloud
```

2. **Install dependencies:**
```bash
# Express API
cd ubuntu/infinitetrading/src/express
npm install

# R packages (if developing R code)
Rscript ubuntu/infinitetrading/install-packages.R
```

3. **Configure environment:**
```bash
# Copy example env file
cp ubuntu/infinitetrading/.env.example ubuntu/infinitetrading/.env.production

# Edit with your credentials
nano ubuntu/infinitetrading/.env.production
```

### Deploy to EC2

**Option 1: Git-based deployment (Recommended)**

```bash
# On EC2
cd /home/ubuntu/infinitetrading
git pull origin main
pm2 restart all
```

**Option 2: Direct file sync**

```bash
# From local machine
rsync -avz --exclude 'node_modules' --exclude 'logs' \
  ubuntu/infinitetrading/ \
  ubuntu@YOUR-EC2-IP:/home/ubuntu/infinitetrading/
```

## 🏗️ System Architecture

### APIs

**Plumber API (R)** - Port 8002
- Database operations (connection pooling)
- Trade execution coordination
- Gas balance monitoring
- Pool composition management

**Express API (TypeScript)** - Port 8000
- DeFi trade execution
- Blockchain interactions
- Slippage management

### Strategy Bots (PM2 Processes)

| Bot Name | Asset | Strategy | Network |
|----------|-------|----------|---------|
| `strategy-aero-ema-crossover` | AERO | EMA 11/33 | Base |
| `strategy-cbbtc-probability` | cbBTC | ML Probability | Base |
| `strategy-op-probability` | OP | ML Probability | Optimism |
| `strategy-eth-ema-crossover` | ETH | EMA Crossover | Polygon |
| `strategy-supertrend` | Multi | SuperTrend | Multi-chain |

### Data Collectors

- **candles-collector**: OHLCV data from exchanges
- **prices-monitor**: Real-time price tracking
- **pools-monitor**: DeFi pool composition
- **yields-monitor**: APY tracking
- **gas-monitor**: Gas wallet balances

## 🔧 Configuration

### Database Connection Pool

File: `ubuntu/infinitetrading/src/api/db_pool.R`

```r
db_pool <- pool::dbPool(
  drv = RMariaDB::MariaDB(),
  host = Sys.getenv("db_ip"),
  minSize = 3,
  maxSize = 15,  # RDS max_connections = 30
  idleTimeout = 300
)
```

### PM2 Ecosystem

File: `ubuntu/infinitetrading/ecosystem_prod.config.js`

```javascript
module.exports = {
  apps: [
    {
      name: 'plumber-api',
      script: 'Rscript',
      args: 'src/api/api.R',
      cwd: '/home/ubuntu/infinitetrading',
      instances: 1,
      autorestart: true
    },
    // ... strategy bots ...
  ]
}
```

## 📝 Development Workflow

### Making Changes

1. **Edit locally** in `ubuntu/infinitetrading/` directory
2. **Test changes** (use local R/Node environment)
3. **Commit to git:**
   ```bash
   git add ubuntu/infinitetrading/src/api/db.R
   git commit -m "fix: resolve connection pool exhaustion"
   git push origin main
   ```

4. **Deploy to EC2:**
   ```bash
   ssh ubuntu@YOUR-EC2-IP
   cd /home/ubuntu/infinitetrading
   git pull origin main
   pm2 restart plumber-api  # or restart specific service
   ```

### Quick Deployment Script

Create `deploy.sh`:

```bash
#!/bin/bash
git add .
git commit -m "$1"
git push origin main

ssh -i ~/.ssh/macbook.pem ubuntu@YOUR-EC2-IP << 'EOF'
  cd /home/ubuntu/infinitetrading
  git pull origin main
  pm2 restart all
EOF
```

Usage: `./deploy.sh "fix: update trade logic"`

## 🗃️ Database Schema

**Primary Database**: `infinitetrading` (RDS MySQL)

Key Tables:
- `dhedge_pools` - Pool configurations
- `dhedge_sides` - Trading positions
- `associated_gas_wallets` - Gas wallet management
- `polygon_dhedge_gas_wallets` - Network-specific wallets
- `candles_*` - OHLCV data per asset
- `messages` - Slack/Discord notifications

## 🔐 Environment Variables

Required in `ubuntu/infinitetrading/.env.production`:

```bash
# Database
db_ip=your-rds-endpoint.rds.amazonaws.com
db_port=3306
db_user=admin
db_password=your-password
db_schema=infinitetrading

# Blockchain RPC
ALCHEMY_BALANCES_APIKEY=your-alchemy-key
BASE_RPC_URL=https://base-mainnet.g.alchemy.com/v2/...
POLYGON_RPC_URL=https://polygon-mainnet.g.alchemy.com/v2/...
OPTIMISM_RPC_URL=https://opt-mainnet.g.alchemy.com/v2/...

# API Keys
COINBASE_API_KEY=your-api-key
COINBASE_SECRET=your-secret
```

## 📊 Monitoring

### Check System Status

```bash
# PM2 processes
pm2 status

# API logs
pm2 logs plumber-api --lines 50
pm2 logs infinitetrading-api --lines 50

# Strategy logs
pm2 logs strategy-aero-ema-crossover --lines 30

# Database connections
pm2 logs plumber-api | grep "pool"
```

### Common Issues

**Connection Pool Exhaustion:**
- **Symptom**: "Maximum number of objects in pool has been reached"
- **Solution**: Restart plumber-api: `pm2 restart plumber-api`
- **Prevention**: Use `db_con(use_pool=TRUE)` in all db.R functions

**Gas Balance Errors:**
- **Check**: `pm2 logs gas-monitor`
- **Solution**: Verify Alchemy API key and RPC endpoints

## 🧪 Testing

### Test APIs

```bash
# Plumber API health check
curl http://localhost:8002/health

# Express API trade endpoint
curl -X POST http://localhost:8000/trade \
  -H "Content-Type: application/json" \
  -d '{"from":"0x...", "to":"0x...", "slippage":1}'

# Set trading side
curl -X POST http://localhost:8002/setSide \
  -d "pool=0x4ce9628fae744c86b3e5435d6777aa4ff2cd15b6&side=long"
```

### Test Database Connection

```bash
cd /home/ubuntu/infinitetrading
Rscript -e "source('src/api/db.R'); print(db_con())"
```

## 📚 Documentation

See `DOCS/` folder for detailed guides:

- **[DEPLOYMENT_GUIDE.md](DOCS/DEPLOYMENT_GUIDE.md)** - Full deployment instructions
- **[SYSTEM_ARCHITECTURE.md](DOCS/SYSTEM_ARCHITECTURE.md)** - System design overview
- **[QUICK_START.md](DOCS/QUICK_START.md)** - Getting started guide
- **[RDS_MIGRATION_GUIDE.md](DOCS/RDS_MIGRATION_GUIDE.md)** - Database setup

## 🤝 Contributing

1. Create feature branch: `git checkout -b feature/new-strategy`
2. Make changes in `ubuntu/infinitetrading/`
3. Test on local/staging environment
4. Commit and push: `git push origin feature/new-strategy`
5. Deploy to EC2 after merge

## 📄 License

Proprietary - All Rights Reserved

## 🆘 Support

For issues, check:
1. PM2 logs: `pm2 logs <process-name>`
2. System logs: `ubuntu/infinitetrading/src/logs/`
3. Database status: Check RDS CloudWatch metrics

---

**Production EC2**: `ec2-3-135-99-211.us-east-2.compute.amazonaws.com`  
**Last Updated**: February 25, 2026
