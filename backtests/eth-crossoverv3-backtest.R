# ============================================================
# eth-crossoverv3-backtest.R
# ETH-USD EMA Crossover v3 Strategy Backtest
#
# Strategy Parameters:
#   - EMA grid: fast 9-13, slow 29-33 (25 combos)
#   - Threshold: 60% bullish consensus
#   - SMA(50) trend filter
#   - RSI(14) > 45 momentum guard
#   - 8% trailing stop below rolling peak
#   - Re-entry reference decays: min(stop_price, rolling_high[120 bars])
#     → as market trades lower after a stop-out the threshold drops too,
#       allowing significantly faster re-entries vs v2
#   - 5% recovery above decayed reference for re-entry
#   - 3 bar cooldown after stop-out
#
# Run: Rscript backtests/eth-crossoverv3-backtest.R
# ============================================================

source(file.path(dirname(normalizePath(
  ifelse(interactive(), "backtests/eth-crossoverv3-backtest.R",
         commandArgs(trailingOnly = FALSE) |>
           (\(a) a[startsWith(a, "--file=")])() |>
           (\(a) if (length(a)) sub("--file=", "", a) else "backtests/eth-crossoverv3-backtest.R")())
)), "backtest_engine.R"), local = TRUE)

# ── 1. Config ──────────────────────────────────────────────
PAIR             <- "ETH-USD"
TIMEFRAME        <- "6h"
BENCHMARKS       <- c("BTC-USD", "ETH-USD")

V3_THRESHOLD        <- 0.60
V3_SMA_PERIOD       <- 50
V3_RSI_PERIOD       <- 14
V3_RSI_MIN          <- 45
V3_TRAILING_STOP    <- 0.08
V3_REENTRY_PCT      <- 0.05
V3_COOLDOWN_BARS    <- 12    # 12 × 6h bars = 3 days
V3_REENTRY_LOOKBACK <- 80    # 80 × 6h bars ≈ 20 days rolling-high window

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

# ── 3. Build signal on 6h bars ────────────────────────────
close_6h <- raw_6h$close
n_combos <- length(EMA_FAST) * length(EMA_SLOW)

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

# Daily filters applied per-6h-bar using the daily close of that date
daily_filters <- asset_daily %>%
  mutate(
    sma50 = as.numeric(SMA(close, n = V3_SMA_PERIOD)),
    rsi14 = as.numeric(RSI(close, n = V3_RSI_PERIOD))
  ) %>%
  select(date_d, sma50, rsi14, daily_close = close)

raw_6h <- raw_6h %>%
  left_join(daily_filters, by = "date_d") %>%
  mutate(
    prob    = prob_6h,
    sig_raw = ifelse(
      prob >= V3_THRESHOLD & daily_close > sma50 & rsi14 > V3_RSI_MIN,
      "long", "neutral"
    ),
    sig_raw = ifelse(is.na(sig_raw), "neutral", sig_raw)
  )

# 1-bar (6h) lookahead shift
sig_6h_shifted <- c("neutral", head(raw_6h$sig_raw, -1))

# ── 4. Backtest on 6h bars, resample returns to daily ──────
# v3: decaying re-entry reference (reentry_lookback = 6h bars)
ret_6h_v3 <- run_backtest_with_stops(
  signal_vec        = sig_6h_shifted,
  close_vec         = raw_6h$close,
  trailing_stop_pct = V3_TRAILING_STOP,
  reentry_pct       = V3_REENTRY_PCT,
  cooldown_bars     = V3_COOLDOWN_BARS,
  reentry_lookback  = V3_REENTRY_LOOKBACK
)

# v2: fixed re-entry reference (for comparison)
ret_6h_v2 <- run_backtest_with_stops(
  signal_vec        = sig_6h_shifted,
  close_vec         = raw_6h$close,
  trailing_stop_pct = V3_TRAILING_STOP,
  reentry_pct       = V3_REENTRY_PCT,
  cooldown_bars     = V3_COOLDOWN_BARS,
  reentry_lookback  = NULL
)

# Resample 6h bar returns → daily compound return
raw_6h$ret_v3 <- ret_6h_v3
raw_6h$ret_v2 <- ret_6h_v2

daily_strat <- raw_6h %>%
  group_by(date_d) %>%
  summarise(
    ret_v3 = prod(1 + ret_v3) - 1,
    ret_v2 = prod(1 + ret_v2) - 1,
    .groups = "drop"
  ) %>%
  arrange(date_d)

asset_ret  <- calc_daily_returns(asset_daily$close)
bench_rets <- lapply(benchmarks, function(b) calc_daily_returns(b$close))

# Daily signal for chart panel: last 6h bar signal of each day
daily_signal <- raw_6h %>%
  group_by(date_d) %>%
  summarise(sig = last(sig_raw), .groups = "drop") %>%
  arrange(date_d)

# ── 5. Align all series ────────────────────────────────────
series_input <- list(
  "Strategy"           = list(dates = daily_strat$date_d, rets = daily_strat$ret_v3),
  "v2 (fixed reentry)" = list(dates = daily_strat$date_d, rets = daily_strat$ret_v2),
  "BTC"                = list(dates = asset_daily$date_d,  rets = asset_ret),
  "ETH"                = list(dates = benchmarks$ETH$date_d, rets = bench_rets$ETH)
)

aligned   <- align_series(series_input)
dates_vec <- aligned$dates
rets_mat  <- aligned$rets

rets_list <- lapply(colnames(rets_mat), function(n) rets_mat[, n])
names(rets_list) <- colnames(rets_mat)

price_aligned  <- asset_daily$close[asset_daily$date_d %in% dates_vec]
signal_aligned <- daily_signal$sig[daily_signal$date_d %in% dates_vec]

# ── 6. Print parameter summary ─────────────────────────────
cat("\n══════════════════════════════════════════\n")
cat(" ETH crossOverV3 Strategy Parameters\n")
cat("══════════════════════════════════════════\n")
cat(sprintf("  Asset              : %s\n", PAIR))
cat(sprintf("  EMA grid           : fast %d-%d, slow %d-%d (%d combos)\n",
            min(EMA_FAST), max(EMA_FAST), min(EMA_SLOW), max(EMA_SLOW), n_combos))
cat(sprintf("  Threshold          : >= %.0f%% bullish combos\n", V3_THRESHOLD * 100))
cat(sprintf("  Trend filter       : close > SMA(%d)\n", V3_SMA_PERIOD))
cat(sprintf("  RSI guard          : RSI(%d) > %d\n", V3_RSI_PERIOD, V3_RSI_MIN))
cat(sprintf("  Trailing stop      : %.0f%% below rolling peak\n", V3_TRAILING_STOP * 100))
cat(sprintf("  Re-entry ref       : min(stop_price, %d-bar rolling high)\n", V3_REENTRY_LOOKBACK))
cat(sprintf("  Re-entry threshold : ref × (1 + %.0f%%)\n", V3_REENTRY_PCT * 100))
cat(sprintf("  Cooldown           : %d × 6h bars (= %d days)\n", V3_COOLDOWN_BARS, V3_COOLDOWN_BARS %/% 4))
cat(sprintf("  Re-entry lookback  : %d × 6h bars (= %d days rolling high)\n", V3_REENTRY_LOOKBACK, V3_REENTRY_LOOKBACK %/% 4))
cat("══════════════════════════════════════════\n\n")

# ── 7. Build chart ─────────────────────────────────────────
script_dir <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile)),
                       error = function(e) getwd())
out_path <- file.path(script_dir, "backtest_charts",
  sprintf("eth_crossoverv3_%s.png", format(Sys.Date(), "%Y%m%d")))

custom_pal <- c(
  "Strategy"           = "#00E5FF",
  "v2 (fixed reentry)" = "#FFD600",
  "BTC"                = "#F7931A",
  "ETH"                = "#627EEA"
)

metrics <- build_chart(
  dates_vec     = dates_vec,
  rets_list     = rets_list,
  primary_asset = "ETH",
  price_vec     = price_aligned,
  signal_vec    = signal_aligned,
  title         = "ETH-USD EMA Crossover v3 — Decaying Re-entry Reference  [Strategy = v3]",
  subtitle      = sprintf(
    "Period: %s to %s  |  v3: re-entry ref = min(stop_price, %d-bar high) × 1.05  |  vs v2 fixed ref",
    format(min(dates_vec), "%d %b %Y"), format(max(dates_vec), "%d %b %Y"),
    V3_REENTRY_LOOKBACK
  ),
  out_path  = out_path,
  palette   = custom_pal
)

cat("\n========== PERFORMANCE METRICS ==========\n")
print(metrics, row.names = FALSE)
cat(sprintf("\n✅ Chart → %s\n", out_path))
