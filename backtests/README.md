# Backtests Directory

This directory contains all backtesting code, data, and results for trading strategies.

## Directory Structure

```
backtests/
├── data/                                   # Historical price data (gitignored)
│   ├── ETH_6H_2016-05-18_2026-04-15.csv   # 10 years of 6-hour candles
│   ├── ETH_1H_START_END.csv               # 1-hour candles (future)
│   └── ETH_1D_START_END.csv               # Daily candles (future)
│
├── trend-rider/                            # Trend Rider strategy backtests
│   ├── backtest_trend_rider.R             # Backtest script
│   ├── trend_rider_results.csv            # Performance metrics
│   ├── trend_rider_equity.csv             # Equity curve data
│   └── charts/
│       └── trend_rider_performance.png
│
├── adaptive-quant/                         # Adaptive Quant strategy
│   └── charts/
│
├── quant-special/                          # Quant Special strategy
│   └── charts/
│
├── current-ema-rsi/                        # Current EMA+RSI strategy
│   └── charts/
│
└── backtest_charts/                        # Overall comparison charts
    └── strategy_comparison_10years.png
```

## What's Gitignored

To keep the repository lightweight:
- ✅ **Backtest code** (`.R` files) - COMMITTED
- ✅ **README files** - COMMITTED
- ❌ **Data files** (`backtests/data/*.csv`) - IGNORED
- ❌ **Result CSVs** (`backtests/**/*.csv`) - IGNORED
- ❌ **Charts** (`backtests/**/charts/*.png`) - IGNORED

## Usage

### Run a Backtest

```bash
cd backtests/trend-rider
Rscript backtest_trend_rider.R
```

The script will:
1. Check for cached data in `../data/`
2. If not found, fetch from Coinbase API
3. Run backtest and save results locally
4. Generate charts in `charts/` folder

### View Results

Results are saved as CSV files in each strategy folder:
- `*_results.csv` - Performance summary
- `*_equity.csv` - Full equity curve data

Charts are saved in `charts/` subdirectories.

## Strategy Performance (10 Years: 2016-2026)

| Strategy | Return | Trades | Win Rate | Sharpe | Max DD |
|----------|--------|--------|----------|--------|--------|
| **Trend Rider** | +21,824% | 639 | 29.2% | 0.39 | -53.6% |
| **Buy & Hold** | +16,845% | 0 | N/A | N/A | -94.1% |
| **Adaptive Quant** | +2,758% | 435 | 43.8% | 0.31 | -49.6% |
| **Quant Special** | +3,131% | 479 | 58.2% | 0.42 | -42.8% |
| **Current** | -21.7% | 464 | 46.1% | -0.07 | -37.7% |

### Key Findings

1. **Trend Rider wins** in long-term trending markets
   - Uses ATR-based dynamic stops (adapts to volatility)
   - Never sells during parabolic runs (4x ATR trailing stop)
   - 30% win rate but massive winners offset small losses

2. **Adaptive Quant** provides smoother returns
   - Lower drawdown (-49% vs -53%)
   - Higher win rate (44% vs 29%)
   - Better for risk-averse traders

3. **Current strategy** overtraded and failed
   - Too sensitive parameters (EMA 4/12, RSI-4)
   - Lost money despite 46% win rate

## Data Management

### Adding New Data

When fetching new timeframes or date ranges:

```r
# The backtest scripts automatically name files:
# ETH_{TIMEFRAME}_{START_DATE}_{END_DATE}.csv

# Example:
# ETH_1H_2020-01-01_2026-04-15.csv
# ETH_1D_2015-01-01_2026-04-15.csv
```

### Sharing Results (Without Data)

Since data files are gitignored, you can commit and push backtest code and others can:
1. Run the scripts to fetch their own data
2. Or manually download the CSV from shared drive
3. Place in `backtests/data/` directory

## Notes

- Data files are excluded from Git to save space (862 KB per 10 years)
- EC2 deployment won't include backtest data
- Keep backtest code and production strategy code separate
- Use cached CSV files to avoid re-fetching data

## Future Enhancements

- [ ] Add 1-hour and daily candle backtests
- [ ] Create backtest scripts for Adaptive Quant
- [ ] Create backtest scripts for Quant Special
- [ ] Add parameter optimization scripts
- [ ] Add Monte Carlo simulation
- [ ] Add walk-forward analysis
