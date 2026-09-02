#!/usr/bin/env Rscript

# Standalone EMA+RSI Strategy Analysis
# No database dependencies - uses CoinGecko API directly

if (!require("httr", quietly = TRUE)) install.packages("httr", repos="http://cran.rstudio.com/")
if (!require("jsonlite", quietly = TRUE)) install.packages("jsonlite", repos="http://cran.rstudio.com/")
if (!require("TTR", quietly = TRUE)) install.packages("TTR", repos="http://cran.rstudio.com/")

library(httr)
library(jsonlite)
library(TTR)

# Fetch data from CoinGecko
get_coingecko_data <- function(coin_id = "ethereum", days = 90) {
  url <- paste0("https://api.coingecko.com/api/v3/coins/", coin_id, "/ohlc")
  response <- GET(url, query = list(vs_currency = "usd", days = days))
  
  if (status_code(response) != 200) {
    stop(sprintf("API error: %d", status_code(response)))
  }
  
  data <- fromJSON(content(response, "text"))
  colnames(data) <- c("Time", "Open", "High", "Low", "Close")
  
  # Convert to time series
  data <- as.data.frame(data)
  data$Time <- as.POSIXct(data$Time/1000, origin = "1970-01-01", tz = "UTC")
  
  return(data)
}

cat("=== EMA+RSI Strategy Backtest ===\n\n")
cat("Fetching ETH data (90 days)...\n")
data <- get_coingecko_data("ethereum", 90)

close <- as.numeric(data$Close)
n <- length(close)

cat(sprintf("Got %d candles\n", n))
cat(sprintf("Price: $%.2f - $%.2f (Current: $%.2f)\n\n", 
            min(close), max(close), close[n]))

# Buy-and-hold baseline
buy_hold_return <- (close[n] - close[1]) / close[1] * 100

# Test configurations
configs <- list(
  list(name="⚡ Very Fast (3/9, RSI-4)", fast=3, slow=9, rsi=4, rsi_low=40, rsi_high=60),
  list(name="🏃 Current (4/12, RSI-4)", fast=4, slow=12, rsi=4, rsi_low=35, rsi_high=65),
  list(name="🚶 Medium (6/18, RSI-14)", fast=6, slow=18, rsi=14, rsi_low=35, rsi_high=65),
  list(name="🐢 Stable (9/21, RSI-14)", fast=9, slow=21, rsi=14, rsi_low=30, rsi_high=70),
  list(name="📊 Standard (12/26, RSI-14)", fast=12, slow=26, rsi=14, rsi_low=30, rsi_high=70)
)

results <- list()

for (cfg in configs) {
  # Calculate indicators
  ema_fast <- EMA(close, n = cfg$fast)
  ema_slow <- EMA(close, n = cfg$slow)
  rsi <- RSI(close, n = cfg$rsi)
  
  # Normalized signal
  signals <- (ema_fast - ema_slow) / ema_fast
  signals_clean <- na.omit(signals)
  
  median_sig <- median(signals_clean)
  sd_sig <- sd(signals_clean)
  
  trend_buy_thresh <- median_sig + sd_sig/3
  trend_sell_thresh <- median_sig - sd_sig/3
  
  # Simulate trading
  position <- rep(0, n)
  trades <- 0
  entry_price <- 0
  pnl_sum <- 0
  wins <- 0
  losses <- 0
  
  for (i in cfg$slow:n) {
    if (is.na(signals[i]) || is.na(rsi[i])) {
      position[i] <- if(i > 1) position[i-1] else 0
      next
    }
    
    # Trend determination
    if (signals[i] >= trend_buy_thresh) {
      trend <- 1
    } else if (signals[i] <= trend_sell_thresh) {
      trend <- -1
    } else {
      trend <- 0
    }
    
    # Find last RSI extreme
    rsi_lows <- which(!is.na(rsi[1:i]) & rsi[1:i] <= cfg$rsi_low)
    rsi_highs <- which(!is.na(rsi[1:i]) & rsi[1:i] >= cfg$rsi_high)
    
    last_low <- if(length(rsi_lows) > 0) max(rsi_lows) else 0
    last_high <- if(length(rsi_highs) > 0) max(rsi_highs) else 0
    
    if (last_low > 0 && last_high > 0) {
      last_extreme <- if(last_low < last_high) "high" else "low"
    } else if (last_low > 0) {
      last_extreme <- "low"
    } else if (last_high > 0) {
      last_extreme <- "high"
    } else {
      last_extreme <- "unknown"
    }
    
    # Trading logic
    prev_pos <- if(i > 1) position[i-1] else 0
    
    # Entry: trend bullish + RSI oversold recovery
    if (last_extreme == "low" && trend == 1 && prev_pos == 0) {
      position[i] <- 1
      entry_price <- close[i]
      trades <- trades + 1
    } 
    # Exit: trend bearish OR RSI overbought
    else if (prev_pos == 1 && (trend == -1 || last_extreme == "high")) {
      position[i] <- 0
      pnl <- (close[i] - entry_price) / entry_price
      pnl_sum <- pnl_sum + pnl
      if (pnl > 0) wins <- wins + 1 else losses <- losses + 1
    }
    # Hold
    else {
      position[i] <- prev_pos
    }
  }
  
  # Close final position if still open
  if (position[n] == 1 && entry_price > 0) {
    pnl <- (close[n] - entry_price) / entry_price
    pnl_sum <- pnl_sum + pnl
    if (pnl > 0) wins <- wins + 1 else losses <- losses + 1
  }
  
  # Calculate metrics
  long_periods <- sum(position == 1)
  market_exposure <- long_periods / (n - cfg$slow) * 100
  
  completed_trades <- wins + losses
  win_rate <- if(completed_trades > 0) wins / completed_trades * 100 else 0
  avg_pnl <- if(completed_trades > 0) pnl_sum / completed_trades * 100 else 0
  strategy_return <- pnl_sum * 100
  
  results[[cfg$name]] <- list(
    trades = trades,
    completed = completed_trades,
    win_rate = win_rate,
    avg_pnl = avg_pnl,
    total_return = strategy_return,
    market_exposure = market_exposure
  )
}

cat("=== BACKTEST RESULTS ===\n\n")
cat(sprintf("📈 Buy & Hold Return: %.2f%%\n\n", buy_hold_return))

for (name in names(results)) {
  r <- results[[name]]
  cat(sprintf("%s\n", name))
  cat(sprintf("  Trades: %d (Completed: %d)\n", r$trades, r$completed))
  cat(sprintf("  Win Rate: %.1f%%\n", r$win_rate))
  cat(sprintf("  Avg P&L: %.2f%% per trade\n", r$avg_pnl))
  cat(sprintf("  Total Return: %.2f%%\n", r$total_return))
  cat(sprintf("  Market Exposure: %.1f%%\n", r$market_exposure))
  
  # Performance vs buy-hold
  outperformance <- r$total_return - buy_hold_return
  symbol <- if(outperformance > 0) "✅" else "❌"
  cat(sprintf("  %s vs Buy-Hold: %+.2f%%\n\n", symbol, outperformance))
}

cat("=== ANALYSIS & RECOMMENDATIONS ===\n\n")

# Find best performer
best_name <- names(results)[which.max(sapply(results, function(x) x$total_return))]
best <- results[[best_name]]

cat(sprintf("🏆 Best Performer: %s (%.2f%% return)\n\n", best_name, best$total_return))

cat("📋 Key Insights:\n\n")
cat("1. CURRENT STRATEGY (4/12 RSI-4):\n")
cat("   - Ultra-fast parameters = high sensitivity to noise\n")
cat("   - RSI-4 on daily data is EXTREMELY reactive\n")
cat("   - Likely causing overtrading on minor fluctuations\n\n")

cat("2. RECOMMENDED IMPROVEMENTS:\n")
cat("   ✓ Use 9/21 or 12/26 EMAs for smoother trend detection\n")
cat("   ✓ Switch to RSI-14 (industry standard, less whipsaw)\n")
cat("   ✓ Widen RSI bands (30/70) to catch true extremes\n")
cat("   ✓ Add stop-loss/take-profit levels\n")
cat("   ✓ Consider market regime filter (bull vs bear)\n\n")

cat("3. THE OVERTRADING PROBLEM:\n")
cat("   - Fast EMAs (4/12) cross frequently = many signals\n")
cat("   - 5-min check interval + sensitive params = execution every minor move\n")
cat("   - Solution: Longer EMAs OR longer check interval (30-60 min)\n\n")

cat("4. RISK MANAGEMENT MISSING:\n")
cat("   ❌ No stop-loss (can hold through big drawdowns)\n")
cat("   ❌ No position sizing (always 100%)\n")
cat("   ❌ No max drawdown limit\n")
cat("   ✓ Add 5-10% stop-loss per trade\n")
cat("   ✓ Consider scaling in/out (25%-50%-75%-100%)\n\n")

cat("💡 ACTIONABLE FIX:\n")
cat("   Change emaRsi.R parameters to:\n")
cat("   - ema_fast: 9 (instead of 4)\n")
cat("   - ema_slow: 21 (instead of 12)\n")
cat("   - rsi_period: 14 (instead of 4)\n")
cat("   - rsi_low: 30 (instead of 35)\n")
cat("   - rsi_high: 70 (instead of 65)\n")
cat("   - Check interval: 30 minutes (instead of 5)\n\n")

cat("This will reduce false signals while still catching major moves.\n")
