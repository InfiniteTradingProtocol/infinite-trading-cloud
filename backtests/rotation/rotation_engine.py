"""
rotation_engine.py
Reusable Python backtesting engine for the ETH/BTC/USDC rotation strategy.

Mirrors the conventions of backtests/backtest_engine.R (R is unavailable in
this environment, so this is a from-scratch Python port covering only what
the rotation backtests need):

  - fetch_coinbase_candles()  -> paginated Coinbase Exchange OHLCV
  - resample_to_daily()       -> collapse intraday candles -> daily close
  - calc_daily_returns()      -> simple % daily return vector
  - ema / sma / rsi / atr     -> indicator helpers (TTR-equivalent)
  - supertrend()              -> SuperTrend line + trend flag
  - calc_metrics()            -> Sharpe / Sortino / Calmar / MaxDD / etc.
  - build_metrics_table()     -> combined metrics DataFrame
  - build_rotation_chart()    -> equity/drawdown/rolling-Sharpe PNG, dark theme

Rotation rule (per user spec):
  1. ETH/BTC bullish AND BTC/USDC bullish  -> hold ETH
  2. ETH/BTC bearish AND BTC/USDC bullish  -> hold BTC
  3. BTC/USDC bearish (regardless of ETH/BTC):
       -> if ETH/USD is itself bullish, hold ETH
       -> else hold USDC (cash)
All signals are shifted by 1 bar before being applied (no lookahead).
"""

import os
import time
import math
import requests
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

COINBASE_URL = "https://api.exchange.coinbase.com/products/{pair}/candles"

TIMEFRAME_SECONDS = {
    "1m": 60, "5m": 300, "15m": 900, "1h": 3600,
    "6h": 21600, "1d": 86400,
}


# ------------------------------------------------------------------
# fetch_coinbase_candles(pair, timeframe, start=None, end=None)
# ------------------------------------------------------------------
def fetch_coinbase_candles(pair, timeframe="1d", start=None, end=None,
                            sleep_secs=0.35, verbose=True):
    gran = TIMEFRAME_SECONDS[timeframe]
    end_dt = pd.Timestamp(end) if end else pd.Timestamp.utcnow().tz_localize(None)
    start_dt = pd.Timestamp(start) if start else (end_dt - pd.Timedelta(days=900))

    all_rows = []
    cur_end = end_dt
    max_candles_per_req = 300

    while cur_end > start_dt:
        cur_start = cur_end - pd.Timedelta(seconds=gran * max_candles_per_req)
        if cur_start < start_dt:
            cur_start = start_dt

        params = {
            "granularity": gran,
            "start": cur_start.strftime("%Y-%m-%dT%H:%M:%S"),
            "end": cur_end.strftime("%Y-%m-%dT%H:%M:%S"),
        }
        url = COINBASE_URL.format(pair=pair)
        resp = requests.get(url, params=params, timeout=30)
        if resp.status_code != 200:
            if verbose:
                print(f"  ! {pair} fetch failed ({resp.status_code}) for "
                      f"{cur_start.date()}..{cur_end.date()}")
            break
        data = resp.json()
        if not isinstance(data, list) or len(data) == 0:
            cur_end = cur_start
            time.sleep(sleep_secs)
            continue

        for row in data:
            t, low, high, open_, close, vol = row
            all_rows.append({
                "time": pd.to_datetime(t, unit="s", utc=True).tz_localize(None),
                "low": low, "high": high, "open": open_,
                "close": close, "volume": vol,
            })

        cur_end = cur_start
        time.sleep(sleep_secs)

    if not all_rows:
        raise RuntimeError(f"No candle data returned for {pair} {timeframe}")

    df = pd.DataFrame(all_rows).drop_duplicates(subset="time").sort_values("time")
    df = df[df["time"] >= start_dt].reset_index(drop=True)
    df["date_d"] = df["time"].dt.normalize()
    if verbose:
        print(f"  fetched {pair} {timeframe}: {len(df)} candles "
              f"({df['date_d'].min().date()} -> {df['date_d'].max().date()})")
    return df


def resample_to_daily(df):
    out = df.groupby("date_d", as_index=False)["close"].last()
    return out.sort_values("date_d").reset_index(drop=True)


def calc_daily_returns(close):
    close = np.asarray(close, dtype=float)
    rets = np.zeros_like(close)
    rets[1:] = np.diff(close) / close[:-1]
    return rets


# ------------------------------------------------------------------
# Indicators
# ------------------------------------------------------------------
def ema(series, n):
    return pd.Series(series).ewm(span=n, adjust=False).mean().to_numpy()


def sma(series, n):
    return pd.Series(series).rolling(n).mean().to_numpy()


def rsi(series, n=14):
    s = pd.Series(series, dtype=float)
    delta = s.diff()
    gain = delta.clip(lower=0)
    loss = -delta.clip(upper=0)
    avg_gain = gain.ewm(alpha=1 / n, adjust=False, min_periods=n).mean()
    avg_loss = loss.ewm(alpha=1 / n, adjust=False, min_periods=n).mean()
    rs = avg_gain / avg_loss
    out = 100 - (100 / (1 + rs))
    out[avg_loss == 0] = 100
    return out.to_numpy()


def atr(high, low, close, n=14):
    high = pd.Series(high, dtype=float)
    low = pd.Series(low, dtype=float)
    close = pd.Series(close, dtype=float)
    prev_close = close.shift(1)
    tr = pd.concat([
        high - low,
        (high - prev_close).abs(),
        (low - prev_close).abs(),
    ], axis=1).max(axis=1)
    return tr.ewm(alpha=1 / n, adjust=False, min_periods=n).mean().to_numpy()


def supertrend(high, low, close, atr_period=100, multiplier=5):
    """Replicates infinitetrading/src/strategies/superTrend.R exactly."""
    high = np.asarray(high, dtype=float)
    low = np.asarray(low, dtype=float)
    close = np.asarray(close, dtype=float)
    n = len(close)

    atr_vals = atr(high, low, close, n=atr_period)
    hl2 = (high + low) / 2
    upper_band = hl2 + multiplier * atr_vals
    lower_band = hl2 - multiplier * atr_vals

    st = np.full(n, np.nan)
    trend_up = np.full(n, True)

    for j in range(1, n):
        prev_st = st[j - 1] if not np.isnan(st[j - 1]) else lower_band[j - 1]
        if close[j] > prev_st:
            trend_up[j] = True
        elif close[j] < prev_st:
            trend_up[j] = False
        else:
            trend_up[j] = trend_up[j - 1]
        st[j] = max(lower_band[j], prev_st) if trend_up[j] else min(upper_band[j], prev_st)

    return st, trend_up


def supertrend_signal(high, low, close, atr_period=100, multiplier=5, sma_len=50):
    """
    Full SuperTrend + SMA-confirmation entry/exit logic (mirrors superTrend.R).
    Returns a "long"/"neutral" numpy array (not yet shifted for lookahead).
    """
    close = np.asarray(close, dtype=float)
    n = len(close)
    st, trend_up = supertrend(high, low, close, atr_period, multiplier)
    sma_vals = sma(close, sma_len)

    is_uptrend = close > sma_vals
    # 2-bar confirmation
    up_confirmed = np.full(n, False)
    down_confirmed = np.full(n, False)
    for j in range(1, n):
        up_confirmed[j] = bool(is_uptrend[j]) and bool(is_uptrend[j - 1])
        down_confirmed[j] = (not is_uptrend[j]) and (not is_uptrend[j - 1])

    in_uptrend_state = False
    sig = np.full(n, "neutral", dtype=object)
    position = "neutral"

    for j in range(1, n):
        new_uptrend = up_confirmed[j] and not in_uptrend_state
        if up_confirmed[j]:
            in_uptrend_state = True
        elif down_confirmed[j]:
            in_uptrend_state = False

        enter_new_uptrend = new_uptrend
        enter_supertrend = (close[j] > st[j]) and (close[j - 1] <= st[j - 1]) and in_uptrend_state
        exit_supertrend = (close[j] < st[j]) and (close[j - 1] >= st[j - 1])
        exit_downtrend = down_confirmed[j]

        if enter_new_uptrend or enter_supertrend:
            position = "long"
        if exit_supertrend or exit_downtrend:
            position = "neutral"

        sig[j] = position

    return sig


def ema_consensus_signal(close_intraday, fast_range, slow_range):
    """Returns fraction of bullish EMA(f,s) combos per bar (0..1)."""
    combos = [(f, s) for f in fast_range for s in slow_range]
    votes = np.zeros((len(close_intraday), len(combos)))
    for k, (f, s) in enumerate(combos):
        ef = ema(close_intraday, f)
        es = ema(close_intraday, s)
        votes[:, k] = (ef > es).astype(int)
    return votes.mean(axis=1)


def shift1(arr, fill="neutral"):
    """Shift signal forward by 1 bar to avoid lookahead."""
    out = np.empty_like(arr)
    out[0] = fill
    out[1:] = arr[:-1]
    return out


# ------------------------------------------------------------------
# Metrics
# ------------------------------------------------------------------
def calc_metrics(rets, label):
    rets = np.asarray(rets, dtype=float)
    n_days = len(rets)
    total_ret = np.prod(1 + rets) - 1
    ann_ret = (1 + total_ret) ** (252 / n_days) - 1
    ann_vol = np.std(rets, ddof=1) * math.sqrt(252)
    sharpe = ann_ret / ann_vol if ann_vol else np.nan
    downside = rets[rets < 0]
    down_std = np.std(downside, ddof=1) * math.sqrt(252) if len(downside) > 1 else np.nan
    sortino = ann_ret / down_std if down_std else np.nan
    cum_curve = np.cumprod(1 + rets)
    max_dd = np.min(cum_curve / np.maximum.accumulate(cum_curve) - 1)
    win_rate = np.mean(rets > 0)
    calmar = ann_ret / abs(max_dd) if max_dd else np.nan

    return pd.DataFrame({
        "Metric": ["Total Return", "Ann. Return", "Ann. Volatility",
                   "Sharpe Ratio", "Sortino Ratio", "Calmar Ratio",
                   "Max Drawdown", "Win Rate"],
        label: [
            f"{total_ret * 100:+.1f}%",
            f"{ann_ret * 100:+.1f}%",
            f"{ann_vol * 100:.1f}%",
            f"{sharpe:.2f}",
            f"{sortino:.2f}",
            f"{calmar:.2f}",
            f"{max_dd * 100:.1f}%",
            f"{win_rate * 100:.1f}%",
        ],
    })


def build_metrics_table(rets_dict):
    tables = [calc_metrics(v, k) for k, v in rets_dict.items()]
    out = tables[0]
    for t in tables[1:]:
        out = out.merge(t, on="Metric")
    return out


def align_series(named_dict):
    """named_dict: {name: {"dates": DatetimeIndex-like, "rets": array}}"""
    date_sets = [pd.DatetimeIndex(v["dates"]) for v in named_dict.values()]
    common = date_sets[0]
    for d in date_sets[1:]:
        common = common.intersection(d)
    common = common.sort_values()

    rets_mat = {}
    for name, v in named_dict.items():
        s = pd.Series(np.asarray(v["rets"], dtype=float), index=pd.DatetimeIndex(v["dates"]))
        rets_mat[name] = s.reindex(common).to_numpy()
    return common, rets_mat


# ------------------------------------------------------------------
# Chart
# ------------------------------------------------------------------
DARK_BG = "#0D1117"
PANEL_BG = "#0D1117"
GRID_COLOR = "#1E2A38"
TEXT_COLOR = "#C9D1D9"
MUTED = "#8B949E"

DEFAULT_PALETTE = {
    "Strategy": "#00E5FF",
    "BTC": "#F7931A",
    "ETH": "#627EEA",
    "USDC": "#2EA043",
}


def _dd_vec(rets):
    c = np.cumprod(1 + np.asarray(rets, dtype=float))
    return c / np.maximum.accumulate(c) - 1


def _roll_sharpe(rets, win=90):
    s = pd.Series(rets, dtype=float)
    roll_mean = s.rolling(win).mean()
    roll_std = s.rolling(win).std()
    return (roll_mean / roll_std * math.sqrt(252)).to_numpy()


def _style_axis(ax):
    ax.set_facecolor(PANEL_BG)
    ax.grid(color=GRID_COLOR, linewidth=0.5)
    ax.tick_params(colors=MUTED, labelsize=8)
    for spine in ax.spines.values():
        spine.set_color(GRID_COLOR)
    ax.xaxis.label.set_color(TEXT_COLOR)
    ax.yaxis.label.set_color(TEXT_COLOR)
    ax.title.set_color("#FFFFFF")


def build_rotation_chart(dates, rets_dict, primary_asset, title, subtitle, out_path,
                          palette=None, signal_labels=None):
    """
    Builds a 4-panel dark chart (equity, drawdown vs primary, rolling Sharpe,
    metrics table) and saves PNG. Returns the metrics DataFrame.
    """
    pal = dict(DEFAULT_PALETTE)
    if palette:
        pal.update(palette)

    fig = plt.figure(figsize=(13, 15), facecolor=DARK_BG)
    gs = fig.add_gridspec(4, 1, height_ratios=[2.2, 1.6, 1.4, 1.6], hspace=0.45)

    # Panel 1: Equity curves (log scale, growth x1)
    ax1 = fig.add_subplot(gs[0])
    for name, rets in rets_dict.items():
        eq = np.cumprod(1 + np.nan_to_num(rets, nan=0.0))
        ax1.plot(dates, eq, label=name, linewidth=1.4,
                 color=pal.get(name, "#A8DADC"))
    ax1.set_yscale("log")
    ax1.set_title(f"{title}\n", fontsize=13, fontweight="bold", loc="left", color="#FFFFFF")
    ax1.text(0, 1.06, subtitle, transform=ax1.transAxes, fontsize=8, color=MUTED)
    ax1.set_ylabel("Growth (x1 start)")
    ax1.legend(facecolor="#161B22", edgecolor=GRID_COLOR, labelcolor=TEXT_COLOR, fontsize=8)
    _style_axis(ax1)

    # Panel 2: Drawdown vs primary asset
    ax2 = fig.add_subplot(gs[1])
    dd_strategy = _dd_vec(rets_dict["Strategy"]) * 100
    dd_primary = _dd_vec(rets_dict[primary_asset]) * 100
    ax2.fill_between(dates, dd_strategy, 0, color=pal["Strategy"], alpha=0.35, label="Strategy")
    ax2.plot(dates, dd_strategy, color=pal["Strategy"], linewidth=0.8)
    ax2.fill_between(dates, dd_primary, 0, color=pal.get(primary_asset, "#A8DADC"), alpha=0.25, label=primary_asset)
    ax2.plot(dates, dd_primary, color=pal.get(primary_asset, "#A8DADC"), linewidth=0.8)
    ax2.set_title(f"Drawdown — Strategy vs {primary_asset}", fontsize=10, loc="left")
    ax2.set_ylabel("Drawdown (%)")
    ax2.legend(facecolor="#161B22", edgecolor=GRID_COLOR, labelcolor=TEXT_COLOR, fontsize=8)
    _style_axis(ax2)

    # Panel 3: Rotation state (which asset held)
    ax3 = fig.add_subplot(gs[2])
    if signal_labels is not None:
        state_map = {"ETH": 2, "BTC": 1, "USDC": 0}
        y = [state_map.get(s, 0) for s in signal_labels]
        ax3.step(dates, y, where="post", color="#00E5FF", linewidth=1.0)
        ax3.set_yticks([0, 1, 2])
        ax3.set_yticklabels(["USDC", "BTC", "ETH"])
        ax3.set_title("Rotation State Held", fontsize=10, loc="left")
    _style_axis(ax3)

    # Panel 4: Rolling 90d Sharpe
    ax4 = fig.add_subplot(gs[3])
    ax4.plot(dates, _roll_sharpe(rets_dict["Strategy"]), color=pal["Strategy"], linewidth=1.0, label="Strategy")
    ax4.plot(dates, _roll_sharpe(rets_dict[primary_asset]), color=pal.get(primary_asset, "#A8DADC"), linewidth=1.0, label=primary_asset)
    ax4.axhline(0, color=MUTED, linestyle="--", linewidth=0.7)
    ax4.axhline(1, color="#2EA043", linestyle=":", linewidth=0.7)
    ax4.set_title("Rolling 90-Day Sharpe Ratio", fontsize=10, loc="left")
    ax4.set_ylabel("Sharpe")
    ax4.legend(facecolor="#161B22", edgecolor=GRID_COLOR, labelcolor=TEXT_COLOR, fontsize=8)
    _style_axis(ax4)

    for ax in (ax1, ax2, ax3, ax4):
        ax.xaxis.set_major_locator(mdates.MonthLocator(interval=3))
        ax.xaxis.set_major_formatter(mdates.DateFormatter("%b %y"))
        plt.setp(ax.get_xticklabels(), rotation=35, ha="right")

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    fig.savefig(out_path, facecolor=DARK_BG, dpi=140, bbox_inches="tight")
    plt.close(fig)

    metrics = build_metrics_table(rets_dict)
    print(f"chart saved -> {out_path}")
    return metrics


# ------------------------------------------------------------------
# Rotation backtest core
# ------------------------------------------------------------------
def run_rotation_backtest(eth_btc_bull, btc_usd_bull, eth_usd_bull,
                           eth_ret, btc_ret, commission_pct=0.003):
    """
    Applies the 3-way rotation rule bar-by-bar (signals already shifted by
    caller to avoid lookahead) and returns (strategy_rets, holding_labels).

    Rule:
      ETH/BTC bull & BTC/USD bull        -> ETH
      ETH/BTC bear & BTC/USD bull        -> BTC
      BTC/USD bear:
          if ETH/USD bull -> ETH
          else            -> USDC (cash)
    """
    n = len(eth_btc_bull)
    holdings = np.empty(n, dtype=object)
    for i in range(n):
        if btc_usd_bull[i]:
            holdings[i] = "ETH" if eth_btc_bull[i] else "BTC"
        else:
            holdings[i] = "ETH" if eth_usd_bull[i] else "USDC"

    rets = np.zeros(n)
    prev_holding = None
    for i in range(n):
        h = holdings[i]
        base_ret = eth_ret[i] if h == "ETH" else (btc_ret[i] if h == "BTC" else 0.0)
        comm = commission_pct if (prev_holding is not None and h != prev_holding) else 0.0
        rets[i] = base_ret - comm
        prev_holding = h

    return rets, holdings
