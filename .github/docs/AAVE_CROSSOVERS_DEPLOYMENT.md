# AAVE-Optimized CrossOvers Deployment Guide

## Overview
This deployment creates 6 new vaults with AAVE yield optimization, running in parallel with the existing crossOvers.R strategy.

## Architecture

### Two Separate Systems:
1. **crossOvers.R** (existing) - Runs on original vaults WITHOUT AAVE
2. **crossOversAndAAVE.R** (new) - Runs on new vaults WITH AAVE optimization

### Key Features:
- **Dual Strategy**: Both `setBot` API (for deposit handling) AND direct AAVE optimization
- **Universal USDC Yield**: ALL pairs earn yield on USDC during bearish periods
- **Asset Support**: Only WETH and USDC are lent to AAVE on LONG signals
- **Automatic**: Handles lending/unlending automatically based on signal changes

## Step 1: Create Vaults

Run the vault creation script:

```bash
cd /Users/richardclare/infinite-trading-cloud
Rscript scripts/create_aave_vaults.R
```

This will:
- Create 6 new dHEDGE vaults (one per strategy pair)
- Set the gas wallet as trader on each vault
- Save vault addresses to `infinitetrading/src/strategies/aave_vault_addresses.R`

### Expected Vaults:
1. **MORPHO-USDC** (Base) - ITP MORPHO/USDC EMA Crossover + AAVE
2. **SNX-USDC** (Optimism) - ITP SNX/USDC EMA Crossover + AAVE
3. **AERO-USDC** (Base) - ITP AERO/USDC EMA Crossover + AAVE
4. **AAVE-USDC** (Optimism) - ITP AAVE/USDC EMA Crossover + AAVE
5. **cbBTC-USDC** (Base) - ITP cbBTC/USDC EMA Crossover + AAVE
6. **WETH-USDC** (Optimism) - ITP WETH/USDC EMA Crossover + AAVE

## Step 2: Fund Vaults

Deposit initial USDC into each vault:
- Use dHEDGE frontend or API
- Recommended: $1000-$5000 USDC per vault to start

## Step 3: Deploy Strategy

### Local Testing:
```bash
cd infinitetrading/src/strategies
Rscript crossOversAndAAVE.R
```

### Production Deployment (EC2):

1. Upload files to EC2:
```bash
scp -i ~/.ssh/macmini.pem \
  infinitetrading/src/strategies/crossOversAndAAVE.R \
  infinitetrading/src/strategies/aave_vault_addresses.R \
  infinitetrading/src/tradebot/aave_yield_optimizer.R \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:~/infinitetrading/src/strategies/

scp -i ~/.ssh/macmini.pem \
  infinitetrading/src/tradebot/aave_yield_optimizer.R \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:~/infinitetrading/src/tradebot/
```

2. Add to PM2:
```bash
ssh -i ~/.ssh/macmini.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# Start strategy
pm2 start --interpreter Rscript \
  --name strategy-crossovers-aave \
  ~/infinitetrading/src/strategies/crossOversAndAAVE.R

# Save PM2 config
pm2 save

# Check logs
pm2 logs strategy-crossovers-aave
```

## How It Works

### Signal Flow:

#### LONG Signal (Bullish):
1. **Unlend USDC** from AAVE (if lent)
2. **Buy** target asset with USDC
3. **Lend** target asset to AAVE (only if WETH or USDC)
4. **Set bot** via API (handles future deposits)

Example:
- WETH-USDC LONG → Buy WETH → Lend WETH to AAVE ✅
- MORPHO-USDC LONG → Buy MORPHO → Keep in vault (not supported)

#### SELL/NEUTRAL Signal (Bearish/Exit):
1. **Unlend** target asset from AAVE (if lent)
2. **Sell** target asset to USDC
3. **ALWAYS lend USDC** to AAVE (USDC always supported!)
4. **Set bot** via API (handles future deposits)

Example:
- WETH-USDC SELL → Sell WETH → Lend USDC to AAVE ✅
- MORPHO-USDC SELL → Sell MORPHO → Lend USDC to AAVE ✅ (even though MORPHO not supported!)

### Why Both Bot API AND Direct Optimization?

1. **`setBot` API**: Ensures deposits trigger automatic trades
2. **Direct AAVE optimization**: Adds lending/unlending on top of trades

This hybrid approach ensures:
- New deposits are handled automatically
- Existing positions are AAVE-optimized
- Maximum capital efficiency

## Monitoring

### Check Logs:
```bash
# Local
pm2 logs strategy-crossovers-aave

# Remote
ssh -i ~/.ssh/macmini.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "pm2 logs strategy-crossovers-aave --lines 100"
```

### Expected Log Output:
```
[1/6] MORPHO-USDC Strategy on base
Signal: 15/25  Probability: 60.00%  Side: LONG
📊 Signal changed: hold → long

🎯 Executing trade with AAVE yield optimization...

================================================================================
🎯 Executing trade with AAVE optimization
Pair: MORPHO-USDC | Signal: long | Network: base
================================================================================

📊 Current balances:
   MORPHO: 0
   USDC: 1000.5

🏦 AAVE positions:
   MORPHO supplied: None
   USDC supplied: 995.2 ✓

💎 AAVE support:
   MORPHO: ❌ Not supported (will skip lending)
   USDC: ✅ Supported

📈 LONG signal detected

Step 1: Unlending USDC from AAVE to free capital for buying...
🏦 Unlending 100% of USDC from AAVE...
✅ Successfully unlent USDC from AAVE. Tx: 0x1234...

Step 2: Buying MORPHO with USDC...
✅ Trade successful. Tx: 0x5678...

Step 3: MORPHO not supported by AAVE, holding in vault

✅ Trade + AAVE optimization completed successfully

📡 Setting bot via API (for deposit handling)...
✅ Bot set successfully - deposits will trigger trades
```

### Check AAVE Positions:
```bash
curl -s "https://api.infinitetrading.io/aaveV3/getSupplied?pool=<VAULT_ADDRESS>&network=optimism&asset=USDC&protocol=dhedge&apiKey=<API_KEY>" | jq '.'
```

## Troubleshooting

### Issue: "Run scripts/create_aave_vaults.R first"
- You need to create vaults before running the strategy
- Run the vault creation script first

### Issue: AAVE transactions failing
- Check vault has approved AAVE Pool contract
- Verify asset is supported (only WETH, USDC work on LONG)
- Check gas wallet has enough ETH for gas

### Issue: Bot not executing on deposits
- Verify bot was set via API (check logs)
- Check vault composition and balance
- Ensure gas wallet is set as trader

## Cost Analysis

### Transaction Costs (per strategy cycle):
- **LONG with AAVE**:
  - Unlend USDC: ~$0.05
  - Trade: ~$0.20-$1.50 (depends on DEX)
  - Lend target asset: ~$0.05
  - Total: ~$0.30-$1.60

- **SELL with AAVE**:
  - Unlend target asset: ~$0.05
  - Trade: ~$0.20-$1.50
  - Lend USDC: ~$0.05
  - Total: ~$0.30-$1.60

### API Pricing:
- lend: $0.05
- unlend: $0.05
- approve: $0.02

### Break-Even Analysis:
- AAVE USDC APY: ~3-5%
- If holding $1000 USDC for 1 week: ~$0.60-$1.00 yield
- Transaction cost: ~$0.30-$1.60
- **Break-even**: ~1-3 weeks holding period

## Safety Features

1. **Asset Whitelist**: Only WETH and USDC are lent (hardcoded)
2. **Error Handling**: All AAVE operations wrapped in tryCatch
3. **State Verification**: Always checks current AAVE positions before acting
4. **Graceful Degradation**: If AAVE fails, trade still executes
5. **Transaction Delays**: 3-5 second delays after transactions for confirmation

## Next Steps

1. ✅ Create vaults with `create_aave_vaults.R`
2. ✅ Fund vaults with USDC
3. ✅ Test locally with small amounts
4. ✅ Deploy to EC2 production
5. ✅ Monitor for 24-48 hours
6. ✅ Scale up vault sizes if successful

## Notes

- Original `crossOvers.R` continues running on existing vaults
- New `crossOversAndAAVE.R` runs independently on new vaults
- Both strategies can run simultaneously
- AAVE optimization adds ~$0.10-$0.20 per trade in gas costs
- Expected to increase returns by 2-4% APY on idle USDC

## Contact

For issues or questions, check:
- `.github/docs/AAVE_YIELD_OPTIMIZATION_GUIDE.md`
- PM2 logs
- AAVE endpoints documentation
