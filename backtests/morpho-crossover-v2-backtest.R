# ============================================================
# morpho-crossover-v2-backtest.R
# MORPHO-USD EMA Crossover — Improved Strategy v2
#
# Changes vs v1:
#   1. Higher threshold: 60% of EMA combos must be bullish (was 30%)
#   2. SMA(50) trend filter: only long when daily close > SMA(50)
#   3. RSI(14) momentum guard: only enter when RSI > 45
#   4. Trailing stop: 8% below rolling high while in position
#
# Compares: v2 Strategy vs v1 Strategy vs MORPHO vs BTC vs ETH
#
# Run: Rscript backtests/morpho-crossover-v2-backtest.R
# ============================================================

source(file.path(dirname(normalizePath(
  ifelse(interactive(), "backtests/morpho-crossover-v2-backtest.R",
         commandArgs(trailingOnly = FALSE) |>
           (\(a) a[startsWith(a, "--file=")])() |>
           (\(a) if (length(a)) sub("--file=", "", a) else "backtests/morpho-crossover-v2-backtest.R")())
)), "backtest_engine.R"), local = TRUE)

# ── 1. Config ──────────────────────────────────────────────
PAIR              <- "MORPHO-USD"
TIMEFRAME         <- "6h"
BENCHMARKS        <- c("BTC-USD", "ETH-USD")

# v1 params (for comparison)
V1_THRESHOLD      <- 0.30

# v2 params (improved)
V2_THRESHOLD      <- 0.60   # raised from 30% → only enter on strong consensus
V2_SMA_PERIOD     <- 50     # daily SMA trend filter
V2_RSI_PERIOD     <- 14     # RSI period
V2_RSI_MIN        <- 45     # don't enter below this RSI
V2_TRAILING_STOP  <- 0.08   # 8% trailing stop from rolling peak
V2_REENTRY_PCT    <- 0.05   # price must recover 5% above stop-out price to re-enter
V2_COOLDOWN_BARS  <- 3      # minimum days to wait after stop before re-entry

EMA_FAST          <- c(9, 10, 11, 12, 13)
EMA_SLOW          <- c(29, 30, 31, 32, 33)

# ── 2. Fetch data ──────────────────────────────────────────
cat(sprintf("Fetching %s %s from Coinbase...\n", PAIR, TIMEFRAME))
raw_6h     <- fetch_coinbase_candles(PAIR, TIMEFRAME)
start_date <- as.character(min(raw_6h$date_d))

asset_daily <- resample_to_daily(raw_6h)

benchmarks <- lapply(BENCHMARKS, function(p) {
  cat(sprintf("Fetching %s 1D from Coinbase...\n", p))
  fetch_coinbase_candles(p, "1d", start = start_date)
})
names(benchmarks) <- sub("-USD", "", BENCHMARKS)

# ── 3a. v1 signal (original, 30% threshold, no filters) ───
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

# v1: long if prob >= 30%
sig_v1_6h  <- ifelse(prob_6h >= V1_THRESHOLD, "long", "neutral")
sig_v1_6h[is.na(prob_6h)] <- "neutral"
raw_6h$sig_v1 <- c("neutral", head(sig_v1_6h, -1))

daily_sig_v1 <- raw_6h %>%
  group_by(date_d) %>%
  summarise(signal = last(sig_v1), .groups = "drop") %>%
  arrange(date_d)

# ── 3b. v2 signal (60% threshold + SMA + RSI filters) ─────
# Work on daily closes for the filters
close_daily <- asset_daily$close
sma50       <- SMA(close_daily, n = V2_SMA_PERIOD)
rsi14       <- RSI(close_daily, n = V2_RSI_PERIOD)

# Aggregate 6H probability to daily (last bar of day)
raw_6h$prob <- prob_6h
prob_daily <- raw_6h %>%
  group_by(date_d) %>%
  summarise(prob = last(prob), .groups = "drop") %>%
  arrange(date_d)

# v2 signal: all three conditions must be met
sig_v2_raw <- ifelse(
  prob_daily$prob      >= V2_THRESHOLD &           # 60% EMA consensus
  close_daily          > sma50         &           # above SMA(50) trend
  rsi14                > V2_RSI_MIN,               # RSI > 45 momentum
  "long", "neutral"
)
sig_v2_raw[is.na(sig_v2_raw)] <- "neutral"

# Shift by 1 day — no lookahead
sig_v2_shifted <- c("neutral", head(sig_v2_raw, -1))

# ── 4. Return vectors ──────────────────────────────────────
asset_ret <- calc_daily_returns(asset_daily$close)

# v1 returns (simple signal, no stop)
sig_v1_shifted <- c("neutral", head(daily_sig_v1$signal, -1))
ret_v1 <- run_backtest(sig_v1_shifted, asset_ret)

# v2 returns with trailing stop
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
series_input <- c(
  list(
    "v2 (improved)" = list(dates = asset_daily$date_d, rets = ret_v2),
    "v1 (original)" = list(dates = asset_daily$date_d, rets = ret_v1),
    MORPHO          = list(dates = asset_daily$date_d, rets = asset_ret)
  ),
  setNames(
    mapply(function(r, d) list(dates = d, rets = r),
           bench_rets, bench_dates, SIMPLIFY = FALSE),
    names(benchmarks)
  )
)

aligned   <- align_series(series_input)
dates_vec <- aligned$dates
rets_mat  <- aligned$rets

rets_list <- lapply(colnames(rets_mat), function(n) rets_mat[, n])
names(rets_list) <- colnames(rets_mat)

# For chart: rename "v2 (improved)" as "Strategy" for engine compatibility
rets_chart           <- rets_list
names(rets_chart)[1] <- "Strategy"

# Price & signal for chart (use v2 signal)
price_aligned  <- asset_daily$close[asset_daily$date_d %in% dates_vec]
signal_aligned <- sig_v2_shifted[asset_daily$date_d %in% dates_vec]

# ── 6. Print parameter summary ─────────────────────────────
cat("\n══════════════════════════════════════════\n")
cat(" v2 Strategy Parameters\n")
cat("══════════════════════════════════════════\n")
cat(sprintf("  EMA grid      : fast %d-%d, slow %d-%d (%d combos)\n",
            min(EMA_FAST), max(EMA_FAST), min(EMA_SLOW), max(EMA_SLOW), n_combos))
cat(sprintf("  Threshold     : >= %.0f%% bullish combos (was 30%%)\n", V2_THRESHOLD*100))
cat(sprintf("  Trend filter  : close > SMA(%d)\n", V2_SMA_PERIOD))
cat(sprintf("  RSI guard     : RSI(%d) > %d\n", V2_RSI_PERIOD, V2_RSI_MIN))
cat(sprintf("  Trailing stop : %.0f%% below rolling peak\n", V2_TRAILING_STOP*100))
cat(sprintf("  Re-entry      : price recovers %.0f%% above stop-out + %d bar cooldown\n",
            V2_REENTRY_PCT*100, V2_COOLDOWN_BARS))
cat("══════════════════════════════════════════\n\n")

# ── 7. Build chart ─────────────────────────────────────────
script_dir <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile)),
                       error = function(e) getwd())
out_path <- file.path(script_dir, "backtest_charts",
  sprintf("morpho_crossover_v2_%s.png", format(Sys.Date(), "%Y%m%d")))

custom_pal <- c(
  "Strategy"       = "#00E5FF",
  "v2 (improved)"  = "#00E5FF",
  "v1 (original)"  = "#FFC107",
  "MORPHO"         = "#7C4DFF",
  "BTC"            = "#F7931A",
  "ETH"            = "#627EEA"
)

metrics <- build_chart(
  dates_vec     = dates_vec,
  rets_list     = rets_chart,
  primary_asset = "MORPHO",
  price_vec     = price_aligned,
  signal_vec    = signal_aligned,
  title         = "MORPHO EMA Crossover v2 — Improved Strategy Backtest",
  subtitle      = sprintf(
    "Period: %s to %s  |  v2: 60%% threshold + SMA(50) filter + RSI>45 + 8%% trailing stop  |  vs v1 (30%%, no filters)",
    format(min(dates_vec), "%d %b %Y"), format(max(dates_vec), "%d %b %Y")
  ),
  out_path  = out_path,
  palette   = custom_pal
)

# Print full table including v1 column
full_metrics <- build_metrics_table(rets_list)
names(full_metrics)[names(full_metrics) == "v2 (improved)"] <- "v2"
names(full_metrics)[names(full_metrics) == "v1 (original)"] <- "v1"
cat("\n========== PERFORMANCE METRICS ==========\n")
print(full_metrics, row.names = FALSE)

# Highlight key improvements
v2_dd <- as.numeric(gsub("%","", full_metrics$v2[full_metrics$Metric == "Max Drawdown"]))
v1_dd <- as.numeric(gsub("%","", full_metrics$v1[full_metrics$Metric == "Max Drawdown"]))
mo_dd <- as.numeric(gsub("%","", full_metrics$MORPHO[full_metrics$Metric == "Max Drawdown"]))
cat(sprintf("\n🔵 Drawdown improvement: v1=%s%%  v2=%s%%  MORPHO=%s%%\n",
            v1_dd, v2_dd, mo_dd))

cat(sprintf("\n✅ Chart → %s\n", out_path))
