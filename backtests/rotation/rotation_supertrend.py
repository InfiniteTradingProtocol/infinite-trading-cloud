"""
rotation_supertrend.py
ETH/BTC/USDC rotation backtest using the SuperTrend + SMA-confirmation logic
from infinitetrading/src/strategies/superTrend.R (the production strategy
behind the "Bitcoin Alpha Vault" and "ETH Trading Bot" vaults).

Rotation rule:
  ETH/BTC bullish & BTC/USD bullish  -> hold ETH
  ETH/BTC bearish & BTC/USD bullish  -> hold BTC
  BTC/USD bearish:
      if ETH/USD bullish -> hold ETH
      else               -> hold USDC (cash)

Trend direction per pair is derived from the SAME SuperTrend signal logic
used in production (ATR period 100, multiplier 5, SMA 50, 1d timeframe),
applied independently to ETH-BTC, BTC-USD, and ETH-USD candles.

Run: python3 backtests/rotation/rotation_supertrend.py
"""
import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from rotation_engine import (
    fetch_coinbase_candles, resample_to_daily, calc_daily_returns,
    supertrend_signal, shift1, align_series, build_rotation_chart,
    run_rotation_backtest,
)

START = "2019-01-01"
ATR_PERIOD = 100
ATR_MULT = 5
SMA_LEN = 50

print("Fetching ETH-BTC, BTC-USD, ETH-USD daily candles from Coinbase...")
eth_btc = fetch_coinbase_candles("ETH-BTC", "1d", start=START)
btc_usd = fetch_coinbase_candles("BTC-USD", "1d", start=START)
eth_usd = fetch_coinbase_candles("ETH-USD", "1d", start=START)

sig_eth_btc = supertrend_signal(eth_btc["high"], eth_btc["low"], eth_btc["close"],
                                 ATR_PERIOD, ATR_MULT, SMA_LEN)
sig_btc_usd = supertrend_signal(btc_usd["high"], btc_usd["low"], btc_usd["close"],
                                 ATR_PERIOD, ATR_MULT, SMA_LEN)
sig_eth_usd = supertrend_signal(eth_usd["high"], eth_usd["low"], eth_usd["close"],
                                 ATR_PERIOD, ATR_MULT, SMA_LEN)

sig_eth_btc_shift = shift1(sig_eth_btc)
sig_btc_usd_shift = shift1(sig_btc_usd)
sig_eth_usd_shift = shift1(sig_eth_usd)

# Align all three signal series + eth/btc returns onto a common date index
common = sorted(set(eth_btc["date_d"]) & set(btc_usd["date_d"]) & set(eth_usd["date_d"]))
common = np.array(common)

def reindex(df, col, dates):
    s = df.set_index("date_d")[col]
    return s.reindex(dates).to_numpy()

eth_btc_bull = reindex(
    eth_btc.assign(sig=(sig_eth_btc_shift == "long")), "sig", common
).astype(bool)
btc_usd_bull = reindex(
    btc_usd.assign(sig=(sig_btc_usd_shift == "long")), "sig", common
).astype(bool)
eth_usd_bull = reindex(
    eth_usd.assign(sig=(sig_eth_usd_shift == "long")), "sig", common
).astype(bool)

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
holdings_aligned = pd_holdings = holdings  # already on `common`, same length/order

pct_eth = (holdings == "ETH").mean() * 100
pct_btc = (holdings == "BTC").mean() * 100
pct_usdc = (holdings == "USDC").mean() * 100

print("\n" + "=" * 60)
print(" SuperTrend Rotation Strategy — ETH / BTC / USDC")
print("=" * 60)
print(f"  Base signal   : SuperTrend(ATR {ATR_PERIOD}, mult {ATR_MULT}) + SMA({SMA_LEN}) confirm")
print(f"  Applied to    : ETH-BTC, BTC-USD, ETH-USD (independently)")
print(f"  Time in ETH   : {pct_eth:.1f}%")
print(f"  Time in BTC   : {pct_btc:.1f}%")
print(f"  Time in USDC  : {pct_usdc:.1f}%")
print("=" * 60 + "\n")

out_path = os.path.join(os.path.dirname(__file__), "..", "backtest_charts",
                         "rotation_supertrend.png")

metrics_btc = build_rotation_chart(
    dates_vec, rets_mat, primary_asset="BTC",
    title="SuperTrend Rotation (ETH/BTC/USDC) vs BTC",
    subtitle=f"Period {dates_vec.min().date()} to {dates_vec.max().date()} | "
             f"Time in ETH {pct_eth:.0f}% / BTC {pct_btc:.0f}% / USDC {pct_usdc:.0f}%",
    out_path=out_path.replace(".png", "_vs_btc.png"),
    signal_labels=holdings_aligned,
)
metrics_eth = build_rotation_chart(
    dates_vec, rets_mat, primary_asset="ETH",
    title="SuperTrend Rotation (ETH/BTC/USDC) vs ETH",
    subtitle=f"Period {dates_vec.min().date()} to {dates_vec.max().date()} | "
             f"Time in ETH {pct_eth:.0f}% / BTC {pct_btc:.0f}% / USDC {pct_usdc:.0f}%",
    out_path=out_path.replace(".png", "_vs_eth.png"),
    signal_labels=holdings_aligned,
)

print("\n========== PERFORMANCE METRICS (vs BTC) ==========")
print(metrics_btc.to_string(index=False))
print("\n========== PERFORMANCE METRICS (vs ETH) ==========")
print(metrics_eth.to_string(index=False))
