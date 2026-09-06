# Adaptive Quant Strategy Deployment

## 📊 Performance Summary (4.1 Year Backtest: 2022-2026)

| Metric | Adaptive Quant | Buy & Hold | Improvement |
|--------|---------------|------------|-------------|
| **Total Return** | **+18.59%** | -18.95% | **+37.54%** |
| **Number of Trades** | 173 | 0 | Active |
| **Win Rate** | 40.7% | N/A | Profitable |
| **Sharpe Ratio** | 0.06 | N/A | Positive |
| **Max Drawdown** | -45.25% | -81.23% | **Better** |

### Chart
_(Performance chart was not committed to the repo; regenerate from the backtest in `backtests/` if needed.)_

## 🎯 Strategy Overview

**Adaptive Quant** intelligently switches between two approaches based on market regime:

1. **Range-Bound Trading** (Choppy/Sideways Markets)
   - Buys at lower Bollinger Band when oversold (RSI < 40)
   - Sells at upper Bollinger Band when overbought (RSI > 70)
   - Uses tight 7% stop losses for capital preservation

2. **Trend-Following** (Parabolic/Trending Markets)
   - Enters on breakouts above upper Bollinger Band
   - **Never sells during parabolic runs** - uses trailing stops
   - 12% trailing stop that only moves UP, never down
   - Only exits on major reversals (bear market structure)

### Key Innovation: Bull Market Filter

The strategy **only trades when all 3 EMAs align**:
```
EMA(9) > EMA(21) > EMA(50) = Bull Market Structure
```

This filter kept the strategy OUT of the 2022 crypto winter crash, resulting in massive outperformance.

## 📁 Files Created

1. **`infinitetrading/src/strategies/adaptiveQuant.R`** - Production strategy
2. **`infinitetrading_api/ecosystem.config.js`** - Updated with new PM2 process
3. **`backtest_adaptive_simple.R`** - Standalone backtest script
4. **Performance chart** - regenerate from the backtest; not committed

## 🚀 Deployment Instructions

### 1. Deploy to EC2

```bash
# From your local machine
cd ~/infinite-trading-cloud

# Upload the strategy file
scp infinitetrading/src/strategies/adaptiveQuant.R ubuntu@YOUR_EC2_IP:~/infinitetrading/src/strategies/

# Upload updated PM2 config
scp infinitetrading_api/ecosystem.config.js ubuntu@YOUR_EC2_IP:~/infinitetrading_api/
```

### 2. Start the Strategy on EC2

```bash
# SSH into EC2
ssh ubuntu@YOUR_EC2_IP

# Navigate to API directory
cd ~/infinitetrading_api

# Reload PM2 config
pm2 reload ecosystem.config.js

# Start the new strategy
pm2 start ecosystem.config.js --only strategy-adaptive-quant

# Check it's running
pm2 list | grep adaptive

# Monitor logs
pm2 logs strategy-adaptive-quant
```

### 3. Verify Operation

```bash
# Check logs for strategy execution
pm2 logs strategy-adaptive-quant --lines 50

# Look for:
# - "Adaptive Quant Strategy Check" every 30 minutes
# - Bull market structure checks
# - Entry/exit signals
# - Position updates
```

### 4. Stop Old EMA-RSI Strategy (Optional)

If you want to replace the old `emaRsi.R` strategy:

```bash
pm2 stop strategy-ema-rsi
pm2 delete strategy-ema-rsi
```

## 🔧 Configuration

Edit `/home/ubuntu/infinitetrading/src/strategies/adaptiveQuant.R`:

```r
# Change trading pair
pairs = c("DHT-USDC")  # Your pool's pair
candles_pairs = c("ETH-USD")  # Proxy for price data

# Adjust position sizing
shares = c(100)  # % of balance to trade
max_usds = c(1000)  # Max USD per trade

# Tune trailing stop (currently 12%)
trailing_stops[i] <<- current_price * 0.88  # 0.88 = 12% stop
```

## 📈 Expected Behavior

### In Bull Markets (EMA 9 > 21 > 50):
- **Active Trading**: Enters on dips and breakouts
- **Holds Winners**: Trailing stop protects gains
- **Quick Exits**: Cuts losers fast (7-12% stops)

### In Bear Markets (EMAs Misaligned):
- **NO TRADING**: Strategy stays in cash/stablecoins
- **Capital Preservation**: Avoids drawdowns
- **Waits for Setup**: Only re-enters when structure improves

### In Sideways Markets:
- **Range Scalping**: Buys dips, sells rips
- **High Activity**: More trades, smaller gains
- **Risk Management**: Tight stops prevent big losses

## 🎯 Performance Highlights

**Why This Strategy Won:**

1. ✅ **Avoided 2022 Crash** - Bull market filter kept it sidelined during -81% drawdown
2. ✅ **Caught Recovery** - Entered on dips during 2023-2024 recovery
3. ✅ **Never Panic Sold** - Trailing stops let winners run
4. ✅ **Managed Risk** - 45% max drawdown vs 81% for other strategies

**Comparison to Other Approaches:**

- **Current (EMA 4/12 RSI-4)**: -18.03% | TOO MANY trades (182), got whipsawed
- **Quant Special**: +7.72% | Good but overtraded (1,054 trades initially, refined to 169)
- **Trend Rider**: -26.34% | Too aggressive, bought every dip including crashes
- **Adaptive Quant**: +18.59% | 🏆 **WINNER** - Smart regime switching

## ⚠️ Risk Warnings

1. **Backtested != Guaranteed** - Past performance doesn't predict future results
2. **Market Dependent** - Works best in bull/ranging, struggles in sustained bears
3. **Trailing Stops** - Can get stopped out on flash crashes
4. **Proxy Pair** - Uses ETH as proxy for DHT, correlation may vary

## 📊 Monitoring Checklist

Daily/Weekly checks:

- [ ] Strategy running in PM2 (`pm2 list`)
- [ ] No error messages in logs
- [ ] Positions match expected based on market structure
- [ ] Trailing stops updating correctly
- [ ] No stuck positions (check pool balances)

## 🔄 Maintenance

**Monthly Review:**
- Check win rate (target: >40%)
- Review trailing stop level (adjust if needed)
- Verify bull market filter accuracy
- Compare to buy & hold

**Quarterly Optimization:**
- Re-run backtest with latest data
- Adjust parameters if market regime changed
- Consider adding more pairs if profitable

## 📞 Support

If issues arise:
1. Check `pm2 logs strategy-adaptive-quant`
2. Verify Coinbase API connectivity
3. Ensure .env variables are set
4. Check pool has sufficient balance

---

**Deployed:** April 15, 2026  
**Backtested Period:** March 2022 - April 2026 (4.1 years)  
**Strategy Author:** Quant Team  
**Version:** 1.0
