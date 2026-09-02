"""
dual_mode_signal.py
Shared dual-mode (trend + accumulation) signal builder used by both
rotation_crossoverv4.py and rotation_btcstrat.py — mirrors the logic in
backtests/btc-crossoverv4-backtest.R / backtests/btc-btcstrat-backtest.R.

TREND mode   : EMA-grid consensus + SMA + RSI momentum guard (6h bars).
ACCUMULATION mode : deep-drawdown + oversold + bounce-confirmed dip buy
                    (daily bars), joined onto the 6h series lagged by 1 day.

Produces a single "long"/"neutral" combined daily signal (trend OR accum),
used as one pair's bullish/bearish state in the rotation engine.
"""
import os
import sys
import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(__file__))
from rotation_engine import (
    fetch_coinbase_candles, resample_to_daily, ema_consensus_signal, sma, rsi,
)


def build_dual_mode_daily_signal(pair, start, params):
    """
    params: dict with keys
      threshold, sma_period, rsi_period, rsi_min,
      accum_drawdown, accum_rsi_max, accum_bounce,
      accum_high_days, accum_low_days, ema_fast, ema_slow
    Returns a DataFrame with columns: date_d, close, sig (combined "long"/"neutral")
    """
    raw = fetch_coinbase_candles(pair, "6h", start=start)
    daily = resample_to_daily(raw)

    prob_6h = ema_consensus_signal(raw["close"].to_numpy(), params["ema_fast"], params["ema_slow"])

    close_d = daily["close"].to_numpy()
    n_daily = len(close_d)
    sma_vals = sma(close_d, params["sma_period"])
    rsi_vals = rsi(close_d, params["rsi_period"])

    high_nd = params["accum_high_days"]
    low_nd = params["accum_low_days"]
    rolling_high = np.array([
        np.max(close_d[max(0, i - high_nd + 1):i + 1]) for i in range(n_daily)
    ])
    rolling_low = np.array([
        np.min(close_d[max(0, i - low_nd + 1):i + 1]) for i in range(n_daily)
    ])

    accum_raw = np.where(
        ((rolling_high - close_d) / rolling_high >= params["accum_drawdown"]) &
        (rsi_vals < params["accum_rsi_max"]) &
        ((close_d - rolling_low) / rolling_low >= params["accum_bounce"]),
        "long", "neutral"
    )
    accum_raw = np.where(pd.isna(accum_raw), "neutral", accum_raw)

    daily_filters = pd.DataFrame({
        "date_d": daily["date_d"], "sma": sma_vals, "rsi": rsi_vals,
        "daily_close": close_d, "accum_sig": accum_raw,
    })
    # lag daily filters by 1 day (no lookahead onto same-day 6h bars)
    daily_filters_lagged = daily_filters.copy()
    daily_filters_lagged["date_d"] = daily_filters_lagged["date_d"] + pd.Timedelta(days=1)

    raw = raw.assign(prob=prob_6h).merge(daily_filters_lagged, on="date_d", how="left")
    sig_trend = np.where(
        (raw["prob"] >= params["threshold"]) &
        (raw["daily_close"] > raw["sma"]) &
        (raw["rsi"] > params["rsi_min"]),
        "long", "neutral"
    )
    sig_trend = np.where(pd.isna(sig_trend), "neutral", sig_trend)
    sig_accum = np.where(pd.isna(raw["accum_sig"]), "neutral", raw["accum_sig"])

    combined_6h = np.where((sig_trend == "long") | (sig_accum == "long"), "long", "neutral")
    raw = raw.assign(combined=combined_6h)

    daily_signal = raw.groupby("date_d", as_index=False)["combined"].last()
    out = daily.merge(daily_signal, on="date_d", how="left")
    out["sig"] = out["combined"].fillna("neutral")
    return out[["date_d", "close", "sig"]]
