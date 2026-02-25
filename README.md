# Infinite Trading Cloud

Cloud-based automated cryptocurrency trading system with DeFi pool management, ML-based strategies, and multi-chain support.

## 📁 Repository Structure

This repository mirrors the production EC2 environment at `/home/ubuntu/`:

```
infinite-trading-cloud/
├── infinitetrading/         # Main trading system
│   ├── src/
│   │   ├── api/             # Plumber API (R) - Port 8002
│   │   ├── express/         # Express API (TypeScript) - Port 8000
│   │   ├── strategies/      # Trading strategy bots
│   │   ├── data-collectors/ # Market data collection
│   │   ├── tradebot/        # Core trading logic
│   │   └── ml/              # Machine learning models
│   └── ecosystem_prod.config.js
│
├── infinitetrading-sdk/     # SDK for trading system
├── infinitetrading_api/     # Additional API components
├── scripts/                 # Deployment and setup scripts
├── misc/                    # Miscellaneous files
├── *.sh                     # EC2 scripts (startup, backup, migrate)
│
├── DOCS/                    # Documentation (local only)
├── deploy.sh                # Deployment script
└── DEPLOYMENT_WORKFLOW.md   # Deployment instructions
```

## 🚀 Quick Deployment

```bash
# Make changes to files
nano infinitetrading/src/api/db.R

# Deploy to EC2
./deploy.sh "fix: connection pool exhaustion" --restart-api
```

## 📚 Documentation

See [DEPLOYMENT_WORKFLOW.md](DEPLOYMENT_WORKFLOW.md) for complete deployment instructions.

**Production EC2**: `ec2-3-135-99-211.us-east-2.compute.amazonaws.com`  
**GitHub**: https://github.com/etherpilled/infinite-trading-cloud
