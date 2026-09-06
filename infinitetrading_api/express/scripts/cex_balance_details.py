#!/usr/bin/env python3
"""
scripts/cex_balance_details.py — Python port of the CCXT half of R's
`get_cex_balance_details()` (infinitetrading/src/api/helpers/cex_helpers.R),
called by express/src/utils/cexBalance.ts for the ported
GET /getAllCEXSubaccounts endpoint.

R reached CCXT through reticulate (i.e. this same Python CCXT install, 4.5.x).
There is no CCXT package in the Node dependency tree, so rather than add a new
heavyweight dependency mid-migration this keeps using the exact same library
and version the R path used, which is also what preserves behavioural parity.

Credentials are passed on STDIN as JSON (never argv, so they cannot leak into
the process table) and the result is written to STDOUT as JSON.

Input : {"exchange","api_key","secret","passphrase"}
Output: {"assets":[{currency,free,used,total,usd_value,price}],"total_usd":N}

Parity notes (mirroring the R implementation exactly):
  - Stablecoins USD/USDC/USDT/DAI/BUSD/FDUSD/TUSD are priced at $1.
  - Other assets: try <CUR>/USDT ticker, then <CUR>/USD; on failure price and
    usd_value are both 0 but the asset is still listed.
  - Assets with total <= 0 are skipped.
  - Coinbase "Cloud" keys (organizations/.../apiKeys/...) bypass CCXT and use
    the coinbase-advanced-py helper at /home/ubuntu/coinbase_cloud_balance.py,
    falling back to CCXT if that file is absent.
  - Any error yields an empty {assets: [], total_usd: 0} rather than raising,
    matching R's tryCatch fallbacks, so one broken subaccount cannot take down
    the whole listing.
"""

import json
import os
import re
import sys

STABLECOINS = {"USD", "USDC", "USDT", "DAI", "BUSD", "FDUSD", "TUSD"}
EMPTY = {"assets": [], "total_usd": 0}


def _num(v):
    try:
        f = float(v)
        return f if f == f else 0.0  # NaN -> 0
    except (TypeError, ValueError):
        return 0.0


def _coinbase_cloud_balance(api_key, secret):
    """Mirror R's branch that calls /home/ubuntu/coinbase_cloud_balance.py."""
    helper_dir = "/home/ubuntu"
    if not os.path.exists(os.path.join(helper_dir, "coinbase_cloud_balance.py")):
        return None
    if helper_dir not in sys.path:
        sys.path.insert(0, helper_dir)
    import coinbase_cloud_balance  # type: ignore

    result = coinbase_cloud_balance.get_coinbase_cloud_balances(api_key, secret)
    if not result or not result.get("success"):
        return None

    total, free, used = {}, {}, {}
    for a in result.get("assets") or []:
        cur = a["currency"]
        total[cur] = a.get("total")
        free[cur] = a.get("available")
        used[cur] = a.get("hold")
    return {"total": total, "free": free, "used": used}


def main():
    try:
        req = json.load(sys.stdin)
    except Exception:
        json.dump(EMPTY, sys.stdout)
        return

    exchange = (req.get("exchange") or "").strip()
    api_key = req.get("api_key") or ""
    secret = req.get("secret") or ""
    passphrase = req.get("passphrase") or None

    if not exchange or not api_key or not secret:
        json.dump(EMPTY, sys.stdout)
        return

    try:
        import ccxt
    except Exception:
        json.dump(EMPTY, sys.stdout)
        return

    is_cloud = exchange == "coinbase" and bool(re.match(r"^organizations/.*/apiKeys/", api_key))

    try:
        klass = getattr(ccxt, exchange)
    except AttributeError:
        json.dump(EMPTY, sys.stdout)
        return

    try:
        cfg = {"apiKey": api_key, "secret": secret}
        if not is_cloud and passphrase:
            cfg["password"] = passphrase
        exchange_obj = klass(cfg)
    except Exception:
        json.dump(EMPTY, sys.stdout)
        return

    balance = None
    if is_cloud:
        try:
            balance = _coinbase_cloud_balance(api_key, secret)
        except Exception:
            balance = None
    if balance is None:
        try:
            balance = exchange_obj.fetch_balance()
        except Exception:
            balance = {"total": {}, "free": {}, "used": {}}

    totals = balance.get("total") or {}
    frees = balance.get("free") or {}
    useds = balance.get("used") or {}

    assets = []
    total_usd = 0.0

    for currency in list(totals.keys()):
        total_amount = _num(totals.get(currency))
        if total_amount <= 0:
            continue

        price = 0.0
        usd_value = 0.0

        if currency in STABLECOINS:
            price = 1.0
            usd_value = total_amount
        else:
            for quote in ("USDT", "USD"):
                try:
                    ticker = exchange_obj.fetch_ticker(f"{currency}/{quote}")
                    p = _num((ticker or {}).get("last"))
                    if p > 0:
                        price = p
                        usd_value = total_amount * p
                        break
                except Exception:
                    continue

        assets.append(
            {
                "currency": currency,
                "free": _num(frees.get(currency)),
                "used": _num(useds.get(currency)),
                "total": total_amount,
                "usd_value": usd_value,
                "price": price,
            }
        )

        if usd_value > 0:
            total_usd += usd_value

    json.dump({"assets": assets, "total_usd": total_usd}, sys.stdout)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        json.dump(EMPTY, sys.stdout)
