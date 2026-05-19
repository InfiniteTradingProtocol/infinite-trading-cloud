# Backtesting Framework

Reusable backtesting system for Infinite Trading strategies.
All data comes from the **Coinbase Exchange REST API** — no Yahoo Finance, no rate-limit bans.

---

## Folder Structure

```
backtests/
├── backtest_engine.R          ← Core library (fetch, metrics, chart) — DO NOT EDIT PER-STRATEGY
├── data/
│   └── fetch_coinbase_candles.R  ← Paginated Coinbase candle fetcher
├── backtest_charts/           ← Auto-created PNG output folder
├── morpho-crossover-backtest.R   ← Example: EMA crossover on MORPHO-USD 6H
└── BACKTESTING.md             ← This file
```

---

## How to Create a New Backtest

### Step 1 — Copy the template

```bash
cp backtests/morpho-crossover-backtest.R backtests/my-strategy-backtest.R
```

### Step 2 — Edit the Config section only

```r
# ── 1. Config ──────────────────────────────────────────────
PAIR           <- "AERO-USD"       # Coinbase pair to trade
TIMEFRAME      <- "6h"             # Candle timeframe: "1m","5m","15m","1h","6h","1d"
BENCHMARKS     <- c("BTC-USD", "ETH-USD")   # Pairs to compare against
```

### Step 3 — Replace the Signal section with your strategy logic

The signal section (step 3 in the file) is the **only part that changes per strategy**.
Your job is to produce a vector called `signal_6h` (or `signal_daily` if 1D) with values `"long"` or `"neutral"`.

**Rules:**
- Signal must be computed on `raw_6h$close` (or `asset_daily$close` for 1D strategies)
- Signal is automatically shifted by 1 bar inside the engine — **do not shift it yourself**
- Only `"long"` and `"neutral"` are supported — no shorting

**EMA crossover example (already in template):**
```r
signal_6h <- ifelse(EMA(close, n=9) > EMA(close, n=29), "long", "neutral")
```

**RSI example:**
```r
rsi_val   <- RSI(close_6h, n = 14)
signal_6h <- ifelse(rsi_val > 50, "long", "neutral")
signal_6h[is.na(rsi_val)] <- "neutral"
```

**SuperTrend example:**
```r
atr_vals   <- ATR(HLC(candle_df), n = 100)[,2]
hl2        <- (high + low) / 2
lowerBand  <- hl2 - 5 * atr_vals
# ... (build superTrend vector) ...
signal_6h  <- ifelse(close > superTrend, "long", "neutral")
```

### Step 4 — Run it

```bash
Rscript backtests/my-strategy-backtest.R
```

Chart is saved to `backtests/backtest_charts/my-strategy-YYYYMMDD.png`.

---

## Engine API Reference

### `fetch_coinbase_candles(pair, timeframe, start, end, sleep_secs, verbose)`

Fetches full OHLCV history from Coinbase, paginating backwards in 300-candle batches.

| Param | Default | Description |
|---|---|---|
| `pair` | required | e.g. `"MORPHO-USD"` |
| `timeframe` | required | `"1m"`, `"5m"`, `"15m"`, `"1h"`, `"6h"`, `"1d"` |
| `start` | `NULL` | Start date `"YYYY-MM-DD"` — stops when reached |
| `end` | `NULL` | End date `"YYYY-MM-DD"` — defaults to now |
| `sleep_secs` | `0.4` | Pause between API requests to avoid rate-limiting |
| `verbose` | `TRUE` | Print progress |

Returns a `data.frame` with columns: `date`, `date_d`, `time`, `open`, `high`, `low`, `close`, `volume`.

---

### `resample_to_daily(df)`

Collapses an intraday candle df (from `fetch_coinbase_candles`) to daily close (last bar of each day).

---

### `calc_daily_returns(close_vec)`

Returns `c(0, diff(close) / lag(close))`. First bar is always 0.

---

### `run_backtest(signal_vec, asset_returns)`

Applies a pre-shifted signal to daily returns.
`"long"` → takes the asset return. `"neutral"` → 0 (cash).

**Important:** signal must already be shifted by 1 day before calling this.

```r
strat_ret <- run_backtest(
  signal_vec    = c("neutral", head(daily_signal, -1)),  # shift here
  asset_returns = asset_ret
)
```

---

### `align_series(named_list)`

Aligns multiple return series to their common dates.

```r
aligned <- align_series(list(
  Strategy = list(dates = d1, rets = r1),
  MORPHO   = list(dates = d2, rets = r2),
  BTC      = list(dates = d3, rets = r3)
))
# aligned$dates  → common Date vector
# aligned$rets   → matrix, one column per series
```

---

### `build_metrics_table(rets_list)`

Takes a named list of return vectors and returns a comparison table with:
Total Return, Ann. Return, Ann. Volatility, Sharpe, Sortino, Calmar, Max Drawdown, Win Rate.

---

### `build_chart(...)`

Generates a 5-panel dark-theme PNG chart:
1. Equity curves (log scale, all assets)
2. Drawdown — Strategy vs primary asset
3. Primary asset price + Long signal zones
4. Rolling 90-day Sharpe — Strategy vs primary asset
5. Performance metrics table

| Param | Description |
|---|---|
| `dates_vec` | Common aligned Date vector |
| `rets_list` | Named list of return vectors — **must include `"Strategy"`** |
| `primary_asset` | Name of main traded asset (e.g. `"MORPHO"`) |
| `price_vec` | Close prices aligned to `dates_vec` |
| `signal_vec` | `"long"`/`"neutral"` vector aligned to `dates_vec` |
| `title` | Chart title |
| `subtitle` | Chart subtitle |
| `out_path` | Full path for PNG output |
| `palette` | Optional named colour overrides |

---

## Supported Timeframes

| Code | Seconds | Description |
|---|---|---|
| `"1m"` | 60 | 1 minute |
| `"5m"` | 300 | 5 minutes |
| `"15m"` | 900 | 15 minutes |
| `"1h"` | 3600 | 1 hour |
| `"6h"` | 21600 | 6 hours |
| `"1d"` | 86400 | 1 day |

---

## Existing Backtests

| File | Strategy | Pair | Timeframe | Max DD | Sharpe |
|---|---|---|---|---|---|
| `morpho-crossover-backtest.R` | EMA Crossover Ensemble v1 — 5×5 grid, ≥30% long, no filters | MORPHO-USD | 6H | -65.4% | -0.12 |
| `morpho-crossover-v2-backtest.R` | EMA Crossover Ensemble v2 — 60% threshold + SMA(50) + RSI>45 + 8% trailing stop | MORPHO-USD | 6H | **-33.5%** | **+0.64** |

### v1 → v2 Improvements

| Metric | v1 | v2 | Delta |
|---|---|---|---|
| Total Return | -11.9% | **+47.2%** | +59pp |
| Ann. Volatility | 58.9% | **39.8%** | -19pp |
| Sharpe Ratio | -0.12 | **+0.64** | +0.76 |
| Max Drawdown | -65.4% | **-33.5%** | **+32pp DD reduction** |

### Changes made in v2
1. **Threshold raised 30% → 60%** — only enter when strong majority of EMA combos agree
2. **SMA(50) trend filter** — only go long when daily close is above the 50-day SMA (avoids entries in downtrends)
3. **RSI(14) > 45 guard** — avoids entering on weak/oversold momentum
4. **8% trailing stop** — exits position if price drops 8% from rolling high while in trade
