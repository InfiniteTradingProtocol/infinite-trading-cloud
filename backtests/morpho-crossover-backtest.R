# ============================================================
# morpho-crossover-backtest.R
# MORPHO-USD EMA Crossover Ensemble Strategy — Backtest
#
# Strategy logic (mirrors crossOvers.R):
#   - 5×5 EMA grid: fast (9,10,11,12,13) × slow (29,30,31,32,33)
#   - 25 combos vote bullish/bearish each 6H bar
#   - Long  if probability >= 30%
#   - Neutral (cash/USDC) otherwise — no shorting
#
# Run: Rscript backtests/morpho-crossover-backtest.R
# ============================================================

source(file.path(dirname(normalizePath(
  ifelse(interactive(), "backtests/morpho-crossover-backtest.R",
         commandArgs(trailingOnly = FALSE) |>
           (\(a) a[startsWith(a, "--file=")])() |>
           (\(a) if (length(a)) sub("--file=", "", a) else "backtests/morpho-crossover-backtest.R")())
)), "backtest_engine.R"), local = TRUE)

# ── 1. Config ──────────────────────────────────────────────
PAIR           <- "MORPHO-USD"
TIMEFRAME      <- "6h"
BENCHMARKS     <- c("BTC-USD", "ETH-USD")
EMA_FAST       <- c(9, 10, 11, 12, 13)
EMA_SLOW       <- c(29, 30, 31, 32, 33)
LONG_THRESHOLD <- 0.30

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

# ── 3. Signal generation (on 6H closes, no lookahead) ─────
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

prob      <- rowSums(votes) / n_combos
signal_6h <- ifelse(prob >= LONG_THRESHOLD, "long", "neutral")
signal_6h[is.na(prob)] <- "neutral"

raw_6h$signal <- c("neutral", head(signal_6h, -1))

daily_signal <- raw_6h %>%
  group_by(date_d) %>%
  summarise(signal = last(signal), .groups = "drop") %>%
  arrange(date_d)

# ── 4. Return vectors ──────────────────────────────────────
asset_ret       <- calc_daily_returns(asset_daily$close)
day_sig_shifted <- c("neutral", head(daily_signal$signal, -1))
strat_ret       <- run_backtest(day_sig_shifted, asset_ret)

bench_rets  <- lapply(benchmarks, function(b) calc_daily_returns(b$close))
bench_dates <- lapply(benchmarks, function(b) b$date_d)

# ── 5. Align all series ────────────────────────────────────
primary_name <- sub("-USD", "", PAIR)

series_input <- c(
  list(
    Strategy = list(dates = asset_daily$date_d, rets = strat_ret),
    MORPHO   = list(dates = asset_daily$date_d, rets = asset_ret)
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

price_aligned  <- asset_daily$close[asset_daily$date_d %in% dates_vec]
signal_aligned <- daily_signal$signal[daily_signal$date_d %in% dates_vec]

# ── 6. Build chart & print metrics ────────────────────────
script_dir <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile)),
                       error = function(e) getwd())
out_path <- file.path(script_dir, "backtest_charts",
  sprintf("morpho_crossover_%s.png", format(Sys.Date(), "%Y%m%d")))

metrics <- build_chart(
  dates_vec     = dates_vec,
  rets_list     = rets_list,
  primary_asset = primary_name,
  price_vec     = price_aligned,
  signal_vec    = signal_aligned,
  title         = "MORPHO EMA Crossover Ensemble — Backtest",
  subtitle      = sprintf(
    "Period: %s to %s  |  6H candles  |  5x5 EMA grid (fast %d-%d, slow %d-%d)  |  Long if >=%d%% combos bullish",
    format(min(dates_vec), "%d %b %Y"), format(max(dates_vec), "%d %b %Y"),
    min(EMA_FAST), max(EMA_FAST), min(EMA_SLOW), max(EMA_SLOW),
    round(LONG_THRESHOLD * 100)
  ),
  out_path = out_path
)

cat("\n========== PERFORMANCE METRICS ==========\n")
print(metrics, row.names = FALSE)
