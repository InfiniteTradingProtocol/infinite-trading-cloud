"""
rotation_crossoverv2.py
ETH/BTC/USDC rotation backtest using the EMA Crossover v2 signal logic
(backtests/btc-crossoverv2-backtest.R):
  - EMA grid: fast 9-13, slow 29-33 (25 combos), 6h bars
  - >=60% bullish consensus threshold
  - SMA(50) daily trend filter
  - RSI(14) daily > 45 momentum guard

Applied independently to ETH-BTC, BTC-USD, ETH-USD to derive each pair's
bullish/bearish state, then combined via the same 3-way rotation rule as
the other rotation scripts.

Run: python3 backtests/rotation/rotation_crossoverv2.py
"""
import os
import sys
import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(__file__))
from rotation_engine import (
    fetch_coinbase_candles, resample_to_daily, calc_daily_returns,
    ema_consensus_signal, sma, rsi, shift1, align_series,
    build_rotation_chart, run_rotation_backtest,
)

START = "2019-01-01"
TIMEFRAME = "6h"
THRESHOLD = 0.60
SMA_PERIOD = 50
RSI_PERIOD = 14
RSI_MIN = 45
EMA_FAST = range(9, 14)
EMA_SLOW = range(29, 34)


def build_daily_signal(pair):
    raw = fetch_coinbase_candles(pair, TIMEFRAME, start=START)
    daily = resample_to_daily(raw)

    prob_6h = ema_consensus_signal(raw["close"].to_numpy(), EMA_FAST, EMA_SLOW)
    raw = raw.assign(prob=prob_6h)
    prob_daily = raw.groupby("date_d", as_index=False)["prob"].last()

    close_d = daily["close"].to_numpy()
    sma50 = sma(close_d, SMA_PERIOD)
    rsi14 = rsi(close_d, RSI_PERIOD)

    sig_raw = np.where(
        (prob_daily["prob"].to_numpy() >= THRESHOLD) &
        (close_d > sma50) &
        (rsi14 > RSI_MIN),
        "long", "neutral"
    )
    sig_raw = np.where(pd.isna(sig_raw), "neutral", sig_raw)
    return daily.assign(sig=shift1(sig_raw))


print("Fetching & building EMA Crossover v2 signals for ETH-BTC, BTC-USD, ETH-USD...")
eth_btc = build_daily_signal("ETH-BTC")
btc_usd = build_daily_signal("BTC-USD")
eth_usd = build_daily_signal("ETH-USD")

common = np.array(sorted(
    set(eth_btc["date_d"]) & set(btc_usd["date_d"]) & set(eth_usd["date_d"])
))


def reindex(df, col, dates):
    return df.set_index("date_d")[col].reindex(dates).to_numpy()


eth_btc_bull = reindex(eth_btc, "sig", common) == "long"
btc_usd_bull = reindex(btc_usd, "sig", common) == "long"
eth_usd_bull = reindex(eth_usd, "sig", common) == "long"

btc_close = reindex(btc_usd, "close", common)
eth_close = reindex(eth_usd, "close", common)
btc_ret = calc_daily_returns(btc_close)
eth_ret = calc_daily_returns(eth_close)

strat_ret, holdings = run_rotation_backtest(
    eth_btc_bull, btc_usd_bull, eth_usd_bull, eth_ret, btc_ret
)

series_input = {
    "Strategy": {"dates": common, "rets": strat_ret},
    "BTC": {"dates": common, "rets": btc_ret},
    "ETH": {"dates": common, "rets": eth_ret},
}
dates_vec, rets_mat = align_series(series_input)

pct_eth = (holdings == "ETH").mean() * 100
pct_btc = (holdings == "BTC").mean() * 100
pct_usdc = (holdings == "USDC").mean() * 100

print("\n" + "=" * 60)
print(" EMA Crossover v2 Rotation Strategy — ETH / BTC / USDC")
print("=" * 60)
print(f"  Base signal   : EMA grid(9-13,29-33) >=60% + SMA(50) + RSI(14)>45")
print(f"  Applied to    : ETH-BTC, BTC-USD, ETH-USD (independently)")
print(f"  Time in ETH   : {pct_eth:.1f}%")
print(f"  Time in BTC   : {pct_btc:.1f}%")
print(f"  Time in USDC  : {pct_usdc:.1f}%")
print("=" * 60 + "\n")

out_path = os.path.join(os.path.dirname(__file__), "..", "backtest_charts", "rotation_crossoverv2.png")

metrics_btc = build_rotation_chart(
    dates_vec, rets_mat, primary_asset="BTC",
    title="EMA Crossover v2 Rotation (ETH/BTC/USDC) vs BTC",
    subtitle=f"Period {dates_vec.min().date()} to {dates_vec.max().date()} | "
             f"Time in ETH {pct_eth:.0f}% / BTC {pct_btc:.0f}% / USDC {pct_usdc:.0f}%",
    out_path=out_path.replace(".png", "_vs_btc.png"),
    signal_labels=holdings,
)
metrics_eth = build_rotation_chart(
    dates_vec, rets_mat, primary_asset="ETH",
    title="EMA Crossover v2 Rotation (ETH/BTC/USDC) vs ETH",
    subtitle=f"Period {dates_vec.min().date()} to {dates_vec.max().date()} | "
             f"Time in ETH {pct_eth:.0f}% / BTC {pct_btc:.0f}% / USDC {pct_usdc:.0f}%",
    out_path=out_path.replace(".png", "_vs_eth.png"),
    signal_labels=holdings,
)

print("\n========== PERFORMANCE METRICS (vs BTC) ==========")
print(metrics_btc.to_string(index=False))
print("\n========== PERFORMANCE METRICS (vs ETH) ==========")
print(metrics_eth.to_string(index=False))
