"""
rotation_crossoverv4.py
ETH/BTC/USDC rotation backtest using the EMA Crossover v4 dual-mode signal
(backtests/btc-crossoverv4-backtest.R):
  TREND mode      : 60% EMA consensus + SMA(50) + RSI(14)>45, 6h bars
  ACCUMULATION mode: price >=35% below 180d high, RSI<35, bounced >=10%
                     off 90d low

Applied independently to ETH-BTC, BTC-USD, ETH-USD; combined via the
3-way rotation rule.

Run: python3 backtests/rotation/rotation_crossoverv4.py
"""
import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from rotation_engine import (
    calc_daily_returns, shift1, align_series, build_rotation_chart,
    run_rotation_backtest,
)
from dual_mode_signal import build_dual_mode_daily_signal

START = "2019-01-01"

PARAMS = dict(
    threshold=0.60, sma_period=50, rsi_period=14, rsi_min=45,
    accum_drawdown=0.35, accum_rsi_max=35, accum_bounce=0.10,
    accum_high_days=180, accum_low_days=90,
    ema_fast=range(9, 14), ema_slow=range(29, 34),
)

print("Fetching & building EMA Crossover v4 (dual-mode) signals for ETH-BTC, BTC-USD, ETH-USD...")
eth_btc = build_dual_mode_daily_signal("ETH-BTC", START, PARAMS)
btc_usd = build_dual_mode_daily_signal("BTC-USD", START, PARAMS)
eth_usd = build_dual_mode_daily_signal("ETH-USD", START, PARAMS)

eth_btc = eth_btc.assign(sig=shift1(eth_btc["sig"].to_numpy()))
btc_usd = btc_usd.assign(sig=shift1(btc_usd["sig"].to_numpy()))
eth_usd = eth_usd.assign(sig=shift1(eth_usd["sig"].to_numpy()))

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
print(" EMA Crossover v4 (Dual-Mode) Rotation Strategy — ETH / BTC / USDC")
print("=" * 60)
print(f"  Trend mode    : 60% EMA(9-13,29-33) + SMA(50) + RSI(14)>45")
print(f"  Accum mode    : >=35% dip / RSI<35 / >=10% bounce")
print(f"  Applied to    : ETH-BTC, BTC-USD, ETH-USD (independently)")
print(f"  Time in ETH   : {pct_eth:.1f}%")
print(f"  Time in BTC   : {pct_btc:.1f}%")
print(f"  Time in USDC  : {pct_usdc:.1f}%")
print("=" * 60 + "\n")

out_path = os.path.join(os.path.dirname(__file__), "..", "backtest_charts", "rotation_crossoverv4.png")

metrics_btc = build_rotation_chart(
    dates_vec, rets_mat, primary_asset="BTC",
    title="EMA Crossover v4 (Dual-Mode) Rotation vs BTC",
    subtitle=f"Period {dates_vec.min().date()} to {dates_vec.max().date()} | "
             f"Time in ETH {pct_eth:.0f}% / BTC {pct_btc:.0f}% / USDC {pct_usdc:.0f}%",
    out_path=out_path.replace(".png", "_vs_btc.png"),
    signal_labels=holdings,
)
metrics_eth = build_rotation_chart(
    dates_vec, rets_mat, primary_asset="ETH",
    title="EMA Crossover v4 (Dual-Mode) Rotation vs ETH",
    subtitle=f"Period {dates_vec.min().date()} to {dates_vec.max().date()} | "
             f"Time in ETH {pct_eth:.0f}% / BTC {pct_btc:.0f}% / USDC {pct_usdc:.0f}%",
    out_path=out_path.replace(".png", "_vs_eth.png"),
    signal_labels=holdings,
)

print("\n========== PERFORMANCE METRICS (vs BTC) ==========")
print(metrics_btc.to_string(index=False))
print("\n========== PERFORMANCE METRICS (vs ETH) ==========")
print(metrics_eth.to_string(index=False))
