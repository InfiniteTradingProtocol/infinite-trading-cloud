"""
rotation_btcstrat.py
ETH/BTC/USDC rotation backtest using the BTCStrat dual-mode signal
(backtests/btc-btcstrat-backtest.R) — a BTC-tuned variant of crossOverV4
with earlier trend entry and wider stops/lookbacks (stops aren't used
directly in this rotation, only the underlying long/neutral state):
  TREND mode      : 50% EMA consensus + SMA(50) + RSI(14)>40, 6h bars
  ACCUMULATION mode: price >=30% below 365d high, RSI<40, bounced >=5%
                     off 120d low

Applied independently to ETH-BTC, BTC-USD, ETH-USD; combined via the
3-way rotation rule.

Run: python3 backtests/rotation/rotation_btcstrat.py
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
    threshold=0.50, sma_period=50, rsi_period=14, rsi_min=40,
    accum_drawdown=0.30, accum_rsi_max=40, accum_bounce=0.05,
    accum_high_days=365, accum_low_days=120,
    ema_fast=range(9, 14), ema_slow=range(29, 34),
)

print("Fetching & building BTCStrat (dual-mode) signals for ETH-BTC, BTC-USD, ETH-USD...")
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
print(" BTCStrat (Dual-Mode) Rotation Strategy — ETH / BTC / USDC")
print("=" * 60)
print(f"  Trend mode    : 50% EMA(9-13,29-33) + SMA(50) + RSI(14)>40")
print(f"  Accum mode    : >=30% dip / RSI<40 / >=5% bounce")
print(f"  Applied to    : ETH-BTC, BTC-USD, ETH-USD (independently)")
print(f"  Time in ETH   : {pct_eth:.1f}%")
print(f"  Time in BTC   : {pct_btc:.1f}%")
print(f"  Time in USDC  : {pct_usdc:.1f}%")
print("=" * 60 + "\n")

out_path = os.path.join(os.path.dirname(__file__), "..", "backtest_charts", "rotation_btcstrat.png")

metrics_btc = build_rotation_chart(
    dates_vec, rets_mat, primary_asset="BTC",
    title="BTCStrat (Dual-Mode) Rotation vs BTC",
    subtitle=f"Period {dates_vec.min().date()} to {dates_vec.max().date()} | "
             f"Time in ETH {pct_eth:.0f}% / BTC {pct_btc:.0f}% / USDC {pct_usdc:.0f}%",
    out_path=out_path.replace(".png", "_vs_btc.png"),
    signal_labels=holdings,
)
metrics_eth = build_rotation_chart(
    dates_vec, rets_mat, primary_asset="ETH",
    title="BTCStrat (Dual-Mode) Rotation vs ETH",
    subtitle=f"Period {dates_vec.min().date()} to {dates_vec.max().date()} | "
             f"Time in ETH {pct_eth:.0f}% / BTC {pct_btc:.0f}% / USDC {pct_usdc:.0f}%",
    out_path=out_path.replace(".png", "_vs_eth.png"),
    signal_labels=holdings,
)

print("\n========== PERFORMANCE METRICS (vs BTC) ==========")
print(metrics_btc.to_string(index=False))
print("\n========== PERFORMANCE METRICS (vs ETH) ==========")
print(metrics_eth.to_string(index=False))
