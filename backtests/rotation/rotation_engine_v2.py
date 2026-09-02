"""
rotation_engine_v2.py
Additive enhancement layer on top of rotation_engine.py — does NOT modify
rotation_engine.py or any of the original strategy signal files. This
module only adds a new rotation backtest function with:

  1. Per-leg trailing stop: forces an exit to USDC if the currently held
     asset (ETH or BTC) drops more than `trailing_stop_pct` from its
     rolling peak since entry, regardless of what the trend signal says.
     This directly targets the "rides the loss until the lagging trend
     signal finally confirms" problem seen in the original rotation runs.

  2. Switch deadband (min_hold_days): a new target asset must be signalled
     for `min_hold_days` consecutive days before the strategy actually
     switches into it. This filters out single/short-lived signal flips
     that were shown to be followed by a net loss ~59% of the time.

  A stop-out always executes immediately (safety first) and is exempt
  from the deadband; only voluntary rotation switches are debounced.

Original strategy files (superTrend.R equivalent, EMA v2/v4, BTCStrat
signal builders) are unchanged and still used as-is to generate the
underlying bullish/bearish signals — only the position-management layer
on top is different here.
"""
import numpy as np


def run_rotation_backtest_v2(eth_btc_bull, btc_usd_bull, eth_usd_bull,
                              eth_ret, btc_ret, eth_close, btc_close,
                              trailing_stop_pct=0.15,
                              min_hold_days=5,
                              commission_pct=0.003):
    """
    Same 3-way rotation rule as run_rotation_backtest(), plus:
      - forced stop-out to USDC on a trailing-stop breach
      - a min_hold_days deadband before acting on a new target signal

    Returns (rets, holdings, stop_events) where stop_events is a boolean
    array marking bars where the trailing stop fired (for diagnostics).
    """
    n = len(eth_btc_bull)
    holdings = np.empty(n, dtype=object)
    rets = np.zeros(n)
    stop_events = np.zeros(n, dtype=bool)

    held = "USDC"
    peak = None
    pending_target = None
    pending_count = 0
    cooldown_days = 0   # short cooldown after a stop-out before re-entering

    for i in range(n):
        # ── desired target per the rotation rule ──
        if btc_usd_bull[i]:
            desired = "ETH" if eth_btc_bull[i] else "BTC"
        else:
            desired = "ETH" if eth_usd_bull[i] else "USDC"

        price = eth_close[i] if held == "ETH" else (btc_close[i] if held == "BTC" else None)

        stopped_this_bar = False

        # ── trailing stop check on current holding ──
        if held != "USDC":
            if peak is None or price > peak:
                peak = price
            if price < peak * (1 - trailing_stop_pct):
                held = "USDC"
                peak = None
                pending_target = None
                pending_count = 0
                stopped_this_bar = True
                stop_events[i] = True
                cooldown_days = min_hold_days  # avoid instant re-entry chop

        # ── deadband logic for voluntary switches ──
        if not stopped_this_bar:
            if cooldown_days > 0:
                cooldown_days -= 1
            else:
                if desired == held:
                    pending_target = None
                    pending_count = 0
                else:
                    if desired == pending_target:
                        pending_count += 1
                    else:
                        pending_target = desired
                        pending_count = 1

                    if pending_count >= min_hold_days:
                        held = desired
                        pending_target = None
                        pending_count = 0
                        peak = eth_close[i] if held == "ETH" else (btc_close[i] if held == "BTC" else None)

        holdings[i] = held

        # ── bar return + commission on any change vs previous holding ──
        base_ret = eth_ret[i] if held == "ETH" else (btc_ret[i] if held == "BTC" else 0.0)
        prev_holding = holdings[i - 1] if i > 0 else "USDC"
        comm = commission_pct if held != prev_holding else 0.0
        rets[i] = base_ret - comm

    return rets, holdings, stop_events
