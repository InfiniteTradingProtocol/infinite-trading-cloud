#!/usr/bin/env Rscript

# ============================================================
# btc_eth_1h_backtest.R
# BTC-USD & ETH-USD 1H Candles Strategy Comparison
#
# Tests all 4 strategies on 1-hour candles (3 years):
#   1. Current  : EMA 4/12 + RSI-4, thresholds 35/65
#   2. Proposed : Parabolic Rider + BB Range Master (EMA 9/21/50)
#   3. Trend Rider : EMA crossover + ATR dynamic stops
#   4. Adaptive : Regime-switching (range → quant, trend → rider)
#
# Benchmarks each against Buy & Hold.
# Run: Rscript backtests/btc_eth_1h_backtest.R
# ============================================================

suppressPackageStartupMessages({
  library(TTR)
  library(quantmod)
  library(httr)
  library(jsonlite)
  library(lubridate)
})

TIMEFRAME   <- "1h"
GRANULARITY <- 3600          # seconds
YEARS_BACK  <- 3
PAIRS       <- c("BTC-USD", "ETH-USD")
DATA_DIR    <- "backtests/data/1h_cache"
dir.create(DATA_DIR, showWarnings = FALSE, recursive = TRUE)

# ── Coinbase paginated fetcher ────────────────────────────────
fetch_1h_candles <- function(pair, years = 3, sleep_secs = 0.4, verbose = TRUE) {
  csv_file <- file.path(DATA_DIR, sprintf("%s_1h_%dyr.csv", gsub("-", "_", pair), years))

  if (file.exists(csv_file)) {
    if (verbose) cat(sprintf("  ✓ Loading cached %s 1h data from CSV...\n", pair))
    df <- read.csv(csv_file, stringsAsFactors = FALSE)
    df$time <- as.POSIXct(df$time, tz = "UTC")
    if (verbose) cat(sprintf("    %d candles | %s → %s\n\n",
        nrow(df), format(min(df$time), "%Y-%m-%d"), format(max(df$time), "%Y-%m-%d")))
    return(df)
  }

  BATCH    <- 300
  base_url <- sprintf("https://api.exchange.coinbase.com/products/%s/candles", pair)
  target   <- ceiling(years * 365.25 * 24)
  batches  <- ceiling(target / BATCH)

  if (verbose) cat(sprintf("  Fetching %s 1h candles (~%d candles in %d batches)...\n",
      pair, target, batches))

  all_candles <- list()
  batch_end   <- as.numeric(Sys.time())
  start_ts    <- batch_end - years * 365.25 * 24 * 3600

  repeat {
    batch_start <- batch_end - BATCH * GRANULARITY
    if (batch_start < start_ts) batch_start <- start_ts

    url <- sprintf(
      "%s?granularity=%d&start=%s&end=%s",
      base_url, GRANULARITY,
      format(as.POSIXct(batch_start, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ"),
      format(as.POSIXct(batch_end,   origin = "1970-01-01", tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")
    )

    resp <- tryCatch(
      GET(url, add_headers("User-Agent" = "infinite-trading-backtest/1.0")),
      error = function(e) NULL
    )

    if (is.null(resp) || status_code(resp) != 200) {
      warning(sprintf("HTTP error for %s batch ending %s", pair,
                      as.Date(as.POSIXct(batch_end, origin = "1970-01-01"))))
      break
    }

    raw <- fromJSON(content(resp, "text", encoding = "UTF-8"))
    if (length(raw) == 0) break

    if (is.matrix(raw) || is.data.frame(raw)) {
      mat <- raw
    } else {
      mat <- do.call(rbind, raw)
    }
    mat <- as.data.frame(mat)
    colnames(mat) <- c("time", "low", "high", "open", "close", "volume")
    mat[] <- lapply(mat, as.numeric)
    all_candles[[length(all_candles) + 1]] <- mat

    total_so_far <- sum(sapply(all_candles, nrow))
    if (verbose) cat(sprintf("\r    Fetched %d / %d candles...", total_so_far, target))

    oldest_ts <- min(mat$time)
    if (oldest_ts <= start_ts || total_so_far >= target) break

    batch_end <- oldest_ts
    Sys.sleep(sleep_secs)
  }

  if (verbose) cat("\n")
  if (length(all_candles) == 0) stop(sprintf("No data for %s", pair))

  df <- do.call(rbind, all_candles)
  df <- df[order(df$time), ]
  df <- df[!duplicated(df$time), ]
  df$time <- as.POSIXct(df$time, origin = "1970-01-01", tz = "UTC")

  write.csv(df, csv_file, row.names = FALSE)
  if (verbose) cat(sprintf("  ✓ %d candles saved → %s\n\n", nrow(df), csv_file))
  df
}

# ── Strategy definitions ──────────────────────────────────────

strategy_current <- function(prices, highs, lows) {
  ema_fast <- EMA(prices, 4)
  ema_slow <- EMA(prices, 12)
  rsi_v    <- RSI(prices, 4)
  n        <- length(prices)
  signals  <- rep(0, n)
  for (i in 30:n) {
    if (anyNA(c(ema_fast[i], ema_slow[i], rsi_v[i]))) next
    if      (ema_fast[i] > ema_slow[i] && rsi_v[i] < 35) signals[i] <-  1
    else if (ema_fast[i] < ema_slow[i] || rsi_v[i] > 65) signals[i] <- -1
  }
  signals
}

strategy_proposed <- function(prices, highs, lows) {
  n        <- length(prices)
  signals  <- rep(0, n)
  ema_fast <- EMA(prices, 9)
  ema_slow <- EMA(prices, 21)
  ema_tr   <- EMA(prices, 50)
  bb       <- BBands(prices, n = 20, sd = 2)
  rsi_v    <- RSI(prices, 14)
  position <- 0; entry_price <- 0; trailing_stop <- 0
  for (i in 55:n) {
    if (anyNA(c(ema_fast[i], ema_slow[i], ema_tr[i], bb[i, "dn"], rsi_v[i]))) next
    price     <- as.numeric(prices[i])
    bull      <- ema_fast[i] > ema_slow[i] && ema_slow[i] > ema_tr[i]
    bb_pct    <- (price - bb[i, "dn"]) / (bb[i, "up"] - bb[i, "dn"])
    if (position == 0 && bull) {
      if (!is.na(bb_pct) && bb_pct > 1.0 && rsi_v[i] < 80) {
        signals[i] <- 1; position <- 1; entry_price <- price
        trailing_stop <- price * 0.88
      } else if (!is.na(bb_pct) && bb_pct < 0.15 && rsi_v[i] < 40) {
        signals[i] <- 1; position <- 1; entry_price <- price
        trailing_stop <- price * 0.93
      }
    } else if (position == 1) {
      new_stop <- price * 0.88
      if (new_stop > trailing_stop) trailing_stop <- new_stop
      profit_pct <- (price - entry_price) / entry_price
      if (price < trailing_stop) {
        signals[i] <- -1; position <- 0
      } else if (!bull) {
        signals[i] <- -1; position <- 0
      } else if (!is.na(bb_pct) && bb_pct > 0.85 && rsi_v[i] > 70 && profit_pct > 0.05) {
        signals[i] <- -1; position <- 0
      }
    }
  }
  signals
}

strategy_crossover <- function(prices, highs, lows) {
  n        <- length(prices)
  signals  <- rep(0, n)
  ema_fast <- EMA(prices, 9)
  ema_slow <- EMA(prices, 21)
  ema_tr   <- EMA(prices, 50)
  rsi_v    <- RSI(prices, 14)
  atr_v    <- ATR(cbind(highs, lows, prices), n = 14)[, "atr"]
  adx_prx  <- abs(ema_fast - ema_slow) / ema_slow * 100
  position <- 0; entry_price <- 0; highest <- 0
  for (i in 55:n) {
    if (anyNA(c(ema_fast[i], ema_slow[i], rsi_v[i], atr_v[i]))) next
    price          <- as.numeric(prices[i])
    trend_strength <- as.numeric(adx_prx[i])
    cur_atr        <- as.numeric(atr_v[i])
    if (position == 0) {
      if (ema_fast[i] > ema_slow[i] && ema_fast[i-1] <= ema_slow[i-1]) {
        signals[i] <- 1; position <- 1; entry_price <- price; highest <- price
      } else if (ema_fast[i] > ema_slow[i] && price > ema_tr[i] && rsi_v[i] < 40) {
        signals[i] <- 1; position <- 1; entry_price <- price; highest <- price
      }
    } else if (position == 1) {
      if (price > highest) highest <- price
      profit_pct  <- (price - entry_price) / entry_price
      is_parabolic <- trend_strength > 3 && profit_pct > 0.15
      stop_loss   <- if (is_parabolic) highest - cur_atr * 4 else highest - cur_atr * 2.5
      if (price < stop_loss) {
        signals[i] <- -1; position <- 0
      } else if (!is_parabolic && ema_fast[i] < ema_slow[i] && ema_fast[i-1] >= ema_slow[i-1]) {
        signals[i] <- -1; position <- 0
      }
    }
  }
  signals
}

strategy_adaptive <- function(prices, highs, lows, regimes) {
  n             <- length(prices)
  signals       <- rep(0, n)
  q_sig         <- strategy_proposed(prices, highs, lows)
  t_sig         <- strategy_crossover(prices, highs, lows)
  ema_fast      <- EMA(prices, 9)
  ema_slow      <- EMA(prices, 21)
  bb            <- BBands(prices, n = 20, sd = 2)
  position      <- 0; entry_strategy <- ""; entry_price <- 0; highest <- 0
  for (i in 55:n) {
    if (anyNA(c(ema_fast[i], bb[i, "dn"]))) next
    price      <- as.numeric(prices[i])
    bb_width   <- (bb[i, "up"] - bb[i, "dn"]) / bb[i, "mavg"]
    tight      <- !is.na(bb_width) && bb_width < 0.08
    uptrend    <- ema_fast[i] > ema_slow[i]
    if (position == 0) {
      if (tight || regimes[i] %in% c("ranging", "choppy")) {
        if (q_sig[i] == 1) { signals[i] <- 1; position <- 1; entry_strategy <- "range"; entry_price <- price; highest <- price }
      } else if (regimes[i] == "trending" || uptrend) {
        if (t_sig[i] == 1) { signals[i] <- 1; position <- 1; entry_strategy <- "trend"; entry_price <- price; highest <- price }
      }
    } else if (position == 1) {
      if (price > highest) highest <- price
      if (entry_strategy == "range" && q_sig[i] == -1) { signals[i] <- -1; position <- 0 }
      else if (entry_strategy == "trend" && t_sig[i] == -1) { signals[i] <- -1; position <- 0 }
    }
  }
  signals
}

detect_regime <- function(prices, lookback = 100) {
  n <- length(prices); regimes <- rep("ranging", n)
  for (i in lookback:n) {
    w      <- prices[(i - lookback + 1):i]
    rng    <- (max(w) - min(w)) / min(w) * 100
    change <- (as.numeric(w[lookback]) - as.numeric(w[1])) / as.numeric(w[1]) * 100
    if      (abs(change) > 15 && rng > 20) regimes[i] <- "trending"
    else if (abs(change) < 10 && rng > 15) regimes[i] <- "choppy"
  }
  regimes
}

backtest <- function(prices, signals, commission = 0.001) {
  n <- length(prices); position <- 0; cash <- 10000; shares <- 0
  equity <- rep(10000, n); trades <- list()
  for (i in 2:n) {
    if (is.na(prices[i])) next
    if (signals[i] == 1 && position <= 0) {
      shares <- cash / as.numeric(prices[i]) * (1 - commission)
      cash <- 0; position <- 1
      trades[[length(trades)+1]] <- list(type="BUY", price=as.numeric(prices[i]), time=index(prices)[i])
    } else if (signals[i] == -1 && position >= 0 && shares > 0) {
      cash <- shares * as.numeric(prices[i]) * (1 - commission)
      shares <- 0; position <- -1
      trades[[length(trades)+1]] <- list(type="SELL", price=as.numeric(prices[i]), time=index(prices)[i])
    }
    equity[i] <- if (shares > 0) shares * as.numeric(prices[i]) else cash
  }
  total_ret <- (equity[n] - 10000) / 10000 * 100
  wins <- 0; total_trades <- 0
  if (length(trades) >= 2) {
    for (i in seq(2, length(trades), by = 2)) {
      if (i <= length(trades)) {
        if (trades[[i]]$price > trades[[i-1]]$price) wins <- wins + 1
        total_trades <- total_trades + 1
      }
    }
  }
  win_rate <- if (total_trades > 0) wins / total_trades * 100 else 0
  # Hourly Sharpe → annualised (√8760 trading hours / year)
  rets   <- diff(log(equity))
  sharpe <- if (sd(rets, na.rm=TRUE) > 0) mean(rets, na.rm=TRUE) / sd(rets, na.rm=TRUE) * sqrt(8760) else 0
  peak   <- cummax(equity); dd <- (equity - peak) / peak * 100; max_dd <- min(dd)
  list(equity=equity, total_return=total_ret, num_trades=length(trades),
       win_rate=win_rate, sharpe=sharpe, max_dd=max_dd)
}

print_results <- function(label, r, bh_ret) {
  cat(sprintf("%-28s  Return: %+8.1f%%  Trades: %4d  Win: %5.1f%%  Sharpe: %5.2f  MaxDD: %6.1f%%\n",
              label, r$total_return, r$num_trades, r$win_rate, r$sharpe, r$max_dd))
}

# ── Main loop over pairs ──────────────────────────────────────

all_results <- list()

for (pair in PAIRS) {
  cat("\n")
  cat(sprintf("============================================================\n"))
  cat(sprintf("  %s  —  1H CANDLES  (%d years)\n", pair, YEARS_BACK))
  cat(sprintf("============================================================\n"))

  df <- fetch_1h_candles(pair, years = YEARS_BACK)

  prices <- xts(df$close,  order.by = df$time)
  highs  <- xts(df$high,   order.by = df$time)
  lows   <- xts(df$low,    order.by = df$time)

  regimes <- detect_regime(prices, lookback = 100)

  cat("  Running strategies...\n")
  s_cur  <- strategy_current(prices, highs, lows)
  s_prop <- strategy_proposed(prices, highs, lows)
  s_xo   <- strategy_crossover(prices, highs, lows)
  s_adap <- strategy_adaptive(prices, highs, lows, regimes)

  r_cur  <- backtest(prices, s_cur)
  r_prop <- backtest(prices, s_prop)
  r_xo   <- backtest(prices, s_xo)
  r_adap <- backtest(prices, s_adap)

  bh_ret <- (as.numeric(prices[length(prices)]) - as.numeric(prices[1])) /
             as.numeric(prices[1]) * 100

  regime_pct <- prop.table(table(regimes)) * 100

  cat(sprintf("\n  Market Regime (1h):  Trending %.1f%%  |  Choppy %.1f%%  |  Ranging %.1f%%\n\n",
      regime_pct["trending"], regime_pct["choppy"], regime_pct["ranging"]))

  cat(sprintf("  %-28s  Return: %+8.1f%%\n", "Buy & Hold", bh_ret))
  print_results("  Current  (EMA 4/12 RSI-4)",      r_cur,  bh_ret)
  print_results("  Proposed (Parabolic+BB)",          r_prop, bh_ret)
  print_results("  Trend Rider (EMA XO + ATR stop)", r_xo,   bh_ret)
  print_results("  Adaptive (Regime switch)",         r_adap, bh_ret)

  # ── Per-year breakdown ─────────────────────────────────────
  cat("\n  --- Year-by-year breakdown (Adaptive vs Buy & Hold) ---\n")
  years_in_data <- unique(year(df$time))
  for (yr in years_in_data) {
    idx   <- which(year(df$time) == yr)
    if (length(idx) < 24) next
    p_yr  <- as.numeric(prices[idx])
    eq_yr <- r_adap$equity[idx]
    bh_yr <- (p_yr[length(p_yr)] - p_yr[1]) / p_yr[1] * 100
    st_yr <- (eq_yr[length(eq_yr)] - eq_yr[1]) / eq_yr[1] * 100
    cat(sprintf("    %d  |  Buy & Hold: %+7.1f%%  |  Adaptive: %+7.1f%%\n",
                yr, bh_yr, st_yr))
  }

  # ── Save equity curves ─────────────────────────────────────
  out_csv <- sprintf("backtests/data/1h_cache/%s_1h_equity.csv", gsub("-", "_", pair))
  eq_df <- data.frame(
    time          = df$time,
    price         = as.numeric(prices),
    buyhold       = as.numeric(prices) / as.numeric(prices[1]) * 10000,
    strategy_cur  = r_cur$equity,
    strategy_prop = r_prop$equity,
    strategy_xo   = r_xo$equity,
    strategy_adap = r_adap$equity
  )
  write.csv(eq_df, out_csv, row.names = FALSE)
  cat(sprintf("\n  ✓ Equity curves saved → %s\n", out_csv))

  # ── PNG chart ──────────────────────────────────────────────
  chart_file <- sprintf("backtests/data/1h_cache/%s_1h_chart.png", gsub("-", "_", pair))
  png(chart_file, width = 1400, height = 800)
  par(mar = c(5, 5, 4, 2), bg = "#0d1117")

  # Normalise to 100
  nm <- function(v) v / v[1] * 100
  dates   <- df$time
  bh_norm <- nm(as.numeric(prices))
  xo_norm <- nm(r_xo$equity)
  ad_norm <- nm(r_adap$equity)

  y_min <- min(c(bh_norm, xo_norm, ad_norm)) * 0.9
  y_max <- max(c(bh_norm, xo_norm, ad_norm)) * 1.05

  plot(dates, bh_norm, type = "l", lwd = 3, col = "#3b82f6",
       ylim = c(y_min, y_max),
       xlab = "Date", ylab = "Portfolio Value (Start = 100)",
       main = sprintf("%s — Strategy Comparison on 1H Candles (%d yrs)", pair, YEARS_BACK),
       col.main = "white", col.lab = "gray80", col.axis = "gray70",
       cex.main = 1.6, cex.lab = 1.2, cex.axis = 1.0, fg = "gray40")
  grid(col = "gray25", lty = 2, lwd = 1)
  lines(dates, xo_norm, col = "#f97316", lwd = 2.5)
  lines(dates, ad_norm, col = "#22c55e", lwd = 2.5, lty = 1)
  abline(h = 100, col = "gray50", lty = 2)

  legend("topleft",
    legend = c(
      sprintf("Buy & Hold  %+.0f%%",  bh_ret),
      sprintf("Trend Rider %+.0f%%  (trades: %d  win: %.0f%%  Sharpe: %.2f)",
              r_xo$total_return, r_xo$num_trades, r_xo$win_rate, r_xo$sharpe),
      sprintf("Adaptive    %+.0f%%  (trades: %d  win: %.0f%%  Sharpe: %.2f)",
              r_adap$total_return, r_adap$num_trades, r_adap$win_rate, r_adap$sharpe)
    ),
    col = c("#3b82f6", "#f97316", "#22c55e"),
    lwd = c(3, 2.5, 2.5),
    cex = 1.1, bg = "#161b22", text.col = "white", box.col = "gray40"
  )
  dev.off()
  cat(sprintf("  ✓ Chart saved      → %s\n", chart_file))

  all_results[[pair]] <- list(
    bh = bh_ret, cur = r_cur, prop = r_prop, xo = r_xo, adap = r_adap,
    regimes = regime_pct
  )
}

# ── Cross-pair summary ────────────────────────────────────────
cat("\n\n============================================================\n")
cat("  CROSS-PAIR SUMMARY  —  1H CANDLES\n")
cat("============================================================\n")
cat(sprintf("  %-30s  %8s  %8s  %8s  %8s\n", "Strategy", "BTC", "ETH", "BTC Sharpe", "ETH Sharpe"))
cat(sprintf("  %-30s  %8s  %8s  %8s  %8s\n", "--------", "---", "---", "----------", "----------"))

strategies <- list(
  "Buy & Hold"              = list(btc = all_results[["BTC-USD"]]$bh,    eth = all_results[["ETH-USD"]]$bh,
                                   btc_s = NA, eth_s = NA),
  "Current (EMA 4/12 RSI4)" = list(btc = all_results[["BTC-USD"]]$cur$total_return,
                                    eth = all_results[["ETH-USD"]]$cur$total_return,
                                    btc_s = all_results[["BTC-USD"]]$cur$sharpe,
                                    eth_s = all_results[["ETH-USD"]]$cur$sharpe),
  "Proposed (Parabolic+BB)" = list(btc = all_results[["BTC-USD"]]$prop$total_return,
                                    eth = all_results[["ETH-USD"]]$prop$total_return,
                                    btc_s = all_results[["BTC-USD"]]$prop$sharpe,
                                    eth_s = all_results[["ETH-USD"]]$prop$sharpe),
  "Trend Rider (EMA+ATR)"   = list(btc = all_results[["BTC-USD"]]$xo$total_return,
                                    eth = all_results[["ETH-USD"]]$xo$total_return,
                                    btc_s = all_results[["BTC-USD"]]$xo$sharpe,
                                    eth_s = all_results[["ETH-USD"]]$xo$sharpe),
  "Adaptive (Regime switch)" = list(btc = all_results[["BTC-USD"]]$adap$total_return,
                                     eth = all_results[["ETH-USD"]]$adap$total_return,
                                     btc_s = all_results[["BTC-USD"]]$adap$sharpe,
                                     eth_s = all_results[["ETH-USD"]]$adap$sharpe)
)

for (nm in names(strategies)) {
  r <- strategies[[nm]]
  cat(sprintf("  %-30s  %+7.1f%%  %+7.1f%%  %8s  %8s\n",
    nm,
    r$btc, r$eth,
    if (is.na(r$btc_s)) "  —   " else sprintf("%.2f", r$btc_s),
    if (is.na(r$eth_s)) "  —   " else sprintf("%.2f", r$eth_s)
  ))
}

cat("\n  ✓ Done.\n\n")
