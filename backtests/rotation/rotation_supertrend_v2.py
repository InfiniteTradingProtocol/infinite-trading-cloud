"""
rotation_supertrend_v2.py
Enhanced version of rotation_supertrend.py — SAME underlying SuperTrend
signal logic (unchanged, reused from rotation_engine.py), but with an
improved position-management layer (rotation_engine_v2.py):
  - 15% trailing stop per held leg (forces exit to USDC on a deep drop,
    instead of waiting for the lagging trend signal to flip)
  - 5-day switch deadband (a new target must persist 5 days before the
    strategy actually rotates into it, cutting whipsaw switches)

Does not modify rotation_supertrend.py, rotation_engine.py, or the
production superTrend.R strategy in any way — this is an additive
overlay compared side-by-side against the original run.

Run: python3 backtests/rotation/rotation_supertrend_v2.py
"""
import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from rotation_engine import fetch_coinbase_candles, calc_daily_returns, supertrend_signal, shift1
from rotation_engine_v2 import run_rotation_backtest_v2
from rotation_v2_report import report

START = "2019-01-01"
ATR_PERIOD = 100
ATR_MULT = 5
SMA_LEN = 50
TRAILING_STOP = 0.15
MIN_HOLD_DAYS = 5

print("Fetching ETH-BTC, BTC-USD, ETH-USD daily candles from Coinbase...")
eth_btc = fetch_coinbase_candles("ETH-BTC", "1d", start=START)
btc_usd = fetch_coinbase_candles("BTC-USD", "1d", start=START)
eth_usd = fetch_coinbase_candles("ETH-USD", "1d", start=START)

sig_eth_btc = shift1(supertrend_signal(eth_btc["high"], eth_btc["low"], eth_btc["close"], ATR_PERIOD, ATR_MULT, SMA_LEN))
sig_btc_usd = shift1(supertrend_signal(btc_usd["high"], btc_usd["low"], btc_usd["close"], ATR_PERIOD, ATR_MULT, SMA_LEN))
sig_eth_usd = shift1(supertrend_signal(eth_usd["high"], eth_usd["low"], eth_usd["close"], ATR_PERIOD, ATR_MULT, SMA_LEN))

common = np.array(sorted(set(eth_btc["date_d"]) & set(btc_usd["date_d"]) & set(eth_usd["date_d"])))


def reindex(df, col, dates):
    return df.set_index("date_d")[col].reindex(dates).to_numpy()


eth_btc_bull = reindex(eth_btc.assign(sig=(sig_eth_btc == "long")), "sig", common).astype(bool)
btc_usd_bull = reindex(btc_usd.assign(sig=(sig_btc_usd == "long")), "sig", common).astype(bool)
eth_usd_bull = reindex(eth_usd.assign(sig=(sig_eth_usd == "long")), "sig", common).astype(bool)

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
    name="SuperTrend Rotation v2",
    out_name="rotation_supertrend_v2.png",
    common=common, strat_ret=strat_ret, btc_ret=btc_ret, eth_ret=eth_ret,
    holdings=holdings, stop_events=stop_events,
    base_signal_desc=f"SuperTrend(ATR {ATR_PERIOD}, mult {ATR_MULT}) + SMA({SMA_LEN}) confirm",
    trailing_stop=TRAILING_STOP, min_hold_days=MIN_HOLD_DAYS,
    charts_dir=os.path.join(os.path.dirname(__file__), "..", "backtest_charts"),
)
