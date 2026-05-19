# Shim — redirects to the shared fetcher in backtests/data/
# This file exists so the backtest_engine.R path-detection works
# when this strategy is run from the project root.
source("backtests/data/fetch_coinbase_candles.R")
