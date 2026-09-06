#!/usr/bin/env Rscript

# Adaptive Strategy Backtest - Standalone Version
# Uses public Coinbase API (no database needed)

library(TTR)
library(quantmod)
library(httr)
library(jsonlite)
library(lubridate)

cat("============================================================\n")
cat("ADAPTIVE STRATEGY BACKTEST\n")
cat("EMA+RSI (Choppy) + EMA Crossover (Trending)\n")
cat("============================================================\n\n")

# Fetch candles from Coinbase Public API
fetch_coinbase_candles <- function(product_id = "ETH-USD", granularity = 21600, start_time = NULL, end_time = NULL) {
  url <- sprintf("https://api.exchange.coinbase.com/products/%s/candles", product_id)
  
  params <- list(granularity = granularity)
  if (!is.null(start_time)) params$start <- format(start_time, "%Y-%m-%dT%H:%M:%S")
  if (!is.null(end_time)) params$end <- format(end_time, "%Y-%m-%dT%H:%M:%S")
  
  tryCatch({
    response <- GET(url, query = params, timeout(30))
    
    if (status_code(response) == 200) {
      data <- content(response, as = "parsed")
      if (length(data) > 0) {
        df <- do.call(rbind, lapply(data, function(x) {
          data.frame(
            time = as.POSIXct(x[[1]], origin = "1970-01-01", tz = "UTC"),
            low = as.numeric(x[[2]]),
            high = as.numeric(x[[3]]),
            open = as.numeric(x[[4]]),
            close = as.numeric(x[[5]]),
            volume = as.numeric(x[[6]])
          )
        }))
        return(df[order(df$time), ])
      }
    }
    return(NULL)
  }, error = function(e) {
    return(NULL)
  })
}

# Check if cached data exists
csv_path <- "backtest_data/eth_usd_6h_10years.csv"

if (file.exists(csv_path)) {
  cat("Loading cached data from CSV...\n")
  df <- read.csv(csv_path)
  df$time <- as.POSIXct(df$time, tz = "UTC")
  cat(sprintf("✓ Loaded %d candles from cache\n", nrow(df)))
  cat(sprintf("Date range: %s to %s\n", min(df$time), max(df$time)))
  cat(sprintf("Period: %.1f years\n\n", as.numeric(difftime(max(df$time), min(df$time), units = "days")) / 365.25))
} else {
  # Fetch 10 years of data
  cat("Fetching 10 years of ETH-USD 6h candles...\n")
  
  all_candles <- list()
  current_end <- Sys.time()
  target_candles <- 365.25 * 10 * 4  # 10 years * 4 candles per day = ~14,610 candles
  batch_size <- 300
  num_batches <- ceiling(target_candles / batch_size)
  
  cat(sprintf("Target: %d candles in %d batches\n\n", target_candles, num_batches))
  
  for (i in 1:num_batches) {
    cat(sprintf("Batch %d/%d... ", i, num_batches))
    
    current_start <- current_end - (batch_size * 21600)
    
    candles <- fetch_coinbase_candles(
      product_id = "ETH-USD",
      granularity = 21600,
      start_time = current_start,
      end_time = current_end
    )
    
    if (!is.null(candles) && nrow(candles) > 0) {
      all_candles[[i]] <- candles
      cat(sprintf("✓ Got %d candles\n", nrow(candles)))
      current_end <- min(candles$time) - 21600
      Sys.sleep(0.5)
    } else {
      cat("✗ Failed\n")
      Sys.sleep(2)
    }
    
    if (sum(sapply(all_candles, nrow)) >= target_candles) break
  }
  
  if (length(all_candles) == 0) {
    stop("Failed to fetch any data")
  }
  
  # Combine all candles
  df <- do.call(rbind, all_candles)
  df <- df[order(df$time), ]
  df <- df[!duplicated(df$time), ]
  
  cat(sprintf("\n✓ Total: %d candles\n", nrow(df)))
  cat(sprintf("Date range: %s to %s\n", min(df$time), max(df$time)))
  cat(sprintf("Period: %.1f years\n\n", as.numeric(difftime(max(df$time), min(df$time), units = "days")) / 365.25))
  
  # Save to CSV for future use
  write.csv(df, csv_path, row.names = FALSE)
  cat(sprintf("✓ Data saved to: %s\n\n", csv_path))
}

# Convert to xts for TTR functions
prices <- xts(df$close, order.by = df$time)
highs <- xts(df$high, order.by = df$time)
lows <- xts(df$low, order.by = df$time)

# Market regime detection
detect_market_regime <- function(prices, lookback = 100) {
  n <- length(prices)
  regimes <- rep("ranging", n)
  
  for (i in lookback:n) {
    window <- prices[(i - lookback + 1):i]
    price_range <- (max(window) - min(window)) / min(window) * 100
    price_change <- (as.numeric(window[lookback]) - as.numeric(window[1])) / as.numeric(window[1]) * 100
    
    if (abs(price_change) > 15 && price_range > 20) {
      regimes[i] <- "trending"
    } else if (abs(price_change) < 10 && price_range > 15) {
      regimes[i] <- "choppy"
    }
  }
  
  return(regimes)
}

regimes <- detect_market_regime(prices, 100)

# Strategy 1: Current EMA+RSI (4/12 RSI-4)
strategy_current <- function(prices, highs, lows) {
  ema_fast <- EMA(prices, 4)
  ema_slow <- EMA(prices, 12)
  rsi <- RSI(prices, 4)
  
  signals <- rep(0, length(prices))
  for (i in 30:length(prices)) {
    if (is.na(ema_fast[i]) || is.na(ema_slow[i]) || is.na(rsi[i])) next
    
    if (ema_fast[i] > ema_slow[i] && rsi[i] < 35) {
      signals[i] <- 1  # Buy
    } else if (ema_fast[i] < ema_slow[i] || rsi[i] > 65) {
      signals[i] <- -1  # Sell
    }
  }
  
  return(signals)
}

# Strategy 2: QUANT SPECIAL - Parabolic Rider + Range Master
strategy_proposed <- function(prices, highs, lows) {
  n <- length(prices)
  signals <- rep(0, n)
  
  # Calculate indicators
  ema_fast <- EMA(prices, 9)
  ema_slow <- EMA(prices, 21)
  ema_trend <- EMA(prices, 50)
  bb <- BBands(prices, n = 20, sd = 2)
  rsi <- RSI(prices, 14)
  
  # Market structure: Higher highs and higher lows = bullish
  hh <- prices > lag(prices, 20)
  
  position <- 0
  entry_price <- 0
  trailing_stop <- 0
  
  for (i in 55:n) {
    if (is.na(ema_fast[i]) || is.na(bb[i, "dn"]) || is.na(rsi[i])) next
    
    price <- as.numeric(prices[i])
    
    # CRITICAL: Only trade in bull market structure
    bull_market <- ema_fast[i] > ema_slow[i] && ema_slow[i] > ema_trend[i]
    
    # Bollinger Band position
    bb_pct <- (price - bb[i, "dn"]) / (bb[i, "up"] - bb[i, "dn"])
    
    if (position == 0 && bull_market) {
      # ENTRY 1: Parabolic breakout (price > upper BB in uptrend)
      if (!is.na(bb_pct) && bb_pct > 1.0 && rsi[i] < 80) {
        signals[i] <- 1
        position <- 1
        entry_price <- price
        trailing_stop <- price * 0.88  # 12% stop
      }
      # ENTRY 2: Buy the dip (lower BB bounce in uptrend)
      else if (!is.na(bb_pct) && bb_pct < 0.15 && rsi[i] < 40) {
        signals[i] <- 1
        position <- 1
        entry_price <- price
        trailing_stop <- price * 0.93  # 7% tight stop
      }
      
    } else if (position == 1) {
      # Update trailing stop (only raise, never lower)
      new_stop <- price * 0.88
      if (new_stop > trailing_stop) {
        trailing_stop <- new_stop
      }
      
      profit_pct <- (price - entry_price) / entry_price
      
      # EXIT 1: Hit trailing stop
      if (price < trailing_stop) {
        signals[i] <- -1
        position <- 0
      }
      # EXIT 2: Bear market structure (all EMAs down)
      else if (!bull_market) {
        signals[i] <- -1
        position <- 0
      }
      # EXIT 3: Take profit in ranging (upper BB + RSI > 70)
      else if (!is.na(bb_pct) && bb_pct > 0.85 && rsi[i] > 70 && profit_pct > 0.05) {
        signals[i] <- -1
        position <- 0
      }
    }
  }
  
  return(signals)
}

# Strategy 3: Improved Trend Rider (Adaptive Stops Based on Volatility)
strategy_crossover <- function(prices, highs, lows) {
  n <- length(prices)
  signals <- rep(0, n)
  
  ema_fast <- EMA(prices, 9)
  ema_slow <- EMA(prices, 21)
  ema_trend <- EMA(prices, 50)
  rsi <- RSI(prices, 14)
  
  # Calculate ATR for volatility-based stops
  atr <- ATR(cbind(highs, lows, prices), n = 14)[, "atr"]
  
  # Measure trend strength
  adx_proxy <- abs(ema_fast - ema_slow) / ema_slow * 100
  
  position <- 0
  entry_price <- 0
  highest_price <- 0
  stop_multiplier <- 2.5  # ATR multiplier for stop
  
  for (i in 55:n) {
    if (is.na(ema_fast[i]) || is.na(ema_slow[i]) || is.na(rsi[i]) || is.na(atr[i])) next
    
    price <- as.numeric(prices[i])
    trend_strength <- as.numeric(adx_proxy[i])
    current_atr <- as.numeric(atr[i])
    
    if (position == 0) {
      # Enter on crossover UP
      if (ema_fast[i] > ema_slow[i] && ema_fast[i-1] <= ema_slow[i-1]) {
        signals[i] <- 1
        position <- 1
        entry_price <- price
        highest_price <- price
      }
      # Also enter on strong pullback in uptrend
      else if (ema_fast[i] > ema_slow[i] && price > ema_trend[i] && rsi[i] < 40) {
        signals[i] <- 1
        position <- 1
        entry_price <- price
        highest_price <- price
      }
      
    } else if (position == 1) {
      # Track highest price for trailing stop
      if (price > highest_price) {
        highest_price <- price
      }
      
      # Calculate profit
      profit_pct <- (price - entry_price) / entry_price
      
      # DYNAMIC STOPS based on market conditions
      is_parabolic <- trend_strength > 3 && profit_pct > 0.15
      
      if (is_parabolic) {
        # In parabolic: Wide ATR-based stop (let it run!)
        stop_loss <- highest_price - (current_atr * 4)  # 4x ATR from peak
      } else {
        # Normal trend: Tighter ATR-based stop
        stop_loss <- highest_price - (current_atr * stop_multiplier)  # 2.5x ATR from peak
      }
      
      # Exit conditions
      if (price < stop_loss) {
        signals[i] <- -1
        position <- 0
      }
      # Also exit on crossover down (but only if not parabolic)
      else if (!is_parabolic && ema_fast[i] < ema_slow[i] && ema_fast[i-1] >= ema_slow[i-1]) {
        signals[i] <- -1
        position <- 0
      }
    }
  }
  
  return(signals)
}

# Strategy 4: ULTIMATE ADAPTIVE - Best of Both Worlds
strategy_adaptive <- function(prices, highs, lows, regimes) {
  n <- length(prices)
  signals <- rep(0, n)
  
  # Get signals from both strategies
  quant_signals <- strategy_proposed(prices, highs, lows)
  trend_signals <- strategy_crossover(prices, highs, lows)
  
  # Enhanced regime detection
  ema_fast <- EMA(prices, 9)
  ema_slow <- EMA(prices, 21)
  bb <- BBands(prices, n = 20, sd = 2)
  
  position <- 0
  entry_strategy <- ""
  entry_price <- 0
  highest_price <- 0
  
  for (i in 55:n) {
    if (is.na(ema_fast[i]) || is.na(bb[i, "dn"])) next
    
    price <- as.numeric(prices[i])
    
    # Calculate current regime characteristics
    bb_width <- (bb[i, "up"] - bb[i, "dn"]) / bb[i, "mavg"]
    is_tight_range <- !is.na(bb_width) && bb_width < 0.08
    is_uptrend <- ema_fast[i] > ema_slow[i]
    
    if (position == 0) {
      # In tight/sideways: Use range-bound strategy (quant)
      if (is_tight_range || regimes[i] %in% c("ranging", "choppy")) {
        if (quant_signals[i] == 1) {
          signals[i] <- 1
          position <- 1
          entry_strategy <- "range"
          entry_price <- price
          highest_price <- price
        }
      }
      # In trending: Use momentum strategy (trend rider)
      else if (regimes[i] == "trending" || is_uptrend) {
        if (trend_signals[i] == 1) {
          signals[i] <- 1
          position <- 1
          entry_strategy <- "trend"
          entry_price <- price
          highest_price <- price
        }
      }
      
    } else if (position == 1) {
      # Track highest
      if (price > highest_price) {
        highest_price <- price
      }
      
      # Exit based on entry strategy
      if (entry_strategy == "range") {
        # Range exit: Quick profit or stop
        if (quant_signals[i] == -1) {
          signals[i] <- -1
          position <- 0
        }
      } else if (entry_strategy == "trend") {
        # Trend exit: Let it run, only exit on trend signals
        if (trend_signals[i] == -1) {
          signals[i] <- -1
          position <- 0
        }
      }
    }
  }
  
  return(signals)
}

# Backtest engine
backtest <- function(prices, signals, commission = 0.001) {
  position <- 0
  cash <- 10000
  shares <- 0
  equity <- rep(10000, length(prices))
  trades <- list()
  
  for (i in 2:length(prices)) {
    if (is.na(prices[i])) next
    
    # Execute signal
    if (signals[i] == 1 && position <= 0) {
      # Buy
      shares <- cash / as.numeric(prices[i]) * (1 - commission)
      cash <- 0
      position <- 1
      trades[[length(trades) + 1]] <- list(
        type = "BUY",
        price = as.numeric(prices[i]),
        time = index(prices)[i],
        shares = shares
      )
    } else if (signals[i] == -1 && position >= 0) {
      # Sell
      if (shares > 0) {
        cash <- shares * as.numeric(prices[i]) * (1 - commission)
        shares <- 0
        position <- -1
        trades[[length(trades) + 1]] <- list(
          type = "SELL",
          price = as.numeric(prices[i]),
          time = index(prices)[i],
          cash = cash
        )
      }
    }
    
    # Calculate equity
    if (shares > 0) {
      equity[i] <- shares * as.numeric(prices[i])
    } else {
      equity[i] <- cash
    }
  }
  
  # Calculate metrics
  total_return <- (equity[length(equity)] - 10000) / 10000 * 100
  
  # Count winning trades
  wins <- 0
  total_trades <- 0
  if (length(trades) >= 2) {
    for (i in seq(2, length(trades), by = 2)) {
      if (i <= length(trades)) {
        buy_price <- trades[[i-1]]$price
        sell_price <- trades[[i]]$price
        if (sell_price > buy_price) wins <- wins + 1
        total_trades <- total_trades + 1
      }
    }
  }
  
  win_rate <- if (total_trades > 0) wins / total_trades * 100 else 0
  
  # Calculate Sharpe ratio
  returns <- diff(log(equity))
  sharpe <- if (sd(returns, na.rm = TRUE) > 0) mean(returns, na.rm = TRUE) / sd(returns, na.rm = TRUE) * sqrt(252) else 0
  
  # Max drawdown
  peak <- cummax(equity)
  drawdown <- (equity - peak) / peak * 100
  max_dd <- min(drawdown)
  
  return(list(
    equity = equity,
    total_return = total_return,
    trades = trades,
    num_trades = length(trades),
    win_rate = win_rate,
    sharpe = sharpe,
    max_dd = max_dd
  ))
}

# Run all strategies
cat("Running backtests...\n\n")

signals_current <- strategy_current(prices, highs, lows)
signals_proposed <- strategy_proposed(prices, highs, lows)
signals_crossover <- strategy_crossover(prices, highs, lows)
signals_adaptive <- strategy_adaptive(prices, highs, lows, regimes)

results_current <- backtest(prices, signals_current)
results_proposed <- backtest(prices, signals_proposed)
results_crossover <- backtest(prices, signals_crossover)
results_adaptive <- backtest(prices, signals_adaptive)

# Buy & Hold
buy_hold_return <- (as.numeric(prices[length(prices)]) - as.numeric(prices[1])) / as.numeric(prices[1]) * 100

# Market regime stats
regime_table <- table(regimes)
regime_pct <- prop.table(regime_table) * 100

cat("============================================================\n")
cat("MARKET REGIME ANALYSIS\n")
cat("============================================================\n")
cat(sprintf("Trending: %.1f%%\n", regime_pct["trending"]))
cat(sprintf("Choppy: %.1f%%\n", regime_pct["choppy"]))
cat(sprintf("Ranging: %.1f%%\n", regime_pct["ranging"]))

cat("\n============================================================\n")
cat("BACKTEST RESULTS\n")
cat("============================================================\n\n")

cat("📈 Buy & Hold:\n")
cat(sprintf("Return: %.2f%%\n\n", buy_hold_return))

cat("🔴 CURRENT (EMA 4/12, RSI-4, 35/65):\n")
cat(sprintf("Return: %.2f%%\n", results_current$total_return))
cat(sprintf("Trades: %d\n", results_current$num_trades))
cat(sprintf("Win Rate: %.1f%%\n", results_current$win_rate))
cat(sprintf("Sharpe: %.2f\n", results_current$sharpe))
cat(sprintf("Max DD: %.2f%%\n", results_current$max_dd))
if (results_current$num_trades > 0) {
  cat("\nFirst 10 trades:\n")
  for (i in 1:min(10, length(results_current$trades))) {
    trade <- results_current$trades[[i]]
    cat(sprintf("  %s at $%.2f on %s\n", trade$type, trade$price, trade$time))
  }
}
cat("\n")

cat("🟢 QUANT SPECIAL (Parabolic Rider + Range Master):\n")
cat(sprintf("Return: %.2f%%\n", results_proposed$total_return))
cat(sprintf("Trades: %d\n", results_proposed$num_trades))
cat(sprintf("Win Rate: %.1f%%\n", results_proposed$win_rate))
cat(sprintf("Sharpe: %.2f\n", results_proposed$sharpe))
cat(sprintf("Max DD: %.2f%%\n", results_proposed$max_dd))
if (results_proposed$num_trades > 0) {
  cat("\nFirst 10 trades:\n")
  for (i in 1:min(10, length(results_proposed$trades))) {
    trade <- results_proposed$trades[[i]]
    cat(sprintf("  %s at $%.2f on %s\n", trade$type, trade$price, trade$time))
  }
} else {
  cat("\n⚠️  NO TRADES\n")
}
cat("\n")

cat("🔵 TREND RIDER (Never Sell Parabolic):\n")
cat(sprintf("Return: %.2f%%\n", results_crossover$total_return))
cat(sprintf("Trades: %d\n", results_crossover$num_trades))
cat(sprintf("Win Rate: %.1f%%\n", results_crossover$win_rate))
cat(sprintf("Sharpe: %.2f\n", results_crossover$sharpe))
cat(sprintf("Max DD: %.2f%%\n", results_crossover$max_dd))
if (results_crossover$num_trades > 0) {
  cat("\nFirst 10 trades:\n")
  for (i in 1:min(10, length(results_crossover$trades))) {
    trade <- results_crossover$trades[[i]]
    cat(sprintf("  %s at $%.2f on %s\n", trade$type, trade$price, trade$time))
  }
}
cat("\n")

cat("⭐ ULTIMATE ADAPTIVE (Best of Both):\n")
cat(sprintf("Return: %.2f%%\n", results_adaptive$total_return))
cat(sprintf("Trades: %d\n", results_adaptive$num_trades))
cat(sprintf("Win Rate: %.1f%%\n", results_adaptive$win_rate))
cat(sprintf("Sharpe: %.2f\n", results_adaptive$sharpe))
cat(sprintf("Max DD: %.2f%%\n", results_adaptive$max_dd))
if (results_adaptive$num_trades > 0) {
  cat("\nFirst 10 trades:\n")
  for (i in 1:min(10, length(results_adaptive$trades))) {
    trade <- results_adaptive$trades[[i]]
    cat(sprintf("  %s at $%.2f on %s\n", trade$type, trade$price, trade$time))
  }
}
cat("\n")

# Determine winner
returns <- c(
  "Current" = results_current$total_return,
  "Proposed" = results_proposed$total_return,
  "Crossover" = results_crossover$total_return,
  "Adaptive" = results_adaptive$total_return,
  "Buy&Hold" = buy_hold_return
)

winner <- names(which.max(returns))

cat("============================================================\n")
cat("WINNER ANALYSIS\n")
cat("============================================================\n")
cat(sprintf("🏆 %s (%.2f%%)\n\n", winner, max(returns)))

if (winner == "Buy&Hold") {
  cat("💡 Buy & Hold dominates - this was a strong trending period.\n")
  cat("   Active trading strategies underperformed passive holding.\n")
  cat("   Consider if trend-following or regime-aware approaches help.\n")
} else if (winner == "Adaptive") {
  cat("✅ Adaptive strategy wins! Regime detection adds value.\n")
  cat("   Switching between EMA+RSI and Crossover works better than single approach.\n")
  cat("   RECOMMENDATION: Deploy adaptive strategy.\n")
} else if (winner == "Crossover") {
  cat("📊 Pure crossover wins - market was primarily trending.\n")
  cat("   EMA+RSI underperformed in trending conditions.\n")
  cat("   Consider deploying crossover or adaptive for trending markets.\n")
} else if (winner == "Proposed") {
  cat("✅ Proposed EMA+RSI parameters (9/21 RSI-14) win!\n")
  cat("   Slower parameters outperform fast (4/12 RSI-4).\n")
  cat("   RECOMMENDATION: Update emaRsi.R with new parameters.\n")
} else {
  cat("⚠️  Current parameters win by avoiding trades.\n")
  cat("   This suggests market conditions don't favor mean reversion.\n")
  cat("   Consider trend-following or waiting for choppier markets.\n")
}

cat("\n============================================================\n")

# Generate performance chart
cat("\nGenerating performance chart...\n")

# Normalize all equity curves to start at 100
normalize <- function(equity) {
  (equity / equity[1]) * 100
}

# Calculate buy & hold equity curve
bh_equity <- as.numeric(prices) / as.numeric(prices[1]) * 10000

# Create time series
dates <- index(prices)

# Plot setup
png("eth_strategy_performance.png", width = 1400, height = 900)
par(mar = c(5, 5, 4, 2), bg = "white")

# Normalize all curves to 100
norm_bh <- normalize(bh_equity)
norm_adaptive <- normalize(results_adaptive$equity)
norm_trend <- normalize(results_crossover$equity)

# Plot
plot(dates, norm_trend, type = "l", lwd = 4, col = "#FF1493", 
     ylim = c(min(c(norm_bh, norm_adaptive, norm_trend)) * 0.9, max(c(norm_bh, norm_adaptive, norm_trend)) * 1.1),
     xlab = "Date", ylab = "Portfolio Value (Starting = 100)",
     main = "Strategy Comparison vs ETH Buy & Hold - 10 Year Backtest",
     cex.main = 1.8, cex.lab = 1.4, cex.axis = 1.2)

# Add grid
grid(col = "gray70", lty = 2, lwd = 1)

# Plot buy & hold and adaptive
lines(dates, norm_bh, col = "#1E90FF", lwd = 4)
lines(dates, norm_adaptive, col = "#FFD700", lwd = 3.5)

# Add horizontal line at 100
abline(h = 100, col = "gray40", lty = 2, lwd = 2)

# Add shaded regions for major market phases (dynamically based on data range)
date_range <- range(dates)
if (min(dates) < as.POSIXct("2018-01-01")) {
  # 2017-2018 Bull run
  rect(as.POSIXct("2017-01-01"), par("usr")[3], as.POSIXct("2018-01-31"), par("usr")[4],
       col = rgb(0, 1, 0, 0.05), border = NA)
  # 2018-2019 Bear
  rect(as.POSIXct("2018-02-01"), par("usr")[3], as.POSIXct("2020-03-01"), par("usr")[4],
       col = rgb(1, 0, 0, 0.05), border = NA)
  # 2020-2021 Bull
  rect(as.POSIXct("2020-03-01"), par("usr")[3], as.POSIXct("2022-01-01"), par("usr")[4],
       col = rgb(0, 1, 0, 0.05), border = NA)
}
# 2022 Bear
rect(as.POSIXct("2022-01-01"), par("usr")[3], as.POSIXct("2022-12-31"), par("usr")[4],
     col = rgb(1, 0, 0, 0.05), border = NA)
# 2023-2026 Recovery
rect(as.POSIXct("2023-01-01"), par("usr")[3], date_range[2], par("usr")[4],
     col = rgb(0, 1, 0, 0.05), border = NA)

# Re-plot lines on top of shading
lines(dates, norm_bh, col = "#1E90FF", lwd = 4)
lines(dates, norm_adaptive, col = "#FFD700", lwd = 3.5)
lines(dates, norm_trend, col = "#FF1493", lwd = 4)

# Legend
legend("topleft", 
       legend = c(
         sprintf("🏆 Trend Rider: +%.0f%%", results_crossover$total_return),
         sprintf("ETH Buy & Hold: +%.0f%%", buy_hold_return),
         sprintf("Adaptive Quant: +%.0f%%", results_adaptive$total_return)
       ),
       col = c("#FF1493", "#1E90FF", "#FFD700"),
       lwd = c(4, 4, 3.5),
       lty = c(1, 1, 1),
       cex = 1.3,
       bg = "white",
       box.lwd = 2)

# Add performance stats box for Trend Rider
text(as.POSIXct("2019-06-01"), max(norm_trend) * 0.3, 
     sprintf("TREND RIDER STATS:\nTrades: %d\nWin Rate: %.1f%%\nSharpe: %.2f\nMax DD: %.1f%%",
             results_crossover$num_trades,
             results_crossover$win_rate,
             results_crossover$sharpe,
             results_crossover$max_dd),
     cex = 1.2, col = "#8B008B", pos = 4, font = 2)

# Add phase labels based on date range
date_range <- range(dates)
years_span <- as.numeric(difftime(date_range[2], date_range[1], units = "days")) / 365.25

if (years_span > 8) {
  text(as.POSIXct("2018-06-01"), max(norm_adaptive) * 1.05, 
       "2018 Bear", cex = 1.1, col = "darkred", font = 2)
  text(as.POSIXct("2021-01-01"), max(norm_adaptive) * 1.05, 
       "2020-21 Bull", cex = 1.1, col = "darkgreen", font = 2)
}
text(as.POSIXct("2022-07-01"), max(norm_adaptive) * 1.05, 
     "2022 Bear", cex = 1.1, col = "darkred", font = 2)
text(as.POSIXct("2024-06-01"), max(norm_adaptive) * 1.05, 
     "2023-26 Recovery", cex = 1.1, col = "darkgreen", font = 2)

dev.off()

cat("✓ Chart saved to: eth_strategy_performance.png\n")

# Save backtest results to CSV
results_df <- data.frame(
  Strategy = c("Current", "Quant Special", "Trend Rider", "Adaptive", "Buy & Hold"),
  Return_Pct = c(results_current$total_return, results_proposed$total_return, 
                 results_crossover$total_return, results_adaptive$total_return, buy_hold_return),
  Num_Trades = c(results_current$num_trades, results_proposed$num_trades,
                 results_crossover$num_trades, results_adaptive$num_trades, 0),
  Win_Rate = c(results_current$win_rate, results_proposed$win_rate,
               results_crossover$win_rate, results_adaptive$win_rate, 0),
  Sharpe = c(results_current$sharpe, results_proposed$sharpe,
             results_crossover$sharpe, results_adaptive$sharpe, 0),
  Max_DD = c(results_current$max_dd, results_proposed$max_dd,
             results_crossover$max_dd, results_adaptive$max_dd, 
             min((bh_equity / cummax(bh_equity) - 1) * 100))
)

results_path <- "backtest_results/strategy_comparison_10years.csv"
write.csv(results_df, results_path, row.names = FALSE)
cat(sprintf("✓ Results saved to: %s\n", results_path))

# Save individual strategy equity curves
equity_df <- data.frame(
  time = index(prices),
  price = as.numeric(prices),
  current_equity = results_current$equity,
  quant_equity = results_proposed$equity,
  trend_equity = results_crossover$equity,
  adaptive_equity = results_adaptive$equity,
  buyhold_equity = bh_equity
)

equity_path <- "backtest_results/equity_curves_10years.csv"
write.csv(equity_df, equity_path, row.names = FALSE)
cat(sprintf("✓ Equity curves saved to: %s\n", equity_path))

cat("\n============================================================\n")
