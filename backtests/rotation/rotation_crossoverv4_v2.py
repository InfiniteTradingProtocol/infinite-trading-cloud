"""
rotation_crossoverv4_v2.py
Enhanced version of rotation_crossoverv4.py — SAME underlying EMA
Crossover v4 dual-mode signal logic (unchanged, via dual_mode_signal.py),
with the improved position management overlay from rotation_engine_v2.py
(15% trailing stop + 5-day switch deadband). Does not modify
rotation_crossoverv4.py, dual_mode_signal.py, or rotation_engine.py.

Run: python3 backtests/rotation/rotation_crossoverv4_v2.py
"""
import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from rotation_engine import calc_daily_returns, shift1
from rotation_engine_v2 import run_rotation_backtest_v2
from rotation_v2_report import report
from dual_mode_signal import build_dual_mode_daily_signal

START = "2019-01-01"
TRAILING_STOP = 0.15
MIN_HOLD_DAYS = 5

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

common = np.array(sorted(set(eth_btc["date_d"]) & set(btc_usd["date_d"]) & set(eth_usd["date_d"])))


def reindex(df, col, dates):
    return df.set_index("date_d")[col].reindex(dates).to_numpy()


eth_btc_bull = reindex(eth_btc, "sig", common) == "long"
btc_usd_bull = reindex(btc_usd, "sig", common) == "long"
eth_usd_bull = reindex(eth_usd, "sig", common) == "long"

btc_close = reindex(btc_usd, "close", common)
eth_close = reindex(eth_usd, "close", common)
btc_ret = calc_daily_returns(btc_close)
eth_ret = calc_daily_returns(eth_close)

strat_ret, holdings, stop_events = run_rotation_backtest_v2(
    eth_btc_bull, btc_usd_bull, eth_usd_bull, eth_ret, btc_ret,
    eth_close, btc_close,
    trailing_stop_pct=TRAILING_STOP, min_hold_days=MIN_HOLD_DAYS,
)

report(
    name="EMA Crossover v4 (Dual-Mode) Rotation v2",
    out_name="rotation_crossoverv4_v2.png",
    common=common, strat_ret=strat_ret, btc_ret=btc_ret, eth_ret=eth_ret,
    holdings=holdings, stop_events=stop_events,
    base_signal_desc="Trend: 60% EMA+SMA50+RSI>45 | Accum: >=35% dip / RSI<35 / >=10% bounce",
    trailing_stop=TRAILING_STOP, min_hold_days=MIN_HOLD_DAYS,
    charts_dir=os.path.join(os.path.dirname(__file__), "..", "backtest_charts"),
)
