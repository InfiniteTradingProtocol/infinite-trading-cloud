# ============================================================
# btc-btcstrat-backtest.R
# BTCStrat — BTC-optimised Dual-Mode Strategy
#
# Problem with crossOverV4 on BTC:
#   - Only 43.6% time in market (too conservative)
#   - Triple-lock (EMA 60% + SMA50 + RSI>45) takes 3-6 months
#     to clear after a bear market → misses entire recovery years
#   - 8% trailing stop is too tight for BTC's 15-20% bull corrections
#   - 2019, 2023 missed entirely; 2020, 2024 mostly missed
#
# BTCStrat adjustments:
#   TREND mode:
#     • EMA consensus threshold  : 60% → 50%  (enter trend earlier)
#     • RSI minimum              : 45  → 40   (catch early-trend recovery)
#     • Trailing stop            : 8%  → 14%  (survive BTC bull corrections)
#     • Cooldown                 : 12 bars → 6 bars  (re-enter faster)
#
#   ACCUMULATION mode (more aggressive than v4):
#     • Drawdown threshold       : 35% → 30%  (fire earlier in recovery)
#     • RSI max                  : 35  → 40   (more sensitive)
#     • Bounce required          : 10% → 5%   (lower bar to enter)
#     • High lookback            : 180d → 365d (BTC has longer cycles)
#     • Low lookback             : 90d  → 120d
#     • Trailing stop            : 15%  → 20%  (higher vol in bear)
#
# Run: Rscript backtests/btc-btcstrat-backtest.R
# ============================================================

source(file.path(dirname(normalizePath(
  ifelse(interactive(), "backtests/btc-btcstrat-backtest.R",
         commandArgs(trailingOnly = FALSE) |>
           (\(a) a[startsWith(a, "--file=")])() |>
           (\(a) if (length(a)) sub("--file=", "", a) else "backtests/btc-btcstrat-backtest.R")())
)), "backtest_engine.R"), local = TRUE)

# ── 1. Config ──────────────────────────────────────────────
PAIR       <- "BTC-USD"
TIMEFRAME  <- "6h"
BENCHMARKS <- c("BTC-USD", "ETH-USD")

# Trend signal — more aggressive than v4
BTCS_THRESHOLD     <- 0.50   # was 0.60
BTCS_SMA_PERIOD    <- 50
BTCS_RSI_PERIOD    <- 14
BTCS_RSI_MIN       <- 40     # was 45
BTCS_TRAIL_TREND   <- 0.14   # was 0.08
BTCS_COOLDOWN_BARS <- 6      # was 12 (1.5 days vs 3 days)

# Accumulation signal — tuned for BTC's longer cycles
BTCS_ACCUM_DRAWDOWN   <- 0.30   # was 0.35
BTCS_ACCUM_RSI_MAX    <- 40     # was 35
BTCS_ACCUM_BOUNCE     <- 0.05   # was 0.10
BTCS_ACCUM_HIGH_DAYS  <- 365    # was 180 — BTC cycles are longer
BTCS_ACCUM_LOW_DAYS   <- 120    # was 90
BTCS_TRAIL_ACCUM      <- 0.20   # was 0.15

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

# Daily trend filters — shifted +1 day to prevent look-ahead
daily_filters <- asset_daily %>%
  mutate(
    sma50 = as.numeric(SMA(close, n = BTCS_SMA_PERIOD)),
    rsi14 = as.numeric(RSI(close, n = BTCS_RSI_PERIOD))
  ) %>%
  select(date_d, sma50, rsi14, daily_close = close) %>%
  mutate(date_d = date_d + 1L)   # ← lag fix: use D-1 daily close for day D bars

# ── 4. Build accumulation signal on daily bars ─────────────
n_daily  <- nrow(asset_daily)
close_d  <- asset_daily$close

rolling_high <- sapply(seq_len(n_daily), function(i) {
  max(close_d[max(1, i - BTCS_ACCUM_HIGH_DAYS + 1):i], na.rm = TRUE)
})
rolling_low  <- sapply(seq_len(n_daily), function(i) {
  min(close_d[max(1, i - BTCS_ACCUM_LOW_DAYS + 1):i], na.rm = TRUE)
})
rsi14_d <- as.numeric(RSI(close_d, n = BTCS_RSI_PERIOD))

accum_raw <- ifelse(
  (rolling_high - close_d) / rolling_high >= BTCS_ACCUM_DRAWDOWN &
  rsi14_d < BTCS_ACCUM_RSI_MAX                                    &
  (close_d - rolling_low) / rolling_low >= BTCS_ACCUM_BOUNCE,
  "long", "neutral"
)
accum_raw[is.na(accum_raw)] <- "neutral"

# Shifted +1 day — same look-ahead fix as trend filters
daily_accum <- asset_daily %>%
  mutate(accum_sig = accum_raw) %>%
  select(date_d, accum_sig) %>%
  mutate(date_d = date_d + 1L)   # ← lag fix

# ── 5. Join all signals onto 6h bars ───────────────────────
raw_6h <- raw_6h %>%
  left_join(daily_filters, by = "date_d") %>%
  left_join(daily_accum,   by = "date_d") %>%
  mutate(
    prob      = prob_6h,
    sig_trend = ifelse(
      prob >= BTCS_THRESHOLD & daily_close > sma50 & rsi14 > BTCS_RSI_MIN,
      "long", "neutral"
    ),
    sig_trend = ifelse(is.na(sig_trend), "neutral", sig_trend),
    sig_accum = ifelse(is.na(accum_sig), "neutral", accum_sig)
  )

# 1-bar lookahead shift for both signals
sig_trend_shifted <- c("neutral", head(raw_6h$sig_trend, -1))
sig_accum_shifted <- c("neutral", head(raw_6h$sig_accum, -1))

# ── 6. Run backtests on 6h bars ────────────────────────────
ret_6h_btcs <- run_backtest_v4(
  signal_trend_vec    = sig_trend_shifted,
  signal_accum_vec    = sig_accum_shifted,
  close_vec           = raw_6h$close,
  trailing_stop_trend = BTCS_TRAIL_TREND,
  trailing_stop_accum = BTCS_TRAIL_ACCUM,
  cooldown_bars       = BTCS_COOLDOWN_BARS
)

# v4 original for comparison (with look-ahead fix applied)
V4_THRESHOLD   <- 0.60; V4_RSI_MIN <- 45; V4_TRAIL_TREND <- 0.08
V4_COOLDOWN    <- 12L;  V4_TRAIL_ACCUM <- 0.15

daily_filters_v4 <- asset_daily %>%
  mutate(sma50=as.numeric(SMA(close,50)), rsi14=as.numeric(RSI(close,14))) %>%
  select(date_d, sma50, rsi14, daily_close=close) %>%
  mutate(date_d = date_d + 1L)

accum_raw_v4 <- ifelse(
  (sapply(seq_len(n_daily), function(i) max(close_d[max(1,i-180+1):i])) - close_d) /
    sapply(seq_len(n_daily), function(i) max(close_d[max(1,i-180+1):i])) >= 0.35 &
  rsi14_d < 35 &
  (close_d - sapply(seq_len(n_daily), function(i) min(close_d[max(1,i-90+1):i]))) /
    sapply(seq_len(n_daily), function(i) min(close_d[max(1,i-90+1):i])) >= 0.10,
  "long", "neutral"
)
accum_raw_v4[is.na(accum_raw_v4)] <- "neutral"

daily_accum_v4 <- asset_daily %>%
  mutate(accum_sig = accum_raw_v4) %>%
  select(date_d, accum_sig) %>%
  mutate(date_d = date_d + 1L)

raw_v4 <- fetch_coinbase_candles(PAIR, TIMEFRAME)  # fresh copy
raw_v4 <- raw_v4 %>%
  mutate(prob = prob_6h) %>%
  left_join(daily_filters_v4, by="date_d") %>%
  left_join(daily_accum_v4,   by="date_d") %>%
  mutate(
    sig_trend = ifelse(prob>=V4_THRESHOLD & daily_close>sma50 & rsi14>V4_RSI_MIN,"long","neutral"),
    sig_trend = ifelse(is.na(sig_trend),"neutral",sig_trend),
    sig_accum = ifelse(is.na(accum_sig),"neutral",accum_sig)
  )

ret_6h_v4 <- run_backtest_v4(
  c("neutral", head(raw_v4$sig_trend,-1)),
  c("neutral", head(raw_v4$sig_accum,-1)),
  raw_v4$close, V4_TRAIL_TREND, V4_TRAIL_ACCUM, V4_COOLDOWN
)

# ── 7. Resample to daily ────────────────────────────────────
raw_6h$ret_btcs <- ret_6h_btcs
raw_6h$ret_v4   <- ret_6h_v4

daily_strat <- raw_6h %>%
  group_by(date_d) %>%
  summarise(
    ret_btcs = prod(1 + ret_btcs) - 1,
    ret_v4   = prod(1 + ret_v4)   - 1,
    .groups  = "drop"
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
  "Strategy"   = list(dates = daily_strat$date_d, rets = daily_strat$ret_btcs),
  "v4 (orig)"  = list(dates = daily_strat$date_d, rets = daily_strat$ret_v4),
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
cat(" BTCStrat Parameters\n")
cat("══════════════════════════════════════════\n")
cat(sprintf("  Asset              : %s\n", PAIR))
cat("  --- TREND MODE ---\n")
cat(sprintf("  EMA pairs          : %d combos (%d fast × %d slow)\n",
            n_combos, length(EMA_FAST), length(EMA_SLOW)))
cat(sprintf("  EMA consensus      : %.0f%% (v4: 60%%)\n", BTCS_THRESHOLD*100))
cat(sprintf("  SMA filter         : SMA(%d)\n", BTCS_SMA_PERIOD))
cat(sprintf("  RSI filter         : RSI(%d) > %d (v4: >45)\n", BTCS_RSI_PERIOD, BTCS_RSI_MIN))
cat(sprintf("  Trailing stop      : %.0f%% (v4: 8%%)\n", BTCS_TRAIL_TREND*100))
cat(sprintf("  Cooldown           : %d bars = %.1f days (v4: 12 bars)\n",
            BTCS_COOLDOWN_BARS, BTCS_COOLDOWN_BARS*6/24))
cat("  --- ACCUMULATION MODE ---\n")
cat(sprintf("  Drawdown trigger   : >= %.0f%% below %dd high (v4: 35%%)\n",
            BTCS_ACCUM_DRAWDOWN*100, BTCS_ACCUM_HIGH_DAYS))
cat(sprintf("  RSI trigger        : < %d (v4: <35)\n", BTCS_ACCUM_RSI_MAX))
cat(sprintf("  Bounce required    : >= %.0f%% off %dd low (v4: 10%%)\n",
            BTCS_ACCUM_BOUNCE*100, BTCS_ACCUM_LOW_DAYS))
cat(sprintf("  Trailing stop      : %.0f%% (v4: 15%%)\n", BTCS_TRAIL_ACCUM*100))
cat(sprintf("  Commission         : 0.3%% per side\n"))
cat("══════════════════════════════════════════\n")

# ── 10. Year-by-year breakdown ─────────────────────────────
cat("\n--- Year-by-year: BTCStrat vs v4 vs BTC buy-hold ---\n")
cat(sprintf("  %-6s  %9s  %9s  %9s  %9s\n", "Year", "BTCStrat", "v4(orig)", "BTC", "Gap(BTCS-BTC)"))

ds_yy  <- daily_strat
btc_yy <- data.frame(date_d = asset_daily$date_d, rb = asset_ret)
comb   <- inner_join(ds_yy, btc_yy, by = "date_d")
comb$yr <- format(comb$date_d, "%Y")

for (yr in unique(comb$yr)) {
  d    <- comb[comb$yr == yr, ]
  rbs  <- prod(1 + d$ret_btcs) - 1
  rv4  <- prod(1 + d$ret_v4)   - 1
  rb   <- prod(1 + d$rb)       - 1
  cat(sprintf("  %-6s  %+8.1f%%  %+8.1f%%  %+8.1f%%  %+8.1f%%\n",
              yr, rbs*100, rv4*100, rb*100, (rbs-rb)*100))
}

# Time in market
sig_combined <- ifelse(raw_6h$sig_trend=="long" | raw_6h$sig_accum=="long", "long","neutral")
tim <- mean(sig_combined == "long", na.rm=TRUE) * 100
cat(sprintf("\nTime in market (BTCStrat): %.1f%% (v4 was 43.6%%)\n", tim))

# ── 11. Metrics table ──────────────────────────────────────
metrics <- do.call(cbind, lapply(names(rets_list), function(n)
  calc_metrics(rets_list[[n]], n)))

cat("\n")
print(metrics, row.names = FALSE)

# ── 12. Chart ──────────────────────────────────────────────
chart_file <- "backtests/backtest_charts/BTC_BTCStrat.png"
build_chart(
  dates_vec     = dates_vec,
  rets_list     = rets_list,
  primary_asset = "Strategy",
  price_vec     = price_aligned,
  signal_vec    = signal_aligned,
  title         = "BTCStrat — BTC-Optimised Dual-Mode Strategy",
  subtitle      = "EMA50% | RSI>40 | 14% stop | 6-bar cooldown | accum: 30% dip/RSI<40/5% bounce",
  out_path      = chart_file
)
cat(sprintf("\nChart saved → %s\n", chart_file))
