"""
rotation_v2_report.py
Shared reporting helper for the *_v2 rotation scripts (rotation_engine_v2
overlay). Does not modify any original strategy or engine file — purely
DRYs up the metrics/chart printing that's duplicated across
rotation_supertrend_v2.py / rotation_crossoverv2_v2.py /
rotation_crossoverv4_v2.py / rotation_btcstrat_v2.py.
"""
import os
import numpy as np

from rotation_engine import align_series, build_rotation_chart


def report(name, out_name, common, strat_ret, btc_ret, eth_ret, holdings,
           stop_events, base_signal_desc, trailing_stop, min_hold_days,
           charts_dir):
    series_input = {
        "Strategy": {"dates": common, "rets": strat_ret},
        "BTC": {"dates": common, "rets": btc_ret},
        "ETH": {"dates": common, "rets": eth_ret},
    }
    dates_vec, rets_mat = align_series(series_input)

    pct_eth = (holdings == "ETH").mean() * 100
    pct_btc = (holdings == "BTC").mean() * 100
    pct_usdc = (holdings == "USDC").mean() * 100
    n_switches = int((holdings[1:] != holdings[:-1]).sum())
    n_stops = int(stop_events.sum())

    print("\n" + "=" * 60)
    print(f" {name} — ETH / BTC / USDC (+stop +deadband)")
    print("=" * 60)
    print(f"  Base signal   : {base_signal_desc}")
    print(f"  Enhancement   : {trailing_stop*100:.0f}% trailing stop + {min_hold_days}-day switch deadband")
    print(f"  Time in ETH   : {pct_eth:.1f}%")
    print(f"  Time in BTC   : {pct_btc:.1f}%")
    print(f"  Time in USDC  : {pct_usdc:.1f}%")
    print(f"  Total switches: {n_switches}  (trailing-stop exits: {n_stops})")
    print("=" * 60 + "\n")

    out_path = os.path.join(charts_dir, out_name)
    subtitle = (f"Period {dates_vec.min().date()} to {dates_vec.max().date()} | "
                f"ETH {pct_eth:.0f}% / BTC {pct_btc:.0f}% / USDC {pct_usdc:.0f}% | "
                f"{n_switches} switches ({n_stops} stops)")

    metrics_btc = build_rotation_chart(
        dates_vec, rets_mat, primary_asset="BTC",
        title=f"{name} vs BTC", subtitle=subtitle,
        out_path=out_path.replace(".png", "_vs_btc.png"),
        signal_labels=holdings,
    )
    metrics_eth = build_rotation_chart(
        dates_vec, rets_mat, primary_asset="ETH",
        title=f"{name} vs ETH", subtitle=subtitle,
        out_path=out_path.replace(".png", "_vs_eth.png"),
        signal_labels=holdings,
    )

    print("\n========== PERFORMANCE METRICS (vs BTC) ==========")
    print(metrics_btc.to_string(index=False))
    print("\n========== PERFORMANCE METRICS (vs ETH) ==========")
    print(metrics_eth.to_string(index=False))
