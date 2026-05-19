# ============================================================
# eth-crossoverv4-backtest.R
# ETH-USD EMA Crossover v4 — Dual-Mode Strategy
#
# Same dual-mode logic as BTC v4 but for ETH-USD.
# Run: Rscript backtests/eth-crossoverv4-backtest.R
# ============================================================

source(file.path(dirname(normalizePath(
  ifelse(interactive(), "backtests/eth-crossoverv4-backtest.R",
         commandArgs(trailingOnly = FALSE) |>
           (\(a) a[startsWith(a, "--file=")])() |>
           (\(a) if (length(a)) sub("--file=", "", a) else "backtests/eth-crossoverv4-backtest.R")())
)), "backtest_engine.R"), local = TRUE)

# ── 1. Config ──────────────────────────────────────────────
PAIR       <- "ETH-USD"
TIMEFRAME  <- "6h"
BENCHMARKS <- c("BTC-USD", "ETH-USD")

V4_THRESHOLD     <- 0.60
V4_SMA_PERIOD    <- 50
V4_RSI_PERIOD    <- 14
V4_RSI_MIN       <- 45
V4_TRAIL_TREND   <- 0.08
V4_COOLDOWN_BARS <- 12

V4_ACCUM_DRAWDOWN  <- 0.35
V4_ACCUM_RSI_MAX   <- 35
V4_ACCUM_BOUNCE    <- 0.10
V4_ACCUM_HIGH_DAYS <- 180
V4_ACCUM_LOW_DAYS  <- 90
V4_TRAIL_ACCUM     <- 0.15

EMA_FAST <- c(9, 10, 11, 12, 13)
EMA_SLOW <- c(29, 30, 31, 32, 33)

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

# ── 3. Build trend signal on 6h bars ───────────────────────
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

daily_filters <- asset_daily %>%
  mutate(
    sma50 = as.numeric(SMA(close, n = V4_SMA_PERIOD)),
    rsi14 = as.numeric(RSI(close, n = V4_RSI_PERIOD))
  ) %>%
  select(date_d, sma50, rsi14, daily_close = close)

# ── 4. Build accumulation signal on daily bars ─────────────
n_daily     <- nrow(asset_daily)
close_d     <- asset_daily$close

rolling_high <- sapply(seq_len(n_daily), function(i)
  max(close_d[max(1, i - V4_ACCUM_HIGH_DAYS + 1):i], na.rm = TRUE))
rolling_low  <- sapply(seq_len(n_daily), function(i)
  min(close_d[max(1, i - V4_ACCUM_LOW_DAYS + 1):i], na.rm = TRUE))
rsi14_d      <- as.numeric(RSI(close_d, n = V4_RSI_PERIOD))

accum_raw <- ifelse(
  (rolling_high - close_d) / rolling_high >= V4_ACCUM_DRAWDOWN &
  rsi14_d < V4_ACCUM_RSI_MAX                                    &
  (close_d - rolling_low) / rolling_low >= V4_ACCUM_BOUNCE,
  "long", "neutral"
)
accum_raw[is.na(accum_raw)] <- "neutral"

daily_accum <- asset_daily %>%
  mutate(accum_sig = accum_raw) %>%
  select(date_d, accum_sig)

# ── 5. Join signals onto 6h bars ───────────────────────────
# Shift daily signals forward by 1 day: intraday bars on day D use day D-1
# confirmed closes, preventing look-ahead bias from same-day daily filters.
daily_filters_lagged <- daily_filters %>% mutate(date_d = date_d + 1L)
daily_accum_lagged   <- daily_accum   %>% mutate(date_d = date_d + 1L)

raw_6h <- raw_6h %>%
  left_join(daily_filters_lagged, by = "date_d") %>%
  left_join(daily_accum_lagged,   by = "date_d") %>%
  mutate(
    prob      = prob_6h,
    sig_trend = ifelse(
      prob >= V4_THRESHOLD & daily_close > sma50 & rsi14 > V4_RSI_MIN,
      "long", "neutral"
    ),
    sig_trend = ifelse(is.na(sig_trend), "neutral", sig_trend),
    sig_accum = ifelse(is.na(accum_sig), "neutral", accum_sig)
  )

sig_trend_shifted <- c("neutral", head(raw_6h$sig_trend, -1))
sig_accum_shifted <- c("neutral", head(raw_6h$sig_accum, -1))

# ── 6. Run backtests on 6h bars ────────────────────────────
ret_6h_v4 <- run_backtest_v4(
  signal_trend_vec    = sig_trend_shifted,
  signal_accum_vec    = sig_accum_shifted,
  close_vec           = raw_6h$close,
  trailing_stop_trend = V4_TRAIL_TREND,
  trailing_stop_accum = V4_TRAIL_ACCUM,
  cooldown_bars       = V4_COOLDOWN_BARS
)

ret_6h_v3 <- run_backtest_with_stops(
  signal_vec        = sig_trend_shifted,
  close_vec         = raw_6h$close,
  trailing_stop_pct = V4_TRAIL_TREND,
  reentry_pct       = 0.05,
  cooldown_bars     = V4_COOLDOWN_BARS,
  reentry_lookback  = 80L
)

# ── 7. Resample to daily ────────────────────────────────────
raw_6h$ret_v4 <- ret_6h_v4
raw_6h$ret_v3 <- ret_6h_v3

daily_strat <- raw_6h %>%
  group_by(date_d) %>%
  summarise(
    ret_v4 = prod(1 + ret_v4) - 1,
    ret_v3 = prod(1 + ret_v3) - 1,
    .groups = "drop"
  ) %>%
  arrange(date_d)

asset_ret  <- calc_daily_returns(asset_daily$close)
bench_rets <- lapply(benchmarks, function(b) calc_daily_returns(b$close))

daily_signal <- raw_6h %>%
  group_by(date_d) %>%
  summarise(
    sig = last(ifelse(sig_trend == "long" | sig_accum == "long", "long", "neutral")),
    .groups = "drop"
  ) %>%
  arrange(date_d)

# ── 8. Align series ─────────────────────────────────────────
series_input <- list(
  "Strategy"   = list(dates = daily_strat$date_d, rets = daily_strat$ret_v4),
  "v3 (trend)" = list(dates = daily_strat$date_d, rets = daily_strat$ret_v3),
  "BTC"        = list(dates = asset_daily$date_d,  rets = asset_ret),
  "ETH"        = list(dates = benchmarks$ETH$date_d, rets = bench_rets$ETH)
)

aligned   <- align_series(series_input)
dates_vec <- aligned$dates
rets_mat  <- aligned$rets

rets_list <- lapply(colnames(rets_mat), function(n) rets_mat[, n])
names(rets_list) <- colnames(rets_mat)

price_aligned  <- asset_daily$close[asset_daily$date_d %in% dates_vec]
signal_aligned <- daily_signal$sig[daily_signal$date_d %in% dates_vec]

# ── 9. Print parameter summary ─────────────────────────────
cat("\n══════════════════════════════════════════\n")
cat(" ETH crossOverV4 Strategy Parameters\n")
cat("══════════════════════════════════════════\n")
cat(sprintf("  Asset              : %s\n", PAIR))
cat("  --- TREND MODE ---\n")
cat(sprintf("  EMA grid           : fast %d-%d, slow %d-%d (%d combos)\n",
            min(EMA_FAST), max(EMA_FAST), min(EMA_SLOW), max(EMA_SLOW), n_combos))
cat(sprintf("  Threshold          : >= %.0f%% bullish combos\n", V4_THRESHOLD * 100))
cat(sprintf("  Trend filter       : close > SMA(%d)\n", V4_SMA_PERIOD))
cat(sprintf("  RSI guard          : RSI(%d) > %d\n", V4_RSI_PERIOD, V4_RSI_MIN))
cat(sprintf("  Trailing stop      : %.0f%%\n", V4_TRAIL_TREND * 100))
cat(sprintf("  Cooldown           : %d × 6h bars (= %d days)\n",
            V4_COOLDOWN_BARS, V4_COOLDOWN_BARS %/% 4))
cat("  --- ACCUMULATION MODE ---\n")
cat(sprintf("  Dip depth          : price >= %.0f%% below %d-day high\n",
            V4_ACCUM_DRAWDOWN * 100, V4_ACCUM_HIGH_DAYS))
cat(sprintf("  Oversold guard     : RSI(%d) < %d\n", V4_RSI_PERIOD, V4_ACCUM_RSI_MAX))
cat(sprintf("  Bounce confirm     : price >= %.0f%% above %d-day low\n",
            V4_ACCUM_BOUNCE * 100, V4_ACCUM_LOW_DAYS))
cat(sprintf("  Trailing stop      : %.0f%% (wider for volatile bottoms)\n",
            V4_TRAIL_ACCUM * 100))
cat("══════════════════════════════════════════\n\n")

# ── 10. Build chart ─────────────────────────────────────────
script_dir <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile)),
                       error = function(e) getwd())
out_path <- file.path(script_dir, "backtest_charts",
  sprintf("eth_crossoverv4_%s.png", format(Sys.Date(), "%Y%m%d")))

custom_pal <- c(
  "Strategy"   = "#00E5FF",
  "v3 (trend)" = "#FFD600",
  "BTC"        = "#F7931A",
  "ETH"        = "#627EEA"
)

metrics <- build_chart(
  dates_vec     = dates_vec,
  rets_list     = rets_list,
  primary_asset = "ETH",
  price_vec     = price_aligned,
  signal_vec    = signal_aligned,
  title         = "ETH-USD EMA Crossover v4 — Dual Mode: Trend + Accumulation",
  subtitle      = sprintf(
    "Period: %s to %s  |  Trend: 60%% EMA+SMA50+RSI>45 (8%% stop)  |  Accum: ≥35%% dip + RSI<35 + 10%% bounce (15%% stop)",
    format(min(dates_vec), "%d %b %Y"), format(max(dates_vec), "%d %b %Y")
  ),
  out_path = out_path,
  palette  = custom_pal
)

cat("\n========== PERFORMANCE METRICS ==========\n")
print(metrics, row.names = FALSE)
cat(sprintf("\n✅ Chart → %s\n", out_path))
