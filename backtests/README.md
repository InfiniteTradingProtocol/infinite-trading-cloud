# Backtests Directory

This directory contains all backtesting code, data, and results for trading strategies.

## Directory Structure

```
backtests/
├── data/                                   # Historical price data (gitignored)
│
├── backtest_engine.R                        # Core R backtest library (fetch, metrics, chart)
├── BACKTESTING.md                           # How to write a new R backtest from the template
├── btc-crossoverv2/v3/v4-backtest.R         # Per-pair strategy backtests (BTC)
├── eth-crossoverv2/v3/v4-backtest.R         # Per-pair strategy backtests (ETH)
├── morpho-crossover(-v2)-backtest.R         # MORPHO-USD EMA crossover backtests
├── btc_eth_1h_backtest.R, trade_replay.R, check_pkgs.R
│
├── rotation/                                # Python BTC/ETH/USDC rotation backtests
│   ├── rotation_engine.py                  # Core engine: fetch/indicators/signals/metrics (v1, untouched baseline)
│   ├── rotation_engine_v2.py               # v2 overlay: trailing stop + switch deadband on top of v1 signals
│   ├── dual_mode_signal.py                 # Shared trend+accumulation signal builder (v4/BTCStrat)
│   ├── rotation_v2_report.py               # Shared v2 metrics/chart reporting helper
│   ├── rotation_<strategy>.py              # v1 rotation script per strategy (SuperTrend, EMA v2/v4, BTCStrat)
│   └── rotation_<strategy>_v2.py           # v2 rotation script per strategy (same signals, stop+deadband overlay)
│
├── optimized-crossover/                     # Parameter-optimized crossover backtest + its own data/
├── trend-rider/                             # Trend Rider strategy backtest
│
├── legacy/                                  # Archived ad-hoc scripts/artifacts moved here from the
│   │                                        # repo root during the 2026-09 cleanup (kept for reference,
│   │                                        # not part of the active backtesting workflow above)
│   ├── adaptive-quant/                     # Adaptive Quant standalone backtest scripts + results
│   ├── ema-rsi/                            # EMA+RSI analysis/backtest/test scripts
│   └── root-charts/                        # Old chart PNGs that used to sit at the repo root
│
└── backtest_charts/                         # PNG output for the R backtests + rotation/ scripts above
```

## What's Gitignored

To keep the repository lightweight:
- ✅ **Backtest code** (`.R` / `.py` files) - COMMITTED
- ✅ **README files** - COMMITTED
- ✅ **`backtest_charts/*.png`** (note: this exact folder name is NOT gitignored — charts here are committed on purpose so results are reviewable without re-running)
- ❌ **Data files** (`backtests/data/*.csv`) - IGNORED
- ❌ **Result CSVs** (`backtests/**/*.csv`) - IGNORED
- ❌ **Charts in any folder literally named `charts/`** (`backtests/**/charts/*.png`) - IGNORED

## Usage

### Run an R Backtest

```bash
cd backtests
Rscript btc-crossoverv2-backtest.R
```

See [BACKTESTING.md](BACKTESTING.md) for the full template-based workflow (copy a script, edit the
Config section, replace the Signal section).

### Run a Rotation Backtest (Python)

```bash
cd backtests/rotation
python3 rotation_supertrend_v2.py     # or any other rotation_<strategy>[_v2].py
```

Each script fetches fresh data from the Coinbase Exchange REST API (no caching), prints a metrics
table (Sharpe, Sortino, Calmar, Max Drawdown, ...) vs BTC and ETH buy-and-hold, and writes 2 chart
PNGs into `../backtest_charts/`.

- `rotation_engine.py` / `dual_mode_signal.py` / `rotation_<strategy>.py` (v1) contain the actual
  strategy signal logic — **do not modify** these when tuning execution/risk-management behavior;
  they mirror the production R strategies as closely as possible.
- `rotation_engine_v2.py` / `rotation_<strategy>_v2.py` are an **additive, execution-only** layer
  (trailing stop + switch deadband) built on top of the unmodified v1 signals — this is where
  risk-management experiments should go.

### Legacy Scripts

Files under `backtests/legacy/` were moved from the repo root during a cleanup pass and are kept
only for historical reference. Some of them `source()` production files using a repo-root-relative
path (see the note at the top of each affected script) — run them from the repo root if you need to.

## Notes

- Data files are excluded from Git to save space
- EC2 deployment won't include backtest data
- Keep backtest code and production strategy code separate
- Use cached CSV files to avoid re-fetching data where the script supports it


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
