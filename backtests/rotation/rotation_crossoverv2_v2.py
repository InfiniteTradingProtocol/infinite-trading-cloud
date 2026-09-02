"""
rotation_crossoverv2_v2.py
Enhanced version of rotation_crossoverv2.py — SAME underlying EMA
Crossover v2 signal logic (unchanged), with the improved position
management overlay from rotation_engine_v2.py (15% trailing stop +
5-day switch deadband). Does not modify rotation_crossoverv2.py or
rotation_engine.py.

Run: python3 backtests/rotation/rotation_crossoverv2_v2.py
"""
import os
import sys
import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(__file__))
from rotation_engine import (
    fetch_coinbase_candles, resample_to_daily, calc_daily_returns,
    ema_consensus_signal, sma, rsi, shift1,
)
from rotation_engine_v2 import run_rotation_backtest_v2
from rotation_v2_report import report

START = "2019-01-01"
TIMEFRAME = "6h"
THRESHOLD = 0.60
SMA_PERIOD = 50
RSI_PERIOD = 14
RSI_MIN = 45
EMA_FAST = range(9, 14)
EMA_SLOW = range(29, 34)
TRAILING_STOP = 0.15
MIN_HOLD_DAYS = 5


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
    name="EMA Crossover v2 Rotation v2",
    out_name="rotation_crossoverv2_v2.png",
    common=common, strat_ret=strat_ret, btc_ret=btc_ret, eth_ret=eth_ret,
    holdings=holdings, stop_events=stop_events,
    base_signal_desc="EMA grid(9-13,29-33) >=60% + SMA(50) + RSI(14)>45",
    trailing_stop=TRAILING_STOP, min_hold_days=MIN_HOLD_DAYS,
    charts_dir=os.path.join(os.path.dirname(__file__), "..", "backtest_charts"),
)
