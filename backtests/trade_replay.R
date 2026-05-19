source(file.path(dirname(normalizePath(
  ifelse(interactive(), "backtests/trade_replay.R",
         commandArgs(trailingOnly = FALSE) |>
           (\(a) a[startsWith(a, "--file=")])() |>
           (\(a) if (length(a)) sub("--file=", "", a) else "backtests/trade_replay.R")())
)), "backtest_engine.R"), local = TRUE)

library(TTR); library(quantmod)

ema_fast <- c(9,10,11,12,13); ema_slow <- c(29,30,31,32,33)
long_threshold <- 0.60; sma_period <- 50; rsi_period <- 14; rsi_min <- 45
trailing_stop_trend <- 0.08; trailing_stop_accum <- 0.15; cooldown_bars <- 3
accum_drawdown_pct <- 0.35; accum_high_bars <- 180
accum_rsi_max <- 35; accum_bounce_pct <- 0.10; accum_low_bars <- 90

pairs       <- c("BTC-USD", "ETH-USD")
pair_labels <- c("cbBTC-USDC", "cbETH-USDC")

for (pi in 1:2) {
  cat(sprintf("\n══════════════════════════════════\n %s (%s) — last 300 × 6h bars\n══════════════════════════════════\n",
              pair_labels[pi], pairs[pi]))
  raw   <- fetch_coinbase_candles(pairs[pi], "6h", start = format(Sys.Date() - 75, "%Y-%m-%d"))
  raw$time <- as.POSIXct(raw$time, tz = "UTC")
  close <- raw$close; n <- length(close)

  n_combos <- length(ema_fast) * length(ema_slow)
  votes <- numeric(n)
  for (f in ema_fast) for (s in ema_slow) {
    ef <- EMA(close, n=f); es <- EMA(close, n=s)
    votes <- votes + ifelse(!is.na(ef) & !is.na(es) & ef > es, 1, 0)
  }
  prob  <- votes / n_combos
  sma50 <- as.numeric(SMA(close, n=sma_period))
  rsi14 <- as.numeric(RSI(close, n=rsi_period))
  rolling_high <- sapply(seq_len(n), function(i) max(close[max(1,i-accum_high_bars+1):i]))
  rolling_low  <- sapply(seq_len(n), function(i) min(close[max(1,i-accum_low_bars+1):i]))
  dip    <- (rolling_high - close) / rolling_high
  bounce <- (close - rolling_low) / rolling_low

  sig_trend <- ifelse(prob >= long_threshold & close > sma50 & rsi14 > rsi_min, "long", "neutral")
  sig_accum <- ifelse(dip >= accum_drawdown_pct & rsi14 < accum_rsi_max & bounce >= accum_bounce_pct, "long", "neutral")
  sig_trend[is.na(sig_trend)] <- "neutral"; sig_accum[is.na(sig_accum)] <- "neutral"
  sig_trend_s <- c("neutral", head(sig_trend, -1))
  sig_accum_s <- c("neutral", head(sig_accum, -1))

  in_pos <- FALSE; mode <- NA; peak <- NA
  stopped_out <- FALSE; stop_price <- NA; stop_bar_i <- NA; bar_counter <- 0L
  entry_price <- NA; entry_date <- NA
  total_pnl <- 0; n_trades <- 0

  for (i in seq_len(n)) {
    bar_counter <- bar_counter + 1L; price <- close[i]; dt <- raw$time[i]

    if (stopped_out) {
      bs <- bar_counter - stop_bar_i
      if (bs >= cooldown_bars && !is.na(stop_price) && price >= stop_price * 1.05) {
        stopped_out <- FALSE; stop_price <- NA; stop_bar_i <- NA
      }
    }

    if (in_pos) {
      if (is.na(peak) || price > peak) peak <- price
      ts <- if (!is.na(mode) && mode == "accum") trailing_stop_accum else trailing_stop_trend

      exited <- FALSE; exit_reason <- ""
      if (!is.na(peak) && price < peak * (1 - ts)) {
        exit_reason <- sprintf("STOP  [%-5s]", mode)
        if (!is.na(mode) && mode == "trend") { stopped_out <- TRUE; stop_price <- price; stop_bar_i <- bar_counter }
        exited <- TRUE
      } else if (!is.na(mode) && mode == "trend" && sig_trend_s[i] == "neutral") {
        exit_reason <- "EXIT  [trend]"; exited <- TRUE
      } else if (!is.na(mode) && mode == "accum" && sig_trend_s[i] == "long") {
        exit_reason <- "HAND  [accum]"; exited <- TRUE
      }

      if (exited) {
        pnl <- (price / entry_price - 1) * 100
        total_pnl <- total_pnl + pnl; n_trades <- n_trades + 1
        cat(sprintf("  %s  Entry %s @%9.2f  Exit %s @%9.2f  P&L: %+.2f%%\n",
                    exit_reason, format(entry_date, "%b %d %H:%M"), entry_price,
                    format(dt, "%b %d %H:%M"), price, pnl))
        in_pos <- FALSE; peak <- NA; mode <- NA
      }
    }

    if (!in_pos) {
      if (sig_trend_s[i] == "long" && !stopped_out) {
        cat(sprintf("  ENTRY [trend]  %s @ %.2f\n", format(dt, "%b %d %H:%M"), price))
        in_pos <- TRUE; mode <- "trend"; peak <- price; entry_price <- price; entry_date <- dt
      } else if (sig_accum_s[i] == "long") {
        cat(sprintf("  ENTRY [accum]  %s @ %.2f\n", format(dt, "%b %d %H:%M"), price))
        in_pos <- TRUE; mode <- "accum"; peak <- price; entry_price <- price; entry_date <- dt
      }
    }
  }

  if (in_pos) {
    pnl <- (close[n] / entry_price - 1) * 100
    cat(sprintf("  OPEN  [%-5s]  Entry %s @%9.2f  Now %s @%9.2f  Unrealised: %+.2f%%\n",
                mode, format(entry_date, "%b %d %H:%M"), entry_price,
                format(raw$time[n], "%b %d %H:%M"), close[n], pnl))
    n_trades <- n_trades + 1; total_pnl <- total_pnl + pnl
  }

  cat(sprintf("\n  ─── %d closed trades | Cumulative P&L: %+.2f%% ───\n", n_trades, total_pnl))
}
