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
├── backtests/               # All strategy backtesting code, charts & results
│                            # (see backtests/README.md and backtests/BACKTESTING.md)
├── scripts/                 # Deployment/setup scripts (root), plus:
│   ├── ops/                 #   one-off ops utilities (log cleanup, key rotation, etc.)
│   └── tests/               #   ad-hoc endpoint/logic test scripts (aave, cex, liquidity...)
├── docs/                    # Standalone strategy/feature docs (vault deployment,
│                            # EMA+RSI analysis, adaptive quant, bot linking notes)
├── misc/                    # Miscellaneous files
├── *.sh                     # EC2 scripts (startup, deploy — kept at root, see below)
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

### AI-Optimized Docs (Recommended)
- **Start Here:** `.github/AI_CONTEXT.md` - Overview and critical warnings
- **Quick Tasks:** `.github/COMMON_TASKS.md` - Common operations
- **Architecture:** `.github/ARCHITECTURE.md` - System design
- **API Development:** `.github/guides/API_DEVELOPMENT.md`
- **Deployment:** `infinitetrading_api/DEPLOY.md` or `.github/guides/DEPLOYMENT.md`
- **Troubleshooting:** `.github/guides/TROUBLESHOOTING.md`

### Legacy Documentation
See [DEPLOYMENT_WORKFLOW.md](DEPLOYMENT_WORKFLOW.md) for complete deployment instructions.
See `DOCS/` for historical documentation and migration guides.
See [docs/](docs/) for standalone strategy/feature docs (vault deployment automation,
EMA+RSI analysis, adaptive quant strategy, bot-linking simplification).
See [backtests/README.md](backtests/README.md) for the backtesting framework overview,
including the reorganized `backtests/legacy/` folder for older ad-hoc backtest scripts
that used to live at the repo root.

**Production EC2**: `ec2-3-135-99-211.us-east-2.compute.amazonaws.com`  
**GitHub**: https://github.com/etherpilled/infinite-trading-cloud
