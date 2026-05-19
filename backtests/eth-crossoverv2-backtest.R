# ============================================================
# eth-crossoverv2-backtest.R
# ETH-USD EMA Crossover v2 Strategy Backtest
#
# Strategy Parameters (same as crossOverV2 production):
#   - EMA grid: fast 9-13, slow 29-33 (25 combos)
#   - Threshold: 60% bullish consensus
#   - SMA(50) trend filter
#   - RSI(14) > 45 momentum guard
#   - 8% trailing stop below rolling peak
#   - 5% recovery above stop price for re-entry
#   - 3 bar cooldown after stop-out
#
# Benchmarks: BTC (buy & hold), ETH (buy & hold)
#
# Run: Rscript backtests/eth-crossoverv2-backtest.R
# ============================================================

source(file.path(dirname(normalizePath(
  ifelse(interactive(), "backtests/eth-crossoverv2-backtest.R",
         commandArgs(trailingOnly = FALSE) |>
           (\(a) a[startsWith(a, "--file=")])() |>
           (\(a) if (length(a)) sub("--file=", "", a) else "backtests/eth-crossoverv2-backtest.R")())
)), "backtest_engine.R"), local = TRUE)

# ── 1. Config ──────────────────────────────────────────────
PAIR             <- "ETH-USD"
TIMEFRAME        <- "6h"
BENCHMARKS       <- c("BTC-USD", "ETH-USD")

V2_THRESHOLD     <- 0.60
V2_SMA_PERIOD    <- 50
V2_RSI_PERIOD    <- 14
V2_RSI_MIN       <- 45
V2_TRAILING_STOP <- 0.08
V2_REENTRY_PCT   <- 0.05
V2_COOLDOWN_BARS <- 3

EMA_FAST         <- c(9, 10, 11, 12, 13)
EMA_SLOW         <- c(29, 30, 31, 32, 33)

# ── 2. Fetch data ──────────────────────────────────────────
cat(sprintf("Fetching %s %s from Coinbase...\n", PAIR, TIMEFRAME))
raw_6h      <- fetch_coinbase_candles(PAIR, TIMEFRAME)
start_date  <- as.character(min(raw_6h$date_d))
asset_daily <- resample_to_daily(raw_6h)

benchmarks <- lapply(BENCHMARKS, function(p) {
  cat(sprintf("Fetching %s 1D from Coinbase...\n", p))
  fetch_coinbase_candles(p, "1d", start = start_date)
})
names(benchmarks) <- sub("-USD", "", BENCHMARKS)

# ── 3. Build v2 signal ─────────────────────────────────────
close_6h  <- raw_6h$close
n_combos  <- length(EMA_FAST) * length(EMA_SLOW)

votes <- matrix(0L, nrow = length(close_6h), ncol = n_combos)
col   <- 1
for (f in EMA_FAST) {
  for (s in EMA_SLOW) {
    ef <- EMA(close_6h, n = f)
    es <- EMA(close_6h, n = s)
    votes[, col] <- ifelse(!is.na(ef) & !is.na(es) & ef > es, 1L, 0L)
    col <- col + 1
  }
}
prob_6h <- rowSums(votes) / n_combos

# Aggregate 6H probability to daily (last bar of day)
raw_6h$prob <- prob_6h
prob_daily <- raw_6h %>%
  group_by(date_d) %>%
  summarise(prob = last(prob), .groups = "drop") %>%
  arrange(date_d)

# Daily filters
close_daily <- asset_daily$close
sma50       <- SMA(close_daily, n = V2_SMA_PERIOD)
rsi14       <- RSI(close_daily, n = V2_RSI_PERIOD)

sig_v2_raw <- ifelse(
  prob_daily$prob >= V2_THRESHOLD &
  close_daily     > sma50         &
  rsi14           > V2_RSI_MIN,
  "long", "neutral"
)
sig_v2_raw[is.na(sig_v2_raw)] <- "neutral"

# 1-day lookahead prevention
sig_v2_shifted <- c("neutral", head(sig_v2_raw, -1))

# ── 4. Return vectors ──────────────────────────────────────
asset_ret <- calc_daily_returns(asset_daily$close)

ret_v2 <- run_backtest_with_stops(
  signal_vec        = sig_v2_shifted,
  close_vec         = asset_daily$close,
  trailing_stop_pct = V2_TRAILING_STOP,
  reentry_pct       = V2_REENTRY_PCT,
  cooldown_bars     = V2_COOLDOWN_BARS
)

bench_rets  <- lapply(benchmarks, function(b) calc_daily_returns(b$close))
bench_dates <- lapply(benchmarks, function(b) b$date_d)

# ── 5. Align all series ────────────────────────────────────
series_input <- list(
  "Strategy" = list(dates = asset_daily$date_d, rets = ret_v2),
  "ETH"      = list(dates = asset_daily$date_d, rets = asset_ret),
  "BTC"      = list(dates = benchmarks$BTC$date_d, rets = bench_rets$BTC)
)

aligned   <- align_series(series_input)
dates_vec <- aligned$dates
rets_mat  <- aligned$rets

rets_list <- lapply(colnames(rets_mat), function(n) rets_mat[, n])
names(rets_list) <- colnames(rets_mat)

# Price & signal for chart panels
price_aligned  <- asset_daily$close[asset_daily$date_d %in% dates_vec]
signal_aligned <- sig_v2_shifted[asset_daily$date_d %in% dates_vec]

# ── 6. Print parameter summary ─────────────────────────────
cat("\n══════════════════════════════════════════\n")
cat(" ETH crossOverV2 Strategy Parameters\n")
cat("══════════════════════════════════════════\n")
cat(sprintf("  Asset         : %s\n", PAIR))
cat(sprintf("  EMA grid      : fast %d-%d, slow %d-%d (%d combos)\n",
            min(EMA_FAST), max(EMA_FAST), min(EMA_SLOW), max(EMA_SLOW), n_combos))
cat(sprintf("  Threshold     : >= %.0f%% bullish combos\n", V2_THRESHOLD * 100))
cat(sprintf("  Trend filter  : close > SMA(%d)\n", V2_SMA_PERIOD))
cat(sprintf("  RSI guard     : RSI(%d) > %d\n", V2_RSI_PERIOD, V2_RSI_MIN))
cat(sprintf("  Trailing stop : %.0f%% below rolling peak\n", V2_TRAILING_STOP * 100))
cat(sprintf("  Re-entry      : price recovers %.0f%% above stop-out + %d bar cooldown\n",
            V2_REENTRY_PCT * 100, V2_COOLDOWN_BARS))
cat("══════════════════════════════════════════\n\n")

# ── 7. Build chart ─────────────────────────────────────────
script_dir <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile)),
                       error = function(e) getwd())
out_path <- file.path(script_dir, "backtest_charts",
  sprintf("eth_crossoverv2_%s.png", format(Sys.Date(), "%Y%m%d")))

custom_pal <- c(
  "Strategy" = "#00E5FF",
  "ETH"      = "#627EEA",
  "BTC"      = "#F7931A"
)

metrics <- build_chart(
  dates_vec     = dates_vec,
  rets_list     = rets_list,
  primary_asset = "ETH",
  price_vec     = price_aligned,
  signal_vec    = signal_aligned,
  title         = "ETH-USD EMA Crossover v2 — Strategy Backtest",
  subtitle      = sprintf(
    "Period: %s to %s  |  60%% EMA threshold + SMA(50) + RSI>45 + 8%% trailing stop  |  Benchmarks: ETH & BTC",
    format(min(dates_vec), "%d %b %Y"), format(max(dates_vec), "%d %b %Y")
  ),
  out_path  = out_path,
  palette   = custom_pal
)

cat("\n========== PERFORMANCE METRICS ==========\n")
print(metrics, row.names = FALSE)
cat(sprintf("\n✅ Chart → %s\n", out_path))
